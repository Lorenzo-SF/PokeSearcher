import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../services/config/app_config.dart';
import '../database/daos/pokedex_dao.dart';
import '../database/daos/pokemon_dao.dart';
import '../utils/color_generator.dart';

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
        
        pokemonList.add({
          'species': species,
          'pokemon': pokemon,
          'pokedexNumbers': pokedexNumbers,
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

  /// Obtener la mejor imagen disponible (SVG preferido, igual que en regiones)
  String? _getBestImageUrl(PokemonData? pokemon) {
    if (pokemon == null) return null;
    
    // Prioridad: SVG primero (igual que en regiones)
    if (pokemon.artworkOfficialUrl != null && 
        pokemon.artworkOfficialUrl!.isNotEmpty &&
        pokemon.artworkOfficialUrl!.toLowerCase().endsWith('.svg')) {
      return pokemon.artworkOfficialUrl;
    }
    if (pokemon.artworkOfficialShinyUrl != null && 
        pokemon.artworkOfficialShinyUrl!.isNotEmpty &&
        pokemon.artworkOfficialShinyUrl!.toLowerCase().endsWith('.svg')) {
      return pokemon.artworkOfficialShinyUrl;
    }
    if (pokemon.spriteFrontDefaultUrl != null && 
        pokemon.spriteFrontDefaultUrl!.isNotEmpty &&
        pokemon.spriteFrontDefaultUrl!.toLowerCase().endsWith('.svg')) {
      return pokemon.spriteFrontDefaultUrl;
    }
    if (pokemon.spriteFrontShinyUrl != null && 
        pokemon.spriteFrontShinyUrl!.isNotEmpty &&
        pokemon.spriteFrontShinyUrl!.toLowerCase().endsWith('.svg')) {
      return pokemon.spriteFrontShinyUrl;
    }
    
    // Si no hay SVG, usar artwork oficial (PNG)
    if (pokemon.artworkOfficialUrl != null && pokemon.artworkOfficialUrl!.isNotEmpty) {
      return pokemon.artworkOfficialUrl;
    }
    if (pokemon.artworkOfficialShinyUrl != null && pokemon.artworkOfficialShinyUrl!.isNotEmpty) {
      return pokemon.artworkOfficialShinyUrl;
    }
    if (pokemon.spriteFrontDefaultUrl != null && pokemon.spriteFrontDefaultUrl!.isNotEmpty) {
      return pokemon.spriteFrontDefaultUrl;
    }
    if (pokemon.spriteFrontShinyUrl != null && pokemon.spriteFrontShinyUrl!.isNotEmpty) {
      return pokemon.spriteFrontShinyUrl;
    }
    
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

  /// Obtener colores de las pokedexes
  List<Color> _getPokedexColors(List<Map<String, dynamic>> pokedexNumbers) {
    return pokedexNumbers
        .map((n) {
          final colorHex = n['color'] as String?;
          if (colorHex == null || colorHex.isEmpty) {
            return const Color(0xFFCCCCCC); // Color por defecto
          }
          return Color(ColorGenerator.hexToColor(colorHex));
        })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.regionName} - Pokemons'),
        centerTitle: true,
        backgroundColor: const Color(0xFFDC143C),
      ),
      body: _isLoading
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
                    final colors = _getPokedexColors(pokedexNumbers);
                    
                    return _buildPokemonCard(
                      species: species,
                      pokemon: pokemon,
                      pokedexNumbers: pokedexNumbers,
                      colors: colors,
                    );
                  },
                ),
    );
  }

  Widget _buildPokemonCard({
    required PokemonSpecy species,
    required PokemonData? pokemon,
    required List<Map<String, dynamic>> pokedexNumbers,
    required List<Color> colors,
  }) {
    final imageUrl = _getBestImageUrl(pokemon);
    final numbersText = _formatPokedexNumbers(pokedexNumbers);
    final hasMultiplePokedexes = colors.length > 1;
    
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
        child: Stack(
          children: [
            // Fondo con color(es) de pokedex (translúcido)
            if (hasMultiplePokedexes)
              // Múltiples pokedexes: franjas diagonales (45 grados)
              _buildDiagonalLinesBackground(colors)
            else
              // Una sola pokedex: color sólido translúcido
              Container(
                color: colors.first.withOpacity(0.8),
                width: double.infinity,
                height: double.infinity,
              ),
            // Contenido
            Container(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Imagen del pokemon (SVG preferido)
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
                      child: imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Image.network(
                                imageUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.catching_pokemon,
                                    size: 32,
                                    color: Colors.white,
                                  );
                                },
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  );
                                },
                              ),
                            )
                          : const Icon(
                              Icons.catching_pokemon,
                              size: 32,
                              color: Colors.white,
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
          ],
        ),
      ),
    );
  }

  /// Construir fondo con franjas diagonales para múltiples pokedexes
  Widget _buildDiagonalLinesBackground(List<Color> colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _DiagonalLinesPainter(colors),
        );
      },
    );
  }
}

/// Painter para dibujar franjas diagonales (45 grados) con diferentes colores
class _DiagonalLinesPainter extends CustomPainter {
  final List<Color> colors;
  final double angle = 45 * math.pi / 180; // 45 grados en radianes

  _DiagonalLinesPainter(this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;
    
    // Calcular el ancho de cada franja
    final stripeWidth = size.width / colors.length;
    
    // Calcular la distancia diagonal necesaria para cubrir toda la altura
    final diagonalDistance = size.height / math.cos(angle);
    
    // Dibujar cada franja diagonal
    for (int i = 0; i < colors.length; i++) {
      final paint = Paint()
        ..color = colors[i].withOpacity(0.8)
        ..style = PaintingStyle.fill;
      
      // Calcular los puntos de la franja diagonal
      // La franja va de esquina superior izquierda a inferior derecha
      final startX = i * stripeWidth;
      final endX = (i + 1) * stripeWidth;
      
      // Crear path para la franja diagonal
      final path = Path();
      
      // Punto superior izquierdo de la franja
      path.moveTo(startX, 0);
      
      // Punto superior derecho de la franja
      path.lineTo(endX, 0);
      
      // Punto inferior derecho de la franja (desplazado por el ángulo)
      path.lineTo(endX + diagonalDistance * math.sin(angle), size.height);
      
      // Punto inferior izquierdo de la franja (desplazado por el ángulo)
      path.lineTo(startX + diagonalDistance * math.sin(angle), size.height);
      
      // Cerrar el path
      path.close();
      
      // Dibujar la franja
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is _DiagonalLinesPainter) {
      return oldDelegate.colors.length != colors.length ||
          !_colorsEqual(oldDelegate.colors, colors);
    }
    return true;
  }
  
  bool _colorsEqual(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].value != b[i].value) return false;
    }
    return true;
  }
}

