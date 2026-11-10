import 'package:flutter_test/flutter_test.dart';
import 'package:yallanews/models/news_model.dart';

void main() {
  group('NewsModel image URL resolution', () {
    test('resolves a relative image path against the article URL', () {
      expect(
        NewsModel.resolveImageUrl(
          '../images/story.jpg',
          'https://news.example.com/world/story',
        ),
        'https://news.example.com/images/story.jpg',
      );
    });

    test('resolves root-relative and protocol-relative image URLs', () {
      expect(
        NewsModel.resolveImageUrl(
          '/media/story.jpg',
          'https://news.example.com/world/story',
        ),
        'https://news.example.com/media/story.jpg',
      );
      expect(
        NewsModel.resolveImageUrl(
          '//cdn.example.com/story.jpg',
          'http://news.example.com/world/story',
        ),
        'http://cdn.example.com/story.jpg',
      );
    });

    test('keeps absolute image URLs and rejects non-web URLs', () {
      expect(
        NewsModel.resolveImageUrl(
          'https://cdn.example.com/story.jpg',
          'https://news.example.com/story',
        ),
        'https://cdn.example.com/story.jpg',
      );
      expect(
        NewsModel.resolveImageUrl(
          'data:image/png;base64,abc',
          'https://news.example.com/story',
        ),
        isEmpty,
      );
    });
  });

  group('NewsModel source attribution (Fix 3)', () {
    test('preserves API language through serialization and copyWith', () {
      final article = NewsModel.fromJson({
        'title': 'A headline',
        'summary': '',
        'content': '',
        'category': 'politics',
        'language': 'en',
      }, 'https://example.com/article');

      expect(article.language, 'en');
      expect(article.copyWith(language: 'fr').language, 'fr');
      expect(article.toJson()['language'], 'en');
    });

    test('fromJson maps complete source metadata', () {
      final json = {
        'id': 'art_1',
        'url': 'https://example.com/article/1',
        'title': 'Titre de l article',
        'summary': 'Résumé',
        'content': 'Contenu complet',
        'imageUrl': 'https://example.com/img.jpg',
        'category': 'general',
        'sentiment': 0.0,
        'keywords': [],
        'logs': '',
        'author': 'Jane Doe',
        'author_name': 'Jane Doe',
        'publishDate': '1700000000000',
        'published_at': '1700000000000',
        'updated_at': '1700001000000',
        'eventType': 'general',
        'source_name': 'Al Example News',
        'source_url': 'https://example.com/',
        'image_credit': '© Al Example News',
        'image_source_url': 'https://example.com/img.jpg',
      };
      final article = NewsModel.fromJson(json, 'https://example.com/article/1');
      expect(article.authorName, 'Jane Doe');
      expect(article.sourceName, 'Al Example News');
      expect(article.sourceUrl, 'https://example.com/');
      expect(article.publishedAt, '1700000000000');
      expect(article.updatedAt, '1700001000000');
      expect(article.imageCredit, '© Al Example News');
      expect(article.imageSourceUrl, 'https://example.com/img.jpg');
    });

    test('fromJson reads the nested source returned by the news API', () {
      final article = NewsModel.fromJson({
        'title': 'A headline',
        'summary': '',
        'content': '',
        'category': 'sports',
        'source': {'name': 'Example News', 'url': 'https://example.com/'},
      }, 'https://example.com/news/article');

      expect(article.sourceName, 'Example News');
      expect(article.sourceUrl, 'https://example.com/');
      expect(article.displaySourceName, 'Example News');
    });

    test('fromJson with missing metadata stays safe and empty', () {
      final json = {
        'id': 'art_2',
        'url': 'https://example.com/article/2',
        'title': 'Titre',
        'summary': 'Résumé',
        'content': 'Contenu',
        'imageUrl': '',
        'category': 'general',
        'sentiment': 0.0,
        'keywords': [],
        'logs': '',
        'author': '',
        'publishDate': '',
        'eventType': 'general',
      };
      final article = NewsModel.fromJson(json, 'https://example.com/article/2');
      expect(article.sourceName, '');
      expect(article.sourceUrl, '');
      expect(article.authorName, '');
      expect(article.publishedAt, '');
      expect(article.updatedAt, '');
      expect(article.imageCredit, '');
      expect(article.imageSourceUrl, '');
    });

    test('displaySourceName prefers the original publisher name', () {
      final withSource = NewsModel(
        url: 'https://example.com/art',
        title: 'T',
        summary: 'S',
        content: 'C',
        imageUrl: '',
        category: 'general',
        sentiment: 0.0,
        keywords: [],
        logs: '',
        author: '',
        publishDate: '',
        sourceName: 'Le Journal',
        sourceUrl: 'https://lejournal.com/',
      );
      expect(withSource.displaySourceName, 'Le Journal');

      final domainOnly = NewsModel(
        url: 'https://www.unknown-press.com/art',
        title: 'T',
        summary: 'S',
        content: 'C',
        imageUrl: '',
        category: 'general',
        sentiment: 0.0,
        keywords: [],
        logs: '',
        author: '',
        publishDate: '',
      );
      expect(domainOnly.displaySourceName, 'unknown-press.com');

      final unknown = NewsModel(
        url: '',
        title: 'T',
        summary: 'S',
        content: 'C',
        imageUrl: '',
        category: 'general',
        sentiment: 0.0,
        keywords: [],
        logs: '',
        author: '',
        publishDate: '',
      );
      expect(unknown.displaySourceName, '');
    });

    test('toJson round-trip preserves attribution fields', () {
      final article = NewsModel(
        url: 'https://example.com/art',
        title: 'T',
        summary: 'S',
        content: 'C',
        imageUrl: '',
        category: 'general',
        sentiment: 0.0,
        keywords: [],
        logs: '',
        author: 'A',
        authorName: 'A',
        publishDate: '1700000000000',
        publishedAt: '1700000000000',
        updatedAt: '1700001000000',
        sourceName: 'Src',
        sourceUrl: 'https://src.com/',
        imageCredit: 'cr',
        imageSourceUrl: 'https://src.com/i.jpg',
      );
      final json = article.toJson();
      expect(json['source_name'], 'Src');
      expect(json['source_url'], 'https://src.com/');
      expect(json['author_name'], 'A');
      expect(json['published_at'], '1700000000000');
      expect(json['updated_at'], '1700001000000');
      expect(json['image_credit'], 'cr');
      expect(json['image_source_url'], 'https://src.com/i.jpg');
    });
  });

  group('NewsModel publication date parsing', () {
    test('parses epoch milliseconds string', () {
      final a = NewsModel(
        url: 'u',
        title: 't',
        summary: 's',
        content: 'c',
        imageUrl: '',
        category: 'g',
        sentiment: 0.0,
        keywords: [],
        logs: '',
        author: '',
        publishDate: '',
        publishedAt: '1700000000000',
      );
      expect(
        a.publicationDate,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    });

    test('returns null for missing date', () {
      final a = NewsModel(
        url: 'u',
        title: 't',
        summary: 's',
        content: 'c',
        imageUrl: '',
        category: 'g',
        sentiment: 0.0,
        keywords: [],
        logs: '',
        author: '',
        publishDate: '',
        publishedAt: '',
      );
      expect(a.publicationDate, isNull);
    });

    test('returns null for malformed date', () {
      final a = NewsModel(
        url: 'u',
        title: 't',
        summary: 's',
        content: 'c',
        imageUrl: '',
        category: 'g',
        sentiment: 0.0,
        keywords: [],
        logs: '',
        author: '',
        publishDate: 'not-a-date',
        publishedAt: '',
      );
      expect(a.publicationDate, isNull);
    });
  });

  group('NewsModel freshness (Fix 4)', () {
    final now = DateTime.now();

    NewsModel freshArticle({required int daysAgo, bool currentEvent = false}) {
      final d = now.subtract(Duration(days: daysAgo));
      return NewsModel(
        url: 'u',
        title: 't',
        summary: 's',
        content: 'c',
        imageUrl: '',
        category: currentEvent ? 'breaking' : 'general',
        sentiment: 0.0,
        keywords: [],
        logs: '',
        author: '',
        publishDate: '',
        publishedAt: d.millisecondsSinceEpoch.toString(),
        eventType: currentEvent ? 'breaking' : 'general',
      );
    }

    test('current-events article within 30 days is fresh', () {
      expect(
        freshArticle(daysAgo: 10, currentEvent: true).isFreshForFeed(),
        isTrue,
      );
    });

    test('current-events article older than 30 days is stale', () {
      expect(
        freshArticle(daysAgo: 45, currentEvent: true).isFreshForFeed(),
        isFalse,
      );
    });

    test('general article within 3 months is fresh', () {
      expect(freshArticle(daysAgo: 60).isFreshForFeed(), isTrue);
    });

    test('general article older than 3 months is stale', () {
      expect(freshArticle(daysAgo: 100).isFreshForFeed(), isFalse);
    });

    test('article with missing date is kept (not fabricated)', () {
      final a = NewsModel(
        url: 'u',
        title: 't',
        summary: 's',
        content: 'c',
        imageUrl: '',
        category: 'breaking',
        sentiment: 0.0,
        keywords: [],
        logs: '',
        author: '',
        publishDate: '',
        publishedAt: '',
        eventType: 'breaking',
      );
      expect(a.isFreshForFeed(currentEventsMaxAgeDays: 30), isTrue);
    });

    test('future date is kept and not adjusted', () {
      final d = now.add(const Duration(days: 5));
      final a = NewsModel(
        url: 'u',
        title: 't',
        summary: 's',
        content: 'c',
        imageUrl: '',
        category: 'breaking',
        sentiment: 0.0,
        keywords: [],
        logs: '',
        author: '',
        publishDate: '',
        publishedAt: d.millisecondsSinceEpoch.toString(),
        eventType: 'breaking',
      );
      expect(a.isFreshForFeed(currentEventsMaxAgeDays: 30), isTrue);
    });

    test('custom thresholds are respected', () {
      final a = freshArticle(daysAgo: 20, currentEvent: true);
      expect(a.isFreshForFeed(currentEventsMaxAgeDays: 10), isFalse);
      expect(a.isFreshForFeed(currentEventsMaxAgeDays: 30), isTrue);
    });
  });
}
