import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/pokemon.dart';
import '../tables/pokemon_species.dart';
import '../tables/pokemon_types.dart';
import '../tables/types.dart';
import '../tables/pokemon_abilities.dart';
import '../tables/abilities.dart';
import '../tables/pokemon_moves.dart';
import '../tables/moves.dart';

part 'pokemon_dao.g.dart';

/// Data Access Object para operaciones con Pokémon
@DriftAccessor(tables: [
  Pokemon,
  PokemonSpecies,
  PokemonTypes,
  Types,
  PokemonAbilities,
  Abilities,
  PokemonMoves,
  Moves,
])
class PokemonDao extends DatabaseAccessor<AppDatabase> with _$PokemonDaoMixin {
  PokemonDao(AppDatabase db) : super(db);
  
  /// Obtener Pokémon por ID
  Future<PokemonData?> getPokemonById(int id) async {
    return await (select(pokemon)..where((t) => t.id.equals(id))).getSingleOrNull();
  }
  
  /// Obtener Pokémon por API ID
  Future<PokemonData?> getPokemonByApiId(int apiId) async {
    return await (select(pokemon)..where((t) => t.apiId.equals(apiId))).getSingleOrNull();
  }
  
  /// Obtener Pokémon por nombre
  Future<PokemonData?> getPokemonByName(String name) async {
    return await (select(pokemon)..where((t) => t.name.equals(name))).getSingleOrNull();
  }
  
  /// Obtener todos los Pokémon de una especie
  Future<List<PokemonData>> getPokemonBySpecies(int speciesId) async {
    return await (select(pokemon)
      ..where((t) => t.speciesId.equals(speciesId)))
      .get();
  }
  
  /// Obtener tipos de un Pokémon
  Future<List<Type>> getPokemonTypes(int pokemonId) async {
    final query = select(pokemonTypes)
      ..where((t) => t.pokemonId.equals(pokemonId))
      ..orderBy([(t) => OrderingTerm(expression: t.slot)]);
    
    final pokemonTypeList = await query.get();
    
    if (pokemonTypeList.isEmpty) {
      return [];
    }
    
    final typeIds = pokemonTypeList.map((pt) => pt.typeId).toList();
    return await (select(types)..where((t) => t.apiId.isIn(typeIds))).get();
  }
  
  /// Obtener habilidades de un Pokémon
  Future<List<Ability>> getPokemonAbilities(int pokemonId) async {
    final query = select(pokemonAbilities)
      ..where((t) => t.pokemonId.equals(pokemonId));
    
    final pokemonAbilityList = await query.get();
    
    if (pokemonAbilityList.isEmpty) {
      return [];
    }
    
    final abilityIds = pokemonAbilityList.map((pa) => pa.abilityId).toList();
    return await (select(abilities)..where((t) => t.apiId.isIn(abilityIds))).get();
  }
  
  /// Obtener movimientos de un Pokémon
  Future<List<Move>> getPokemonMoves(int pokemonId) async {
    final query = select(pokemonMoves)
      ..where((t) => t.pokemonId.equals(pokemonId));
    
    final pokemonMoveList = await query.get();
    
    if (pokemonMoveList.isEmpty) {
      return [];
    }
    
    final moveIds = pokemonMoveList.map((pm) => pm.moveId).toList();
    return await (select(moves)..where((t) => t.apiId.isIn(moveIds))).get();
  }
  
  /// Buscar Pokémon por nombre
  Future<List<PokemonData>> searchPokemon(String query) async {
    return await (select(pokemon)
      ..where((t) => t.name.like('%$query%')))
      .get();
  }
}

