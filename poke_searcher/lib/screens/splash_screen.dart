import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../database/app_database.dart';
import '../services/config/app_config.dart';
import '../services/backup/backup_processor.dart';
import '../utils/loading_messages.dart';
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
  String _statusText = '';
  bool _isDownloading = false;
  bool _downloadComplete = false;

  @override
  void initState() {
    super.initState();
    _loadBallAssets();
    _initializeAnimations();
    // Inicializar texto con traducción
    _statusText = LoadingMessages.getMessage('preparing', widget.appConfig.language);
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
    // Ejecutar verificación en un microtask para no bloquear la UI
    await Future.microtask(() async {
      // Verificar si la base de datos está vacía
      final hasData = await _hasInitialData();
      
      if (!hasData) {
        // Actualizar UI antes de iniciar carga pesada
        if (mounted) {
          setState(() {
            _isDownloading = true;
            _statusText = 'Cargando base de datos...';
          });
        }

        // Cargar datos desde assets (SQL + multimedia) en segundo plano
        // Usar unawaited para no bloquear, pero manejar errores
        _loadInitialData().then((_) {
          // Navegar después de cargar
          if (mounted) {
            _navigateToRegions();
          }
        }).catchError((error) {
          if (mounted) {
            setState(() {
              _statusText = 'Error: $error';
            });
          }
        });
      } else {
        if (mounted) {
          setState(() {
            _statusText = 'Cargando aplicación...';
            _progress = 1.0;
          });
        }
        
        // Esperar un momento para mostrar la animación
        await Future.delayed(const Duration(seconds: 1));
        
        // Navegar a la pantalla de regiones
        if (mounted) {
          _navigateToRegions();
        }
      }
    });
  }
  
  /// Navegar a la pantalla de regiones
  void _navigateToRegions() {
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

  /// Verificar si la base de datos está vacía de manera sencilla
  /// Comprueba si hay al menos una región en la base de datos
  Future<bool> _hasInitialData() async {
    try {
      // Verificar si hay regiones en la base de datos
      final regions = await widget.database.regionDao.getAllRegions();
      return regions.isNotEmpty;
    } catch (e) {
      // Si hay error, asumir que la DB está vacía
      return false;
    }
  }

  /// Cargar datos iniciales desde assets (SQL + multimedia)
  /// Ejecutado en segundo plano para no bloquear la UI
  Future<void> _loadInitialData() async {
    try {
      final backupProcessor = BackupProcessor(
        database: widget.database,
        appConfig: widget.appConfig,
      );

      // Ejecutar en chunks con delays para permitir que la UI se actualice
      await backupProcessor.processBackupFromAssets(
        onProgress: (message, progress) {
          // Usar scheduleMicrotask para asegurar que setState se ejecute en el hilo de UI
          if (mounted) {
            scheduleMicrotask(() {
              if (mounted) {
                setState(() {
                  _progress = progress;
                  _statusText = message;
                });
              }
            });
          }
        },
      );
      
      // Actualizar estado final
      if (mounted) {
        scheduleMicrotask(() {
          if (mounted) {
            setState(() {
              _downloadComplete = true;
              _statusText = '¡Carga completada!';
              _progress = 1.0;
            });
          }
        });
        
        // Esperar un momento antes de navegar
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      if (mounted) {
        scheduleMicrotask(() {
          if (mounted) {
            setState(() {
              _statusText = 'Error cargando datos: $e';
            });
          }
        });
      }
      rethrow;
    }
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


