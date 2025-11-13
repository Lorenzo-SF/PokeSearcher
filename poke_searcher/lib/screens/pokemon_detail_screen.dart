import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../database/app_database.dart';
import '../utils/media_path_helper.dart';
import '../services/config/app_config.dart';
import '../database/daos/pokemon_dao.dart';
import '../database/daos/pokemon_variants_dao.dart';
import '../utils/color_generator.dart';
import '../services/translation/translation_service.dart';
import '../widgets/type_stripe_background.dart';
import '../widgets/pokemon_image.dart';

class PokemonDetailScreen extends StatefulWidget {
  final AppDatabase database;
  final AppConfig appConfig;
  final int pokemonId;
  final int? regionId;
  final String? regionName;

  const PokemonDetailScreen({
    super.key,
    required this.database,
    required this.appConfig,
    required this.pokemonId,
    this.regionId,
    this.regionName,
  });

  @override
  State<PokemonDetailScreen> createState() => _PokemonDetailScreenState();
}

class _PokemonDetailScreenState extends State<PokemonDetailScreen> {
  PokemonData? _pokemon;
  PokemonSpecy? _species;
  List<Type> _types = [];
  Map<String, int> _stats = {};
  List<Move> _moves = [];
  final Map<int, Type?> _moveTypes = {}; // moveId -> Type
  final Map<int, String?> _moveDamageClasses = {}; // moveId -> damageClassName
  List<PokemonData> _evolutions = [];
  final List<PokemonData> _variants = [];
  String? _genus;
  String? _description;
  String? _pokemonName;
  bool _isLoading = true;
  bool _isShiny = false;
  late TranslationService _translationService;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();
  bool _audioInitialized = false;

  @override
  void initState() {
    super.initState();
    _translationService = TranslationService(
      database: widget.database,
      appConfig: widget.appConfig,
    );
    _initializeAudio();
    _loadPokemonData();
  }

  Future<void> _initializeAudio() async {
    try {
      await _flutterTts.setLanguage('es-ES');
      await _flutterTts.setSpeechRate(0.4); // Más lento para sonar robótico
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(0.5); // Voz más grave (masculina y robótica)
      // Intentar usar un motor de voz más robótico si está disponible
      try {
        await _flutterTts.setEngine('com.google.android.tts');
      } catch (e) {
        // Si no está disponible, continuar con el motor por defecto
      }
      setState(() {
        _audioInitialized = true;
      });
    } catch (e) {
      // Si falla, continuar sin TTS
    }
  }

