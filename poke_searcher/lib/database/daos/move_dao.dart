import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/moves.dart';

part 'move_dao.g.dart';

/// Data Access Object para operaciones con movimientos
@DriftAccessor(tables: [Moves])
class MoveDao extends DatabaseAccessor<AppDatabase> with _$MoveDaoMixin {
  MoveDao(AppDatabase db) : super(db);
  
  /// Obtener todos los movimientos
  Future<List<Move>> getAllMoves() async {
    return await select(moves).get();
  }
  
  /// Obtener movimiento por ID
  Future<Move?> getMoveById(int id) async {
    return await (select(moves)..where((t) => t.id.equals(id))).getSingleOrNull();
  }
  
  /// Obtener movimiento por API ID
  Future<Move?> getMoveByApiId(int apiId) async {
    return await (select(moves)..where((t) => t.apiId.equals(apiId))).getSingleOrNull();
  }
  
  /// Obtener movimiento por nombre
  Future<Move?> getMoveByName(String name) async {
    return await (select(moves)..where((t) => t.name.equals(name))).getSingleOrNull();
  }
  
  /// Buscar movimientos por nombre
  Future<List<Move>> searchMoves(String query) async {
    return await (select(moves)
      ..where((t) => t.name.like('%$query%')))
      .get();
  }
  
  /// Obtener movimientos por tipo
  Future<List<Move>> getMovesByType(int typeId) async {
    return await (select(moves)
      ..where((t) => t.typeId.equals(typeId)))
      .get();
  }
}

