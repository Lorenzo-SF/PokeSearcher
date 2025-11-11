import 'package:drift/drift.dart';

/// Tabla de Pokémon (variantes con estadísticas, tipos, habilidades, movimientos)
class Pokemon extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get speciesId => integer()();
  IntColumn get baseExperience => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get weight => integer().nullable()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get order => integer().nullable()();
  IntColumn get locationAreaEncounters => integer().nullable()();
  
  // JSON para datos complejos
  TextColumn get abilitiesJson => text().nullable()();
  TextColumn get formsJson => text().nullable()();
  TextColumn get gameIndicesJson => text().nullable()();
  TextColumn get heldItemsJson => text().nullable()();
  TextColumn get movesJson => text().nullable()();
  TextColumn get spritesJson => text().nullable()();
  TextColumn get statsJson => text().nullable()();
  TextColumn get typesJson => text().nullable()();
  TextColumn get criesJson => text().nullable()();
  
  // URLs originales de multimedia (para poder reintentar descarga si falla)
  TextColumn get spriteFrontDefaultUrl => text().nullable()();
  TextColumn get spriteFrontShinyUrl => text().nullable()();
  TextColumn get spriteBackDefaultUrl => text().nullable()();
  TextColumn get spriteBackShinyUrl => text().nullable()();
  TextColumn get artworkOfficialUrl => text().nullable()();
  TextColumn get artworkOfficialShinyUrl => text().nullable()();
  TextColumn get cryLatestUrl => text().nullable()();
  TextColumn get cryLegacyUrl => text().nullable()();
  
  // Paths a archivos multimedia locales (después de descargar)
  TextColumn get spriteFrontDefaultPath => text().nullable()();
  TextColumn get spriteFrontShinyPath => text().nullable()();
  TextColumn get spriteBackDefaultPath => text().nullable()();
  TextColumn get spriteBackShinyPath => text().nullable()();
  TextColumn get artworkOfficialPath => text().nullable()();
  TextColumn get artworkOfficialShinyPath => text().nullable()();
  TextColumn get cryLatestPath => text().nullable()();
  TextColumn get cryLegacyPath => text().nullable()();
}

