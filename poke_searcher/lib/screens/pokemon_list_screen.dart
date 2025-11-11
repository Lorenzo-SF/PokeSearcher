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
        final pokedexNumbers = entry['pokedexNumbers'] as List<Map<String, dynamic>>;
        
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

  /// Obtener la mejor imagen disponible (SVG preferido, luego PNG de mayor resolución)
  String? _getBestImageUrl(PokemonData? pokemon) {
    if (pokemon == null) return null;
    
    // Recopilar todas las URLs disponibles
    final List<Map<String, String?>> imageUrls = [
      {'url': pokemon.artworkOfficialUrl, 'type': 'artwork'},
      {'url': pokemon.artworkOfficialShinyUrl, 'type': 'artwork_shiny'},
      {'url': pokemon.spriteFrontDefaultUrl, 'type': 'sprite_front'},
      {'url': pokemon.spriteFrontShinyUrl, 'type': 'sprite_front_shiny'},
      {'url': pokemon.spriteBackDefaultUrl, 'type': 'sprite_back'},
      {'url': pokemon.spriteBackShinyUrl, 'type': 'sprite_back_shiny'},
    ];
    
    // Filtrar URLs válidas
    final validUrls = imageUrls
        .where((item) => item['url'] != null && item['url']!.isNotEmpty)
        .map((item) => item['url']!)
        .toList();
    
    if (validUrls.isEmpty) return null;
    
    // Prioridad 1: Buscar SVG
    final svgUrls = validUrls.where((url) => url.toLowerCase().endsWith('.svg')).toList();
    if (svgUrls.isNotEmpty) {
      // Si hay múltiples SVG, preferir artwork oficial
      final artworkSvg = svgUrls.firstWhere(
        (url) => url.contains('artwork') || url.contains('official'),
        orElse: () => svgUrls.first,
      );
      return artworkSvg;
    }
    
    // Prioridad 2: PNG ordenados por resolución (mayor primero)
    final pngUrls = validUrls.where((url) => url.toLowerCase().endsWith('.png')).toList();
    if (pngUrls.isNotEmpty) {
      // Ordenar por resolución estimada (buscar números en la URL que indiquen resolución)
      pngUrls.sort((a, b) {
        final aRes = _extractResolution(a);
        final bRes = _extractResolution(b);
        return bRes.compareTo(aRes); // Mayor primero
      });
      
      // Preferir artwork oficial si está disponible
      final artworkPng = pngUrls.firstWhere(
        (url) => url.contains('artwork') || url.contains('official'),
        orElse: () => pngUrls.first,
      );
      return artworkPng;
    }
    
    // Si no hay SVG ni PNG, devolver la primera URL disponible
    return validUrls.first;
  }
  
  /// Extraer resolución estimada de una URL
  /// Busca patrones como "192x192", "512", "hd", "high" etc.
  int _extractResolution(String url) {
    // Buscar patrones de resolución en la URL
    final resolutionPattern = RegExp(r'(\d{2,4})x(\d{2,4})|(\d{3,4})(?:px|p)?');
    final match = resolutionPattern.firstMatch(url.toLowerCase());
    
    if (match != null) {
      // Si hay formato "WxH", usar el mayor
      if (match.group(1) != null && match.group(2) != null) {
        final w = int.tryParse(match.group(1)!) ?? 0;
        final h = int.tryParse(match.group(2)!) ?? 0;
        return w > h ? w : h;
      }
      // Si hay un solo número, usarlo
      if (match.group(3) != null) {
        return int.tryParse(match.group(3)!) ?? 0;
      }
    }
    
    // Buscar palabras clave que indiquen resolución
    if (url.toLowerCase().contains('hd') || url.toLowerCase().contains('high')) {
      return 512;
    }
    if (url.toLowerCase().contains('md') || url.toLowerCase().contains('medium')) {
      return 256;
    }
    if (url.toLowerCase().contains('sm') || url.toLowerCase().contains('small')) {
      return 128;
    }
    
    // Por defecto, artwork oficial suele ser de mayor resolución
    if (url.contains('artwork') || url.contains('official')) {
      return 512;
    }
    
    // Sprites suelen ser más pequeños
    if (url.contains('sprite')) {
      return 96;
    }
    
    return 0; // Resolución desconocida
  }

  /// Formatear números de pokedex
  String _formatPokedexNumbers(List<Map<String, dynamic>> pokedexNumbers) {
    if (pokedexNumbers.isEmpty) return '';
    if (pokedexNumbers.length == 1) {
      return '#${pokedexNumbers.first['entryNumber']}';
    }
    
    // Múltiples números: "nº1 / nº2 / ..."
    return pokedexNumbers
        .map((n) => '#${n['entryNumber']}')
        .join(' / ');
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
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
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
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Fondo con color(es) de pokedex
            if (hasMultiplePokedexes)
              // Múltiples pokedexes: líneas diagonales
              _buildDiagonalLinesBackground(colors)
            else
              // Una sola pokedex: color sólido
              Container(
                color: colors.first.withOpacity(0.8),
                width: double.infinity,
                height: 120,
              ),
            // Contenido
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Imagen del pokemon
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                    child: imageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              imageUrl,
                              width: 88,
                              height: 88,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.catching_pokemon,
                                  size: 48,
                                  color: Colors.white,
                                );
                              },
                            ),
                          )
                        : const Icon(
                            Icons.catching_pokemon,
                            size: 48,
                            color: Colors.white,
                          ),
                  ),
                  const SizedBox(width: 16),
                  // Información
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Números de pokedex
                        Text(
                          numbersText,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Nombre del pokemon
                        Text(
                          species.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Construir fondo con líneas diagonales para múltiples pokedexes
  Widget _buildDiagonalLinesBackground(List<Color> colors) {
    return CustomPaint(
      size: const Size(double.infinity, 120),
      painter: _DiagonalLinesPainter(colors),
    );
  }
}

/// Painter para dibujar líneas diagonales con diferentes colores
class _DiagonalLinesPainter extends CustomPainter {
  final List<Color> colors;
  final double angle = 45 * math.pi / 180; // 45 grados en radianes

  _DiagonalLinesPainter(this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = size.width / colors.length;

    // Calcular el espaciado entre líneas
    final spacing = size.width / colors.length;
    
    // Dibujar cada línea diagonal
    for (int i = 0; i < colors.length; i++) {
      paint.color = colors[i].withOpacity(0.8);
      
      // Calcular punto inicial y final de la línea
      // La línea debe cruzar todo el canvas en diagonal
      final startX = i * spacing - size.height * math.tan(angle);
      final startY = 0.0;
      final endX = (i + 1) * spacing + size.height * math.tan(angle);
      final endY = size.height;
      
      // Dibujar línea diagonal
      canvas.drawLine(
        Offset(startX, startY),
        Offset(endX, endY),
        paint,
      );
      
      // Rellenar el área entre líneas para crear bandas
      final path = Path()
        ..moveTo(startX, startY)
        ..lineTo(endX, endY)
        ..lineTo(endX + spacing, endY)
        ..lineTo(startX + spacing, startY)
        ..close();
      
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

