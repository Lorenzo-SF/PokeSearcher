import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// Import condicional para dart:io (no disponible en web)
import 'dart:io' if (dart.library.html) 'dart:html';
import 'tables/languages.dart';
import 'tables/regions.dart';
import 'tables/types.dart';
import 'tables/localized_names.dart';
import 'tables/download_sync.dart';
import 'tables/generations.dart';
import 'tables/version_groups.dart';
import 'tables/stats.dart';
import 'tables/abilities.dart';
import 'tables/moves.dart';
import 'tables/items.dart';
import 'tables/pokedex.dart';
import 'tables/pokemon_species.dart';
import 'tables/pokemon.dart';
import 'tables/pokemon_types.dart';
import 'tables/pokemon_abilities.dart';
import 'tables/pokemon_moves.dart';
import 'tables/pokedex_entries.dart';
import 'tables/evolution_chains.dart';
import 'tables/type_damage_relations.dart';
import 'tables/egg_groups.dart';
import 'tables/growth_rates.dart';
import 'tables/natures.dart';
import 'tables/pokemon_colors.dart';
import 'tables/pokemon_shapes.dart';
import 'tables/pokemon_habitats.dart';
import 'tables/move_damage_classes.dart';
import 'tables/item_categories.dart';
import 'tables/item_pockets.dart';
// Vista temporalmente deshabilitada hasta implementar correctamente
// import 'views/region_summary_view.dart';
import 'daos/region_dao.dart';
import 'daos/pokemon_dao.dart';
import 'daos/pokedex_dao.dart';
import 'daos/type_dao.dart';
import 'daos/move_dao.dart';
import 'daos/ability_dao.dart';
import 'daos/item_dao.dart';
import 'daos/language_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
  Languages,
  Regions,
  Types,
  LocalizedNames,
  DownloadSync,
  Generations,
  VersionGroups,
  Stats,
  Abilities,
  Moves,
  Items,
  Pokedex,
  PokemonSpecies,
  Pokemon,
  PokemonTypes,
  PokemonAbilities,
  PokemonMoves,
  PokedexEntries,
  EvolutionChains,
  TypeDamageRelations,
  EggGroups,
  GrowthRates,
  Natures,
  PokemonColors,
  PokemonShapes,
  PokemonHabitats,
  MoveDamageClasses,
  ItemCategories,
  ItemPockets,
  ],
  // views: [
  //   RegionSummaryView,  // Temporalmente deshabilitada
  // ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  
  /// Constructor para tests (usa base de datos en memoria)
  AppDatabase.test() : super(NativeDatabase.memory());
  
  /// Constructor para web sin WASM (usa base de datos en memoria)
  AppDatabase.web() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        // Crear índices después de crear las tablas
        await _createIndexes();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Migraciones futuras
      },
    );
  }

  /// Crear índices para optimizar consultas
  Future<void> _createIndexes() async {
    // Índices para búsquedas por nombre
    await customStatement('CREATE INDEX IF NOT EXISTS idx_regions_name ON regions(name)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_types_name ON types(name)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_pokemon_species_name ON pokemon_species(name)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_pokemon_name ON pokemon(name)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_moves_name ON moves(name)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_abilities_name ON abilities(name)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_items_name ON items(name)');
    
    // Índices para foreign keys
    await customStatement('CREATE INDEX IF NOT EXISTS idx_regions_main_generation ON regions(main_generation_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_types_generation ON types(generation_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_pokemon_species_id ON pokemon(species_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_pokemon_types_pokemon ON pokemon_types(pokemon_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_pokemon_types_type ON pokemon_types(type_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_pokemon_abilities_pokemon ON pokemon_abilities(pokemon_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_pokemon_abilities_ability ON pokemon_abilities(ability_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_pokemon_moves_pokemon ON pokemon_moves(pokemon_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_pokemon_moves_move ON pokemon_moves(move_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_pokedex_entries_pokedex ON pokedex_entries(pokedex_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_pokedex_entries_species ON pokedex_entries(pokemon_species_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_pokedex_region ON pokedex(region_id)');
    
    // Índices para traducciones
    await customStatement('CREATE INDEX IF NOT EXISTS idx_localized_names_entity ON localized_names(entity_type, entity_id, language_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_localized_names_language ON localized_names(language_id)');
    
    // Índices para download sync
    await customStatement('CREATE INDEX IF NOT EXISTS idx_download_sync_phase ON download_sync(phase, entity_type)');
    
    // Índices para relaciones de daño
    await customStatement('CREATE INDEX IF NOT EXISTS idx_type_damage_attacking ON type_damage_relations(attacking_type_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_type_damage_defending ON type_damage_relations(defending_type_id)');
  }

  // Getters para DAOs
  RegionDao get regionDao => RegionDao(this);
  PokemonDao get pokemonDao => PokemonDao(this);
  PokedexDao get pokedexDao => PokedexDao(this);
  TypeDao get typeDao => TypeDao(this);
  MoveDao get moveDao => MoveDao(this);
  AbilityDao get abilityDao => AbilityDao(this);
  ItemDao get itemDao => ItemDao(this);
  LanguageDao get languageDao => LanguageDao(this);
}

LazyDatabase _openConnection() {
  if (kIsWeb) {
    // En web, usar base de datos en memoria
    // Nota: Los datos se perderán al recargar la página
    // Para persistencia en web, configura WebAssembly ejecutando: .\configurar_web.ps1
    // y luego actualiza este código para usar WasmDatabase
    return LazyDatabase(() async {
      return NativeDatabase.memory();
    });
  } else {
    // En otras plataformas (Android, Windows, iOS, macOS, Linux), usar SQLite nativo
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      // ignore: avoid_dynamic_calls
      final file = File(p.join(dbFolder.path, 'poke_search.db'));
      return NativeDatabase(file);
    });
  }
}

