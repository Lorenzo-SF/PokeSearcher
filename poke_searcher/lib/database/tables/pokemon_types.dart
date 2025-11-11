import 'package:drift/drift.dart';

/// Relación many-to-many entre Pokémon y Tipos
class PokemonTypes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get pokemonId => integer()();
  IntColumn get typeId => integer()();
  IntColumn get slot => integer()(); // 1 o 2 (tipo primario o secundario)
  
  @override
  Set<Column> get primaryKey => {id};
  
  @override
  List<Set<Column>> get uniqueKeys => [
    {pokemonId, typeId, slot}
  ];
}

