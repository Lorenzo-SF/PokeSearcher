import 'package:drift/drift.dart';

/// Tabla de ubicaciones
class Locations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get regionId => integer().nullable()();
  
  // JSON completo
  TextColumn get dataJson => text().nullable()();
}

