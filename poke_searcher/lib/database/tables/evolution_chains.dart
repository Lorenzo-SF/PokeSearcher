import 'package:drift/drift.dart';

/// Tabla de cadenas de evolución
class EvolutionChains extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  IntColumn get babyTriggerItemId => integer().nullable()();
  
  // JSON completo de la cadena de evolución
  TextColumn get chainJson => text().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

