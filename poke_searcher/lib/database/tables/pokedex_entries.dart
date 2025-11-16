import 'package:drift/drift.dart';

/// Relación entre Pokedex y Pokemon (específicos, no especies)
/// Permite asignar pokemons específicos (ej: slowpoke vs slowpoke-galar) a diferentes pokedexes
class PokedexEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get pokedexId => integer()();
  IntColumn get pokemonId => integer()(); // Pokemon específico (no especie)
  IntColumn get entryNumber => integer()();
  
  @override
  Set<Column> get primaryKey => {id};
  
  @override
  List<Set<Column>> get uniqueKeys => [
    {pokedexId, pokemonId}
  ];
}

