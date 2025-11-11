import 'package:drift/drift.dart';

/// Tabla de tasas de crecimiento
class GrowthRates extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  TextColumn get formula => text().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

