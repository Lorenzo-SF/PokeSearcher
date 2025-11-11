import 'dart:async';
import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../services/config/app_config.dart';
import '../database/daos/region_dao.dart';
import '../database/daos/pokedex_dao.dart';
import '../database/daos/pokemon_dao.dart';
import '../services/download/download_service.dart';
import '../services/download/download_manager.dart';
import 'pokemon_list_screen.dart';
import '../utils/logger.dart';

class RegionsScreen extends StatefulWidget {
  final AppDatabase database;
  final AppConfig appConfig;

  const RegionsScreen({
    super.key,
    required this.database,
    required this.appConfig,
  });

  @override
  State<RegionsScreen> createState() => _RegionsScreenState();
}

class _RegionsScreenState extends State<RegionsScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  List<RegionData> _regions = [];
  bool _isLoading = true;
  // Mapa para rastrear qué regiones están completamente descargadas
  final Map<int, bool> _regionCompleteStatus = {};
  // Mapa para almacenar los 3 pokemons iniciales de cada región
  final Map<int, List<PokemonData>> _starterPokemons = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _loadRegions();
  }

  Future<void> _loadRegions() async {
    try {
      final regionDao = RegionDao(widget.database);
      final pokedexDao = PokedexDao(widget.database);
      final pokemonDao = PokemonDao(widget.database);
      final downloadService = DownloadService(database: widget.database);
      final regions = await regionDao.getAllRegions();
      
      // Obtener contador de pokemons únicos, estado de descarga y pokemons iniciales para cada región
      final regionsWithData = await Future.wait(
        regions.map((region) async {
          final pokemonCount = await pokedexDao.getUniquePokemonCountByRegion(region.id);
          final isComplete = await downloadService.isRegionFullyDownloaded(region.id);
          
          // Cargar los 3 pokemons iniciales
          List<PokemonData> starters = [];
          try {
            final starterSpecies = await pokedexDao.getStarterPokemon(region.id);
            for (final species in starterSpecies) {
              final pokemons = await pokemonDao.getPokemonBySpecies(species.id);
              if (pokemons.isNotEmpty) {
                starters.add(pokemons.first); // Tomar el primer pokemon de la especie
              }
            }
          } catch (e) {
            Logger.error('Error al cargar pokemons iniciales', context: LogContext.region, error: e);
          }
          
          return {
            'region': RegionData(
              id: region.id,
              name: region.name,
              pokedexCount: pokemonCount, // Ahora es el conteo de pokemons únicos
            ),
            'isComplete': isComplete,
            'starters': starters,
          };
        }),
      );
      
      // Separar regiones, estados y pokemons iniciales
      final List<RegionData> regionsList = [];
      final Map<int, bool> completeStatus = {};
      final Map<int, List<PokemonData>> starterPokemons = {};
      
      for (final data in regionsWithData) {
        final region = data['region'] as RegionData;
        regionsList.add(region);
        completeStatus[region.id] = data['isComplete'] as bool;
        starterPokemons[region.id] = data['starters'] as List<PokemonData>;
      }
      
      setState(() {
        _regions = regionsList;
        _regionCompleteStatus.clear();
        _regionCompleteStatus.addAll(completeStatus);
        _starterPokemons.clear();
        _starterPokemons.addAll(starterPokemons);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  /// Actualizar el estado de descarga de una región específica y recargar pokemons iniciales
  Future<void> _refreshRegionStatus(int regionId) async {
    try {
      final downloadService = DownloadService(database: widget.database);
      final pokedexDao = PokedexDao(widget.database);
      final pokemonDao = PokemonDao(widget.database);
      
      final isComplete = await downloadService.isRegionFullyDownloaded(regionId);
      final pokemonCount = await pokedexDao.getUniquePokemonCountByRegion(regionId);
      
      // Recargar los 3 pokemons iniciales
      List<PokemonData> starters = [];
      try {
        final starterSpecies = await pokedexDao.getStarterPokemon(regionId);
        for (final species in starterSpecies) {
          final pokemons = await pokemonDao.getPokemonBySpecies(species.id);
          if (pokemons.isNotEmpty) {
            starters.add(pokemons.first);
          }
        }
      } catch (e) {
        Logger.error('Error al recargar pokemons iniciales', context: LogContext.region, error: e);
      }
      
      if (mounted) {
        setState(() {
          _regionCompleteStatus[regionId] = isComplete;
          _starterPokemons[regionId] = starters;
          // Actualizar también el contador de pokemons en la lista de regiones
          final regionIndex = _regions.indexWhere((r) => r.id == regionId);
          if (regionIndex != -1) {
            _regions[regionIndex] = RegionData(
              id: _regions[regionIndex].id,
              name: _regions[regionIndex].name,
              pokedexCount: pokemonCount,
            );
          }
        });
      }
    } catch (e) {
      Logger.error('Error al actualizar estado de región', context: LogContext.region, error: e);
    }
  }
  
  /// Obtener la mejor imagen disponible para un pokemon
  String? _getBestImageUrl(PokemonData? pokemon) {
    if (pokemon == null) return null;
    
    // Prioridad: artwork oficial > sprite front default
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

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
  }

  String _getRegionImageName(String regionName) {
    // Normalizar nombre de región para coincidir con assets
    final normalized = regionName.toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('-', '');
    return 'assets/$normalized.png';
  }
  
  /// Manejar tap en una tarjeta de región
  Future<void> _handleRegionTap(RegionData region) async {
    final downloadService = DownloadService(database: widget.database);
    
    // Verificar si la región está completamente descargada
    // IMPORTANTE: Verificar siempre antes de decidir qué hacer
    final isComplete = await downloadService.isRegionFullyDownloaded(region.id);
    
    if (isComplete) {
      // Navegar a la lista de pokemons
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PokemonListScreen(
              database: widget.database,
              appConfig: widget.appConfig,
              regionId: region.id,
              regionName: region.name,
            ),
          ),
        );
        // Refrescar el estado de la región cuando se vuelve de la navegación
        await _refreshRegionStatus(region.id);
      }
    } else {
      // Descargar solo las pokedexes incompletas
      final progressController = _DownloadProgressController();
      bool dialogShown = false;
      
      try {
        // Mostrar diálogo de progreso
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => _DownloadProgressDialog(
            regionName: region.name,
            controller: progressController,
          ),
        );
        dialogShown = true;
        
        // Descargar solo pokedexes incompletas
        await downloadService.downloadIncompletePokedexes(
          regionId: region.id,
          onProgress: (progress) {
            // Actualizar diálogo con progreso
            progressController.updateProgress(progress);
          },
        );
        
        // Cerrar diálogo y limpiar controlador
        progressController.dispose();
        if (mounted && dialogShown) {
          Navigator.of(context).pop();
        }
        
        // Actualizar el estado de la región después de descargar (incluye pokemons iniciales)
        await _refreshRegionStatus(region.id);
        
        // Esperar un momento para que el setState se procese
        await Future.delayed(const Duration(milliseconds: 200));
        
        // Verificar nuevamente desde el servicio para asegurar que está actualizado
        final isNowComplete = await downloadService.isRegionFullyDownloaded(region.id);
        
        // Actualizar el estado en memoria
        if (mounted) {
          setState(() {
            _regionCompleteStatus[region.id] = isNowComplete;
          });
        }
        
        if (mounted) {
          if (isNowComplete) {
            // Si ahora está completa, navegar a la lista de pokemons
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => PokemonListScreen(
                  database: widget.database,
                  appConfig: widget.appConfig,
                  regionId: region.id,
                  regionName: region.name,
                ),
              ),
            );
            // Refrescar el estado de la región cuando se vuelve de la navegación
            await _refreshRegionStatus(region.id);
          } else {
            // Mostrar mensaje de éxito
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${region.name} actualizada'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        // Cerrar diálogo y limpiar controlador
        progressController.dispose();
        if (mounted && dialogShown) {
          Navigator.of(context).pop();
        }
        
        // Mostrar error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al descargar ${region.name}: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PokeSearch'),
        centerTitle: true,
        backgroundColor: const Color(0xFFDC143C),
      ),
      drawer: _buildDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _regions.isEmpty
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
                        'No hay regiones disponibles',
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Asegúrate de haber descargado los datos iniciales',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    // Fondo dinámico con AnimatedSwitcher
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: child,
                        );
                      },
                      child: Container(
                        key: ValueKey(_currentPage),
                        decoration: BoxDecoration(
                          image: DecorationImage(
                            image: AssetImage(
                              _getRegionImageName(
                                _regions[_currentPage].name,
                              ),
                            ),
                            fit: BoxFit.cover,
                            colorFilter: ColorFilter.mode(
                              Colors.black.withOpacity(0.5),
                              BlendMode.darken,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Contenido
                    Column(
                      children: [
                        Expanded(
                          child: PageView.builder(
                            controller: _pageController,
                            onPageChanged: _onPageChanged,
                            itemCount: _regions.length,
                            itemBuilder: (context, index) {
                              return _buildRegionCard(_regions[index], index);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }

  Widget _buildRegionCard(RegionData region, int index) {
    final isActive = index == _currentPage;
    
    return Center(
      child: GestureDetector(
        onTap: isActive ? () => _handleRegionTap(region) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          margin: EdgeInsets.symmetric(
            horizontal: isActive ? 16 : 32,
            vertical: isActive ? 8 : 16,
          ),
          transform: Matrix4.identity()
            ..scale(isActive ? 1.05 : 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isActive ? 0.4 : 0.2),
                  blurRadius: isActive ? 20 : 10,
                  spreadRadius: isActive ? 5 : 2,
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Nombre de la región
                Text(
                  region.name,
                  style: const TextStyle(
                    fontSize: 28,
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
                const SizedBox(height: 24),
                // 3 imágenes de pokemon iniciales
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) {
                    final starters = _starterPokemons[region.id] ?? [];
                    final pokemon = i < starters.length ? starters[i] : null;
                    final imageUrl = _getBestImageUrl(pokemon);
                    
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: Image.network(
                                imageUrl,
                                width: 60,
                                height: 60,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.catching_pokemon,
                                    color: Colors.white,
                                    size: 40,
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
                              color: Colors.white,
                              size: 40,
                            ),
                    );
                  }),
                ),
                const SizedBox(height: 24),
                // Contador de pokedex
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC143C).withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${region.pokedexCount ?? 0} Pokémon',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Botón de acción (usa el estado en memoria para actualización inmediata)
                Builder(
                  builder: (context) {
                    final isComplete = _regionCompleteStatus[region.id] ?? false;
                    return ElevatedButton(
                      onPressed: isActive ? () => _handleRegionTap(region) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC143C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Text(
                        isComplete ? 'Ver pokemons' : 'Descargar info',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(
              color: Color(0xFFDC143C),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.catching_pokemon,
                  size: 64,
                  color: Colors.white,
                ),
                SizedBox(height: 8),
                Text(
                  'PokeSearch',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.explore),
            title: const Text('Regiones'),
            selected: true,
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.category),
            title: const Text('Tipos'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Navegar a tipos
            },
          ),
          ListTile(
            leading: const Icon(Icons.flash_on),
            title: const Text('Movimientos'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Navegar a movimientos
            },
          ),
          ListTile(
            leading: const Icon(Icons.sports_esports),
            title: const Text('Juegos'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Navegar a juegos
            },
          ),
          ListTile(
            leading: const Icon(Icons.inventory),
            title: const Text('Objetos'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Navegar a objetos
            },
          ),
          ListTile(
            leading: const Icon(Icons.location_on),
            title: const Text('Localizaciones'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Navegar a localizaciones
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Configuración'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Navegar a configuración
            },
          ),
        ],
      ),
    );
  }
}

// Clase temporal para datos de región (hasta que se implemente el DAO completo)
class RegionData {
  final int id;
  final String name;
  final int? pokedexCount;

  RegionData({
    required this.id,
    required this.name,
    this.pokedexCount,
  });
}

/// Controlador para actualizar el diálogo de progreso
class _DownloadProgressController {
  DownloadProgress? _currentProgress;
  final _progressStream = StreamController<DownloadProgress>.broadcast();
  
  Stream<DownloadProgress> get progressStream => _progressStream.stream;
  
  void updateProgress(DownloadProgress progress) {
    _currentProgress = progress;
    _progressStream.add(progress);
  }
  
  DownloadProgress? get currentProgress => _currentProgress;
  
  void dispose() {
    _progressStream.close();
  }
}

/// Diálogo de progreso de descarga
class _DownloadProgressDialog extends StatefulWidget {
  final String regionName;
  final _DownloadProgressController controller;
  
  const _DownloadProgressDialog({
    required this.regionName,
    required this.controller,
  });
  
  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  DownloadProgress? _progress;
  StreamSubscription<DownloadProgress>? _subscription;
  
  @override
  void initState() {
    super.initState();
    _progress = widget.controller.currentProgress;
    
    // Escuchar actualizaciones de progreso
    _subscription = widget.controller.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _progress = progress;
        });
      }
    });
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final percentage = progress?.percentage ?? 0.0;
    final completed = progress?.completed ?? 0;
    final total = progress?.total ?? 0;
    final currentEntity = progress?.currentEntity ?? 'Preparando...';
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Título
            Text(
              'Descargando ${widget.regionName}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFFDC143C),
              ),
            ),
            const SizedBox(height: 24),
            
            // Estado actual
            Text(
              currentEntity,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            
            // Barra de progreso
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: percentage,
                minHeight: 8,
                backgroundColor: Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFDC143C),
                ),
              ),
            ),
            const SizedBox(height: 12),
            
            // Contador y porcentaje
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$completed / $total',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                Text(
                  '${(percentage * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFDC143C),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

