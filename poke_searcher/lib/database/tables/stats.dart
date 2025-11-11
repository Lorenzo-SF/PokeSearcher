import 'package:drift/drift.dart';

/// Tabla de estadísticas base de Pokémon
class Stats extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get gameIndex => integer().nullable()();
  BoolColumn get isBattleOnly => boolean().withDefault(const Constant(false))();
  IntColumn get moveDamageClassId => integer().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

