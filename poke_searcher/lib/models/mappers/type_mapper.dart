import 'dart:convert';
import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import '../api/api_named_resource.dart';

/// Mapper para convertir datos de API a entidades de base de datos (Types)
class TypeMapper {
  static TypesCompanion fromApiJson(Map<String, dynamic> json) {
    final id = json['id'] as int;
    final name = json['name'] as String;
    
    // Extraer generation ID
    int? generationId;
    if (json['generation'] != null) {
      final genUrl = (json['generation'] as Map<String, dynamic>)['url'] as String;
      generationId = _extractIdFromUrl(genUrl);
    }
    
    // Extraer move_damage_class ID
    int? moveDamageClassId;
    if (json['move_damage_class'] != null) {
      final damageClassUrl = (json['move_damage_class'] as Map<String, dynamic>)['url'] as String;
      moveDamageClassId = _extractIdFromUrl(damageClassUrl);
    }
    
    return TypesCompanion.insert(
      apiId: id,
      name: name,
      generationId: Value(generationId),
      moveDamageClassId: Value(moveDamageClassId),
      damageRelationsJson: Value(jsonEncode(json['damage_relations'])),
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
  
  /// Extraer relaciones de daño y guardarlas en TypeDamageRelations
  static List<TypeDamageRelationsCompanion> extractDamageRelations(
    Map<String, dynamic> json,
    int typeId,
  ) {
    final relations = <TypeDamageRelationsCompanion>[];
    
    if (json['damage_relations'] != null) {
      final damageRelations = json['damage_relations'] as Map<String, dynamic>;
      
      // double_damage_to
      if (damageRelations['double_damage_to'] != null) {
        final list = damageRelations['double_damage_to'] as List;
        for (final target in list) {
          final targetUrl = (target as Map<String, dynamic>)['url'] as String;
          final targetId = _extractIdFromUrl(targetUrl);
          if (targetId != null) {
            relations.add(
              TypeDamageRelationsCompanion.insert(
                attackingTypeId: typeId,
                defendingTypeId: targetId,
                relationType: 'double_damage_to',
              ),
            );
          }
        }
      }
      
      // half_damage_to
      if (damageRelations['half_damage_to'] != null) {
        final list = damageRelations['half_damage_to'] as List;
        for (final target in list) {
          final targetUrl = (target as Map<String, dynamic>)['url'] as String;
          final targetId = _extractIdFromUrl(targetUrl);
          if (targetId != null) {
            relations.add(
              TypeDamageRelationsCompanion.insert(
                attackingTypeId: typeId,
                defendingTypeId: targetId,
                relationType: 'half_damage_to',
              ),
            );
          }
        }
      }
      
      // no_damage_to
      if (damageRelations['no_damage_to'] != null) {
        final list = damageRelations['no_damage_to'] as List;
        for (final target in list) {
          final targetUrl = (target as Map<String, dynamic>)['url'] as String;
          final targetId = _extractIdFromUrl(targetUrl);
          if (targetId != null) {
            relations.add(
              TypeDamageRelationsCompanion.insert(
                attackingTypeId: typeId,
                defendingTypeId: targetId,
                relationType: 'no_damage_to',
              ),
            );
          }
        }
      }
      
      // double_damage_from
      if (damageRelations['double_damage_from'] != null) {
        final list = damageRelations['double_damage_from'] as List;
        for (final target in list) {
          final targetUrl = (target as Map<String, dynamic>)['url'] as String;
          final targetId = _extractIdFromUrl(targetUrl);
          if (targetId != null) {
            relations.add(
              TypeDamageRelationsCompanion.insert(
                attackingTypeId: targetId,
                defendingTypeId: typeId,
                relationType: 'double_damage_from',
              ),
            );
          }
        }
      }
      
      // half_damage_from
      if (damageRelations['half_damage_from'] != null) {
        final list = damageRelations['half_damage_from'] as List;
        for (final target in list) {
          final targetUrl = (target as Map<String, dynamic>)['url'] as String;
          final targetId = _extractIdFromUrl(targetUrl);
          if (targetId != null) {
            relations.add(
              TypeDamageRelationsCompanion.insert(
                attackingTypeId: targetId,
                defendingTypeId: typeId,
                relationType: 'half_damage_from',
              ),
            );
          }
        }
      }
      
      // no_damage_from
      if (damageRelations['no_damage_from'] != null) {
        final list = damageRelations['no_damage_from'] as List;
        for (final target in list) {
          final targetUrl = (target as Map<String, dynamic>)['url'] as String;
          final targetId = _extractIdFromUrl(targetUrl);
          if (targetId != null) {
            relations.add(
              TypeDamageRelationsCompanion.insert(
                attackingTypeId: targetId,
                defendingTypeId: typeId,
                relationType: 'no_damage_from',
              ),
            );
          }
        }
      }
    }
    
    return relations;
  }
}

