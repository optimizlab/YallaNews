import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';
import '../database/news_db.dart';
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import '../services/app_settings.dart';
import '../services/yalla_engine_service.dart';
import '../services/background_crawler_service.dart';
import '../services/server_api_service.dart';
import '../services/auth_service.dart';
import '../services/category_service.dart';
import '../services/connectivity_service.dart';
import '../services/device_benchmark.dart';
import '../services/news_api_service.dart';
import '../services/ollama_service.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/custom_logo.dart';
import '../widgets/banner_ad.dart';
import '../widgets/cached_news_image.dart';
import '../widgets/fact_check_widget.dart';
import 'news_detail_page.dart';
import 'explore_page.dart';
import 'bookmarks_page.dart';
import 'settings_page.dart';
import 'daily_briefing_page.dart';
import 'personalized_feed_page.dart';
import 'auth/login_page.dart';
import 'about_us_page.dart';
import 'contact_page.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/top_news_carousel.dart';
import '../services/news_blender_service.dart';

String _getSentimentLabel(double sentiment, AppLocalizations l10n) {
  if (sentiment >= 0.3) return l10n.translate('positive');
  if (sentiment <= -0.3) return l10n.translate('negative');
  return l10n.translate('neutral');
}

bool _isValidArticle(NewsModel article) {
  final title = article.title.trim();
  final url = article.url.trim();
  final content = article.content.trim();

  if (title.isEmpty) {
    debugPrint('[HOME VALIDATION] Rejected: empty title/image');
    return false;
  }
  if (url.isEmpty || url.length < 10) {
    debugPrint('[HOME VALIDATION] Rejected: bad url');
    return false;
  }
  if (content.isEmpty || content.length < 50) {
    debugPrint('[HOME VALIDATION] Rejected: short content');
    return false;
  }

  final adPatterns = <String>[
    'livejournal.com',
    't.co',
    'bit.ly',
    'ad.',
    'advert',
    'banner',
    'sponsor',
    'promotion',
    'shop.',
    'store.',
    'buy now',
    'اشترِ',
    'تسوق',
  ];
  final lowerUrl = url.toLowerCase();
  final bool hasAdPattern = adPatterns.any((p) => lowerUrl.contains(p));
  if (hasAdPattern) {
    debugPrint('[HOME VALIDATION] Rejected: ad pattern | url=$url');
    return false;
  }

  final sectionPatterns = <String>[
    'التصنيف:',
    'التصنيف :',
    'التواصل الاجتماعي',
    'الأكثر قراءة',
    'مقالات ذات صلة',
    'التعليقات',
    'الاسم',
    'البريد الإلكتروني',
    'الموقع الإلكتروني',
    'ترك تعليق',
    'إرسال تعليق',
    'أضف تعليق',
    'شارك المقال',
    'شارك على',
    'تابعنا على',
    'حقوق النشر',
    'جميع الحقوق',
    'طباعة البريد',
    'الالكتروني',
    'اشترك في',
    'للمزيد من الأخبار',
    'latest news',
    'breaking news',
    'top news',
    'all news',
    'all articles',
  ];
  if (sectionPatterns.any((p) => title.contains(p))) {
    debugPrint('[HOME VALIDATION] Rejected: section pattern in title');
    return false;
  }

  final uri = Uri.tryParse(url);
  if (uri != null) {
    final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (pathSegments.length <= 1) {
      debugPrint('[HOME VALIDATION] Rejected: short path');
      return false;
    }
    final lastSegment = pathSegments.last.toLowerCase();
    if (lastSegment.length < 6 && !RegExp(r'^\d+$').hasMatch(lastSegment)) {
      debugPrint('[HOME VALIDATION] Rejected: short last segment');
      return false;
    }
  }

  final titleWords = title
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 2)
      .toList();
  if (titleWords.length < 2) {
    debugPrint('[HOME VALIDATION] Rejected: too few title words');
    return false;
  }

  return true;
}

class HomePage extends StatefulWidget {
  final YallaEngineService engineService;

  const HomePage({super.key, required this.engineService});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<NewsModel> _rawArticles = [];
  List<NewsModel> _articles = [];
  List<NewsModel> _allArticles = [];
  List<Map<String, dynamic>> _categories = [];
  List<String> _trendingSearches = [];
  String _searchQuery = '';
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isSearchActive = false;
  String _selectedCategory = 'all';
  bool _waitingForInitialCrawl = false;
  Locale? _lastLocale;
  int _dataLoadGeneration = 0;
  int _languageReloadGeneration = 0;
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  StreamSubscription<NewsModel>? _articleSubscription;
  final ScrollController _scrollController = ScrollController();
  final List<NewsModel> _pendingArticles = [];
  Timer? _crawlerFlushTimer;
  Timer? _crawlerBlendTimer;
  Timer? _searchDebounce;
  List<NewsModel> _cachedSearchResults = const [];
  String _lastSearchQuery = '';
  int? _lastFeedHash;
  List<List<Widget>> _feedRows = [];

