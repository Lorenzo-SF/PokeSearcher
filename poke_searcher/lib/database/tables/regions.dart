import 'package:drift/drift.dart';

/// Tabla de regiones de Pokémon
class Regions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get mainGenerationId => integer().nullable()();
  
  // JSON para almacenar datos complejos sin normalizar
  TextColumn get locationsJson => text().nullable()();
  TextColumn get pokedexesJson => text().nullable()();
  TextColumn get versionGroupsJson => text().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

