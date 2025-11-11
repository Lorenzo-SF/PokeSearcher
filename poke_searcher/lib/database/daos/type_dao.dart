import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/types.dart';
import '../tables/type_damage_relations.dart';

part 'type_dao.g.dart';

/// Data Access Object para operaciones con tipos
@DriftAccessor(tables: [Types, TypeDamageRelations])
class TypeDao extends DatabaseAccessor<AppDatabase> with _$TypeDaoMixin {
  TypeDao(AppDatabase db) : super(db);
  
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

