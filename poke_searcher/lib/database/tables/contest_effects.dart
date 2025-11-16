import 'package:drift/drift.dart';

/// Tabla de efectos de concurso
class ContestEffects extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  IntColumn get appeal => integer().nullable()();
  IntColumn get jam => integer().nullable()();
  
  // JSON completo
  TextColumn get dataJson => text().nullable()();
}

