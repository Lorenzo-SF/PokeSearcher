import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../database/app_database.dart';
import '../../utils/loading_messages.dart';
import '../../utils/media_path_helper.dart';
import '../config/app_config.dart';

/// Servicio para procesar backups CSV y cargar datos en la base de datos
class BackupProcessor {
  final AppDatabase database;
  final AppConfig? appConfig;
  
  // URLs de los ZIPs en GitHub Releases (siempre estas 4 URLs)
  static List<String> _backupZipUrls = [
    'https://github.com/Lorenzo-SF/PokeSearcher/releases/download/1.0.0/poke_searcher_backup_database.zip',
    'https://github.com/Lorenzo-SF/PokeSearcher/releases/download/1.0.0/poke_searcher_backup_media_item.zip',
    'https://github.com/Lorenzo-SF/PokeSearcher/releases/download/1.0.0/poke_searcher_backup_media_pokemon-form.zip',
    'https://github.com/Lorenzo-SF/PokeSearcher/releases/download/1.0.0/poke_searcher_backup_media_pokemon.zip',
  ];
  
  /// Establecer las URLs de los ZIPs del backup
  static void setBackupZipUrls(List<String> urls) {
    _backupZipUrls = urls;
  }
  
  BackupProcessor({
    required this.database,
    this.appConfig,
  });
  
