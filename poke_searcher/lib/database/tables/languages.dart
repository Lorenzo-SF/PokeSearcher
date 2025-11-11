import 'package:drift/drift.dart';

/// Tabla de idiomas disponibles en la API
class Languages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  TextColumn get officialName => text().nullable()();
  TextColumn get iso639 => text().nullable()();
  TextColumn get iso3166 => text().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

