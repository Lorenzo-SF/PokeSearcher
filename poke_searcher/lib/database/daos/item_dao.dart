import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/items.dart';

part 'item_dao.g.dart';

/// Data Access Object para operaciones con items
@DriftAccessor(tables: [Items])
class ItemDao extends DatabaseAccessor<AppDatabase> with _$ItemDaoMixin {
  ItemDao(AppDatabase db) : super(db);
  
  /// Obtener todos los items
  Future<List<Item>> getAllItems() async {
    return await select(items).get();
  }
  
  /// Obtener item por ID
  Future<Item?> getItemById(int id) async {
    return await (select(items)..where((t) => t.id.equals(id))).getSingleOrNull();
  }
  
  /// Obtener item por API ID
  Future<Item?> getItemByApiId(int apiId) async {
    return await (select(items)..where((t) => t.apiId.equals(apiId))).getSingleOrNull();
  }
  
  /// Obtener item por nombre
  Future<Item?> getItemByName(String name) async {
    return await (select(items)..where((t) => t.name.equals(name))).getSingleOrNull();
  }
  
  /// Buscar items por nombre
  Future<List<Item>> searchItems(String query) async {
    return await (select(items)
      ..where((t) => t.name.like('%$query%')))
      .get();
  }
}