  /// Obtener directorio de datos de la app (donde se guardarán los archivos extraídos)
  Future<Directory> _getAppDataDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory(path.join(appDocDir.path, 'poke_searcher_data'));
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    return dataDir;
  }
  
  /// Buscar la carpeta database en el directorio extraído
  /// Puede estar directamente en dataDir o en una subcarpeta
  Future<Directory?> _findDatabaseDirectory(Directory dataDir) async {
    try {
      // Primero verificar si está directamente en dataDir
      final directDatabaseDir = Directory(path.join(dataDir.path, 'database'));
      if (await directDatabaseDir.exists()) {
        // Verificar que tiene archivos CSV
        try {
          final csvFiles = await directDatabaseDir.list()
            .where((entity) => entity is File && entity.path.endsWith('.csv'))
            .toList();
          if (csvFiles.isNotEmpty) {
            print('[BackupProcessor] ✅ Carpeta database encontrada directamente: ${directDatabaseDir.path} (${csvFiles.length} archivos CSV)');
            return directDatabaseDir;
          }
        } catch (e) {
          print('[BackupProcessor] ⚠️ Error verificando archivos CSV en ${directDatabaseDir.path}: $e');
        }
      }
      
      // Buscar recursivamente la carpeta database
      print('[BackupProcessor] 🔍 Buscando carpeta database recursivamente...');
      Directory? foundDatabaseDir;
      int checkedDirs = 0;
      
      await for (final entity in dataDir.list(recursive: true)) {
        if (entity is Directory && path.basename(entity.path).toLowerCase() == 'database') {
          checkedDirs++;
          // Verificar que tiene archivos CSV
          try {
            final csvFiles = await entity.list()
              .where((e) => e is File && e.path.endsWith('.csv'))
              .toList();
            if (csvFiles.isNotEmpty) {
              print('[BackupProcessor] ✅ Carpeta database encontrada en: ${entity.path} (${csvFiles.length} archivos CSV)');
              foundDatabaseDir = entity;
              break; // Encontrada, salir del bucle
            }
          } catch (e) {
            // Continuar buscando
            continue;
          }
        }
      }
      
      if (foundDatabaseDir != null) {
        return foundDatabaseDir;
      }
      
      print('[BackupProcessor] ⚠️ No se encontró carpeta database con archivos CSV (revisadas $checkedDirs carpetas)');
      
      // Como último recurso, buscar archivos CSV directamente y usar su directorio padre
      print('[BackupProcessor] 🔍 Buscando archivos CSV directamente...');
      File? firstCsvFile;
      await for (final entity in dataDir.list(recursive: true)) {
        if (entity is File && 
            entity.path.endsWith('.csv') && 
            path.basename(entity.path).startsWith('01_')) {
          firstCsvFile = entity;
          print('[BackupProcessor] ✅ Encontrado primer CSV: ${firstCsvFile.path}');
          break;
        }
      }
      
      if (firstCsvFile != null) {
        final csvDir = Directory(path.dirname(firstCsvFile.path));
        print('[BackupProcessor] ✅ Usando directorio del CSV encontrado: ${csvDir.path}');
        return csvDir;
      }
      
      return null;
    } catch (e) {
      print('[BackupProcessor] ⚠️ Error buscando carpeta database: $e');
      return null;
    }
  }
  
  /// Copiar directorio recursivamente
  Future<void> _copyDirectory(Directory source, Directory target) async {
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    
    await for (final entity in source.list()) {
      final targetPath = path.join(target.path, path.basename(entity.path));
      
      if (entity is File) {
        await entity.copy(targetPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(targetPath));
      }
    }
  }
  
  /// Descargar ZIP con reintentos infinitos y manejo de errores
  /// 
  /// Intenta descargar el ZIP indefinidamente con backoff exponencial
  /// entre reintentos hasta que tenga éxito o se encuentre un error no recuperable.
  Future<void> _downloadZipWithRetries({
    required File zipFile,
    required String zipUrl,
    void Function(String message, double progress)? onProgress,
    String? languageCode,
    Duration initialDelay = const Duration(seconds: 2),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;
    Exception? lastError;
    
    while (true) {
      attempt++;
      
      try {
        // Actualizar mensaje de progreso
        if (attempt > 1) {
          final retryMsg = LoadingMessages.getMessageWithParams(
            'retrying_download',
            languageCode,
            {'attempt': attempt.toString(), 'max': '∞'},
          );
          onProgress?.call(retryMsg, 0.05);
          print('[BackupProcessor] 🔄 Reintento $attempt de descarga...');
          
          // Esperar antes de reintentar (backoff exponencial)
          print('[BackupProcessor] ⏳ Esperando ${delay.inSeconds} segundos antes de reintentar...');
          await Future.delayed(delay);
          
          // Aumentar delay para el siguiente intento (backoff exponencial, máximo 60 segundos)
          delay = Duration(seconds: (delay.inSeconds * 2).clamp(2, 60));
        } else {
          onProgress?.call(
            LoadingMessages.getMessage('downloading_backup', languageCode),
            0.05,
          );
          print('[BackupProcessor] 📥 Descargando ZIP desde: $zipUrl (intento $attempt)');
        }
        
        // Crear request con headers apropiados para descargas grandes
        final request = http.Request('GET', Uri.parse(zipUrl));
        request.headers.addAll({
          'User-Agent': 'PokeSearcher/1.0',
          'Accept': '*/*',
          'Accept-Encoding': 'gzip, deflate',
          'Connection': 'keep-alive',
        });
        
        // Crear cliente HTTP para esta descarga
        final client = http.Client();
        http.StreamedResponse? streamedResponse;
        int? contentLength;
        
        try {
          // Enviar request con timeout
          streamedResponse = await client
            .send(request)
            .timeout(
              const Duration(minutes: 30), // Timeout más largo para archivos grandes
              onTimeout: () {
                throw TimeoutException(
                  'La descarga excedió el tiempo máximo de espera (30 minutos)',
                  const Duration(minutes: 30),
                );
              },
            );
          
          // Verificar código de estado
          if (streamedResponse.statusCode != 200) {
            await streamedResponse.stream.drain(); // Limpiar stream
            final httpException = HttpException(
              'Error descargando backup: código de estado ${streamedResponse.statusCode}',
              uri: Uri.parse(zipUrl),
            );
            // Si es 404, no tiene sentido reintentar
            if (streamedResponse.statusCode == 404) {
              print('[BackupProcessor] ❌ Archivo no encontrado (404): $zipUrl');
              throw httpException;
            }
            throw httpException;
          }
          
          // Obtener tamaño total si está disponible
          contentLength = streamedResponse.contentLength;
          if (contentLength != null) {
            print('[BackupProcessor] 📦 Tamaño del archivo: ${(contentLength / 1024 / 1024).toStringAsFixed(2)} MB');
          }
          
          // Descargar usando streaming en chunks para archivos grandes
          final sink = zipFile.openWrite();
          int downloadedBytes = 0;
          const chunkSize = 8192; // 8KB chunks
          
          try {
            await for (final chunk in streamedResponse.stream) {
              sink.add(chunk);
              downloadedBytes += chunk.length;
              
              // Actualizar progreso cada 1MB descargado
              if (downloadedBytes % (1024 * 1024) < chunkSize) {
                if (contentLength != null) {
                  final progress = (downloadedBytes / contentLength).clamp(0.0, 1.0);
                  final progressMsg = 'Descargando... ${(downloadedBytes / 1024 / 1024).toStringAsFixed(2)} MB / ${(contentLength / 1024 / 1024).toStringAsFixed(2)} MB';
                  onProgress?.call(progressMsg, 0.05 + (progress * 0.15)); // 5-20% para descarga
                } else {
                  final progressMsg = 'Descargando... ${(downloadedBytes / 1024 / 1024).toStringAsFixed(2)} MB';
                  onProgress?.call(progressMsg, 0.05); // Progreso fijo si no conocemos el tamaño
                }
              }
            }
            
            await sink.flush();
            await sink.close();
          } catch (e) {
            try {
              await sink.close();
            } catch (_) {}
            // Eliminar archivo parcial
            if (await zipFile.exists()) {
              await zipFile.delete();
            }
            rethrow;
          } finally {
            // Asegurar que el stream se cierre de forma segura
            try {
              await streamedResponse.stream.drain();
            } catch (_) {
              // Ignorar errores al drenar el stream (puede estar ya cerrado)
            }
          }
        } finally {
          // Cerrar cliente HTTP
          client.close();
        }
        
        // Si llegamos aquí sin excepción, la descarga fue exitosa
        // Verificar que el archivo se guardó correctamente
        if (!await zipFile.exists()) {
          throw Exception('Error guardando el archivo ZIP descargado');
        }
        
        final fileSize = await zipFile.length();
        if (fileSize == 0) {
          throw Exception('El archivo ZIP guardado está vacío');
        }
        
        // Verificar que el tamaño coincide si tenemos content-length
        if (contentLength != null && fileSize != contentLength) {
          print('[BackupProcessor] ⚠️ Tamaño del archivo no coincide: esperado $contentLength, obtenido $fileSize');
          // No es crítico, continuar
        }
        
        print('[BackupProcessor] ✅ ZIP descargado correctamente (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB) -> ${zipFile.path}');
        return; // Éxito, salir del bucle y continuar con el proceso
        
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        
        // Limpiar archivo parcial si existe
        try {
          if (await zipFile.exists()) {
            await zipFile.delete();
            print('[BackupProcessor] 🗑️ Archivo parcial eliminado');
          }
        } catch (_) {
          // Ignorar errores al limpiar
        }
        
        // Determinar si es un error recuperable o no
        final isRecoverable = _isRecoverableError(e);
        
        if (!isRecoverable) {
          print('[BackupProcessor] ❌ Error no recuperable: $e');
          throw lastError;
        }
        
        print('[BackupProcessor] ⚠️ Error en intento $attempt: $e');
        // Continuar el bucle para reintentar (sin límite)
      }
    }
  }
  
  /// Determinar si un error es recuperable (se puede reintentar)
  bool _isRecoverableError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    // Errores HTTP 404 (Not Found) NO son recuperables - el archivo no existe
    if (errorString.contains('404') || errorString.contains('not found')) {
      return false;
    }
    
    // Errores HTTP 400, 401, 403 (Bad Request, Unauthorized, Forbidden) NO son recuperables
    if (errorString.contains('400') || 
        errorString.contains('401') || 
        errorString.contains('403')) {
      return false;
    }
    
    // Errores de timeout son recuperables
    if (error is TimeoutException) {
      return true;
    }
    
    // Errores de conexión son recuperables
    if (errorString.contains('connection') ||
        errorString.contains('network') ||
        errorString.contains('socket') ||
        errorString.contains('failed host lookup') ||
        errorString.contains('no internet') ||
        errorString.contains('connection closed')) {
      return true;
    }
    
    // Errores HTTP 429 (rate limit) son recuperables
    if (errorString.contains('429')) {
      return true;
    }
    
    // Errores HTTP 408 (timeout) son recuperables
    if (errorString.contains('408')) {
      return true;
    }
    
    // Errores HTTP 5xx (servidor) son recuperables
    if (errorString.contains('500') ||
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('504')) {
      return true;
    }
    
    // Si es HttpException, verificar el código de estado
    if (error is HttpException) {
      // Ya verificamos 404, 400, 401, 403 arriba
      // Los demás códigos de error HTTP pueden ser recuperables
      return true;
    }
    
    // Errores de formato o validación NO son recuperables
    if (errorString.contains('format') ||
        errorString.contains('invalid') ||
        errorString.contains('parse')) {
      return false;
    }
    
    // Errores de permisos NO son recuperables
    if (errorString.contains('permission') ||
        errorString.contains('access denied')) {
      return false;
    }
    
    // Por defecto, asumir que es recuperable
    return true;
  }
  
  /// Descargar y extraer múltiples ZIPs del backup
  Future<Directory> _downloadAndExtractZips({
    void Function(String message, double progress)? onProgress,
    List<File>? downloadedZipFiles,
  }) async {
    final languageCode = appConfig?.language;
    
    // Verificar si hay URLs configuradas
    if (_backupZipUrls.isEmpty) {
      throw Exception('No se han configurado las URLs de los ZIPs del backup. Use BackupProcessor.setBackupZipUrls() para configurarlas.');
    }
    
    // Verificar si ya está extraído
    final dataDir = await _getAppDataDirectory();
    final databaseDir = Directory(path.join(dataDir.path, 'database'));
    final mediaDir = Directory(path.join(dataDir.path, 'media'));
    
    if (await databaseDir.exists() && await mediaDir.exists()) {
      // Verificar que hay archivos
      final csvFiles = await databaseDir.list()
        .where((e) => e is File && e.path.endsWith('.csv'))
        .toList();
      if (csvFiles.isNotEmpty) {
        print('[BackupProcessor] ✅ Backup ya extraído, usando archivos existentes');
        onProgress?.call(
          LoadingMessages.getMessage('using_existing_data', languageCode),
          0.1,
        );
        return dataDir;
      }
    }
    
    // Limpiar directorio de datos si existe
    if (await dataDir.exists()) {
      await dataDir.delete(recursive: true);
    }
    await dataDir.create(recursive: true);
    
    // Obtener directorio temporal para los ZIPs
    final tempDir = await getTemporaryDirectory();
    
    // Separar URLs de database y media
    final databaseZipUrl = _backupZipUrls.firstWhere(
      (url) => url.contains('database'),
      orElse: () => '',
    );
    final mediaZipUrls = _backupZipUrls.where((url) => url.contains('media')).toList();
    
    print('[BackupProcessor] 📦 Total de ZIPs a procesar: ${_backupZipUrls.length}');
    print('[BackupProcessor]   - Database: ${databaseZipUrl.isNotEmpty ? "1" : "0"}');
    print('[BackupProcessor]   - Media: ${mediaZipUrls.length}');
    
    try {
      // 1. Procesar ZIP de database primero
      if (databaseZipUrl.isNotEmpty) {
        print('[BackupProcessor] 📥 Procesando ZIP de database...');
        onProgress?.call(
          LoadingMessages.getMessage('downloading_backup', languageCode),
          0.05,
        );
        
        final databaseZipFile = File(path.join(tempDir.path, 'poke_searcher_backup_database.zip'));
        
        // Descargar ZIP de database
        await _downloadZipWithRetries(
          zipFile: databaseZipFile,
          onProgress: (message, progress) {
            onProgress?.call(message, 0.05 + (progress * 0.05)); // 5-10% para descarga de database
          },
          languageCode: languageCode,
          zipUrl: databaseZipUrl,
        );
        
        // Extraer ZIP de database
        onProgress?.call(
          LoadingMessages.getMessage('extracting_backup', languageCode),
          0.1,
        );
        await _extractZip(databaseZipFile, dataDir, onProgress: (message, progress) {
          onProgress?.call(message, 0.1 + (progress * 0.05)); // 10-15% para extracción de database
        });
        
        // Guardar ruta del ZIP para borrarlo después de volcar los datos
        if (downloadedZipFiles != null && await databaseZipFile.exists()) {
          downloadedZipFiles.add(databaseZipFile);
        }
      }
      
      // 2. Procesar ZIPs de media
      if (mediaZipUrls.isNotEmpty) {
        print('[BackupProcessor] 📥 Procesando ${mediaZipUrls.length} ZIP(s) de media...');
        
        for (int i = 0; i < mediaZipUrls.length; i++) {
          final mediaZipUrl = mediaZipUrls[i];
          final progressStart = 0.15 + (i / mediaZipUrls.length) * 0.05; // 15-20% para descarga de media
          final progressEnd = 0.15 + ((i + 1) / mediaZipUrls.length) * 0.05;
          
          print('[BackupProcessor] 📥 Procesando ZIP de media ${i + 1}/${mediaZipUrls.length}: $mediaZipUrl');
          onProgress?.call(
            'Descargando media ${i + 1}/${mediaZipUrls.length}...',
            progressStart,
          );
          
          final mediaZipFile = File(path.join(tempDir.path, 'poke_searcher_backup_media_$i.zip'));
          
          // Descargar ZIP de media
          await _downloadZipWithRetries(
            zipFile: mediaZipFile,
            onProgress: (message, progress) {
              onProgress?.call(
                message,
                progressStart + (progress * (progressEnd - progressStart)),
              );
            },
            languageCode: languageCode,
            zipUrl: mediaZipUrl,
          );
          
          // Extraer ZIP de media
          onProgress?.call(
            'Extrayendo media ${i + 1}/${mediaZipUrls.length}...',
            progressEnd * 0.8,
          );
          await _extractZip(mediaZipFile, dataDir, onProgress: (message, progress) {
            onProgress?.call(
              message,
              progressEnd * 0.8 + (progress * (progressEnd * 0.2)),
            );
          });
          
          // Guardar ruta del ZIP para borrarlo después de volcar los datos
          if (downloadedZipFiles != null && await mediaZipFile.exists()) {
            downloadedZipFiles.add(mediaZipFile);
          }
        }
      }
      
      // Reorganizar archivos aplanados si es necesario
      await _reorganizeFlattenedFiles(dataDir);
      
      // Organizar carpetas después de extraer todos los ZIPs
      await _organizeExtractedFolders(dataDir);
      
      // Verificar que los archivos de media existen después de la consolidación
      final finalMediaDir = Directory(path.join(dataDir.path, 'media'));
      print('[BackupProcessor] 🔍 Verificación final de archivos de media...');
      print('[BackupProcessor]   - finalMediaDir: ${finalMediaDir.path}');
      print('[BackupProcessor]   - finalMediaDir existe: ${await finalMediaDir.exists()}');
      
      final pokemonMediaDir = Directory(path.join(finalMediaDir.path, 'pokemon'));
      if (await pokemonMediaDir.exists()) {
        print('[BackupProcessor]   - pokemonMediaDir existe: ${pokemonMediaDir.path}');
        
        // Verificar que existen archivos en pokemon/1/
        final pokemon1Dir = Directory(path.join(pokemonMediaDir.path, '1'));
        if (await pokemon1Dir.exists()) {
          print('[BackupProcessor]   - pokemon/1/ existe');
          int fileCount = 0;
          List<String> fileNames = [];
          await for (final entity in pokemon1Dir.list()) {
            if (entity is File) {
              fileCount++;
              fileNames.add(path.basename(entity.path));
            }
          }
          print('[BackupProcessor]   - pokemon/1/ tiene $fileCount archivos: ${fileNames.join(", ")}');
          
          // Si no hay archivos, intentar buscar en otras ubicaciones y moverlos
          if (fileCount == 0) {
            print('[BackupProcessor]   ⚠️ pokemon/1/ está vacío, buscando archivos en otras ubicaciones...');
            // Buscar archivos de pokemon en cualquier ubicación dentro de dataDir
            await for (final entity in dataDir.list(recursive: true)) {
              if (entity is File) {
                final fileName = path.basename(entity.path);
                final parentDir = Directory(path.dirname(entity.path));
                final parentName = path.basename(parentDir.path);
                
                // Si el archivo está en una carpeta que es un número (ID de pokemon)
                if (RegExp(r'^\d+$').hasMatch(parentName) && 
                    (fileName.contains('sprite') || fileName.contains('artwork') || fileName.contains('cry'))) {
                  // Verificar si está en una ruta que contiene "pokemon"
                  final relativePath = path.relative(entity.path, from: dataDir.path);
                  if (relativePath.contains('pokemon') || 
                      relativePath.contains('media')) {
                    // Construir ruta de destino correcta
                    final pathParts = path.split(relativePath);
                    int pokemonIndex = -1;
                    int idIndex = -1;
                    
                    for (int i = 0; i < pathParts.length; i++) {
                      if (pathParts[i].toLowerCase() == 'pokemon') {
                        pokemonIndex = i;
                      }
                      if (RegExp(r'^\d+$').hasMatch(pathParts[i]) && pokemonIndex >= 0 && i > pokemonIndex) {
                        idIndex = i;
                        break;
                      }
                    }
                    
                    if (pokemonIndex >= 0 && idIndex >= 0) {
                      // Construir ruta de destino: media/pokemon/{id}/{fileName}
                      final targetPath = path.join(
                        finalMediaDir.path,
                        'pokemon',
                        pathParts[idIndex],
                        fileName,
                      );
                      
                      final targetDir = Directory(path.dirname(targetPath));
                      if (!await targetDir.exists()) {
                        await targetDir.create(recursive: true);
                      }
                      
                      final targetFile = File(targetPath);
                      if (!await targetFile.exists()) {
                        await entity.copy(targetPath);
                      }
                    }
                  }
                }
              }
            }
          }
        } else {
          print('[BackupProcessor]   ⚠️ pokemon/1/ no existe');
        }
      } else {
        print('[BackupProcessor]   ⚠️ pokemonMediaDir no existe');
      }
      
      // Verificar también algunos archivos específicos que sabemos que deberían existir
      final testFiles = [
        'pokemon/1/sprite_front_default.svg',
        'pokemon/1/artwork_official.svg',
        'pokemon/4/sprite_front_default.svg',
        'pokemon/7/sprite_front_default.svg',
      ];
      
      print('[BackupProcessor] 🔍 Verificando archivos de prueba:');
      for (final testFile in testFiles) {
        final testPath = path.join(finalMediaDir.path, testFile);
        final testFileObj = File(testPath);
        final exists = await testFileObj.exists();
        print('[BackupProcessor]   ${exists ? "✅" : "❌"} $testFile: ${exists ? "existe" : "NO existe"}');
        if (exists) {
          final size = await testFileObj.length();
          print('[BackupProcessor]      Tamaño: $size bytes');
        }
      }
      
      return dataDir;
    } catch (e) {
      print('[BackupProcessor] ❌ Error procesando ZIPs: $e');
      rethrow;
    }
  }
  
  /// Extraer un ZIP a un directorio de destino
  Future<void> _extractZip(
    File zipFile,
    Directory destDir, {
    void Function(String message, double progress)? onProgress,
  }) async {
    try {
      print('[BackupProcessor] 📦 Extrayendo ZIP: ${path.basename(zipFile.path)}');
      print('[BackupProcessor]   - Destino: ${destDir.path}');
      
      // Intentar extraer usando unzip del sistema (más eficiente para archivos grandes)
      try {
        print('[BackupProcessor] 🔧 Intentando extraer con unzip del sistema...');
        final result = await Process.run(
          'unzip',
          [
            '-o', // Sobrescribir sin preguntar
            '-q', // Modo silencioso
            zipFile.path,
            '-d', // Directorio de destino
            destDir.path,
          ],
          runInShell: false,
        );
        
        if (result.exitCode == 0) {
          print('[BackupProcessor] ✅ Extracción con unzip completada');
          
          // Verificar estructura después de extracción
          print('[BackupProcessor] 🔍 Verificando estructura después de extracción...');
          try {
            final topLevelItems = await destDir.list().toList();
            print('[BackupProcessor]   - Elementos en raíz: ${topLevelItems.length}');
            for (final item in topLevelItems.take(10)) {
              final itemType = item is Directory ? '[DIR]' : '[FILE]';
              print('[BackupProcessor]     $itemType ${path.basename(item.path)}');
            }
            
            // Verificar si hay carpeta media
            final mediaDir = Directory(path.join(destDir.path, 'media'));
            if (await mediaDir.exists()) {
              print('[BackupProcessor]   - Carpeta media encontrada');
              final pokemonDir = Directory(path.join(mediaDir.path, 'pokemon'));
              if (await pokemonDir.exists()) {
                int pokemonCount = 0;
                await for (final entity in pokemonDir.list()) {
                  if (entity is Directory) pokemonCount++;
                }
                print('[BackupProcessor]   - Carpeta pokemon encontrada con $pokemonCount subcarpetas');
              }
            }
          } catch (e) {
            print('[BackupProcessor] ⚠️ Error verificando estructura: $e');
          }
          
          return;
        } else {
          throw Exception('unzip falló: ${result.stderr}');
        }
      } catch (e) {
        print('[BackupProcessor] ⚠️ unzip falló, usando archive package: $e');
        // Fallback: usar archive package
        
        final zipBytes = await zipFile.readAsBytes();
        final archive = await _decodeZipInIsolate(zipBytes);
        
        int extracted = 0;
        final files = archive.whereType<ArchiveFile>().toList();
        final total = files.length;
        const chunkSize = 50;
        
        print('[BackupProcessor] 📦 Extrayendo $total archivos con archive package...');
        
        for (int i = 0; i < files.length; i += chunkSize) {
          final endIndex = (i + chunkSize < files.length) ? i + chunkSize : files.length;
          final chunk = files.sublist(i, endIndex);
          
          for (final file in chunk) {
            if (file.isFile) {
              final filePath = path.join(destDir.path, file.name);
              final fileDir = Directory(path.dirname(filePath));
              if (!await fileDir.exists()) {
                await fileDir.create(recursive: true);
              }
              
              final outFile = File(filePath);
              await outFile.writeAsBytes(file.content as List<int>);
              extracted++;
              
              // Log primeros archivos para ver estructura
              if (extracted <= 5) {
                print('[BackupProcessor]     📄 Extraído: ${file.name} -> $filePath');
              }
            }
          }
          
          await Future.delayed(Duration.zero);
          
          if (extracted % 100 == 0 || extracted == total) {
            onProgress?.call(
              'Extrayendo... ($extracted/$total archivos)',
              extracted / total,
            );
          }
        }
        
        print('[BackupProcessor] ✅ Extracción con archive package completada: $extracted archivos');
      }
    } catch (e) {
      rethrow;
    }
  }
  
  /// Reorganizar archivos que se extrajeron con nombres aplanados
  /// Ejemplo: "mediapokemon1000sprite_front_shiny.png" -> "media/pokemon/1000/sprite_front_shiny.png"
  Future<void> _reorganizeFlattenedFiles(Directory dataDir) async {
    print('[BackupProcessor] 🔄 Reorganizando archivos aplanados...');
    
    try {
      final mediaDir = Directory(path.join(dataDir.path, 'media'));
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }
      
      int reorganizedCount = 0;
      
      // Buscar archivos con nombres aplanados recursivamente en media y también en dataDir
      final searchDirs = [mediaDir, dataDir];
      
      for (final searchDir in searchDirs) {
        if (!await searchDir.exists()) continue;
        
        print('[BackupProcessor]   🔍 Buscando archivos aplanados en: ${searchDir.path}');
        
        await for (final entity in searchDir.list(recursive: true)) {
          if (entity is File) {
            final fileName = path.basename(entity.path);
            
            // Patrón: mediapokemon{id}{filename} o media{item}{id}{filename}, etc.
            // Ejemplo: "mediapokemon1000sprite_front_shiny.png" -> pokemon/1000/sprite_front_shiny.png
            String? mediaType;
            String? entityId;
            String? actualFileName;
            
            // Intentar diferentes patrones
            // 1. mediapokemon{id}{filename}
            var match = RegExp(r'^mediapokemon(\d+)(.+)$', caseSensitive: false).firstMatch(fileName);
            if (match != null) {
              mediaType = 'pokemon';
              entityId = match.group(1);
              actualFileName = match.group(2);
            } else {
              // 2. mediaitem{id}{filename}
              match = RegExp(r'^mediaitem(\d+)(.+)$', caseSensitive: false).firstMatch(fileName);
              if (match != null) {
                mediaType = 'item';
                entityId = match.group(1);
                actualFileName = match.group(2);
              } else {
                // 3. mediapokemon-form{id}{filename} (con guión)
                match = RegExp(r'^mediapokemon-form(\d+)(.+)$', caseSensitive: false).firstMatch(fileName);
                if (match != null) {
                  mediaType = 'pokemon-form';
                  entityId = match.group(1);
                  actualFileName = match.group(2);
                } else {
                  // 4. mediaform{id}{filename}
                  match = RegExp(r'^mediaform(\d+)(.+)$', caseSensitive: false).firstMatch(fileName);
                  if (match != null) {
                    mediaType = 'form';
                    entityId = match.group(1);
                    actualFileName = match.group(2);
                  }
                }
              }
            }
            
            if (mediaType != null && entityId != null && actualFileName != null) {
              // Construir ruta de destino correcta
              final targetDir = Directory(path.join(mediaDir.path, mediaType, entityId));
              if (!await targetDir.exists()) {
                await targetDir.create(recursive: true);
              }
              
              final targetPath = path.join(targetDir.path, actualFileName);
              final targetFile = File(targetPath);
              
              // Solo mover si no existe ya en la ubicación correcta
              if (!await targetFile.exists()) {
                try {
                  // Si el archivo está en otro directorio, usar copy + delete en lugar de rename
                  if (path.dirname(entity.path) != targetDir.path) {
                    await entity.copy(targetPath);
                    await entity.delete();
                  } else {
                    await entity.rename(targetPath);
                  }
                  reorganizedCount++;
                  
                  if (reorganizedCount <= 10) {
                    print('[BackupProcessor]   ✅ Reorganizado: $fileName -> $mediaType/$entityId/$actualFileName');
                  }
                } catch (e) {
                  print('[BackupProcessor]   ⚠️ Error reorganizando $fileName: $e');
                }
              } else {
                // Si ya existe, eliminar el duplicado aplanado
                try {
                  await entity.delete();
                  print('[BackupProcessor]   🗑️ Eliminado duplicado aplanado: $fileName');
                } catch (e) {
                  print('[BackupProcessor]   ⚠️ Error eliminando duplicado $fileName: $e');
                }
              }
            }
          }
        }
      }
      
      if (reorganizedCount > 0) {
        print('[BackupProcessor] ✅ Reorganizados $reorganizedCount archivos aplanados');
      } else {
        print('[BackupProcessor] ℹ️ No se encontraron archivos aplanados para reorganizar');
      }
    } catch (e, stackTrace) {
      print('[BackupProcessor] ⚠️ Error reorganizando archivos aplanados: $e');
      print('[BackupProcessor] StackTrace: $stackTrace');
    }
  }
  
  /// Organizar las carpetas extraídas (database y media) en sus ubicaciones correctas
  Future<void> _organizeExtractedFolders(Directory dataDir) async {
    
    // Buscar la carpeta database real (puede estar en una subcarpeta del ZIP)
    final expectedDatabaseDir = Directory(path.join(dataDir.path, 'database'));
    final expectedMediaDir = Directory(path.join(dataDir.path, 'media'));
    
    // Primero verificar si están directamente en dataDir
    bool databaseFound = await expectedDatabaseDir.exists();
    bool mediaFound = await expectedMediaDir.exists();
    
    // Siempre buscar y consolidar, incluso si ya existen, para asegurar que todos los ZIPs se consolidaron
    
    // Buscar recursivamente las carpetas database y media
    Directory? foundDatabaseDir;
    List<Directory> foundMediaDirs = [];
    
    try {
      await for (final entity in dataDir.list(recursive: true)) {
        if (entity is Directory) {
          final dirName = path.basename(entity.path).toLowerCase();
          
          // Buscar carpeta database
          if (dirName == 'database' && foundDatabaseDir == null) {
            // Verificar que tiene archivos CSV
            try {
              final csvFiles = await entity.list()
                .where((e) => e is File && e.path.endsWith('.csv'))
                .toList();
              if (csvFiles.isNotEmpty) {
                foundDatabaseDir = entity;
              }
            } catch (e) {
              // Continuar buscando
            }
          }
          
          // Buscar carpetas media (puede haber múltiples si vienen de diferentes ZIPs)
          if (dirName == 'media') {
            // Verificar que tiene subcarpetas o archivos
            try {
              final items = await entity.list().toList();
              if (items.isNotEmpty) {
                foundMediaDirs.add(entity);
              }
            } catch (e) {
              // Continuar buscando
            }
          }
        }
      }
    } catch (e) {
      // Error silencioso
    }
    
    // Mover database si está en otra ubicación
    if (foundDatabaseDir != null && foundDatabaseDir.path != expectedDatabaseDir.path) {
      if (await expectedDatabaseDir.exists()) {
        await expectedDatabaseDir.delete(recursive: true);
      }
      await _copyDirectory(foundDatabaseDir, expectedDatabaseDir);
    }
    
    // Consolidar todas las carpetas media encontradas en una sola
    // Crear carpeta media de destino si no existe
    if (!await expectedMediaDir.exists()) {
      await expectedMediaDir.create(recursive: true);
    }
    
    if (foundMediaDirs.isNotEmpty) {
      print('[BackupProcessor] 📦 Consolidando ${foundMediaDirs.length} carpeta(s) media encontrada(s)');
      // Mover/consolidar contenido de cada carpeta media encontrada
      for (int i = 0; i < foundMediaDirs.length; i++) {
        final mediaDir = foundMediaDirs[i];
        print('[BackupProcessor]   📁 Procesando carpeta media ${i + 1}/${foundMediaDirs.length}: ${mediaDir.path}');
        
        // Copiar contenido de la carpeta media encontrada a la carpeta media de destino
        try {
          int filesProcessed = 0;
          int filesCopied = 0;
          int filesSkipped = 0;
          
          // Listar todos los archivos recursivamente
          await for (final entity in mediaDir.list(recursive: true)) {
            // Obtener ruta relativa desde mediaDir
            final relativePath = path.relative(entity.path, from: mediaDir.path);
            
            // Construir ruta de destino
            final targetPath = path.join(expectedMediaDir.path, relativePath);
            
            // Si la ruta de origen y destino son la misma, saltar
            if (entity.path == targetPath) {
              continue;
            }
            
            if (entity is File) {
              filesProcessed++;
              
              // Crear directorio padre si no existe
              final targetDir = Directory(path.dirname(targetPath));
              if (!await targetDir.exists()) {
                await targetDir.create(recursive: true);
              }
              
              // Copiar archivo solo si no existe o es diferente
              final targetFile = File(targetPath);
              bool shouldCopy = true;
              
              if (await targetFile.exists()) {
                // Si ya existe, verificar si es el mismo archivo
                final existingSize = await targetFile.length();
                final sourceSize = await entity.length();
                if (existingSize == sourceSize) {
                  shouldCopy = false; // Ya existe y es igual, saltar
                  filesSkipped++;
                } else {
                  // Reemplazar si es diferente
                  await targetFile.delete();
                }
              }
              
              if (shouldCopy) {
                await entity.copy(targetPath);
                filesCopied++;
                
                // Log cada 50 archivos para no saturar
                if (filesCopied % 50 == 0) {
                  print('[BackupProcessor]     ✅ Copiados $filesCopied archivos...');
                }
              }
            } else if (entity is Directory) {
              // Crear directorio si no existe
              final targetDir = Directory(targetPath);
              if (!await targetDir.exists()) {
                await targetDir.create(recursive: true);
              }
            }
          }
          
          print('[BackupProcessor]   ✅ Carpeta media ${i + 1} procesada: $filesProcessed archivos procesados, $filesCopied copiados, $filesSkipped omitidos');
        } catch (e, stackTrace) {
          print('[BackupProcessor]   ❌ Error procesando carpeta media ${mediaDir.path}: $e');
          print('[BackupProcessor]   StackTrace: $stackTrace');
        }
      }
      
      // Verificar archivos después de consolidación
      print('[BackupProcessor] 🔍 Verificando archivos después de consolidación...');
      final pokemonMediaDir = Directory(path.join(expectedMediaDir.path, 'pokemon'));
      if (await pokemonMediaDir.exists()) {
        int pokemonDirs = 0;
        int totalFiles = 0;
        await for (final entity in pokemonMediaDir.list()) {
          if (entity is Directory) {
            pokemonDirs++;
            int filesInDir = 0;
            await for (final file in entity.list()) {
              if (file is File) {
                filesInDir++;
                totalFiles++;
              }
            }
            if (filesInDir > 0 && pokemonDirs <= 10) {
              print('[BackupProcessor]   📂 pokemon/${path.basename(entity.path)}: $filesInDir archivos');
            }
          }
        }
        print('[BackupProcessor]   ✅ Total: $pokemonDirs carpetas de pokemon, $totalFiles archivos');
      } else {
        print('[BackupProcessor]   ⚠️ Carpeta pokemon no existe después de consolidación');
      }
    }
    
    // Si no se encontraron carpetas media o media no existe, buscar archivos directamente
    if (foundMediaDirs.isEmpty || !mediaFound) {
      // Como último recurso, buscar archivos de media directamente (imágenes, sonidos)
      try {
        // Crear carpeta media de destino
        if (!await expectedMediaDir.exists()) {
          await expectedMediaDir.create(recursive: true);
        }
        
        await for (final entity in dataDir.list(recursive: true)) {
          if (entity is File) {
            final ext = path.extension(entity.path).toLowerCase();
            if (ext == '.svg' || ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.ogg' || ext == '.mp3') {
              // Intentar determinar la estructura de carpetas
              final relativePath = path.relative(entity.path, from: dataDir.path);
              final pathParts = path.split(relativePath);
              
              // Buscar si hay una carpeta "pokemon", "item", etc. en la ruta
              int mediaTypeIndex = -1;
              
              for (int i = 0; i < pathParts.length; i++) {
                final part = pathParts[i].toLowerCase();
                if (part == 'pokemon' || part == 'item' || part == 'pokemon-form') {
                  mediaTypeIndex = i;
                  break;
                }
              }
              
              if (mediaTypeIndex >= 0 && mediaTypeIndex < pathParts.length - 1) {
                // Construir ruta de destino en media/
                final mediaSubPath = pathParts.sublist(mediaTypeIndex);
                
                // Si el primer elemento ya es "media", saltarlo
                List<String> finalPath = [];
                if (pathParts[0].toLowerCase() == 'media' && mediaTypeIndex > 0) {
                  finalPath = pathParts.sublist(mediaTypeIndex);
                } else {
                  finalPath = mediaSubPath;
                }
                
                final targetPath = path.join(expectedMediaDir.path, finalPath.join(Platform.pathSeparator));
                final targetDir = Directory(path.dirname(targetPath));
                
                if (!await targetDir.exists()) {
                  await targetDir.create(recursive: true);
                }
                
                final targetFile = File(targetPath);
                if (!await targetFile.exists()) {
                  await entity.copy(targetPath);
                } else {
                  // Verificar si el archivo existente es diferente
                  final existingSize = await targetFile.length();
                  final sourceSize = await entity.length();
                  if (existingSize != sourceSize) {
                    // Reemplazar si es diferente
                    await targetFile.delete();
                    await entity.copy(targetPath);
                  }
                }
              } else {
                // Si no encontramos la estructura esperada, intentar inferirla del nombre del archivo
                final fileName = path.basename(entity.path);
                if (fileName.contains('sprite') || fileName.contains('artwork') || fileName.contains('cry')) {
                  // Intentar extraer el ID del pokemon de la ruta
                  for (int i = 0; i < pathParts.length; i++) {
                    final part = pathParts[i];
                    // Si encontramos un número, podría ser el ID del pokemon
                    if (RegExp(r'^\d+$').hasMatch(part)) {
                      final pokemonId = part;
                      // Determinar tipo de archivo
                      String? fileType = 'pokemon';
                      if (fileName.contains('cry')) {
                        fileType = 'pokemon';
                      }
                      
                      final targetPath = path.join(expectedMediaDir.path, fileType, pokemonId, fileName);
                      final targetDir = Directory(path.dirname(targetPath));
                      
                      if (!await targetDir.exists()) {
                        await targetDir.create(recursive: true);
                      }
                      
                      final targetFile = File(targetPath);
                      if (!await targetFile.exists()) {
                        await entity.copy(targetPath);
                      }
                      break;
                    }
                  }
                }
              }
            }
          }
        }
      } catch (e, stackTrace) {
        // Error silencioso
      }
    }
  }
  
  /// Fusionar dos directorios, copiando archivos que no existen en el destino
  Future<void> _mergeDirectories(Directory source, Directory target) async {
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    
    // Listar recursivamente para mantener la estructura completa
    await for (final entity in source.list(recursive: true)) {
      // Obtener ruta relativa desde source
      final relativePath = path.relative(entity.path, from: source.path);
      
      // Construir ruta de destino
      final targetPath = path.join(target.path, relativePath);
      
      if (entity is File) {
        // Crear directorio padre si no existe
        final targetDir = Directory(path.dirname(targetPath));
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
        
        final targetFile = File(targetPath);
        if (!await targetFile.exists()) {
          await entity.copy(targetPath);
        } else {
          // Verificar si el archivo existente es diferente
          final existingSize = await targetFile.length();
          final sourceSize = await entity.length();
          if (existingSize != sourceSize) {
            // Reemplazar si es diferente
            await targetFile.delete();
            await entity.copy(targetPath);
          }
        }
      } else if (entity is Directory) {
        // Crear directorio si no existe
        final targetDir = Directory(targetPath);
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
      }
    }
  }
  
  /// Procesar un backup desde ZIP descargado
  /// 
  /// Descarga el ZIP desde Cloudflare, lo extrae y carga los CSV desde el directorio extraído
  /// Los archivos multimedia se guardan en el directorio de datos de la app
  /// [onProgress] - Callback opcional para reportar progreso
  Future<void> processBackupFromAssets({
    void Function(String message, double progress)? onProgress,
  }) async {
    // Lista de archivos ZIP descargados para borrarlos después de volcar los datos
    final downloadedZipFiles = <File>[];
    
    try {
      final languageCode = appConfig?.language;
      final message = LoadingMessages.getMessage('preparing', languageCode);
      print('[BackupProcessor] Iniciando proceso de backup desde ZIP');
      print('[BackupProcessor] Progreso: 0.0% - $message');
      onProgress?.call(message, 0.0);
      
      // Descargar y extraer ZIPs (0-20% del progreso)
      // Pasar la lista para que guarde las rutas de los ZIPs descargados
      final dataDir = await _downloadAndExtractZips(
        onProgress: onProgress,
        downloadedZipFiles: downloadedZipFiles,
      );
      Directory databaseDir = Directory(path.join(dataDir.path, 'database'));
      
      // Verificar nuevamente la ubicación de database después de la extracción
      // (puede haber sido movida durante la extracción)
      final verifiedDatabaseDir = await _findDatabaseDirectory(dataDir);
      if (verifiedDatabaseDir != null && verifiedDatabaseDir.path != databaseDir.path) {
        print('[BackupProcessor] 📁 Usando carpeta database encontrada: ${verifiedDatabaseDir.path}');
        databaseDir = verifiedDatabaseDir;
      } else if (verifiedDatabaseDir == null) {
        // Si no se encontró database, buscar archivos CSV directamente
        print('[BackupProcessor] ⚠️ No se encontró carpeta database. Buscando archivos CSV en cualquier ubicación...');
        List<File> allCsvFiles = [];
        List<File> csvFilesInDatabase = [];
        Directory? csvDatabaseDir;
        
        try {
          // Primero, buscar TODOS los CSV para ver qué hay
          await for (final entity in dataDir.list(recursive: true)) {
            if (entity is File && entity.path.endsWith('.csv')) {
              allCsvFiles.add(entity);
              
              // Verificar si está en una carpeta "database"
              Directory currentDir = Directory(path.dirname(entity.path));
              Directory? foundDatabaseDir;
              
              while (currentDir.path != dataDir.path && currentDir.path.length > dataDir.path.length) {
                if (path.basename(currentDir.path).toLowerCase() == 'database') {
                  foundDatabaseDir = currentDir;
                  break;
                }
                final parentPath = path.dirname(currentDir.path);
                if (parentPath == currentDir.path) break; // Evitar bucle infinito
                currentDir = Directory(parentPath);
              }
              
              if (foundDatabaseDir != null) {
                csvFilesInDatabase.add(entity);
                if (csvDatabaseDir == null) {
                  csvDatabaseDir = foundDatabaseDir;
                  print('[BackupProcessor] 📁 Carpeta database encontrada desde CSV: ${csvDatabaseDir.path}');
                  print('[BackupProcessor] 📄 Primer CSV encontrado: ${path.basename(entity.path)}');
                }
              }
            }
          }
          
          print('[BackupProcessor] 📊 Total de archivos CSV encontrados: ${allCsvFiles.length}');
          print('[BackupProcessor] 📊 CSV en carpetas "database": ${csvFilesInDatabase.length}');
          
          if (allCsvFiles.isEmpty) {
            // No hay CSV en absoluto - listar estructura para debugging
            print('[BackupProcessor] ⚠️ No se encontraron archivos CSV. Listando estructura del ZIP extraído...');
            int topLevelItemsCount = 0;
            try {
              final topLevelItems = await dataDir.list().toList();
              topLevelItemsCount = topLevelItems.length;
              print('[BackupProcessor] 📂 Elementos en la raíz (primeros 30):');
              for (final item in topLevelItems.take(30)) {
                final itemType = item is Directory ? '[DIR]' : '[FILE]';
                print('[BackupProcessor]   $itemType ${item.path}');
              }
              
              // Buscar si hay alguna carpeta que pueda contener CSV
              print('[BackupProcessor] 🔍 Buscando carpetas que puedan contener CSV...');
              for (final item in topLevelItems) {
                if (item is Directory) {
                  try {
                    final subItems = await item.list().toList();
                    final hasCsv = subItems.any((subItem) => subItem is File && subItem.path.endsWith('.csv'));
                    if (hasCsv) {
                      print('[BackupProcessor] ✅ Carpeta con CSV encontrada: ${item.path}');
                    }
                  } catch (e) {
                    // Ignorar errores al listar
                  }
                }
              }
            } catch (e) {
              print('[BackupProcessor] ⚠️ Error listando estructura: $e');
            }
            
            throw Exception(
              'El ZIP no contiene archivos CSV. '
              'El ZIP extraído tiene $topLevelItemsCount elementos en la raíz, pero no se encontraron archivos CSV. '
              'Verifica que el script de generación del ZIP incluya los archivos CSV en la carpeta "database".'
            );
          }
          
          // Si hay CSV pero no en carpetas "database", usar el directorio del primer CSV
          if (csvFilesInDatabase.isEmpty && allCsvFiles.isNotEmpty) {
            print('[BackupProcessor] ⚠️ CSV encontrados pero no en carpeta "database". Usando ubicación del primer CSV...');
            final firstCsv = allCsvFiles.first;
            csvDatabaseDir = Directory(path.dirname(firstCsv.path));
            print('[BackupProcessor] 📁 Usando directorio del CSV: ${csvDatabaseDir.path}');
            print('[BackupProcessor] 📄 Primer CSV: ${path.basename(firstCsv.path)}');
            csvFilesInDatabase = allCsvFiles; // Usar todos los CSV encontrados
          }
          
          if (csvDatabaseDir != null) {
            databaseDir = csvDatabaseDir;
            print('[BackupProcessor] 📁 Estableciendo databaseDir: ${databaseDir.path}');
          } else {
            throw Exception(
              'No se pudo determinar la ubicación de la carpeta database. '
              'Se encontraron ${allCsvFiles.length} archivos CSV pero no se pudo identificar la carpeta database.'
            );
          }
        } catch (e) {
          if (e.toString().contains('El ZIP no contiene archivos CSV') || 
              e.toString().contains('No se pudo determinar')) {
            rethrow;
          }
          print('[BackupProcessor] ⚠️ Error buscando archivos CSV: $e');
        }
      }
      
      // Lista de archivos CSV en orden (uno por tabla)
      final csvFiles = [
        '01_languages.csv',
        '02_generations.csv',
        '03_regions.csv',
        '04_types.csv',
        '05_type_damage_relations.csv',
        '06_stats.csv',
        '07_version_groups.csv',
        '08_move_damage_classes.csv',
        '09_abilities.csv',
        '10_moves.csv',
        '11_item_pockets.csv',
        '12_item_categories.csv',
        '13_items.csv',
        '14_egg_groups.csv',
        '15_growth_rates.csv',
        '16_natures.csv',
        '17_pokemon_colors.csv',
        '18_pokemon_shapes.csv',
        '19_pokemon_habitats.csv',
        '20_evolution_chains.csv',
        '21_pokemon_species.csv',
        '22_pokedex.csv',
        '23_pokemon.csv',
        '24_pokemon_types.csv',
        '25_pokemon_abilities.csv',
        '26_pokemon_moves.csv',
        '27_pokedex_entries.csv',
        '28_pokemon_variants.csv',
        '29_localized_names.csv',
      ];
      
      final totalFiles = csvFiles.length;
      
      // Cargar y parsear todos los CSV primero (en paralelo cuando sea posible)
      final parsedData = <String, List<List<String>>>{};
      
      // Mapa de nombres amigables en español
      final tableNames = {
        '01_languages.csv': 'Idiomas',
        '02_generations.csv': 'Generaciones',
        '03_regions.csv': 'Regiones',
        '04_types.csv': 'Tipos',
        '05_type_damage_relations.csv': 'Relaciones de daño',
        '06_stats.csv': 'Estadísticas',
        '07_version_groups.csv': 'Grupos de versión',
        '08_move_damage_classes.csv': 'Clases de daño',
        '09_abilities.csv': 'Habilidades',
        '10_moves.csv': 'Movimientos',
        '11_item_pockets.csv': 'Bolsillos de objetos',
        '12_item_categories.csv': 'Categorías de objetos',
        '13_items.csv': 'Objetos',
        '14_egg_groups.csv': 'Grupos de huevo',
        '15_growth_rates.csv': 'Ritmos de crecimiento',
        '16_natures.csv': 'Naturalezas',
        '17_pokemon_colors.csv': 'Colores',
        '18_pokemon_shapes.csv': 'Formas',
        '19_pokemon_habitats.csv': 'Hábitats',
        '20_evolution_chains.csv': 'Cadenas evolutivas',
        '21_pokemon_species.csv': 'Especies',
        '22_pokedex.csv': 'Pokedex',
        '23_pokemon.csv': 'Pokemons',
        '24_pokemon_types.csv': 'Tipos de pokemon',
        '25_pokemon_abilities.csv': 'Habilidades de pokemon',
        '26_pokemon_moves.csv': 'Movimientos de pokemon',
        '27_pokedex_entries.csv': 'Entradas de pokedex',
        '28_pokemon_variants.csv': 'Variantes',
        '29_localized_names.csv': 'Nombres localizados',
      };
      
      for (int fileIndex = 0; fileIndex < csvFiles.length; fileIndex++) {
        final fileName = csvFiles[fileIndex];
        final tableName = tableNames[fileName] ?? fileName.replaceAll(RegExp(r'^\d+_|\.csv$'), '').replaceAll('_', ' ');
        
        final loadingMsg = LoadingMessages.getMessageWithParams(
          'loading_table',
          languageCode,
          {
            'table': tableName,
          },
        );
        final progress = (fileIndex / totalFiles) * 0.5;
        print('[BackupProcessor] Progreso: ${(progress * 100).toStringAsFixed(1)}% - Cargando tabla ${fileIndex + 1}/$totalFiles: $tableName');
        onProgress?.call(
          loadingMsg,
          progress, // Primera mitad: carga y parseo
        );
        
        // Cargar archivo CSV desde directorio extraído
        File csvFile = File(path.join(databaseDir.path, fileName));
        String csvContent;
        
        // Si el archivo no existe en la ubicación esperada, buscarlo recursivamente
        if (!await csvFile.exists()) {
          print('[BackupProcessor] ⚠️ Archivo no encontrado en ubicación esperada: ${csvFile.path}');
          print('[BackupProcessor] 🔍 Buscando archivo $fileName recursivamente...');
          
          // Buscar el archivo recursivamente en dataDir
          File? foundFile;
          int searchedFiles = 0;
          try {
            await for (final entity in dataDir.list(recursive: true)) {
              if (entity is File && entity.path.endsWith('.csv')) {
                searchedFiles++;
                if (searchedFiles % 100 == 0) {
                  print('[BackupProcessor] 🔍 Buscando CSV... (${searchedFiles} CSV revisados)');
                }
                
                if (path.basename(entity.path) == fileName) {
                  foundFile = entity;
                  print('[BackupProcessor] ✅ Archivo encontrado en: ${foundFile.path}');
                  
                  // Actualizar databaseDir si es diferente
                  final foundDatabaseDir = Directory(path.dirname(foundFile.path));
                  if (foundDatabaseDir.path != databaseDir.path) {
                    print('[BackupProcessor] 📁 Actualizando databaseDir a: ${foundDatabaseDir.path}');
                    databaseDir = foundDatabaseDir; // Actualizar para los siguientes archivos
                  }
                  
                  break;
                }
              }
            }
            print('[BackupProcessor] 🔍 Búsqueda completada: ${searchedFiles} archivos CSV revisados');
          } catch (e) {
            print('[BackupProcessor] ⚠️ Error buscando archivo recursivamente: $e');
          }
          
          if (foundFile != null) {
            csvFile = foundFile;
          } else {
            // Si aún no se encuentra, verificar si databaseDir existe y listar su contenido
            print('[BackupProcessor] ⚠️ Archivo $fileName no encontrado después de búsqueda recursiva');
            if (await databaseDir.exists()) {
              print('[BackupProcessor] 📂 Contenido de databaseDir (primeros 20 CSV):');
              try {
                final items = await databaseDir.list()
                  .where((item) => item is File && item.path.endsWith('.csv'))
                  .toList();
                print('[BackupProcessor] 📂 Total de CSV en databaseDir: ${items.length}');
                for (final item in items.take(20)) {
                  print('[BackupProcessor]   - ${item.path}');
                }
              } catch (e) {
                print('[BackupProcessor] ⚠️ Error listando databaseDir: $e');
              }
            } else {
              print('[BackupProcessor] ⚠️ databaseDir no existe: ${databaseDir.path}');
            }
          }
        }
        
        try {
          print('[BackupProcessor] Cargando archivo: ${csvFile.path}');
          if (!await csvFile.exists()) {
            throw Exception('Archivo no encontrado: ${csvFile.path}');
          }
          csvContent = await csvFile.readAsString();
          print('[BackupProcessor] Archivo cargado: $fileName (${csvContent.length} caracteres)');
        } catch (e, stackTrace) {
          print('[BackupProcessor] ❌ ERROR cargando archivo ${csvFile.path}: $e');
          print('[BackupProcessor] Stack trace: $stackTrace');
          final errorMsg = LoadingMessages.getMessageWithParams(
            'error_loading_file',
            languageCode,
            {'path': csvFile.path},
          );
          final instructions = LoadingMessages.getMessage(
            'error_file_instructions',
            languageCode,
          );
          throw Exception('$errorMsg\n$instructions\nError: $e');
        }
        
        // Parsear CSV en un isolate separado
        try {
          print('[BackupProcessor] Parseando CSV: $fileName');
          final rows = await compute(_parseCsvIsolate, csvContent);
          print('[BackupProcessor] CSV parseado: $fileName -> ${rows.length} filas');
          
          if (rows.isNotEmpty) {
            // Validar que el header tenga el formato esperado
            final headers = rows[0];
            print('[BackupProcessor] Header de $fileName: ${headers.length} columnas');
            if (headers.length > 20) {
              print('[BackupProcessor] ⚠️ ADVERTENCIA: Header de $fileName tiene ${headers.length} columnas (esperado < 20). Posible problema de formato.');
              print('[BackupProcessor] Primeras 10 columnas del header: ${headers.take(10).join(", ")}');
            }
            
            parsedData[fileName] = rows;
            print('[BackupProcessor] ✅ $fileName: ${rows.length} filas listas para insertar (${rows.length - 1} filas de datos)');
          } else {
            print('[BackupProcessor] ⚠️ CSV $fileName está vacío después del parseo');
          }
        } catch (e, stackTrace) {
          print('[BackupProcessor] ❌ ERROR parseando CSV $fileName: $e');
          print('[BackupProcessor] Stack trace: $stackTrace');
      rethrow;
    }
  }
  
      // Insertar todos los datos en una sola transacción (mucho más rápido)
      // Ajustar progreso: 20% para descarga/extracción, 80% para procesamiento CSV
      final executingMsg = LoadingMessages.getMessage('executing', languageCode);
      print('[BackupProcessor] Progreso: 20.0% - Iniciando inserción de datos en transacción');
      print('[BackupProcessor] Total de archivos CSV procesados: ${parsedData.length}');
      onProgress?.call(executingMsg, 0.2);
      
      try {
        await database.transaction(() async {
          await database.batch((batch) {
            // Procesar todas las tablas en el mismo batch
            for (int fileIndex = 0; fileIndex < csvFiles.length; fileIndex++) {
              final fileName = csvFiles[fileIndex];
              final rows = parsedData[fileName];
              
              // Progreso: 20% base + 80% para procesamiento (distribuido entre todos los archivos)
              final progress = 0.2 + (fileIndex / csvFiles.length) * 0.8;
              print('[BackupProcessor] Progreso: ${(progress * 100).toStringAsFixed(1)}% - Procesando archivo ${fileIndex + 1}/${csvFiles.length}: $fileName');
              
              if (rows == null || rows.isEmpty) {
                print('[BackupProcessor] ⚠️ Archivo $fileName está vacío o no se pudo parsear, saltando...');
        continue;
      }
      
              final headers = rows[0];
              final dataRows = rows.sublist(1);
              
              print('[BackupProcessor] Archivo $fileName: ${dataRows.length} filas de datos (headers: ${headers.length} columnas)');
              
              try {
                _insertTableData(batch, fileName, headers, dataRows);
                print('[BackupProcessor] ✅ Archivo $fileName procesado correctamente');
              } catch (e, stackTrace) {
                print('[BackupProcessor] ❌ ERROR procesando $fileName: $e');
                print('[BackupProcessor] Stack trace: $stackTrace');
                rethrow;
              }
            }
          });
        });
        
        // Actualizar progreso después de la transacción
        print('[BackupProcessor] Progreso: 100.0% - Transacción completada');
        final progressMsg = LoadingMessages.getMessage('executing', languageCode);
        onProgress?.call(progressMsg, 1.0);
        
        print('[BackupProcessor] Progreso: 100.0% - Proceso completado');
        final completedMsg = LoadingMessages.getMessage('completed', languageCode);
        onProgress?.call(completedMsg, 1.0);
        
        // Borrar ZIPs después de volcar los datos a la base de datos
        print('[BackupProcessor] 🗑️ Eliminando archivos ZIP descargados...');
        int deletedCount = 0;
        for (final zipFile in downloadedZipFiles) {
          try {
            if (await zipFile.exists()) {
              await zipFile.delete();
              deletedCount++;
              print('[BackupProcessor]   ✅ Eliminado: ${path.basename(zipFile.path)}');
            }
          } catch (e) {
            print('[BackupProcessor]   ⚠️ No se pudo eliminar ${path.basename(zipFile.path)}: $e');
          }
        }
        
        if (deletedCount > 0) {
          print('[BackupProcessor] ✅ $deletedCount archivo(s) ZIP eliminado(s)');
        } else {
          print('[BackupProcessor] ℹ️ No se encontraron archivos ZIP para eliminar');
        }
      } catch (e, stackTrace) {
        print('[BackupProcessor] ❌ ERROR en transacción: $e');
        print('[BackupProcessor] Stack trace: $stackTrace');
        final errorLanguageCode = appConfig?.language;
        final errorMsg = LoadingMessages.getMessageWithParams(
          'error',
          errorLanguageCode,
          {'error': e.toString()},
        );
        onProgress?.call(errorMsg, 0.0);
        rethrow;
      }
    } catch (e, stackTrace) {
      print('[BackupProcessor] ❌ ERROR general en processBackupFromAssets: $e');
      print('[BackupProcessor] Stack trace: $stackTrace');
      final errorLanguageCode = appConfig?.language;
      final errorMsg = LoadingMessages.getMessageWithParams(
        'error',
        errorLanguageCode,
        {'error': e.toString()},
      );
      onProgress?.call(errorMsg, 0.0);
      rethrow;
    }
  }
  
  /// Función estática para parsear CSV en un isolate
  /// Maneja correctamente saltos de línea dentro de campos entre comillas
  /// Decodificar ZIP en un isolate para no bloquear el hilo principal
  static Future<Archive> _decodeZipInIsolate(List<int> zipBytes) async {
    return await compute(_decodeZipIsolate, zipBytes);
  }
  
  /// Función estática para decodificar ZIP en isolate
  static Archive _decodeZipIsolate(List<int> zipBytes) {
    return ZipDecoder().decodeBytes(zipBytes);
  }
  
  static List<List<String>> _parseCsvIsolate(String csvContent) {
    final rows = <List<String>>[];
    final fields = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;
    
    // Procesar carácter por carácter para manejar saltos de línea dentro de comillas
    for (int i = 0; i < csvContent.length; i++) {
      final char = csvContent[i];
      
      if (char == '"') {
        if (inQuotes && i + 1 < csvContent.length && csvContent[i + 1] == '"') {
          // Comilla escapada ("" dentro de comillas)
          buffer.write('"');
          i++; // Saltar la siguiente comilla
          } else {
          // Toggle quotes
          inQuotes = !inQuotes;
        }
      } else if (char == ';' && !inQuotes) {
        // Separador de campo (solo fuera de comillas)
        fields.add(buffer.toString());
        buffer.clear();
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        // Fin de fila (solo fuera de comillas)
        // Añadir el último campo antes del salto de línea
        if (buffer.isNotEmpty || fields.isNotEmpty) {
          fields.add(buffer.toString());
          buffer.clear();
          
          // Solo añadir fila si tiene contenido
          if (fields.any((f) => f.trim().isNotEmpty)) {
            rows.add(List<String>.from(fields));
          }
          fields.clear();
        }
        // Saltar \r si viene seguido de \n
        if (char == '\r' && i + 1 < csvContent.length && csvContent[i + 1] == '\n') {
          i++;
          }
        } else {
        // Cualquier otro carácter (incluyendo saltos de línea dentro de comillas)
        buffer.write(char);
      }
    }
    
    // Añadir última fila si queda contenido
    if (buffer.isNotEmpty || fields.isNotEmpty) {
      fields.add(buffer.toString());
      if (fields.any((f) => f.trim().isNotEmpty)) {
        rows.add(fields);
      }
    }
    
    return rows;
  }
  
  
  /// Insertar datos de una tabla usando batch
  void _insertTableData(
    Batch batch,
    String fileName,
    List<String> headers,
    List<List<String>> dataRows,
  ) {
    if (fileName.startsWith('01_languages')) {
      _insertLanguages(batch, headers, dataRows);
    } else if (fileName.startsWith('02_generations')) {
      _insertGenerations(batch, headers, dataRows);
    } else if (fileName.startsWith('03_regions')) {
      _insertRegions(batch, headers, dataRows);
    } else if (fileName.startsWith('04_types')) {
      _insertTypes(batch, headers, dataRows);
    } else if (fileName.startsWith('05_type_damage_relations')) {
      _insertTypeDamageRelations(batch, headers, dataRows);
    } else if (fileName.startsWith('06_stats')) {
      _insertStats(batch, headers, dataRows);
    } else if (fileName.startsWith('07_version_groups')) {
      _insertVersionGroups(batch, headers, dataRows);
    } else if (fileName.startsWith('08_move_damage_classes')) {
      _insertMoveDamageClasses(batch, headers, dataRows);
    } else if (fileName.startsWith('09_abilities')) {
      _insertAbilities(batch, headers, dataRows);
    } else if (fileName.startsWith('10_moves')) {
      _insertMoves(batch, headers, dataRows);
    } else if (fileName.startsWith('11_item_pockets')) {
      _insertItemPockets(batch, headers, dataRows);
    } else if (fileName.startsWith('12_item_categories')) {
      _insertItemCategories(batch, headers, dataRows);
    } else if (fileName.startsWith('13_items')) {
      _insertItems(batch, headers, dataRows);
    } else if (fileName.startsWith('14_egg_groups')) {
      _insertEggGroups(batch, headers, dataRows);
    } else if (fileName.startsWith('15_growth_rates')) {
      _insertGrowthRates(batch, headers, dataRows);
    } else if (fileName.startsWith('16_natures')) {
      _insertNatures(batch, headers, dataRows);
    } else if (fileName.startsWith('17_pokemon_colors')) {
      _insertPokemonColors(batch, headers, dataRows);
    } else if (fileName.startsWith('18_pokemon_shapes')) {
      _insertPokemonShapes(batch, headers, dataRows);
    } else if (fileName.startsWith('19_pokemon_habitats')) {
      _insertPokemonHabitats(batch, headers, dataRows);
    } else if (fileName.startsWith('20_evolution_chains')) {
      _insertEvolutionChains(batch, headers, dataRows);
    } else if (fileName.startsWith('21_pokemon_species')) {
      _insertPokemonSpecies(batch, headers, dataRows);
    } else if (fileName.startsWith('22_pokedex')) {
      _insertPokedex(batch, headers, dataRows);
    } else if (fileName.startsWith('23_pokemon')) {
      _insertPokemon(batch, headers, dataRows);
    } else if (fileName.startsWith('24_pokemon_types')) {
      _insertPokemonTypes(batch, headers, dataRows);
    } else if (fileName.startsWith('25_pokemon_abilities')) {
      _insertPokemonAbilities(batch, headers, dataRows);
    } else if (fileName.startsWith('26_pokemon_moves')) {
      _insertPokemonMoves(batch, headers, dataRows);
    } else if (fileName.startsWith('27_pokedex_entries')) {
      _insertPokedexEntries(batch, headers, dataRows);
    } else if (fileName.startsWith('28_pokemon_variants')) {
      _insertPokemonVariants(batch, headers, dataRows);
    } else if (fileName.startsWith('29_localized_names')) {
      _insertLocalizedNames(batch, headers, dataRows);
    }
  }
  
  // Funciones auxiliares para convertir valores CSV a tipos Dart (optimizadas)
  int? _parseInt(String? value) {
    if (value == null || value.isEmpty || value == 'null') return null;
    // Optimización: evitar tryParse cuando es posible
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }
  
  bool _parseBool(String? value) {
    if (value == null || value.isEmpty || value == 'null') return false;
    // Optimización: comparación directa sin toLowerCase cuando es posible
    return value == '1' || value == 'true' || value.toLowerCase() == 'true';
  }
  
  String? _parseString(String? value) {
    if (value == null || value.isEmpty || value == 'null') return null;
    return value;
  }
  
  // Funciones de inserción por tabla
  void _insertLanguages(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <LanguagesCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 6) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Languages incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Languages: id o apiId es null');
        continue;
      }
      
      companions.add(LanguagesCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
        officialName: Value(_parseString(row[3])),
        iso639: Value(_parseString(row[4])),
        iso3166: Value(_parseString(row[5])),
      ));
    }
    
    batch.insertAll(database.languages, companions, mode: InsertMode.replace);
  }
  
  void _insertGenerations(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <GenerationsCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 4) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Generations incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Generations: id o apiId es null');
        continue;
      }
      
      companions.add(GenerationsCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
        mainRegionId: Value(_parseInt(row[3])),
      ));
    }
    
    batch.insertAll(database.generations, companions, mode: InsertMode.replace);
  }
  
  void _insertRegions(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <RegionsCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 7) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Regions incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Regions: id o apiId es null');
        continue;
      }
      
      companions.add(RegionsCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
        mainGenerationId: Value(_parseInt(row[3])),
        locationsJson: Value(_parseString(row[4])),
        pokedexesJson: Value(_parseString(row[5])),
        versionGroupsJson: Value(_parseString(row[6])),
      ));
    }
    
    batch.insertAll(database.regions, companions, mode: InsertMode.replace);
  }
  
  void _insertTypes(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <TypesCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 7) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Types incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Types: id o apiId es null');
        continue;
      }
      
      companions.add(TypesCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
        generationId: Value(_parseInt(row[3])),
        moveDamageClassId: Value(_parseInt(row[4])),
        color: Value(_parseString(row[5])),
        damageRelationsJson: Value(_parseString(row[6])),
      ));
    }
    
    batch.insertAll(database.types, companions, mode: InsertMode.replace);
  }
  
  void _insertTypeDamageRelations(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <TypeDamageRelationsCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 3) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de TypeDamageRelations incompleta: ${row.length} columnas');
        continue;
      }
      
      final attackingTypeId = _parseInt(row[0]);
      final defendingTypeId = _parseInt(row[1]);
      if (attackingTypeId == null || defendingTypeId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de TypeDamageRelations: attackingTypeId o defendingTypeId es null');
        continue;
      }
      
      companions.add(TypeDamageRelationsCompanion(
        attackingTypeId: Value(attackingTypeId),
        defendingTypeId: Value(defendingTypeId),
        relationType: Value(row[2]),
      ));
    }
    
    batch.insertAll(database.typeDamageRelations, companions, mode: InsertMode.replace);
  }
  
  void _insertStats(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <StatsCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 6) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Stats incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Stats: id o apiId es null');
        continue;
      }
      
      companions.add(StatsCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
        gameIndex: Value(_parseInt(row[3])),
        isBattleOnly: Value(_parseBool(row[4])),
        moveDamageClassId: Value(_parseInt(row[5])),
      ));
    }
    
    batch.insertAll(database.stats, companions, mode: InsertMode.replace);
  }
  
  void _insertVersionGroups(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <VersionGroupsCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 5) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de VersionGroups incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de VersionGroups: id o apiId es null');
        continue;
      }
      
      companions.add(VersionGroupsCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
        generationId: Value(_parseInt(row[3])),
        order: Value(_parseInt(row[4])),
      ));
    }
    
    batch.insertAll(database.versionGroups, companions, mode: InsertMode.replace);
  }
  
  void _insertMoveDamageClasses(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <MoveDamageClassesCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 3) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de MoveDamageClasses incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de MoveDamageClasses: id o apiId es null');
        continue;
      }
      
      companions.add(MoveDamageClassesCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
      ));
    }
    
    batch.insertAll(database.moveDamageClasses, companions, mode: InsertMode.replace);
  }
  
  void _insertAbilities(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <AbilitiesCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 6) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Abilities incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Abilities: id o apiId es null');
        continue;
      }
      
      companions.add(AbilitiesCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
        isMainSeries: Value(_parseBool(row[3])),
        generationId: Value(_parseInt(row[4])),
        fullDataJson: Value(_parseString(row[5])),
      ));
    }
    
    batch.insertAll(database.abilities, companions, mode: InsertMode.replace);
  }
  
  void _insertMoves(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <MovesCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 12) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Moves incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Moves: id o apiId es null');
        continue;
      }
      
      companions.add(MovesCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
        accuracy: Value(_parseInt(row[3])),
        effectChance: Value(_parseInt(row[4])),
        pp: Value(_parseInt(row[5])),
        priority: Value(_parseInt(row[6])),
        power: Value(_parseInt(row[7])),
        typeId: Value(_parseInt(row[8])),
        damageClassId: Value(_parseInt(row[9])),
        generationId: Value(_parseInt(row[10])),
        fullDataJson: Value(_parseString(row[11])),
      ));
    }
    
    batch.insertAll(database.moves, companions, mode: InsertMode.replace);
  }
  
  void _insertItemPockets(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <ItemPocketsCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 3) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de ItemPockets incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de ItemPockets: id o apiId es null');
        continue;
      }
      
      companions.add(ItemPocketsCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
      ));
    }
    
    batch.insertAll(database.itemPockets, companions, mode: InsertMode.replace);
  }
  
  void _insertItemCategories(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <ItemCategoriesCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 4) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de ItemCategories incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de ItemCategories: id o apiId es null');
        continue;
      }
      
      companions.add(ItemCategoriesCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
        pocketId: Value(_parseInt(row[3])),
      ));
    }
    
    batch.insertAll(database.itemCategories, companions, mode: InsertMode.replace);
  }
  
  void _insertItems(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <ItemsCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 8) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Items incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Items: id o apiId es null');
        continue;
      }
      
      companions.add(ItemsCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
        cost: Value(_parseInt(row[3])),
        flingPower: Value(_parseInt(row[4])),
        categoryId: Value(_parseInt(row[5])),
        flingEffectId: Value(_parseInt(row[6])),
        fullDataJson: Value(_parseString(row[7])),
      ));
    }
    
    batch.insertAll(database.items, companions, mode: InsertMode.replace);
  }
  
  void _insertEggGroups(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <EggGroupsCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 3) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de EggGroups incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de EggGroups: id o apiId es null');
        continue;
      }
      
      companions.add(EggGroupsCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
      ));
    }
    
    batch.insertAll(database.eggGroups, companions, mode: InsertMode.replace);
  }
  
  void _insertGrowthRates(Batch batch, List<String> headers, List<List<String>> rows) {
    print('[BackupProcessor] _insertGrowthRates: Iniciando inserción de ${rows.length} growth rates');
    print('[BackupProcessor] _insertGrowthRates: Headers esperados: ${headers.length} columnas');
    print('[BackupProcessor] _insertGrowthRates: Headers: ${headers.join(", ")}');
    
    int processedCount = 0;
    int errorCount = 0;
    final List<String> errors = [];
    final companions = <GrowthRatesCompanion>[];
    
    try {
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        processedCount++;
        
        try {
          // Validar que la fila tenga suficientes columnas
          if (row.length < 4) {
            final error = 'Fila ${i + 1} de GrowthRates incompleta: se esperaban 4 columnas, se encontraron ${row.length}. Fila: ${row.join(";")}';
            print('[BackupProcessor] ❌ $error');
            errors.add(error);
            errorCount++;
            continue;
          }
          
          final id = _parseInt(row[0]);
          final apiId = _parseInt(row[1]);
          final name = row.length > 2 ? row[2] : '';
          final formula = row.length > 3 ? _parseString(row[3]) : null;
          
          // Validar campos requeridos
          if (id == null) {
            final error = 'Fila ${i + 1}: GrowthRates id es null. Fila: ${row.join(";")}';
            print('[BackupProcessor] ❌ $error');
            errors.add(error);
            errorCount++;
            continue;
          }
          if (apiId == null) {
            final error = 'Fila ${i + 1}: GrowthRates apiId es null. Fila: ${row.join(";")}';
            print('[BackupProcessor] ❌ $error');
            errors.add(error);
            errorCount++;
            continue;
          }
          
          companions.add(GrowthRatesCompanion(
            id: Value(id),
            apiId: Value(apiId),
            name: Value(name),
            formula: Value(formula),
          ));
        } catch (e, stackTrace) {
          final error = 'Fila ${i + 1}: Error procesando growth rate: $e';
          print('[BackupProcessor] ❌ $error');
          print('[BackupProcessor] Stack trace: $stackTrace');
          errors.add(error);
          errorCount++;
          continue;
        }
      }
      
      print('[BackupProcessor] _insertGrowthRates: Procesados $processedCount growth rates, ${companions.length} válidos, $errorCount errores');
      
      if (errors.isNotEmpty) {
        print('[BackupProcessor] Errores encontrados en GrowthRates:');
        for (final error in errors.take(10)) {
          print('[BackupProcessor]   - $error');
        }
      }
      
      if (companions.isEmpty) {
        print('[BackupProcessor] ⚠️ ADVERTENCIA: No se pudo procesar ningún growth rate válido. Total de filas: $processedCount, Errores: $errorCount');
        print('[BackupProcessor] Continuando sin insertar growth rates...');
        return; // Continuar sin lanzar excepción
      }
      
      print('[BackupProcessor] _insertGrowthRates: Insertando ${companions.length} growth rates en la base de datos...');
      batch.insertAll(database.growthRates, companions, mode: InsertMode.replace);
      print('[BackupProcessor] ✅ _insertGrowthRates: Inserción completada');
    } catch (e, stackTrace) {
      print('[BackupProcessor] ❌ ERROR en _insertGrowthRates: $e');
      print('[BackupProcessor] Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  void _insertNatures(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <NaturesCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 7) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Natures incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Natures: id o apiId es null');
        continue;
      }
      
      companions.add(NaturesCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
        decreasedStatId: Value(_parseInt(row[3])),
        increasedStatId: Value(_parseInt(row[4])),
        hatesFlavorId: Value(_parseInt(row[5])),
        likesFlavorId: Value(_parseInt(row[6])),
      ));
    }
    
    batch.insertAll(database.natures, companions, mode: InsertMode.replace);
  }
  
  void _insertPokemonColors(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <PokemonColorsCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 3) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokemonColors incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokemonColors: id o apiId es null');
        continue;
      }
      
      companions.add(PokemonColorsCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
      ));
    }
    
    batch.insertAll(database.pokemonColors, companions, mode: InsertMode.replace);
  }
  
  void _insertPokemonShapes(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <PokemonShapesCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 3) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokemonShapes incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokemonShapes: id o apiId es null');
        continue;
      }
      
      companions.add(PokemonShapesCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
      ));
    }
    
    batch.insertAll(database.pokemonShapes, companions, mode: InsertMode.replace);
  }
  
  void _insertPokemonHabitats(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <PokemonHabitatsCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 3) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokemonHabitats incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokemonHabitats: id o apiId es null');
        continue;
      }
      
      companions.add(PokemonHabitatsCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
      ));
    }
    
    batch.insertAll(database.pokemonHabitats, companions, mode: InsertMode.replace);
  }
  
  void _insertEvolutionChains(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <EvolutionChainsCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 4) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de EvolutionChains incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de EvolutionChains: id o apiId es null');
        continue;
      }
      
      companions.add(EvolutionChainsCompanion(
        id: Value(id),
        apiId: Value(apiId),
        babyTriggerItemId: Value(_parseInt(row[2])),
        chainJson: Value(_parseString(row[3])),
      ));
    }
    
    batch.insertAll(database.evolutionChains, companions, mode: InsertMode.replace);
  }
  
  void _insertPokemonSpecies(Batch batch, List<String> headers, List<List<String>> rows) {
    print('[BackupProcessor] _insertPokemonSpecies: Iniciando inserción de ${rows.length} pokemon species');
    
    final companions = <PokemonSpeciesCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      // Aceptar filas con al menos 25 columnas (puede haber más, las ignoramos)
      if (row.length < 25) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokemonSpecies incompleta: ${row.length} columnas (mínimo 25)');
        continue;
      }
      // Si hay más de 25 columnas, solo usamos las primeras 25 (las demás se ignoran)
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokemonSpecies: id o apiId es null');
        continue;
      }
      
      companions.add(PokemonSpeciesCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
        order: Value(_parseInt(row[3])),
        genderRate: Value(_parseInt(row[4])),
        captureRate: Value(_parseInt(row[5])),
        baseHappiness: Value(_parseInt(row[6])),
        isBaby: Value(_parseBool(row[7])),
        isLegendary: Value(_parseBool(row[8])),
        isMythical: Value(_parseBool(row[9])),
        hatchCounter: Value(_parseInt(row[10])),
        hasGenderDifferences: Value(_parseBool(row[11])),
        formsSwitchable: Value(_parseInt(row[12])),
        growthRateId: Value(_parseInt(row[13])),
        colorId: Value(_parseInt(row[14])),
        shapeId: Value(_parseInt(row[15])),
        habitatId: Value(_parseInt(row[16])),
        generationId: Value(_parseInt(row[17])),
        evolvesFromSpeciesId: Value(_parseInt(row[18])),
        evolutionChainId: Value(_parseInt(row[19])),
        eggGroupsJson: Value(_parseString(row[20])),
        flavorTextEntriesJson: Value(_parseString(row[21])),
        formDescriptionsJson: Value(_parseString(row[22])),
        varietiesJson: Value(_parseString(row[23])),
        generaJson: Value(_parseString(row[24])),
      ));
    }
    
    print('[BackupProcessor] _insertPokemonSpecies: Insertando ${companions.length} pokemon species en la base de datos...');
    batch.insertAll(database.pokemonSpecies, companions, mode: InsertMode.replace);
    print('[BackupProcessor] ✅ _insertPokemonSpecies: Inserción completada');
  }
  
  void _insertPokedex(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <PokedexCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 8) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Pokedex incompleta: ${row.length} columnas');
        continue;
      }
      
      final id = _parseInt(row[0]);
      final apiId = _parseInt(row[1]);
      if (id == null || apiId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de Pokedex: id o apiId es null');
        continue;
      }
      
      companions.add(PokedexCompanion(
        id: Value(id),
        apiId: Value(apiId),
        name: Value(row[2]),
        isMainSeries: Value(_parseBool(row[3])),
        regionId: Value(_parseInt(row[4])),
        color: Value(_parseString(row[5])),
        descriptionsJson: Value(_parseString(row[6])),
        pokemonEntriesJson: Value(_parseString(row[7])),
      ));
    }
    
    batch.insertAll(database.pokedex, companions, mode: InsertMode.replace);
  }
  
  void _insertPokemon(Batch batch, List<String> headers, List<List<String>> rows) {
    print('[BackupProcessor] _insertPokemon: Iniciando inserción de ${rows.length} pokemons');
    print('[BackupProcessor] _insertPokemon: Headers esperados: ${headers.length} columnas');
    print('[BackupProcessor] _insertPokemon: Headers: ${headers.join(", ")}');
    
    int processedCount = 0;
    int errorCount = 0;
    final List<String> errors = [];
    
    final companions = <PokemonCompanion>[];
    
    try {
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        processedCount++;
        
        try {
          // Validar que la fila tenga suficientes columnas (puede haber más, las ignoramos)
          if (row.length < 27) {
            final error = 'Fila ${i + 1} de Pokemon incompleta: se esperaban 27 columnas, se encontraron ${row.length}. Fila: ${row.take(5).join(";")}...';
            print('[BackupProcessor] ❌ $error');
            errors.add(error);
            errorCount++;
            continue;
          }
          // Si hay más de 27 columnas, solo usamos las primeras 27 (las demás se ignoran)
          
          final id = _parseInt(row[0]);
          final apiId = _parseInt(row[1]);
          final name = row.length > 2 ? row[2] : '';
          final speciesId = row.length > 3 ? _parseInt(row[3]) : null;
          
          // Log cada 100 pokemons para no saturar
          if (processedCount % 100 == 0) {
            print('[BackupProcessor] Procesando pokemon $processedCount/${rows.length}... (id=$id, apiId=$apiId, name=$name)');
          }
          
          // Validar campos requeridos
          if (id == null) {
            final error = 'Fila ${i + 1}: Pokemon id es null. Fila: ${row.take(5).join(";")}...';
            print('[BackupProcessor] ❌ $error');
            errors.add(error);
            errorCount++;
            continue;
          }
          if (apiId == null) {
            final error = 'Fila ${i + 1}: Pokemon apiId es null. Fila: ${row.take(5).join(";")}...';
            print('[BackupProcessor] ❌ $error');
            errors.add(error);
            errorCount++;
            continue;
          }
          if (speciesId == null) {
            final error = 'Fila ${i + 1}: Pokemon speciesId es null para pokemon id=$id, apiId=$apiId, name=$name. Fila completa: ${row.join(";")}';
            print('[BackupProcessor] ❌ $error');
            errors.add(error);
            errorCount++;
            continue;
          }
          
          companions.add(PokemonCompanion(
            id: Value(id),
            apiId: Value(apiId),
            name: Value(name),
            speciesId: Value(speciesId),
            baseExperience: Value(_parseInt(row[4])),
            height: Value(_parseInt(row[5])),
            weight: Value(_parseInt(row[6])),
            isDefault: Value(_parseBool(row[7])),
            order: Value(_parseInt(row[8])),
            locationAreaEncounters: Value(_parseInt(row[9])),
            abilitiesJson: Value(_parseString(row[10])),
            formsJson: Value(_parseString(row[11])),
            gameIndicesJson: Value(_parseString(row[12])),
            heldItemsJson: Value(_parseString(row[13])),
            movesJson: Value(_parseString(row[14])),
            spritesJson: Value(_parseString(row[15])),
            statsJson: Value(_parseString(row[16])),
            typesJson: Value(_parseString(row[17])),
            criesJson: Value(_parseString(row[18])),
            spriteFrontDefaultPath: Value(_parseString(row[19])),
            spriteFrontShinyPath: Value(_parseString(row[20])),
            spriteBackDefaultPath: Value(_parseString(row[21])),
            spriteBackShinyPath: Value(_parseString(row[22])),
            artworkOfficialPath: Value(_parseString(row[23])),
            artworkOfficialShinyPath: Value(_parseString(row[24])),
            cryLatestPath: Value(_parseString(row[25])),
            cryLegacyPath: Value(_parseString(row[26])),
          ));
        } catch (e, stackTrace) {
          final error = 'Fila ${i + 1}: Error procesando pokemon: $e';
          print('[BackupProcessor] ❌ $error');
          print('[BackupProcessor] Stack trace: $stackTrace');
          errors.add(error);
          errorCount++;
          continue;
        }
      }
      
      print('[BackupProcessor] _insertPokemon: Procesados $processedCount pokemons, ${companions.length} válidos, $errorCount errores');
      
      if (errors.isNotEmpty && errors.length <= 10) {
        print('[BackupProcessor] Primeros errores encontrados:');
        for (final error in errors.take(10)) {
          print('[BackupProcessor]   - $error');
        }
      } else if (errors.length > 10) {
        print('[BackupProcessor] Total de $errorCount errores (mostrando solo los primeros 10)');
        for (final error in errors.take(10)) {
          print('[BackupProcessor]   - $error');
        }
      }
      
      if (companions.isEmpty) {
        throw Exception('No se pudo procesar ningún pokemon válido. Total de filas: $processedCount, Errores: $errorCount');
      }
      
      print('[BackupProcessor] _insertPokemon: Insertando ${companions.length} pokemons en la base de datos...');
      batch.insertAll(database.pokemon, companions, mode: InsertMode.replace);
      print('[BackupProcessor] ✅ _insertPokemon: Inserción completada');
    } catch (e, stackTrace) {
      print('[BackupProcessor] ❌ ERROR en _insertPokemon: $e');
      print('[BackupProcessor] Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  void _insertPokemonTypes(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <PokemonTypesCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 3) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokemonTypes incompleta: ${row.length} columnas');
        continue;
      }
      
      final pokemonId = _parseInt(row[0]);
      final typeId = _parseInt(row[1]);
      final slot = _parseInt(row[2]);
      if (pokemonId == null || typeId == null || slot == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokemonTypes: pokemonId, typeId o slot es null');
        continue;
      }
      
      companions.add(PokemonTypesCompanion(
        pokemonId: Value(pokemonId),
        typeId: Value(typeId),
        slot: Value(slot),
      ));
    }
    
    batch.insertAll(database.pokemonTypes, companions, mode: InsertMode.replace);
  }
  
  void _insertPokemonAbilities(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <PokemonAbilitiesCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 4) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokemonAbilities incompleta: ${row.length} columnas');
        continue;
      }
      
      final pokemonId = _parseInt(row[0]);
      final abilityId = _parseInt(row[1]);
      final slot = _parseInt(row[3]);
      if (pokemonId == null || abilityId == null || slot == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokemonAbilities: pokemonId, abilityId o slot es null');
        continue;
      }
      
      companions.add(PokemonAbilitiesCompanion(
        pokemonId: Value(pokemonId),
        abilityId: Value(abilityId),
        isHidden: Value(_parseBool(row[2])),
        slot: Value(slot),
      ));
    }
    
    batch.insertAll(database.pokemonAbilities, companions, mode: InsertMode.replace);
  }
  
  void _insertPokemonMoves(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <PokemonMovesCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 5) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokemonMoves incompleta: ${row.length} columnas');
        continue;
      }
      
      final pokemonId = _parseInt(row[0]);
      final moveId = _parseInt(row[1]);
      if (pokemonId == null || moveId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokemonMoves: pokemonId o moveId es null');
        continue;
      }
      
      companions.add(PokemonMovesCompanion(
        pokemonId: Value(pokemonId),
        moveId: Value(moveId),
        versionGroupId: Value(_parseInt(row[2])),
        learnMethod: Value(_parseString(row[3])),
        level: Value(_parseInt(row[4])),
      ));
    }
    
    batch.insertAll(database.pokemonMoves, companions, mode: InsertMode.replace);
  }
  
  void _insertPokedexEntries(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <PokedexEntriesCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 3) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokedexEntries incompleta: ${row.length} columnas');
        continue;
      }
      
      final pokedexId = _parseInt(row[0]);
      final pokemonSpeciesId = _parseInt(row[1]);
      final entryNumber = _parseInt(row[2]);
      if (pokedexId == null || pokemonSpeciesId == null || entryNumber == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokedexEntries: pokedexId, pokemonSpeciesId o entryNumber es null');
        continue;
      }
      
      companions.add(PokedexEntriesCompanion(
        pokedexId: Value(pokedexId),
        pokemonSpeciesId: Value(pokemonSpeciesId),
        entryNumber: Value(entryNumber),
      ));
    }
    
    batch.insertAll(database.pokedexEntries, companions, mode: InsertMode.replace);
  }
  
  void _insertPokemonVariants(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <PokemonVariantsCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 2) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokemonVariants incompleta: ${row.length} columnas');
        continue;
      }
      
      final pokemonId = _parseInt(row[0]);
      final variantPokemonId = _parseInt(row[1]);
      if (pokemonId == null || variantPokemonId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de PokemonVariants: pokemonId o variantPokemonId es null');
        continue;
      }
      
      companions.add(PokemonVariantsCompanion(
        pokemonId: Value(pokemonId),
        variantPokemonId: Value(variantPokemonId),
      ));
    }
    
    batch.insertAll(database.pokemonVariants, companions, mode: InsertMode.replace);
  }
  
  void _insertLocalizedNames(Batch batch, List<String> headers, List<List<String>> rows) {
    final companions = <LocalizedNamesCompanion>[];
    
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 4) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de LocalizedNames incompleta: ${row.length} columnas');
        continue;
      }
      
      final entityId = _parseInt(row[1]);
      final languageId = _parseInt(row[2]);
      if (entityId == null || languageId == null) {
        print('[BackupProcessor] ⚠️ Fila ${i + 1} de LocalizedNames: entityId o languageId es null');
        continue;
      }
      
      companions.add(LocalizedNamesCompanion(
        entityType: Value(row[0]),
        entityId: Value(entityId),
        languageId: Value(languageId),
        name: Value(row[3]),
      ));
    }
    
    batch.insertAll(database.localizedNames, companions, mode: InsertMode.replace);
  }
}
