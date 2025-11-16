import 'package:drift/drift.dart';

/// Tabla de formas de pokemon
class PokemonForms extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get pokemonId => integer().nullable()();
  IntColumn get versionGroupId => integer().nullable()();
  IntColumn get order => integer().nullable()();
  IntColumn get formOrder => integer().nullable()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get isBattleOnly => boolean().withDefault(const Constant(false))();
  BoolColumn get isMega => boolean().withDefault(const Constant(false))();
  TextColumn get formName => text().nullable()();
  
  // JSON para datos complejos
  TextColumn get spritesJson => text().nullable()();
  TextColumn get typesJson => text().nullable()();
  TextColumn get dataJson => text().nullable()();
  
  // Referencias a assets de Flutter
  TextColumn get spriteFrontDefaultPath => text().nullable()();
  TextColumn get spriteFrontShinyPath => text().nullable()();
  TextColumn get spriteBackDefaultPath => text().nullable()();
  TextColumn get spriteBackShinyPath => text().nullable()();
}

