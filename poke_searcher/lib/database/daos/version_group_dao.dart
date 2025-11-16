import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/version_groups.dart';

part 'version_group_dao.g.dart';

/// Data Access Object para operaciones con Version Groups
@DriftAccessor(tables: [VersionGroups])
class VersionGroupDao extends DatabaseAccessor<AppDatabase> with _$VersionGroupDaoMixin {
  VersionGroupDao(super.db);
  
  /// Obtener todos los version groups
  Future<List<VersionGroup>> getAllVersionGroups() async {
    return await (select(versionGroups)
      ..orderBy([(t) => OrderingTerm(expression: t.order, mode: OrderingMode.asc)]))
      .get();
  }
  
  /// Obtener version groups por generación
  Future<List<VersionGroup>> getVersionGroupsByGeneration(int generationId) async {
    return await (select(versionGroups)
      ..where((t) => t.generationId.equals(generationId))
      ..orderBy([(t) => OrderingTerm(expression: t.order, mode: OrderingMode.asc)]))
      .get();
  }
  
  /// Obtener version group por ID
  Future<VersionGroup?> getVersionGroupById(int id) async {
    return await (select(versionGroups)
      ..where((t) => t.id.equals(id)))
      .getSingleOrNull();
  }
  
  /// Obtener version group por API ID
  Future<VersionGroup?> getVersionGroupByApiId(int apiId) async {
    return await (select(versionGroups)
      ..where((t) => t.apiId.equals(apiId)))
      .getSingleOrNull();
  }
}

