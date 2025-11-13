import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/pokedex.dart';
import '../tables/pokedex_entries.dart';
import '../tables/pokemon_species.dart';
import '../tables/regions.dart';
import '../../utils/starter_pokemon.dart';

part 'pokedex_dao.g.dart';

/// Data Access Object para operaciones con Pokedex
@DriftAccessor(tables: [Pokedex, PokedexEntries, PokemonSpecies, Regions])
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
  Future<List<PokemonSpecy>> getSpeciesInPokedex(int pokedexId) async {
    final query = select(pokedexEntries)
      ..where((t) => t.pokedexId.equals(pokedexId));
    
    final entries = await query.get();
    
    if (entries.isEmpty) {
      return [];
    }
    
    final speciesIds = entries.map((e) => e.pokemonSpeciesId).toList();
    return await (select(pokemonSpecies)
      ..where((t) => t.id.isIn(speciesIds)))
      .get();
  }
  
  /// Obtener los 3 Pokémon iniciales de una región usando la lista fija
  /// Si la región no tiene iniciales definidos o no se encuentran en la DB, retorna lista vacía
  Future<List<PokemonSpecy>> getStarterPokemon(int regionId) async {
    // Obtener el nombre de la región
    final region = await (select(regions)
      ..where((t) => t.id.equals(regionId)))
      .getSingleOrNull();
    
    if (region == null) {
      return [];
    }
    
    // Obtener los nombres de los iniciales para esta región
    final starterNames = StarterPokemon.getStartersForRegion(region.name);
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
  Future<Map<int, Map<String, dynamic>>> getUniquePokemonByRegion(int regionId) async {
    // Obtener todas las pokedexes de la región
    final pokedexList = await getPokedexByRegion(regionId);
    if (pokedexList.isEmpty) {
      return {};
    }
    
    final Map<int, Map<String, dynamic>> result = {};
    
    // Para cada pokedex, obtener sus entradas
    for (final pokedex in pokedexList) {
      final entries = await getPokedexEntries(pokedex.id);
      
      for (final entry in entries) {
        final speciesId = entry.pokemonSpeciesId;
        
        // Si no existe, crear entrada
        if (!result.containsKey(speciesId)) {
          // Obtener la especie
          final species = await (select(pokemonSpecies)
            ..where((t) => t.id.equals(speciesId)))
            .getSingleOrNull();
          
          if (species != null) {
            result[speciesId] = {
              'species': species,
              'pokedexNumbers': [],
            };
          }
        }
        
        // Añadir número de pokedex
        if (result.containsKey(speciesId)) {
          result[speciesId]!['pokedexNumbers'].add({
            'pokedexId': pokedex.id,
            'pokedexApiId': pokedex.apiId,
            'entryNumber': entry.entryNumber,
            'color': pokedex.color,
          });
        }
      }
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
}

