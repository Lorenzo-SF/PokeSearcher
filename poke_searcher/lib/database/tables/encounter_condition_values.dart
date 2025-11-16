import 'package:drift/drift.dart';

/// Tabla de valores de condiciones de encuentro
class EncounterConditionValues extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get conditionId => integer().nullable()();
  
  // JSON completo
  TextColumn get dataJson => text().nullable()();
}

