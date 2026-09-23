import 'package:flutter/foundation.dart';
import '../models/news_model.dart';
import 'server_api_service.dart';

class CategoryService extends ChangeNotifier {
  CategoryService._internal();
  static final CategoryService instance = CategoryService._internal();

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> get categories => List.unmodifiable(_categories);

  bool _initialized = false;
  bool get initialized => _initialized;

  static const List<Map<String, dynamic>> defaultCategories = [
    {'id': 'politics', 'name': 'سياسة', 'nameEn': 'Politics', 'active': true, 'newsCount': 0},
    {'id': 'sports', 'name': 'رياضة', 'nameEn': 'Sports', 'active': true, 'newsCount': 0},
    {'id': 'business', 'name': 'اقتصاد', 'nameEn': 'Business', 'active': true, 'newsCount': 0},
    {'id': 'technology', 'name': 'تكنولوجيا', 'nameEn': 'Technology', 'active': true, 'newsCount': 0},
    {'id': 'health', 'name': 'صحة', 'nameEn': 'Health', 'active': true, 'newsCount': 0},
    {'id': 'science', 'name': 'علوم', 'nameEn': 'Science', 'active': true, 'newsCount': 0},
    {'id': 'entertainment', 'name': 'ترفيه', 'nameEn': 'Entertainment', 'active': true, 'newsCount': 0},
    {'id': 'world', 'name': 'أخبار دولية', 'nameEn': 'World', 'active': true, 'newsCount': 0},
    {'id': 'local', 'name': 'أخبار محلية', 'nameEn': 'Local', 'active': true, 'newsCount': 0},
  ];

  Future<void> loadCategories({bool forceRefresh = false}) async {
    if (_initialized && !forceRefresh) return;
    try {
      final fetched = await ServerApiService.getCategories();
      if (fetched.isNotEmpty) {
        _categories = fetched.where((c) {
          final active = c['active'];
          return active == true || active == 1 || active == '1' || active == null;
        }).map((c) => Map<String, dynamic>.from(c)).toList();
      }

      if (_categories.isEmpty) {
        _categories = defaultCategories.map((c) => Map<String, dynamic>.from(c)).toList();
      }

      _initialized = true;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('[CategoryService] Failed to load categories: $e');
      }
      if (_categories.isEmpty) {
        _categories = defaultCategories.map((c) => Map<String, dynamic>.from(c)).toList();
        _initialized = true;
        notifyListeners();
      }
    }
  }

  List<String> get categoryIds => _categories.map((c) => c['id']?.toString() ?? 'general').toList();

  Map<String, String> get categoryNames {
    final map = <String, String>{};
    for (final c in _categories) {
      final id = c['id']?.toString() ?? 'general';
      final name = c['name']?.toString() ?? id;
      map[id] = name;
    }
    return map;
  }

  bool _matchesCategory(String articleCat, String targetCat) {
    final a = articleCat.toLowerCase().trim();
    final t = targetCat.toLowerCase().trim();
    if (a == t) return true;

    final categoryAliases = <String, List<String>>{
      'sports': ['sports', 'رياضة', 'كرة القدم', 'كرة السلة', 'تنس', 'sport', 'football'],
      'politics': ['politics', 'سياسة', 'أخبار محلية', 'أخبار دولية', 'politic'],
      'business': ['business', 'اقتصاد', 'أعمال', 'أسواق ومال', 'عقارات', 'economy', 'finance'],
      'technology': ['technology', 'تكنولوجيا', 'تقنية', 'علوم وتكنولوجيا', 'tech'],
      'health': ['health', 'صحة', 'طب وصحة', 'علوم وطب', 'medical'],
      'entertainment': ['entertainment', 'ترفيه', 'فن', 'ثقافة', 'منوعات', 'فن وموسيقى', 'culture'],
      'science': ['science', 'علوم', 'علم'],
      'world': ['world', 'أخبار دولية', 'دولي', 'العالم'],
      'general': ['general', 'general_news', 'أخبار عامة', 'عام'],
    };

    for (final aliases in categoryAliases.values) {
      final matchesA = aliases.any((x) => x == a || a.contains(x) || x.contains(a));
      final matchesT = aliases.any((x) => x == t || t.contains(x) || x.contains(t));
      if (matchesA && matchesT) return true;
    }

    return false;
  }

  void updateCategoryCounts(List<NewsModel> articles) {
    for (final category in _categories) {
      final id = category['id']?.toString() ?? '';
      final name = category['name']?.toString() ?? id;
      int count = 0;
      for (final article in articles) {
        if (_matchesCategory(article.category, id) || _matchesCategory(article.category, name)) {
          count++;
        }
      }
      category['newsCount'] = count;
    }
    notifyListeners();
  }
}
