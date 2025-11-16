import 'dart:convert';
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/pokedex.dart';
import '../tables/pokedex_entries.dart';
import '../tables/pokemon_species.dart';
import '../tables/pokemon.dart';
import '../tables/regions.dart';
import '../../utils/starter_pokemon.dart';

part 'pokedex_dao.g.dart';

/// Data Access Object para operaciones con Pokedex
@DriftAccessor(tables: [Pokedex, PokedexEntries, PokemonSpecies, Pokemon, Regions])
class PokedexDao extends DatabaseAccessor<AppDatabase> with _$PokedexDaoMixin {
  PokedexDao(super.db);
  
  /// Obtener todos los pokedex
  Future<List<PokedexData>> getAllPokedex() async {
    return await select(pokedex).get();
  }
  
  /// Obtener pokedex por ID
  Future<PokedexData?> getPokedexById(int id) async {
    return await (select(pokedex)..where((t) => t.id.equals(id))).getSingleOrNull();
  }
  
  /// Obtener pokedex por API ID
  Future<PokedexData?> getPokedexByApiId(int apiId) async {
    return await (select(pokedex)..where((t) => t.apiId.equals(apiId))).getSingleOrNull();
  }
  
  /// Obtener pokedex por región
  Future<List<PokedexData>> getPokedexByRegion(int regionId) async {
    return await (select(pokedex)
      ..where((t) => t.regionId.equals(regionId)))
      .get();
  }
  
  /// Obtener entradas de pokedex
  Future<List<PokedexEntry>> getPokedexEntries(int pokedexId) async {
    return await (select(pokedexEntries)
      ..where((t) => t.pokedexId.equals(pokedexId))
      ..orderBy([(t) => OrderingTerm(expression: t.entryNumber)]))
      .get();
  }
  
  /// Obtener especies de Pokémon en un pokedex
  /// Ahora usa pokemonId en lugar de pokemonSpeciesId
  Future<List<PokemonSpecy>> getSpeciesInPokedex(int pokedexId) async {
    final query = select(pokedexEntries)
      ..where((t) => t.pokedexId.equals(pokedexId));
    
    final entries = await query.get();
    
    if (entries.isEmpty) {
      return [];
    }
    
    // Obtener pokemons y luego sus especies
    final pokemonIds = entries.map((e) => e.pokemonId).toList();
    final pokemons = await (select(pokemon)
      ..where((t) => t.id.isIn(pokemonIds)))
      .get();
    
    final speciesIds = pokemons.map((p) => p.speciesId).toSet().toList();
    return await (select(pokemonSpecies)
      ..where((t) => t.id.isIn(speciesIds)))
      .get();
  }
  
  /// Obtener los Pokémon iniciales de una región desde processed_starters_json
  /// Si la región no tiene iniciales definidos o no se encuentran en la DB, retorna lista vacía
  Future<List<PokemonSpecy>> getStarterPokemon(int regionId) async {
    // Obtener la región
    final region = await (select(regions)
      ..where((t) => t.id.equals(regionId)))
      .getSingleOrNull();
    
    if (region == null) {
      return [];
    }
    
    // Obtener los nombres de los iniciales desde processed_starters_json
    List<String> starterNames = [];
    if (region.processedStartersJson != null && region.processedStartersJson!.isNotEmpty) {
      try {
        final startersData = jsonDecode(region.processedStartersJson!) as List;
        starterNames = startersData
            .map((item) => item.toString())
            .where((name) => name.isNotEmpty)
            .toList();
      } catch (e) {
        print('[PokedexDao] ⚠️ Error parseando processed_starters_json para región ${region.name}: $e');
        // Fallback a la lista fija si hay error parseando
        starterNames = StarterPokemon.getStartersForRegion(region.name);
      }
    } else {
      // Fallback a la lista fija si no hay processed_starters_json
      starterNames = StarterPokemon.getStartersForRegion(region.name);
    }
    
    if (starterNames.isEmpty) {
      return [];
    }
    
    // Buscar las especies por nombre
    final List<PokemonSpecy> starters = [];
    for (final starterName in starterNames) {
      final species = await (select(pokemonSpecies)
        ..where((t) => t.name.equals(starterName)))
        .getSingleOrNull();
      
      if (species != null) {
        starters.add(species);
      }
    }
    
    return starters;
  }
  
