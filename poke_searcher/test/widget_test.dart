// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poke_searcher/main.dart';
import 'package:poke_searcher/database/app_database.dart';
import 'package:poke_searcher/services/config/app_config.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    // Setup: Initialize SharedPreferences and database for testing
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final appConfig = AppConfig(prefs);
    final database = AppDatabase.test();

    // Build our app and trigger a frame.
    await tester.pumpWidget(PokeSearchApp(
      database: database,
      appConfig: appConfig,
    ));

    // Verify that the app loads (we can check for any widget that should be present)
    await tester.pumpAndSettle();
    
    // The app should load without errors
    expect(tester.takeException(), isNull);
  });
}
