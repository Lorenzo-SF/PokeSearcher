import 'dart:ui';
import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../services/config/app_config.dart';
import '../database/daos/pokedex_dao.dart';
import '../database/daos/pokemon_dao.dart';
import '../database/daos/type_dao.dart';
import '../utils/color_generator.dart';
import '../utils/pokemon_image_helper.dart';
import '../widgets/type_stripe_background.dart';
import '../widgets/pokemon_image.dart';
import 'pokemon_detail_screen.dart';

class PokemonListScreen extends StatefulWidget {
  final AppDatabase database;
  final AppConfig appConfig;
  final int? regionId; // nullable para pokedex nacional
  final String regionName;
  final int? typeId; // nullable, si está presente filtra por tipo

  const PokemonListScreen({
    super.key,
    required this.database,
    required this.appConfig,
    this.regionId, // nullable para pokedex nacional
    required this.regionName,
    this.typeId, // nullable, si está presente filtra por tipo
  });

  @override
  State<PokemonListScreen> createState() => _PokemonListScreenState();
}

class _PokemonListScreenState extends State<PokemonListScreen> {
  List<Map<String, dynamic>> _pokemonList = [];
  List<Map<String, dynamic>> _filteredPokemonList = [];
  bool _isLoading = true;
  
  // Filtros
  final TextEditingController _nameFilterController = TextEditingController();
  int? _selectedType1Id;
  int? _selectedType2Id;
  List<Type> _availableTypes = [];
  bool _isLoadingTypes = true;

  @override
  void initState() {
    super.initState();
    _loadTypes();
    _loadPokemons();
    _nameFilterController.addListener(_applyFilters);
  }
  
  @override
  void dispose() {
    _nameFilterController.dispose();
    super.dispose();
  }
  
  Future<void> _loadTypes() async {
    try {
      final typeDao = TypeDao(widget.database);
      final types = await typeDao.getAllTypes();
      // Filtrar tipos desconocidos, stellar y shadow
      final filteredTypes = types.where((t) => 
        t.name.toLowerCase() != 'unknown' &&
        t.name.toLowerCase() != 'stellar' &&
        t.name.toLowerCase() != 'shadow'
      ).toList();
      setState(() {
        _availableTypes = filteredTypes;
        _isLoadingTypes = false;
      });
    } catch (e) {
      setState(() => _isLoadingTypes = false);
    }
  }
  
  void _applyFilters() {
    setState(() {
      _filteredPokemonList = _pokemonList.where((item) {
        // Filtro por nombre
        final species = item['species'] as PokemonSpecy;
        final nameFilter = _nameFilterController.text.toLowerCase().trim();
        if (nameFilter.isNotEmpty) {
          if (!species.name.toLowerCase().contains(nameFilter)) {
            return false;
          }
        }
        
        // Filtro por tipos
        final types = item['types'] as List<Type>;
        if (_selectedType1Id != null || _selectedType2Id != null) {
          final typeIds = types.map((t) => t.id).toList();
          
          if (_selectedType1Id != null && _selectedType2Id != null) {
            // Ambos tipos deben estar presentes (en cualquier orden)
            if (!typeIds.contains(_selectedType1Id!) || !typeIds.contains(_selectedType2Id!)) {
              return false;
            }
          } else if (_selectedType1Id != null) {
            // Solo tipo 1
            if (!typeIds.contains(_selectedType1Id!)) {
              return false;
            }
          } else if (_selectedType2Id != null) {
            // Solo tipo 2
            if (!typeIds.contains(_selectedType2Id!)) {
              return false;
            }
          }
        }
        
        return true;
      }).toList();
    });
  }

