import 'package:drift/drift.dart';

/// Tabla de versiones de juegos
class Versions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get versionGroupId => integer().nullable()();
  
  // JSON completo
  TextColumn get dataJson => text().nullable()();
}

