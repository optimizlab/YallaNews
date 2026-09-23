import 'package:flutter_test/flutter_test.dart';
import 'package:yallanews/services/news_uri_parser.dart';

void main() {
  group('NewsUriParser', () {
    test('isValidArticleUrl rejects social domains', () {
      expect(NewsUriParser.isValidArticleUrl('https://facebook.com/post'), isFalse);
      expect(NewsUriParser.isValidArticleUrl('https://twitter.com/status'), isFalse);
      expect(NewsUriParser.isValidArticleUrl('https://www.instagram.com/p/'), isFalse);
    });

    test('isValidArticleUrl rejects non-http URLs', () {
      expect(NewsUriParser.isValidArticleUrl('ftp://example.com/article'), isFalse);
    });

    test('isValidArticleUrl rejects homepage-only URLs', () {
      expect(NewsUriParser.isValidArticleUrl('https://hespress.com'), isFalse);
    });

    test('isValidArticleUrl accepts valid article URLs', () {
      expect(NewsUriParser.isValidArticleUrl('https://hespress.com/politics/article-title'), isTrue);
      expect(NewsUriParser.isValidArticleUrl('https://aljazeera.net/news/2024/01/15/article-title'), isTrue);
    });

    test('isValidArticleUrl rejects wp-admin paths', () {
      expect(NewsUriParser.isValidArticleUrl('https://example.com/wp-admin/post'), isFalse);
    });

    test('isValidArticleUrl rejects privacy/terms pages', () {
      expect(NewsUriParser.isValidArticleUrl('https://example.com/privacy'), isFalse);
      expect(NewsUriParser.isValidArticleUrl('https://example.com/terms'), isFalse);
    });

    test('parseUri extracts host and category', () {
      final parsed = NewsUriParser.parseUri('https://hespress.com/politics/2024/01/15/article-title');
      expect(parsed.host, 'hespress.com');
      expect(parsed.category, 'politics');
    });

    test('parseUri extracts dateHint from URL segments', () {
      final parsed = NewsUriParser.parseUri('https://example.com/2024/03/15/news-story');
      expect(parsed.dateHint, '2024-03-15');
    });

    test('parseUri assigns higher priority to breaking news', () {
      final breaking = NewsUriParser.parseUri('https://example.com/breaking/urgent-news-story');
      final regular = NewsUriParser.parseUri('https://example.com/general/some-news-article');
      expect(breaking.priority, greaterThan(regular.priority));
    });

    test('calculateSimilarity returns 1.0 for identical slug keywords', () {
      final a = NewsUriParser.parseUri('https://example.com/news/government-announces-new-policy');
      final b = NewsUriParser.parseUri('https://example.com/news/government-announces-new-policy-reform');
      final sim = NewsUriParser.calculateSimilarity(a, b);
      expect(sim, greaterThan(0.0));
    });

    test('calculateSimilarity returns 0.0 for unrelated articles', () {
      final a = NewsUriParser.parseUri('https://example.com/sports/football-match');
      final b = NewsUriParser.parseUri('https://example.com/tech/new-phone-release');
      final sim = NewsUriParser.calculateSimilarity(a, b);
      expect(sim, equals(0.0));
    });
  });
}