import 'package:flutter_test/flutter_test.dart';
import 'package:poke_searcher/models/mappers/language_mapper.dart';
import 'package:poke_searcher/models/mappers/region_mapper.dart';
import 'package:poke_searcher/models/mappers/type_mapper.dart';

void main() {
  group('LanguageMapper', () {
    test('Convierte JSON de API a LanguagesCompanion correctamente', () {
      final json = {
        'id': 9,
        'name': 'en',
        'official': true,
        'iso639': 'en',
        'iso3166': 'us',
      };

      final companion = LanguageMapper.fromApiJson(json);

      expect(companion.apiId.value, equals(9));
      expect(companion.name.value, equals('en'));
      expect(companion.iso639.value, equals('en'));
      expect(companion.iso3166.value, equals('us'));
    });
  });

  group('RegionMapper', () {
    test('Convierte JSON de API a RegionsCompanion correctamente', () {
      final json = {
        'id': 1,
        'name': 'kanto',
        'main_generation': {
          'name': 'generation-i',
          'url': 'https://pokeapi.co/api/v2/generation/1/',
        },
        'locations': [],
        'pokedexes': [],
        'version_groups': [],
      };

      final companion = RegionMapper.fromApiJson(json);

      expect(companion.apiId.value, equals(1));
      expect(companion.name.value, equals('kanto'));
      expect(companion.mainGenerationId.value, equals(1));
    });
  });

  group('TypeMapper', () {
    test('Convierte JSON de API a TypesCompanion correctamente', () {
      final json = {
        'id': 1,
        'name': 'normal',
        'generation': {
          'name': 'generation-i',
          'url': 'https://pokeapi.co/api/v2/generation/1/',
        },
        'move_damage_class': {
          'name': 'physical',
          'url': 'https://pokeapi.co/api/v2/move-damage-class/2/',
        },
        'damage_relations': {
          'double_damage_to': [],
          'half_damage_to': [],
          'no_damage_to': [],
          'double_damage_from': [],
          'half_damage_from': [],
          'no_damage_from': [],
        },
      };

      final companion = TypeMapper.fromApiJson(json);

      expect(companion.apiId.value, equals(1));
      expect(companion.name.value, equals('normal'));
      expect(companion.generationId.value, equals(1));
      expect(companion.moveDamageClassId.value, equals(2));
    });

    test('Extrae relaciones de daño correctamente', () {
      final json = {
        'id': 1,
        'name': 'normal',
        'damage_relations': {
          'double_damage_to': [
            {'name': 'rock', 'url': 'https://pokeapi.co/api/v2/type/6/'},
          ],
          'half_damage_to': [],
          'no_damage_to': [
            {'name': 'ghost', 'url': 'https://pokeapi.co/api/v2/type/8/'},
          ],
          'double_damage_from': [],
          'half_damage_from': [],
          'no_damage_from': [],
        },
      };

      final relations = TypeMapper.extractDamageRelations(json, 1);

      expect(relations.length, equals(2));
      expect(relations[0].relationType.value, equals('double_damage_to'));
      expect(relations[1].relationType.value, equals('no_damage_to'));
    });
  });
}

