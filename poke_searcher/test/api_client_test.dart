import 'package:flutter_test/flutter_test.dart';
import 'package:poke_searcher/services/download/api_client.dart';

void main() {
  group('ApiClient', () {
    test('isMediaUrl detecta URLs multimedia correctamente', () {
      expect(ApiClient.isMediaUrl('https://example.com/image.png'), isTrue);
      expect(ApiClient.isMediaUrl('https://example.com/image.jpg'), isTrue);
      expect(ApiClient.isMediaUrl('https://example.com/sound.ogg'), isTrue);
      expect(ApiClient.isMediaUrl('https://example.com/data.json'), isFalse);
      expect(ApiClient.isMediaUrl('https://pokeapi.co/api/v2/pokemon/1'), isFalse);
    });
  });
}

