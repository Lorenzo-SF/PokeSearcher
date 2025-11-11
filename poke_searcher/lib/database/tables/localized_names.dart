import 'package:drift/drift.dart';

/// Tabla genérica para traducciones/nombres localizados
/// Soporta múltiples entidades: regions, pokemon, moves, abilities, etc.
class LocalizedNames extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()(); // 'region', 'pokemon', 'move', etc.
  IntColumn get entityId => integer()();
  IntColumn get languageId => integer()();
  TextColumn get name => text()();
  
  @override
  Set<Column> get primaryKey => {id};
  
  @override
  List<Set<Column>> get uniqueKeys => [
    {entityType, entityId, languageId}
  ];
}

