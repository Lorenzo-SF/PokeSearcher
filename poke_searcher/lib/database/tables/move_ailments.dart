import 'package:drift/drift.dart';

/// Tabla de aflicciones de movimientos
class MoveAilments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  
  // JSON completo
  TextColumn get dataJson => text().nullable()();
}

