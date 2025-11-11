import 'package:drift/drift.dart';

/// Tabla de habilidades de Pokémon
class Abilities extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  BoolColumn get isMainSeries => boolean().withDefault(const Constant(false))();
  IntColumn get generationId => integer().nullable()();
  
  // JSON completo para evitar múltiples joins en inserts
  TextColumn get fullDataJson => text().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

