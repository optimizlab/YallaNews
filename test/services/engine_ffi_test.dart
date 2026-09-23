import 'package:flutter_test/flutter_test.dart';
import 'package:yallanews/services/engine_ffi.dart';

void main() {
  group('EngineFfi', () {
    test('hasNativeEngine is a boolean', () {
      expect(hasNativeEngine, isA<bool>());
    });

    test('processUrlJson returns empty map when native engine unavailable', () {
      final result = processUrlJson('https://example.com');
      expect(result, isA<Map<String, dynamic>>());
    });

    test('analyzeArticleJson returns empty map when native engine unavailable', () {
      final result = analyzeArticleJson('{"title":"test"}');
      expect(result, isA<Map<String, dynamic>>());
    });

    test('initEngineWithJson does not throw when native engine unavailable', () {
      expect(() => initEngineWithJson('{}'), returnsNormally);
    });

    test('clusterArticlesJson returns empty list when native engine unavailable', () {
      final result = clusterArticlesJson('[]');
      expect(result, isA<List<dynamic>>());
      expect(result.length, equals(0));
    });

    test('clusterArticlesExJson returns empty list when native engine unavailable', () {
      final result = clusterArticlesExJson('[]', 0, 2, 0.5, 2);
      expect(result, isA<List<dynamic>>());
      expect(result.length, equals(0));
    });

    test('cleanArticleContentJson returns empty map when native engine unavailable', () {
      final result = cleanArticleContentJson('title', 'content');
      expect(result, isA<Map<String, dynamic>>());
    });

    test('extractStoryElementsJson returns empty map when native engine unavailable', () {
      final result = extractStoryElementsJson('title', 'content');
      expect(result, isA<Map<String, dynamic>>());
    });

    test('optimizeSentiment returns 0.0 when native engine unavailable', () {
      final result = optimizeSentiment('some text');
      expect(result, equals(0.0));
    });

    test('getEngineLogs returns empty string when native engine unavailable', () {
      final result = getEngineLogs();
      expect(result, isA<String>());
    });

    test('clearEngineLogs does not throw when native engine unavailable', () {
      expect(() => clearEngineLogs(), returnsNormally);
    });

    test('isValidImageUrl returns false when native engine unavailable', () {
      final result = isValidImageUrl('https://example.com/image.jpg');
      expect(result, isFalse);
    });

    test('splitParagraphsByDots returns empty list when native engine unavailable', () {
      final result = splitParagraphsByDots('Some content.');
      expect(result, isA<List<String>>());
      expect(result.length, equals(0));
    });
  });
}