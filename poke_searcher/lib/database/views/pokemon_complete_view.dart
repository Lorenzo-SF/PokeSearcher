import '../app_database.dart';
import '../daos/pokemon_dao.dart';
import '../daos/pokemon_variants_dao.dart';
import '../daos/pokedex_dao.dart';
import '../../services/translation/translation_service.dart';
import '../../services/config/app_config.dart';

/// Vista helper para obtener toda la información de un pokemon
/// Encapsula la lógica de carga de datos del pokemon, incluyendo:
/// - Datos básicos (pokemon, especie, tipos, stats)
/// - Habilidades y movimientos
/// - Evoluciones y variantes
/// - Información traducida (nombre, genus, descripción)
/// - Números de pokedex
class PokemonCompleteView {
  final AppDatabase database;
  final AppConfig appConfig;
  late final TranslationService translationService;
  
  PokemonCompleteView(this.database, this.appConfig) {
    translationService = TranslationService(
      database: database,
      appConfig: appConfig,
    );
  }
  
  /// Cargar toda la información de un pokemon
  Future<PokemonCompleteData?> getPokemonData(int pokemonId, {int? pokedexId}) async {
    final pokemonDao = PokemonDao(database);
    final variantsDao = PokemonVariantsDao(database);
    final pokedexDao = PokedexDao(database);
    
    // Obtener pokemon
    final pokemon = await pokemonDao.getPokemonById(pokemonId);
    if (pokemon == null) {
      return null;
    }
    
    // Obtener especie
    final species = await pokemonDao.getSpeciesByPokemonId(pokemonId);
    if (species == null) {
      return null;
    }
    
    // Obtener tipos
    final types = await pokemonDao.getPokemonTypes(pokemon.id);
    
    // Obtener estadísticas
    final stats = pokemonDao.getPokemonStats(pokemon);
    
    // Obtener habilidades
    final abilities = await pokemonDao.getPokemonAbilities(pokemon.id);
    
    // Obtener movimientos
    final moves = await pokemonDao.getPokemonMoves(pokemon.id);
    
    // Obtener tipos y clases de daño de los movimientos
    // OPTIMIZACIÓN: Cargar todos los tipos y clases de daño UNA VEZ antes del loop
    final Map<int, Type?> moveTypes = {};
    final Map<int, String?> moveDamageClasses = {};
    
    if (moves.isNotEmpty) {
      // Cargar todos los tipos y clases de daño de una vez
      final allTypes = await database.select(database.types).get();
      final allDamageClasses = await database.select(database.moveDamageClasses).get();
      
      // Crear mapas para búsqueda rápida
      final typesMap = {for (var t in allTypes) t.id: t};
      final damageClassesMap = {for (var dc in allDamageClasses) dc.id: dc};
      
      for (final move in moves) {
        // Obtener tipo del movimiento
        if (move.typeId != null) {
          moveTypes[move.id] = typesMap[move.typeId];
        }
        
        // Obtener clase de daño del movimiento
        if (move.damageClassId != null) {
          final damageClass = damageClassesMap[move.damageClassId];
          moveDamageClasses[move.id] = damageClass?.name;
        }
      }
    }
    
    // Obtener nombre traducido del pokemon
    final pokemonName = await translationService.getLocalizedName(
      entityType: 'pokemon-species',
      entityId: species.id,
      fallbackName: species.name,
    );
    
    // Obtener genus y descripción traducidos
    String? genus;
    String? description;
    
    if (species.generaJson != null && species.generaJson!.isNotEmpty) {
      genus = await translationService.getGenus(
        generaJson: species.generaJson!,
      );
    }
    
    if (species.flavorTextEntriesJson != null && 
        species.flavorTextEntriesJson!.isNotEmpty) {
      description = await translationService.getFlavorText(
        flavorTextEntriesJson: species.flavorTextEntriesJson!,
      );
    }
    
    // Obtener evoluciones
    final evolutions = await _loadEvolutions(species, pokemonDao);
    
    // Obtener variantes normales (con pokedex) - solo del pokemon actual
    final variants = <PokemonData>[];
    final specialVariants = <PokemonData>[]; // mega, gigamax, primal sin pokedex
    
    // OPTIMIZACIÓN: Cargar todas las entradas de pokedex de una vez
    final allPokedex = await pokedexDao.getAllPokedex();
    final Map<int, Set<int>> pokedexEntriesMap = {}; // pokedexId -> Set<pokemonId>
    for (final pokedex in allPokedex) {
      final entries = await pokedexDao.getPokedexEntries(pokedex.id);
      pokedexEntriesMap[pokedex.id] = entries.map((e) => e.pokemonId).toSet();
    }
    
    // Función helper para verificar si un pokemon tiene pokedex
    bool hasPokedexEntry(int pokemonId) {
      for (final entries in pokedexEntriesMap.values) {
        if (entries.contains(pokemonId)) {
          return true;
        }
      }
      return false;
    }
    
    final variantRelations = await variantsDao.getVariantsForPokemon(pokemon.id);
    if (variantRelations.isNotEmpty) {
      final variantIds = variantRelations.map((v) => v.variantPokemonId).toList();
      
      // OPTIMIZACIÓN: Cargar todos los pokemons de una vez
      final variantPokemons = await Future.wait(
        variantIds.map((id) => pokemonDao.getPokemonById(id)),
      );
      
      for (final variant in variantPokemons) {
        if (variant == null) continue;
        
        if (hasPokedexEntry(variant.id)) {
          variants.add(variant);
        } else if (_isSpecialVariant(variant.name)) {
          specialVariants.add(variant);
        }
      }
    }
    
    // También verificar si este pokemon es una variante de otro
    final defaultId = await variantsDao.getDefaultPokemonId(pokemon.id);
    if (defaultId != null && defaultId != pokemon.id) {
      final defaultPokemon = await pokemonDao.getPokemonById(defaultId);
      if (defaultPokemon != null) {
        // Cargar todas las variantes del pokemon default
        final allVariants = await variantsDao.getVariantsForPokemon(defaultId);
        final variantIds = allVariants.map((v) => v.variantPokemonId).toList();
        variantIds.add(defaultId);
        
        // OPTIMIZACIÓN: Cargar todos los pokemons de una vez
        final variantPokemons = await Future.wait(
          variantIds.where((id) => id != pokemon.id).map((id) => pokemonDao.getPokemonById(id)),
        );
        
        for (final variant in variantPokemons) {
          if (variant == null) continue;
          
          if (hasPokedexEntry(variant.id)) {
            variants.add(variant);
          } else if (_isSpecialVariant(variant.name)) {
            specialVariants.add(variant);
          }
        }
      }
    }
    
    // Cargar variantes de TODA la gama evolutiva
    final allEvolutionVariants = await _loadAllEvolutionVariants(
      species,
      pokemonDao,
      variantsDao,
      pokedexDao,
    );
    
    // Obtener números de pokedex
    int? pokedexEntryNumber;
    int? nationalEntryNumber;
    
    // Número en la pokedex usada para ordenar
    if (pokedexId != null) {
      pokedexEntryNumber = await pokedexDao.getEntryNumberForPokemon(
        pokedexId,
        species.id,
      );
    }
    
    // Número en la pokedex nacional
    nationalEntryNumber = await pokedexDao.getNationalEntryNumber(species.id);
    
    return PokemonCompleteData(
      pokemon: pokemon,
      species: species,
      types: types,
      stats: stats,
      abilities: abilities,
      moves: moves,
      moveTypes: moveTypes,
      moveDamageClasses: moveDamageClasses,
      evolutions: evolutions,
      variants: variants,
      specialVariants: specialVariants,
      allEvolutionVariants: allEvolutionVariants,
      pokemonName: pokemonName,
      genus: genus,
      description: description,
      pokedexEntryNumber: pokedexEntryNumber,
      nationalEntryNumber: nationalEntryNumber,
    );
  }
  
