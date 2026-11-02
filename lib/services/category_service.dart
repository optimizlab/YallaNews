import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../l10n/app_localizations.dart';
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
    {'id': 'general', 'name': 'أخبار عامة', 'nameEn': 'General News', 'sortOrder': 1, 'active': true, 'newsCount': 0},
    {'id': 'politics', 'name': 'سياسة', 'nameEn': 'Politics', 'sortOrder': 2, 'active': true, 'newsCount': 0},
    {'id': 'sports', 'name': 'رياضة', 'nameEn': 'Sports', 'sortOrder': 3, 'active': true, 'newsCount': 0},
    {'id': 'economy', 'name': 'اقتصاد', 'nameEn': 'Economy', 'sortOrder': 4, 'active': true, 'newsCount': 0},
    {'id': 'technology', 'name': 'تكنولوجيا', 'nameEn': 'Technology', 'sortOrder': 5, 'active': true, 'newsCount': 0},
    {'id': 'health', 'name': 'صحة', 'nameEn': 'Health', 'sortOrder': 6, 'active': true, 'newsCount': 0},
    {'id': 'culture', 'name': 'ثقافة', 'nameEn': 'Culture', 'sortOrder': 7, 'active': true, 'newsCount': 0},
    {'id': 'entertainment', 'name': 'فن وترفيه', 'nameEn': 'Entertainment', 'sortOrder': 8, 'active': true, 'newsCount': 0},
    {'id': 'science', 'name': 'علوم', 'nameEn': 'Science', 'sortOrder': 9, 'active': true, 'newsCount': 0},
  ];

  Future<void> loadCategories({bool forceRefresh = false}) async {
    if (_initialized && !forceRefresh) return;
    try {
      final fetched = await ServerApiService.getCategories();
      if (fetched.isNotEmpty) {
        final activeList = fetched.where((c) {
          final active = c['active'];
          return active == true || active == 1 || active == '1' || active == null;
        }).map((c) => Map<String, dynamic>.from(c)).toList();

        // Deduplicate and normalize display names if server returned raw slugs
        final Map<String, Map<String, dynamic>> uniqueCats = {};
        for (final cat in activeList) {
          final id = (cat['id']?.toString() ?? '').toLowerCase().trim();
          if (id.isEmpty) continue;
          
          // Normalize slugs like tech -> technology, general_news -> general
          final normalizedId = _normalizeCategoryId(id);
          var name = (cat['name']?.toString() ?? '').trim();
          var nameEn = (cat['nameEn']?.toString() ?? '').trim();

          // If the name is just the raw ID, provide Arabic/English human-readable names
          if (name.isEmpty || name == id || name == normalizedId) {
            name = _defaultArabicName(normalizedId);
          }
          if (nameEn.isEmpty || nameEn == id || nameEn == normalizedId) {
            nameEn = _defaultEnglishName(normalizedId);
          }

          if (!uniqueCats.containsKey(normalizedId)) {
            uniqueCats[normalizedId] = {
              'id': normalizedId,
              'name': name,
              'nameEn': nameEn,
              'sortOrder': cat['sortOrder'] ?? 50,
              'active': true,
              'newsCount': cat['newsCount'] ?? 0,
            };
          }
        }

        final sorted = uniqueCats.values.toList();
        sorted.sort((a, b) {
          final orderA = (a['sortOrder'] as num?)?.toInt() ?? 50;
          final orderB = (b['sortOrder'] as num?)?.toInt() ?? 50;
          return orderA.compareTo(orderB);
        });

        _categories = sorted;
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

  static String _normalizeCategoryId(String id) {
    switch (id) {
      case 'general_news':
        return 'general';
      case 'tech':
        return 'technology';
      case 'world':
      case 'international':
        return 'general';
      case 'biz':
      case 'business':
      case 'markets':
        return 'economy';
      case 'sport':
        return 'sports';
      default:
        return id;
    }
  }

  static String _defaultArabicName(String id) {
    switch (id) {
      case 'general':
      case 'general_news':
        return 'أخبار عامة';
      case 'politics':
        return 'سياسة';
      case 'sports':
      case 'football':
        return 'رياضة';
      case 'economy':
      case 'business':
      case 'markets':
        return 'اقتصاد';
      case 'technology':
      case 'tech':
      case 'ai':
        return 'تكنولوجيا';
      case 'health':
      case 'medicine':
        return 'صحة';
      case 'culture':
        return 'ثقافة';
      case 'entertainment':
      case 'cinema':
        return 'فن وترفيه';
      case 'science':
      case 'space':
        return 'علوم';
      case 'international':
      case 'world':
        return 'أخبار دولية';
      case 'local':
        return 'أخبار محلية';
      default:
        return id;
    }
  }

  static String _defaultEnglishName(String id) {
    switch (id) {
      case 'general':
      case 'general_news':
        return 'General News';
      case 'politics':
        return 'Politics';
      case 'sports':
      case 'football':
        return 'Sports';
      case 'economy':
      case 'business':
      case 'markets':
        return 'Economy';
      case 'technology':
      case 'tech':
      case 'ai':
        return 'Technology';
      case 'health':
      case 'medicine':
        return 'Health';
      case 'culture':
        return 'Culture';
      case 'entertainment':
      case 'cinema':
        return 'Entertainment';
      case 'science':
      case 'space':
        return 'Science';
      case 'international':
      case 'world':
        return 'International News';
      case 'local':
        return 'Local News';
      default:
        return id;
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

  static bool matchesCategory(String articleCat, String targetCat) {
    final a = articleCat.toLowerCase().trim();
    final t = targetCat.toLowerCase().trim();
    if (a == t) return true;

    final categoryAliases = <String, List<String>>{
      'sports': ['sports', 'رياضة', 'كرة القدم', 'كرة السلة', 'تنس', 'sport', 'football', 'motorsport'],
      'politics': ['politics', 'سياسة', 'politic'],
      'business': ['business', 'اقتصاد', 'أعمال', 'أسواق ومال', 'عقارات', 'economy', 'finance', 'markets', 'real_estate'],
      'technology': ['technology', 'تكنولوجيا', 'تقنية', 'علوم وتكنولوجيا', 'tech', 'ai', 'cybersecurity'],
      'health': ['health', 'صحة', 'طب وصحة', 'علوم وطب', 'medical', 'medicine'],
      'entertainment': ['entertainment', 'ترفيه', 'فن', 'فن وترفيه', 'سينما', 'موسيقى', 'cinema', 'music'],
      'culture': ['culture', 'ثقافة', 'كتب وأدب', 'books'],
      'science': ['science', 'علوم', 'علم', 'فضاء', 'space'],
      'world': ['world', 'international', 'أخبار دولية', 'دولي', 'العالم', 'regional', 'أخبار إقليمية'],
      'general': ['general', 'general_news', 'أخبار عامة', 'عام'],
      'local': ['local', 'أخبار محلية', 'محلي'],
    };

    for (final aliases in categoryAliases.values) {
      final matchesA = aliases.any((x) => x == a || a.contains(x) || x.contains(a));
      final matchesT = aliases.any((x) => x == t || t.contains(x) || x.contains(t));
      if (matchesA && matchesT) return true;
    }

    return false;
  }

  static String getCategoryLabel(String category, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cat = category.toLowerCase().trim();
    if (matchesCategory(cat, 'sports')) return l10n.translate('sports');
    if (matchesCategory(cat, 'politics')) return l10n.translate('politics');
    if (matchesCategory(cat, 'business')) return l10n.translate('business');
    if (matchesCategory(cat, 'technology')) return l10n.translate('technology');
    if (matchesCategory(cat, 'health')) return l10n.translate('health');
    if (matchesCategory(cat, 'science')) return l10n.translate('science');
    if (matchesCategory(cat, 'entertainment')) return l10n.translate('entertainment');
    if (matchesCategory(cat, 'world')) return l10n.translate('world');
    if (matchesCategory(cat, 'local')) return l10n.translate('local');
    return category.isNotEmpty ? category : l10n.translate('generalNews');
  }

  static IconData getCategoryIcon(String id) {
    final cleanId = _normalizeCategoryId(id.toLowerCase().trim());
    switch (cleanId) {
      case 'sports':
        return Icons.sports_soccer_rounded;
      case 'technology':
        return Icons.memory_rounded;
      case 'politics':
        return Icons.account_balance_rounded;
      case 'entertainment':
        return Icons.movie_filter_rounded;
      case 'culture':
        return Icons.menu_book_rounded;
      case 'business':
      case 'economy':
        return Icons.trending_up_rounded;
      case 'health':
        return Icons.health_and_safety_rounded;
      case 'science':
        return Icons.science_rounded;
      case 'international':
      case 'world':
        return Icons.public_rounded;
      case 'local':
        return Icons.location_city_rounded;
      default:
        return Icons.newspaper_rounded;
    }
  }

  static Color getCategoryColor(String id) {
    final cleanId = _normalizeCategoryId(id.toLowerCase().trim());
    switch (cleanId) {
      case 'sports':
        return const Color(0xFF1B5E20);
      case 'technology':
        return const Color(0xFF6A1B9A);
      case 'politics':
        return const Color(0xFFB71C1C);
      case 'entertainment':
        return const Color(0xFFE65100);
      case 'culture':
        return const Color(0xFF795548);
      case 'business':
      case 'economy':
        return const Color(0xFF0D47A1);
      case 'health':
        return const Color(0xFF00695C);
      case 'science':
        return const Color(0xFF0277BD);
      case 'international':
      case 'world':
        return const Color(0xFF283593);
      case 'local':
        return const Color(0xFF455A64);
      default:
        return const Color(0xFFC62828);
    }
  }

  static String getCategoryDisplayName(Map<String, dynamic> category, BuildContext context) {
    final isArabic = (AppLocalizations.of(context)?.locale?.languageCode ?? 'ar') == 'ar';
    final name = category['name']?.toString() ?? '';
    final nameEn = category['nameEn']?.toString() ?? '';
    if (isArabic && name.isNotEmpty) return name;
    if (!isArabic && nameEn.isNotEmpty) return nameEn;
    return name.isNotEmpty ? name : (category['id']?.toString() ?? '');
  }

  void updateCategoryCounts(List<NewsModel> articles) {
    for (final category in _categories) {
      final id = category['id']?.toString() ?? '';
      final name = category['name']?.toString() ?? id;
      int count = 0;
      for (final article in articles) {
        if (matchesCategory(article.category, id) || matchesCategory(article.category, name)) {
          count++;
        }
      }
      category['newsCount'] = count;
    }
    notifyListeners();
  }
}
