import 'package:flutter_test/flutter_test.dart';
import 'package:poke_searcher/database/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    // Usar base de datos en memoria para tests
    database = AppDatabase.test();
  });

  tearDown(() async {
    await database.close();
  });

  test('Database se crea correctamente', () async {
    expect(database, isNotNull);
    expect(database.schemaVersion, equals(1));
  });

  test('Tablas se crean correctamente', () async {
    // Verificar que las tablas existen consultándolas
    final languages = await database.select(database.languages).get();
    final regions = await database.select(database.regions).get();
    final types = await database.select(database.types).get();
    
    expect(languages, isA<List>());
    expect(regions, isA<List>());
    expect(types, isA<List>());
  });
}

