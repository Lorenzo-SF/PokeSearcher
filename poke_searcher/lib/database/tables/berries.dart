import 'package:drift/drift.dart';

/// Tabla de bayas (berries)
class Berries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get apiId => integer().unique()();
  TextColumn get name => text()();
  IntColumn get growthTime => integer().nullable()();
  IntColumn get maxHarvest => integer().nullable()();
  IntColumn get naturalGiftPower => integer().nullable()();
  IntColumn get size => integer().nullable()();
  IntColumn get smoothness => integer().nullable()();
  IntColumn get soilDryness => integer().nullable()();
  IntColumn get firmnessId => integer().nullable()();
  IntColumn get itemId => integer().nullable()();
  IntColumn get naturalGiftTypeId => integer().nullable()();
  
  // JSON completo
  TextColumn get dataJson => text().nullable()();
}

