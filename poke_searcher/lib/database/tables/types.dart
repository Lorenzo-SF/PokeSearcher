import 'package:drift/drift.dart';

/// Tabla de tipos de Pokémon
class Types extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get generationId => integer().nullable()();
  IntColumn get moveDamageClassId => integer().nullable()();
  
  // Color hexadecimal del tipo
  TextColumn get color => text().nullable()();
  
  // JSON para relaciones de daño (evita múltiples joins en inserts)
  TextColumn get damageRelationsJson => text().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

