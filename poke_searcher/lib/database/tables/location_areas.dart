import 'package:drift/drift.dart';

/// Tabla de áreas de ubicación
class LocationAreas extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get locationId => integer().nullable()();
  IntColumn get gameIndex => integer().nullable()();
  
  // JSON completo
  TextColumn get dataJson => text().nullable()();
}

