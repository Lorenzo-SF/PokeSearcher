/// Sistema de logging con colores por contexto/entidad
class Logger {
  // Códigos ANSI para colores
  static const String _reset = '\x1B[0m';
  static const String _bold = '\x1B[1m';
  
  // Colores por contexto/entidad
  static const String _colorRegion = '\x1B[34m'; // Azul
  static const String _colorPokedex = '\x1B[36m'; // Cyan
  static const String _colorPokemon = '\x1B[32m'; // Verde
  static const String _colorType = '\x1B[33m'; // Amarillo
  static const String _colorMove = '\x1B[35m'; // Magenta
  static const String _colorItem = '\x1B[31m'; // Rojo
  static const String _colorEssential = '\x1B[37m'; // Blanco
  static const String _colorError = '\x1B[91m'; // Rojo brillante
  static const String _colorApi = '\x1B[90m'; // Gris oscuro
  
  /// Obtener color según el tipo de entidad/contexto
  static String _getColorForContext(LogContext context) {
    switch (context) {
      case LogContext.region:
        return _colorRegion;
      case LogContext.pokedex:
        return _colorPokedex;
      case LogContext.pokemon:
        return _colorPokemon;
      case LogContext.type:
        return _colorType;
      case LogContext.move:
        return _colorMove;
      case LogContext.item:
        return _colorItem;
      case LogContext.essential:
        return _colorEssential;
      case LogContext.api:
        return _colorApi;
      case LogContext.error:
        return _colorError;
    }
  }
  
  /// Log de información
  static void info(String message, {LogContext context = LogContext.essential}) {
    final color = _getColorForContext(context);
    print('$color$_bold[INFO]$_reset $color$message$_reset');
  }
  
  /// Log de error
  static void error(String message, {LogContext? context, Object? error}) {
    final ctx = context ?? LogContext.error;
    final color = _getColorForContext(ctx);
    final errorMsg = error != null ? ': $error' : '';
    print('$_colorError$_bold[ERROR]$_reset $color$message$errorMsg$_reset');
  }
  
  /// Log de descarga de entidad
  static void downloadEntity(String entityName, LogContext context) {
    final color = _getColorForContext(context);
    print('$color⬇️  Descargando: $entityName$_reset');
  }
  
  /// Log de guardado de entidad
  static void saveEntity(String entityName, LogContext context) {
    final color = _getColorForContext(context);
    print('$color💾 Guardando: $entityName$_reset');
  }
  
  /// Log de región
  static void region(String message, {String? regionName}) {
    final name = regionName != null ? ' [$regionName]' : '';
    final color = _getColorForContext(LogContext.region);
    print('$color$_bold[REGION]$_reset$name $color$message$_reset');
  }
  
  /// Log de pokedex
  static void pokedex(String message, {String? pokedexName}) {
    final name = pokedexName != null ? ' [$pokedexName]' : '';
    final color = _getColorForContext(LogContext.pokedex);
    print('$color$_bold[POKEDEX]$_reset$name $color$message$_reset');
  }
  
  /// Log de pokemon
  static void pokemon(String message, {String? pokemonName}) {
    final name = pokemonName != null ? ' [$pokemonName]' : '';
    final color = _getColorForContext(LogContext.pokemon);
    print('$color$_bold[POKEMON]$_reset$name $color$message$_reset');
  }
  
  /// Log de API (rate limiting, etc.)
  static void api(String message) {
    final color = _getColorForContext(LogContext.api);
    print('$color$_bold[API]$_reset $color$message$_reset');
  }
}

/// Contextos de logging para asignar colores
enum LogContext {
  region,
  pokedex,
  pokemon,
  type,
  move,
  item,
  essential,
  api,
  error,
}

