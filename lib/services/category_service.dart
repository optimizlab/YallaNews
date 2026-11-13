import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import '../database/news_db.dart';
import 'server_api_service.dart';

class CategoryService extends ChangeNotifier {
  CategoryService._internal();
  static final CategoryService instance = CategoryService._internal();

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> get categories => List.unmodifiable(_categories);

  bool _initialized = false;
  bool get initialized => _initialized;

  static Map<String, String> _parseNameTranslation(dynamic raw) {
    final translations = <String, String>{};
    if (raw == null) return translations;

    dynamic decoded;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return translations;
      }
    } else {
      decoded = raw;
    }

    if (decoded is List && decoded.isNotEmpty) {
      final first = decoded.first;
      if (first is Map) {
        for (final entry in first.entries) {
          translations[entry.key.toString()] = entry.value.toString();
        }
      }
    } else if (decoded is Map) {
      for (final entry in decoded.entries) {
        translations[entry.key.toString()] = entry.value.toString();
      }
    }

    return translations;
  }

  Future<void> loadCategories({bool forceRefresh = false}) async {
    if (_initialized && !forceRefresh) return;
    try {
      final fetched = await ServerApiService.getCategories();
      if (fetched.isNotEmpty) {
        final activeList = fetched
            .where((c) {
              final active = c['active'];
              return active == true ||
                  active == 1 ||
                  active == '1' ||
                  active == null;
            })
            .map((c) => Map<String, dynamic>.from(c))
            .toList();

        final Map<String, Map<String, dynamic>> uniqueCats = {};
        for (final cat in activeList) {
          final id = (cat['id']?.toString() ?? '').toLowerCase().trim();
          if (id.isEmpty) continue;

          final nameTranslations = _parseNameTranslation(
            cat['name_translation'],
          );
          var name = (cat['name']?.toString() ?? '').trim();
          final nameEn = (cat['nameEn'] ?? cat['name_en'] ?? '')
              .toString()
              .trim();
          if (name.isEmpty && nameEn.isEmpty) continue;

          if (!uniqueCats.containsKey(id)) {
            uniqueCats[id] = {
              'id': id,
              'name': name,
              'nameEn': nameEn,
              'name_translation': nameTranslations,
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
        await _loadCategoriesFromLocalArticles();
      }

      _initialized = true;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('[CategoryService] Failed to load categories: $e');
      }
      try {
        await _loadCategoriesFromLocalArticles();
      } catch (fallbackError) {
        if (kDebugMode) {
          print(
            '[CategoryService] Failed to load categories from local articles: $fallbackError',
          );
        }
      }
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> _loadCategoriesFromLocalArticles() async {
    final articles = await NewsDatabase.instance.getAllArticles(limit: 1000);
    final categoryCounts = <String, int>{};
    for (final article in articles) {
      final id = article.category.trim();
      if (id.isEmpty) continue;
      categoryCounts.update(id, (count) => count + 1, ifAbsent: () => 1);
    }

    final categories =
        categoryCounts.entries
            .map(
              (entry) => <String, dynamic>{
                'id': entry.key,
                'name': entry.key,
                'nameEn': entry.key,
                'translations': const <String, String>{},
                'sortOrder': 50,
                'active': true,
                'newsCount': entry.value,
              },
            )
            .toList()
          ..sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String),
          );
    if (categories.isNotEmpty) _categories = categories;
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

  List<String> get categoryIds =>
      _categories.map((c) => c['id']?.toString() ?? 'general').toList();

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
      'sports': [
        'sports',
        'رياضة',
        'كرة القدم',
        'كرة السلة',
        'تنس',
        'sport',
        'football',
        'motorsport',
      ],
      'politics': ['politics', 'سياسة', 'politic'],
      'business': [
        'business',
        'اقتصاد',
        'أعمال',
        'أسواق ومال',
        'عقارات',
        'economy',
        'finance',
        'markets',
        'real_estate',
      ],
      'technology': [
        'technology',
        'تكنولوجيا',
        'تقنية',
        'علوم وتكنولوجيا',
        'tech',
        'ai',
        'cybersecurity',
      ],
      'health': ['health', 'صحة', 'طب وصحة', 'علوم وطب', 'medical', 'medicine'],
      'entertainment': [
        'entertainment',
        'ترفيه',
        'فن',
        'فن وترفيه',
        'سينما',
        'موسيقى',
        'cinema',
        'music',
      ],
      'culture': ['culture', 'ثقافة', 'كتب وأدب', 'books'],
      'science': ['science', 'علوم', 'علم', 'فضاء', 'space'],
      'world': [
        'world',
        'international',
        'أخبار دولية',
        'دولي',
        'العالم',
        'regional',
        'أخبار إقليمية',
      ],
      'general': ['general', 'general_news', 'أخبار عامة', 'عام'],
      'local': ['local', 'أخبار محلية', 'محلي'],
    };

    for (final aliases in categoryAliases.values) {
      final matchesA = aliases.any(
        (x) => x == a || a.contains(x) || x.contains(a),
      );
      final matchesT = aliases.any(
        (x) => x == t || t.contains(x) || x.contains(t),
      );
      if (matchesA && matchesT) return true;
    }

    return false;
  }

  String getCategoryName(String categoryId, BuildContext context) {
    final normalizedId = categoryId.toLowerCase().trim();
    if (normalizedId.isEmpty) {
      return categoryId;
    }
    if (normalizedId == 'all' || normalizedId == 'الكل') {
      return AppLocalizations.of(context).translate('all');
    }

    for (final category in _categories) {
      final id = category['id']?.toString().toLowerCase().trim() ?? '';
      final name = category['name']?.toString().toLowerCase().trim() ?? '';
      final translations = _categoryTranslations(category);
      if (normalizedId == id ||
          normalizedId == name ||
          translations.values.any(
            (translation) => translation.toLowerCase().trim() == normalizedId,
          )) {
        return getCategoryDisplayName(category, context);
      }
    }

    return categoryId;
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

  static String getCategoryDisplayName(
    Map<String, dynamic> category,
    BuildContext context,
  ) {
    final id = (category['id']?.toString() ?? '').toLowerCase().trim();
    if (matchesCategory(id, 'all') || id == 'all' || id == 'الكل')
      return AppLocalizations.of(context).translate('all');

    final localeCode = AppLocalizations.of(context).locale.languageCode;

    final name = category['name']?.toString().trim() ?? '';
    final nameAr =
        (category['nameAr'] ?? category['name_ar'])?.toString().trim() ?? '';
    final nameEn =
        (category['nameEn'] ?? category['name_en'])?.toString().trim() ?? '';
    final nameFr =
        (category['nameFr'] ?? category['name_fr'])?.toString().trim() ?? '';
    final nameTr =
        (category['nameTr'] ?? category['name_tr'])?.toString().trim() ?? '';

    final translations = _categoryTranslations(category);

    switch (localeCode) {
      case 'ar':
        if (nameAr.isNotEmpty) return nameAr;
        final arTr = translations['ar'];
        if (arTr != null && arTr.isNotEmpty) return arTr;
        final l10nTr = AppLocalizations.of(context).translate(id);
        if (l10nTr != id && l10nTr.isNotEmpty) return l10nTr;
        if (name.isNotEmpty) return name;
        if (nameEn.isNotEmpty) return nameEn;
        break;
      case 'en':
        if (nameEn.isNotEmpty) return nameEn;
        final enTr = translations['en'];
        if (enTr != null && enTr.isNotEmpty) return enTr;
        final l10nTr = AppLocalizations.of(context).translate(id);
        if (l10nTr != id && l10nTr.isNotEmpty) return l10nTr;
        if (name.isNotEmpty) return name;
        break;
      case 'fr':
        if (nameFr.isNotEmpty) return nameFr;
        final frTr = translations['fr'];
        if (frTr != null && frTr.isNotEmpty) return frTr;
        final l10nTr = AppLocalizations.of(context).translate(id);
        if (l10nTr != id && l10nTr.isNotEmpty) return l10nTr;
        if (name.isNotEmpty) return name;
        if (nameEn.isNotEmpty) return nameEn;
        break;
      case 'tr':
        if (nameTr.isNotEmpty) return nameTr;
        final trTr = translations['tr'];
        if (trTr != null && trTr.isNotEmpty) return trTr;
        final l10nTr = AppLocalizations.of(context).translate(id);
        if (l10nTr != id && l10nTr.isNotEmpty) return l10nTr;
        if (name.isNotEmpty) return name;
        if (nameEn.isNotEmpty) return nameEn;
        break;
    }

    final fallback = <String, String>{
      'ar': nameAr.isNotEmpty ? nameAr : name,
      'en': nameEn.isNotEmpty ? nameEn : name,
      'fr': nameFr.isNotEmpty ? nameFr : name,
      'tr': nameTr.isNotEmpty ? nameTr : name,
    }[localeCode];
    if (fallback != null && fallback.isNotEmpty) return fallback;
    if (name.isNotEmpty) return name;
    if (nameEn.isNotEmpty) return nameEn;
    return category['id']?.toString() ?? '';
  }

  static Map<String, String> _categoryTranslations(
    Map<String, dynamic> category,
  ) {
    final fromApi = _parseNameTranslation(
      category['translations'] ?? category['name_translation'],
    );
    final fields = <String, String>{
      'ar': (category['nameAr'] ?? category['name_ar'])?.toString().trim() ?? '',
      'en':
          (category['nameEn'] ?? category['name_en'])?.toString().trim() ?? '',
      'fr':
          (category['nameFr'] ?? category['name_fr'])?.toString().trim() ?? '',
      'tr':
          (category['nameTr'] ?? category['name_tr'])?.toString().trim() ?? '',
    };
    for (final entry in fields.entries) {
      if (entry.value.isNotEmpty) {
        fromApi[entry.key] = entry.value;
      }
    }
    return fromApi;
  }

  void updateCategoryCounts(List<NewsModel> articles) {
    for (final category in _categories) {
      final id = category['id']?.toString() ?? '';
      final name = category['name']?.toString() ?? id;
      int count = 0;
      for (final article in articles) {
        if (matchesCategory(article.category, id) ||
            matchesCategory(article.category, name)) {
          count++;
        }
      }
      category['newsCount'] = count;
    }
    notifyListeners();
  }
}
