import '../database/app_database.dart';

/// Helper para obtener la mejor imagen disponible de un pokemon
/// Prioridad: SVG > PNG de mayor resolución
/// Estrategia: dream-world SVG > official-artwork PNG > home PNG
class PokemonImageHelper {
  /// Obtener la mejor imagen disponible para un pokemon (normal, no shiny)
  /// Prioridad: SVG > PNG de mayor resolución
  static String? getBestImagePath(PokemonData? pokemon, {bool preferShiny = false}) {
    if (pokemon == null) {
      return null;
    }
    
    // Si se prefiere shiny, buscar shiny primero
    if (preferShiny) {
      // Buscar SVG shiny (poco probable que exista)
      if (pokemon.artworkOfficialShinyPath != null && 
          pokemon.artworkOfficialShinyPath!.isNotEmpty &&
          pokemon.artworkOfficialShinyPath!.toLowerCase().endsWith('.svg')) {
        return pokemon.artworkOfficialShinyPath;
      }
      
      // PNG shiny de official-artwork (mayor resolución)
      if (pokemon.artworkOfficialShinyPath != null && 
          pokemon.artworkOfficialShinyPath!.isNotEmpty &&
          pokemon.artworkOfficialShinyPath!.toLowerCase().endsWith('.png')) {
        return pokemon.artworkOfficialShinyPath;
      }
      
      // PNG shiny de home (fallback)
      if (pokemon.spriteFrontShinyPath != null && 
          pokemon.spriteFrontShinyPath!.isNotEmpty &&
          pokemon.spriteFrontShinyPath!.toLowerCase().endsWith('.png')) {
        return pokemon.spriteFrontShinyPath;
      }
    }
    
    // Prioridad 1: SVG normal desde dream-world (artworkOfficialPath si es SVG)
    if (pokemon.artworkOfficialPath != null && 
        pokemon.artworkOfficialPath!.isNotEmpty &&
        pokemon.artworkOfficialPath!.toLowerCase().endsWith('.svg')) {
      return pokemon.artworkOfficialPath;
    }
    
    // Prioridad 2: SVG desde spriteFrontDefaultPath
    if (pokemon.spriteFrontDefaultPath != null && 
        pokemon.spriteFrontDefaultPath!.isNotEmpty &&
        pokemon.spriteFrontDefaultPath!.toLowerCase().endsWith('.svg')) {
      return pokemon.spriteFrontDefaultPath;
    }
    
    // Prioridad 3: PNG de official-artwork (mayor resolución)
    if (pokemon.artworkOfficialPath != null && 
        pokemon.artworkOfficialPath!.isNotEmpty &&
        pokemon.artworkOfficialPath!.toLowerCase().endsWith('.png')) {
      return pokemon.artworkOfficialPath;
    }
    
    // Prioridad 4: PNG de spriteFrontDefaultPath (fallback)
    if (pokemon.spriteFrontDefaultPath != null && 
        pokemon.spriteFrontDefaultPath!.isNotEmpty) {
      return pokemon.spriteFrontDefaultPath;
    }
    
    // Si no hay nada, intentar shiny como último recurso
    if (pokemon.artworkOfficialShinyPath != null && 
        pokemon.artworkOfficialShinyPath!.isNotEmpty) {
      return pokemon.artworkOfficialShinyPath;
    }
    if (pokemon.spriteFrontShinyPath != null && 
        pokemon.spriteFrontShinyPath!.isNotEmpty) {
      return pokemon.spriteFrontShinyPath;
    }
    
    return null;
  }
  
  /// Verificar si un pokemon tiene imagen shiny disponible
  static bool hasShinyImage(PokemonData? pokemon) {
    if (pokemon == null) return false;
    return (pokemon.artworkOfficialShinyPath != null && 
            pokemon.artworkOfficialShinyPath!.isNotEmpty) ||
           (pokemon.spriteFrontShinyPath != null && 
            pokemon.spriteFrontShinyPath!.isNotEmpty);
  }
}

