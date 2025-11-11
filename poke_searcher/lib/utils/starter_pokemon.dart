/// Lista fija de Pokémon iniciales por región
/// Cada región tiene exactamente 3 iniciales: Planta, Fuego, Agua
class StarterPokemon {
  /// Mapa de nombre de región (en inglés, como en la API) a lista de nombres de iniciales
  static const Map<String, List<String>> regionStarters = {
    'kanto': ['bulbasaur', 'charmander', 'squirtle'],
    'johto': ['chikorita', 'cyndaquil', 'totodile'],
    'hoenn': ['treecko', 'torchic', 'mudkip'],
    'sinnoh': ['turtwig', 'chimchar', 'piplup'],
    'unova': ['snivy', 'tepig', 'oshawott'],
    'kalos': ['chespin', 'fennekin', 'froakie'],
    'alola': ['rowlet', 'litten', 'popplio'],
    'galar': ['grookey', 'scorbunny', 'sobble'],
    'paldea': ['sprigatito', 'fuecoco', 'quaxly'],
    'hisui': ['rowlet', 'cyndaquil', 'oshawott'], // Reutiliza iniciales de otras regiones
  };
  
  /// Obtener los iniciales de una región por su nombre (en inglés)
  /// Retorna lista vacía si la región no tiene iniciales definidos
  static List<String> getStartersForRegion(String regionName) {
    final normalizedName = regionName.toLowerCase();
    return regionStarters[normalizedName] ?? [];
  }
  
  /// Verificar si un pokemon es inicial de alguna región
  static bool isStarter(String pokemonName) {
    final normalizedName = pokemonName.toLowerCase();
    for (final starters in regionStarters.values) {
      if (starters.contains(normalizedName)) {
        return true;
      }
    }
    return false;
  }
  
  /// Obtener todas las regiones que tienen iniciales definidos
  static List<String> getRegionsWithStarters() {
    return regionStarters.keys.toList();
  }
}

