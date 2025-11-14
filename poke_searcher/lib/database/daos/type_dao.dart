import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/types.dart';
import '../tables/type_damage_relations.dart';

part 'type_dao.g.dart';

/// Data Access Object para operaciones con tipos
@DriftAccessor(tables: [Types, TypeDamageRelations])
class TypeDao extends DatabaseAccessor<AppDatabase> with _$TypeDaoMixin {
  TypeDao(super.db);
  
  /// Obtener todos los tipos
  Future<List<Type>> getAllTypes() async {
    return await select(types).get();
  }
  
  /// Obtener tipo por ID
  Future<Type?> getTypeById(int id) async {
    return await (select(types)..where((t) => t.id.equals(id))).getSingleOrNull();
  }
  
  /// Obtener tipo por API ID
  Future<Type?> getTypeByApiId(int apiId) async {
    return await (select(types)..where((t) => t.apiId.equals(apiId))).getSingleOrNull();
  }
  
  /// Obtener tipo por nombre
  Future<Type?> getTypeByName(String name) async {
    return await (select(types)..where((t) => t.name.equals(name))).getSingleOrNull();
  }
  
  /// Obtener relaciones de daño de un tipo
  Future<List<TypeDamageRelation>> getDamageRelations(int typeId) async {
    return await (select(typeDamageRelations)
      ..where((t) => 
        t.attackingTypeId.equals(typeId) | 
        t.defendingTypeId.equals(typeId)))
      .get();
  }
  
  /// Obtener tipos que reciben doble daño de este tipo (super efectivo)
  Future<List<Type>> getDoubleDamageTo(int typeId) async {
    final relations = await (select(typeDamageRelations)
      ..where((t) => 
        t.attackingTypeId.equals(typeId) &
        t.relationType.equals('double_damage_to')))
      .get();
    
    if (relations.isEmpty) return [];
    
    final defendingTypeIds = relations.map((r) => r.defendingTypeId).toList();
    return await (select(types)..where((t) => t.id.isIn(defendingTypeIds))).get();
  }
  
  /// Obtener tipos que reciben medio daño de este tipo (no muy efectivo)
  Future<List<Type>> getHalfDamageTo(int typeId) async {
    final relations = await (select(typeDamageRelations)
      ..where((t) => 
        t.attackingTypeId.equals(typeId) &
        t.relationType.equals('half_damage_to')))
      .get();
    
    if (relations.isEmpty) return [];
    
    final defendingTypeIds = relations.map((r) => r.defendingTypeId).toList();
    return await (select(types)..where((t) => t.id.isIn(defendingTypeIds))).get();
  }
  
  /// Obtener tipos que no reciben daño de este tipo (sin efecto)
  Future<List<Type>> getNoDamageTo(int typeId) async {
    final relations = await (select(typeDamageRelations)
      ..where((t) => 
        t.attackingTypeId.equals(typeId) &
        t.relationType.equals('no_damage_to')))
      .get();
    
    if (relations.isEmpty) return [];
    
    final defendingTypeIds = relations.map((r) => r.defendingTypeId).toList();
    return await (select(types)..where((t) => t.id.isIn(defendingTypeIds))).get();
  }
  
  /// Obtener tipos que hacen doble daño a este tipo (débil contra)
  Future<List<Type>> getDoubleDamageFrom(int typeId) async {
    final relations = await (select(typeDamageRelations)
      ..where((t) => 
        t.defendingTypeId.equals(typeId) &
        t.relationType.equals('double_damage_from')))
      .get();
    
    if (relations.isEmpty) return [];
    
    final attackingTypeIds = relations.map((r) => r.attackingTypeId).toList();
    return await (select(types)..where((t) => t.id.isIn(attackingTypeIds))).get();
  }
  
  /// Obtener tipos que hacen medio daño a este tipo (resistente a)
  Future<List<Type>> getHalfDamageFrom(int typeId) async {
    final relations = await (select(typeDamageRelations)
      ..where((t) => 
        t.defendingTypeId.equals(typeId) &
        t.relationType.equals('half_damage_from')))
      .get();
    
    if (relations.isEmpty) return [];
    
    final attackingTypeIds = relations.map((r) => r.attackingTypeId).toList();
    return await (select(types)..where((t) => t.id.isIn(attackingTypeIds))).get();
  }
  
  /// Obtener tipos que no hacen daño a este tipo (inmune a)
  Future<List<Type>> getNoDamageFrom(int typeId) async {
    final relations = await (select(typeDamageRelations)
      ..where((t) => 
        t.defendingTypeId.equals(typeId) &
        t.relationType.equals('no_damage_from')))
      .get();
    
    if (relations.isEmpty) return [];
    
    final attackingTypeIds = relations.map((r) => r.attackingTypeId).toList();
    return await (select(types)..where((t) => t.id.isIn(attackingTypeIds))).get();
  }
  
  /// Obtener efectividad de un tipo contra otro
  Future<double> getEffectiveness({
    required int attackingTypeId,
    required int defendingTypeId,
  }) async {
    // Buscar relaciones
    final relations = await (select(typeDamageRelations)
      ..where((t) => 
        t.attackingTypeId.equals(attackingTypeId) &
        t.defendingTypeId.equals(defendingTypeId)))
      .get();
    
    double effectiveness = 1.0;
    
    for (final relation in relations) {
      switch (relation.relationType) {
        case 'double_damage_to':
          effectiveness *= 2.0;
          break;
        case 'half_damage_to':
          effectiveness *= 0.5;
          break;
        case 'no_damage_to':
          effectiveness = 0.0;
          break;
        default:
          break;
      }
    }
    
    return effectiveness;
  }
}

