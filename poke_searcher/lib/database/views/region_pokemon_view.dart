import '../app_database.dart';
import '../daos/pokedex_dao.dart';
import '../daos/pokemon_dao.dart';

/// Vista helper para obtener pokemons de una región con su información de pokedex
/// Encapsula la lógica de selección de pokemon y número de entrada
class RegionPokemonView {
  final AppDatabase database;
  
  RegionPokemonView(this.database);
  
  /// Obtener todos los pokemons únicos de una región con su información de pokedex
  /// Retorna una lista de RegionPokemonItem ordenada por número de entrada
  /// 
  /// La lógica de selección:
  /// 1. Obtiene todas las pokedexes de la región ordenadas por tamaño (mayor a menor)
  /// 2. Para cada especie, busca el número de entrada en las pokedexes en orden
  /// 3. Usa el primer número encontrado (de la pokedex más grande)
  /// 4. Si no se encuentra, usa 0 como fallback
  /// 5. Ordena por ese número
  Future<List<RegionPokemonItem>> getPokemonByRegion(int regionId) async {
    final pokedexDao = PokedexDao(database);
    final pokemonDao = PokemonDao(database);
    
    // Obtener todas las pokedexes de la región ordenadas por tamaño (mayor a menor)
    final pokedexList = await pokedexDao.getPokedexByRegionOrderedBySize(regionId);
    
    // Obtener pokemons únicos de la región
    final uniquePokemon = await pokedexDao.getUniquePokemonByRegion(regionId);
    
    // OPTIMIZACIÓN: Cargar todas las entradas de pokedex de una vez
    final Map<int, Map<int, int>> pokedexEntriesMap = {}; // pokedexId -> {pokemonId: entryNumber}
    for (final pokedex in pokedexList) {
      final entries = await pokedexDao.getPokedexEntries(pokedex.id);
      pokedexEntriesMap[pokedex.id] = {
        for (var entry in entries) entry.pokemonId: entry.entryNumber
      };
    }
    
    // OPTIMIZACIÓN: Obtener todos los pokemons default de las especies de una vez
    final speciesIds = uniquePokemon.keys.toList();
    final allDefaultPokemons = await Future.wait(
      speciesIds.map((speciesId) async {
        final pokemons = await pokemonDao.getPokemonBySpecies(speciesId);
        return pokemons.isNotEmpty ? pokemons.first : null;
      }),
    );
    
    // Crear mapa de speciesId -> pokemon default
    final Map<int, PokemonData?> speciesToPokemonMap = {};
    for (int i = 0; i < speciesIds.length; i++) {
      speciesToPokemonMap[speciesIds[i]] = allDefaultPokemons[i];
    }
    
    // OPTIMIZACIÓN: Obtener todos los tipos de una vez
    final pokemonIds = allDefaultPokemons.whereType<PokemonData>().map((p) => p.id).toList();
    final Map<int, List<Type>> pokemonTypesMap = {};
    if (pokemonIds.isNotEmpty) {
      await Future.wait(
        pokemonIds.map((pokemonId) async {
          final types = await pokemonDao.getPokemonTypes(pokemonId);
          pokemonTypesMap[pokemonId] = types;
        }),
      );
    }
    
    final List<RegionPokemonItem> pokemonList = [];
    
    for (final entry in uniquePokemon.values) {
      final species = entry['species'] as PokemonSpecy;
      
      // Implementar coalesce: buscar número de entrada en pokedex ordenadas por tamaño
      int? orderNumber;
      PokedexData? usedPokedex;
      
      final defaultPokemon = speciesToPokemonMap[species.id];
      if (defaultPokemon != null) {
        for (final pokedex in pokedexList) {
          final entriesMap = pokedexEntriesMap[pokedex.id];
          if (entriesMap != null && entriesMap.containsKey(defaultPokemon.id)) {
            orderNumber = entriesMap[defaultPokemon.id];
            usedPokedex = pokedex;
            break; // Usar el primero encontrado (pokedex más grande)
          }
        }
      }
      
      // Si no se encontró en ninguna pokedex de la región, usar 0 como fallback
      if (orderNumber == null) {
        orderNumber = 0;
      }
      
      // Obtener tipos del pokemon
      final types = defaultPokemon != null 
          ? (pokemonTypesMap[defaultPokemon.id] ?? [])
          : <Type>[];
      
      pokemonList.add(RegionPokemonItem(
        species: species,
        pokemon: defaultPokemon,
        orderNumber: orderNumber,
        usedPokedex: usedPokedex,
        types: types,
      ));
    }
    
    // Ordenar por el número de orden (coalesce)
    pokemonList.sort((a, b) => a.orderNumber.compareTo(b.orderNumber));
    
    return pokemonList;
  }
  
