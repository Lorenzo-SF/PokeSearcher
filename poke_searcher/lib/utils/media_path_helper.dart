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
      return null;
    }
    
    // Si ya es una ruta absoluta (empieza con /), devolverla tal cual
    if (assetPath.startsWith('/')) {
      return assetPath;
    }
    
    // Remover prefijo "assets/" si existe
    String relativePath = assetPath;
    if (relativePath.startsWith('assets/')) {
      relativePath = relativePath.substring(7); // Quitar "assets/"
    }
    
    // Si la ruta no empieza con "media/", añadirla (por compatibilidad)
    if (!relativePath.startsWith('media/')) {
      relativePath = 'media/$relativePath';
    }
    
    // Construir ruta local
    final dataDir = await getAppDataDirectory();
    final localPath = path.join(dataDir.path, relativePath);
    
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

