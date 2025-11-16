import 'package:drift/drift.dart';

/// Tabla de características de pokemon
class Characteristics extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  IntColumn get geneModulo => integer().nullable()();
  IntColumn get highestStatId => integer().nullable()();
  
  // JSON para valores posibles y descripciones
  TextColumn get possibleValuesJson => text().nullable()();
  TextColumn get dataJson => text().nullable()();
}

