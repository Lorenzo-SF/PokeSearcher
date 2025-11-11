import 'package:drift/drift.dart';

/// Tabla de formas de Pokémon
class PokemonShapes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  
  @override
  Set<Column> get primaryKey => {id};
}

