import 'package:drift/drift.dart';

/// Relación entre Pokedex y Pokemon Species
class PokedexEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get pokedexId => integer()();
  IntColumn get pokemonSpeciesId => integer()();
  IntColumn get entryNumber => integer()();
  
  @override
  Set<Column> get primaryKey => {id};
  
  @override
  List<Set<Column>> get uniqueKeys => [
    {pokedexId, pokemonSpeciesId}
  ];
}

