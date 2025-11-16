import 'dart:async';
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
  final List<PokemonData> _specialVariants = []; // mega, gigamax, primal sin pokedex (solo del pokemon actual)
  final List<PokemonData> _allEvolutionVariants = []; // variantes de TODA la gama evolutiva
  String? _genus;
  String? _description;
  String? _pokemonName;
  bool _isLoading = true;
  String _currentImageType = 'front_transparent'; // front_transparent, front_shiny_transparent, front_gray
  late TranslationService _translationService;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();
  bool _audioInitialized = false;
  List<Ability> _abilities = []; // Habilidades del pokemon
  int? _pokedexEntryNumber; // Número en la pokedex usada para ordenar
  int? _nationalEntryNumber; // Número en la pokedex nacional

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
      // Forzar idioma a castellano (es-ES)
      const locale = 'es-ES';
      
      await _flutterTts.setLanguage(locale);
      
      // Configuración para voz robótica
      await _flutterTts.setSpeechRate(0.2); // Más lento para sonar más robótico
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(0.1); // Pitch muy bajo para sonar más robótico y grave
      
      // Intentar configurar voz masculina en castellano
      try {
        // Obtener todas las voces disponibles
        final voices = await _flutterTts.getVoices;
        if (voices != null && voices.isNotEmpty) {
          print('[PokemonDetailScreen] 🔍 Buscando voz masculina en castellano...');
          print('[PokemonDetailScreen]   Voces disponibles: ${voices.length}');
          
          // Buscar voz masculina en castellano con múltiples criterios
          Map<String, dynamic>? selectedVoice;
          
          // Prioridad 1: Buscar voces específicamente masculinas en es-ES
          for (final voice in voices) {
            final voiceLocale = voice['locale']?.toString().toLowerCase() ?? '';
            final voiceName = voice['name']?.toString().toLowerCase() ?? '';
            final voiceLabel = voice['label']?.toString().toLowerCase() ?? '';
            
            // Verificar que sea español
            if (voiceLocale.startsWith('es')) {
              // Buscar indicadores de voz masculina
              final isMale = voiceName.contains('male') || 
                            voiceName.contains('masculino') ||
                            voiceName.contains('hombre') ||
                            voiceName.contains('man') ||
                            voiceName.contains('masc') ||
                            voiceLabel.contains('male') ||
                            voiceLabel.contains('masculino') ||
                            voiceLabel.contains('hombre') ||
                            voiceLabel.contains('man') ||
                            voiceLabel.contains('masc');
              
              if (isMale) {
                selectedVoice = voice;
                print('[PokemonDetailScreen] ✅ Voz masculina encontrada: ${voice['name']} (${voice['locale']})');
                break;
              }
            }
          }
          
          // Prioridad 2: Si no se encontró voz masculina explícita, buscar cualquier voz en es-ES
          // y verificar por nombre común de voces masculinas
          if (selectedVoice == null) {
            for (final voice in voices) {
              final voiceLocale = voice['locale']?.toString().toLowerCase() ?? '';
              final voiceName = voice['name']?.toString().toLowerCase() ?? '';
              
              if (voiceLocale == 'es-es' || voiceLocale == 'es') {
                // Nombres comunes de voces masculinas en español
                final commonMaleNames = [
                  'pablo', 'carlos', 'jorge', 'luis', 'diego', 'miguel',
                  'antonio', 'juan', 'pedro', 'manuel', 'jose', 'francisco',
                  'es-es', 'es_es', 'spanish', 'español'
                ];
                
                final mightBeMale = commonMaleNames.any((name) => voiceName.contains(name));
                
                if (mightBeMale || selectedVoice == null) {
                  selectedVoice = voice;
                  print('[PokemonDetailScreen] ✅ Voz en castellano seleccionada: ${voice['name']} (${voice['locale']})');
                  // Continuar buscando por si hay una mejor opción
                }
              }
            }
          }
          
          // Prioridad 3: Cualquier voz en español como último recurso
          if (selectedVoice == null) {
            for (final voice in voices) {
              final voiceLocale = voice['locale']?.toString().toLowerCase() ?? '';
              if (voiceLocale.startsWith('es')) {
                selectedVoice = voice;
                print('[PokemonDetailScreen] ⚠️ Usando cualquier voz en español: ${voice['name']} (${voice['locale']})');
                break;
              }
            }
          }
          
          // Configurar la voz seleccionada
          if (selectedVoice != null && selectedVoice['name'] != null) {
            await _flutterTts.setVoice({
              'name': selectedVoice['name'], 
              'locale': selectedVoice['locale'] ?? locale
            });
            print('[PokemonDetailScreen] ✅ Voz TTS configurada: ${selectedVoice['name']} (${selectedVoice['locale']})');
          } else {
            print('[PokemonDetailScreen] ⚠️ No se encontró voz adecuada, usando configuración por defecto');
          }
        } else {
          print('[PokemonDetailScreen] ⚠️ No hay voces disponibles');
        }
      } catch (e) {
        print('[PokemonDetailScreen] ⚠️ No se pudo configurar voz específica: $e');
        // Si no está disponible, continuar con el motor por defecto
        // Los parámetros de pitch y rate ya están configurados para sonar robótico
      }
      
      setState(() {
        _audioInitialized = true;
      });
      
      print('[PokemonDetailScreen] ✅ TTS inicializado: idioma=es-ES, rate=0.2, pitch=0.1');
    } catch (e) {
      print('[PokemonDetailScreen] ⚠️ Error inicializando TTS: $e');
      // Si falla, continuar sin TTS
      setState(() {
        _audioInitialized = false;
      });
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
      // OPTIMIZACIÓN: Cargar todos los tipos y clases de daño UNA VEZ antes del loop
      _moveTypes.clear();
      _moveDamageClasses.clear();
      
      if (_moves.isNotEmpty) {
        // Cargar todos los tipos y clases de daño de una vez
        final allTypes = await widget.database.select(widget.database.types).get();
        final allDamageClasses = await widget.database.select(widget.database.moveDamageClasses).get();
        
        // Crear mapas para búsqueda rápida
        final typesMap = {for (var t in allTypes) t.id: t};
        final damageClassesMap = {for (var dc in allDamageClasses) dc.id: dc};
        
        for (final move in _moves) {
          // Obtener tipo del movimiento
          if (move.typeId != null) {
            _moveTypes[move.id] = typesMap[move.typeId];
          }
          
          // Obtener clase de daño del movimiento
          if (move.damageClassId != null) {
            final damageClass = damageClassesMap[move.damageClassId];
            _moveDamageClasses[move.id] = damageClass?.name;
          }
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
          // Obtener descripción (flavor_text) en el idioma configurado
          _description = await _translationService.getFlavorText(
            flavorTextEntriesJson: _species!.flavorTextEntriesJson!,
          );
        }
        
        // Obtener evoluciones
        _evolutions = await _loadEvolutions(_species!);
        
        // Cargar variantes de TODA la gama evolutiva (evoluciones + preevoluciones + pokemon actual)
        await _loadAllEvolutionVariants();
      } else {
        _pokemonName = _pokemon!.name;
      }
      
      // Obtener variantes normales (con pokedex) - solo del pokemon actual
      final variantRelations = await variantsDao.getVariantsForPokemon(_pokemon!.id);
      final pokedexDao = PokedexDao(widget.database);
      
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
      
      if (variantRelations.isNotEmpty) {
        final variantIds = variantRelations.map((v) => v.variantPokemonId).toList();
        
        // OPTIMIZACIÓN: Cargar todos los pokemons de una vez
        final variantPokemons = await Future.wait(
          variantIds.map((id) => pokemonDao.getPokemonById(id)),
        );
        
        for (final variant in variantPokemons) {
          if (variant == null) continue;
          
          if (hasPokedexEntry(variant.id)) {
            _variants.add(variant);
          } else if (_isSpecialVariant(variant.name)) {
            _specialVariants.add(variant);
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
          
          // OPTIMIZACIÓN: Cargar todos los pokemons de una vez
          final variantPokemons = await Future.wait(
            variantIds.where((id) => id != _pokemon!.id).map((id) => pokemonDao.getPokemonById(id)),
          );
          
          for (final variant in variantPokemons) {
            if (variant == null) continue;
            
            if (hasPokedexEntry(variant.id)) {
              _variants.add(variant);
            } else if (_isSpecialVariant(variant.name)) {
              _specialVariants.add(variant);
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
        
        // Leer nombre del pokemon
        if (_pokemonName != null && _pokemonName!.isNotEmpty) {
          await speakAndWait(_pokemonName!);
        }
        
        // Leer genus si existe
        if (_genus != null && _genus!.isNotEmpty) {
          await speakAndWait(_genus!);
        }
        
        // Leer flavor_text (descripción) si existe
        if (_description != null && _description!.isNotEmpty) {
          await speakAndWait(_description!);
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


  /// Cargar evoluciones usando la evolution chain de la especie
  /// Usa la función helper del DAO que procesa la evolution chain
  Future<List<PokemonData>> _loadEvolutions(PokemonSpecy species) async {
    if (species.evolutionChainId == null) return [];
    
    try {
      final pokemonDao = PokemonDao(widget.database);
      
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
  /// Usa las evolution chains para obtener todas las especies relacionadas
  /// Reglas:
  /// - Si son variantes con pokedex, solo mostrar la default: true
  /// - Si son variantes sin pokedex, mostrar todas
  Future<void> _loadAllEvolutionVariants() async {
    _allEvolutionVariants.clear();
    
    try {
      final pokemonDao = PokemonDao(widget.database);
      final variantsDao = PokemonVariantsDao(widget.database);
      final pokedexDao = PokedexDao(widget.database);
      
      if (_species == null || _species!.evolutionChainId == null) {
        return;
      }
      
      // Obtener todas las especies relacionadas de la evolution chain
      final relatedSpecies = await pokemonDao.getRelatedSpecies(_species!);
      
      // Para cada especie relacionada, buscar TODAS sus variantes
      final Set<int> addedVariantIds = {}; // Para evitar duplicados
      final allPokedex = await pokedexDao.getAllPokedex();
      
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
          final variant = await pokemonDao.getPokemonById(variantId);
          if (variant == null) continue;
          
          // Verificar si esta variante tiene pokedex
          for (final pokedex in allPokedex) {
            final entries = await pokedexDao.getPokedexEntries(pokedex.id);
            if (entries.any((e) => e.pokemonId == variantId)) {
              variantsWithPokedex.add(variantId);
              break;
            }
          }
        }
        
        // Si hay variantes con pokedex, solo mostrar el default
        // Si no hay variantes con pokedex, mostrar todas las variantes
        if (variantsWithPokedex.isNotEmpty) {
          // Solo mostrar el default si no está ya añadido y no es el pokemon actual
          if (!addedVariantIds.contains(defaultPokemon.id) && 
              defaultPokemon.id != _pokemon?.id) {
            _allEvolutionVariants.add(defaultPokemon);
            addedVariantIds.add(defaultPokemon.id);
          }
        } else {
          // Mostrar todas las variantes (sin pokedex)
          for (final variantRelation in variantRelations) {
            final variantId = variantRelation.variantPokemonId;
            
            if (addedVariantIds.contains(variantId)) {
              continue;
            }
            
            final variant = await pokemonDao.getPokemonById(variantId);
            if (variant != null) {
              _allEvolutionVariants.add(variant);
              addedVariantIds.add(variantId);
            }
          }
        }
      }
    } catch (e) {
      print('[PokemonDetailScreen] ⚠️ Error cargando variantes de gama evolutiva: $e');
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
                // 1. Región y pokedex en la parte superior
                _buildRegionAndPokedex(),
                
                const SizedBox(height: 16),
                
                // 2. Nombre con primera letra mayúscula, #posición pokedex (nacional entre paréntesis)
                _buildPokemonName(),
                
                const SizedBox(height: 16),
                
                // 3. Imagen del pokemon (con toggle shiny al pulsar)
                _buildImage(),
                
                const SizedBox(height: 16),
                
                // 4. Tipos (horizontal)
                if (_types.isNotEmpty) ...[
                  _buildTypesHorizontal(),
                  const SizedBox(height: 16),
                ],
                
                // 5. Altura, peso y habilidad en la misma fila
                _buildInfo(),
                
                const SizedBox(height: 16),
                
                // 6. Descripción
                if (_description != null && _description!.isNotEmpty) ...[
                  _buildDescription(),
                  const SizedBox(height: 16),
                ],
                
                // 7. Estadísticas
                _buildStatsSection(),
                
                const SizedBox(height: 16),
                
                // 8. Evoluciones (pre y post)
                _buildEvolutionsSection(),
                
                const SizedBox(height: 16),
                
                // 9. Variantes (con y sin pokedex) - para TODA la gama evolutiva
                if (_allEvolutionVariants.isNotEmpty) ...[
                  _buildVariantsSection(_allEvolutionVariants),
                  const SizedBox(height: 16),
                ],
                
                // 10. Movimientos (acordeón)
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
    // Usar front_transparent por defecto, con toggle para cambiar entre tipos
    final imagePathFuture = PokemonImageHelper.getBestImagePath(
      _pokemon,
      appConfig: widget.appConfig,
      database: widget.database,
      imageType: _currentImageType,
    );
    
    return Center(
      child: GestureDetector(
        onTap: _toggleImageType,
        child: Container(
          width: 300,
          height: 300,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: FutureBuilder<String?>(
            future: imagePathFuture,
            builder: (context, snapshot) {
              return PokemonImage(
                imagePath: snapshot.data,
                fit: BoxFit.contain,
                width: 300,
                height: 300,
                errorWidget: const Icon(
                  Icons.catching_pokemon,
                  size: 150,
                  color: Colors.white,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
  
  void _toggleImageType() {
    setState(() {
      // Ciclar entre: front_transparent -> front_shiny_transparent -> front_gray -> front_transparent
      if (_currentImageType == 'front_transparent') {
        _currentImageType = 'front_shiny_transparent';
      } else if (_currentImageType == 'front_shiny_transparent') {
        _currentImageType = 'front_gray';
      } else {
        _currentImageType = 'front_transparent';
      }
    });
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
    final imageUrlFuture = _getBestImageForPokemon(evolution);
    
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
        child: FutureBuilder<String?>(
          future: imageUrlFuture,
          builder: (context, snapshot) {
            return _buildPokemonCard(
              pokemon: evolution,
              imageUrl: snapshot.data,
            );
          },
        ),
      ),
    );
  }


  Widget _buildVariantsSection([List<PokemonData>? variants]) {
    final variantsToShow = variants ?? _variants;
    if (variantsToShow.isEmpty) {
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
              itemCount: variantsToShow.length,
              itemBuilder: (context, index) {
                final variant = variantsToShow[index];
                return _buildVariantCard(variant);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantCard(PokemonData variant) {
    final imageUrlFuture = _getBestImageForPokemon(variant);
    
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
        child: FutureBuilder<String?>(
          future: imageUrlFuture,
          builder: (context, snapshot) {
            return _buildPokemonCard(
              pokemon: variant,
              imageUrl: snapshot.data,
            );
          },
        ),
      ),
    );
  }

  Future<String?> _getBestImageForPokemon(PokemonData pokemon) async {
    // Para evolutions y variants, usar front_transparent si hay configuración
    return await PokemonImageHelper.getBestImagePath(
      pokemon,
      appConfig: widget.appConfig,
      database: widget.database,
      imageType: 'front_transparent',
    );
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
