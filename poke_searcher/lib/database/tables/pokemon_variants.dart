import 'package:drift/drift.dart';

/// Tabla para relacionar pokemon con sus variantes
class PokemonVariants extends Table {
  IntColumn get pokemonId => integer()(); // Pokemon default
  IntColumn get variantPokemonId => integer()(); // Pokemon variante
  
  @override
  Set<Column> get primaryKey => {pokemonId, variantPokemonId};
}

