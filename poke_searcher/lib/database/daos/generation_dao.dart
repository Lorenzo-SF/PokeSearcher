import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/generations.dart';

part 'generation_dao.g.dart';

/// Data Access Object para operaciones con Generaciones
@DriftAccessor(tables: [Generations])
class GenerationDao extends DatabaseAccessor<AppDatabase> with _$GenerationDaoMixin {
  GenerationDao(super.db);
  
  /// Obtener todas las generaciones
  Future<List<Generation>> getAllGenerations() async {
    return await (select(generations)
      ..orderBy([(t) => OrderingTerm(expression: t.apiId)]))
      .get();
  }
  
  /// Obtener generación por ID
  Future<Generation?> getGenerationById(int id) async {
    return await (select(generations)
      ..where((t) => t.id.equals(id)))
      .getSingleOrNull();
  }
  
  /// Obtener generación por API ID
  Future<Generation?> getGenerationByApiId(int apiId) async {
    return await (select(generations)
      ..where((t) => t.apiId.equals(apiId)))
      .getSingleOrNull();
  }
}

