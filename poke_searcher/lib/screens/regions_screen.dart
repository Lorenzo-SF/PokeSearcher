import 'dart:async';
import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../services/config/app_config.dart';
import '../database/daos/region_dao.dart';
import '../database/daos/pokedex_dao.dart';
import '../database/daos/pokemon_dao.dart';
import '../services/download/download_service.dart';
import '../utils/pokemon_image_helper.dart';
import '../widgets/pokemon_image.dart';
import 'pokemon_list_screen.dart';
import 'types_list_screen.dart';
import 'configuration_screen.dart';
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
      final regions = await regionDao.getAllRegions();
      
      // Primero mostrar las regiones básicas (sin datos adicionales) para que la UI aparezca rápido
      final regionsList = regions.map((r) => RegionData(
        id: r.id,
        name: r.name,
        pokedexCount: 0, // Se actualizará después
      )).toList();
      
      // Añadir Pokedex Nacional como región adicional
      final nationalPokedex = await pokedexDao.getNationalPokedex();
      if (nationalPokedex != null) {
        final nationalEntries = await pokedexDao.getPokedexEntries(nationalPokedex.id);
        regionsList.add(RegionData(
          id: -1, // ID especial para pokedex nacional
          name: 'Pokedex Nacional',
          pokedexCount: nationalEntries.length,
        ));
      }
      
      setState(() {
        _regions = regionsList;
        _isLoading = false; // Mostrar UI inmediatamente
      });
      
      // Luego cargar datos adicionales de forma asíncrona (sin bloquear UI)
      _loadRegionsAdditionalData(regionsList);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  /// Cargar datos adicionales de regiones de forma asíncrona
  Future<void> _loadRegionsAdditionalData(List<RegionData> regions) async {
    try {
      final pokedexDao = PokedexDao(widget.database);
      final pokemonDao = PokemonDao(widget.database);
      final downloadService = DownloadService(database: widget.database);
      
      // Cargar datos para cada región de forma incremental
      for (final region in regions) {
        if (!mounted) break;
        
        // Cargar datos de esta región
        final pokemonCount = await pokedexDao.getUniquePokemonCountByRegion(region.id);
        final isComplete = await downloadService.isRegionFullyDownloaded(region.id);
        
        // Cargar los 3 pokemons iniciales
        List<PokemonData> starters = [];
        try {
          final starterSpecies = await pokedexDao.getStarterPokemon(region.id);
          for (final species in starterSpecies) {
            final pokemons = await pokemonDao.getPokemonBySpecies(species.id);
            if (pokemons.isNotEmpty) {
              starters.add(pokemons.first);
            }
          }
        } catch (e) {
          Logger.error('Error al cargar pokemons iniciales', context: LogContext.region, error: e);
        }
        
        // Actualizar UI incrementalmente
        if (mounted) {
          setState(() {
            // Actualizar región con el conteo correcto
            final index = _regions.indexWhere((r) => r.id == region.id);
            if (index >= 0) {
              _regions[index] = RegionData(
                id: region.id,
                name: region.name,
                pokedexCount: pokemonCount,
              );
            }
            _regionCompleteStatus[region.id] = isComplete;
            _starterPokemons[region.id] = starters;
          });
        }
        
        // Pequeña pausa para no bloquear el hilo principal
        await Future.delayed(const Duration(milliseconds: 10));
      }
    } catch (e) {
      Logger.error('Error al cargar datos adicionales de regiones', context: LogContext.region, error: e);
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
  
  /// Obtener la mejor imagen disponible para un pokemon desde assets
  String? _getBestImagePath(PokemonData? pokemon) {
    return PokemonImageHelper.getBestImagePath(pokemon);
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
    // Si es Pokedex Nacional, usar national.png
    if (regionName.toLowerCase() == 'pokedex nacional') {
      return 'assets/national.png';
    }
    // Normalizar nombre de región para coincidir con assets
    final normalized = regionName.toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('-', '');
    return 'assets/$normalized.png';
  }
  
  /// Manejar tap en una tarjeta de región - Navega directamente al listado
  Future<void> _handleRegionTap(RegionData region) async {
    // Navegar directamente a la lista de pokemons
    if (mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PokemonListScreen(
            database: widget.database,
            appConfig: widget.appConfig,
            regionId: region.id == -1 ? null : region.id, // null para pokedex nacional
            regionName: region.name,
          ),
        ),
      );
      // Refrescar el estado de la región cuando se vuelve de la navegación
      if (region.id != -1) {
        await _refreshRegionStatus(region.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Sin AppBar, pero mantenemos el drawer
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          // Contenido principal
          _isLoading
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
                        width: double.infinity,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          image: DecorationImage(
                            image: AssetImage(
                              _getRegionImageName(
                                _regions[_currentPage].name,
                              ),
                            ),
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            colorFilter: ColorFilter.mode(
                              Colors.black.withOpacity(0.5),
                              BlendMode.darken,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Contenido centrado y estirado
                    Center(
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.9,
                        height: MediaQuery.of(context).size.height * 0.85,
                        child: PageView.builder(
                          controller: _pageController,
                          onPageChanged: _onPageChanged,
                          itemCount: _regions.length,
                          itemBuilder: (context, index) {
                            return _buildRegionCard(_regions[index], index);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
          // Botón flotante para abrir el menú
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: GestureDetector(
              onTap: () {
                Scaffold.of(context).openDrawer();
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.menu,
                  color: Colors.white,
                ),
              ),
            ),
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
            horizontal: isActive ? 8 : 16,
            vertical: isActive ? 4 : 8,
          ),
          transform: Matrix4.identity()
            ..scale(isActive ? 1.0 : 0.9),
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
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Nombre de la región con número de pokémons entre paréntesis
                Text(
                  '${region.name} (${region.pokedexCount ?? 0})',
                  style: const TextStyle(
                    fontSize: 22,
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
                const SizedBox(height: 16),
                // 3 imágenes de pokemon iniciales (agrandadas)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) {
                    final starters = _starterPokemons[region.id] ?? [];
                    final pokemon = i < starters.length ? starters[i] : null;
                    final imagePath = _getBestImagePath(pokemon);
                    
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: PokemonImage(
                          imagePath: imagePath,
                          width: 100,
                          height: 100,
                          fit: BoxFit.contain,
                          errorWidget: const Icon(
                            Icons.catching_pokemon,
                            color: Colors.white,
                            size: 50,
                          ),
                        ),
                      ),
                    );
                  }),
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
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => TypesListScreen(
                    database: widget.database,
                    appConfig: widget.appConfig,
                  ),
                ),
              );
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
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ConfigurationScreen(
                    database: widget.database,
                    appConfig: widget.appConfig,
                  ),
                ),
              );
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


