import 'dart:convert';
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
import '../tables/evolution_chains.dart';
import '../tables/pokedex_entries.dart';
import '../tables/pokedex.dart';

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
  EvolutionChains,
  PokedexEntries,
  Pokedex,
])
class PokemonDao extends DatabaseAccessor<AppDatabase> with _$PokemonDaoMixin {
  PokemonDao(super.db);
  
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
    
    // Obtener los tipos usando los IDs de la tabla types (no apiId)
    final typeIds = pokemonTypeList.map((pt) => pt.typeId).toList();
    
    // Buscar los tipos por su ID (no apiId)
    final allTypes = await select(types).get();
    return allTypes.where((type) => typeIds.contains(type.id)).toList();
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
  
  /// Obtener la especie de un Pokémon
  Future<PokemonSpecy?> getSpeciesByPokemonId(int pokemonId) async {
    final pokemonData = await getPokemonById(pokemonId);
    if (pokemonData == null) return null;
    
    return await (select(pokemonSpecies)
      ..where((t) => t.id.equals(pokemonData.speciesId)))
      .getSingleOrNull();
  }
  
  /// Obtener estadísticas de un Pokémon (desde statsJson)
  /// Retorna un mapa: statName -> baseStat
  Map<String, int> getPokemonStats(PokemonData pokemon) {
    if (pokemon.statsJson == null || pokemon.statsJson!.isEmpty) {
      return {};
    }
    
    try {
      final statsData = jsonDecode(pokemon.statsJson!) as List;
      final Map<String, int> stats = {};
      
      for (final statEntry in statsData) {
        final stat = statEntry as Map<String, dynamic>;
        final statInfo = stat['stat'] as Map<String, dynamic>?;
        final baseStat = stat['base_stat'] as int?;
        
        if (statInfo != null && baseStat != null) {
          final statName = statInfo['name'] as String?;
          if (statName != null) {
            stats[statName] = baseStat;
          }
        }
      }
      
      return stats;
    } catch (e) {
      return {};
    }
  }
  
  /// Obtener todas las especies de una cadena evolutiva
  /// Extrae todas las especies relacionadas desde el JSON de la evolution chain
  Future<List<PokemonSpecy>> getSpeciesFromEvolutionChain(int evolutionChainApiId) async {
    try {
      // Obtener la evolution chain por apiId
      final evolutionChain = await (db.select(db.evolutionChains)
        ..where((t) => t.apiId.equals(evolutionChainApiId)))
        .getSingleOrNull();
      
      if (evolutionChain == null || evolutionChain.chainJson == null) {
        return [];
      }
      
      // Parsear el JSON de la cadena
      final chainData = jsonDecode(evolutionChain.chainJson!) as Map<String, dynamic>;
      final Set<String> speciesNames = {};
      
      // Función recursiva para extraer todas las especies de la cadena
      void extractSpeciesNames(Map<String, dynamic> chain) {
        final speciesInfo = chain['species'] as Map<String, dynamic>?;
        if (speciesInfo != null) {
          final speciesName = speciesInfo['name'] as String?;
          if (speciesName != null) {
            speciesNames.add(speciesName);
          }
        }
        
        final evolvesTo = chain['evolves_to'] as List?;
        if (evolvesTo != null) {
          for (final nextChain in evolvesTo) {
            extractSpeciesNames(nextChain as Map<String, dynamic>);
          }
        }
      }
      
      extractSpeciesNames(chainData);
      
      // Obtener todas las especies por nombre
      final List<PokemonSpecy> speciesList = [];
      for (final speciesName in speciesNames) {
        final species = await (select(pokemonSpecies)
          ..where((t) => t.name.equals(speciesName)))
          .getSingleOrNull();
        if (species != null) {
          speciesList.add(species);
        }
      }
      
      return speciesList;
    } catch (e) {
      return [];
    }
  }
  
  /// Obtener todas las especies relacionadas de una especie (a través de su evolution chain)
  Future<List<PokemonSpecy>> getRelatedSpecies(PokemonSpecy species) async {
    if (species.evolutionChainId == null) {
      return [];
    }
    
    // Obtener la evolution chain por apiId (evolutionChainId es el apiId, no el id de la tabla)
    return await getSpeciesFromEvolutionChain(species.evolutionChainId!);
  }
  
  /// Obtener todos los Pokémon de un tipo específico, ordenados por número de Pokédex nacional
  /// Retorna una lista de mapas con: pokemon, species, nationalEntryNumber
  Future<List<Map<String, dynamic>>> getPokemonByTypeOrderedByNational(int typeId) async {
    try {
      // Obtener la Pokédex nacional (apiId = 1)
      final nationalPokedex = await (db.select(db.pokedex)
        ..where((t) => t.apiId.equals(1)))
        .getSingleOrNull();
      
      if (nationalPokedex == null) {
        return [];
      }
      
      // Obtener todos los Pokémon que tienen este tipo
      final pokemonWithType = await (db.select(db.pokemonTypes)
        ..where((t) => t.typeId.equals(typeId)))
        .get();
      
      if (pokemonWithType.isEmpty) {
        return [];
      }
      
      final pokemonIds = pokemonWithType.map((pt) => pt.pokemonId).toSet().toList();
      
      // Obtener los Pokémon
      final pokemons = await (db.select(db.pokemon)
        ..where((t) => t.id.isIn(pokemonIds)))
        .get();
      
      // Obtener las entradas de la Pokédex nacional para estos Pokémon
      final nationalEntries = await (db.select(db.pokedexEntries)
        ..where((t) => 
          t.pokedexId.equals(nationalPokedex.id) &
          t.pokemonId.isIn(pokemonIds)))
        .get();
      
      // Crear un mapa: pokemonId -> entryNumber
      final entryNumberMap = <int, int>{};
      for (final entry in nationalEntries) {
        entryNumberMap[entry.pokemonId] = entry.entryNumber;
      }
      
      // Obtener las especies
      final speciesIds = pokemons.map((p) => p.speciesId).toSet().toList();
      final speciesList = await (db.select(db.pokemonSpecies)
        ..where((t) => t.id.isIn(speciesIds)))
        .get();
      
      final speciesMap = <int, PokemonSpecy>{};
      for (final species in speciesList) {
        speciesMap[species.id] = species;
      }
      
      // Crear la lista de resultados con número nacional
      final List<Map<String, dynamic>> result = [];
      for (final pokemon in pokemons) {
        final nationalEntryNumber = entryNumberMap[pokemon.id];
        if (nationalEntryNumber != null) {
          final species = speciesMap[pokemon.speciesId];
          if (species != null) {
            result.add({
              'pokemon': pokemon,
              'species': species,
              'nationalEntryNumber': nationalEntryNumber,
            });
          }
        }
      }
      
      // Ordenar por número nacional
      result.sort((a, b) => 
        (a['nationalEntryNumber'] as int).compareTo(b['nationalEntryNumber'] as int));
      
      return result;
    } catch (e) {
      return [];
    }
  }
}

