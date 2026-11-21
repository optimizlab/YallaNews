import 'package:test/test.dart';
import 'package:yallanews/services/publication_date_extractor.dart';
import 'package:yallanews/services/freshness_engine.dart';
import 'package:yallanews/services/candidate_queue.dart';
import 'package:yallanews/models/news_model.dart';

NewsModel _article({
  required String url,
  DateTime? publishedAt,
  DateTime? publishDate,
  int hoursAgo = 0,
  bool emptyDate = false,
}) {
  final now = DateTime.now();
  final dt = publishedAt ?? publishDate;
  String pub;
  if (emptyDate) {
    pub = '';
  } else if (dt != null) {
    pub = dt.toUtc().toIso8601String();
  } else {
    pub = now.subtract(Duration(hours: hoursAgo)).toUtc().toIso8601String();
  }
  return NewsModel(
    url: url,
    urlHash: '',
    title: 'Title',
    shortTitle: '',
    summary: 'Summary',
    content: 'Content',
    imageUrl: '',
    category: 'general',
    language: 'en',
    sentiment: 0.0,
    keywords: [],
    logs: '',
    author: '',
    publishDate: pub,
    eventType: 'general',
    subcategory: 'general',
    entities: [],
    structuredData: const {},
    intelligenceJson: '',
    metaTags: const {},
    hashtags: '',
    youtubeVideoId: '',
    instagramVideoId: '',
    twitterVideoUrl: '',
    imageId: '',
    sourceCount: 1,
    sources: [],
    isFresh: true,
    readCount: 0,
    commentCount: 0,
    likeCount: 0,
    sourceName: '',
    sourceUrl: '',
    authorName: '',
    publishedAt: publishedAt?.toIso8601String() ?? '',
    updatedAt: '',
    imageCredit: '',
    imageSourceUrl: '',
    latitude: null,
    longitude: null,
    aiSummary: '',
    translations: const {},
    relevanceScore: 0.5,
  );
}

