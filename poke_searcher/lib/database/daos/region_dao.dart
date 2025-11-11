import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/regions.dart';
import '../tables/localized_names.dart';
import '../tables/pokedex.dart';

part 'region_dao.g.dart';

/// Data Access Object para operaciones con regiones
@DriftAccessor(tables: [Regions, LocalizedNames, Pokedex])
class RegionDao extends DatabaseAccessor<AppDatabase> with _$RegionDaoMixin {
  RegionDao(AppDatabase db) : super(db);
  
  /// Obtener todas las regiones
  Future<List<Region>> getAllRegions() async {
    return await select(regions).get();
  }
  
  /// Obtener región por ID
  Future<Region?> getRegionById(int id) async {
    return await (select(regions)..where((t) => t.id.equals(id))).getSingleOrNull();
  }
  
  /// Obtener región por API ID
  Future<Region?> getRegionByApiId(int apiId) async {
    return await (select(regions)..where((t) => t.apiId.equals(apiId))).getSingleOrNull();
  }
  
  /// Obtener región por nombre
  Future<Region?> getRegionByName(String name) async {
    return await (select(regions)..where((t) => t.name.equals(name))).getSingleOrNull();
  }
  
  /// Obtener nombre localizado de una región
  Future<String?> getLocalizedName({
    required int regionId,
    required int languageId,
  }) async {
    final query = select(localizedNames)
      ..where((t) => 
        t.entityType.equals('region') &
        t.entityId.equals(regionId) &
        t.languageId.equals(languageId));
    
    final result = await query.getSingleOrNull();
    return result?.name;
  }
  
  /// Buscar regiones por nombre (búsqueda parcial)
  Future<List<Region>> searchRegions(String query) async {
    return await (select(regions)
      ..where((t) => t.name.like('%$query%')))
      .get();
  }
  
  /// Obtener contador de pokedex por región
  Future<int> getPokedexCount(int regionId) async {
    final query = select(pokedex)
      ..where((t) => t.regionId.equals(regionId));
    
    final results = await query.get();
    return results.length;
  }
}

