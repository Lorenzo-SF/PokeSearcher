import 'dart:math' as math;

/// Generador de colores pastel únicos para pokedexes
class ColorGenerator {
  static final math.Random _random = math.Random();
  
  /// Lista de colores pastel base (tonos suaves)
  static const List<String> _pastelColors = [
    '#FFB3BA', // Rosa pastel
    '#FFDFBA', // Melocotón pastel
    '#FFFFBA', // Amarillo pastel
    '#BAFFC9', // Verde menta pastel
    '#BAE1FF', // Azul cielo pastel
    '#E0BBE4', // Lavanda pastel
    '#FFCCCB', // Rosa claro
    '#F0E68C', // Khaki
    '#DDA0DD', // Ciruela
    '#98D8C8', // Turquesa pastel
    '#F7DC6F', // Amarillo suave
    '#AED6F1', // Azul claro
    '#F8BBD0', // Rosa suave
    '#C8E6C9', // Verde claro
    '#FFE5B4', // Melocotón claro
    '#E1BEE7', // Lila claro
    '#BBDEFB', // Azul muy claro
    '#FFECB3', // Amarillo claro
    '#C5E1A5', // Verde lima
    '#B2DFDB', // Verde azulado
  ];
  
  /// Genera un color pastel único basado en un índice
  /// Si el índice es mayor que los colores disponibles, genera uno aleatorio
  static String generatePastelColor(int index) {
    if (index < _pastelColors.length) {
      return _pastelColors[index];
    }
    
    // Si se agotan los colores predefinidos, generar uno aleatorio pastel
    return _generateRandomPastel();
  }
  
  /// Genera un color pastel aleatorio
  static String _generateRandomPastel() {
    // Generar colores pastel: valores RGB entre 180-255 (tonos claros)
    final int r = 180 + _random.nextInt(76); // 180-255
    final int g = 180 + _random.nextInt(76); // 180-255
    final int b = 180 + _random.nextInt(76); // 180-255
    
    return '#${r.toRadixString(16).padLeft(2, '0')}'
           '${g.toRadixString(16).padLeft(2, '0')}'
           '${b.toRadixString(16).padLeft(2, '0')}';
  }
  
  /// Convierte un color hexadecimal a Color de Flutter
  static int hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) {
      buffer.write('ff'); // Añadir alpha si no está presente
    }
    buffer.write(hexString.replaceFirst('#', ''));
    return int.parse(buffer.toString(), radix: 16);
  }
}

