import 'dart:convert';
import 'package:drift/drift.dart';
import '../../database/app_database.dart';

/// Mapper para convertir datos de API a entidades de base de datos (Regions)
class RegionMapper {
  static RegionsCompanion fromApiJson(Map<String, dynamic> json) {
    final id = json['id'] as int;
    final name = json['name'] as String;
    
    // Extraer main_generation ID
    int? mainGenerationId;
    if (json['main_generation'] != null) {
      final genUrl = (json['main_generation'] as Map<String, dynamic>)['url'] as String;
      final genId = _extractIdFromUrl(genUrl);
      mainGenerationId = genId;
    }
    
    return RegionsCompanion.insert(
      apiId: id,
      name: name,
      mainGenerationId: Value(mainGenerationId),
      locationsJson: Value(jsonEncode(json['locations'])),
      pokedexesJson: Value(jsonEncode(json['pokedexes'])),
      versionGroupsJson: Value(jsonEncode(json['version_groups'])),
    );
  }
  
  static int? _extractIdFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) {
        final lastSegment = segments.last;
        return int.tryParse(lastSegment);
      }
    } catch (e) {
      // Ignorar errores
    }
    return null;
  }
  
  /// Extraer nombres localizados y guardarlos en LocalizedNames
  static List<LocalizedNamesCompanion> extractLocalizedNames(
    Map<String, dynamic> json,
    int regionId,
  ) {
    final names = <LocalizedNamesCompanion>[];
    
    if (json['names'] != null) {
      final namesList = json['names'] as List;
      for (final nameEntry in namesList) {
        final nameMap = nameEntry as Map<String, dynamic>;
        final language = nameMap['language'] as Map<String, dynamic>;
        final languageName = language['name'] as String;
        final name = nameMap['name'] as String;
        
        // Necesitamos el languageId de la base de datos
        // Por ahora, guardamos el nombre del idioma y lo resolveremos después
        names.add(
          LocalizedNamesCompanion.insert(
            entityType: 'region',
            entityId: regionId,
            languageId: 0, // Se actualizará después con el ID real
            name: name,
          ),
        );
      }
    }
    
    return names;
  }
}

