import 'package:drift/drift.dart';

/// Tabla de categorías de items
class ItemCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get pocketId => integer().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

