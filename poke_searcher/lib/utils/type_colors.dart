/// Colores hexadecimales para cada tipo de Pokémon
class TypeColors {
  static const Map<String, String> _typeColors = {
    'normal': '#A8A77A',
    'fire': '#EE8130',
    'water': '#6390F0',
    'grass': '#7AC74C',
    'electric': '#F7D02C',
    'ice': '#96D9D6',
    'fighting': '#C22E28',
    'poison': '#A33EA1',
    'ground': '#E2BF65',
    'flying': '#A98FF3',
    'psychic': '#F95587',
    'bug': '#A6B91A',
    'rock': '#B6A136',
    'ghost': '#735797',
    'dragon': '#6F35FC',
    'dark': '#705746',
    'steel': '#B7B7CE',
    'fairy': '#D685AD',
  };

  /// Obtener el color hexadecimal de un tipo por su nombre
  /// Retorna null si el tipo no existe
  static String? getColorForType(String typeName) {
    return _typeColors[typeName.toLowerCase()];
  }

  /// Obtener todos los colores de tipos
  static Map<String, String> get allColors => Map.unmodifiable(_typeColors);
}

