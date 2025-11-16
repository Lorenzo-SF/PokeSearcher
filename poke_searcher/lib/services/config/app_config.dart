import 'package:shared_preferences/shared_preferences.dart';

/// Servicio de configuración de la aplicación
class AppConfig {
  static const String _keyLanguage = 'app_language';
  static const String _keyTheme = 'app_theme';
  static const String _keyInitialDownloadCompleted = 'initial_download_completed';
  static const String _keyDataVersion = 'data_version';
  static const String _keyTypeImageGenerationId = 'type_image_generation_id';
  static const String _keyTypeImageVersionGroupId = 'type_image_version_group_id';
  
  final SharedPreferences _prefs;
  
  AppConfig(this._prefs);
  
  /// Obtener instancia de AppConfig
  static Future<AppConfig> getInstance() async {
    final prefs = await SharedPreferences.getInstance();
    return AppConfig(prefs);
  }
  
  /// Idioma seleccionado (código ISO, ej: 'en', 'es', 'fr')
  String? get language {
    return _prefs.getString(_keyLanguage);
  }
  
  Future<bool> setLanguage(String languageCode) {
    return _prefs.setString(_keyLanguage, languageCode);
  }
  
  /// Tema seleccionado ('light', 'dark', 'system')
  String get theme {
    return _prefs.getString(_keyTheme) ?? 'system';
  }
  
  Future<bool> setTheme(String theme) {
    return _prefs.setString(_keyTheme, theme);
  }
  
  /// Indica si la descarga inicial fue completada
  bool get initialDownloadCompleted {
    return _prefs.getBool(_keyInitialDownloadCompleted) ?? false;
  }
  
  Future<bool> setInitialDownloadCompleted(bool completed) {
    return _prefs.setBool(_keyInitialDownloadCompleted, completed);
  }
  
  /// Versión de los datos descargados
  String? get dataVersion {
    return _prefs.getString(_keyDataVersion);
  }
  
  Future<bool> setDataVersion(String version) {
    return _prefs.setString(_keyDataVersion, version);
  }
  
  /// ID de generación seleccionada para imágenes de tipos
  int? get typeImageGenerationId {
    final value = _prefs.getInt(_keyTypeImageGenerationId);
    return value;
  }
  
  Future<bool> setTypeImageGenerationId(int? generationId) {
    if (generationId == null) {
      return _prefs.remove(_keyTypeImageGenerationId);
    }
    return _prefs.setInt(_keyTypeImageGenerationId, generationId);
  }
  
  /// ID de version-group seleccionado para imágenes de tipos
  int? get typeImageVersionGroupId {
    final value = _prefs.getInt(_keyTypeImageVersionGroupId);
    return value;
  }
  
  Future<bool> setTypeImageVersionGroupId(int? versionGroupId) {
    if (versionGroupId == null) {
      return _prefs.remove(_keyTypeImageVersionGroupId);
    }
    return _prefs.setInt(_keyTypeImageVersionGroupId, versionGroupId);
  }
  
  /// Limpiar toda la configuración
  Future<bool> clear() {
    return _prefs.clear();
  }
}

