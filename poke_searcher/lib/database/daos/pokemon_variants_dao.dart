import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/pokemon_variants.dart';

part 'pokemon_variants_dao.g.dart';

/// Data Access Object para operaciones con variantes de pokemon
@DriftAccessor(tables: [PokemonVariants])
class PokemonVariantsDao extends DatabaseAccessor<AppDatabase> with _$PokemonVariantsDaoMixin {
  PokemonVariantsDao(super.db);
  
  /// Obtener todas las variantes de un pokemon
  Future<List<PokemonVariant>> getVariants(int pokemonId) async {
    return await (select(pokemonVariants)
      ..where((t) => t.pokemonId.equals(pokemonId)))
      .get();
  }
  
  /// Alias para compatibilidad
  Future<List<PokemonVariant>> getVariantsForPokemon(int pokemonId) async {
    return getVariants(pokemonId);
  }
  
  /// Obtener el pokemon default de una variante
  Future<PokemonVariant?> getDefaultPokemon(int variantPokemonId) async {
    return await (select(pokemonVariants)
      ..where((t) => t.variantPokemonId.equals(variantPokemonId)))
      .getSingleOrNull();
  }
  
  /// Obtener el ID del pokemon default de una variante
  Future<int?> getDefaultPokemonId(int variantPokemonId) async {
    final variant = await getDefaultPokemon(variantPokemonId);
    return variant?.pokemonId;
  }
  
  /// Insertar relación de variante
  Future<void> insertVariant({
    required int pokemonId,
    required int variantPokemonId,
  }) async {
    final companion = PokemonVariantsCompanion(
      pokemonId: Value(pokemonId),
      variantPokemonId: Value(variantPokemonId),
    );
    
    await into(pokemonVariants).insert(
      companion,
      mode: InsertMode.replace,
    );
  }
  
  /// Insertar múltiples variantes en batch
  Future<void> insertVariantsBatch(List<PokemonVariantsCompanion> variants) async {
    await batch((batch) {
      batch.insertAll(pokemonVariants, variants, mode: InsertMode.replace);
    });
  }
  
  /// Eliminar todas las variantes de un pokemon
  Future<void> deleteVariants(int pokemonId) async {
    await (delete(pokemonVariants)
      ..where((t) => t.pokemonId.equals(pokemonId)))
      .go();
  }
}

