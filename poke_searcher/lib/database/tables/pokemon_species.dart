import 'package:drift/drift.dart';

/// Tabla de especies de Pokémon (información base, sin multimedia)
class PokemonSpecies extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get order => integer().nullable()();
  IntColumn get genderRate => integer().nullable()();
  IntColumn get captureRate => integer().nullable()();
  IntColumn get baseHappiness => integer().nullable()();
  BoolColumn get isBaby => boolean().withDefault(const Constant(false))();
  BoolColumn get isLegendary => boolean().withDefault(const Constant(false))();
  BoolColumn get isMythical => boolean().withDefault(const Constant(false))();
  IntColumn get hatchCounter => integer().nullable()();
  BoolColumn get hasGenderDifferences => boolean().withDefault(const Constant(false))();
  IntColumn get formsSwitchable => integer().nullable()();
  IntColumn get growthRateId => integer().nullable()();
  IntColumn get colorId => integer().nullable()();
  IntColumn get shapeId => integer().nullable()();
  IntColumn get habitatId => integer().nullable()();
  IntColumn get generationId => integer().nullable()();
  IntColumn get evolvesFromSpeciesId => integer().nullable()();
  IntColumn get evolutionChainId => integer().nullable()();
  
  // JSON para datos complejos
  TextColumn get eggGroupsJson => text().nullable()();
  TextColumn get flavorTextEntriesJson => text().nullable()();
  TextColumn get formDescriptionsJson => text().nullable()();
  TextColumn get varietiesJson => text().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

