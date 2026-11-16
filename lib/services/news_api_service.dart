import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/news_model.dart';
import 'news_intelligence.dart';

/// Fetches articles from NewsAPI.org (https://newsapi.org/)
/// and maps them to [NewsModel] so they can be combined with crawled articles.
class NewsApiService {
  static const String _baseUrl = 'https://newsapi.org/v2';
  static const String _apiKeyPrefsKey = 'yn_newsapi_key';

  static String? _apiKey = '35f32981d77843a2962defd90736e138';
  static bool _initialized = true;

  /// Initialize the API key from persistent storage. Call once at app startup.
  static Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_apiKeyPrefsKey);
    _initialized = true;
  }

  /// Persist the API key to shared preferences and keep it in memory.
  static Future<void> setApiKey(String key) async {
    _apiKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPrefsKey, key);
  }

  /// Clear the stored API key.
  static Future<void> clearApiKey() async {
    _apiKey = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyPrefsKey);
  }

  static String? get apiKey => _apiKey;

  static Future<List<NewsModel>> fetchArticles({
    String? category,
    String? language,
    int pageSize = 30,
    String? query,
  }) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) return <NewsModel>[];

    final params = <String, String>{
      'apiKey': key,
      'pageSize': pageSize.toString(),
      if (category != null && category.isNotEmpty && category != 'general')
        'category': category,
      if (language != null && language.isNotEmpty) 'language': language,
      if (query != null && query.isNotEmpty) 'q': query,
    };

    try {
      final uri = Uri.parse('$_baseUrl/top-headlines')
          .replace(queryParameters: params);
      final response = await http.get(uri).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode != 200) return <NewsModel>[];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'ok') return <NewsModel>[];

      final articles = data['articles'] as List<dynamic>? ?? <dynamic>[];
      return articles.map((a) {
        final map = Map<String, dynamic>.from(a as Map);
        final source = map['source'] as Map<String, dynamic>?;
        final sourceName = (source?['name'] ?? 'NewsAPI').toString();
        final url = (map['url'] ?? '').toString();
        final publishedAt = (map['publishedAt'] ?? '').toString();

        return NewsModel(
          url: url,
          title: (map['title'] ?? '').toString(),
          summary: (map['description'] ?? '').toString(),
          content: (map['content'] ?? '').toString(),
          imageUrl: (map['urlToImage'] ?? '').toString(),
          category: IntelligenceResult.determineCategory(
            '${(map['title'] ?? '')} ${(map['description'] ?? '')}',
            url: url,
            title: (map['title'] ?? '').toString(),
          ),
          language: (language ?? 'en').toString(),
          sentiment: 0.0,
          keywords: <String>[],
          logs: '',
          author: (map['author'] ?? '').toString(),
          publishDate: publishedAt,
          eventType: 'general',
          subcategory: 'general',
          entities: <String>[],
          structuredData: <String, dynamic>{
            'source_attributions': <Map<String, dynamic>>[
              {
                'name': sourceName,
                'domain': sourceName,
                'url': url,
                'title': (map['title'] ?? '').toString(),
                'publishDate': publishedAt,
                'author': (map['author'] ?? '').toString(),
              },
            ],
          },
          intelligenceJson: '',
          sourceName: sourceName,
          sourceUrl: sourceName,
          authorName: (map['author'] ?? '').toString(),
          publishedAt: publishedAt,
          updatedAt: '',
          isFresh: true,
          sourceCount: 1,
          sources: <String>[url],
        );
      }).toList();
    } catch (_) {
      return <NewsModel>[];
    }
  }
}