  @override
  void initState() {
    super.initState();
    CategoryService.instance.addListener(_onCategoriesChanged);
    AppSettings.instance.addListener(_onSettingsChanged);
    AuthService.instance.addListener(_onAuthChanged);
    _lastLocale = AppSettings.instance.locale;
    _loadData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _articleSubscription?.cancel();
    _crawlerFlushTimer?.cancel();
    _crawlerBlendTimer?.cancel();
    _searchDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    CategoryService.instance.removeListener(_onCategoriesChanged);
    AppSettings.instance.removeListener(_onSettingsChanged);
    AuthService.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onCategoriesChanged() {
    if (mounted) {
      setState(() {
        _categories = CategoryService.instance.categories;
      });
    }
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    final currentLocale = AppSettings.instance.locale;
    if (_lastLocale == null ||
        currentLocale?.languageCode != _lastLocale?.languageCode) {
      _lastLocale = currentLocale;
      _dataLoadGeneration++;
      final reloadGeneration = ++_languageReloadGeneration;
      debugPrint(
        '[HOME] Language changed to ${currentLocale?.languageCode}, reloading news',
      );
      unawaited(_reloadForLanguageChange(reloadGeneration));
    }
  }

  Future<void> _reloadForLanguageChange(int reloadGeneration) async {
    await CrawlerScheduler.instance.stop();
    await BackgroundCrawlerService.instance.stop();
    if (!mounted || reloadGeneration != _languageReloadGeneration) return;

    // Reload categories from the server so their names match the
    // newly selected language before we reload the news feed.
    await CategoryService.instance.loadCategories(forceRefresh: true);
    if (!mounted || reloadGeneration != _languageReloadGeneration) return;

    _articleSubscription?.cancel();
    _crawlerFlushTimer?.cancel();
    _crawlerBlendTimer?.cancel();
    _pendingArticles.clear();
    setState(() {
      _isLoading = true;
      _rawArticles = [];
      _allArticles = [];
      _articles = [];
      _selectedCategory = 'all';
      _trendingSearches = [];
    });

    await _loadData(skipCachedArticles: true);
  }

  Future<void> _applyBlendedArticles(List<NewsModel> rawList) async {
    if (!mounted) return;
    final compliantArticles = _filterPolicyCompliantArticles(rawList);

    setState(() {
      _rawArticles = compliantArticles;
      _allArticles = compliantArticles;
      _articles = compliantArticles;
    });

    unawaited(_updateCategoryCountsAsync(compliantArticles));
    unawaited(_ensureArticleImages(compliantArticles));
  }

  /// Fetches a main image for every article that lacks one, using MSN/Bing
  /// image search on the article title + category. Updates state as each
  /// image is resolved so the feed never shows an article without an image.
  Future<void> _ensureArticleImages(List<NewsModel> articles) async {
    final needImage = articles.where((a) => a.imageUrl.isEmpty).toList();
    if (needImage.isEmpty) return;
    final updates = <int, NewsModel>{};
    for (final a in needImage) {
      if (!mounted) return;
      final updated = await NewsModel.ensureImage(a);
      if (updated.imageUrl == a.imageUrl) continue;
      final idx = _articles.indexWhere((x) => x.url == a.url);
      if (idx >= 0) updates[idx] = updated;
      final allIdx = _allArticles.indexWhere((x) => x.url == a.url);
      if (allIdx >= 0) {
        _allArticles[allIdx] = updated;
      }
      final rawIdx = _rawArticles.indexWhere((x) => x.url == a.url);
      if (rawIdx >= 0) {
        _rawArticles[rawIdx] = updated;
      }
    }
    if (updates.isNotEmpty && mounted) {
      setState(() {
        updates.forEach((idx, updated) {
          _articles[idx] = updated;
        });
      });
    }
  }

  /// News and Magazines policy requires current content and clear publisher
  /// attribution. Articles without either are not shown in the feed.
  List<NewsModel> _filterPolicyCompliantArticles(Iterable<NewsModel> articles) {
    final selectedLanguage = AppSettings.instance.locale?.languageCode;
    return articles.where((article) {
      final hasPublisher =
          article.sourceName.trim().isNotEmpty ||
          article.displaySourceName.trim().isNotEmpty ||
          article.authorName.trim().isNotEmpty ||
          article.author.trim().isNotEmpty;
      final languageMatches =
          article.language.isEmpty ||
          selectedLanguage == null ||
          article.language.toLowerCase() == selectedLanguage.toLowerCase();
      // The server may legitimately have no original publication timestamp.
      // Keep such articles visible; only reject a known, genuinely stale date.
      return hasPublisher &&
          languageMatches &&
          (article.publicationDate == null || article.isWithinMonths(3));
    }).toList();
  }

  void _flushPendingArticles() {
    if (_pendingArticles.isEmpty) return;
    final batch = List<NewsModel>.from(_pendingArticles);
    _pendingArticles.clear();
    if (!mounted) return;
    setState(() {
      for (final article in batch) {
        if (_filterPolicyCompliantArticles([article]).isEmpty) continue;
        final existingIndex = _rawArticles.indexWhere(
          (a) => a.url == article.url,
        );
        if (existingIndex >= 0) {
          _rawArticles[existingIndex] = article;
        } else {
          _rawArticles.insert(0, article);
        }
      }
    });
    _applyBlendedArticles(_rawArticles);
    widget.engineService.addLog(
      '[HOME] Flushed ${batch.length} articles, total: ${_rawArticles.length}',
    );
    if (_waitingForInitialCrawl) {
      _waitingForInitialCrawl = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _updateCategoryCountsAsync(List<NewsModel> articles) async {
    try {
      final updatedCategories = await compute(
        _updateCategoryCountsIsolate,
        articles.map((a) => a.toJson()).toList(),
      );
      if (mounted) {
        setState(() {
          _categoryCounts.clear();
          for (final category in updatedCategories) {
            final id = category['id']?.toString() ?? '';
            _categoryCounts[id] = category['newsCount'] ?? 0;
          }
        });
      }
    } catch (_) {}
  }

  final Map<String, int> _categoryCounts = {};
  final int _blendedCount = 0;

  static List<Map<String, dynamic>> _updateCategoryCountsIsolate(
    List<Map<String, dynamic>> articlesJson,
  ) {
    final articles = articlesJson
        .map((json) => NewsModel.fromJson(json, json['url'] as String))
        .toList();
    final categories = CategoryService.instance.categories;

    for (final category in categories) {
      final id = category['id']?.toString() ?? '';
      final name = category['name']?.toString() ?? id;
      int count = 0;
      for (final article in articles) {
        if (CategoryService.matchesCategory(article.category, id) ||
            CategoryService.matchesCategory(article.category, name)) {
          count++;
        }
      }
      category['newsCount'] = count;
    }

    return categories;
  }

  Future<void> _blendInBackground(List<NewsModel> rawList) async {
    try {
      final blended = await NewsBlenderService.instance.blendArticlesAsync(
        rawList,
      );
      if (!mounted) return;
      setState(() {
        _allArticles = blended;
        if (_selectedCategory == 'all') {
          _articles = List.from(blended);
        } else if (_selectedCategory == 'blended') {
          _articles = blended.where((a) => a.isBlended).toList();
        } else {
          _articles = blended
              .where((a) => _matchesCategory(a.category, _selectedCategory))
              .toList();
        }
      });
      await _updateCategoryCountsAsync(blended);
    } catch (_) {}
  }

  Future<void> _loadData({bool skipCachedArticles = false}) async {
    final loadGeneration = ++_dataLoadGeneration;
    debugPrint('[HOME] _loadData started');
    _waitingForInitialCrawl = false;
    _currentPage = 1;
    _hasMore = true;

    try {
      // Clean up invalid articles from DB on startup
      final db = NewsDatabase.instance;
      final removedCount = await db.removeInvalidArticles();
      if (removedCount > 0) {
        debugPrint('[HOME] Removed $removedCount invalid articles from DB');
      }

      final locale = AppSettings.instance.locale;
      final language = locale?.languageCode;

      // ─── 1. Load from our server API first ───
      List<NewsModel> serverArticles = <NewsModel>[];
      try {
        serverArticles = await ServerApiService.getNews(
          limit: 20,
          page: 1,
          language: language,
        ).timeout(const Duration(seconds: 20));
        debugPrint('[HOME] Server returned ${serverArticles.length} articles');
      } catch (e) {
        debugPrint('[HOME] Server API load failed: $e');
      }
      if (loadGeneration != _dataLoadGeneration) return;

      // Stored news always updates when we find responses from the server API.
      List<NewsModel> rawList;
      if (serverArticles.isNotEmpty) {
        final validServer = _filterPolicyCompliantArticles(serverArticles);
        // Persist server articles to local DB so the cache stays fresh.
        await _saveArticlesToLocalDb(validServer);
        rawList = validServer;
      } else if (!skipCachedArticles) {
        // Fall back to stored local DB when the server has no news.
        final articleCount = await db.getArticleCount();
        if (loadGeneration != _dataLoadGeneration) return;
        if (articleCount > 0 && mounted) {
          final cachedArticles = await db.getAllArticles(
            limit: 100,
            language: language,
          );
          if (loadGeneration != _dataLoadGeneration) return;
          final validCached = _filterPolicyCompliantArticles(
            cachedArticles.where(_isValidArticle),
          );
          rawList = validCached;
          debugPrint('[HOME] Loaded ${validCached.length} articles from local cache');
        } else {
          rawList = <NewsModel>[];
        }
      } else {
        rawList = <NewsModel>[];
      }

      // ─── 2. Merge NewsAPI.org headlines (real-world sources) ───
      final newsApiArticles = await _fetchNewsApiArticles();
      if (newsApiArticles.isNotEmpty) {
        final existingUrls = rawList.map((a) => a.url).toSet();
        final freshNewsApi =
            newsApiArticles.where((a) => !existingUrls.contains(a.url)).toList();
        widget.engineService.addLog(
          '[NEWSAPI] Merge: ${newsApiArticles.length} fetched, ${freshNewsApi.length} new (${existingUrls.length} already present)',
        );
        rawList.addAll(freshNewsApi);
      } else {
        widget.engineService.addLog('[NEWSAPI] Merge: 0 articles fetched');
      }

      // ─── 3. Filter policy-compliant ───
      rawList = _filterPolicyCompliantArticles(rawList);

      // ─── 4. Validate + LLM regenerate (Ollama where available) ───
      final validatedArticles = await _validateAndRegenerateArticles(rawList);

      // ─── 5. Blend + LLM synthesize across sources ───
      final blendedArticles = await NewsBlenderService.instance.blendArticlesAsync(
        validatedArticles,
      );

      // ─── 6. Push new/blended articles to our server ───
      await _pushArticlesToApi(blendedArticles);

      // ─── 7. Trending ───
      List<NewsModel> trending = <NewsModel>[];
      try {
        trending = await ServerApiService.getTrending(
          limit: 10,
          language: language ?? 'ar',
        ).timeout(const Duration(seconds: 10));
      } catch (_) {
        trending = <NewsModel>[];
      }
      if (loadGeneration != _dataLoadGeneration) return;

      debugPrint(
        '[HOME] Loaded ${rawList.length} articles (blended: ${blendedArticles.length})',
      );

      // Show articles immediately
      if (mounted && blendedArticles.isNotEmpty) {
        _rawArticles = blendedArticles;
        _allArticles = List.from(blendedArticles);
        _articles = List.from(blendedArticles);
        setState(() {
          _selectedCategory = 'all';
          _categories = CategoryService.instance.categories;
          _trendingSearches = trending
              .map((t) => t.title)
              .where((q) => q.isNotEmpty)
              .toList();
          _isLoading = false;
        });
        _applyBlendedArticles(blendedArticles);
        CategoryService.instance.updateCategoryCounts(blendedArticles);
      } else if (mounted && _rawArticles.isEmpty) {
        setState(() {
          _isLoading = false;
          _selectedCategory = 'all';
          _categories = CategoryService.instance.categories;
        });
      }

      // ─── 8. Crawler: WiFi-based smart trigger ───
      if (!kIsWeb) {
        unawaited(
          _setupLocalDbAndCrawler(
            blendedArticles,
            trending,
            loadGeneration: loadGeneration,
            allowCachedFallback: !skipCachedArticles,
          ),
        );
      }
    } catch (e) {
      debugPrint('[HOME] _loadData failed: $e');
      if (mounted && _rawArticles.isEmpty) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Persists [articles] received from our server API into the local DB so the
  /// stored cache always stays fresh when the server returns news.
  Future<void> _saveArticlesToLocalDb(List<NewsModel> articles) async {
    if (articles.isEmpty) return;
    try {
      await NewsDatabase.instance.saveCrawledArticles(articles, '');
    } catch (e) {
      debugPrint('[HOME] Failed to save server articles to local DB: $e');
    }
  }

  /// Validates and regenerates article content using the local LLM (Ollama)
  /// when available. Keeps articles unchanged when no LLM is reachable so the
  /// feed never stalls waiting for regeneration.
  Future<List<NewsModel>> _validateAndRegenerateArticles(
    List<NewsModel> articles,
  ) async {
    if (articles.isEmpty) return const [];
    final ollama = OllamaService.instance;
    final available = await ollama.isOllamaAvailable();
    if (!available) return articles;

    final result = <NewsModel>[];
    for (final a in articles) {
      try {
        final cleaned = await ollama.cleanNewsContent(a.title, a.content);
        if (cleaned != null && cleaned.isNotEmpty) {
          result.add(a.copyWith(content: cleaned, summary: cleaned));
        } else {
          result.add(a);
        }
      } catch (_) {
        result.add(a);
      }
    }
    return result;
  }

  Future<void> _pushArticlesToApi(List<NewsModel> articles) async {
    try {
      final uploadable = articles
          .where((article) => article.language.trim().isNotEmpty)
          .toList();
      if (uploadable.length != articles.length) {
        debugPrint(
          '[HOME] Skipped ${articles.length - uploadable.length} cached articles without a known language',
        );
      }

      // Validate + LLM regenerate each article before saving to our server.
      final cleaned = await _validateAndRegenerateArticles(uploadable);

      int pushed = 0;
      for (final article in cleaned) {
        try {
          await ServerApiService.saveArticle(
            article,
          ).timeout(const Duration(seconds: 8));
          pushed++;
        } catch (e) {
          debugPrint('[HOME] Push failed: ${article.url} | $e');
        }
        await Future.delayed(const Duration(milliseconds: 200));
      }
      debugPrint('[HOME] Pushed $pushed/${cleaned.length} articles to API');
    } catch (_) {}
  }

  Future<void> _setupLocalDbAndCrawler(
    List<NewsModel> rawList,
    List<NewsModel> trending, {
    required int loadGeneration,
    bool allowCachedFallback = true,
  }) async {
    try {
      final db = NewsDatabase.instance;
      final articleCount = await db.getArticleCount();
      if (loadGeneration != _dataLoadGeneration) return;
      final serverEmpty = rawList.isEmpty;

      final settings = await AppSettings.instance.getPrefs();
      if (loadGeneration != _dataLoadGeneration) return;
      final backgroundEnabled =
          settings.getBool('background_crawler_enabled') ?? true;

      if (backgroundEnabled) {
        debugPrint('[HOME] Listening to background crawler stream');
        widget.engineService.addLog(
          '[HOME] Listening to background crawler stream',
        );
        _articleSubscription?.cancel();
        _crawlerFlushTimer?.cancel();
        _crawlerBlendTimer?.cancel();
        _pendingArticles.clear();
        _articleSubscription = BackgroundCrawlerService.instance.articleStream.listen((
          article,
        ) {
          debugPrint(
            '[HOME STREAM] Received article: ${article.title.substring(0, min(60, article.title.length))}...',
          );
          widget.engineService.addLog(
            '[HOME STREAM] Received article: ${article.title.substring(0, min(60, article.title.length))}...',
          );
          if (!_isValidArticle(article) ||
              _filterPolicyCompliantArticles([article]).isEmpty) {
            debugPrint(
              '[HOME VALIDATION] Dropped invalid or non-compliant article: ${article.url}',
            );
            widget.engineService.addLog(
              '[HOME VALIDATION] Dropped invalid or non-compliant article: ${article.url}',
            );
            return;
          }
          _pendingArticles.add(article);
          if (_pendingArticles.length >= 20) {
            _flushPendingArticles();
          }
        });
        _crawlerFlushTimer = Timer.periodic(
          const Duration(milliseconds: 1200),
          (_) {
            if (_pendingArticles.isNotEmpty) {
              _flushPendingArticles();
            }
          },
        );
        _crawlerBlendTimer = Timer.periodic(const Duration(seconds: 3), (_) {
          if (_allArticles.isNotEmpty) {
            unawaited(_blendInBackground(_allArticles));
          }
        });

        // Start both the immediate crawl and adaptive scheduler only when
        // enabled in the user's saved preferences.
        unawaited(
          CrawlerScheduler.instance.start(
            engineService: widget.engineService,
            requireWifi: false,
            onComplete: () {
              if (mounted && _pendingArticles.isNotEmpty) {
                _flushPendingArticles();
              }
            },
          ),
        );
        // On Wi-Fi, crawl sources immediately so the server and the feed are
        // fed with the latest news instead of stale cached articles.
        unawaited(_refreshNewsNow());
        unawaited(
          BackgroundCrawlerService.instance.startSilentCrawl(
            engineService: widget.engineService,
            requireWifi: false,
            onComplete: () {
              if (mounted && _pendingArticles.isNotEmpty) {
                _flushPendingArticles();
              }
            },
          ),
        );
      } else {
        await _articleSubscription?.cancel();
        _articleSubscription = null;
        _crawlerFlushTimer?.cancel();
        _crawlerFlushTimer = null;
        _crawlerBlendTimer?.cancel();
        _crawlerBlendTimer = null;
        _pendingArticles.clear();
        await CrawlerScheduler.instance.stop();
        await BackgroundCrawlerService.instance.stop();
      }

      if (loadGeneration == _dataLoadGeneration &&
          allowCachedFallback &&
          serverEmpty &&
          articleCount > 0) {
        debugPrint(
          '[HOME] Server empty, loading $articleCount articles from local DB',
        );
        final localArticles = await db.getAllArticles(limit: 100, language: AppSettings.instance.locale?.languageCode);
        final validLocal = _filterPolicyCompliantArticles(
          localArticles.where(_isValidArticle),
        );
        debugPrint(
          '[HOME] Local fallback kept ${validLocal.length}/${localArticles.length} cached articles',
        );

        if (validLocal.isNotEmpty && mounted) {
          _rawArticles.addAll(validLocal);
          _allArticles = List.from(_rawArticles);
          _articles = List.from(_rawArticles);
          setState(() {});
          _applyBlendedArticles(_rawArticles);
        }

        unawaited(_pushArticlesToApi(validLocal));
      }
    } catch (_) {}
  }

  Future<List<NewsModel>> _loadArticles({int page = 1, int limit = 20}) async {
    try {
      debugPrint('[HOME] Loading articles from server API (page $page)...');
      final locale = AppSettings.instance.locale;
      final language = locale?.languageCode;
      if (language == null || language.isEmpty) return [];
      final serverArticles = await ServerApiService.getNews(
        limit: limit,
        page: page,
        language: language,
      ).timeout(const Duration(seconds: 20));
      debugPrint('[HOME] Server returned ${serverArticles.length} articles');
      return serverArticles;
    } catch (e) {
      debugPrint('[HOME] Failed to load articles: $e');
      return [];
    }
  }

  /// Fetches the latest headlines from NewsAPI.org and merges them into the
  /// feed alongside crawled/server articles. Requires a configured API key
  /// (set in Settings); returns an empty list when no key is configured or the
  /// request fails, so it never blocks the feed.
  Future<List<NewsModel>> _fetchNewsApiArticles() async {
    try {
      await NewsApiService.init();
      final key = NewsApiService.apiKey;
      widget.engineService.addLog('[NEWSAPI] init done; key=${key == null || key.isEmpty ? 'missing' : key.substring(0, 8)}...');
      if (key == null || key.isEmpty) {
        widget.engineService.addLog('[NEWSAPI] No API key configured — skipping NewsAPI fetch.');
        return <NewsModel>[];
      }
      final locale = AppSettings.instance.locale;
      final language = locale?.languageCode;
      widget.engineService.addLog(
        '[NEWSAPI] Fetching top-headlines language=$language pageSize=30',
      );
      final articles = await NewsApiService.fetchArticles(
        language: language ?? 'ar',
        pageSize: 30,
      ).timeout(const Duration(seconds: 15));
      final compliant = _filterPolicyCompliantArticles(articles);
      widget.engineService.addLog(
        '[NEWSAPI] Received ${articles.length} articles, ${compliant.length} passed policy filter',
      );
      return compliant;
    } catch (e) {
      widget.engineService.addLog('[NEWSAPI] Fetch failed: $e');
      debugPrint('[HOME] NewsAPI fetch failed: $e');
      return <NewsModel>[];
    }
  }

  /// Crawl news sources right now when the device is on Wi-Fi and push fresh
  /// articles to the local DB and the server so users always see the latest
  /// news instead of stale cached stories. Safe to call repeatedly; the
  /// crawler guards against concurrent runs and skips when not on Wi-Fi or on
  /// small-memory devices.
  Future<void> _refreshNewsNow() async {
    // NewsAPI headlines refresh on any connection — never Wi-Fi gated — so the
    // feed always gets the latest real-world news immediately.
    widget.engineService.addLog('[NEWSAPI] Refresh starting NewsAPI fetch');
    final newsApiArticles = await _fetchNewsApiArticles();
    if (newsApiArticles.isNotEmpty && mounted) {
      final existingUrls = _rawArticles.map((a) => a.url).toSet();
      final fresh = newsApiArticles.where((a) => !existingUrls.contains(a.url)).toList();
      widget.engineService.addLog(
        '[NEWSAPI] Refresh: ${newsApiArticles.length} fetched, ${fresh.length} new',
      );
      if (fresh.isNotEmpty) {
        setState(() {
          _rawArticles.insertAll(0, fresh);
          _allArticles = List.from(_rawArticles);
          _articles = List.from(_rawArticles);
        });
        unawaited(_applyBlendedArticles(_rawArticles));
      }
    } else {
      widget.engineService.addLog('[NEWSAPI] Refresh: 0 articles fetched');
    }

    final isWifi = await ConnectivityService.isWifi();
    if (!isWifi) return;

    // Crawl when we have no news, or when existing news is stale for the
    // current connection quality/speed. Otherwise skip (silent, no-op).
    final hasNews = _rawArticles.isNotEmpty;
    final newest = hasNews
        ? _rawArticles
            .map((a) => a.publicationDate ?? DateTime.now())
            .reduce((a, b) => a.isAfter(b) ? a : b)
        : null;

    if (!_isStale(newest)) return;

    await BackgroundCrawlerService.instance.forceRefresh(
      engineService: widget.engineService,
      onComplete: () {
        if (mounted && _pendingArticles.isNotEmpty) {
          _flushPendingArticles();
        }
      },
    );
  }

  /// True when the newest article is older than the freshness window derived
  /// from connection quality/speed (better connection → shorter window).
  bool _isStale(DateTime? newest) {
    if (newest == null) return true;
    final now = DateTime.now();
    final age = now.difference(newest);
    final benchmark = DeviceBenchmark.instance;
    final tier = benchmark.hasValidBenchmark
        ? benchmark.lastResult!.tier
        : DeviceTier.medium;
    final maxAge = switch (tier) {
      DeviceTier.high => const Duration(hours: 6),
      DeviceTier.medium => const Duration(hours: 12),
      DeviceTier.low => const Duration(hours: 24),
    };
    return age > maxAge;
  }

  void _onScroll() {
    if (!_isLoadingMore &&
        _hasMore &&
        !_isSearchActive &&
        _selectedCategory == 'all' &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      unawaited(_loadMoreArticles());
    }
  }

  Future<void> _loadMoreArticles() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final nextPage = _currentPage + 1;
      final more = await _loadArticles(page: nextPage, limit: 20);
      if (!mounted) return;
      if (more.isEmpty) {
        _hasMore = false;
      } else {
        _currentPage = nextPage;
        final newArticles = more.where(
          (a) => !_articles.any((e) => e.url == a.url),
        ).toList();
        setState(() {
          _articles.addAll(newArticles);
          _allArticles.addAll(newArticles);
          _rawArticles.addAll(newArticles);
        });
        CategoryService.instance.updateCategoryCounts(newArticles);
        unawaited(_blendInBackground(List.from(_articles)));
        unawaited(_ensureArticleImages(newArticles));
      }
    } catch (e) {
      debugPrint('[HOME] Load more failed: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _onRefresh() async {
    _currentPage = 1;
    _hasMore = true;
    if (mounted) setState(() => _isLoading = true);
    try {
      final rawRefreshed = _filterPolicyCompliantArticles(
        await _loadArticles(page: 1, limit: 20),
      );
      if (!mounted) return;
      _rawArticles = rawRefreshed;
      _allArticles = List.from(rawRefreshed);
      await _applyBlendedArticles(rawRefreshed);
      setState(() {
        _articles = _allArticles;
        _isLoading = false;
      });
      CategoryService.instance.updateCategoryCounts(rawRefreshed);
      // Refresh trending searches too
      try {
        final trending = await ServerApiService.getTrending(
          limit: 10,
          language: AppSettings.instance.locale?.languageCode ?? 'ar',
        ).timeout(const Duration(seconds: 10));
        setState(() {
          _trendingSearches = trending
              .map((t) => t.title)
              .where((q) => q.isNotEmpty)
              .toList();
        });
        // On Wi-Fi, also crawl sources immediately so the refreshed feed gets
        // the latest stories instead of only what the cached API returned.
        unawaited(_refreshNewsNow());
      } catch (_) {}
    } catch (e) {
      debugPrint('[HOME] _onRefresh failed: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _activateSearch() {
    setState(() => _isSearchActive = true);
  }

  void _deactivateSearch() {
    setState(() {
      _isSearchActive = false;
      _searchQuery = '';
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final q = value.trim();
      if (_lastSearchQuery == q) return;
      _lastSearchQuery = q;
      if (q.isEmpty) {
        _cachedSearchResults = const [];
      } else {
        final query = q.toLowerCase();
        _cachedSearchResults = _allArticles
            .where(
              (a) =>
                  a.title.toLowerCase().contains(query) ||
                  a.summary.toLowerCase().contains(query),
            )
            .toList();
      }
      setState(() {
        _searchQuery = value;
      });
    });
  }

  List<NewsModel> get _searchResults => _cachedSearchResults;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AdaptiveLayout(
      currentIndex: _currentIndex,
      onNavigationChanged: (i) => setState(() => _currentIndex = i),
      scrollController: _scrollController,
      destinations: [
        AdaptiveNavigationDestination(
          icon: Icons.home_rounded,
          label: l10n.translate('home'),
        ),
        AdaptiveNavigationDestination(
          icon: Icons.explore_rounded,
          label: l10n.translate('explore'),
        ),
        AdaptiveNavigationDestination(
          icon: Icons.newspaper_rounded,
          label: l10n.translate('dailyBriefing'),
        ),
        AdaptiveNavigationDestination(
          icon: Icons.bookmark_rounded,
          label: l10n.translate('bookmarks'),
        ),
        AdaptiveNavigationDestination(
          icon: Icons.person_rounded,
          label: l10n.translate('personalizedFeed'),
        ),
        AdaptiveNavigationDestination(
          icon: Icons.fact_check_rounded,
          label: l10n.translate('factCheck'),
        ),
        AdaptiveNavigationDestination(
          icon: Icons.settings_rounded,
          label: l10n.translate('settings'),
        ),
      ],
      scaffoldKey: _scaffoldKey,
      onRefresh: _onRefresh,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        leading: _isSearchActive
            ? IconButton(
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                onPressed: _deactivateSearch,
              )
            : IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
        title: _isSearchActive
            ? SizedBox(
                width: MediaQuery.of(context).size.width * 0.7,
                child: TextField(
                  autofocus: true,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: l10n.translate('searchHint'),
                    hintStyle: GoogleFonts.outfit(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                ),
              )
            : YallaNewsLogo(
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            iconSize: 24,
            onPressed: _activateSearch,
          ),
          AnimatedBuilder(
            animation: AuthService.instance,
            builder: (context, _) {
              final isLoggedIn = AuthService.instance.isLoggedIn;
              if (!isLoggedIn) {
                return IconButton(
                  icon: const Icon(Icons.person_add_rounded),
                  iconSize: 24,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  ),
                );
              }
              return IconButton(
                icon: CircleAvatar(
                  radius: 12,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    'U',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 12,
                    ),
                  ),
                ),
                iconSize: 24,
                onPressed: () async {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    showDragHandle: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    builder: (context) => SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.translate('profile'),
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  await AuthService.instance.logout();
                                  if (mounted) setState(() {});
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.error,
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.onError,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  l10n.translate('logout'),
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: _buildCurrentPage(),
    );
  }

  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case 0:
        return _buildHomeContent(context);
      case 1:
        return const ExplorePage();
      case 2:
        return const DailyBriefingPage();
      case 3:
        return const BookmarksPage();
      case 4:
        return const PersonalizedFeedPage(embedded: true);
      case 5:
        return FactCheckWidget(
          article: NewsModel(
            url: '',
            title: '',
            summary: '',
            content: '',
            imageUrl: '',
            category: 'general',
            sentiment: 0.0,
            keywords: [],
            logs: '',
            author: '',
            publishDate: '',
          ),
          autoCheck: true,
        );
      case 6:
        return const SettingsPage(embedded: true);
      default:
        return _buildHomeContent(context);
    }
  }

  /// Builds the feed rows with randomized banner ad placement and count.
  ///
  /// Ads use [BannerAdWidget] (real ad unit id `ca-app-pub-2951683509728611/4930663860`)
  /// and are inserted into random gaps between news items, styled to look like
  /// a news item (placement `banner_1`). The layout is cached per article set
  /// so ads don't jump around on every rebuild.
  List<List<Widget>> _buildFeedRows(List<NewsModel> articles, bool isWide) {
    final hash = articles.map((a) => a.url).join('\n').hashCode;
    if (_lastFeedHash == hash && _feedRows.isNotEmpty) {
      return _feedRows;
    }
    _lastFeedHash = hash;
    _feedRows = [];

    if (articles.isEmpty) return _feedRows;

    final random = Random(hash);
    final n = articles.length;

    // Randomized ad count: at least one banner ad when there are multiple news
    // items, up to roughly one ad per two news items, capped at 4. Placement
    // (which gaps) is also randomized, but an ad is never inserted before the
    // first 5 news items, and at least 4 news items separate any two ads.
    final validGapCount = (n - 5).clamp(0, n - 1);
    final maxAds = ((validGapCount + 4) / 5).floor().clamp(1, 4);
    final adCount = validGapCount <= 0
        ? 0
        : (1 + random.nextInt(maxAds)).clamp(1, validGapCount);

    // Eligible gaps are after at least 5 news items (index i >= 4).
    final eligibleGaps = List<int>.generate(
      validGapCount,
      (idx) => 4 + idx,
    )..shuffle(random);

    // Enforce min 4 news items between any two banner ads (gap difference >= 5).
    final adGaps = <int>{};
    for (final gap in eligibleGaps) {
      if (adGaps.length >= adCount) break;
      if (adGaps.any((g) => (gap - g).abs() < 5)) continue;
      adGaps.add(gap);
    }

    // Flat interleaved list of news cards and banner ads.
    final flat = <Widget>[];
    for (var i = 0; i < n; i++) {
      flat.add(_buildArticleCard(articles[i]));
      if (i < n - 1 && adGaps.contains(i)) {
        flat.add(const BannerAdWidget(placement: 'banner_1'));
      }
    }

    // Group into rows: banner ads render full-width, news cards pair up on wide
    // screens to preserve the existing two-column feed layout.
    var j = 0;
    while (j < flat.length) {
      final first = flat[j];
      if (first is BannerAdWidget) {
        _feedRows.add([first]);
        j++;
      } else if (isWide &&
          j + 1 < flat.length &&
          flat[j + 1] is! BannerAdWidget) {
        _feedRows.add([first, flat[j + 1]]);
        j += 2;
      } else {
        _feedRows.add([first]);
        j++;
      }
    }
    return _feedRows;
  }

  Widget _buildHomeContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_isLoading) {
      return const ShimmerLoadingList();
    }

    if (_isSearchActive) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ListView.builder(
          itemCount: _searchQuery.isEmpty ? 1 : _searchResults.length,
          itemBuilder: (context, index) {
            if (_searchQuery.isEmpty) {
              return _buildTrendingSearches(context);
            }
            return _buildArticleCard(_searchResults[index]);
          },
        ),
      );
    }

    if (_articles.isEmpty) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: max(
            0,
            MediaQuery.of(context).size.height -
                kToolbarHeight -
                MediaQuery.of(context).padding.top,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 180,
                width: 240,
                child: Lottie.asset(
                  'assets/animations/empty_news.json',
                  fit: BoxFit.contain,
                  repeat: true,
                  animate: true,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.newspaper_rounded,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.translate('noArticles'),
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.translate('autoLoadMessage'),
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  l10n.translate('refresh'),
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC62828),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                ),
                icon: const Icon(Icons.person_add_rounded, size: 18),
                label: Text(
                  l10n.translate('login'),
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 750;
        final topArticles = _sortCarouselArticles(_articles).take(9).toList();
        final remainingArticles = _articles.length > 3
            ? _articles.sublist(3)
            : _articles;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCategoryChips(context),
                const SizedBox(height: 10),
                if (_articles.isNotEmpty) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      TopNewsCarousel(
                        articles: topArticles,
                        onArticleTap: (article) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NewsDetailPage(article: article),
                            ),
                          );
                        },
                        getCategoryName: (cat) =>
                            _getCategoryName(cat, context),
                        getReadTime: (art) => _getReadTime(art, context),
                        getSourceName: (art) => _getSourceName(art),
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 18,
                              decoration: BoxDecoration(
                                color: const Color(0xFFC62828),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _selectedCategory == 'all'
                                  ? l10n.translate('all')
                                  : _getCategoryName(
                                      _selectedCategory,
                                      context,
                                    ),
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                  ..._buildFeedRows(remainingArticles, isWide).map((row) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: isWide && row.length == 2
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: row[0]),
                                const SizedBox(width: 14),
                                Expanded(child: row[1]),
                              ],
                            )
                          : row.first,
                    );
                  }),
                  if (_isLoadingMore)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            ),
                            SizedBox(height: 12),
                              Text(
                                l10n.translate('loadingMore'),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  bool _matchesCategory(String articleCat, String selectedCat) {
    return CategoryService.matchesCategory(articleCat, selectedCat);
  }

  /// Sorts articles for the carousel by a blend of recency and popularity
  /// (read count). Most-read recent articles surface first; ties break by
  /// newest publish date.
  List<NewsModel> _sortCarouselArticles(List<NewsModel> articles) {
    final now = DateTime.now();
    final sorted = List<NewsModel>.from(articles);
    sorted.sort((a, b) {
      final aDate = a.publicationDate ?? DateTime.now();
      final bDate = b.publicationDate ?? DateTime.now();
      // Recency score: newer = higher (decays over days).
      final aDays = now.difference(aDate).inDays.toDouble();
      final bDays = now.difference(bDate).inDays.toDouble();
      final aRecency = (1.0 / (aDays + 1)).clamp(0.0, 1.0);
      final bRecency = (1.0 / (bDays + 1)).clamp(0.0, 1.0);
      // Popularity score from read count (log-scaled so a single viral article
      // doesn't dwarf everything else).
      final aPopularity = (1 + log(a.readCount + 1)) /
          (1 + log(101));
      final bPopularity = (1 + log(b.readCount + 1)) /
          (1 + log(101));
      final aScore = aRecency * 0.6 + aPopularity * 0.4;
      final bScore = bRecency * 0.6 + bPopularity * 0.4;
      return bScore.compareTo(aScore);
    });
    return sorted;
  }

  Widget _buildCategoryChips(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allCats = <Map<String, dynamic>>[
      {'id': 'all', 'name': l10n.translate('all'), 'nameEn': l10n.translate('all')},
    ];
    if (_blendedCount > 0) {
      allCats.add({
        'id': 'blended',
        'name': l10n.translate('blendedBadge'),
        'nameEn': 'Blended',
      });
    }
    allCats.addAll(_categories);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: allCats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final cat = allCats[i];
          final catKey = cat['id']?.toString() ?? 'all';
          final String catName;
          if (catKey == 'all') {
            catName = l10n.translate('all');
          } else if (catKey == 'blended') {
            catName = l10n.translate('blendedBadge');
          } else {
            catName = CategoryService.getCategoryDisplayName(cat, context);
          }
          final int count = catKey == 'all'
              ? _allArticles.length
              : (catKey == 'blended'
                    ? _blendedCount
                    : _allArticles
                          .where(
                            (a) =>
                                _matchesCategory(a.category, catKey) ||
                                _matchesCategory(a.category, catName),
                          )
                          .length);
          final isSelected = _selectedCategory == catKey;

          return FilterChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (catKey == 'blended') ...[
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 12,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  catName,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.25)
                        : Theme.of(context).colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            selected: isSelected,
            onSelected: (bool selected) {
              if (!selected) return;
              setState(() {
                _selectedCategory = catKey;
                if (catKey == 'all') {
                  _articles = List.from(_allArticles);
                } else if (catKey == 'blended') {
                  _articles = _allArticles.where((a) => a.isBlended).toList();
                } else {
                  _articles = _allArticles
                      .where(
                        (a) =>
                            _matchesCategory(a.category, catKey) ||
                            _matchesCategory(a.category, catName),
                      )
                      .toList();
                }
              });
            },
            selectedColor: Theme.of(context).colorScheme.primary,
            checkmarkColor: Theme.of(context).colorScheme.onPrimary,
            side: BorderSide.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTrendingSearches(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final terms = _trendingSearches.isEmpty ? [''] : _trendingSearches;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            l10n.translate('trendingSearches'),
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: terms.map((term) {
            return GestureDetector(
              onTap: () {
                setState(() => _searchQuery = term);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Text(
                  term,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildArticleCard(NewsModel article) {
    final l10n = AppLocalizations.of(context);
    final isBlended = article.isBlended;
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => NewsDetailPage(article: article)),
        );
        if (result != null &&
            result is Map<String, dynamic> &&
            result['search'] != null) {
          final searchQuery = result['search'] as String;
          setState(() {
            _searchQuery = searchQuery;
            _isSearchActive = true;
          });
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: isBlended
              ? Border.all(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.35),
                  width: 1.2,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: isBlended
                  ? const Color(0xFF1565C0).withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isBlended) ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 11,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${l10n.translate('blendedBadge')} • ${article.sourceCount} ${l10n.translate('sources')}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      article.title,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _getCategoryName(article.category, context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getReadTime(article, context),
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (isBlended) ...[
                          const Icon(
                            Icons.layers_rounded,
                            size: 13,
                            color: Color(0xFF1565C0),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              article.sourceAttributions
                                      .take(2)
                                      .map((a) => a['name'])
                                      .join(' + ') +
                                  (article.sourceAttributions.length > 2
                                      ? ' +${article.sourceAttributions.length - 2}'
                                      : ''),
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1565C0),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ] else ...[
                          Icon(
                            Icons.favorite_border_rounded,
                            size: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _getSentimentLabel(article.sentiment, l10n),
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _getSourceName(article),
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNewsImage(
                  imageUrl: article.imageUrl.isEmpty
                      ? 'https://placehold.co/72x72/1A1A2E/C62828?text=${_getCategoryName(article.category, context)[0]}'
                      : article.imageUrl,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorWidget: _buildFallbackImage(article.category),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackImage(String category) {
    final label = _getCategoryName(category, context);
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.secondaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          label.isNotEmpty ? label[0] : '?',
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  String _getCategoryName(String category, BuildContext context) {
    return CategoryService.instance.getCategoryName(category, context);
  }

  String _getReadTime(NewsModel article, BuildContext context) {
    final words = article.content.split(' ').length;
    final minutes = (words / 200).ceil();
    return '$minutes ${AppLocalizations.of(context).translate('readTimeUnit')}';
  }

  String _getSourceName(NewsModel article) {
    return article.displaySourceName;
  }

  Widget _buildDrawer(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/img/play_store_icon_512.png',
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _DrawerItem(
              icon: Icons.home_rounded,
              label: l10n.translate('home'),
              isSelected: _currentIndex == 0,
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentIndex = 0);
              },
            ),
            _DrawerItem(
              icon: Icons.explore_rounded,
              label: l10n.translate('explore'),
              isSelected: _currentIndex == 1,
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentIndex = 1);
              },
            ),
            _DrawerItem(
              icon: Icons.newspaper_rounded,
              label: l10n.translate('dailyBriefing'),
              isSelected: _currentIndex == 2,
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentIndex = 2);
              },
            ),
            _DrawerItem(
              icon: Icons.bookmark_rounded,
              label: l10n.translate('bookmarks'),
              isSelected: _currentIndex == 3,
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentIndex = 3);
              },
            ),
            Divider(
              height: 24,
              thickness: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            _DrawerItem(
              icon: Icons.psychology_rounded,
              label: l10n.translate('personalizedFeed'),
              isSelected: _currentIndex == 4,
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentIndex = 4);
              },
            ),
            _DrawerItem(
              icon: Icons.verified_rounded,
              label: l10n.translate('factCheck'),
              isSelected: _currentIndex == 5,
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentIndex = 5);
              },
            ),
            Divider(
              height: 32,
              thickness: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            _DrawerItem(
              icon: Icons.info_rounded,
              label: l10n.translate('about'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutUsPage()),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.contact_support_rounded,
              label: l10n.translate('contact'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ContactPage()),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.policy_rounded,
              label: l10n.translate('privacyPolicy'),
              onTap: () {
                Navigator.pop(context);
                _openPublicPage('https://apps.inoov.com/yallanews/#privacy');
              },
            ),
            _DrawerItem(
              icon: Icons.article_rounded,
              label: l10n.translate('terms'),
              onTap: () {
                Navigator.pop(context);
                _openPublicPage('https://apps.inoov.com/yallanews/#terms');
              },
            ),
            _DrawerItem(
              icon: Icons.settings_rounded,
              label: l10n.translate('settingsNav'),
              isSelected: _currentIndex == 6,
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentIndex = 6);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPublicPage(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).translate('contactWebsiteError'),
          ),
        ),
    );
  }
}

}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.12)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
