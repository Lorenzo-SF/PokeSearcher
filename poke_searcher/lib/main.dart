import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'database/app_database.dart';
import 'services/config/app_config.dart';
import 'screens/splash_screen.dart';

/// Punto de entrada principal de la aplicación PokeSearch.
/// 
/// Inicializa los servicios necesarios (configuración y base de datos)
/// y lanza la aplicación Flutter.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configurar orientación preferida (permitir ambas)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  
  // Inicializar servicios
  final appConfig = await AppConfig.getInstance();
  final database = AppDatabase();
  
  runApp(PokeSearchApp(
    database: database,
    appConfig: appConfig,
  ));
}

/// Widget raíz de la aplicación PokeSearch.
/// 
/// Configura el tema de la aplicación (claro/oscuro/sistema) y establece
/// la pantalla inicial (SplashScreen).
class PokeSearchApp extends StatelessWidget {
  /// Instancia de la base de datos de la aplicación
  final AppDatabase database;
  
  /// Configuración de la aplicación (tema, idioma, etc.)
  final AppConfig appConfig;
  
  const PokeSearchApp({
    super.key,
    required this.database,
    required this.appConfig,
  });

  @override
  Widget build(BuildContext context) {
    // Obtener tema configurado
    final themeMode = _getThemeMode(appConfig.theme);
    
    return MaterialApp(
      title: 'PokeSearch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFDC143C), // Rojo Pokédex
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFDC143C),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      themeMode: themeMode,
      home: SplashScreen(
        database: database,
        appConfig: appConfig,
      ),
    );
  }
  
  ThemeMode _getThemeMode(String theme) {
    switch (theme) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}
