import 'dart:convert';
import 'dart:ui' as ui;
import '../config/app_config.dart';
import '../../database/app_database.dart';
import '../../database/daos/language_dao.dart';

/// Servicio para obtener traducciones según el idioma configurado
class TranslationService {
  final AppDatabase database;
  final AppConfig appConfig;

  TranslationService({
    required this.database,
    required this.appConfig,
  });

  /// Obtener el ID del idioma configurado (o idioma del sistema por defecto)
  Future<int?> _getLanguageId() async {
    final languageCode = appConfig.language;
    
    // Si no hay idioma configurado o es "sistema", usar idioma del sistema
    if (languageCode == null || languageCode.isEmpty) {
      final languageDao = LanguageDao(database);
      
      // Obtener idioma del sistema
      final systemLocale = ui.PlatformDispatcher.instance.locale;
      final systemLanguageCode = systemLocale.languageCode;
      
      // Buscar idioma del sistema en la base de datos
      final systemLanguage = await languageDao.getLanguageByIso(systemLanguageCode);
      if (systemLanguage != null) {
        return systemLanguage.id;
      }
      
      // Si no se encuentra el idioma del sistema, usar inglés como fallback
      final english = await languageDao.getLanguageByIso('en');
      return english?.id;
    }
    
    // Buscar el idioma por código ISO
    final languageDao = LanguageDao(database);
    final language = await languageDao.getLanguageByIso(languageCode);
    
    if (language != null) {
      return language.id;
    }
    
    // Fallback a inglés
    final english = await languageDao.getLanguageByIso('en');
    return english?.id;
  }

  /// Obtener nombre localizado de una entidad
  /// Retorna el nombre en el idioma configurado, o en inglés si no existe
  Future<String> getLocalizedName({
    required String entityType,
    required int entityId,
    String? fallbackName,
  }) async {
    final languageDao = LanguageDao(database);
    final languageId = await _getLanguageId();
    
    if (languageId != null) {
      // Intentar obtener traducción en el idioma configurado
      final translatedName = await languageDao.getLocalizedName(
        entityType: entityType,
        entityId: entityId,
        languageId: languageId,
      );
      
      if (translatedName != null && translatedName.isNotEmpty) {
        return translatedName;
      }
    }
    
    // Si no hay traducción, intentar inglés
    final englishLanguage = await languageDao.getLanguageByIso('en');
    if (englishLanguage != null) {
      final englishName = await languageDao.getLocalizedName(
        entityType: entityType,
        entityId: entityId,
        languageId: englishLanguage.id,
      );
      
      if (englishName != null && englishName.isNotEmpty) {
        return englishName;
      }
    }
    
    // Fallback al nombre proporcionado o nombre genérico
    return fallbackName ?? 'Unknown';
  }

  /// Obtener descripción/flavor text en el idioma configurado
  /// Retorna la descripción en el idioma configurado, o en inglés si no existe
  Future<String?> getFlavorText({
    required String flavorTextEntriesJson,
  }) async {
    if (flavorTextEntriesJson.isEmpty) return null;
    
    try {
      final entries = jsonDecode(flavorTextEntriesJson) as List;
      if (entries.isEmpty) return null;
      
      final languageId = await _getLanguageId();
      final languageDao = LanguageDao(database);
      
      // Obtener el código del idioma configurado
      String? targetLanguageCode;
      if (languageId != null) {
        final language = await languageDao.getLanguageById(languageId);
        targetLanguageCode = language?.iso639 ?? language?.name;
      }
      
      // Si no hay idioma configurado, usar inglés
      if (targetLanguageCode == null || targetLanguageCode.isEmpty) {
        targetLanguageCode = 'en';
      }
      
      // Buscar la descripción más reciente en el idioma objetivo
      String? latestDescription;
      int? latestVersionGroupId;
      
      for (final entry in entries) {
        final entryMap = entry as Map<String, dynamic>;
        final language = entryMap['language'] as Map<String, dynamic>?;
        final version = entryMap['version'] as Map<String, dynamic>?;
        
        if (language != null) {
          final languageName = language['name'] as String?;
          
          // Verificar si coincide con el idioma objetivo
          if (languageName == targetLanguageCode || 
              languageName?.startsWith(targetLanguageCode) == true) {
            final flavorText = entryMap['flavor_text'] as String?;
            final versionGroupId = version != null 
                ? _extractIdFromUrl(version['url'] as String?) 
                : null;
            
            if (flavorText != null) {
              if (latestVersionGroupId == null || 
                  (versionGroupId != null && versionGroupId > latestVersionGroupId)) {
                latestDescription = flavorText.replaceAll('\n', ' ').replaceAll('\f', ' ');
                latestVersionGroupId = versionGroupId;
              }
            }
          }
        }
      }
      
      // Si no se encontró en el idioma objetivo, buscar en inglés
      if (latestDescription == null && targetLanguageCode != 'en') {
        for (final entry in entries) {
          final entryMap = entry as Map<String, dynamic>;
          final language = entryMap['language'] as Map<String, dynamic>?;
          final version = entryMap['version'] as Map<String, dynamic>?;
          
          if (language != null && language['name'] == 'en') {
            final flavorText = entryMap['flavor_text'] as String?;
            final versionGroupId = version != null 
                ? _extractIdFromUrl(version['url'] as String?) 
                : null;
            
            if (flavorText != null) {
              if (latestVersionGroupId == null || 
                  (versionGroupId != null && versionGroupId > latestVersionGroupId)) {
                latestDescription = flavorText.replaceAll('\n', ' ').replaceAll('\f', ' ');
                latestVersionGroupId = versionGroupId;
              }
            }
          }
        }
      }
      
      return latestDescription;
    } catch (e) {
      return null;
    }
  }

  /// Obtener genus (categoría) en el idioma configurado
  Future<String?> getGenus({
    required String generaJson,
  }) async {
    if (generaJson.isEmpty) return null;
    
    try {
      final genera = jsonDecode(generaJson) as List;
      if (genera.isEmpty) return null;
      
      final languageId = await _getLanguageId();
      final languageDao = LanguageDao(database);
      
      // Obtener el código del idioma configurado
      String? targetLanguageCode;
      if (languageId != null) {
        final language = await languageDao.getLanguageById(languageId);
        targetLanguageCode = language?.iso639 ?? language?.name;
      }
      
      // Si no hay idioma configurado, usar inglés
      if (targetLanguageCode == null || targetLanguageCode.isEmpty) {
        targetLanguageCode = 'en';
      }
      
      // Buscar el genus en el idioma objetivo
      for (final genusEntry in genera) {
        final genusMap = genusEntry as Map<String, dynamic>;
        final language = genusMap['language'] as Map<String, dynamic>?;
        
        if (language != null) {
          final languageName = language['name'] as String?;
          
          if (languageName == targetLanguageCode || 
              languageName?.startsWith(targetLanguageCode) == true) {
            return genusMap['genus'] as String?;
          }
        }
      }
      
      // Si no se encontró, buscar en inglés
      if (targetLanguageCode != 'en') {
        for (final genusEntry in genera) {
          final genusMap = genusEntry as Map<String, dynamic>;
          final language = genusMap['language'] as Map<String, dynamic>?;
          
          if (language != null && language['name'] == 'en') {
            return genusMap['genus'] as String?;
          }
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  int? _extractIdFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) {
        return int.tryParse(segments.last);
      }
    } catch (e) {
      // Ignorar errores
    }
    return null;
  }
}

