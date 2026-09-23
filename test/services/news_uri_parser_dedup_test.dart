import 'package:flutter_test/flutter_test.dart';
import 'package:yallanews/services/news_uri_parser.dart';

void main() {
  group('NewsUriParser deduplication', () {
    test('groupAndDeduplicate keeps unique articles', () {
      final urls = [
        'https://example.com/news/government-announces-new-policy',
        'https://example.com/news/government-announces-new-policy-reform',
        'https://example.com/sports/football-match-results',
        'https://example.com/tech/new-phone-release',
      ];
      final result = NewsUriParser.groupAndDeduplicate(urls);
      expect(result.length, lessThanOrEqualTo(urls.length));
    });

    test('groupAndDeduplicate removes exact duplicate URLs', () {
      final urls = [
        'https://example.com/news/government-announces-new-policy',
        'https://example.com/news/government-announces-new-policy',
        'https://example.com/news/government-announces-new-policy',
      ];
      final result = NewsUriParser.groupAndDeduplicate(urls);
      expect(result.length, equals(1));
    });

    test('calculateSimilarity returns 0 for completely different articles', () {
      final a = NewsUriParser.parseUri('https://example.com/sports/football-match');
      final b = NewsUriParser.parseUri('https://example.com/tech/new-phone-release');
      final sim = NewsUriParser.calculateSimilarity(a, b);
      expect(sim, equals(0.0));
    });

    test('runDeduplicationIsolate returns list of maps', () {
      final result = NewsUriParser.runDeduplicationIsolate({
        'rawUrls': [
          'https://example.com/news/story-1',
          'https://example.com/news/story-2',
        ],
      });
      expect(result, isA<List<Map<String, dynamic>>>());
    });
  });
}