  /// Obtener todos los pokemons únicos de una región con sus números de pokedex
  /// Retorna un mapa: speciesId -> {species, pokedexNumbers: [{pokedexId, entryNumber, color}]}
  /// Ahora usa pokemonId en lugar de pokemonSpeciesId
  /// OPTIMIZADO: Evita N+1 queries cargando todos los pokemons y especies de una vez
  Future<Map<int, Map<String, dynamic>>> getUniquePokemonByRegion(int regionId) async {
    // Obtener todas las pokedexes de la región
    final pokedexList = await getPokedexByRegion(regionId);
    if (pokedexList.isEmpty) {
      return {};
    }
    
    // OPTIMIZACIÓN: Cargar todas las entradas de todas las pokedexes de una vez
    final List<PokedexEntry> allEntries = [];
    for (final pokedex in pokedexList) {
      final entries = await getPokedexEntries(pokedex.id);
      allEntries.addAll(entries);
    }
    
    if (allEntries.isEmpty) {
      return {};
    }
    
    // OPTIMIZACIÓN: Cargar todos los pokemons de una vez
    final pokemonIds = allEntries.map((e) => e.pokemonId).toSet().toList();
    final allPokemons = await (select(pokemon)
      ..where((t) => t.id.isIn(pokemonIds)))
      .get();
    
    // Crear mapa de pokemonId -> pokemon
    final pokemonMap = {for (var p in allPokemons) p.id: p};
    
    // OPTIMIZACIÓN: Cargar todas las especies de una vez
    final speciesIds = allPokemons.map((p) => p.speciesId).toSet().toList();
    final allSpecies = await (select(pokemonSpecies)
      ..where((t) => t.id.isIn(speciesIds)))
      .get();
    
    // Crear mapa de speciesId -> species
    final speciesMap = {for (var s in allSpecies) s.id: s};
    
    // Construir resultado
    final Map<int, Map<String, dynamic>> result = {};
    
    for (final entry in allEntries) {
      final pokemonData = pokemonMap[entry.pokemonId];
      if (pokemonData == null) continue;
      
      final speciesId = pokemonData.speciesId;
      final species = speciesMap[speciesId];
      if (species == null) continue;
      
      // Obtener la pokedex correspondiente
      final pokedex = pokedexList.firstWhere(
        (p) => p.id == entry.pokedexId,
        orElse: () => pokedexList.first,
      );
      
      // Si no existe, crear entrada
      if (!result.containsKey(speciesId)) {
        result[speciesId] = {
          'species': species,
          'pokedexNumbers': [],
        };
      }
      
      // Añadir número de pokedex
      result[speciesId]!['pokedexNumbers'].add({
        'pokedexId': pokedex.id,
        'pokedexApiId': pokedex.apiId,
        'entryNumber': entry.entryNumber,
        'color': pokedex.color,
      });
    }
    
    // Ordenar números de pokedex por pokedexId
    for (final entry in result.values) {
      final numbers = entry['pokedexNumbers'] as List;
      numbers.sort((a, b) => (a['pokedexId'] as int).compareTo(b['pokedexId'] as int));
    }
    
    return result;
  }
  
  /// Obtener el conteo de pokemons únicos de una región
  Future<int> getUniquePokemonCountByRegion(int regionId) async {
    final uniquePokemon = await getUniquePokemonByRegion(regionId);
    return uniquePokemon.length;
  }
  
  /// Obtener la pokedex nacional (sin región)
  Future<PokedexData?> getNationalPokedex() async {
    return await (select(pokedex)
      ..where((t) => t.regionId.isNull()))
      .getSingleOrNull();
  }
  
  /// Obtener todas las pokedex de una región ordenadas por tamaño (mayor a menor)
  Future<List<PokedexData>> getPokedexByRegionOrderedBySize(int regionId) async {
    final pokedexList = await getPokedexByRegion(regionId);
    
    // Obtener el tamaño de cada pokedex
    final List<Map<String, dynamic>> pokedexWithSize = [];
    for (final pokedex in pokedexList) {
      final entries = await getPokedexEntries(pokedex.id);
      pokedexWithSize.add({
        'pokedex': pokedex,
        'size': entries.length,
      });
    }
    
    // Ordenar por tamaño (mayor a menor)
    pokedexWithSize.sort((a, b) => (b['size'] as int).compareTo(a['size'] as int));
    
    return pokedexWithSize.map((item) => item['pokedex'] as PokedexData).toList();
  }
  
  /// Obtener el número de entrada de un pokemon en una pokedex específica
  /// Ahora busca por pokemonId (necesita obtener el pokemon default de la especie)
  Future<int?> getEntryNumberForPokemon(int pokedexId, int speciesId) async {
    // Obtener el pokemon default de la especie
    final defaultPokemon = await (select(pokemon)
      ..where((t) => t.speciesId.equals(speciesId) & t.isDefault.equals(true)))
      .getSingleOrNull();
    
    if (defaultPokemon == null) return null;
    
    final entry = await (select(pokedexEntries)
      ..where((t) => t.pokedexId.equals(pokedexId) & t.pokemonId.equals(defaultPokemon.id)))
      .getSingleOrNull();
    return entry?.entryNumber;
  }
  
  /// Obtener el número de entrada de un pokemon en la pokedex nacional
  Future<int?> getNationalEntryNumber(int speciesId) async {
    final nationalPokedex = await getNationalPokedex();
    if (nationalPokedex == null) return null;
    return await getEntryNumberForPokemon(nationalPokedex.id, speciesId);
  }
}

