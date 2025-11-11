import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/abilities.dart';

part 'ability_dao.g.dart';

/// Data Access Object para operaciones con habilidades
@DriftAccessor(tables: [Abilities])
class AbilityDao extends DatabaseAccessor<AppDatabase> with _$AbilityDaoMixin {
  AbilityDao(AppDatabase db) : super(db);
  
  /// Obtener todas las habilidades
  Future<List<Ability>> getAllAbilities() async {
    return await select(abilities).get();
  }
  
  /// Obtener habilidad por ID
  Future<Ability?> getAbilityById(int id) async {
    return await (select(abilities)..where((t) => t.id.equals(id))).getSingleOrNull();
  }
  
  /// Obtener habilidad por API ID
  Future<Ability?> getAbilityByApiId(int apiId) async {
    return await (select(abilities)..where((t) => t.apiId.equals(apiId))).getSingleOrNull();
  }
  
  /// Obtener habilidad por nombre
  Future<Ability?> getAbilityByName(String name) async {
    return await (select(abilities)..where((t) => t.name.equals(name))).getSingleOrNull();
  }
  
  /// Buscar habilidades por nombre
  Future<List<Ability>> searchAbilities(String query) async {
    return await (select(abilities)
      ..where((t) => t.name.like('%$query%')))
      .get();
  }
}

