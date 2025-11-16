import 'package:drift/drift.dart';

/// Tabla de métodos de aprendizaje de movimientos
class MoveLearnMethods extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  
  // JSON completo
  TextColumn get dataJson => text().nullable()();
}

