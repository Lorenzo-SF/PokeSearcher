import 'package:drift/drift.dart';

/// Tabla de efectos de super concurso
class SuperContestEffects extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  IntColumn get appeal => integer().nullable()();
  
  // JSON completo
  TextColumn get dataJson => text().nullable()();
}

