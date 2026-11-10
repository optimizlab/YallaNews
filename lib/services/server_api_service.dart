import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/news_model.dart';
import 'news_intelligence.dart';
import 'app_settings.dart';
import 'tiny_llm_service.dart';
import 'yalla_engine_service.dart';

class ServerApiService {
  static const String _baseUrl = 'https://api.inoov.com/yallanews';
  static const Duration _timeout = Duration(seconds: 15);
  static const String _tokenKey = 'yn_auth_token';
  static const String _userKey = 'yn_auth_user';
  static const String _cookieKey = 'yn_auth_cookie';

  /// In-memory token cache (avoids SharedPreferences call on every request)
  static String? _cachedToken;
  static String? _cachedCookie;

  /// True right after the server issued a token (login/signup). Lets the first
  /// isLoggedIn() check trust the fresh token without a round-trip, in case
  /// check_auth.php on the server does not verify Bearer tokens yet.
  static bool _sessionAuthenticated = false;

  // ─── Token persistence ────────────────────────────────────────────────────

  static Future<String?> getToken() async {
    if (_cachedToken != null) return _cachedToken;
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(_tokenKey);
    return _cachedToken;
  }

  static Future<void> saveToken(String token) async {
    _cachedToken = token;
    _sessionAuthenticated = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<String?> getCookie() async {
    if (_cachedCookie != null) return _cachedCookie;
    final prefs = await SharedPreferences.getInstance();
    _cachedCookie = prefs.getString(_cookieKey);
    return _cachedCookie;
  }

  static Future<void> saveCookie(String cookie) async {
    _cachedCookie = cookie;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cookieKey, cookie);
  }

