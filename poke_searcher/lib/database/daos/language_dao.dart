import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/languages.dart';
import '../tables/localized_names.dart';

part 'language_dao.g.dart';

/// Data Access Object para operaciones con idiomas
@DriftAccessor(tables: [Languages, LocalizedNames])
class LanguageDao extends DatabaseAccessor<AppDatabase> with _$LanguageDaoMixin {
  LanguageDao(super.db);
  
  /// Obtener todos los idiomas
  Future<List<Language>> getAllLanguages() async {
    return await select(languages).get();
  }
  
  /// Obtener idioma por ID
  Future<Language?> getLanguageById(int id) async {
    return await (select(languages)..where((t) => t.id.equals(id))).getSingleOrNull();
  }
  
  /// Obtener idioma por API ID
  Future<Language?> getLanguageByApiId(int apiId) async {
    return await (select(languages)..where((t) => t.apiId.equals(apiId))).getSingleOrNull();
  }
  
  /// Obtener idioma por nombre
  Future<Language?> getLanguageByName(String name) async {
    return await (select(languages)..where((t) => t.name.equals(name))).getSingleOrNull();
  }
  
  /// Obtener idioma por código ISO
  Future<Language?> getLanguageByIso(String iso) async {
    return await (select(languages)
      ..where((t) => 
        t.iso639.equals(iso) | 
        t.iso3166.equals(iso)))
      .getSingleOrNull();
  }
  
  /// Obtener nombre localizado de una entidad
  Future<String?> getLocalizedName({
    required String entityType,
    required int entityId,
    required int languageId,
  }) async {
    final query = select(localizedNames)
      ..where((t) => 
        t.entityType.equals(entityType) &
        t.entityId.equals(entityId) &
        t.languageId.equals(languageId));
    
    final result = await query.getSingleOrNull();
    return result?.name;
  }
  
  /// Obtener todos los nombres localizados de una entidad
  Future<Map<int, String>> getAllLocalizedNames({
    required String entityType,
    required int entityId,
  }) async {
    final query = select(localizedNames)
      ..where((t) => 
        t.entityType.equals(entityType) &
        t.entityId.equals(entityId));
    
    final results = await query.get();
    return Map.fromEntries(
      results.map((r) => MapEntry(r.languageId, r.name)),
    );
  }
}

