import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/news_model.dart';
import 'news_intelligence.dart';

class ServerApiService {
  static const String _baseUrl = 'https://api.inoov.com/yallanews';
  static const Duration _timeout = Duration(seconds: 15);

  static Uri _endpoint(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$_baseUrl/$path');
    return query != null ? uri.replace(queryParameters: query) : uri;
  }

  static Future<Map<String, dynamic>> getJson(String path, {Map<String, String>? query}) async {
    final response = await http.get(_endpoint(path, query), headers: {
      'Accept': 'application/json',
      'User-Agent': 'YallaNewsApp/1.0',
    }).timeout(_timeout);
    if (response.statusCode == 200) {
      if (response.body.isEmpty) throw Exception('Empty response');
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Server responded ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    final response = await http.post(
      _endpoint(path),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'YallaNewsApp/1.0',
      },
      body: jsonEncode(body),
    ).timeout(_timeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return <String, dynamic>{};
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    String parsedError;
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final error = (data['error'] ?? data['message'] ?? 'Request failed').toString();
      final details = (data['details'] ?? '').toString();
      parsedError = details.isEmpty ? error : '$error | $details';
    } on Exception catch (_) {
      parsedError = response.body.isEmpty ? 'Server responded ${response.statusCode}' : response.body;
    }
    throw Exception('Server responded ${response.statusCode}: $parsedError');
  }

  static Future<List<NewsModel>> getNews({
    int limit = 20,
    int page = 1,
    String? category,
    String? language,
    String? search,
    String sort = 'published_at',
    String order = 'DESC',
  }) async {
    final query = <String, String>{
      'limit': limit.toString(),
      'page': page.toString(),
      'sort': sort,
      'order': order,
      if (category != null && category.isNotEmpty && category != 'all') 'category': category,
      if (language != null && language.isNotEmpty) 'language': language,
      if (search != null && search.isNotEmpty) 'search': search,
    };

    final data = await getJson('news/list.php', query: query);
    if (data['success'] != true) return [];

    final articles = data['articles'] as List<dynamic>? ?? [];
    return articles.map((a) => _parseArticle(a as Map<String, dynamic>)).toList();
  }

  static Future<NewsModel?> getNewsById(String id) async {
    final data = await getJson('news/get.php', query: {'id': id});
    if (data['success'] != true || data['article'] == null) return null;
    return _parseArticle(Map<String, dynamic>.from(data['article']));
  }

  static Future<List<NewsModel>> getTrending({int limit = 10, String language = 'ar'}) async {
    final data = await getJson('trending/list.php', query: {'limit': limit.toString(), 'language': language});
    if (data['success'] != true) return [];
    final trending = data['trending'] as List<dynamic>? ?? [];
    return trending.map((t) {
      final item = Map<String, dynamic>.from(t);
      return NewsModel(
        url: 'trending://${item['query']}',
        title: item['query'] ?? '',
        summary: '',
        content: '',
        imageUrl: '',
        category: 'general',
        sentiment: 0.0,
        keywords: const [],
        logs: '',
        author: '',
        publishDate: (item['createdAt'] ?? 0).toString(),
        sourceCount: 0,
        sources: const [],
      );
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> getCategories() async {
    final data = await getJson('categories/list.php');
    if (data['success'] != true) return [];
    final cats = data['categories'] as List<dynamic>? ?? [];
    return cats.map((c) => Map<String, dynamic>.from(c)).toList();
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
      if (countryCode != null && countryCode.isNotEmpty) 'country_code': countryCode,
      if (language != null && language.isNotEmpty) 'language': language,
      if (lastVisitedTimestamp != null) 'last_visited': lastVisitedTimestamp.toString(),
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
      if (countryCode != null && countryCode.isNotEmpty) 'country_code': countryCode,
      if (language != null && language.isNotEmpty) 'language': language,
      if (lastVisitedTimestamp != null) 'last_visited': lastVisitedTimestamp.toString(),
    };
    final data = await getJson('sources/list.php', query: query.isEmpty ? null : query);
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

  static Future<List<Map<String, dynamic>>> getComments(String articleId) async {
    final data = await getJson('comments/get.php', query: {'articleId': articleId});
    if (data['success'] != true) return [];
    final comments = data['comments'] as List<dynamic>? ?? [];
    return comments.map((c) => Map<String, dynamic>.from(c)).toList();
  }

  static Future<List<Map<String, dynamic>>> getSavedArticles(String userId) async {
    final data = await getJson('saves/list.php');
    if (data['success'] != true) return [];
    final articles = data['articles'] as List<dynamic>? ?? [];
    return articles.map((a) => Map<String, dynamic>.from(a)).toList();
  }

  static Future<List<Map<String, dynamic>>> getHistory(String userId) async {
    final data = await getJson('history/list.php');
    if (data['success'] != true) return [];
    final history = data['history'] as List<dynamic>? ?? [];
    return history.map((h) => Map<String, dynamic>.from(h)).toList();
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    return await postJson('auth/login.php', {'email': email, 'password': password});
  }

  static Future<Map<String, dynamic>> signup(Map<String, dynamic> userData) async {
    return await postJson('auth/signup.php', userData);
  }

  static Future<void> logout() async {
    await postJson('auth/logout.php', {});
  }

  static Future<bool> isLoggedIn() async {
    try {
      final data = await getJson('auth/check_auth.php');
      return data['authenticated'] == true;
    } catch (_e) {
      return false;
    }
  }

  // ─── Likes ────────────────────────────────────────────────────────────────────

  /// Check whether the current authenticated user has liked [articleId].
  static Future<bool> checkLike(String articleId) async {
    try {
      final data = await getJson('likes/check.php', query: {'article_id': articleId});
      return data['liked'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Get the total like count for [articleId].
  static Future<int> getLikeCount(String articleId) async {
    try {
      final data = await getJson('likes/count.php', query: {'article_id': articleId});
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

  static Future<void> saveArticle(NewsModel article) async {
    final sourceId = (article.author.isNotEmpty) ? article.author : NewsModel.extractDomain(article.url);
    await postJson('news/create.php', {
      'title': article.title,
      'summary': article.summary,
      'content': article.content,
      'language': 'ar',
      'category': article.category,
      'sourceId': sourceId,
      'sourceUrlArticle': article.url,
      'imageUrl': article.imageUrl,
      'publishedAt': int.tryParse(article.publishDate) ?? DateTime.now().millisecondsSinceEpoch,
      'status': 'published',
    });
  }



  static NewsModel _parseArticle(Map<String, dynamic> data) {
    final source = data['source'] as Map<String, dynamic>?;
    final title = data['title'] ?? '';
    final summary = data['summary'] ?? '';
    final content = data['content'] ?? '';
    // Compute sentiment from actual article text using local NLP
    final intel = NewsIntelligence.extract(title, content, summary);
    return NewsModel(
      url: data['sourceUrl'] ?? data['id'] ?? '',
      title: title,
      shortTitle: '',
      summary: summary,
      content: content,
      imageUrl: data['imageUrl'] ?? '',
      category: data['category'] ?? 'general',
      sentiment: intel.sentiment,
      keywords: const [],
      logs: '',
      author: source?['name'] ?? '',
      publishDate: (data['publishedAt'] ?? 0).toString(),
      eventType: intel.eventType,
      subcategory: intel.subcategory,
      entities: const [],
      structuredData: const {},
      intelligenceJson: '',
      sourceCount: 1,
      sources: [data['sourceUrl'] ?? ''],
    );
  }
}
