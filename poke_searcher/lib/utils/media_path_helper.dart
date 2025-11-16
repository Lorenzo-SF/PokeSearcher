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
  
  /// Transformar ruta con estructura de directorios a ruta aplanada real
  /// Funciona para TODOS los tipos de archivos multimedia: png, svg, ogg, mp3, jpg, jpeg, gif, webp, etc.
  /// Ejemplos:
  ///   - "media/pokemon/4/sprite_front_default.svg" -> "media_pokemon_4_sprite_front_default.svg"
  ///   - "media/pokemon/4/cry_latest.ogg" -> "media_pokemon_4_cry_latest.ogg"
  ///   - "media/item/101/helix-fossil.png" -> "media_item_101_helix-fossil.png"
  /// Flutter aplanará los nombres al extraer, así que necesitamos transformar la ruta buscada
  static String _flattenPath(String originalPath) {
    // Remover prefijo "assets/" si existe
    String cleanPath = originalPath;
    if (cleanPath.startsWith('assets/')) {
      cleanPath = cleanPath.substring(7);
    }
    
    // Si ya es una ruta absoluta, extraer solo la parte relativa
    if (cleanPath.startsWith('/')) {
      // Buscar la parte después de poke_searcher_data
      final dataIndex = cleanPath.indexOf('poke_searcher_data/');
      if (dataIndex != -1) {
        cleanPath = cleanPath.substring(dataIndex + 'poke_searcher_data/'.length);
      } else {
        // Si no tiene poke_searcher_data, tomar solo el nombre del archivo
        return path.basename(cleanPath);
      }
    }
    
    // Normalizar separadores de ruta
    cleanPath = cleanPath.replaceAll('\\', '/');
    
    // Si la ruta tiene estructura (ej: "media/pokemon/4/sprite_front_default.svg")
    // Transformarla a nombre aplanado (ej: "media_pokemon_4_sprite_front_default.svg")
    if (cleanPath.contains('/')) {
      // Reemplazar todos los separadores / por _
      return cleanPath.replaceAll('/', '_');
    }
    
    // Si ya está aplanado, devolverlo tal cual
    return cleanPath;
  }
  
  /// Convertir ruta de asset (puede tener estructura o estar aplanada) a ruta de archivo local aplanado
  /// Funciona para TODOS los tipos de archivos multimedia: png, svg, ogg, mp3, jpg, jpeg, gif, webp, etc.
  /// Los archivos se extraen con nombres aplanados porque Flutter no puede crear directorios anidados
  static Future<String?> assetPathToLocalPath(String? assetPath) async {
    if (assetPath == null || assetPath.isEmpty) {
      return null;
    }
    
    // Si ya es una ruta absoluta (empieza con /), transformarla
    if (assetPath.startsWith('/')) {
      // Extraer la parte relativa y aplanarla
      final dataIndex = assetPath.indexOf('poke_searcher_data/');
      if (dataIndex != -1) {
        final relativePath = assetPath.substring(dataIndex + 'poke_searcher_data/'.length);
        final flattenedName = _flattenPath(relativePath);
        final dataDir = await getAppDataDirectory();
        return path.join(dataDir.path, flattenedName);
      }
      // Si no tiene poke_searcher_data, intentar aplanar toda la ruta
      final flattenedName = _flattenPath(assetPath);
      final dataDir = await getAppDataDirectory();
      return path.join(dataDir.path, flattenedName);
    }
    
    // Transformar la ruta a nombre aplanado
    final flattenedName = _flattenPath(assetPath);
    final dataDir = await getAppDataDirectory();
    
    // Construir ruta local aplanada directamente en la raíz de poke_searcher_data
    final localPath = path.join(dataDir.path, flattenedName);
    
    // Verificar si el archivo existe
    final file = File(localPath);
    final exists = await file.exists();
    
    if (!exists) {
      // Buscar el archivo por nombre en poke_searcher_data (puede estar en cualquier ubicación)
      try {
        if (await dataDir.exists()) {
          final fileName = path.basename(flattenedName);
          
          // PRIORIDAD 1: Buscar exactamente por nombre
          await for (final entity in dataDir.list(recursive: true)) {
            if (entity is File && path.basename(entity.path) == fileName) {
              return entity.path;
            }
          }
          
          // PRIORIDAD 2: Para archivos de pokemon, buscar variante con _default_
          // Ejemplo: media_pokemon_1_artwork_official.svg -> media_pokemon_1_default_artwork_official.svg
          if (fileName.startsWith('media_pokemon_') && 
              (fileName.contains('_artwork_official') || 
               fileName.contains('_sprite_front_default') ||
               fileName.contains('_sprite_front_shiny') ||
               fileName.contains('_cry_latest') ||
               fileName.contains('_cry_legacy'))) {
            // Intentar insertar _default_ antes del tipo de archivo
            String? alternativeName;
            if (fileName.contains('_artwork_official')) {
              alternativeName = fileName.replaceFirst('_artwork_official', '_default_artwork_official');
            } else if (fileName.contains('_sprite_front_default')) {
              alternativeName = fileName.replaceFirst('_sprite_front_default', '_default_sprite_front_default');
            } else if (fileName.contains('_sprite_front_shiny')) {
              alternativeName = fileName.replaceFirst('_sprite_front_shiny', '_default_sprite_front_shiny');
            } else if (fileName.contains('_cry_latest')) {
              alternativeName = fileName.replaceFirst('_cry_latest', '_default_cry_latest');
            } else if (fileName.contains('_cry_legacy')) {
              alternativeName = fileName.replaceFirst('_cry_legacy', '_default_cry_legacy');
            }
            
            if (alternativeName != null) {
              await for (final entity in dataDir.list(recursive: true)) {
                if (entity is File && path.basename(entity.path) == alternativeName) {
                  return entity.path;
                }
              }
            }
          }
        }
      } catch (e) {
        // Error buscando, continuar
      }
    }
    
    return localPath;
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

