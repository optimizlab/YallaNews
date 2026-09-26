import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/news_source.dart';
import '../models/news_model.dart';
import '../services/server_api_service.dart';

class NewsDatabase {
  NewsDatabase._privateConstructor();
  static final NewsDatabase instance = NewsDatabase._privateConstructor();

  static Database? _db;
  static bool _hasFts5 = true;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      databaseFactory = databaseFactoryFfi;
    }

    final Directory docsDir = await getApplicationDocumentsDirectory();
    final String dbPath = p.join(docsDir.path, 'news_base_source.db');

    // If file exists but is corrupt (< 100 bytes is not a valid SQLite DB),
    // delete it so we can recreate cleanly.
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      final size = await dbFile.length();
      if (size < 100) {
        // Not a valid SQLite header (minimum 100 bytes for header page)
        await dbFile.delete();
      }
    }

      try {
      final db = await openDatabase(
        dbPath,
        version: 15, // v15: add url_blacklist table
        onCreate: (Database db, int version) async {
          await _createSchema(db);
          try {
            await _createFtsIndex(db);
          } catch (_) {
            _hasFts5 = false;
          }
          await _seedFromJson(db);
        },
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
            if (oldVersion < 2) {
              await db.execute('DROP TABLE IF EXISTS sources');
              await _createSchema(db);
              await _seedFromJson(db);
            }
            if (oldVersion < 3) {
              await db.execute('''
                CREATE TABLE IF NOT EXISTS crawled_articles (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  source_url TEXT NOT NULL,
                  url TEXT NOT NULL UNIQUE,
                  title TEXT NOT NULL,
                  summary TEXT NOT NULL,
                  content TEXT NOT NULL,
                  image_url TEXT NOT NULL,
                  category TEXT NOT NULL,
                  sentiment REAL NOT NULL,
                  keywords TEXT NOT NULL,
                  logs TEXT NOT NULL
                )
              ''');
            }
            if (oldVersion < 4) {
              try {
                await db.execute(
                  'ALTER TABLE crawled_articles ADD COLUMN crawled_at INTEGER NOT NULL DEFAULT 0',
                );
              } catch (_) {}
            }
            if (oldVersion < 8) {
              await db.execute('DROP TABLE IF EXISTS crawled_articles');
              await db.execute('''
                CREATE TABLE IF NOT EXISTS crawled_articles (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  source_url TEXT NOT NULL,
                  url TEXT NOT NULL UNIQUE,
                  title TEXT NOT NULL,
                  summary TEXT NOT NULL,
                  content TEXT NOT NULL,
                  image_url TEXT NOT NULL,
                  category TEXT NOT NULL,
                  sentiment REAL NOT NULL,
                  keywords TEXT NOT NULL,
                  logs TEXT NOT NULL,
                  crawled_at INTEGER NOT NULL DEFAULT 0,
                  author TEXT NOT NULL DEFAULT '',
                  publish_date TEXT NOT NULL DEFAULT ''
                )
              ''');
            }
            if (oldVersion < 9) {
              try {
                await db.execute(
                  'ALTER TABLE crawled_articles ADD COLUMN author TEXT NOT NULL DEFAULT ""',
                );
                await db.execute(
                  'ALTER TABLE crawled_articles ADD COLUMN publish_date TEXT NOT NULL DEFAULT ""',
                );
              } catch (_) {}
            }
            if (oldVersion < 10) {
              await db.execute('DELETE FROM sources');
              await _seedFromJson(db);
            }
            if (oldVersion < 11) {
              await db.execute("DELETE FROM sources WHERE country_code != 'MA'");
            }
            if (oldVersion < 12) {
              try {
                await db.execute(
                  'ALTER TABLE crawled_articles ADD COLUMN url_hash TEXT NOT NULL DEFAULT ""',
                );
                await db.execute(
                  'ALTER TABLE crawled_articles ADD COLUMN meta_tags TEXT NOT NULL DEFAULT "{}"',
                );
                await db.execute(
                  'ALTER TABLE crawled_articles ADD COLUMN source_count INTEGER NOT NULL DEFAULT 1',
                );
                await db.execute(
                  'ALTER TABLE crawled_articles ADD COLUMN sources TEXT NOT NULL DEFAULT ""',
                );
              } catch (_) {}
            }
            if (oldVersion < 13) {
              await db.execute('''
                CREATE TABLE IF NOT EXISTS yn_entities (
                  id TEXT PRIMARY KEY,
                  article_url TEXT NOT NULL,
                  type TEXT NOT NULL,
                  value TEXT NOT NULL,
                  normalized TEXT NOT NULL DEFAULT '',
                  language TEXT NOT NULL DEFAULT 'ar',
                  context TEXT NOT NULL DEFAULT '',
                  confidence REAL NOT NULL DEFAULT 1.0,
                  extracted_at INTEGER NOT NULL
                )
              ''');
              await db.execute('''
                CREATE TABLE IF NOT EXISTS yn_events (
                  id TEXT PRIMARY KEY,
                  article_url TEXT NOT NULL,
                  label TEXT NOT NULL,
                  date TEXT NOT NULL DEFAULT '',
                  location TEXT NOT NULL DEFAULT '',
                  actors TEXT NOT NULL DEFAULT '[]',
                  evidence TEXT NOT NULL DEFAULT '{}',
                  confidence REAL NOT NULL DEFAULT 1.0,
                  extracted_at INTEGER NOT NULL
                )
              ''');
              await db.execute('''
                CREATE TABLE IF NOT EXISTS yn_topics (
                  id TEXT PRIMARY KEY,
                  article_url TEXT NOT NULL,
                  primary_topic TEXT NOT NULL,
                  secondary_topics TEXT NOT NULL DEFAULT '[]',
                  themes TEXT NOT NULL DEFAULT '[]',
                  confidence REAL NOT NULL DEFAULT 1.0,
                  extracted_at INTEGER NOT NULL
                )
              ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS yn_claims (
        id TEXT PRIMARY KEY,
        article_url TEXT NOT NULL,
        claim_text TEXT NOT NULL,
        attributed_to TEXT NOT NULL DEFAULT '',
        evidence_span TEXT NOT NULL DEFAULT '',
        confidence REAL NOT NULL DEFAULT 1.0,
        extracted_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS url_blacklist (
        url_hash TEXT PRIMARY KEY,
        reason TEXT NOT NULL DEFAULT '',
        added_at INTEGER NOT NULL
      )
    ''');
  }
            if (oldVersion < 14) {
              try {
                await _createFtsIndex(db);
              } catch (_) {
                _hasFts5 = false;
              }
            }
            if (oldVersion < 15) {
              await db.execute('''
                CREATE TABLE IF NOT EXISTS url_blacklist (
                  url_hash TEXT PRIMARY KEY,
                  reason TEXT NOT NULL DEFAULT '',
                  added_at INTEGER NOT NULL
                )
              ''');
            }
          },
        onOpen: (Database db) async {
          // Verify the table has data; if not, seed it
          final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM sources'),
          );
          if (count == null || count == 0) {
            await _seedFromJson(db);
          }
        },
      );
      return db;
    } catch (e) {
      // If opening still fails, nuke the file and start fresh
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
        final db = await openDatabase(
          dbPath,
          version: 15,
          onCreate: (Database db, int version) async {
            await _createSchema(db);
            await _createFtsIndex(db);
            await _seedFromJson(db);
          },
        );
      return db;
    }
  }

  /// Create the sources and crawled_articles tables with all required columns.
  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        country TEXT NOT NULL,
        country_code TEXT NOT NULL,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        category TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'digital_news',
        language TEXT NOT NULL DEFAULT 'ar',
        rank INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS crawled_articles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_url TEXT NOT NULL,
        url TEXT NOT NULL UNIQUE,
        url_hash TEXT NOT NULL DEFAULT '',
        title TEXT NOT NULL,
        summary TEXT NOT NULL,
        content TEXT NOT NULL,
        image_url TEXT NOT NULL,
        category TEXT NOT NULL,
        sentiment REAL NOT NULL,
        keywords TEXT NOT NULL,
        logs TEXT NOT NULL,
        crawled_at INTEGER NOT NULL DEFAULT 0,
        author TEXT NOT NULL DEFAULT '',
        publish_date TEXT NOT NULL DEFAULT '',
        meta_tags TEXT NOT NULL DEFAULT '{}',
        source_count INTEGER NOT NULL DEFAULT 1,
        sources TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS yn_entities (
        id TEXT PRIMARY KEY,
        article_url TEXT NOT NULL,
        type TEXT NOT NULL,
        value TEXT NOT NULL,
        normalized TEXT NOT NULL DEFAULT '',
        language TEXT NOT NULL DEFAULT 'ar',
        context TEXT NOT NULL DEFAULT '',
        confidence REAL NOT NULL DEFAULT 1.0,
        extracted_at INTEGER NOT NULL,
        FOREIGN KEY(article_url) REFERENCES crawled_articles(url) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS yn_events (
        id TEXT PRIMARY KEY,
        article_url TEXT NOT NULL,
        label TEXT NOT NULL,
        date TEXT NOT NULL DEFAULT '',
        location TEXT NOT NULL DEFAULT '',
        actors TEXT NOT NULL DEFAULT '[]',
        evidence TEXT NOT NULL DEFAULT '{}',
        confidence REAL NOT NULL DEFAULT 1.0,
        extracted_at INTEGER NOT NULL,
        FOREIGN KEY(article_url) REFERENCES crawled_articles(url) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS yn_topics (
        id TEXT PRIMARY KEY,
        article_url TEXT NOT NULL,
        primary_topic TEXT NOT NULL,
        secondary_topics TEXT NOT NULL DEFAULT '[]',
        themes TEXT NOT NULL DEFAULT '[]',
        confidence REAL NOT NULL DEFAULT 1.0,
        extracted_at INTEGER NOT NULL,
        FOREIGN KEY(article_url) REFERENCES crawled_articles(url) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS yn_claims (
        id TEXT PRIMARY KEY,
        article_url TEXT NOT NULL,
        claim_text TEXT NOT NULL,
        attributed_to TEXT NOT NULL DEFAULT '',
        evidence_span TEXT NOT NULL DEFAULT '',
        confidence REAL NOT NULL DEFAULT 1.0,
        extracted_at INTEGER NOT NULL,
        FOREIGN KEY(article_url) REFERENCES crawled_articles(url) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _createFtsIndex(Database db) async {
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS crawled_articles_fts USING fts5(
        title,
        summary,
        content,
        keywords,
        content='crawled_articles',
        content_rowid='id'
      )
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS ai_crawled_articles_ai AFTER INSERT ON crawled_articles BEGIN
        INSERT INTO crawled_articles_fts(rowid, title, summary, content, keywords)
        VALUES (new.id, new.title, new.summary, new.content, new.keywords);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS au_crawled_articles_ad AFTER DELETE ON crawled_articles BEGIN
        INSERT INTO crawled_articles_fts(crawled_articles_fts, rowid, title, summary, content, keywords)
        VALUES ('delete', old.id, old.title, old.summary, old.content, old.keywords);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS bu_crawled_articles_au AFTER UPDATE ON crawled_articles BEGIN
        INSERT INTO crawled_articles_fts(crawled_articles_fts, rowid, title, summary, content, keywords)
        VALUES ('delete', old.id, old.title, old.summary, old.content, old.keywords);
        INSERT INTO crawled_articles_fts(rowid, title, summary, content, keywords)
        VALUES (new.id, new.title, new.summary, new.content, new.keywords);
      END
    ''');
  }

  /// Seed the database from the bundled news_sources_ar.json asset.
  static Future<void> _seedFromJson(Database db) async {
    try {
      final String jsonStr = await rootBundle.loadString(
        'assets/news_sources_ar.json',
      );
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final List<dynamic> countries = data['countries'] ?? [];

      final batch = db.batch();
      int insertedCount = 0;
      for (final country in countries) {
        final String countryName = country['country'] ?? '';
        final String countryCode = country['country_code'] ?? '';
        final List<dynamic> sources = country['sources'] ?? [];

        for (final source in sources) {
          // language field in JSON is a list; join to comma-separated string
          final langs = source['language'];
          final String language = (langs is List)
              ? langs.join(',')
              : (langs ?? 'ar').toString();

          batch.insert('sources', {
            'country': countryName,
            'country_code': countryCode,
            'name': source['name'] ?? '',
            'url': source['url'] ?? '',
            'category': source['category'] ?? 'general_news',
            'type': source['type'] ?? 'digital_news',
            'language': language,
            'rank': source['rank'] ?? 0,
          });
          insertedCount++;
        }
      }
      await batch.commit(noResult: true);
      print('[NewsDatabase] Seeded database with $insertedCount sources.');
    } catch (e) {
      // If JSON loading fails, we still have an empty but valid DB
      // This prevents a crash loop — the user just sees 0 sources
      print('[NewsDatabase] Failed to seed from JSON: $e');
    }
  }

  Future<List<NewsSource>> getAllSources({bool syncApi = true}) async {
    final db = await database;

    if (syncApi) {
      try {
        final apiSources = await ServerApiService.getSources();
        if (apiSources.isNotEmpty) {
          final batch = db.batch();
          for (final s in apiSources) {
            batch.insert(
              'sources',
              {
                'country': s['country'] ?? 'Morocco',
                'country_code': s['country_code'] ?? s['countryCode'] ?? 'MA',
                'name': s['name'] ?? '',
                'url': s['url'] ?? '',
                'category': s['category'] ?? 'general_news',
                'type': s['type'] ?? 'digital_news',
                'language': s['language'] is List ? (s['language'] as List).join(',') : (s['language'] ?? 'ar').toString(),
                'rank': s['rank'] ?? 0,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await batch.commit(noResult: true);
        }
      } catch (_) {
        // Fallback to local DB if API unavailable
      }
    }

    final List<Map<String, dynamic>> maps = await db.query('sources');
    return maps.map((map) => NewsSource.fromMap(map)).toList();
  }

  Future<void> addSource(NewsSource source) async {
    final db = await database;
    final map = source.toMap();
    map.remove('id'); // Let DB auto-increment
    await db.insert(
      'sources',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateSource(NewsSource source) async {
    final db = await database;
    await db.update(
      'sources',
      source.toMap(),
      where: 'id = ?',
      whereArgs: [source.id],
    );
  }

  Future<void> deleteSource(int id) async {
    final db = await database;
    await db.delete('sources', where: 'id = ?', whereArgs: [id]);
  }

  static bool _hasEnoughTitleWords(String title) {
    final wordCount = title
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    return wordCount >= 3;
  }

  Future<void> saveCrawledArticles(
    List<NewsModel> articles,
    String sourceUrl,
  ) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final art in articles) {
      batch.insert('crawled_articles', {
        'source_url': sourceUrl,
        'url': art.url,
        'url_hash': art.urlHash,
        'title': art.title,
        'summary': art.summary,
        'content': art.content,
        'image_url': art.imageUrl,
        'category': art.category,
        'sentiment': art.sentiment,
        'keywords': art.keywords.join(','),
        'logs': art.logs,
        'crawled_at': now,
        'author': art.author,
        'publish_date': art.publishDate,
        'meta_tags': jsonEncode(art.metaTags),
        'source_count': art.sourceCount,
        'sources': art.sources.join(','),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Fetch ALL crawled articles across all sources, newest first.
  Future<List<NewsModel>> getAllArticles({int limit = 100}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'crawled_articles',
      orderBy: 'crawled_at DESC, id DESC',
      limit: limit,
    );
    return maps.map((map) {
      return NewsModel(
        url: map['url'] as String,
        urlHash: map['url_hash'] as String? ?? '',
        title: map['title'] as String,
        summary: map['summary'] as String,
        content: map['content'] as String,
        imageUrl: map['image_url'] as String,
        category: map['category'] as String,
        sentiment: (map['sentiment'] as num).toDouble(),
        keywords: (map['keywords'] as String)
            .split(',')
            .where((k) => k.isNotEmpty)
            .toList(),
        logs: map['logs'] as String,
        author: map['author'] as String? ?? '',
        publishDate: map['publish_date'] as String? ?? '',
        metaTags: map['meta_tags'] != null
            ? Map<String, dynamic>.from(jsonDecode(map['meta_tags'] as String))
            : const {},
        sourceCount: (map['source_count'] as int?) ?? 1,
        sources: (map['sources'] as String? ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(),
      );
    }).toList();
  }

  Future<int> removeInvalidArticles() async {
    final db = await database;
    final invalidPatterns = [
      '%أخبار قطاع الأعمال%',
      '%أخبار القطاع%',
      '%أخبار الشركات%',
      '%أخبار التقنية%',
      '%أخبار الرياضة%',
      '%أخبار السياسة%',
      '%أخبار الاقتصاد%',
      '%أخبار المجتمع%',
      '%أخبار المحلية%',
      '%أخبار العالمية%',
      '%أخبار الثقافة%',
      '%أخبار الصحة%',
      '%أخبار التعليم%',
      '%أخبار العلوم%',
      '%أخبار البيئة%',
      '%أخبار السياحة%',
      '%أخبار الترفيه%',
      '%أخبار المنوعات%',
      '%أخبار عاجلة%',
      '%latest news%',
      '%breaking news%',
      '%top news%',
      '%all news%',
      '%all articles%',
      '%مقالات%',
      '%أخبار%',
      '%تقارير%',
      '%مجلة%',
      '%مجلات%',
      '%صحف%',
      '%صحافة%',
      '%إعلام%',
      '%منوعات%',
      '%العام%',
      '%الكل%',
      '%كل الأخبار%',
    ];
    
    int totalRemoved = 0;
    for (final pattern in invalidPatterns) {
      final result = await db.delete(
        'crawled_articles',
        where: 'title LIKE ? OR content LIKE ?',
        whereArgs: [pattern, pattern],
      );
      totalRemoved += result;
    }
    
    // Also remove articles with very short content
    final shortContentResult = await db.delete(
      'crawled_articles',
      where: 'length(content) < ?',
      whereArgs: [100],
    );
    totalRemoved += shortContentResult;
    
    // Also remove articles with URL paths that look like categories (1-2 segments)
    final categoryUrls = await db.query('crawled_articles');
    int removedByUrl = 0;
    for (final map in categoryUrls) {
      final url = map['url'] as String;
      final uri = Uri.tryParse(url);
      if (uri != null) {
        final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (pathSegments.length <= 2) {
          await db.delete('crawled_articles', where: 'url = ?', whereArgs: [url]);
          removedByUrl++;
        }
      }
    }
    totalRemoved += removedByUrl;
    
    return totalRemoved;
  }

  /// Return total count of crawled articles (fast check for first-run detection).
  Future<int> getArticleCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM crawled_articles');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Search articles using FTS5 full-text search, with LIKE fallback.
  Future<List<NewsModel>> searchArticles(String query, {int limit = 50}) async {
    final db = await database;
    final sanitized = query.trim().replaceAll('"', '""');
    final List<Map<String, dynamic>> maps;
    if (_hasFts5) {
      final ftsQuery = '"$sanitized"';
      maps = await db.rawQuery('''
        SELECT ca.*
        FROM crawled_articles ca
        JOIN crawled_articles_fts fts ON fts.rowid = ca.id
        WHERE crawled_articles_fts MATCH ?
        ORDER BY ca.crawled_at DESC
        LIMIT ?
      ''', [ftsQuery, limit]);
    } else {
      final like = '%$sanitized%';
      maps = await db.query(
        'crawled_articles',
        where: 'title LIKE ? OR summary LIKE ? OR content LIKE ? OR keywords LIKE ?',
        whereArgs: [like, like, like, like],
        orderBy: 'crawled_at DESC',
        limit: limit,
      );
    }
    return maps.map((map) {
      return NewsModel(
        url: map['url'] as String,
        urlHash: map['url_hash'] as String? ?? '',
        title: map['title'] as String,
        summary: map['summary'] as String,
        content: map['content'] as String,
        imageUrl: map['image_url'] as String,
        category: map['category'] as String,
        sentiment: (map['sentiment'] as num).toDouble(),
        keywords: (map['keywords'] as String)
            .split(',')
            .where((k) => k.isNotEmpty)
            .toList(),
        logs: map['logs'] as String,
        author: map['author'] as String? ?? '',
        publishDate: map['publish_date'] as String? ?? '',
        metaTags: map['meta_tags'] != null
            ? Map<String, dynamic>.from(jsonDecode(map['meta_tags'] as String))
            : const {},
        sourceCount: (map['source_count'] as int?) ?? 1,
        sources: (map['sources'] as String? ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(),
      );
    }).toList();
  }

  /// Return distinct source names that have been crawled.
  Future<List<String>> getCrawledSourceNames() async {
    final db = await database;
    final maps = await db.rawQuery(
      'SELECT DISTINCT source_url FROM crawled_articles ORDER BY crawled_at DESC',
    );
    return maps.map((m) => m['source_url'] as String).toList();
  }

  Future<List<NewsModel>> getArticlesBySource(String sourceUrl) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'crawled_articles',
      where: 'source_url = ?',
      whereArgs: [sourceUrl],
    );
    return maps.map((map) {
      return NewsModel(
        url: map['url'] as String,
        title: map['title'] as String,
        summary: map['summary'] as String,
        content: map['content'] as String,
        imageUrl: map['image_url'] as String,
        category: map['category'] as String,
        sentiment: (map['sentiment'] as num).toDouble(),
        keywords: (map['keywords'] as String)
            .split(',')
            .where((k) => k.isNotEmpty)
            .toList(),
        logs: map['logs'] as String,
        author: map['author'] as String? ?? '',
        publishDate: map['publish_date'] as String? ?? '',
      );
    }).toList();
  }

  Future<void> clearArticlesForSource(String sourceUrl) async {
    final db = await database;
    await db.delete(
      'crawled_articles',
      where: 'source_url = ?',
      whereArgs: [sourceUrl],
    );
  }

  Future<Set<String>> getCrawledSourceUrls() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT DISTINCT source_url FROM crawled_articles',
    );
    return maps.map((map) => map['source_url'] as String).toSet();
  }

  Future<bool> isImageUsedByOtherArticle(String imageUrl, String articleUrl, {String? sourceUrl}) async {
    if (imageUrl.isEmpty) return false;
    final db = await database;
    final whereClauses = <String>['image_url = ? AND url != ?'];
    final whereArgs = <dynamic>[imageUrl, articleUrl];
    if (sourceUrl != null) {
      whereClauses.add('source_url != ?');
      whereArgs.add(sourceUrl);
    }
    final result = await db.query(
      'crawled_articles',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<bool> articleUrlExists(String url) async {
    if (url.isEmpty) return false;
    final db = await database;
    final result = await db.query(
      'crawled_articles',
      where: 'url = ?',
      whereArgs: [url],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> clearAllArticles() async {
    final db = await database;
    await db.delete('crawled_articles');
  }

  /// Returns the timestamp of the most recent article crawled for this source.
  Future<DateTime?> getLastCrawlTime(String sourceUrl) async {
    final db = await database;
    final res = await db.rawQuery(
      'SELECT MAX(crawled_at) as ts FROM crawled_articles WHERE source_url = ?',
      [sourceUrl],
    );
    final ts = res.isNotEmpty ? res.first['ts'] as int? : null;
    return (ts != null && ts > 0)
        ? DateTime.fromMillisecondsSinceEpoch(ts)
        : null;
  }

  /// Compute a simple content fingerprint for deduplication:
  /// first 50 words + last 50 words of normalized title + content.
  static String _contentFingerprint(String title, String content) {
    final combined = '$title ${content.trim()}';
    final words = combined.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= 100) return combined;
    final first50 = words.take(50).join(' ');
    final last50 = words.sublist(words.length - 50).join(' ');
    return '$first50 $last50';
  }

  /// Find potential content duplicates among the given articles.
  /// Returns groups of URLs that share similar content fingerprints.
  static List<List<String>> findContentDuplicates(List<NewsModel> articles) {
    final Map<String, List<String>> fingerprintToUrls = {};
    for (final article in articles) {
      final fp = _contentFingerprint(article.title, article.content);
      fingerprintToUrls.putIfAbsent(fp, () => []).add(article.url);
    }
    return fingerprintToUrls.values.where((group) => group.length > 1).toList();
  }

  /// Remove content duplicates from the database for a given source.
  /// Keeps the newest article in each duplicate group and removes older ones.
  Future<void> deduplicateByContent(String sourceUrl) async {
    final db = await database;
    final articles = await getArticlesBySource(sourceUrl);
    final duplicateGroups = NewsDatabase.findContentDuplicates(articles);
    if (duplicateGroups.isEmpty) return;

    for (final group in duplicateGroups) {
      if (group.length <= 1) continue;
      group.sort((a, b) => 0);

      final urlsToRemove = group.sublist(1);
      for (final url in urlsToRemove) {
        await db.delete('crawled_articles', where: 'url = ?', whereArgs: [url]);
      }
    }
  }

  Future<bool> isUrlBlacklisted(String urlHash) async {
    if (urlHash.isEmpty) return false;
    final db = await database;
    final result = await db.query(
      'url_blacklist',
      where: 'url_hash = ?',
      whereArgs: [urlHash],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> addToBlacklist(String urlHash, {String reason = ''}) async {
    if (urlHash.isEmpty) return;
    final db = await database;
    await db.insert(
      'url_blacklist',
      {
        'url_hash': urlHash,
        'reason': reason,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> getBlacklistCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM url_blacklist');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> clearBlacklist() async {
    final db = await database;
    return await db.delete('url_blacklist');
  }

  Future<int> clearOldBlacklistEntries({int days = 7}) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final result = await db.delete(
      'url_blacklist',
      where: 'added_at < ?',
      whereArgs: [cutoff],
    );
    return result;
  }
}
