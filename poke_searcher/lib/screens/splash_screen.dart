import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../database/app_database.dart';
import '../services/config/app_config.dart';
import '../services/download/download_service.dart';
import 'regions_screen.dart';

class SplashScreen extends StatefulWidget {
  final AppDatabase database;
  final AppConfig appConfig;

  const SplashScreen({
    super.key,
    required this.database,
    required this.appConfig,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _orbitController;
  late List<AnimationController> _ballControllers;
  late List<String> _ballAssets;
  double _progress = 0.0;
  String _statusText = 'Inicializando...';
  bool _isDownloading = false;
  bool _downloadComplete = false;
  int _totalSizeBytes = 0;

  @override
  void initState() {
    super.initState();
    _loadBallAssets();
    _initializeAnimations();
    _checkAndDownload();
  }

  void _loadBallAssets() {
    // Cargar todas las imágenes PNG que contengan "ball" en el nombre
    _ballAssets = [
      'assets/pokeball_mini.png',
      'assets/cherishball.png',
      'assets/diveball.png',
      'assets/duskball.png',
      'assets/greatball.png',
      'assets/healball.png',
      'assets/luxuryball.png',
      'assets/masterball.png',
      'assets/nestball.png',
      'assets/netball.png',
      'assets/premierballl.png',
      'assets/quickball.png',
      'assets/repeatball.png',
      'assets/safariball.png',
      'assets/timerball.png',
      'assets/ultraball.png',
    ];
  }

  void _initializeAnimations() {
    // Controlador principal para la órbita
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    // Controladores individuales para cada pokeball
    _ballControllers = List.generate(
      _ballAssets.length,
      (index) => AnimationController(
        vsync: this,
        duration: Duration(seconds: 8 + (index % 3) * 2), // Variar velocidad
      )..repeat(),
    );
  }

  Future<void> _checkAndDownload() async {
    // Verificar si ya hay datos descargados
    final hasData = await _hasInitialData();
    
    if (!hasData) {
      setState(() {
        _isDownloading = true;
        _statusText = 'Preparando descarga inicial...';
      });

      // Iniciar descarga en segundo plano
      await _downloadInitialData();
    } else {
      setState(() {
        _statusText = 'Cargando aplicación...';
        _progress = 1.0;
      });
    }

    // Esperar un momento para mostrar la animación
    await Future.delayed(const Duration(seconds: 1));

    // Navegar a la pantalla de regiones
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => RegionsScreen(
            database: widget.database,
            appConfig: widget.appConfig,
          ),
        ),
      );
    }
  }

  Future<bool> _hasInitialData() async {
    try {
      // Verificar si hay regiones en la base de datos
      final regions = await widget.database.regionDao.getAllRegions();
      return regions.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _downloadInitialData() async {
    try {
      final downloadService = DownloadService(
        database: widget.database,
      );

      await downloadService.downloadEssentialData(
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _progress = progress.total > 0 
                  ? progress.completed / progress.total 
                  : 0.0;
              _totalSizeBytes = progress.totalSizeBytes ?? 0;
              // Mostrar mensaje más descriptivo si hay rate limiting
              if (progress.currentEntity.contains('rate limit')) {
                _statusText = 'Esperando... (demasiadas peticiones)';
              } else {
                _statusText = 'Descargando ${progress.currentEntity}... '
                    '(${progress.completed}/${progress.total})';
              }
            });
          }
        },
      );
      
      if (mounted) {
        setState(() {
          _downloadComplete = true;
          _statusText = '¡Descarga completada!';
          _progress = 1.0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = 'Error: $e';
        });
      }
    }
  }

  /// Formatear tamaño en formato legible
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  void dispose() {
    _orbitController.dispose();
    for (var controller in _ballControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Área de animación con pokemon central y pokeballs orbitando
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Pokeballs orbitando
                    ...List.generate(_ballAssets.length, (index) {
                      return AnimatedBuilder(
                        animation: _orbitController,
                        builder: (context, child) {
                          final baseAngle = (2 * math.pi * index / _ballAssets.length);
                          final currentAngle = baseAngle + (_orbitController.value * 2 * math.pi);
                          // Radio de órbita (no cambiar distancia del centro)
                          final radius = 100.0 + (index % 3) * 30.0;
                          
                          return Transform.translate(
                            offset: Offset(
                              radius * math.cos(currentAngle),
                              radius * math.sin(currentAngle),
                            ),
                            child: Transform.rotate(
                              angle: _ballControllers[index].value * 2 * math.pi,
                              child: Opacity(
                                opacity: 0.8 - (index % 3) * 0.1,
                                child: Image.asset(
                                  _ballAssets[index],
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.3),
                                        shape: BoxShape.circle,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }),
                    // Imagen central rotada 180 grados (arriba abajo)
                    Transform.rotate(
                      angle: math.pi, // 180 grados
                      child: const Icon(
                        Icons.catching_pokemon,
                        size: 120,
                        color: Color(0xFFDC143C),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Barra de progreso y texto de estado
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Column(
                  children: [
                    // Barra de progreso
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 8,
                        backgroundColor: Colors.grey[800],
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFDC143C),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Texto de estado
                    Text(
                      _statusText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_isDownloading && !_downloadComplete) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${(_progress * 100).toInt()}% completado',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                      ),
                      // Tamaño total a descargar
                      if (_totalSizeBytes > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Tamaño total: ${_formatSize(_totalSizeBytes)}',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


