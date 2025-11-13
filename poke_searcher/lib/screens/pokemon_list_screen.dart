import 'dart:ui';
import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../services/config/app_config.dart';
import '../database/daos/pokedex_dao.dart';
import '../database/daos/pokemon_dao.dart';
import '../utils/color_generator.dart';
import '../widgets/type_stripe_background.dart';
import '../widgets/pokemon_image.dart';
import 'pokemon_detail_screen.dart';

class PokemonListScreen extends StatefulWidget {
  final AppDatabase database;
  final AppConfig appConfig;
  final int regionId;
  final String regionName;

  const PokemonListScreen({
    super.key,
    required this.database,
    required this.appConfig,
    required this.regionId,
    required this.regionName,
  });

  @override
  State<PokemonListScreen> createState() => _PokemonListScreenState();
}

class _PokemonListScreenState extends State<PokemonListScreen> {
  List<Map<String, dynamic>> _pokemonList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPokemons();
  }

  Future<void> _loadPokemons() async {
    try {
      final pokedexDao = PokedexDao(widget.database);
      final pokemonDao = PokemonDao(widget.database);
      
      // Obtener pokemons únicos de la región
      final uniquePokemon = await pokedexDao.getUniquePokemonByRegion(widget.regionId);
      
      final List<Map<String, dynamic>> pokemonList = [];
      
      for (final entry in uniquePokemon.values) {
        final species = entry['species'] as PokemonSpecy;
        // Convertir List<dynamic> a List<Map<String, dynamic>>
        final pokedexNumbersRaw = entry['pokedexNumbers'] as List;
        final pokedexNumbers = pokedexNumbersRaw
            .map((item) => item as Map<String, dynamic>)
            .toList();
        
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
          'pokedexNumbers': pokedexNumbers,
          'types': types,
        });
      }
      
      // Ordenar por el primer número de pokedex
      pokemonList.sort((a, b) {
        final aNumbers = a['pokedexNumbers'] as List<Map<String, dynamic>>;
        final bNumbers = b['pokedexNumbers'] as List<Map<String, dynamic>>;
        if (aNumbers.isEmpty) return 1;
        if (bNumbers.isEmpty) return -1;
        final aFirst = aNumbers.first['entryNumber'] as int;
        final bFirst = bNumbers.first['entryNumber'] as int;
        return aFirst.compareTo(bFirst);
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

  /// Obtener la mejor imagen disponible desde assets (SVG preferido)
  String? _getBestImagePath(PokemonData? pokemon) {
    if (pokemon == null) {
      print('[PokemonListScreen] _getBestImagePath: pokemon es null');
      return null;
    }
    
    print('[PokemonListScreen] _getBestImagePath para pokemon ${pokemon.name} (id: ${pokemon.id}):');
    print('  - artworkOfficialPath: ${pokemon.artworkOfficialPath}');
    print('  - artworkOfficialShinyPath: ${pokemon.artworkOfficialShinyPath}');
    print('  - spriteFrontDefaultPath: ${pokemon.spriteFrontDefaultPath}');
    print('  - spriteFrontShinyPath: ${pokemon.spriteFrontShinyPath}');
    
    // Prioridad: SVG primero (igual que en regiones)
    if (pokemon.artworkOfficialPath != null && 
        pokemon.artworkOfficialPath!.isNotEmpty &&
        pokemon.artworkOfficialPath!.toLowerCase().endsWith('.svg')) {
      print('[PokemonListScreen] Usando artworkOfficialPath (SVG): ${pokemon.artworkOfficialPath}');
      return pokemon.artworkOfficialPath;
    }
    if (pokemon.artworkOfficialShinyPath != null && 
        pokemon.artworkOfficialShinyPath!.isNotEmpty &&
        pokemon.artworkOfficialShinyPath!.toLowerCase().endsWith('.svg')) {
      return pokemon.artworkOfficialShinyPath;
    }
    if (pokemon.spriteFrontDefaultPath != null && 
        pokemon.spriteFrontDefaultPath!.isNotEmpty &&
        pokemon.spriteFrontDefaultPath!.toLowerCase().endsWith('.svg')) {
      return pokemon.spriteFrontDefaultPath;
    }
    if (pokemon.spriteFrontShinyPath != null && 
        pokemon.spriteFrontShinyPath!.isNotEmpty &&
        pokemon.spriteFrontShinyPath!.toLowerCase().endsWith('.svg')) {
      return pokemon.spriteFrontShinyPath;
    }
    
    // Si no hay SVG, usar artwork oficial (PNG)
    if (pokemon.artworkOfficialPath != null && pokemon.artworkOfficialPath!.isNotEmpty) {
      return pokemon.artworkOfficialPath;
    }
    if (pokemon.artworkOfficialShinyPath != null && pokemon.artworkOfficialShinyPath!.isNotEmpty) {
      return pokemon.artworkOfficialShinyPath;
    }
    if (pokemon.spriteFrontDefaultPath != null && pokemon.spriteFrontDefaultPath!.isNotEmpty) {
      print('[PokemonListScreen] Usando spriteFrontDefaultPath: ${pokemon.spriteFrontDefaultPath}');
      return pokemon.spriteFrontDefaultPath;
    }
    if (pokemon.spriteFrontShinyPath != null && pokemon.spriteFrontShinyPath!.isNotEmpty) {
      print('[PokemonListScreen] Usando spriteFrontShinyPath: ${pokemon.spriteFrontShinyPath}');
      return pokemon.spriteFrontShinyPath;
    }
    
    print('[PokemonListScreen] ⚠️ No se encontró ninguna imagen válida para pokemon ${pokemon.name}');
    return null;
  }

  /// Formatear números de pokedex (separados por "/")
  /// Aplica distinct para evitar mostrar números duplicados
  String _formatPokedexNumbers(List<Map<String, dynamic>> pokedexNumbers) {
    if (pokedexNumbers.isEmpty) return '';
    
    // Obtener números únicos (distinct)
    final uniqueNumbers = <int>{};
    for (final n in pokedexNumbers) {
      final entryNumber = n['entryNumber'] as int?;
      if (entryNumber != null) {
        uniqueNumbers.add(entryNumber);
      }
    }
    
    if (uniqueNumbers.isEmpty) return '';
    if (uniqueNumbers.length == 1) {
      return '${uniqueNumbers.first}';
    }
    
    // Múltiples números únicos: "nº1 / nº2 / ..." (ordenados)
    final sortedNumbers = uniqueNumbers.toList()..sort();
    return sortedNumbers.join(' / ');
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
            child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pokemonList.isEmpty
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
                  itemCount: _pokemonList.length,
                  itemBuilder: (context, index) {
                    final item = _pokemonList[index];
                    final species = item['species'] as PokemonSpecy;
                    final pokemon = item['pokemon'] as PokemonData?;
                    final pokedexNumbers = item['pokedexNumbers'] as List<Map<String, dynamic>>;
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
                            ),
                          ),
                        );
                      } : null,
                      child: _buildPokemonCard(
                        species: species,
                        pokemon: pokemon,
                        pokedexNumbers: pokedexNumbers,
                        colors: colors,
                        types: types,
                      ),
                    );
                  },
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

  Widget _buildPokemonCard({
    required PokemonSpecy species,
    required PokemonData? pokemon,
    required List<Map<String, dynamic>> pokedexNumbers,
    required List<Color> colors,
    required List<Type> types,
  }) {
    final imagePath = _getBestImagePath(pokemon);
    final numbersText = _formatPokedexNumbers(pokedexNumbers);
    
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
                        child: PokemonImage(
                          imagePath: imagePath,
                          fit: BoxFit.contain,
                          errorWidget: const Icon(
                            Icons.catching_pokemon,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Números de pokedex (separados por "/")
                  Text(
                    numbersText,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Nombre del pokemon con formato "nombre #numero"
                  Text(
                    '${species.name} #$numbersText',
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

