import 'package:drift/drift.dart';

/// Tabla de objetos/items
class Items extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get cost => integer().nullable()();
  IntColumn get flingPower => integer().nullable()();
  IntColumn get categoryId => integer().nullable()();
  IntColumn get flingEffectId => integer().nullable()();
  
  // JSON completo para evitar múltiples joins en inserts
  TextColumn get fullDataJson => text().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