void main() {
  group('PublicationDateExtractor', () {
    final extractor = PublicationDateExtractor();

    test('extracts RSS pubDate', () {
      final html = '''
        <rss><channel>
          <item><title>News</title><pubDate>Mon, 21 Nov 2023 10:00:00 GMT</pubDate></item>
        </channel></rss>
      ''';
      final date = extractor.extractFromFeedOrSitemap(html);
      expect(date, isNotNull);
      expect(date!.source, 'rss');
      expect(date.confidence, greaterThan(0.9));
      expect(date.utc?.year, 2023);
      expect(date.utc?.month, 11);
      expect(date.utc?.day, 21);
    });

    test('extracts Atom published', () {
      final html = '''
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry><title>News</title><published>2023-11-21T10:00:00Z</published></entry>
        </feed>
      ''';
      final date = extractor.extractFromFeedOrSitemap(html);
      expect(date, isNotNull);
      expect(date!.source, 'atom');
      expect(date.utc?.year, 2023);
      expect(date.utc?.day, 21);
    });

    test('extracts JSON-LD datePublished', () {
      final html = '''
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"NewsArticle","headline":"News","datePublished":"2023-11-21T10:00:00+01:00","dateModified":"2023-11-22T12:00:00+01:00"}
        </script>
      ''';
      final date = extractor.extractFromArticleHtml(html);
      expect(date, isNotNull);
      expect(date.source, 'json-ld');
      expect(date.utc?.hour, 9);
      expect(date.confidence, greaterThan(0.8));
    });

    test('extracts Open Graph article:published_time', () {
      final html = '''
        <html><head><meta property="article:published_time" content="2023-11-21T10:00:00+02:00"/></head></html>
      ''';
      final date = extractor.extractFromArticleHtml(html);
      expect(date, isNotNull);
      expect(date.source, 'opengraph');
      expect(date.utc?.hour, 8);
    });

    test('extracts HTML time datetime', () {
      final html = '''
        <html><body><time datetime="2023-11-21T10:00:00Z">Nov 21</time></body></html>
      ''';
      final date = extractor.extractFromArticleHtml(html);
      expect(date, isNotNull);
      expect(date.source, 'html-time');
      expect(date.utc?.day, 21);
    });

    test('extracts meta article:published_time', () {
      final html = '''
        <html><head><meta name="article:published_time" content="2023-11-21T10:00:00Z"/></head></html>
      ''';
      final date = extractor.extractFromArticleHtml(html);
      expect(date, isNotNull);
      expect(date.source, 'meta-article:published_time');
      expect(date.utc?.hour, 10);
    });

    test('returns unknown when no date present', () {
      final html = '<html><body><p>No date here</p></body></html>';
      final date = extractor.extractFromArticleHtml(html);
      expect(date.isKnown, isFalse);
      expect(date.source, 'unknown');
      expect(date.confidence, 0.0);
    });

    test('never fabricates a date', () {
      final html = '<html><body><p>Article without any date metadata</p></body></html>';
      final date = extractor.extractFromArticleHtml(html);
      expect(date.utc, isNull);
      expect(date.epochMs, 0);
    });

    test('prefers highest-confidence source', () {
      final html = '''
        <html>
        <head>
          <meta name="date" content="2023-11-20T10:00:00Z"/>
          <script type="application/ld+json">
          {"@type":"NewsArticle","datePublished":"2023-11-21T10:00:00Z"}
          </script>
        </head></html>
      ''';
      final date = extractor.extractFromArticleHtml(html);
      expect(date, isNotNull);
      expect(date!.utc?.day, 21);
    });
  });

  group('FreshnessEngine', () {
    final engine = FreshnessEngine();

    test('classifies 0-1 hour as VERY_FRESH', () {
      final future = DateTime.now().add(const Duration(seconds: 30));
      final a = _article(url: 'https://example.com/fresh', publishedAt: future);
      expect(engine.classify(a), FreshnessClass.veryFresh);
    });

    test('classifies 3 hours as FRESH', () {
      final a = _article(url: 'https://example.com/fresh3', hoursAgo: 2);
      expect(engine.classify(a), FreshnessClass.fresh);
    });

    test('classifies 12 hours as RECENT', () {
      final a = _article(url: 'https://example.com/recent', hoursAgo: 12);
      expect(engine.classify(a), FreshnessClass.recent);
    });

    test('classifies 36 hours as OLDER', () {
      final a = _article(url: 'https://example.com/older', hoursAgo: 36);
      expect(engine.classify(a), FreshnessClass.older);
    });

    test('classifies 60 hours as BACKFILL', () {
      final a = _article(url: 'https://example.com/backfill', hoursAgo: 60);
      expect(engine.classify(a), FreshnessClass.backfill);
    });

    test('classifies 100 hours as ARCHIVE', () {
      final a = _article(url: 'https://example.com/archive', hoursAgo: 100);
      expect(engine.classify(a), FreshnessClass.archive);
    });

    test('classifies unknown date as unknownDate', () {
      final a = _article(url: 'https://example.com/unknown', emptyDate: true);
      expect(engine.classify(a), FreshnessClass.unknownDate);
    });

    test('sorts newest first with unknown dates last', () {
      final now = DateTime.now();
      final old = _article(url: 'https://example.com/old', publishedAt: now.subtract(const Duration(hours: 48)));
      final newer = _article(url: 'https://example.com/newer', publishedAt: now.subtract(const Duration(hours: 2)));
      final unknown = _article(url: 'https://example.com/unknown2', emptyDate: true);
      final sorted = engine.sortNewestFirst([old, unknown, newer]);
      expect(sorted.first.url, newer.url);
      expect(sorted.last.url, unknown.url);
      expect(sorted[1].url, old.url);
    });

    test('filters at least fresh excludes old', () {
      final recent = _article(url: 'https://example.com/recent2', hoursAgo: 2);
      final old = _article(url: 'https://example.com/older2', hoursAgo: 48);
      final filtered = engine.filterAtLeastFresh(
        [recent, old],
        minClass: FreshnessClass.recent,
      );
      expect(filtered.length, 1);
      expect(filtered.first.url, recent.url);
    });

    test('includes unknown dates when requested', () {
      final unknown = _article(url: 'https://example.com/unknown3', emptyDate: true);
      final recent = _article(url: 'https://example.com/recent3', hoursAgo: 2);
      final filtered = engine.filterAtLeastFresh(
        [unknown, recent],
        minClass: FreshnessClass.recent,
        includeUnknown: true,
      );
      expect(filtered.length, 2);
    });
  });

  group('CandidateQueue', () {
    test('deduplicates by URL', () {
      final queue = CandidateQueue();
      final c1 = CrawlCandidate(
        url: 'https://example.com/a',
        sourceId: 's1',
        discoveryMethod: 'rss',
        freshness: FreshnessClass.fresh,
      );
      final c2 = CrawlCandidate(
        url: 'https://example.com/A',
        sourceId: 's1',
        discoveryMethod: 'rss',
        freshness: FreshnessClass.fresh,
      );
      expect(queue.add(c1), isTrue);
      expect(queue.add(c2), isFalse);
      expect(queue.length, 1);
    });

    test('prioritizes fresher articles first', () {
      final queue = CandidateQueue();
      final now = DateTime.now();
      final old = CrawlCandidate(
        url: 'https://example.com/old',
        sourceId: 's1',
        publishedAt: now.subtract(const Duration(hours: 48)),
        discoveredAt: now.subtract(const Duration(hours: 48)),
        discoveryMethod: 'rss',
        freshness: FreshnessClass.older,
      );
      final fresh = CrawlCandidate(
        url: 'https://example.com/fresh',
        sourceId: 's1',
        publishedAt: now.subtract(const Duration(hours: 2)),
        discoveredAt: now.subtract(const Duration(hours: 2)),
        discoveryMethod: 'rss',
        freshness: FreshnessClass.fresh,
      );
      queue.addAll([old, fresh]);
      final first = queue.pop();
      expect(first?.url, fresh.url);
    });

    test('prioritizes higher source priority', () {
      final queue = CandidateQueue();
      final now = DateTime.now();
      final low = CrawlCandidate(
        url: 'https://example.com/low',
        sourceId: 's1',
        publishedAt: now.subtract(const Duration(hours: 2)),
        discoveryMethod: 'rss',
        freshness: FreshnessClass.fresh,
        sourcePriority: 1,
      );
      final high = CrawlCandidate(
        url: 'https://example.com/high',
        sourceId: 's2',
        publishedAt: now.subtract(const Duration(hours: 2)),
        discoveryMethod: 'rss',
        freshness: FreshnessClass.fresh,
        sourcePriority: 100,
      );
      queue.addAll([low, high]);
      final first = queue.pop();
      expect(first?.url, high.url);
    });

    test('marks failed candidate for retry with backoff', () {
      final queue = CandidateQueue();
      final c = CrawlCandidate(
        url: 'https://example.com/a',
        sourceId: 's1',
        discoveryMethod: 'rss',
        freshness: FreshnessClass.fresh,
      );
      queue.add(c);
      final popped = queue.pop();
      expect(popped, isNotNull);
      expect(popped!.status, CrawlStatus.fetching);
      queue.retry(popped, error: 'timeout', backoff: const Duration(minutes: 5));
      final retried = queue.byStatus(CrawlStatus.retrying);
      expect(retried.isNotEmpty, isTrue);
      expect(retried.first.lastError, 'timeout');
      expect(retried.first.retryAfter, isNotNull);
    });
  });

  group('NewsModel date parsing', () {
    test('parses ISO-8601 publication date', () {
      final pub = DateTime.utc(2023, 11, 21, 10, 0, 0);
      final a = _article(
        url: 'https://example.com/a',
        publishedAt: pub,
      );
      expect(a.publicationDate, pub);
    });

    test('returns null for empty publish date', () {
      final a = _article(url: 'https://example.com/a', emptyDate: true);
      expect(a.publicationDate, isNull);
    });

    test('prefers publishDate over publishedAt when publishedAt empty', () {
      final pub = DateTime.utc(2023, 11, 21, 10, 0, 0);
      final a = _article(
        url: 'https://example.com/a',
        publishDate: pub,
      );
      expect(a.publicationDate, pub);
    });

    test('isWithinDays with unknown date returns true (kept)', () {
      final a = _article(url: 'https://example.com/a', emptyDate: true);
      expect(a.isWithinDays(7), isTrue);
    });

    test('isWithinDays with future date returns false', () {
      final future = DateTime.now().add(const Duration(days: 30));
      final a = _article(
        url: 'https://example.com/a',
        publishedAt: future,
      );
      expect(a.isWithinDays(7), isFalse);
    });
  });
}
