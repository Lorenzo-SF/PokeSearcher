import 'package:drift/drift.dart';

/// Tabla de Pokedex
class Pokedex extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  BoolColumn get isMainSeries => boolean().withDefault(const Constant(false))();
  IntColumn get regionId => integer().nullable()();
  
  // Color hexadecimal para la UI (tonos pastel)
  TextColumn get color => text().nullable()();
  
  // JSON para descripciones y entradas
  TextColumn get descriptionsJson => text().nullable()();
  TextColumn get pokemonEntriesJson => text().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

