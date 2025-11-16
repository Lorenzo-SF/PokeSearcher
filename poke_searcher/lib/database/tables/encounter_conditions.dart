import 'package:drift/drift.dart';

/// Tabla de condiciones de encuentro
class EncounterConditions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  
  // JSON completo
  TextColumn get dataJson => text().nullable()();
}

