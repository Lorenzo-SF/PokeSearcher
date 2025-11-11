import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Gestor de almacenamiento de archivos multimedia
class MediaStorage {
  static Directory? _mediaDirectory;
  
  /// Obtener el directorio de almacenamiento multimedia
  static Future<Directory> getMediaDirectory() async {
    if (_mediaDirectory != null) {
      return _mediaDirectory!;
    }
    
    final appDir = await getApplicationDocumentsDirectory();
    _mediaDirectory = Directory(p.join(appDir.path, 'media'));
    
    if (!await _mediaDirectory!.exists()) {
      await _mediaDirectory!.create(recursive: true);
    }
    
    return _mediaDirectory!;
  }
  
  /// Obtener la ruta completa para un archivo multimedia
  static Future<String> getMediaPath(String url) async {
    final mediaDir = await getMediaDirectory();
    final uri = Uri.parse(url);
    final fileName = p.basename(uri.path);
    
    // Crear subdirectorios basados en el tipo de media
    String subDir = 'general';
    if (url.contains('/sprites/')) {
      subDir = 'sprites';
    } else if (url.contains('/cries/')) {
      subDir = 'cries';
    } else if (url.contains('/artwork/')) {
      subDir = 'artwork';
    }
    
    final subDirectory = Directory(p.join(mediaDir.path, subDir));
    if (!await subDirectory.exists()) {
      await subDirectory.create(recursive: true);
    }
    
    return p.join(subDirectory.path, fileName);
  }
  
  /// Guardar archivo multimedia
  static Future<File> saveMediaFile(String url, List<int> bytes) async {
    final filePath = await getMediaPath(url);
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    return file;
  }
  
  /// Verificar si un archivo multimedia existe localmente
  static Future<bool> mediaFileExists(String url) async {
    try {
      final filePath = await getMediaPath(url);
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }
  
  /// Obtener el archivo local si existe
  static Future<File?> getMediaFile(String url) async {
    final filePath = await getMediaPath(url);
    final file = File(filePath);
    if (await file.exists()) {
      return file;
    }
    return null;
  }
  
  /// Limpiar archivos multimedia (útil para liberar espacio)
  static Future<void> clearMedia() async {
    final mediaDir = await getMediaDirectory();
    if (await mediaDir.exists()) {
      await mediaDir.delete(recursive: true);
      await mediaDir.create(recursive: true);
    }
  }
  
  /// Obtener el tamaño total de los archivos multimedia
  static Future<int> getMediaSize() async {
    try {
      final mediaDir = await getMediaDirectory();
      if (!await mediaDir.exists()) {
        return 0;
      }
      
      int totalSize = 0;
      await for (final entity in mediaDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      
      return totalSize;
    } catch (e) {
      return 0;
    }
  }
}

