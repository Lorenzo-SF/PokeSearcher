import 'package:drift/drift.dart';
import '../../database/app_database.dart';

/// Mapper para convertir datos de API a entidades de base de datos (Languages)
class LanguageMapper {
  static LanguagesCompanion fromApiJson(Map<String, dynamic> json) {
    final id = json['id'] as int;
    final name = json['name'] as String;
    
    // Extraer el nombre del idioma en su propio idioma desde el array "names"
    // Buscar el nombre donde language.name coincide con el name del idioma
    String? officialName;
    if (json['names'] != null) {
      final names = json['names'] as List;
      for (final nameEntry in names) {
        final nameData = nameEntry as Map<String, dynamic>;
        final languageInfo = nameData['language'] as Map<String, dynamic>?;
        if (languageInfo != null) {
          final languageName = languageInfo['name'] as String?;
          // Si el language.name coincide con el name del idioma, ese es su nombre en su propio idioma
          if (languageName == name) {
            officialName = nameData['name'] as String?;
            break;
          }
        }
      }
    }
    
    return LanguagesCompanion.insert(
      apiId: id,
      name: name,
      officialName: Value(officialName),
      iso639: Value(json['iso639'] as String?),
      iso3166: Value(json['iso3166'] as String?),
    );
  }
}

