import 'package:drift/drift.dart';

/// Tabla para tracking de descargas por fase/entidad
class DownloadSync extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get phase => text()(); // 'essential', 'region', 'pokemon', 'media'
  TextColumn get entityType => text()(); // 'region', 'pokemon', 'type', etc.
  IntColumn get entityId => integer().nullable()(); // ID específico o null para "todos"
  DateTimeColumn get downloadedAt => dateTime()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  TextColumn get errorMessage => text().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
  
  @override
  List<Set<Column>> get uniqueKeys => [
    {phase, entityType, entityId}
  ];
}

