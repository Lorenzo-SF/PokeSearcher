/// Fases de descarga de datos
enum DownloadPhase {
  /// Fase 0: Datos esenciales (splash screen)
  /// Incluye: languages, types, regions (metadatos), generations, version_groups,
  /// stats, abilities (metadatos), moves (metadatos), items (metadatos),
  /// catálogos pequeños (egg_groups, growth_rates, natures, etc.)
  essential,
  
  /// Fase 1: Datos de región (on-demand)
  /// Incluye: pokedex completos, pokemon_species (metadatos), evolution_chains
  regionData,
  
  /// Fase 2: Datos completos de pokemon (on-demand)
  /// Incluye: pokemon completo, pokemon_forms, moves completos, abilities completas
  pokemonData,
  
  /// Fase 3: Archivos multimedia (on-demand)
  /// Incluye: sprites, cries, imágenes oficiales
  media,
}

/// Información sobre una fase de descarga
class PhaseInfo {
  final DownloadPhase phase;
  final String name;
  final String description;
  final List<String> entityTypes;
  
  const PhaseInfo({
    required this.phase,
    required this.name,
    required this.description,
    required this.entityTypes,
  });
  
  static const Map<DownloadPhase, PhaseInfo> phases = {
    DownloadPhase.essential: PhaseInfo(
      phase: DownloadPhase.essential,
      name: 'Datos Esenciales',
      description: 'Descargando datos básicos necesarios para el funcionamiento de la aplicación',
      entityTypes: [
        'language',
        'type',
        'region',
        'generation',
        'version-group',
        'stat',
        // Excluidos: 'ability', 'move', 'item' (se descargarán on-demand)
        'egg-group',
        'growth-rate',
        'nature',
        'pokemon-color',
        'pokemon-shape',
        'pokemon-habitat',
        'move-damage-class',
        'item-category',
        'item-pocket',
        // Excluidos: 'location', 'pokemon-species', 'pokemon' (se descargarán on-demand)
      ],
    ),
    DownloadPhase.regionData: PhaseInfo(
      phase: DownloadPhase.regionData,
      name: 'Datos de Región',
      description: 'Descargando información de la región seleccionada',
      entityTypes: [
        'pokedex',
        'pokemon-species',
        'evolution-chain',
      ],
    ),
    DownloadPhase.pokemonData: PhaseInfo(
      phase: DownloadPhase.pokemonData,
      name: 'Datos de Pokémon',
      description: 'Descargando información completa del Pokémon',
      entityTypes: [
        'pokemon',
        'pokemon-form',
        'move',
        'ability',
      ],
    ),
    DownloadPhase.media: PhaseInfo(
      phase: DownloadPhase.media,
      name: 'Multimedia',
      description: 'Descargando archivos multimedia',
      entityTypes: [
        'media',
      ],
    ),
  };
  
  static PhaseInfo getInfo(DownloadPhase phase) {
    return phases[phase] ?? phases[DownloadPhase.essential]!;
  }
}

