import 'package:drift/drift.dart';

/// Tabla de grupos de versiones de juegos
class VersionGroups extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get generationId => integer().nullable()();
  IntColumn get order => integer().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

