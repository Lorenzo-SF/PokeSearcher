import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../services/config/app_config.dart';
import '../database/daos/pokedex_dao.dart';
import '../database/daos/pokemon_dao.dart';
import '../utils/color_generator.dart';
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
  }) {
    final imageUrl = _getBestImageUrl(pokemon);
    final numbersText = _formatPokedexNumbers(pokedexNumbers);
    final hasMultipleTypes = colors.length > 1;
    
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
            // Fondo con color(es) de tipos (franjas ocupando mitad de la tarjeta)
            if (hasMultipleTypes)
              // Múltiples tipos: franjas diagonales (45 grados) ocupando mitad
              _buildDiagonalLinesBackground(colors)
            else
              // Un solo tipo: franja diagonal ocupando mitad
              _buildDiagonalLinesBackground(colors),
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
    
    // Las franjas ocupan el triángulo superior (de esquina superior izquierda a esquina inferior derecha)
    // Dividir la diagonal en partes iguales según el número de tipos
    final startRatio = 0.0;
    final endRatio = 0.5; // Ocupar solo la mitad (triángulo superior)
    
    // Dibujar cada franja diagonal formando el triángulo superior
    for (int i = 0; i < colors.length; i++) {
      final paint = Paint()
        ..color = colors[i].withOpacity(0.8)
        ..style = PaintingStyle.fill;
      
      // Calcular los puntos del triángulo
      // Dividir la mitad de la diagonal en partes iguales
      final stripeStartRatio = startRatio + (i / colors.length) * (endRatio - startRatio);
      final stripeEndRatio = startRatio + ((i + 1) / colors.length) * (endRatio - startRatio);
      
      // Puntos de inicio y fin en la diagonal (de esquina superior izquierda a mitad de la diagonal)
      final startX = stripeStartRatio * size.width;
      final startY = stripeStartRatio * size.height;
      final endX = stripeEndRatio * size.width;
      final endY = stripeEndRatio * size.height;
      
      // Crear path para el triángulo
      final path = Path();
      
      // Punto superior izquierdo (esquina superior izquierda de la tarjeta)
      if (i == 0) {
        path.moveTo(0, 0);
      } else {
        path.moveTo(startX, startY);
      }
      
      // Punto en la diagonal (inicio de esta franja)
      path.lineTo(startX, startY);
      
      // Punto en la diagonal (fin de esta franja)
      path.lineTo(endX, endY);
      
      // Punto superior derecho (si es la última franja, va hasta la mitad del borde superior)
      if (i == colors.length - 1) {
        path.lineTo(size.width / 2, 0);
      } else {
        // Para franjas intermedias, el borde superior es la línea desde startX hasta endX en y=0
        path.lineTo(endX, 0);
      }
      
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

