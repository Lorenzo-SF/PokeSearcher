import 'package:drift/drift.dart';

/// Tabla de generaciones de Pokémon
class Generations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get mainRegionId => integer().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