  Future<void> _loadPokemonData() async {
    try {
      final pokemonDao = PokemonDao(widget.database);
      final variantsDao = PokemonVariantsDao(widget.database);
      
      // Obtener pokemon
      _pokemon = await pokemonDao.getPokemonById(widget.pokemonId);
      if (_pokemon == null) {
        setState(() => _isLoading = false);
        return;
      }
      
      // Obtener especie
      _species = await pokemonDao.getSpeciesByPokemonId(widget.pokemonId);
      
      // Obtener tipos
      _types = await pokemonDao.getPokemonTypes(_pokemon!.id);
      
      // Obtener estadísticas
      _stats = pokemonDao.getPokemonStats(_pokemon!);
      
      // Obtener movimientos
      _moves = await pokemonDao.getPokemonMoves(_pokemon!.id);
      
      // Obtener tipos y clases de daño de los movimientos
      _moveTypes.clear();
      _moveDamageClasses.clear();
      for (final move in _moves) {
        // Obtener tipo del movimiento
        if (move.typeId != null) {
          final allTypes = await widget.database.select(widget.database.types).get();
          final moveType = allTypes.firstWhere(
            (t) => t.id == move.typeId,
            orElse: () => allTypes.first, // Fallback (no debería pasar)
          );
          _moveTypes[move.id] = moveType;
        }
        
        // Obtener clase de daño del movimiento
        if (move.damageClassId != null) {
          final allDamageClasses = await widget.database.select(widget.database.moveDamageClasses).get();
          final damageClass = allDamageClasses.firstWhere(
            (dc) => dc.id == move.damageClassId,
            orElse: () => allDamageClasses.first, // Fallback
          );
          _moveDamageClasses[move.id] = damageClass.name;
        }
      }
      
      // Obtener nombre traducido del pokemon
      if (_species != null) {
        _pokemonName = await _translationService.getLocalizedName(
          entityType: 'pokemon-species',
          entityId: _species!.id,
          fallbackName: _species!.name,
        );
        
        // Obtener genus y descripción traducidos
        if (_species!.generaJson != null && _species!.generaJson!.isNotEmpty) {
          _genus = await _translationService.getGenus(
            generaJson: _species!.generaJson!,
          );
        }
        
        if (_species!.flavorTextEntriesJson != null && 
            _species!.flavorTextEntriesJson!.isNotEmpty) {
          _description = await _translationService.getFlavorText(
            flavorTextEntriesJson: _species!.flavorTextEntriesJson!,
          );
        }
        
        // Obtener evoluciones
        _evolutions = await _loadEvolutions(_species!);
      } else {
        _pokemonName = _pokemon!.name;
      }
      
      // Obtener variantes
      final variantRelations = await variantsDao.getVariantsForPokemon(_pokemon!.id);
      if (variantRelations.isNotEmpty) {
        final variantIds = variantRelations.map((v) => v.variantPokemonId).toList();
        for (final variantId in variantIds) {
          final variant = await pokemonDao.getPokemonById(variantId);
          if (variant != null) {
            _variants.add(variant);
          }
        }
      }
      
      // También verificar si este pokemon es una variante de otro
      final defaultId = await variantsDao.getDefaultPokemonId(_pokemon!.id);
      if (defaultId != null && defaultId != _pokemon!.id) {
        final defaultPokemon = await pokemonDao.getPokemonById(defaultId);
        if (defaultPokemon != null) {
          // Cargar todas las variantes del pokemon default
          final allVariants = await variantsDao.getVariantsForPokemon(defaultId);
          final variantIds = allVariants.map((v) => v.variantPokemonId).toList();
          variantIds.add(defaultId);
          
          for (final variantId in variantIds) {
            if (variantId != _pokemon!.id) {
              final variant = await pokemonDao.getPokemonById(variantId);
              if (variant != null) {
                _variants.add(variant);
              }
            }
          }
        }
      }
      
      setState(() => _isLoading = false);
      
      // Reproducir cry y TTS después de cargar
      _playCryAndTTS();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _playCryAndTTS() async {
    if (_pokemon == null) {
      print('[PokemonDetailScreen] ⚠️ _pokemon es null, no se puede reproducir audio');
      return;
    }
    
    print('[PokemonDetailScreen] 🔊 Iniciando reproducción de cry y TTS');
    print('[PokemonDetailScreen]   - cryLatestPath: ${_pokemon!.cryLatestPath}');
    print('[PokemonDetailScreen]   - cryLegacyPath: ${_pokemon!.cryLegacyPath}');
    
    // Esperar 750ms antes de reproducir el cry
    await Future.delayed(const Duration(milliseconds: 750));
    
    // Reproducir cry si está disponible (desde archivos locales)
    // Prioridad: cryLatestPath > cryLegacyPath
    String? audioPathToPlay = _pokemon!.cryLatestPath;
    if (audioPathToPlay == null || audioPathToPlay.isEmpty) {
      audioPathToPlay = _pokemon!.cryLegacyPath;
    }
    
    if (audioPathToPlay != null && audioPathToPlay.isNotEmpty) {
      try {
        // Convertir ruta de asset a ruta local
        final localAudioPath = await MediaPathHelper.assetPathToLocalPath(audioPathToPlay);
        
        if (localAudioPath == null) {
          print('[PokemonDetailScreen] ⚠️ No se pudo convertir ruta de audio a local: $audioPathToPlay');
          return;
        }
        
        print('[PokemonDetailScreen]   - audioPath original: $audioPathToPlay');
        print('[PokemonDetailScreen]   - audioPath local: $localAudioPath');
        
        // Verificar que el archivo existe
        final audioFile = File(localAudioPath);
        if (!await audioFile.exists()) {
          print('[PokemonDetailScreen] ⚠️ Archivo de audio no existe: $localAudioPath');
          return;
        }
        
        // Reproducir desde archivo local usando UrlSource con file://
        print('[PokemonDetailScreen] 📦 Intentando reproducir audio desde archivo: $localAudioPath');
        final fileAudio = UrlSource('file://$localAudioPath');
        
        try {
          await _audioPlayer.play(fileAudio);
          print('[PokemonDetailScreen] ✅ Audio reproducido correctamente');
          
          // Esperar a que termine el audio (con timeout)
          await _audioPlayer.onPlayerComplete.first.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              print('[PokemonDetailScreen] ⏱️ Timeout esperando que termine el audio');
            },
          );
          print('[PokemonDetailScreen] ✅ Audio terminado');
        } catch (e, stackTrace) {
          print('[PokemonDetailScreen] ❌ Error reproduciendo audio: $e');
          print('[PokemonDetailScreen] StackTrace: $stackTrace');
        }
      } catch (e, stackTrace) {
        print('[PokemonDetailScreen] ❌ Error preparando audio: $e');
        print('[PokemonDetailScreen] StackTrace: $stackTrace');
        // Si falla, continuar con TTS
      }
    } else {
      print('[PokemonDetailScreen] ⚠️ No hay ruta de audio disponible para este pokemon');
    }
    
    // Esperar 750ms después del cry
    await Future.delayed(const Duration(milliseconds: 750));
    
    // Reproducir TTS si está inicializado
    if (_audioInitialized && _pokemonName != null) {
      try {
        // Leer nombre
        await _flutterTts.speak(_pokemonName!);
        await Future.delayed(const Duration(seconds: 2));
        
        // Leer genus si existe
        if (_genus != null && _genus!.isNotEmpty) {
          await _flutterTts.speak(_genus!);
          await Future.delayed(const Duration(seconds: 2));
        }
        
        // Leer descripción si existe
        if (_description != null && _description!.isNotEmpty) {
          await _flutterTts.speak(_description!);
        }
      } catch (e) {
        // Si falla, continuar
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  String? _getBestSvgImage() {
    if (_pokemon == null) {
      print('[PokemonDetailScreen] _getBestSvgImage: pokemon es null');
      return null;
    }
    
    print('[PokemonDetailScreen] _getBestSvgImage para pokemon ${_pokemon!.name} (id: ${_pokemon!.id}, shiny: $_isShiny):');
    print('  - artworkOfficialPath: ${_pokemon!.artworkOfficialPath}');
    print('  - artworkOfficialShinyPath: ${_pokemon!.artworkOfficialShinyPath}');
    print('  - spriteFrontDefaultPath: ${_pokemon!.spriteFrontDefaultPath}');
    print('  - spriteFrontShinyPath: ${_pokemon!.spriteFrontShinyPath}');
    
    if (_isShiny) {
      if (_pokemon!.artworkOfficialShinyPath != null && 
          _pokemon!.artworkOfficialShinyPath!.isNotEmpty) {
        print('[PokemonDetailScreen] Usando artworkOfficialShinyPath: ${_pokemon!.artworkOfficialShinyPath}');
        return _pokemon!.artworkOfficialShinyPath;
      }
      if (_pokemon!.spriteFrontShinyPath != null && 
          _pokemon!.spriteFrontShinyPath!.isNotEmpty) {
        print('[PokemonDetailScreen] Usando spriteFrontShinyPath: ${_pokemon!.spriteFrontShinyPath}');
        return _pokemon!.spriteFrontShinyPath;
      }
    }
    
    if (_pokemon!.artworkOfficialPath != null && 
        _pokemon!.artworkOfficialPath!.toLowerCase().endsWith('.svg')) {
      print('[PokemonDetailScreen] Usando artworkOfficialPath (SVG): ${_pokemon!.artworkOfficialPath}');
      return _pokemon!.artworkOfficialPath;
    }
    if (_pokemon!.artworkOfficialPath != null) {
      print('[PokemonDetailScreen] Usando artworkOfficialPath: ${_pokemon!.artworkOfficialPath}');
      return _pokemon!.artworkOfficialPath;
    }
    if (_pokemon!.spriteFrontDefaultPath != null) {
      print('[PokemonDetailScreen] Usando spriteFrontDefaultPath: ${_pokemon!.spriteFrontDefaultPath}');
      return _pokemon!.spriteFrontDefaultPath;
    }
    
    print('[PokemonDetailScreen] ⚠️ No se encontró ninguna imagen válida');
    return null;
  }
  
  bool _hasShinyImage() {
    if (_pokemon == null) return false;
    return (_pokemon!.artworkOfficialShinyPath != null && 
            _pokemon!.artworkOfficialShinyPath!.isNotEmpty) ||
           (_pokemon!.spriteFrontShinyPath != null && 
            _pokemon!.spriteFrontShinyPath!.isNotEmpty);
  }
  
  void _toggleShiny() {
    if (_hasShinyImage()) {
      setState(() {
        _isShiny = !_isShiny;
      });
    }
  }

  Future<List<PokemonData>> _loadEvolutions(PokemonSpecy species) async {
    if (species.evolutionChainId == null) return [];
    
    try {
      final pokemonDao = PokemonDao(widget.database);
      
      final evolutionChain = await (widget.database.select(widget.database.evolutionChains)
        ..where((t) => t.apiId.equals(species.evolutionChainId!)))
        .getSingleOrNull();
      
      if (evolutionChain == null || evolutionChain.chainJson == null) {
        return [];
      }
      
      final chainData = jsonDecode(evolutionChain.chainJson!) as Map<String, dynamic>;
      final List<PokemonData> evolutions = [];
      final List<Future<PokemonData?>> evolutionFutures = [];
      
      void extractSpecies(Map<String, dynamic> chain) {
        final speciesInfo = chain['species'] as Map<String, dynamic>?;
        if (speciesInfo != null) {
          final speciesName = speciesInfo['name'] as String?;
          if (speciesName != null && speciesName != _species?.name) {
            evolutionFutures.add(pokemonDao.getPokemonByName(speciesName));
          }
        }
        
        final evolvesTo = chain['evolves_to'] as List?;
        if (evolvesTo != null) {
          for (final nextChain in evolvesTo) {
            extractSpecies(nextChain as Map<String, dynamic>);
          }
        }
      }
      
      extractSpecies(chainData);
      
      final results = await Future.wait(evolutionFutures);
      for (final pokemon in results) {
        if (pokemon != null) {
          evolutions.add(pokemon);
        }
      }
      
      return evolutions;
    } catch (e) {
      return [];
    }
  }

  Future<String> _getPokedexNumber() async {
    if (_species == null) return '';
    if (_species!.order != null) {
      return '#${_species!.order}';
    }
    return '';
  }

  String _getRegionImageName() {
    if (widget.regionName != null) {
      return 'assets/${widget.regionName!.toLowerCase()}.png';
    }
    return 'assets/kanto.png'; // Default
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Stack(
          children: [
            // Fondo con blur de región
            if (widget.regionName != null) ...[
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(_getRegionImageName()),
                    fit: BoxFit.cover,
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
            ],
            const Center(child: CircularProgressIndicator()),
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

    if (_pokemon == null) {
      return Scaffold(
        body: Stack(
          children: [
            if (widget.regionName != null) ...[
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(_getRegionImageName()),
                    fit: BoxFit.cover,
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
            ],
            const Center(
              child: Text('No se pudo cargar la información del Pokémon'),
            ),
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

    return Scaffold(
      body: Stack(
        children: [
          // Fondo con blur de región
          if (widget.regionName != null) ...[
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(_getRegionImageName()),
                  fit: BoxFit.cover,
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
          ],
          SingleChildScrollView(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 56,
              left: 16,
              right: 16,
              bottom: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nombre y número (más arriba)
                _buildHeader(),
                
                // Género (sin label, más pequeño y centrado)
                if (_genus != null) ...[
                  const SizedBox(height: 8),
                  _buildGenus(),
                ],
                
                // Imagen (arriba)
                const SizedBox(height: 16),
                _buildImage(),
                
                // Tipos (debajo de la imagen, vertical)
                if (_types.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildTypesVertical(),
                ],
                
                // Información (altura y peso en misma línea, sin género que ya está arriba)
                const SizedBox(height: 16),
                _buildInfo(),
                
                // Estadísticas
                _buildStatsSection(),
                
                // Evoluciones
                _buildEvolutionsSection(),
                
                // Variantes
                _buildVariantsSection(),
                
                // Movimientos
                _buildMovesSection(),
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

  Widget _buildHeader() {
    return FutureBuilder<String>(
      future: _getPokedexNumber(),
      builder: (context, snapshot) {
        final number = snapshot.data ?? '';
        return Container(
          padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 0),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _pokemonName ?? _pokemon?.name ?? 'Pokemon',
                  style: const TextStyle(
                    fontSize: 36,
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
                ),
                if (number.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Text(
                    number,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                      shadows: [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 3,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGenus() {
    return Center(
      child: Text(
        _genus!,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: Colors.white70,
          shadows: [
            Shadow(
              color: Colors.black,
              blurRadius: 2,
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildImage() {
    final imageUrl = _getBestSvgImage();
    final hasShiny = _hasShinyImage();
    
    return Center(
      child: GestureDetector(
        onTap: hasShiny ? _toggleShiny : null,
        child: Container(
          width: 300,
          height: 300,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: PokemonImage(
            imagePath: imageUrl,
            fit: BoxFit.contain,
            width: 300,
            height: 300,
            errorWidget: const Icon(
              Icons.catching_pokemon,
              size: 150,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypesVertical() {
    return Center(
      child: Column(
        children: _types.map((type) {
          final colorHex = type.color;
          final color = colorHex != null 
              ? Color(ColorGenerator.hexToColor(colorHex))
              : Colors.grey;
          
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              type.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInfo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                // Altura y peso en misma línea
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    if (_pokemon!.height != null)
                      Expanded(
                        child: _buildInfoRow('Altura', '${(_pokemon!.height! / 10).toStringAsFixed(1)} m'),
                      ),
                    if (_pokemon!.height != null && _pokemon!.weight != null)
                      const SizedBox(width: 16),
                    if (_pokemon!.weight != null)
                      Expanded(
                        child: _buildInfoRow('Peso', '${(_pokemon!.weight! / 10).toStringAsFixed(1)} kg'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
          // Habilidad
          FutureBuilder<List<Ability>>(
            future: PokemonDao(widget.database).getPokemonAbilities(_pokemon!.id),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                final abilities = snapshot.data!.map((a) => a.name).join(', ');
                return _buildInfoRow('Habilidad', abilities);
              }
              return const SizedBox.shrink();
            },
          ),
          const SizedBox(height: 16),
          // Descripción
          if (_description != null)
            _buildInfoRow('Descripción', _description!),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(
                color: Colors.black,
                blurRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Colors.black,
                blurRadius: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsSection() {
    final statNames = {
      'hp': 'PS',
      'attack': 'Ataque',
      'defense': 'Defensa',
      'special-attack': 'Ataque Especial',
      'special-defense': 'Defensa Especial',
      'speed': 'Velocidad',
    };
    
    final orderedStats = [
      'hp',
      'attack',
      'defense',
      'special-attack',
      'special-defense',
      'speed',
    ];
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Estadísticas',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black,
                  blurRadius: 3,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...orderedStats.map((statKey) {
            final statValue = _stats[statKey] ?? 0;
            final statName = statNames[statKey] ?? statKey;
            return _buildStatBar(statName, statValue);
          }),
        ],
      ),
    );
  }

  Widget _buildStatBar(String name, int value) {
    final maxValue = 255.0;
    final percentage = (value / maxValue).clamp(0.0, 1.0);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              name,
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
          ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: percentage,
                  child: Container(
                    height: 20,
                    decoration: BoxDecoration(
                      color: _getStatColor(percentage),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
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
          ),
        ],
      ),
    );
  }

  Color _getStatColor(double percentage) {
    if (percentage >= 0.7) return Colors.green;
    if (percentage >= 0.4) return Colors.orange;
    return Colors.red;
  }

  Widget _buildMovesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExpansionTile(
            title: Text(
              'Movimientos (${_moves.length})',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black,
                    blurRadius: 3,
                  ),
                ],
              ),
            ),
            initiallyExpanded: false, // Contraído por defecto
            backgroundColor: Colors.transparent,
            collapsedBackgroundColor: Colors.transparent,
            iconColor: Colors.white,
            collapsedIconColor: Colors.white70,
            children: [
              if (_moves.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'No hay movimientos disponibles',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                      shadows: [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Column(
                  children: _moves.map((move) => _buildMoveCard(move)).toList(),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMoveCard(Move move) {
    final moveType = _moveTypes[move.id];
    final damageClass = _moveDamageClasses[move.id] ?? 'N/A';
    final typeList = moveType != null ? <Type>[moveType] : <Type>[];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: TypeStripeBackground(
          types: typeList,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nombre del movimiento
                Text(
                  move.name,
                  style: const TextStyle(
                    fontSize: 16,
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
                // Información del movimiento
                Row(
                  children: [
                    // Tipo
                    if (moveType != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          moveType.name,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    if (moveType != null) const SizedBox(width: 8),
                    // Clase de daño
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        damageClass,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Estadísticas del movimiento
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    if (move.power != null)
                      _buildMoveStat('Daño', move.power.toString()),
                    if (move.accuracy != null)
                      _buildMoveStat('Precisión', '${move.accuracy}%'),
                    if (move.pp != null)
                      _buildMoveStat('PP', move.pp.toString()),
                    if (move.priority != null && move.priority != 0)
                      _buildMoveStat('Prioridad', move.priority.toString()),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMoveStat(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildEvolutionsSection() {
    if (_evolutions.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Evoluciones',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black,
                  blurRadius: 3,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _evolutions.length,
              itemBuilder: (context, index) {
                final evolution = _evolutions[index];
                return _buildEvolutionCard(evolution);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvolutionCard(PokemonData evolution) {
    final imageUrl = _getBestImageForPokemon(evolution);
    
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => PokemonDetailScreen(
              database: widget.database,
              appConfig: widget.appConfig,
              pokemonId: evolution.id,
              regionId: widget.regionId,
              regionName: widget.regionName,
            ),
          ),
        );
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        child: _buildPokemonCard(
          pokemon: evolution,
          imageUrl: imageUrl,
        ),
      ),
    );
  }

  Widget _buildVariantsSection() {
    if (_variants.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Variantes',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black,
                  blurRadius: 3,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _variants.length,
              itemBuilder: (context, index) {
                final variant = _variants[index];
                return _buildVariantCard(variant);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantCard(PokemonData variant) {
    final imageUrl = _getBestImageForPokemon(variant);
    
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => PokemonDetailScreen(
              database: widget.database,
              appConfig: widget.appConfig,
              pokemonId: variant.id,
              regionId: widget.regionId,
              regionName: widget.regionName,
            ),
          ),
        );
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        child: _buildPokemonCard(
          pokemon: variant,
          imageUrl: imageUrl,
        ),
      ),
    );
  }

  String? _getBestImageForPokemon(PokemonData pokemon) {
    print('[PokemonDetailScreen] _getBestImageForPokemon para pokemon ${pokemon.name} (id: ${pokemon.id}):');
    print('  - artworkOfficialPath: ${pokemon.artworkOfficialPath}');
    print('  - spriteFrontDefaultPath: ${pokemon.spriteFrontDefaultPath}');
    
    if (pokemon.artworkOfficialPath != null && 
        pokemon.artworkOfficialPath!.toLowerCase().endsWith('.svg')) {
      print('[PokemonDetailScreen] Usando artworkOfficialPath (SVG): ${pokemon.artworkOfficialPath}');
      return pokemon.artworkOfficialPath;
    }
    if (pokemon.spriteFrontDefaultPath != null && 
        pokemon.spriteFrontDefaultPath!.toLowerCase().endsWith('.svg')) {
      print('[PokemonDetailScreen] Usando spriteFrontDefaultPath (SVG): ${pokemon.spriteFrontDefaultPath}');
      return pokemon.spriteFrontDefaultPath;
    }
    if (pokemon.artworkOfficialPath != null) {
      print('[PokemonDetailScreen] Usando artworkOfficialPath: ${pokemon.artworkOfficialPath}');
      return pokemon.artworkOfficialPath;
    }
    if (pokemon.spriteFrontDefaultPath != null) {
      print('[PokemonDetailScreen] Usando spriteFrontDefaultPath: ${pokemon.spriteFrontDefaultPath}');
      return pokemon.spriteFrontDefaultPath;
    }
    print('[PokemonDetailScreen] ⚠️ No se encontró ninguna imagen válida para pokemon ${pokemon.name}');
    return null;
  }

  Widget _buildPokemonCard({
    required PokemonData pokemon,
    String? imageUrl,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          // Fondo translúcido en el contenedor padre
          color: Colors.white.withOpacity(0.2),
          child: Column(
            children: [
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: PokemonImage(
                    imagePath: imageUrl,
                    fit: BoxFit.contain,
                    width: 60,
                    height: 60,
                    errorWidget: const Icon(
                      Icons.catching_pokemon,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                child: Text(
                  pokemon.name,
                  style: const TextStyle(
                    fontSize: 12,
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
