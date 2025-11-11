import 'package:drift/drift.dart';

/// Relación many-to-many entre Pokémon y Habilidades
class PokemonAbilities extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get pokemonId => integer()();
  IntColumn get abilityId => integer()();
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();
  IntColumn get slot => integer()();
  
  @override
  Set<Column> get primaryKey => {id};
  
  @override
  List<Set<Column>> get uniqueKeys => [
    {pokemonId, abilityId}
  ];
}

