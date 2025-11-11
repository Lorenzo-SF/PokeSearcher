import 'package:drift/drift.dart';

/// Tabla de movimientos de Pokémon
class Moves extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get accuracy => integer().nullable()();
  IntColumn get effectChance => integer().nullable()();
  IntColumn get pp => integer().nullable()();
  IntColumn get priority => integer().nullable()();
  IntColumn get power => integer().nullable()();
  IntColumn get typeId => integer().nullable()();
  IntColumn get damageClassId => integer().nullable()();
  IntColumn get generationId => integer().nullable()();
  
  // JSON completo para evitar múltiples joins en inserts
  TextColumn get fullDataJson => text().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

