import 'package:drift/drift.dart';

/// Tabla de sabores de bayas
class BerryFlavor extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get contestTypeId => integer().nullable()();
  
  // JSON completo
  TextColumn get dataJson => text().nullable()();
}

