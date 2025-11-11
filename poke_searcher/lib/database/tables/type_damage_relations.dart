import 'package:drift/drift.dart';

/// Relaciones de daño entre tipos (double_damage, half_damage, no_damage)
class TypeDamageRelations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get attackingTypeId => integer()();
  IntColumn get defendingTypeId => integer()();
  TextColumn get relationType => text()(); // 'double_damage_to', 'half_damage_to', 'no_damage_to', 'double_damage_from', 'half_damage_from', 'no_damage_from'
  
  @override
  Set<Column> get primaryKey => {id};
  
  @override
  List<Set<Column>> get uniqueKeys => [
    {attackingTypeId, defendingTypeId, relationType}
  ];
}

