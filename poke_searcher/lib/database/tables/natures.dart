import 'package:drift/drift.dart';

/// Tabla de naturalezas
class Natures extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get decreasedStatId => integer().nullable()();
  IntColumn get increasedStatId => integer().nullable()();
  IntColumn get hatesFlavorId => integer().nullable()();
  IntColumn get likesFlavorId => integer().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

