import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/news_model.dart';
import '../models/news_source.dart';
import 'server_api_service.dart';
import 'news_uri_parser.dart';
import 'yalla_engine_service.dart';

typedef ArticleValidator = bool Function(NewsModel article);
typedef ArticleTransformer = NewsModel Function(NewsModel article);

class NewsCrawlerService {
  NewsCrawlerService._privateConstructor();
  static final NewsCrawlerService instance =
      NewsCrawlerService._privateConstructor();

  final YallaEngineService _engine = YallaEngineService();
  final List<ArticleValidator> _validators = <ArticleValidator>[];
  final List<ArticleTransformer> _transformers = <ArticleTransformer>[];

  bool _isCrawling = false;
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  Stream<String> get logStream => _logController.stream;

  Future<void> init() async {
    _validators.clear();
    _transformers.clear();

    _validators.addAll(<ArticleValidator>[
      _validateRequiredFields,
      _validateTitleLength,
      _validateContentLength,
      _validateSourceUrl,
      _validateImageUrl,
    ]);

    _transformers.addAll(<ArticleTransformer>[
      _normalizeTextFields,
      _enrichWithSourceInfo,
      _applyLanguageDefaults,
    ]);
  }

  Future<List<NewsSource>> fetchSources({
    String? countryCode,
    String? language,
    bool preferServer = true,
  }) async {
    final List<NewsSource> sources = [];

    if (preferServer) {
      try {
        final apiSources =
            await ServerApiService.getSourcesByCountryAndLanguage(
              countryCode: countryCode,
              language: language,
            );
        if (apiSources.isNotEmpty) {
          sources.addAll(
            apiSources
                .map(
                  (s) => NewsSource.fromMap(<String, dynamic>{
                    ...s,
                    'country_code': s['countryCode'] ?? s['country_code'] ?? '',
                    'language': (s['language'] is List)
                        ? (s['language'] as List).join(',')
                        : (s['language'] ?? 'ar').toString(),
                  }),
                )
                .toList(),
          );
        }
      } catch (_) {
        if (kDebugMode)
          _log('[CRAWLER] Server sources unavailable, using local fallback');
      }
    }

    if (sources.isEmpty) {
      final localSources = await _loadLocalSources(
        countryCode: countryCode,
        language: language,
      );
      sources.addAll(localSources);
    }

    _deduplicateSources(sources);
    sources.sort((a, b) => a.rank.compareTo(b.rank));
    return sources;
  }

  Future<List<String>> extractCandidateArticleUrls(NewsSource source) async {
    final List<String> rawUrls = [];

    try {
      final localDbJson = await _buildLocalDatabaseJson();
      final fetchResult = await _engine.processNewsUrl(
        source.url,
        localDbJson,
        silent: true,
      );

      if (fetchResult['success'] == true && fetchResult['is_source'] == true) {
        final List<dynamic> discovered = fetchResult['articles'] ?? <dynamic>[];
        rawUrls.addAll(discovered.map((u) => u.toString()).toList());
      }
    } catch (_) {
      if (kDebugMode)
        _log('[CRAWLER] Failed to extract URLs from ${source.name}');
    }

    return rawUrls;
  }

  List<String> normalizeAndCleanUris(List<String> rawUrls) {
    final Set<String> cleaned = <String>{};

    for (final raw in rawUrls) {
      final normalized = _normalizeArticleUrl(raw);
      if (normalized.isEmpty) continue;
      if (!NewsUriParser.isValidArticleUrl(normalized)) continue;
      cleaned.add(normalized);
    }

    return cleaned.toList()..sort((a, b) => a.compareTo(b));
  }

  Map<String, String> hashUris(List<String> urls) {
    final Map<String, String> urlToHash = <String, String>{};

    for (final url in urls) {
      final hash = _computeUrlHash(url);
      urlToHash[url] = hash;
    }

    return urlToHash;
  }

  Future<List<String>> filterDuplicates(
    List<String> urls,
    Set<String> knownHashes, {
    Set<String>? existingArticleHashes,
  }) async {
    final Set<String> duplicates = <String>{};
    duplicates.addAll(knownHashes);

    if (existingArticleHashes != null) {
      duplicates.addAll(existingArticleHashes);
    }

    return urls
        .where((url) => !duplicates.contains(_computeUrlHash(url)))
        .toList();
  }