  /// Obtener pokemons de la pokedex nacional
  /// Similar a getPokemonByRegion pero solo usa la pokedex nacional
  Future<List<RegionPokemonItem>> getPokemonByNationalPokedex() async {
    final pokedexDao = PokedexDao(database);
    final pokemonDao = PokemonDao(database);
    
    // Obtener la pokedex nacional
    final nationalPokedex = await pokedexDao.getNationalPokedex();
    if (nationalPokedex == null) {
      return [];
    }
    
    // Obtener todas las entradas de la pokedex nacional
    final entries = await pokedexDao.getPokedexEntries(nationalPokedex.id);
    
    final List<RegionPokemonItem> pokemonList = [];
    
    for (final entry in entries) {
      final pokemon = await pokemonDao.getPokemonById(entry.pokemonId);
      if (pokemon == null) continue;
      
      final species = await (database.select(database.pokemonSpecies)
        ..where((t) => t.id.equals(pokemon.speciesId)))
        .getSingleOrNull();
      
      if (species == null) continue;
      
      // Obtener tipos del pokemon
      final types = await pokemonDao.getPokemonTypes(pokemon.id);
      
      pokemonList.add(RegionPokemonItem(
        species: species,
        pokemon: pokemon,
        orderNumber: entry.entryNumber,
        usedPokedex: nationalPokedex,
        types: types,
      ));
    }
    
    // Ordenar por número de entrada
    pokemonList.sort((a, b) => a.orderNumber.compareTo(b.orderNumber));
    
    return pokemonList;
  }
  
  /// Obtener los pokemons iniciales de una región
  Future<List<RegionPokemonItem>> getStarterPokemon(int regionId) async {
    final pokedexDao = PokedexDao(database);
    final pokemonDao = PokemonDao(database);
    
    // Obtener las especies iniciales
    final starterSpecies = await pokedexDao.getStarterPokemon(regionId);
    
    final List<RegionPokemonItem> starters = [];
    
    for (final species in starterSpecies) {
      final pokemons = await pokemonDao.getPokemonBySpecies(species.id);
      if (pokemons.isEmpty) continue;
      
      final pokemon = pokemons.first;
      
      // Obtener tipos del pokemon
      final types = await pokemonDao.getPokemonTypes(pokemon.id);
      
      // Obtener número de entrada en la pokedex nacional (si existe)
      final nationalEntryNumber = await pokedexDao.getNationalEntryNumber(species.id);
      
      starters.add(RegionPokemonItem(
        species: species,
        pokemon: pokemon,
        orderNumber: nationalEntryNumber ?? 0,
        usedPokedex: null, // Los iniciales no necesitan pokedex específica
        types: types,
      ));
    }
    
    // Ordenar por número nacional
    starters.sort((a, b) => a.orderNumber.compareTo(b.orderNumber));
    
    return starters;
  }
}

/// Item que representa un pokemon en una región con su información de pokedex
class RegionPokemonItem {
  final PokemonSpecy species;
  final PokemonData? pokemon;
  final int orderNumber; // Número de entrada usado para ordenar
  final PokedexData? usedPokedex; // Pokedex de la que se tomó el número
  final List<Type> types;
  
  RegionPokemonItem({
    required this.species,
    required this.pokemon,
    required this.orderNumber,
    required this.usedPokedex,
    required this.types,
  });
}

