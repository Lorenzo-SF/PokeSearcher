import 'package:drift/drift.dart';

/// Tabla de efectos de lanzamiento de items
class ItemFlingEffects extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  
  // JSON completo
  TextColumn get dataJson => text().nullable()();
}