  Future<List<NewsModel>> crawlArticles(
    List<String> urls,
    NewsSource source, {
    Duration delayBetweenRequests = const Duration(milliseconds: 250),
    int maxArticles = 20,
  }) async {
    if (_isCrawling) return <NewsModel>[];
    _isCrawling = true;

    final List<NewsModel> articles = <NewsModel>[];
    final Set<String> seenHashes = <String>{};

    try {
      final localDbJson = await _buildLocalDatabaseJson();

      for (final url in urls.take(maxArticles)) {
        if (!_isCrawling) break;

        final hash = _computeUrlHash(url);
        if (seenHashes.contains(hash)) continue;
        seenHashes.add(hash);

        try {
          final result = await _engine.processNewsUrl(
            url,
            localDbJson,
            silent: true,
          );

          if (result['success'] != true || result['is_source'] == true)
            continue;

          NewsModel article = NewsModel.fromJson(result, url);
          article = _applyPipeline(article, source);

          final validationErrors = _validateArticle(article);
          if (validationErrors.isNotEmpty) {
            if (kDebugMode) {
              _log('[CRAWLER] Skipped invalid article $url: $validationErrors');
            }
            continue;
          }

          articles.add(article);
        } catch (_) {
          if (kDebugMode) _log('[CRAWLER] Failed to crawl $url');
        }

        await Future.delayed(delayBetweenRequests);
      }
    } finally {
      _isCrawling = false;
    }

    return articles;
  }

  Future<List<NewsModel>> deduplicateArticles(List<NewsModel> articles) async {
    if (articles.isEmpty) return <NewsModel>[];

    final Map<String, NewsModel> bestByHash = <String, NewsModel>{};
    final Map<String, List<NewsModel>> similarityClusters =
        <String, List<NewsModel>>{};

    for (final article in articles) {
      final hash = article.urlHash;
      if (hash.isEmpty) continue;

      if (!bestByHash.containsKey(hash)) {
        bestByHash[hash] = article;
        continue;
      }

      final existing = bestByHash[hash]!;
      final existingScore = _articleQualityScore(existing);
      final candidateScore = _articleQualityScore(article);

      if (candidateScore > existingScore) {
        bestByHash[hash] = article;
      }
    }

    final List<NewsModel> deduped = bestByHash.values.toList();

    for (int i = 0; i < deduped.length; i++) {
      for (int j = i + 1; j < deduped.length; j++) {
        final similarity = _titleSimilarity(deduped[i], deduped[j]);
        if (similarity >= 0.75) {
          final key = deduped[i].urlHash;
          similarityClusters.putIfAbsent(key, () => <NewsModel>[]).addAll(
            <NewsModel>[deduped[i], deduped[j]],
          );
          break;
        }
      }
    }

    final Set<String> removeUrls = <String>{};
    for (final cluster in similarityClusters.values) {
      if (cluster.length <= 1) continue;
      cluster.sort(
        (a, b) => _articleQualityScore(b).compareTo(_articleQualityScore(a)),
      );
      removeUrls.addAll(cluster.skip(1).map((a) => a.url));
    }

    return deduped.where((a) => !removeUrls.contains(a.url)).toList();
  }

  Future<bool> pushArticlesToServer(List<NewsModel> articles) async {
    if (articles.isEmpty) return false;

    int succeeded = 0;
    for (final article in articles) {
      try {
        await ServerApiService.saveArticle(article);
        succeeded++;
      } catch (_) {
        if (kDebugMode)
          _log('[CRAWLER] Failed to push article: ${article.url}');
      }
    }

    _log('[CRAWLER] Pushed $succeeded/${articles.length} articles to server');
    return succeeded == articles.length;
  }

  Future<Map<String, dynamic>> runCrawlCycle({
    String? countryCode,
    String? language,
    int maxSources = 10,
    int maxArticlesPerSource = 10,
    bool autoPush = true,
  }) async {
    await init();

    final Map<String, dynamic> report = <String, dynamic>{
      'startedAt': DateTime.now().toIso8601String(),
      'countryCode': countryCode,
      'language': language,
      'sources': <String>[],
      'articlesConsidered': 0,
      'articlesPushed': 0,
      'duplicatesSkipped': 0,
      'invalidSkipped': 0,
      'errors': <String>[],
    };

    try {
      final sources = await fetchSources(
        countryCode: countryCode,
        language: language,
      );
      final limitedSources = sources.take(maxSources).toList();
      report['sources'] = limitedSources.map((s) => s.name).toList();

      final Set<String> globalKnownHashes = await _loadKnownArticleHashes();

      for (final source in limitedSources) {
        try {
          _log('[CRAWLER] Crawling source: ${source.name} (${source.url})');

          final rawUrls = await extractCandidateArticleUrls(source);
          final cleanedUrls = normalizeAndCleanUris(rawUrls);
          final urlHashes = hashUris(cleanedUrls);

          final newUrls = await filterDuplicates(
            cleanedUrls,
            globalKnownHashes,
            existingArticleHashes: urlHashes.values.toSet(),
          );

          if (newUrls.isEmpty) {
            _log('[CRAWLER] No new articles for ${source.name}');
            continue;
          }

          final candidates = await crawlArticles(
            newUrls,
            source,
            maxArticles: maxArticlesPerSource,
          );

          final deduped = await deduplicateArticles(candidates);

          for (final article in deduped) {
            globalKnownHashes.add(article.urlHash);
          }

          report['articlesConsidered'] =
              (report['articlesConsidered'] as int) + candidates.length;
          report['duplicatesSkipped'] =
              (report['duplicatesSkipped'] as int) +
              (candidates.length - deduped.length);

          if (deduped.isEmpty) continue;

          if (autoPush) {
            final pushed = await pushArticlesToServer(deduped);
            if (pushed) {
              report['articlesPushed'] =
                  (report['articlesPushed'] as int) + deduped.length;
            } else {
              (report['errors'] as List<String>).add(
                'Push failed for ${source.name}',
              );
            }
          }
        } catch (e) {
          (report['errors'] as List<String>).add('${source.name}: $e');
          if (kDebugMode) _log('[CRAWLER] Source crawl failed: $e');
        }
      }
    } catch (e) {
      (report['errors'] as List<String>).add('Global: $e');
    }

    report['finishedAt'] = DateTime.now().toIso8601String();
    report['success'] = (report['errors'] as List<String>).isEmpty;
    return report;
  }

