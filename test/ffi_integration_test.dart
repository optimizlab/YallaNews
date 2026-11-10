// FFI Integration Tests for YallaNews
// Tests existing FFI bindings before migration

import 'package:flutter_test/flutter_test.dart';

import 'package:yallanews/services/yalla_ffi_io.dart' as yalla_io;
import 'package:yallanews/services/news_brain_ffi.dart';

void main() {
  group('yalla_engine FFI Tests', () {
    setUpAll(() {
      // Only run on platforms with FFI support
      if (!yalla_io.YallaFFIService.isSupported) {
        print('Skipping yalla_engine FFI tests - not supported on this platform');
        return;
      }
      yalla_io.YallaFFIService.loadLibrary();
    });

    test('Library loading', () {
      if (!yalla_io.YallaFFIService.isSupported) return;

      expect(() => yalla_io.YallaFFIService.loadLibrary(), returnsNormally);
      // Note: Will fail if DLL not present, which is expected in test env
    });

    test('init_engine with empty DB', () {
      if (!yalla_io.YallaFFIService.isSupported || !yalla_io.YallaFFIService.isLoaded) return;

      expect(() => yalla_io.YallaFFIService.initEngine('{}'), returnsNormally);
    });

    test('process_url with invalid URL', () {
      if (!yalla_io.YallaFFIService.isSupported || !yalla_io.YallaFFIService.isLoaded) return;

      // Should not crash, returns error JSON
      final result = yalla_io.YallaFFIService.processUrl('not-a-url');
      expect(result, isA<String>());
      expect(result, contains('success'));
    });

    test('get_logs returns string', () {
      if (!yalla_io.YallaFFIService.isSupported || !yalla_io.YallaFFIService.isLoaded) return;

      final logs = yalla_io.YallaFFIService.getLogs();
      expect(logs, isA<String>());
    });

    test('clear_logs works', () {
      if (!yalla_io.YallaFFIService.isSupported || !yalla_io.YallaFFIService.isLoaded) return;

      expect(() => yalla_io.YallaFFIService.clearLogs(), returnsNormally);
    });

    test('analyze_article with minimal input', () {
      if (!yalla_io.YallaFFIService.isSupported || !yalla_io.YallaFFIService.isLoaded) return;

      final input = '{"title":"Test","content":"Test content","summary":"Test summary"}';
      final result = yalla_io.YallaFFIService.analyzeArticle(input);
      expect(result, isA<String>());
    });
  });

  group('news_brain FFI Tests', () {
    late NewsBrainService newsBrain;

    setUpAll(() {
      newsBrain = NewsBrainService.instance;
    });

    test('Library loading on supported platforms', () {
      if (!newsBrain.isAvailable) {
        print('newsBrain not available on this platform - skipping');
        return;
      }
      expect(newsBrain.isAvailable, isTrue);
    });

    test('getVersion returns string', () {
      if (!newsBrain.isAvailable) return;

      final version = newsBrain.getVersion();
      expect(version, isA<String>());
      expect(version.isNotEmpty, isTrue);
    });

    test('analyzeSentiment with positive text', () async {
      if (!newsBrain.isAvailable) return;

      final sentiment = await newsBrain.analyzeSentiment('This is great news! Wonderful success!');
      expect(sentiment, greaterThan(0.0));
      expect(sentiment, lessThanOrEqualTo(1.0));
    });

    test('analyzeSentiment with negative text', () async {
      if (!newsBrain.isAvailable) return;

      final sentiment = await newsBrain.analyzeSentiment('Terrible disaster. Complete failure.');
      expect(sentiment, lessThan(0.0));
      expect(sentiment, greaterThanOrEqualTo(-1.0));
    });

    test('analyzeSentiment with neutral text', () async {
      if (!newsBrain.isAvailable) return;

      final sentiment = await newsBrain.analyzeSentiment('The meeting was held on Tuesday.');
      expect(sentiment.abs(), lessThanOrEqualTo(0.5));
    });

    test('classifyCategory returns category', () async {
      if (!newsBrain.isAvailable) return;

      final category = await newsBrain.classifyCategory(
        'Football match ends in victory',
        'The team won the championship after a thrilling match.',
        'Team wins championship'
      );
      expect(category, isA<String>());
      expect(category!.isNotEmpty, isTrue);
    });

    test('classifyArticle returns full analysis', () async {
      if (!newsBrain.isAvailable) return;

      final result = await newsBrain.classifyArticle(
        'Technology company announces new AI product',
        'The company revealed their latest artificial intelligence system today.',
        'New AI product announced'
      );
      expect(result, isA<Map<String, dynamic>>());
      expect(result!.containsKey('category'), isTrue);
      expect(result.containsKey('sentiment'), isTrue);
    });
  });

  group('Cross-engine consistency Tests', () {
    test('Both engines can coexist', () {
      // Verify both FFI services can be initialized without conflict
      expect(() {
        yalla_io.YallaFFIService.loadLibrary();
        // NewsBrainService initializes lazily on first use
        NewsBrainService.instance.getVersion();
      }, returnsNormally);
    });
  });

  group('Error Handling Tests', () {
    test('Null/empty input handling', () {
      if (!yalla_io.YallaFFIService.isSupported || !yalla_io.YallaFFIService.isLoaded) return;

      // These should not crash
      expect(() => yalla_io.YallaFFIService.processUrl(''), returnsNormally);
      expect(() => yalla_io.YallaFFIService.analyzeArticle('{}'), returnsNormally);
    });

    test('Invalid JSON handling', () {
      if (!yalla_io.YallaFFIService.isSupported || !yalla_io.YallaFFIService.isLoaded) return;

      expect(() => yalla_io.YallaFFIService.analyzeArticle('not json'), returnsNormally);
    });
  });
}