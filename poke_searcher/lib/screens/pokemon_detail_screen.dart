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
import '../database/daos/pokedex_dao.dart';
import '../utils/color_generator.dart';
import '../utils/pokemon_image_helper.dart';
import '../services/translation/translation_service.dart';
import '../widgets/type_stripe_background.dart';
import '../widgets/pokemon_image.dart';

class PokemonDetailScreen extends StatefulWidget {
  final AppDatabase database;
  final AppConfig appConfig;
  final int pokemonId;
  final int? regionId;
  final String? regionName;
  final int? pokedexId;
  final String? pokedexName;

  const PokemonDetailScreen({
    super.key,
    required this.database,
    required this.appConfig,
    required this.pokemonId,
    this.regionId,
    this.regionName,
    this.pokedexId,
    this.pokedexName,
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
  final List<PokemonData> _specialVariants = []; // mega, gigamax, primal sin pokedex
  String? _genus;
  String? _description;
  String? _pokemonName;
  bool _isLoading = true;
  bool _isShiny = false;
  late TranslationService _translationService;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();
  bool _audioInitialized = false;
  List<Ability> _abilities = []; // Habilidades del pokemon
  int? _pokedexEntryNumber; // Número en la pokedex usada para ordenar
  int? _nationalEntryNumber; // Número en la pokedex nacional
  String? _shortDescription; // Descripción corta
  String? _longDescription; // Descripción larga

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
      await _flutterTts.setSpeechRate(0.3); // Más lento para sonar robótico
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(0.3); // Voz más grave (masculina y robótica)
      // Intentar usar un motor de voz más robótico si está disponible
      try {
        await _flutterTts.setEngine('com.google.android.tts');
        // Intentar configurar voz masculina
        final voices = await _flutterTts.getVoices;
        if (voices != null) {
          // Buscar voz masculina en español
          final maleVoice = voices.firstWhere(
            (voice) => voice['locale']?.toString().startsWith('es') == true &&
                       (voice['name']?.toString().toLowerCase().contains('male') == true ||
                        voice['name']?.toString().toLowerCase().contains('masculino') == true),
            orElse: () => voices.firstWhere(
              (voice) => voice['locale']?.toString().startsWith('es') == true,
              orElse: () => voices.first,
            ),
          );
          if (maleVoice != null && maleVoice['name'] != null) {
            await _flutterTts.setVoice({'name': maleVoice['name'], 'locale': maleVoice['locale']});
          }
        }
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
      
      // Obtener habilidades
      _abilities = await pokemonDao.getPokemonAbilities(_pokemon!.id);
      
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
          // Obtener descripción (puede ser corta o larga, usaremos la primera disponible)
          _description = await _translationService.getFlavorText(
            flavorTextEntriesJson: _species!.flavorTextEntriesJson!,
          );
          // Por ahora, usar la misma descripción para corta y larga
          // TODO: Separar descripción corta y larga si hay múltiples entradas
          _shortDescription = _description;
          _longDescription = _description;
        }
        
        // Obtener evoluciones
        _evolutions = await _loadEvolutions(_species!);
      } else {
        _pokemonName = _pokemon!.name;
      }
      
      // Obtener variantes normales (con pokedex)
      final variantRelations = await variantsDao.getVariantsForPokemon(_pokemon!.id);
      if (variantRelations.isNotEmpty) {
        final variantIds = variantRelations.map((v) => v.variantPokemonId).toList();
        final pokedexDao = PokedexDao(widget.database);
        
        for (final variantId in variantIds) {
          final variant = await pokemonDao.getPokemonById(variantId);
          if (variant != null) {
            // Verificar si tiene pokedex asignada
            final species = await pokemonDao.getSpeciesByPokemonId(variantId);
            if (species != null) {
              final allPokedex = await pokedexDao.getAllPokedex();
              bool hasPokedex = false;
              for (final pokedex in allPokedex) {
                    final entries = await pokedexDao.getPokedexEntries(pokedex.id);
                    if (entries.any((e) => e.pokemonSpeciesId == species.id)) {
                      hasPokedex = true;
                      break;
                    }
              }
              
              if (hasPokedex) {
                _variants.add(variant);
              } else if (_isSpecialVariant(variant.name)) {
                _specialVariants.add(variant);
              }
            }
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
          final pokedexDao = PokedexDao(widget.database);
          
          for (final variantId in variantIds) {
            if (variantId != _pokemon!.id) {
              final variant = await pokemonDao.getPokemonById(variantId);
              if (variant != null) {
                // Verificar si tiene pokedex asignada
                final species = await pokemonDao.getSpeciesByPokemonId(variantId);
                if (species != null) {
                  final allPokedex = await pokedexDao.getAllPokedex();
                  bool hasPokedex = false;
                  for (final pokedex in allPokedex) {
                    final entries = await pokedexDao.getPokedexEntries(pokedex.id);
                    if (entries.any((e) => e.pokemonSpeciesId == species.id)) {
                      hasPokedex = true;
                      break;
                    }
                  }
                  
                  if (hasPokedex) {
                    _variants.add(variant);
                  } else if (_isSpecialVariant(variant.name)) {
                    _specialVariants.add(variant);
                  }
                }
              }
            }
          }
        }
      }
      
      // Obtener números de pokedex
      if (_species != null) {
        final pokedexDao = PokedexDao(widget.database);
        
        // Número en la pokedex usada para ordenar
        if (widget.pokedexId != null) {
          _pokedexEntryNumber = await pokedexDao.getEntryNumberForPokemon(
            widget.pokedexId!,
            _species!.id,
          );
        }
        
        // Número en la pokedex nacional
        _nationalEntryNumber = await pokedexDao.getNationalEntryNumber(_species!.id);
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
    
    // Esperar 500ms antes de reproducir el cry
    await Future.delayed(const Duration(milliseconds: 500));
    
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
        } else {
          print('[PokemonDetailScreen]   - audioPath original: $audioPathToPlay');
          print('[PokemonDetailScreen]   - audioPath local: $localAudioPath');
          
          // Verificar que el archivo existe
          final audioFile = File(localAudioPath);
          if (await audioFile.exists()) {
            // Reproducir desde archivo local usando UrlSource con file://
            print('[PokemonDetailScreen] 📦 Intentando reproducir audio desde archivo: $localAudioPath');
            final fileAudio = UrlSource('file://$localAudioPath');
            
            try {
              await _audioPlayer.play(fileAudio);
              print('[PokemonDetailScreen] ✅ Audio reproducido correctamente');
              
              // Esperar a que termine el audio (con timeout)
              await _audioPlayer.onPlayerComplete.first.timeout(
                const Duration(seconds: 10),
                onTimeout: () {
                  print('[PokemonDetailScreen] ⏱️ Timeout esperando que termine el audio');
                },
              );
              print('[PokemonDetailScreen] ✅ Audio terminado');
            } catch (e, stackTrace) {
              print('[PokemonDetailScreen] ❌ Error reproduciendo audio: $e');
              print('[PokemonDetailScreen] StackTrace: $stackTrace');
            }
          } else {
            print('[PokemonDetailScreen] ⚠️ Archivo de audio no existe: $localAudioPath');
          }
        }
      } catch (e, stackTrace) {
        print('[PokemonDetailScreen] ❌ Error preparando audio: $e');
        print('[PokemonDetailScreen] StackTrace: $stackTrace');
        // Si falla, continuar con TTS
      }
    } else {
      print('[PokemonDetailScreen] ⚠️ No hay ruta de audio disponible para este pokemon');
    }
    
