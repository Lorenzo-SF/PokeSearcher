import 'package:drift/drift.dart';

/// Tabla de máquinas (TMs/HMs)
class Machines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  IntColumn get itemId => integer().nullable()();
  IntColumn get moveId => integer().nullable()();
  IntColumn get versionGroupId => integer().nullable()();
  
  // JSON completo
  TextColumn get dataJson => text().nullable()();
}

