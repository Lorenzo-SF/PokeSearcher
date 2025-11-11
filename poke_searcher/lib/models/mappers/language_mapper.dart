import 'dart:convert';
import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import '../api/api_named_resource.dart';

/// Mapper para convertir datos de API a entidades de base de datos (Languages)
class LanguageMapper {
  static LanguagesCompanion fromApiJson(Map<String, dynamic> json) {
    final id = json['id'] as int;
    final name = json['name'] as String;
    final officialName = json['official'] as bool? ?? false 
        ? json['name'] as String 
        : null;
    
    return LanguagesCompanion.insert(
      apiId: id,
      name: name,
      officialName: Value(officialName),
      iso639: Value(json['iso639'] as String?),
      iso3166: Value(json['iso3166'] as String?),
    );
  }
}

