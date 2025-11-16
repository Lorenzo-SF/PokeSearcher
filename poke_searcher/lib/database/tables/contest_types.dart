import 'package:drift/drift.dart';

/// Tabla de tipos de concurso
class ContestTypes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get berryFlavorId => integer().nullable()();
  
  // JSON completo
  TextColumn get dataJson => text().nullable()();
}