    // Esperar 500ms después de que termine el cry
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Reproducir TTS si está inicializado
    if (_audioInitialized && _pokemonName != null) {
      try {
        // Helper para esperar a que termine el TTS
        Future<void> speakAndWait(String text) async {
          final completer = Completer<void>();
          
          // Configurar handler de completion
          _flutterTts.setCompletionHandler(() {
            if (!completer.isCompleted) {
              completer.complete();
            }
          });
          
          // Hablar
          await _flutterTts.speak(text);
          
          // Esperar a que termine (con timeout de seguridad)
          await completer.future.timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print('[PokemonDetailScreen] ⏱️ Timeout esperando que termine el TTS');
            },
          );
        }
        
        // Leer nombre
        await speakAndWait(_pokemonName!);
        
        // Leer descripción corta si existe
        if (_shortDescription != null && _shortDescription!.isNotEmpty) {
          await speakAndWait(_shortDescription!);
        }
        
        // Leer descripción larga si existe
        if (_longDescription != null && _longDescription!.isNotEmpty) {
          await speakAndWait(_longDescription!);
        }
      } catch (e) {
        // Si falla, continuar
        print('[PokemonDetailScreen] ❌ Error en TTS: $e');
      }
    }
  }
  
  /// Verificar si un pokemon es una variante especial (mega, gigamax, primal)
  bool _isSpecialVariant(String pokemonName) {
    final nameLower = pokemonName.toLowerCase();
    return nameLower.contains('gmax') || 
           nameLower.contains('mega') || 
           nameLower.contains('primal');
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  String? _getBestSvgImage() {
    return PokemonImageHelper.getBestImagePath(_pokemon, preferShiny: _isShiny);
  }
  
  bool _hasShinyImage() {
    return PokemonImageHelper.hasShinyImage(_pokemon);
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
                // Región y pokedex en la parte superior
                _buildRegionAndPokedex(),
                
                const SizedBox(height: 16),
                
                // Imagen del pokemon (con toggle shiny al pulsar)
                _buildImage(),
                
                const SizedBox(height: 16),
                
                // Nombre con primera letra mayúscula, #posición pokedex (nacional entre paréntesis)
                _buildPokemonName(),
                
                const SizedBox(height: 16),
                
                // Tipos (horizontal)
                if (_types.isNotEmpty) ...[
                  _buildTypesHorizontal(),
                  const SizedBox(height: 16),
                ],
                
                // Altura, peso y habilidad en la misma fila
                _buildInfo(),
                
                const SizedBox(height: 16),
                
                // Descripción
                if (_description != null && _description!.isNotEmpty) ...[
                  _buildDescription(),
                  const SizedBox(height: 16),
                ],
                
                // Estadísticas
                _buildStatsSection(),
                
                const SizedBox(height: 16),
                
                // Evoluciones (pre y post)
                _buildEvolutionsSection(),
                
                const SizedBox(height: 16),
                
                // Variantes especiales (mega, gigamax, primal sin pokedex)
                if (_specialVariants.isNotEmpty) ...[
                  _buildSpecialVariantsSection(),
                  const SizedBox(height: 16),
                ],
                
                // Movimientos (acordeón)
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

  Widget _buildRegionAndPokedex() {
    String regionText = '';
    if (widget.regionName != null) {
      regionText = widget.regionName!;
      if (widget.pokedexName != null) {
        regionText += ' (${widget.pokedexName})';
      }
    }
    
    if (regionText.isEmpty) return const SizedBox.shrink();
    
    return Center(
      child: Text(
        regionText,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
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
    );
  }
  
  Widget _buildPokemonName() {
    String name = _pokemonName ?? _pokemon?.name ?? 'Pokemon';
    // Primera letra en mayúscula
    if (name.isNotEmpty) {
      name = name[0].toUpperCase() + name.substring(1);
    }
    
    String numberText = '';
    if (_pokedexEntryNumber != null) {
      numberText = '#$_pokedexEntryNumber';
      if (_nationalEntryNumber != null) {
        numberText += ' (#$_nationalEntryNumber)';
      }
    } else if (_nationalEntryNumber != null) {
      numberText = '#$_nationalEntryNumber';
    }
    
    return Center(
      child: Column(
        children: [
          Text(
            name,
            style: const TextStyle(
              fontSize: 32,
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
          if (numberText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              numberText,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
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
          ],
        ],
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

  Widget _buildTypesHorizontal() {
    return Center(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: _types.map((type) {
          final colorHex = type.color;
          final color = colorHex != null 
              ? Color(ColorGenerator.hexToColor(colorHex))
              : Colors.grey;
          
          return Container(
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Altura
          if (_pokemon!.height != null)
            Expanded(
              child: _buildInfoItem('Altura', '${(_pokemon!.height! / 10).toStringAsFixed(1)} m'),
            ),
          if (_pokemon!.height != null && _pokemon!.weight != null)
            const SizedBox(width: 8),
          // Peso
          if (_pokemon!.weight != null)
            Expanded(
              child: _buildInfoItem('Peso', '${(_pokemon!.weight! / 10).toStringAsFixed(1)} kg'),
            ),
          if ((_pokemon!.height != null || _pokemon!.weight != null) && _abilities.isNotEmpty)
            const SizedBox(width: 8),
          // Habilidad
          if (_abilities.isNotEmpty)
            Expanded(
              child: _buildInfoItem('Habilidad', _abilities.map((a) => a.name).join(', ')),
            ),
        ],
      ),
    );
  }
  
  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
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
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Colors.black,
                blurRadius: 2,
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
  
  Widget _buildDescription() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        _description ?? '',
        style: const TextStyle(
          fontSize: 16,
          color: Colors.white,
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
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
            child: ExpansionTile(
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
              childrenPadding: EdgeInsets.zero,
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                    child: Column(
                      children: _moves.map((move) => _buildMoveCard(move)).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoveCard(Move move) {
    final moveType = _moveTypes[move.id];
    final damageClass = _moveDamageClasses[move.id] ?? 'N/A';
    final typeList = moveType != null ? <Type>[moveType] : <Type>[];
    
    // Obtener nombre traducido del movimiento
    return FutureBuilder<String>(
      future: _translationService.getLocalizedName(
        entityType: 'move',
        entityId: move.apiId,
        fallbackName: move.name,
      ),
      builder: (context, snapshot) {
        final moveName = snapshot.data ?? move.name;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: TypeStripeBackground(
              types: typeList,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Contenido principal
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Nombre del movimiento
                          Text(
                            moveName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
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
                          // Tipo de daño y poder
                          Row(
                            children: [
                              // Tipo de daño (físico, especial, etc.)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  damageClass,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Poder de ataque
                              if (move.power != null)
                                Text(
                                  'Poder: ${move.power}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black,
                                        blurRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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

  Widget _buildSpecialVariantsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Variantes Especiales',
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
              itemCount: _specialVariants.length,
              itemBuilder: (context, index) {
                final variant = _specialVariants[index];
                return _buildVariantCard(variant);
              },
            ),
          ),
        ],
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
    return PokemonImageHelper.getBestImagePath(pokemon);
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
