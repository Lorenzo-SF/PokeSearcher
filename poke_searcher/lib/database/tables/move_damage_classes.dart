import 'package:drift/drift.dart';

/// Tabla de clases de daño de movimientos
class MoveDamageClasses extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  
  @override
  Set<Column> get primaryKey => {id};
}

