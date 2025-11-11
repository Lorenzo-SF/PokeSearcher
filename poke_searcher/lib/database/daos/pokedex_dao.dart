import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/pokedex.dart';
import '../tables/pokedex_entries.dart';
import '../tables/pokemon_species.dart';

part 'pokedex_dao.g.dart';

/// Data Access Object para operaciones con Pokedex
@DriftAccessor(tables: [Pokedex, PokedexEntries, PokemonSpecies])
class PokedexDao extends DatabaseAccessor<AppDatabase> with _$PokedexDaoMixin {
  PokedexDao(AppDatabase db) : super(db);
  
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
  
  /// Obtener los 3 Pokémon iniciales de una región (primeros 3 del pokedex principal)
  Future<List<PokemonSpecy>> getStarterPokemon(int regionId) async {
    // Obtener el pokedex principal de la región
    final pokedexList = await getPokedexByRegion(regionId);
    if (pokedexList.isEmpty) {
      return [];
    }
    
    // Tomar el primer pokedex (asumiendo que es el principal)
    final mainPokedex = pokedexList.first;
    
    // Obtener las primeras 3 entradas
    final entries = await (select(pokedexEntries)
      ..where((t) => t.pokedexId.equals(mainPokedex.id))
      ..orderBy([(t) => OrderingTerm(expression: t.entryNumber)])
      ..limit(3))
      .get();
    
    if (entries.isEmpty) {
      return [];
    }
    
    final speciesIds = entries.map((e) => e.pokemonSpeciesId).toList();
    return await (select(pokemonSpecies)
      ..where((t) => t.id.isIn(speciesIds)))
      .get();
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
}

