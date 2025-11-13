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
import '../config/app_config.dart';

/// Servicio para procesar backups CSV y cargar datos en la base de datos
class BackupProcessor {
  final AppDatabase database;
  final AppConfig? appConfig;
  
  // URL del ZIP en GitHub Releases
  static const String _backupZipUrl = 'https://github.com/Lorenzo-SF/PokeSearcher/releases/download/1.0.0/poke_searcher_backup.zip';
  
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
  
  /// Buscar y mover la carpeta media a la ubicación correcta
  Future<void> _findAndMoveMediaDirectory(Directory dataDir, Directory targetMediaDir) async {
    try {
      // Buscar recursivamente la carpeta media
      await for (final entity in dataDir.list(recursive: true)) {
        if (entity is Directory && path.basename(entity.path).toLowerCase() == 'media') {
          // Encontramos una carpeta media
          final sourceMediaDir = entity;
          
          // Si no es la ubicación objetivo, moverla
          if (sourceMediaDir.path != targetMediaDir.path) {
            print('[BackupProcessor] 📦 Moviendo carpeta media de ${sourceMediaDir.path} a ${targetMediaDir.path}');
            
            // Si ya existe la carpeta objetivo, eliminarla primero
            if (await targetMediaDir.exists()) {
              await targetMediaDir.delete(recursive: true);
            }
            
            // Crear directorio padre si no existe
            final parentDir = Directory(path.dirname(targetMediaDir.path));
            if (!await parentDir.exists()) {
              await parentDir.create(recursive: true);
            }
            
            // Mover la carpeta (copiar y luego eliminar)
            await _copyDirectory(sourceMediaDir, targetMediaDir);
            await sourceMediaDir.delete(recursive: true);
            
            print('[BackupProcessor] ✅ Carpeta media movida correctamente');
            return;
          }
        }
      }
      
      print('[BackupProcessor] ⚠️ No se encontró carpeta media en el ZIP extraído');
    } catch (e) {
      print('[BackupProcessor] ⚠️ Error buscando/moviendo carpeta media: $e');
      // No es crítico, continuar
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
          print('[BackupProcessor] 📥 Descargando ZIP desde: $_backupZipUrl (intento $attempt)');
        }
        
        // Crear request con headers apropiados para descargas grandes
        final request = http.Request('GET', Uri.parse(_backupZipUrl));
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
              uri: Uri.parse(_backupZipUrl),
            );
            // Si es 404, no tiene sentido reintentar
            if (streamedResponse.statusCode == 404) {
              print('[BackupProcessor] ❌ Archivo no encontrado (404): $_backupZipUrl');
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
  
  /// Descargar y extraer el ZIP del backup
  Future<Directory> _downloadAndExtractZip({
    void Function(String message, double progress)? onProgress,
  }) async {
    final languageCode = appConfig?.language;
    
    // Verificar si ya está extraído
    final dataDir = await _getAppDataDirectory();
    final databaseDir = Directory(path.join(dataDir.path, 'database'));
    final mediaDir = Directory(path.join(dataDir.path, 'media'));
    
    if (await databaseDir.exists() && await mediaDir.exists()) {
      // Verificar que hay archivos
      final csvFiles = await databaseDir.list().toList();
      if (csvFiles.isNotEmpty) {
        print('[BackupProcessor] ✅ Backup ya extraído, usando archivos existentes');
        onProgress?.call(
          LoadingMessages.getMessage('using_existing_data', languageCode),
          0.1,
        );
        return dataDir;
      }
    }
    
    // Obtener directorio temporal para el ZIP
    final tempDir = await getTemporaryDirectory();
    final zipFile = File(path.join(tempDir.path, 'poke_searcher_backup.zip'));
    
    // Descargar ZIP con reintentos infinitos
    await _downloadZipWithRetries(
      zipFile: zipFile,
      onProgress: onProgress,
      languageCode: languageCode,
    );
    
    // Extraer ZIP
    onProgress?.call(
      LoadingMessages.getMessage('extracting_backup', languageCode),
      0.1,
    );
    print('[BackupProcessor] 📦 Extrayendo ZIP...');
    
    try {
      // Leer ZIP desde archivo de forma asíncrona
      final zipBytes = await zipFile.readAsBytes();
      
      // Decodificar ZIP en un isolate para no bloquear el hilo principal
      final archive = await _decodeZipInIsolate(zipBytes);
      
      // Limpiar directorio de datos si existe
      if (await dataDir.exists()) {
        await dataDir.delete(recursive: true);
      }
      await dataDir.create(recursive: true);
      
      // Extraer archivos en chunks para permitir actualizaciones de UI
      int extracted = 0;
      final files = archive.whereType<ArchiveFile>().toList();
      final total = files.length;
      const chunkSize = 50; // Procesar 50 archivos por chunk
      
      for (int i = 0; i < files.length; i += chunkSize) {
        final endIndex = (i + chunkSize < files.length) ? i + chunkSize : files.length;
        final chunk = files.sublist(i, endIndex);
        
        // Procesar chunk
        for (final file in chunk) {
          if (file.isFile) {
            final filePath = path.join(dataDir.path, file.name);
            final fileDir = Directory(path.dirname(filePath));
            if (!await fileDir.exists()) {
              await fileDir.create(recursive: true);
            }
            
            final outFile = File(filePath);
            await outFile.writeAsBytes(file.content as List<int>);
            extracted++;
          }
        }
        
        // Permitir que la UI se actualice después de cada chunk
        await Future.delayed(Duration.zero);
        
        // Actualizar progreso
        if (extracted % 100 == 0 || extracted == total) {
          final progress = 0.1 + (extracted / total) * 0.1;
          onProgress?.call(
            'Extrayendo... ($extracted/$total archivos)',
            progress,
          );
        }
      }
      
      print('[BackupProcessor] ✅ ZIP extraído: $extracted archivos');
      
      // Asegurar que la carpeta media esté en la ubicación correcta
      final targetMediaDir = Directory(path.join(dataDir.path, 'media'));
      
      if (await targetMediaDir.exists()) {
        print('[BackupProcessor] ✅ Carpeta media encontrada en ubicación correcta: ${targetMediaDir.path}');
      } else {
        // Buscar la carpeta media en otras ubicaciones posibles dentro del ZIP extraído
        print('[BackupProcessor] 🔍 Buscando carpeta media en otras ubicaciones...');
        await _findAndMoveMediaDirectory(dataDir, targetMediaDir);
        
        // Verificar nuevamente después de mover
        if (await targetMediaDir.exists()) {
          print('[BackupProcessor] ✅ Carpeta media movida y verificada: ${targetMediaDir.path}');
        } else {
          print('[BackupProcessor] ⚠️ Carpeta media no encontrada después de la búsqueda');
        }
      }
      
      // Borrar el ZIP después de extraer
      try {
        if (await zipFile.exists()) {
          await zipFile.delete();
          print('[BackupProcessor] ✅ ZIP borrado después de extraer');
        }
      } catch (e) {
        print('[BackupProcessor] ⚠️ No se pudo borrar el ZIP (no crítico): $e');
      }
      
      return dataDir;
    } catch (e) {
      print('[BackupProcessor] ❌ Error extrayendo ZIP: $e');
      // Intentar borrar el ZIP incluso si hay error
      try {
        if (await zipFile.exists()) {
          await zipFile.delete();
        }
      } catch (_) {}
      rethrow;
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
    try {
      final languageCode = appConfig?.language;
      final message = LoadingMessages.getMessage('preparing', languageCode);
      print('[BackupProcessor] Iniciando proceso de backup desde ZIP');
      print('[BackupProcessor] Progreso: 0.0% - $message');
      onProgress?.call(message, 0.0);
      
      // Descargar y extraer ZIP (0-20% del progreso)
      final dataDir = await _downloadAndExtractZip(onProgress: onProgress);
      final databaseDir = Directory(path.join(dataDir.path, 'database'));
      
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
        final csvFile = File(path.join(databaseDir.path, fileName));
        String csvContent;
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