  static Future<void> clearToken() async {
    _cachedToken = null;
    _cachedCookie = null;
    _sessionAuthenticated = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_cookieKey);
  }

  static Future<void> saveUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user));
  }

  static Future<Map<String, dynamic>?> getSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ─── HTTP helpers ─────────────────────────────────────────────────────────

  static Uri _endpoint(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$_baseUrl/$path');
    return query != null ? uri.replace(queryParameters: query) : uri;
  }

  static Future<Map<String, String>> _authHeaders({bool isJson = false}) async {
    final token = await getToken();
    final cookie = await getCookie();
    return {
      if (isJson) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'YallaNewsApp/1.0',
      if (token != null) 'Authorization': 'Bearer $token',
      if (token != null) 'X-Auth-Token': token,
      if (token != null) 'X-User-Token': token,
      if (token != null) 'X-Authorization': 'Bearer $token',
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  static void _extractAndSaveCookie(http.Response response) {
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      final match = RegExp(r'PHPSESSID=[^;]+').firstMatch(setCookie);
      if (match != null) {
        saveCookie(match.group(0)!);
      }
    }
  }

  static Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final token = await getToken();
    final queryParams = query != null ? Map<String, String>.from(query) : <String, String>{};
    if (token != null && (path.contains('auth/') || path.contains('users/') || path.contains('comments/'))) {
      queryParams.putIfAbsent('token', () => token);
      queryParams.putIfAbsent('auth_token', () => token);
    }
    final response = await http
        .get(_endpoint(path, queryParams.isEmpty ? null : queryParams), headers: await _authHeaders())
        .timeout(_timeout);
    _extractAndSaveCookie(response);
    if (response.statusCode == 200) {
      if (response.body.isEmpty) throw Exception('Empty response');
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    var reason = response.reasonPhrase;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final apiError = (decoded['error'] ?? decoded['message'])?.toString();
        if (apiError != null && apiError.isNotEmpty) reason = apiError;
      }
    } on FormatException {
      // Non-JSON responses, such as a web-server access-denied page, use the
      // HTTP reason phrase rather than leaking an HTML response into the UI.
    }
    throw Exception(
      'Server responded ${response.statusCode}'
      '${reason == null || reason.isEmpty ? '' : ': $reason'}',
    );
  }

  static Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = await getToken();
    final enrichedBody = Map<String, dynamic>.from(body);
    if (token != null && token.isNotEmpty) {
      enrichedBody.putIfAbsent('auth_token', () => token);
      enrichedBody.putIfAbsent('token', () => token);
    }
    final response = await http
        .post(
          _endpoint(path),
          headers: await _authHeaders(isJson: true),
          body: jsonEncode(enrichedBody),
        )
        .timeout(_timeout);
    _extractAndSaveCookie(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return <String, dynamic>{};
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    String parsedError;
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final error = (data['error'] ?? data['message'] ?? 'Request failed')
          .toString();
      final details = (data['details'] ?? '').toString();
      parsedError = details.isEmpty ? error : '$error | $details';
    } on Exception catch (_) {
      parsedError = response.body.isEmpty
          ? 'Server responded ${response.statusCode}'
          : response.body;
    }
    throw Exception('Server responded ${response.statusCode}: $parsedError');
  }

  static Future<List<NewsModel>> getNews({
    int limit = 20,
    int page = 1,
    String? category,
    String? language,
    String? search,
    bool relatedOnly = false,
    String? excludeUrl,
    String sort = 'published_at',
    String order = 'DESC',
  }) async {
    if (relatedOnly &&
        (category == null ||
            category.trim().isEmpty ||
            category.trim().toLowerCase() == 'all' ||
            language == null ||
            language.trim().isEmpty)) {
      throw ArgumentError('Related news requires both category and language.');
    }

    final query = <String, String>{
      'limit': limit.toString(),
      'page': page.toString(),
      'sort': sort,
      'order': order,
      if (relatedOnly) 'related': '1',
      if (relatedOnly && excludeUrl != null && excludeUrl.isNotEmpty)
        'exclude_url': excludeUrl,
      if (category != null && category.isNotEmpty && category != 'all')
        'category': category,
      if (language != null && language.isNotEmpty) 'language': language,
      if (search != null && search.isNotEmpty) 'search': search,
    };

    final data = await getJson('news/list.php', query: query);
    if (data['success'] != true) return <NewsModel>[];

    final articles = data['articles'] as List<dynamic>? ?? const <dynamic>[];
    return articles.map((a) {
      try {
        return _parseArticle(Map<String, dynamic>.from(a as Map));
      } on RangeError catch (e, stack) {
        print('[API] _parseArticle RangeError: $e');
        print('[API] _parseArticle stack: $stack');
        rethrow;
      } catch (e, stack) {
        print('[API] _parseArticle error: $e');
        print('[API] _parseArticle stack: $stack');
        rethrow;
      }
    }).toList();
  }

  static Future<NewsModel?> getNewsById(String id) async {
    final data = await getJson('news/get.php', query: {'id': id});
    if (data['success'] != true || data['article'] == null) return null;
    return _parseArticle(Map<String, dynamic>.from(data['article']));
  }

  static Future<List<NewsModel>> getTrending({
    int limit = 10,
    String language = 'ar',
  }) async {
    try {
      final data = await getJson(
        'trending/list.php',
        query: {'limit': limit.toString(), 'language': language},
      );
      if (data['success'] != true) return [];
      final trending = data['trending'] as List<dynamic>? ?? [];
      return trending.map((t) {
        final item = Map<String, dynamic>.from(t);
        return NewsModel(
          url: 'trending://${(item['query'] ?? '').toString()}',
          title: (item['query'] ?? '').toString(),
          summary: '',
          content: '',
          imageUrl: '',
          category: 'general',
          sentiment: 0.0,
          keywords: const [],
          logs: '',
          author: '',
          publishDate: '',
          sourceUrl: '',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getCategories() async {
    final data = await getJson('categories/list.php');
    if (data['success'] != true) return [];
    final cats = data['categories'] as List<dynamic>? ?? [];
    return cats.map((c) => Map<String, dynamic>.from(c)).toList();
  }

  static Future<Map<String, String>> getCategoryMapping() async {
    final data = await getJson('categories/mapping.php');
    if (data['success'] != true) return <String, String>{};
    final mapping = data['mapping'] as Map<String, dynamic>? ?? {};
    return mapping.map((key, value) => MapEntry(key, value.toString()));
  }

  static Future<List<Map<String, dynamic>>> getSources() async {
    final data = await getJson('sources/list.php');
    if (data['success'] != true) return [];
    final sources = data['sources'] as List<dynamic>? ?? [];
    return sources.map((s) => Map<String, dynamic>.from(s)).toList();
  }

  static Future<List<String>> getSourceUrls({
    String? countryCode,
    String? language,
    int? lastVisitedTimestamp,
  }) async {
    final query = <String, String>{
      'fields': 'urls',
      if (countryCode != null && countryCode.isNotEmpty)
        'country_code': countryCode,
      if (language != null && language.isNotEmpty) 'language': language,
      if (lastVisitedTimestamp != null)
        'last_visited': lastVisitedTimestamp.toString(),
    };
    final data = await getJson('sources/list.php', query: query);
    if (data['success'] != true) return [];
    final urls = data['urls'] as List<dynamic>? ?? [];
    return urls.map((u) => u.toString()).toList();
  }

  static Future<List<Map<String, dynamic>>> getSourcesByCountryAndLanguage({
    String? countryCode,
    String? language,
    int? lastVisitedTimestamp,
  }) async {
    final query = <String, String>{
      if (countryCode != null && countryCode.isNotEmpty)
        'country_code': countryCode,
      if (language != null && language.isNotEmpty) 'language': language,
      if (lastVisitedTimestamp != null)
        'last_visited': lastVisitedTimestamp.toString(),
    };
    final data = await getJson(
      'sources/list.php',
      query: query.isEmpty ? null : query,
    );
    if (data['success'] != true) return [];
    final sources = data['sources'] as List<dynamic>? ?? [];
    return sources.map((s) => Map<String, dynamic>.from(s)).toList();
  }

  static Future<void> updateSourceCrawlTime(String sourceUrl) async {
    await postJson('sources/update_crawl_time.php', {
      'url': sourceUrl,
      'last_crawled': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<void> updateSourceScore(String sourceUrl, double score) async {
    await postJson('sources/update_score.php', {
      'url': sourceUrl,
      'score': score,
    });
  }

  static Future<List<Map<String, dynamic>>> getComments(
    String articleId,
  ) async {
    final data = await getJson(
      'comments/get.php',
      query: {
        'article_id': articleId,
        'articleId': articleId,
      },
    );
    if (data['success'] != true) return [];
    final comments = data['comments'] as List<dynamic>? ?? [];
    return comments.map((c) => Map<String, dynamic>.from(c)).toList();
  }

  static Future<List<Map<String, dynamic>>> getSavedArticles(
    String userId,
  ) async {
    final data = await getJson('saves/list.php');
    if (data['success'] != true) return [];
    final articles = data['articles'] as List<dynamic>? ?? [];
    return articles.map((a) => Map<String, dynamic>.from(a)).toList();
  }

  static Future<List<NewsModel>> getSavedNews() async {
    final data = await getJson('saves/list.php');
    if (data['success'] != true) return [];
    final articles = data['articles'] as List<dynamic>? ?? [];
    return articles
        .map((a) => _parseArticle(Map<String, dynamic>.from(a as Map)))
        .toList();
  }

  static Future<bool> checkSave(String articleId) async {
    try {
      final data = await getJson(
        'saves/check.php',
        query: {'article_id': articleId},
      );
      return data['saved'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> saveUserArticle(String articleId) async {
    await postJson('saves/save.php', {'articleId': articleId});
  }

  static Future<void> unsaveUserArticle(String articleId) async {
    await postJson('saves/unsave.php', {'articleId': articleId});
  }

  static Future<List<Map<String, dynamic>>> getHistory(String userId) async {
    final data = await getJson('history/list.php');
    if (data['success'] != true) return [];
    final history = data['history'] as List<dynamic>? ?? [];
    return history.map((h) => Map<String, dynamic>.from(h)).toList();
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final result = await postJson('auth/login.php', {
      'email': email,
      'password': password,
    });
    if (result['success'] == true) {
      final token = result['token'] as String?;
      if (token != null && token.isNotEmpty) await saveToken(token);
      final user = result['user'];
      if (user is Map<String, dynamic>) await saveUser(user);
    }
    return result;
  }

  static Future<Map<String, dynamic>> signup(
    Map<String, dynamic> userData,
  ) async {
    final result = await postJson('auth/signup.php', userData);
    if (result['success'] == true) {
      final token = result['token'] as String?;
      if (token != null && token.isNotEmpty) await saveToken(token);
      final user = result['user'];
      if (user is Map<String, dynamic>) await saveUser(user);
    }
    return result;
  }

  static Future<void> logout() async {
    try {
      await postJson('auth/logout.php', {});
    } catch (_) {}
    await clearToken();
  }

  static Future<bool> isLoggedIn() async {
    // Fast path: check stored token first
    final token = await getToken();
    if (token == null || token.isEmpty) return false;
    // Token was just issued or verified this session — trust it.
    if (_sessionAuthenticated) return true;
    try {
      final data = await getJson('auth/check_auth.php', query: {'token': token});
      if (data['authenticated'] == true) {
        _sessionAuthenticated = true;
        return true;
      }
      return false;
    } catch (_) {
      // Network error / offline: trust stored token
      return true;
    }
  }

  // ─── Likes ────────────────────────────────────────────────────────────────────

  /// Check whether the current authenticated user has liked [articleId].
  static Future<bool> checkLike(String articleId) async {
    try {
      final data = await getJson(
        'likes/check.php',
        query: {'article_id': articleId},
      );
      return data['liked'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Get the total like count for [articleId].
  static Future<int> getLikeCount(String articleId) async {
    try {
      final data = await getJson(
        'likes/count.php',
        query: {'article_id': articleId},
      );
      return (data['count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Like [articleId] as the current authenticated user.
  static Future<void> likeArticle(String articleId) async {
    await postJson('likes/like.php', {'articleId': articleId});
  }

  /// Unlike [articleId] as the current authenticated user.
  static Future<void> unlikeArticle(String articleId) async {
    await postJson('likes/unlike.php', {'articleId': articleId});
  }

  // ─── Local like fallback ────────────────────────────────────────────────────
  // Likes/unlikes made while the server is unreachable (or cannot verify the
  // token) are kept locally so the user's +1 is never silently reverted.

  static const String _pendingLikesKey = 'pending_likes';

  /// Record the desired like state for [articleId] until the server confirms it.
  static Future<void> setPendingLike(String articleId, bool liked) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = await getPendingLikes();
    pending[articleId] = liked;
    await prefs.setString(_pendingLikesKey, jsonEncode(pending));
  }

  /// Article ids whose local like state has not been confirmed by the server,
  /// mapped to their desired state (true = liked, false = unliked).
  static Future<Map<String, bool>> getPendingLikes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingLikesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return decoded.map((key, value) => MapEntry(key, value == true));
    } catch (_) {
      return {};
    }
  }

  /// Drop the local override once the server has confirmed the like state.
  static Future<void> clearPendingLike(String articleId) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = await getPendingLikes();
    if (pending.remove(articleId) == true) {
      await prefs.setString(_pendingLikesKey, jsonEncode(pending));
    }
  }

  static Future<void> saveArticle(NewsModel article) async {
    final language = article.language.trim().toLowerCase();
    if (language.isEmpty) {
      throw ArgumentError.value(
        article.language,
        'article.language',
        'A crawled article must have a detected source language before upload.',
      );
    }
    final sourceName = article.sourceName.isNotEmpty
        ? article.sourceName
        : article.displaySourceName;
    final sourceUri = Uri.tryParse(
      article.sourceUrl.isNotEmpty ? article.sourceUrl : article.url,
    );
    final imageUrl = NewsModel.resolveImageUrl(article.imageUrl, article.url);
    final publishedAt = _toEpochMilliseconds(article.publishDate);
    await postJson('news/create.php', {
      'title': article.title,
      'summary': article.summary,
      'content': article.content,
      'language': language,
      'category': article.category,
      'source': {
        'name': sourceName,
        'id': sourceName,
        'url': sourceUri == null
            ? ''
            : Uri(scheme: sourceUri.scheme, host: sourceUri.host).toString(),
      },
      'sourceUrlArticle': article.url,
      'imageUrl': imageUrl.isEmpty
          ? NewsModel.getFallbackImage(article.category)
          : imageUrl,
      // Never fabricate a publication date: send the original value when
      // parseable, otherwise 0 so the backend stores an epoch date that
      // freshness filtering treats as stale instead of "now".
      'publishedAt': publishedAt,
      'status': 'published',
    });
  }

  static int _toEpochMilliseconds(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return 0;
    final numeric = int.tryParse(raw);
    if (numeric != null) {
      // Accept both seconds and milliseconds from existing crawlers.
      return numeric < 100000000000 ? numeric * 1000 : numeric;
    }
    final parsed = DateTime.tryParse(raw);
    return parsed?.millisecondsSinceEpoch ?? 0;
  }

  static NewsModel _parseArticle(Map<String, dynamic> data) {
    final source = data['source'] as Map<String, dynamic>?;
    final formatted = TinyLLMService.instance.formatArticleFields(
      title: (data['title'] ?? '').toString(),
      summary: (data['summary'] ?? '').toString(),
      content: (data['content'] ?? '').toString(),
    );
    final sourceUrl =
        data['sourceUrl'] ?? data['source_url'] ?? data['id'] ?? '';
    final sourceName = (data['sourceName'] ?? source?['name'] ?? '').toString();
    final title = _cleanPublisherSuffix(
      formatted['title']!,
      sourceUrl: sourceUrl.toString(),
      sourceName: sourceName,
    );
    final summary = formatted['summary']!;
    final content = formatted['content']!;
    final rawPublishedAt = data['publishedAt'] ?? data['published_at'] ?? 0;
    // Epoch zero is the API's “unknown date” value, not 1 Jan 1970.
    final publishedAt = rawPublishedAt.toString() == '0' ? '' : rawPublishedAt;
    // Compute sentiment from actual article text using local NLP
    final intel = NewsIntelligence.extract(title, content, summary);
    // Original publisher name — taken from the API, never fabricated.
    final displaySourceName = sourceName.isNotEmpty
        ? sourceName
        : NewsModel.extractDomain(sourceUrl);
    // Build source attribution map for News & Magazines policy compliance
    final sourceAttribution = <Map<String, dynamic>>[
      {
        'name': displaySourceName,
        'domain': sourceUrl.isNotEmpty
            ? NewsModel.extractDomain(sourceUrl)
            : '',
        'url': sourceUrl,
        'title': title,
        'publishDate': publishedAt.toString(),
        'author': data['author_name'] ?? data['author'] ?? '',
      },
    ];
    return NewsModel(
      url: sourceUrl,
      title: title,
      shortTitle: '',
      summary: summary,
      content: content,
      imageUrl: data['imageUrl'] ?? '',
      category: data['category'] ?? 'general',
      language: (data['language'] ?? data['lang'] ?? '').toString(),
      sentiment: YallaEngineService.analyzeSentiment(
        '$title $summary $content',
      ),
      keywords: YallaEngineService.extractKeywords(title, summary, content),
      logs: '',
      author: data['author'] ?? '',
      authorName: data['author_name'] ?? '',
      publishDate: publishedAt.toString(),
      publishedAt: publishedAt.toString(),
      updatedAt: data['updated_at'] ?? '',
      eventType: intel.eventType,
      subcategory: intel.subcategory,
      entities: const [],
      structuredData: {'source_attributions': sourceAttribution},
      intelligenceJson: '',
      sourceName: displaySourceName,
      sourceUrl: sourceUrl,
      sourceCount: 1,
      sources: [sourceUrl],
      isFresh: NewsModel.computeFreshness(publishedAt.toString()),
    );
  }

  static String _cleanPublisherSuffix(
    String value, {
    String sourceUrl = '',
    String sourceName = '',
  }) {
    var title = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Repeat because headlines may contain chains such as "| رياضة | الجزيرة نت".
    final suffix = RegExp(
      r'\s*(?:\||—|–|::|:)\s*([^|—–:]{1,60})\s*$',
      caseSensitive: false,
    );
    bool changed;
    do {
      final match = suffix.firstMatch(title);
      changed =
          match != null &&
          (match.group(1) ?? '').trim().split(RegExp(r'\s+')).length <= 6;
      if (changed) title = title.substring(0, match!.start).trim();
    } while (changed);
    final host =
        Uri.tryParse(sourceUrl)?.host.toLowerCase().replaceFirst('www.', '') ??
        '';
    final aliases = <String>[
      'هسبورت',
      'هيسبورت',
      'هسبريس',
      'أراجيك',
      'اراجيك',
      'كووورة',
      'اليوم24',
      'اليوم 24',
    ];
    for (final candidate in <String>[
      sourceName,
      ...aliases,
    ].where((c) => c.trim().isNotEmpty)) {
      title = title
          .replaceFirst(
            RegExp(
              '\\s*${RegExp.escape(candidate)}\\s*\$',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
    }
    if (host.contains('hesport')) {
      title = title
          .replaceFirst(
            RegExp(r'\s*(?:هسبورت|هيسبورت)\s*$', caseSensitive: false),
            '',
          )
          .trim();
    }
    return title.replaceAll(RegExp(r'[|—–:]+\s*$'), '').trim();
  }

  static Timer? _heartbeatTimer;
  static String? _sessionId;

  /// Stable per-install session id shared with the analytics pipeline.
  static String get sessionId {
    _sessionId ??=
        'session_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecondsSinceEpoch % 9000))}';
    return _sessionId!;
  }

  /// Send a live ping to api/stats/ping.php
  static Future<void> sendPing() async {
    try {
      final os = Platform.isAndroid
          ? 'android'
          : Platform.isIOS
          ? 'ios'
          : Platform.isWindows
          ? 'windows'
          : Platform.isMacOS
          ? 'macos'
          : Platform.isLinux
          ? 'linux'
          : 'unknown';

      String countryCode = 'EG';
      try {
        final loc = Platform.localeName;
        final parts = loc.split(RegExp('[-_]'));
        if (parts.length >= 2) {
          countryCode = parts[1].toUpperCase();
        } else if (parts.isNotEmpty) {
          countryCode = parts[0].toUpperCase();
        }
      } catch (_) {}

      bool isNewInstall = false;
      try {
        isNewInstall = await AppSettings.instance.isFirstRun();
      } catch (_) {}

      await postJson('stats/ping.php', {
        'sessionId': _sessionId,
        'deviceOs': os,
        'appVersion': '1.0.0',
        'countryCode': countryCode,
        'isNewInstall': isNewInstall ? 1 : 0,
      });
    } catch (_) {
      // Silent in background
    }
  }

  /// Start periodic live heartbeat (every 60s)
  static void startHeartbeat() {
    _heartbeatTimer?.cancel();
    sendPing();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => sendPing(),
    );
  }

  /// Stop heartbeat
  static void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
}
