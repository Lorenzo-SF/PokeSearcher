import 'package:drift/drift.dart';

/// Relación many-to-many entre Pokémon y Movimientos
class PokemonMoves extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get pokemonId => integer()();
  IntColumn get moveId => integer()();
  IntColumn get versionGroupId => integer().nullable()();
  TextColumn get learnMethod => text().nullable()(); // 'level-up', 'machine', 'tutor', 'egg'
  IntColumn get level => integer().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

