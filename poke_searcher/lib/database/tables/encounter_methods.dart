import 'package:drift/drift.dart';

/// Tabla de métodos de encuentro
class EncounterMethods extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get order => integer().nullable()();
  
  // JSON completo
  TextColumn get dataJson => text().nullable()();
}

