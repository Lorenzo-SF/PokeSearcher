import '../app_database.dart';
import '../daos/pokemon_dao.dart';
import 'region_pokemon_view.dart';

/// Vista helper para obtener listados de pokemons con filtros
/// Encapsula la lógica de filtrado por región, tipo y búsqueda
class PokemonListView {
  final AppDatabase database;
  final RegionPokemonView regionView;
  
  PokemonListView(this.database) : regionView = RegionPokemonView(database);
  
  /// Obtener pokemons filtrados
  /// 
  /// Parámetros:
  /// - regionId: ID de la región (null para pokedex nacional)
  /// - typeId: ID del tipo para filtrar (null para no filtrar por tipo)
  /// - nameFilter: Texto para filtrar por nombre (null o vacío para no filtrar)
  /// 
  /// Retorna una lista de PokemonListItem ordenada
  Future<List<PokemonListItem>> getFilteredPokemon({
    int? regionId,
    int? typeId,
    String? nameFilter,
  }) async {
    List<PokemonListItem> pokemonList;
    
    // Si hay filtro por tipo, usar lógica especial
    if (typeId != null) {
      pokemonList = await _getPokemonByType(typeId);
    } else if (regionId == null) {
      // Pokedex Nacional
      pokemonList = await _getPokemonByNationalPokedex();
    } else {
      // Región normal
      pokemonList = await _getPokemonByRegion(regionId);
    }
    
    // Aplicar filtro por nombre si existe
    if (nameFilter != null && nameFilter.isNotEmpty) {
      final filterLower = nameFilter.toLowerCase().trim();
      pokemonList = pokemonList.where((item) {
        return item.species.name.toLowerCase().contains(filterLower);
      }).toList();
    }
    
    return pokemonList;
  }
  
  /// Obtener pokemons por tipo
  Future<List<PokemonListItem>> _getPokemonByType(int typeId) async {
    final pokemonDao = PokemonDao(database);
    
    final pokemonByType = await pokemonDao.getPokemonByTypeOrderedByNational(typeId);
    
    final List<PokemonListItem> pokemonList = [];
    
    for (final entry in pokemonByType) {
      final pokemon = entry['pokemon'] as PokemonData;
      final species = entry['species'] as PokemonSpecy;
      final nationalEntryNumber = entry['nationalEntryNumber'] as int;
      
      // Obtener tipos del pokemon
      final types = await pokemonDao.getPokemonTypes(pokemon.id);
      
      pokemonList.add(PokemonListItem(
        species: species,
        pokemon: pokemon,
        orderNumber: nationalEntryNumber,
        usedPokedex: null, // No aplica para filtro por tipo
        types: types,
      ));
    }
    
    return pokemonList;
  }
  
  /// Obtener pokemons de la pokedex nacional
  Future<List<PokemonListItem>> _getPokemonByNationalPokedex() async {
    final regionItems = await regionView.getPokemonByNationalPokedex();
    
    return regionItems.map((item) => PokemonListItem(
      species: item.species,
      pokemon: item.pokemon,
      orderNumber: item.orderNumber,
      usedPokedex: item.usedPokedex,
      types: item.types,
    )).toList();
  }
  
  /// Obtener pokemons de una región
  Future<List<PokemonListItem>> _getPokemonByRegion(int regionId) async {
    final regionItems = await regionView.getPokemonByRegion(regionId);
    
    return regionItems.map((item) => PokemonListItem(
      species: item.species,
      pokemon: item.pokemon,
      orderNumber: item.orderNumber,
      usedPokedex: item.usedPokedex,
      types: item.types,
    )).toList();
  }
  
  /// Obtener pokemons con filtros múltiples (tipo1 y tipo2)
  /// 
  /// Si ambos tipos están presentes, busca pokemons que tengan ambos tipos (en cualquier orden)
  /// Si solo uno está presente, busca pokemons que tengan ese tipo
  Future<List<PokemonListItem>> getFilteredPokemonByTypes({
    int? regionId,
    int? type1Id,
    int? type2Id,
    String? nameFilter,
  }) async {
    // Primero obtener la lista base
    List<PokemonListItem> pokemonList = await getFilteredPokemon(
      regionId: regionId,
      nameFilter: nameFilter,
    );
    
    // Aplicar filtros por tipo
    if (type1Id != null || type2Id != null) {
      pokemonList = pokemonList.where((item) {
        final typeIds = item.types.map((t) => t.id).toList();
        
        if (type1Id != null && type2Id != null) {
          // Ambos tipos deben estar presentes (en cualquier orden)
          return typeIds.contains(type1Id) && typeIds.contains(type2Id);
        } else if (type1Id != null) {
          // Solo tipo 1
          return typeIds.contains(type1Id);
        } else if (type2Id != null) {
          // Solo tipo 2
          return typeIds.contains(type2Id);
        }
        
        return true;
      }).toList();
    }
    
    return pokemonList;
  }
}

/// Item que representa un pokemon en un listado con su información
class PokemonListItem {
  final PokemonSpecy species;
  final PokemonData? pokemon;
  final int orderNumber; // Número de entrada usado para ordenar
  final PokedexData? usedPokedex; // Pokedex de la que se tomó el número
  final List<Type> types;
  
  PokemonListItem({
    required this.species,
    required this.pokemon,
    required this.orderNumber,
    required this.usedPokedex,
    required this.types,
  });
}