  /// Cargar evoluciones usando la evolution chain de la especie
  Future<List<PokemonData>> _loadEvolutions(
    PokemonSpecy species,
    PokemonDao pokemonDao,
  ) async {
    if (species.evolutionChainId == null) return [];
    
    try {
      // Obtener todas las especies relacionadas de la evolution chain
      final relatedSpecies = await pokemonDao.getRelatedSpecies(species);
      
      // Obtener el pokemon default de cada especie relacionada (excluyendo la actual)
      final List<PokemonData> evolutions = [];
      
      for (final relatedSpecy in relatedSpecies) {
        if (relatedSpecy.id == species.id) continue; // Excluir la especie actual
        
        // Obtener el pokemon default de esta especie
        final pokemons = await pokemonDao.getPokemonBySpecies(relatedSpecy.id);
        if (pokemons.isEmpty) continue;
        
        final defaultPokemon = pokemons.firstWhere(
          (p) => p.isDefault,
          orElse: () => pokemons.first,
        );
        
        evolutions.add(defaultPokemon);
      }
      
      return evolutions;
    } catch (e) {
      return [];
    }
  }
  
  /// Cargar TODAS las variantes (con y sin pokedex) de TODA la gama evolutiva
  Future<List<PokemonData>> _loadAllEvolutionVariants(
    PokemonSpecy species,
    PokemonDao pokemonDao,
    PokemonVariantsDao variantsDao,
    PokedexDao pokedexDao,
  ) async {
    final List<PokemonData> allVariants = [];
    
    try {
      if (species.evolutionChainId == null) {
        return allVariants;
      }
      
      // Obtener todas las especies relacionadas de la evolution chain
      final relatedSpecies = await pokemonDao.getRelatedSpecies(species);
      
      // Para cada especie relacionada, buscar TODAS sus variantes
      final Set<int> addedVariantIds = {}; // Para evitar duplicados
      
      // OPTIMIZACIÓN: Cargar todas las entradas de pokedex de una vez
      final allPokedex = await pokedexDao.getAllPokedex();
      final Map<int, Set<int>> pokedexEntriesMap = {}; // pokedexId -> Set<pokemonId>
      for (final pokedex in allPokedex) {
        final entries = await pokedexDao.getPokedexEntries(pokedex.id);
        pokedexEntriesMap[pokedex.id] = entries.map((e) => e.pokemonId).toSet();
      }
      
      // Función helper para verificar si un pokemon tiene pokedex
      bool hasPokedexEntry(int pokemonId) {
        for (final entries in pokedexEntriesMap.values) {
          if (entries.contains(pokemonId)) {
            return true;
          }
        }
        return false;
      }
      
      for (final relatedSpecy in relatedSpecies) {
        // Obtener todos los pokemons de esta especie (incluyendo el default)
        final allSpeciesPokemons = await pokemonDao.getPokemonBySpecies(relatedSpecy.id);
        if (allSpeciesPokemons.isEmpty) continue;
        
        final defaultPokemon = allSpeciesPokemons.firstWhere(
          (p) => p.isDefault,
          orElse: () => allSpeciesPokemons.first,
        );
        
        // Obtener variantes del pokemon default
        final variantRelations = await variantsDao.getVariantsForPokemon(defaultPokemon.id);
        
        // Verificar si alguna variante tiene pokedex
        final Set<int> variantsWithPokedex = {};
        
        for (final variantRelation in variantRelations) {
          final variantId = variantRelation.variantPokemonId;
          if (hasPokedexEntry(variantId)) {
            variantsWithPokedex.add(variantId);
          }
        }
        
        // Si hay variantes con pokedex, solo añadir el default
        // Si no hay variantes con pokedex, añadir todas
        if (variantsWithPokedex.isNotEmpty) {
          // Solo añadir el default si no está ya añadido
          if (!addedVariantIds.contains(defaultPokemon.id)) {
            allVariants.add(defaultPokemon);
            addedVariantIds.add(defaultPokemon.id);
          }
        } else {
          // Añadir todas las variantes (incluyendo el default)
          for (final pokemon in allSpeciesPokemons) {
            if (!addedVariantIds.contains(pokemon.id)) {
              allVariants.add(pokemon);
              addedVariantIds.add(pokemon.id);
            }
          }
        }
      }
      
      return allVariants;
    } catch (e) {
      return allVariants;
    }
  }
  
