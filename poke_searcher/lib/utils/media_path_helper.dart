import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Helper para convertir rutas de assets a rutas de archivos locales
class MediaPathHelper {
  static Directory? _appDataDirectory;
  
  /// Obtener el directorio de datos de la app (donde están los archivos extraídos)
  static Future<Directory> getAppDataDirectory() async {
    if (_appDataDirectory != null && await _appDataDirectory!.exists()) {
      return _appDataDirectory!;
    }
    
    final appDocDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory(path.join(appDocDir.path, 'poke_searcher_data'));
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    _appDataDirectory = dataDir;
    return dataDir;
  }
  
  /// Convertir ruta de asset (ej: "assets/media/pokemon/1/artwork_official.png" o "media/pokemon/1/artwork_official.png")
  /// a ruta de archivo local
  static Future<String?> assetPathToLocalPath(String? assetPath) async {
    if (assetPath == null || assetPath.isEmpty) {
      print('[MediaPathHelper] ⚠️ assetPath es null o vacío');
      return null;
    }
    
    print('[MediaPathHelper] 🔍 Convirtiendo path: $assetPath');
    
    // Si ya es una ruta absoluta (empieza con /), devolverla tal cual
    if (assetPath.startsWith('/')) {
      print('[MediaPathHelper] ✅ Path ya es absoluto: $assetPath');
      return assetPath;
    }
    
    // Remover prefijo "assets/" si existe
    String relativePath = assetPath;
    if (relativePath.startsWith('assets/')) {
      relativePath = relativePath.substring(7); // Quitar "assets/"
      print('[MediaPathHelper]   - Removido prefijo assets/: $relativePath');
    }
    
    // Si la ruta no empieza con "media/", añadirla (por compatibilidad)
    if (!relativePath.startsWith('media/')) {
      relativePath = 'media/$relativePath';
      print('[MediaPathHelper]   - Añadido prefijo media/: $relativePath');
    }
    
    // Construir ruta local
    final dataDir = await getAppDataDirectory();
    final localPath = path.join(dataDir.path, relativePath);
    
    print('[MediaPathHelper]   - dataDir: ${dataDir.path}');
    print('[MediaPathHelper]   - relativePath: $relativePath');
    print('[MediaPathHelper]   - localPath final: $localPath');
    
    // Verificar si el archivo existe
    final file = File(localPath);
    final exists = await file.exists();
    print('[MediaPathHelper]   - Archivo existe: $exists');
    
    if (!exists) {
      // Intentar buscar el archivo en ubicaciones alternativas
      print('[MediaPathHelper] 🔍 Archivo no encontrado, buscando alternativas...');
      final alternativePath = await _findAlternativePath(dataDir, relativePath);
      if (alternativePath != null) {
        print('[MediaPathHelper] ✅ Archivo encontrado en ubicación alternativa: $alternativePath');
        return alternativePath;
      }
      
      // Listar archivos en el directorio esperado para debugging
      final expectedDir = Directory(path.dirname(localPath));
      if (await expectedDir.exists()) {
        print('[MediaPathHelper] 📂 Directorio existe, listando archivos:');
        try {
          await for (final entity in expectedDir.list()) {
            if (entity is File) {
              print('[MediaPathHelper]   - ${path.basename(entity.path)}');
            }
          }
        } catch (e) {
          print('[MediaPathHelper] ⚠️ Error listando directorio: $e');
        }
      } else {
        print('[MediaPathHelper] ❌ Directorio no existe: ${expectedDir.path}');
      }
    }
    
    return localPath;
  }
  
  /// Buscar archivo en ubicaciones alternativas
  static Future<String?> _findAlternativePath(Directory dataDir, String relativePath) async {
    final fileName = path.basename(relativePath);
    final pathParts = path.split(relativePath);
    
    // Intentar construir nombre aplanado para buscar
    // Ejemplo: media/pokemon/1000/sprite_front_shiny.png -> mediapokemon1000sprite_front_shiny.png
    String? flattenedName;
    if (pathParts.length >= 4) {
      // Buscar patrón: media/{type}/{id}/{filename}
      final typeIndex = pathParts.indexWhere((p) => p.toLowerCase() == 'media');
      if (typeIndex >= 0 && typeIndex + 2 < pathParts.length) {
        final mediaType = pathParts[typeIndex + 1];
        final entityId = pathParts[typeIndex + 2];
        final actualFileName = pathParts.last;
        // Construir nombre aplanado: media + tipo + id + filename
        flattenedName = 'media$mediaType$entityId$actualFileName';
        print('[MediaPathHelper]   - Buscando nombre aplanado: $flattenedName');
      }
    }
    
    // Buscar recursivamente en media/
    try {
      final mediaDir = Directory(path.join(dataDir.path, 'media'));
      if (await mediaDir.exists()) {
        // Primero buscar por nombre exacto
        await for (final entity in mediaDir.list(recursive: true)) {
          if (entity is File && path.basename(entity.path) == fileName) {
            print('[MediaPathHelper]   - Encontrado archivo alternativo: ${entity.path}');
            return entity.path;
          }
        }
        
        // Si no se encuentra, buscar por nombre aplanado
        if (flattenedName != null) {
          await for (final entity in mediaDir.list()) {
            if (entity is File && path.basename(entity.path) == flattenedName) {
              print('[MediaPathHelper]   - Encontrado archivo aplanado: ${entity.path}');
              // Reorganizar el archivo aplanado a la estructura correcta
              final targetPath = await _reorganizeFlattenedFile(entity, relativePath, dataDir);
              if (targetPath != null) {
                return targetPath;
              }
              // Si la reorganización falla, devolver el path aplanado
              return entity.path;
            }
          }
        }
      }
    } catch (e) {
      print('[MediaPathHelper] ⚠️ Error buscando archivo alternativo: $e');
    }
    
    return null;
  }
  
  /// Reorganizar un archivo aplanado a la estructura correcta
  static Future<String?> _reorganizeFlattenedFile(File flattenedFile, String targetRelativePath, Directory dataDir) async {
    try {
      final targetPath = path.join(dataDir.path, targetRelativePath);
      final targetDir = Directory(path.dirname(targetPath));
      
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      
      final targetFile = File(targetPath);
      if (!await targetFile.exists()) {
        await flattenedFile.rename(targetPath);
        print('[MediaPathHelper]   ✅ Archivo reorganizado: ${path.basename(flattenedFile.path)} -> $targetRelativePath');
        return targetPath;
      } else {
        // Si ya existe, eliminar el duplicado aplanado
        await flattenedFile.delete();
        return targetPath;
      }
    } catch (e) {
      print('[MediaPathHelper] ⚠️ Error reorganizando archivo: $e');
      return null;
    }
  }
  
  /// Verificar si un archivo local existe
  static Future<bool> localFileExists(String? assetPath) async {
    if (assetPath == null || assetPath.isEmpty) {
      return false;
    }
    
    final localPath = await assetPathToLocalPath(assetPath);
    if (localPath == null) {
      return false;
    }
    
    final file = File(localPath);
    return await file.exists();
  }
}