  NewsModel _applyPipeline(NewsModel article, NewsSource source) {
    NewsModel current = article;

    for (final transform in _transformers) {
      current = transform(current);
    }

    return current.copyWith(
      category: current.category.isEmpty ? source.category : current.category,
    );
  }

  List<String> _validateArticle(NewsModel article) {
    final List<String> errors = <String>[];

    for (final validator in _validators) {
      if (!validator(article)) {
        errors.add(validator.toString());
      }
    }

    return errors;
  }

  bool _validateRequiredFields(NewsModel article) {
    return article.title.isNotEmpty &&
        article.url.isNotEmpty &&
        article.summary.isNotEmpty;
  }

  bool _validateTitleLength(NewsModel article) {
    final words = article.title
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    return words.length >= 3;
  }

  bool _validateContentLength(NewsModel article) {
    final content = article.content.isNotEmpty
        ? article.content
        : article.summary;
    return content.trim().length >= 40;
  }

  bool _validateSourceUrl(NewsModel article) {
    try {
      final uri = Uri.parse(article.url);
      return uri.hasScheme && uri.host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool _validateImageUrl(NewsModel article) {
    if (article.imageUrl.isEmpty) return true;
    return Uri.tryParse(article.imageUrl)?.hasAbsolutePath ?? false;
  }

  NewsModel _normalizeTextFields(NewsModel article) {
    return article.copyWith(
      title: article.title.trim().replaceAll(RegExp(r'\s+'), ' '),
      summary: article.summary.trim().replaceAll(RegExp(r'\s+'), ' '),
      content: article.content.trim().replaceAll(RegExp(r'\s+'), ' '),
    );
  }

  NewsModel _enrichWithSourceInfo(NewsModel article) {
    final domain = NewsModel.extractDomain(article.url);
    return article.copyWith(
      author: article.author.isEmpty
          ? NewsModel.domainToName(domain)
          : article.author,
    );
  }

  NewsModel _applyLanguageDefaults(NewsModel article) {
    final text = '${article.title} ${article.summary} ${article.content}';
    final detected = _detectLanguage(text);
    final language = detected.isEmpty ? 'ar' : detected;

    return article.copyWith(
      structuredData: Map<String, dynamic>.from(article.structuredData)
        ..['language'] = language,
    );
  }

  String _detectLanguage(String text) {
    if (text.isEmpty) return 'ar';
    final arabicChars = RegExp(r'[\u0600-\u06FF]').allMatches(text).length;
    final latinChars = RegExp(r'[A-Za-z]').allMatches(text).length;
    return arabicChars >= latinChars ? 'ar' : 'en';
  }

  double _articleQualityScore(NewsModel article) {
    double score = 0.0;

    final titleWords = article.title
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    if (titleWords >= 8)
      score += 2.0;
    else if (titleWords >= 5)
      score += 1.0;

    final contentLength = article.content.length;
    if (contentLength >= 600)
      score += 3.0;
    else if (contentLength >= 300)
      score += 2.0;
    else if (contentLength >= 100)
      score += 1.0;

    if (article.summary.length >= 80) score += 1.0;

    if (article.imageUrl.isNotEmpty &&
        !article.imageUrl.contains('placehold.co')) {
      score += 1.0;
    }

    final hasDate = article.publishDate.isNotEmpty;
    if (hasDate) score += 0.5;

    return score;
  }

  double _titleSimilarity(NewsModel a, NewsModel b) {
    final wordsA = a.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toSet();
    final wordsB = b.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toSet();

    if (wordsA.isEmpty || wordsB.isEmpty) return 0.0;
    return wordsA.intersection(wordsB).length / wordsA.union(wordsB).length;
  }

  Future<String> _buildLocalDatabaseJson() async {
    try {
      final List<NewsSource> sources = await _loadLocalSources();
      return jsonEncode(
        sources
            .map(
              (s) => <String, dynamic>{
                'url': s.url,
                'category': s.category,
                'name': s.name,
              },
            )
            .toList(),
      );
    } catch (_) {
      return '[]';
    }
  }

  Future<List<NewsSource>> _loadLocalSources({
    String? countryCode,
    String? language,
  }) async {
    try {
      final String jsonStr = await rootBundle.loadString(
        'assets/news_sources_ar.json',
      );

      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final List<dynamic> countries = data['countries'] ?? <dynamic>[];
      final List<NewsSource> sources = <NewsSource>[];

      for (final country in countries) {
        final String countryName = '${country['country'] ?? ''}';
        final String countryCodeValue = '${country['country_code'] ?? ''}';
        final List<dynamic> countrySources = country['sources'] ?? <dynamic>[];

        if (countryCode != null && countryCodeValue != countryCode) continue;

        for (final src in countrySources) {
          final srcLang = src['language'];
          final String sourceLanguage = srcLang is List
              ? srcLang.join(',')
              : '${srcLang ?? 'ar'}';

          if (language != null &&
              language.isNotEmpty &&
              !sourceLanguage.contains(language)) {
            continue;
          }

          sources.add(
            NewsSource.fromMap(<String, dynamic>{
              'id': '${src['name'] ?? src['url']}',
              'country': countryName,
              'country_code': countryCodeValue,
              'name': '${src['name'] ?? ''}',
              'url': '${src['url'] ?? ''}',
              'category': '${src['category'] ?? 'general_news'}',
              'type': '${src['type'] ?? 'digital_news'}',
              'language': sourceLanguage,
              'rank': src['rank'] is int
                  ? (src['rank'] as int)
                  : int.tryParse('${src['rank'] ?? 0}') ?? 0,
            }),
          );
        }
      }

      return sources;
    } catch (e) {
      if (kDebugMode) {
        _log('[CRAWLER] Failed to load local sources: $e');
      }
      return <NewsSource>[];
    }
  }

  Future<Set<String>> _loadKnownArticleHashes() async {
    final Set<String> hashes = <String>{};
    try {
      final articles = await ServerApiService.getNews(limit: 200);
      for (final a in articles) {
        final hash = a.urlHash.isNotEmpty
            ? a.urlHash
            : NewsModel.hashUrl(a.url);
        hashes.add(hash);
      }
    } catch (_) {
      if (kDebugMode)
        _log('[CRAWLER] Could not load known article hashes from server');
    }
    return hashes;
  }

  String _normalizeArticleUrl(String url) {
    String normalized = url.trim();

    try {
      final uri = Uri.parse(normalized);
      final host = uri.host.toLowerCase().replaceAll('www.', '');

      final path = uri.path;
      final cleanPath = path
          .split('/')
          .where((segment) => segment.isNotEmpty)
          .map((segment) => Uri.decodeComponent(segment))
          .join('/');

      final queryParams = uri.queryParameters;
      final allowedParams = <String>[];
      for (final key in queryParams.keys) {
        final lower = key.toLowerCase();
        if (lower == 'id' ||
            lower == 'p' ||
            lower == 'page' ||
            lower.startsWith('utm_') == false) {
          allowedParams.add(
            '$key=${Uri.encodeQueryComponent(queryParams[key]!)}',
          );
        }
      }

      normalized = '${uri.scheme}://$host/$cleanPath';
      if (allowedParams.isNotEmpty) {
        normalized += '?${allowedParams.join('&')}';
      }
    } catch (_) {
      normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');
    }

    return normalized;
  }

  String _computeUrlHash(String url) {
    return NewsModel.hashUrl(url);
  }

  void _deduplicateSources(List<NewsSource> sources) {
    final Set<String> seenUrls = <String>{};
    sources.removeWhere((source) {
      final normalized = source.url.trim().toLowerCase();
      if (seenUrls.contains(normalized)) return true;
      seenUrls.add(normalized);
      return false;
    });
  }

  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final formatted = '[$timestamp] $message';
    _logController.add(formatted);
    if (kDebugMode) print(formatted);
  }

  Map<String, dynamic> getStatus() {
    return {
      'isCrawling': _isCrawling,
      'validatorsCount': _validators.length,
      'transformersCount': _transformers.length,
    };
  }

  Future<void> dispose() async {
    await _logController.close();
  }
}