  /// Verificar si un pokemon es una variante especial (mega, gigamax, primal)
  bool _isSpecialVariant(String pokemonName) {
    final nameLower = pokemonName.toLowerCase();
    return nameLower.contains('gmax') || 
           nameLower.contains('mega') || 
           nameLower.contains('primal');
  }
}

/// Datos completos de un pokemon
class PokemonCompleteData {
  final PokemonData pokemon;
  final PokemonSpecy species;
  final List<Type> types;
  final Map<String, int> stats;
  final List<Ability> abilities;
  final List<Move> moves;
  final Map<int, Type?> moveTypes; // moveId -> Type
  final Map<int, String?> moveDamageClasses; // moveId -> damageClassName
  final List<PokemonData> evolutions;
  final List<PokemonData> variants; // Variantes con pokedex
  final List<PokemonData> specialVariants; // Variantes sin pokedex (mega, gigamax, primal)
  final List<PokemonData> allEvolutionVariants; // Variantes de toda la gama evolutiva
  final String pokemonName;
  final String? genus;
  final String? description;
  final int? pokedexEntryNumber; // Número en la pokedex usada para ordenar
  final int? nationalEntryNumber; // Número en la pokedex nacional
  
  PokemonCompleteData({
    required this.pokemon,
    required this.species,
    required this.types,
    required this.stats,
    required this.abilities,
    required this.moves,
    required this.moveTypes,
    required this.moveDamageClasses,
    required this.evolutions,
    required this.variants,
    required this.specialVariants,
    required this.allEvolutionVariants,
    required this.pokemonName,
    this.genus,
    this.description,
    this.pokedexEntryNumber,
    this.nationalEntryNumber,
  });
}