  Future<void> _loadPokemons() async {
    try {
      final pokedexDao = PokedexDao(widget.database);
      final pokemonDao = PokemonDao(widget.database);
      
      // Si hay filtro por tipo, usar lógica especial
      if (widget.typeId != null) {
        final pokemonByType = await pokemonDao.getPokemonByTypeOrderedByNational(widget.typeId!);
        
        final List<Map<String, dynamic>> pokemonList = [];
        
        for (final entry in pokemonByType) {
          final pokemon = entry['pokemon'] as PokemonData;
          final species = entry['species'] as PokemonSpecy;
          final nationalEntryNumber = entry['nationalEntryNumber'] as int;
          
          // Obtener tipos del pokemon
          final types = await pokemonDao.getPokemonTypes(pokemon.id);
          
          pokemonList.add({
            'species': species,
            'pokemon': pokemon,
            'orderNumber': nationalEntryNumber,
            'usedPokedex': null, // No aplica para filtro por tipo
            'types': types,
          });
        }
        
        setState(() {
          _pokemonList = pokemonList;
          _isLoading = false;
        });
        _applyFilters();
        return;
      }
      
      // Lógica normal por región
      List<PokedexData> pokedexList;
      Map<int, Map<String, dynamic>> uniquePokemon;
      
      if (widget.regionId == null) {
        // Pokedex Nacional: usar solo la pokedex nacional
        final nationalPokedex = await pokedexDao.getNationalPokedex();
        if (nationalPokedex == null) {
          setState(() {
            _isLoading = false;
          });
          return;
        }
        pokedexList = [nationalPokedex];
        
        // Obtener todas las entradas de la pokedex nacional
        final entries = await pokedexDao.getPokedexEntries(nationalPokedex.id);
        uniquePokemon = {};
        for (final entry in entries) {
          final pokemon = await pokemonDao.getPokemonById(entry.pokemonId);
          if (pokemon == null) continue;
          final species = await (widget.database.select(widget.database.pokemonSpecies)
            ..where((t) => t.id.equals(pokemon.speciesId)))
            .getSingleOrNull();
          if (species != null && !uniquePokemon.containsKey(species.id)) {
            uniquePokemon[species.id] = {
              'species': species,
              'pokedexNumbers': [{
                'pokedexId': nationalPokedex.id,
                'pokedexApiId': nationalPokedex.apiId,
                'entryNumber': entry.entryNumber,
                'color': nationalPokedex.color,
              }],
            };
          }
        }
      } else {
        // Región normal: obtener todas las pokedex de la región ordenadas por tamaño (mayor a menor)
        pokedexList = await pokedexDao.getPokedexByRegionOrderedBySize(widget.regionId!);
        
        // Obtener pokemons únicos de la región
        uniquePokemon = await pokedexDao.getUniquePokemonByRegion(widget.regionId!);
      }
      
      final List<Map<String, dynamic>> pokemonList = [];
      
      for (final entry in uniquePokemon.values) {
        final species = entry['species'] as PokemonSpecy;
        
        // Implementar coalesce: buscar número de entrada en pokedex ordenadas por tamaño
        int? orderNumber;
        PokedexData? usedPokedex;
        
        for (final pokedex in pokedexList) {
          final entryNumber = await pokedexDao.getEntryNumberForPokemon(pokedex.id, species.id);
          if (entryNumber != null) {
            orderNumber = entryNumber;
            usedPokedex = pokedex;
            break; // Usar el primero encontrado (pokedex más grande)
          }
        }
        
        // Si no se encontró en ninguna pokedex de la región, usar 0 como fallback
        if (orderNumber == null) {
          orderNumber = 0;
        }
        
        // Obtener el pokemon principal de esta especie (el primero)
        final pokemons = await pokemonDao.getPokemonBySpecies(species.id);
        final pokemon = pokemons.isNotEmpty ? pokemons.first : null;
        
        // Obtener tipos del pokemon
        List<Type> types = [];
        if (pokemon != null) {
          types = await pokemonDao.getPokemonTypes(pokemon.id);
        }
        
        pokemonList.add({
          'species': species,
          'pokemon': pokemon,
          'orderNumber': orderNumber,
          'usedPokedex': usedPokedex,
          'types': types,
        });
      }
      
      // Ordenar por el número de orden (coalesce)
      pokemonList.sort((a, b) {
        final aNumber = a['orderNumber'] as int;
        final bNumber = b['orderNumber'] as int;
        return aNumber.compareTo(bNumber);
      });
      
      setState(() {
        _pokemonList = pokemonList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar pokemons: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }



  /// Obtener colores de los tipos del pokemon
  List<Color> _getTypeColors(List<Type> types) {
    if (types.isEmpty) {
      return [const Color(0xFFCCCCCC)]; // Color por defecto
    }
    return types
        .map((type) {
          final colorHex = type.color;
          if (colorHex == null || colorHex.isEmpty) {
            return const Color(0xFFCCCCCC); // Color por defecto
          }
          return Color(ColorGenerator.hexToColor(colorHex));
        })
        .toList();
  }

  String _getRegionImageName(String regionName) {
    return 'assets/${regionName.toLowerCase()}.png';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Fondo con imagen de la región y blur
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(
                  _getRegionImageName(widget.regionName),
                ),
                fit: BoxFit.cover,
                alignment: Alignment.center,
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.5),
                  BlendMode.darken,
                ),
              ),
            ),
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                child: Container(
                  color: Colors.black.withOpacity(0.2),
                ),
              ),
            ),
          ),
          // Contenido
          Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 56,
            ),
            child: Column(
              children: [
                // Filtros
                _buildFilters(),
                // Lista de pokemons
                Expanded(
                  child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredPokemonList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 64,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No hay pokemons disponibles',
                        style: TextStyle(fontSize: 18),
                      ),
                    ],
                  ),
                )
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.75, // Ancho/Altura
                        ),
                        itemCount: _filteredPokemonList.length,
                        itemBuilder: (context, index) {
                          final item = _filteredPokemonList[index];
                    final species = item['species'] as PokemonSpecy;
                    final pokemon = item['pokemon'] as PokemonData?;
                    final orderNumber = item['orderNumber'] as int;
                    final usedPokedex = item['usedPokedex'] as PokedexData?;
                    final types = item['types'] as List<Type>;
                    final colors = _getTypeColors(types);
                    
                    return GestureDetector(
                      onTap: pokemon != null ? () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => PokemonDetailScreen(
                              database: widget.database,
                              appConfig: widget.appConfig,
                              pokemonId: pokemon.id,
                              regionId: widget.regionId,
                              regionName: widget.regionName,
                              pokedexId: usedPokedex?.id,
                              pokedexName: usedPokedex?.name,
                            ),
                          ),
                        );
                      } : null,
                      child: _buildPokemonCard(
                        species: species,
                        pokemon: pokemon,
                        orderNumber: orderNumber,
                        usedPokedex: usedPokedex,
                        colors: colors,
                        types: types,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Botón de volver
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.black.withOpacity(0.3),
      child: Column(
        children: [
          // Filtro por nombre
          TextField(
            controller: _nameFilterController,
            decoration: InputDecoration(
              labelText: 'Buscar por nombre',
              hintText: 'Escribe el nombre del Pokémon...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Filtros por tipo
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedType1Id,
                  decoration: InputDecoration(
                    labelText: 'Tipo 1',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('Ninguno'),
                    ),
                    ..._availableTypes.map((type) {
                      return DropdownMenuItem<int>(
                        value: type.id,
                        child: Text(type.name),
                      );
                    }),
                  ],
                  onChanged: _isLoadingTypes ? null : (value) {
                    setState(() {
                      _selectedType1Id = value;
                    });
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedType2Id,
                  decoration: InputDecoration(
                    labelText: 'Tipo 2',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('Ninguno'),
                    ),
                    ..._availableTypes.map((type) {
                      return DropdownMenuItem<int>(
                        value: type.id,
                        child: Text(type.name),
                      );
                    }),
                  ],
                  onChanged: _isLoadingTypes ? null : (value) {
                    setState(() {
                      _selectedType2Id = value;
                    });
                    _applyFilters();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPokemonCard({
    required PokemonSpecy species,
    required PokemonData? pokemon,
    required int orderNumber,
    required PokedexData? usedPokedex,
    required List<Color> colors,
    required List<Type> types,
  }) {
    // Usar front_transparent si hay configuración, sino usar lógica por defecto
    final imagePathFuture = PokemonImageHelper.getBestImagePath(
      pokemon,
      appConfig: widget.appConfig,
      database: widget.database,
      imageType: 'front_transparent',
    );
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: TypeStripeBackground(
          types: types,
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Imagen del pokemon (SVG preferido) desde assets
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: FutureBuilder<String?>(
                          future: imagePathFuture,
                          builder: (context, snapshot) {
                            return PokemonImage(
                              imagePath: snapshot.data,
                              fit: BoxFit.contain,
                              errorWidget: const Icon(
                                Icons.catching_pokemon,
                                size: 32,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Nombre del pokemon
                  Text(
                    species.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 3,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}

