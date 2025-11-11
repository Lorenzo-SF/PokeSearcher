import 'package:drift/drift.dart';

/// Tabla de grupos de huevo
class EggGroups extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  
  @override
  Set<Column> get primaryKey => {id};
}

