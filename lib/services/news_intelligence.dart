import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'arabic_normalizer.dart';
import 'category_service.dart';
import 'server_api_service.dart';

class NewsIntelligence {
  static final Map<String, dynamic> _classificationCache = {};
  static final List<String> _classificationCacheKeys = [];
  static const int _classificationCacheLimit = 250;

  static String _norm(String text) => ArabicTextNormalizer.normalize(text);

  static const Map<String, List<String>> _categoryKeywords = {
    'POLITICS': [
      // Arabic phrases (higher score)
      'رئيس الحكومة', 'مجلس النواب', 'مجلس المستشارين', 'وزير الخارجية', 'وزارة الداخلية', 'الديوان الملكي',
      'حزب سياسي', 'أحزاب سياسية', 'أزمة دبلوماسية', 'إصلاح سياسي', 'علاقات دبلوماسية', 'مجلس الأمن',
      'الانتخابات الرئاسية', 'حملة انتخابية', 'خطاب ملكي', 'إقبال الناخبين', 'نسبة المشاركة',
      // Arabic single terms
      'سياسة', 'حكومة', 'برلمان', 'رئيس', 'وزير', 'وزارة', 'انتخابات', 'انتخاب', 'حزب', 'أحزاب', 'دستور',
      'معارضة', 'أغلبية', 'دبلوماسية', 'دبلوماسي', 'سفير', 'سفارة', 'قمة', 'مفاوضات', 'معاهدة', 'قانون',
      'تشريع', 'مرسوم', 'عقوبات', 'تصويت', 'اقتراع', 'مستشار', 'رئاسة', 'رئاسي', 'رئاسية', 'ناخبين',
      'ناخب', 'استفتاء', 'تحالف', 'سياسيون', 'سياسي', 'سياسية',
      // English
      'politics', 'political', 'government', 'parliament', 'minister', 'ministry', 'president',
      'presidential', 'election', 'elections', 'voter', 'voters', 'turnout', 'diplomacy', 'diplomatic',
      'ambassador', 'embassy', 'treaty', 'legislation', 'opposition', 'coalition', 'sanctions',
    ],
    'ECONOMY': [
      // Arabic phrases
      'البنك المركزي', 'بنك المغرب', 'سوق الأسهم', 'أسعار الفائدة', 'صندوق النقد', 'البنك الدولي',
      'الناتج المحلي', 'نمو اقتصادي', 'عجز الموازنة', 'سعر الصرف', 'قطاع بنكي', 'استثمار أجنبي',
      'غرفة التجارة', 'سوق العمل', 'بورصة الدار البيضاء', 'ارتفاع الأسعار', 'انخفاض الأسعار',
      // Arabic single terms
      'اقتصاد', 'اقتصادي', 'اقتصادية', 'مال', 'مالية', 'بورصة', 'أسواق', 'سوق', 'بنك', 'بنوك',
      'تضخم', 'فائدة', 'استثمار', 'استثمارات', 'تجارة', 'تجاري', 'صادرات', 'واردات', 'عملة', 'عملات',
      'درهم', 'دولار', 'يورو', 'أسهم', 'سندات', 'شركة', 'شركات', 'أرباح', 'خسائر', 'ركود', 'ميزانية',
      'ضرائب', 'جمارك', 'عقارات', 'نفط', 'غاز', 'طاقة', 'صفقة', 'استحواذ', 'تمويل', 'قرض', 'ديون',
      // English
      'economy', 'economic', 'business', 'finance', 'financial', 'market', 'markets', 'stock',
      'stocks', 'shares', 'bank', 'banking', 'inflation', 'investment', 'investments', 'investor',
      'trade', 'trading', 'currency', 'revenue', 'profit', 'budget', 'gdp', 'recession', 'acquisition',
    ],
    'SPORT': [
      // Arabic phrases
      'كرة القدم', 'دوري أبطال', 'كأس العالم', 'كرة السلة', 'كرة المضرب', 'ركلة جزاء', 'ريال مدريد',
      'برشلونة', 'المنتخب الوطني', 'الدوري الإنجليزي', 'الدوري الإسباني', 'الدوري المغربي', 'نهائي كأس',
      'الدوري المحلي', 'كأس العرش', 'كأس أفريقيا', 'الجامعة الملكية',
      // Arabic single terms
      'رياضة', 'رياضي', 'رياضية', 'مباراة', 'مباريات', 'دوري', 'بطولة', 'كأس', 'منتخب', 'فريق',
      'فريقين', 'فرق', 'لاعب', 'لاعبين', 'مدرب', 'هدف', 'أهداف', 'ملعب', 'ملاعب', 'جولة', 'تصفيات',
      'فيفا', 'كاف', 'كان', 'تنس', 'سباق', 'أولمبياد', 'ميدالية', 'فوز', 'هزيمة', 'خسارة', 'تعادل',
      'شوط', 'حكم', 'تسلل', 'انتقالات', 'مهاجم', 'مدافع', 'حارس', 'هاتريك', 'كروي', 'كروية',
      // English
      'sports', 'sport', 'football', 'soccer', 'match', 'matches', 'tournament', 'championship',
      'league', 'cup', 'team', 'teams', 'player', 'players', 'coach', 'goal', 'goals', 'stadium',
      'fifa', 'champions league', 'world cup', 'olympics', 'medal', 'victory', 'defeat', 'tennis',
      'basketball', 'referee', 'penalty', 'transfer',
    ],
    'TECH': [
      // Arabic phrases
      'ذكاء اصطناعي', 'هاتف ذكي', 'هواتف ذكية', 'أمن سيبراني', 'بيانات ضخمة', 'حوسبة سحابية',
      'منصة رقمية', 'تطبيق ذكي', 'واقع معزز', 'واقع افتراضي', 'شات جي بي تي', 'أوبن إيه آي',
      // Arabic single terms
      'تقنية', 'تقنيات', 'تكنولوجيا', 'روبوت', 'روبوتات', 'حاسوب', 'كمبيوتر', 'هاتف', 'هواتف',
      'تطبيق', 'تطبيقات', 'برمجة', 'مبرمج', 'مطور', 'إنترنت', 'شبكة', 'قرصنة', 'اختراق',
      'خوارزمية', 'خوارزميات', 'سحابة', 'سحابي', 'رقائق', 'معالج', 'معالجات', 'أبل', 'جوجل',
      'مايكروسوفت', 'سامسونج', 'أندرويد', 'آيفون', 'ميتا', 'إلكترونيات', 'برمجيات', 'ابتكار رقمي',
      // English
      'technology', 'tech', 'technological', 'artificial intelligence', 'ai', 'robot', 'robotics',
      'smartphone', 'smartphones', 'computer', 'computers', 'software', 'hardware', 'cybersecurity',
      'algorithm', 'app', 'apps', 'application', 'applications', 'developer', 'programming',
      'internet', 'cloud', 'chip', 'chips', 'processor', 'digital', 'apple', 'google', 'microsoft',
      'samsung', 'android', 'iphone',
    ],
    'HEALTH': [
      // Arabic phrases
      'منظمة الصحة العالمية', 'وزارة الصحة', 'عملية جراحية', 'دراسة طبية', 'أبحاث طبية', 'لقاح كورونا',
      'صحة عامة', 'أمراض القلب', 'ضغط الدم', 'مرض السكري', 'طب وقائي', 'نظام صحي', 'علاج فعال',
      // Arabic single terms
      'صحة', 'صحي', 'صحية', 'طب', 'طبي', 'طبية', 'مستشفى', 'مستشفيات', 'طبيب', 'أطباء',
      'جراحة', 'جراح', 'دواء', 'أدوية', 'علاج', 'علاجات', 'مرض', 'أمراض', 'فيروس', 'فيروسات',
      'بكتيريا', 'وباء', 'أوبئة', 'جائحة', 'لقاح', 'لقاحات', 'تطعيم', 'سرطان', 'سكري', 'أعراض',
      'وقاية', 'تغذية', 'عيادة', 'صيدلية', 'جرعة', 'تشخيص', 'مريض', 'مرضى', 'إصابة', 'إصابات',
      // English
      'health', 'healthy', 'medicine', 'medical', 'hospital', 'hospitals', 'doctor', 'doctors',
      'physician', 'surgery', 'surgical', 'treatment', 'treatments', 'cure', 'disease', 'diseases',
      'illness', 'virus', 'viral', 'bacteria', 'pandemic', 'epidemic', 'vaccine', 'vaccines',
      'vaccination', 'cancer', 'diabetes', 'symptoms', 'diagnosis', 'patient', 'patients', 'clinical',
    ],
    'CULTURE': [
      // Arabic phrases
      'معرض الكتاب', 'جائزة نوبل للآداب', 'أمسية شعرية', 'التراث الثقافي', 'المعالم التاريخية',
      'الموقع الأثري', 'الفن التشكيلي', 'الأدب المغربي', 'الموسيقى الأندلسية',
      // Arabic single terms
      'ثقافة', 'ثقافي', 'ثقافية', 'أدب', 'أدبي', 'أدبية', 'كتاب', 'كتب', 'مؤلف', 'كاتب',
      'رواية', 'روايات', 'قصة', 'قصص', 'شعر', 'شاعر', 'شعراء', 'قصيدة', 'متحف', 'متاحف',
      'تراث', 'تاريخ', 'تاريخي', 'حضارة', 'حضارات', 'فكر', 'مفكر', 'فلسفة', 'فلسفي', 'لغة',
      'لغويات', 'آثار', 'أثري', 'مخطوطات', 'ندوة', 'مكتبة', 'فلكلور',
      // English
      'culture', 'cultural', 'literature', 'literary', 'book', 'books', 'author', 'writer',
      'novel', 'novels', 'poetry', 'poet', 'poem', 'museum', 'museums', 'heritage', 'history',
      'historical', 'civilization', 'philosophy', 'library', 'monument', 'folklore',
    ],
    'ENTERTAINMENT': [
      // Arabic phrases
      'مهرجان سينمائي', 'حفل غنائي', 'عرض مسرحي', 'شباك التذاكر', 'نجم سينمائي', 'صناع السينما',
      'أفلام وثائقية', 'مسلسلات رمضان', 'نجمة الغناء',
      // Arabic single terms
      'فن', 'فنون', 'فنان', 'فنانين', 'فنانة', 'سينما', 'سينمائي', 'فيلم', 'أفلام', 'مسلسل',
      'مسلسلات', 'دراما', 'درامي', 'تمثيل', 'ممثل', 'ممثلين', 'ممثلة', 'مخرج', 'إخراج',
      'موسيقى', 'موسيقي', 'أغنية', 'أغاني', 'مطرب', 'مغني', 'ألبوم', 'مسرح', 'مسرحية',
      'كوميديا', 'كوميدي', 'مشاهير', 'نجم', 'نجوم', 'ترفيه', 'ترفيهي', 'هوليوود', 'بوليود',
      'أوسكار', 'مهرجان كان', 'عروض فنية',
      // English
      'entertainment', 'art', 'arts', 'artist', 'artists', 'cinema', 'cinematic', 'movie',
      'movies', 'film', 'films', 'series', 'drama', 'actor', 'actors', 'actress', 'director',
      'music', 'musical', 'song', 'songs', 'singer', 'album', 'theatre', 'theater', 'play',
      'comedy', 'celebrity', 'celebrities', 'star', 'stars', 'hollywood', 'oscar', 'festival',
    ],
    'SCIENCE': [
      // Arabic phrases
      'بحث علمي', 'دراسة علمية', 'تغير مناخي', 'احتباس حراري', 'طاقة متجددة', 'وكالة ناسا',
      'قمر صناعي', 'تلسكوب جيمس ويب', 'علوم الفضاء', 'محطة الفضاء',
      // Arabic single terms
      'علم', 'علوم', 'علمي', 'علمية', 'عالم', 'علماء', 'بحث', 'أبحاث', 'دراسة', 'دراسات',
      'اكتشاف', 'اكتشافات', 'تجربة', 'تجارب', 'مختبر', 'مختبرات', 'فضاء', 'فلك', 'فلكي',
      'كوكب', 'كواكب', 'مجرة', 'نجوم', 'ناسا', 'فيزياء', 'كيمياء', 'بيولوجيا', 'جيولوجيا',
      'مناخ', 'بيئة', 'بيئي', 'جينات', 'وراثة', 'طاقة شمسية', 'كوانتم',
      // English
      'science', 'scientific', 'scientist', 'scientists', 'research', 'study', 'discovery',
      'experiment', 'laboratory', 'space', 'astronomy', 'planet', 'planets', 'galaxy',
      'nasa', 'physics', 'chemistry', 'biology', 'geology', 'climate', 'environment',
      'environmental', 'solar', 'quantum', 'genetics',
    ],
  };

  static Map<String, String> _nlpToAppCategory = {
    'POLITICS': 'politics',
    'ECONOMY': 'economy',
    'SPORT': 'sports',
    'TECH': 'technology',
    'HEALTH': 'health',
    'CULTURE': 'culture',
    'ARTS': 'entertainment',
    'ENTERTAINMENT': 'entertainment',
    'SCIENCE': 'science',
    'WORLD': 'general',
    'SOCIETY': 'culture',
    'WOMEN': 'culture',
    'FACTS': 'general',
    'ISLAMIC': 'culture',
    'VARIETIES': 'entertainment',
  };

  static bool _categoryMappingLoaded = false;
  static bool _categoryMappingLoading = false;

  /// Loads category mapping asynchronously in background without blocking classification
  static Future<void> loadCategoryMapping() async {
    if (_categoryMappingLoaded || _categoryMappingLoading) return;
    _categoryMappingLoading = true;
    try {
      final mapping = await ServerApiService.getCategoryMapping().timeout(const Duration(seconds: 3));
      if (mapping.isNotEmpty) {
        _nlpToAppCategory = Map<String, String>.from(_nlpToAppCategory)..addAll(mapping);
      }
      _categoryMappingLoaded = true;
    } catch (_) {
      _categoryMappingLoaded = true;
    } finally {
      _categoryMappingLoading = false;
    }
  }

  static String _normalizeAppCategory(String cat) {
    switch (cat.toLowerCase().trim()) {
      case 'business':
      case 'biz':
      case 'markets':
        return 'economy';
      case 'tech':
        return 'technology';
      case 'sport':
      case 'football':
        return 'sports';
      case 'general_news':
      case 'world':
      case 'international':
      case 'local':
        return 'general';
      case 'arts':
      case 'cinema':
        return 'entertainment';
      default:
        return cat.toLowerCase().trim();
    }
  }

  static String _mapNlpToApp(String nlpCategory) {
    final mapped = _nlpToAppCategory[nlpCategory] ?? 'general';
    return _normalizeAppCategory(mapped);
  }

  static Map<String, double> _translateNlpScoresToApp(Map<String, double> nlpScores) {
    final appScores = <String, double>{};
    for (final entry in nlpScores.entries) {
      final appCat = _mapNlpToApp(entry.key);
      appScores[appCat] = (appScores[appCat] ?? 0.0) + entry.value;
    }
    return appScores;
  }

  static ({String category, double confidence, Map<String, double> scores})? _getCachedClassification(
      String title, String content) {
    final t = _norm(title);
    final c = _norm(content);
    final key = '$t::$c';
    if (_classificationCache.containsKey(key)) {
      _classificationCacheKeys.remove(key);
      _classificationCacheKeys.add(key);
      final cached = _classificationCache[key];
      if (cached != null && cached is Map) {
        return (
          category: cached['category'] as String,
          confidence: (cached['confidence'] as num?)?.toDouble() ?? 0.0,
          scores: Map<String, double>.from(cached['scores'] as Map),
        );
      }
    }
    return null;
  }

  static void _cacheClassification(
      String title, String content, ({String category, double confidence, Map<String, double> scores}) result) {
    final t = _norm(title);
    final c = _norm(content);
    final key = '$t::$c';
    _classificationCache[key] = {
      'category': result.category,
      'confidence': result.confidence,
      'scores': result.scores,
    };
    _classificationCacheKeys.add(key);
    if (_classificationCacheKeys.length > _classificationCacheLimit) {
      final removeCount = _classificationCacheKeys.length ~/ 2;
      for (int i = 0; i < removeCount; i++) {
        final k = _classificationCacheKeys.removeAt(0);
        _classificationCache.remove(k);
      }
    }
  }

  static Future<IntelligenceResult> extractAsync(
      String title, String content, String summary, {List<String>? validCategoryIds}) async {
    if (!_categoryMappingLoaded) {
      unawaited(loadCategoryMapping());
    }
    return compute(IntelligenceResult._extract, IntelligenceInput(
      title: title,
      content: content,
      summary: summary,
      validCategoryIds: validCategoryIds,
    ));
  }

  static IntelligenceResult extract(
      String title, String content, String summary, {List<String>? validCategoryIds}) {
    return IntelligenceResult._extract(IntelligenceInput(
      title: title,
      content: content,
      summary: summary,
      validCategoryIds: validCategoryIds,
    ));
  }

  static Future<String> classifyCategory(String text, {String? url, List<String>? validCategoryIds, String? title}) async {
    if (!_categoryMappingLoaded) {
      unawaited(loadCategoryMapping());
    }
    return IntelligenceResult.determineCategory(text, url: url, validCategoryIds: validCategoryIds, title: title);
  }

  /// High-accuracy category scoring:
  /// - Extracts multi-word phrases (weighted higher)
  /// - Checks title words (2.5x weight) vs body words (1.0x weight)
  /// - Preserves Arabic and English tokens
  static Map<String, double> _calculateCategoryScores(String text, {String? title}) {
    if (text.isEmpty && (title == null || title.isEmpty)) return {};

    final normText = ArabicTextNormalizer.normalize(text).toLowerCase();
    final normTitle = title != null && title.isNotEmpty 
        ? ArabicTextNormalizer.normalize(title).toLowerCase() 
        : '';

    // Tokenize text into words with Arabic + Latin word characters
    final textWords = normText
        .replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && !ArabicTextNormalizer.isStopWord(w))
        .map((w) => ArabicTextNormalizer.stemSimple(w).trim())
        .where((w) => w.isNotEmpty)
        .toList();

    final titleWords = normTitle.isNotEmpty
        ? normTitle
            .replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ')
            .split(RegExp(r'\s+'))
            .where((w) => w.length >= 2 && !ArabicTextNormalizer.isStopWord(w))
            .map((w) => ArabicTextNormalizer.stemSimple(w).trim())
            .where((w) => w.isNotEmpty)
            .toSet()
        : <String>{};

    final bodyWordSet = textWords.toSet();
    final scores = <String, double>{};

    for (final entry in _categoryKeywords.entries) {
      final category = entry.key;
      double catScore = 0.0;

      for (final kw in entry.value) {
        final kwNorm = ArabicTextNormalizer.normalize(kw).toLowerCase().trim();
        if (kwNorm.isEmpty) continue;

        if (kwNorm.contains(' ')) {
          // Multi-word phrase matching
          if (normTitle.isNotEmpty && normTitle.contains(kwNorm)) {
            catScore += 4.5; // High priority for keyphrase in title
          } else if (normText.contains(kwNorm)) {
            catScore += 2.5; // Keyphrase in body
          }
        } else {
          // Single-word matching with stemmed normalization
          final kwStem = ArabicTextNormalizer.stemSimple(kwNorm).trim();
          if (titleWords.contains(kwStem) || titleWords.contains(kwNorm)) {
            catScore += 2.5; // Word in title
          } else if (bodyWordSet.contains(kwStem) || bodyWordSet.contains(kwNorm)) {
            catScore += 1.0; // Word in body
          }
        }
      }

      if (catScore > 0) {
        scores[category] = catScore;
      }
    }

    if (scores.isEmpty) return {};

    final maxScore = scores.values.fold<double>(0.0, math.max);
    if (maxScore == 0.0) return {};

    final normalized = <String, double>{};
    for (final entry in scores.entries) {
      normalized[entry.key] = entry.value / maxScore;
    }

    return normalized;
  }
}

class IntelligenceInput {
  final String title;
  final String content;
  final String summary;
  final List<String>? validCategoryIds;

  IntelligenceInput({
    required this.title,
    required this.content,
    required this.summary,
    this.validCategoryIds,
  });
}

class IntelligenceResult {
  final String category;
  final double sentiment;
  final String eventType;
  final String subcategory;
  final List<Entity> entities;
  final Map<String, dynamic> structuredData;

  IntelligenceResult({
    required this.category,
    required this.sentiment,
    required this.eventType,
    required this.subcategory,
    required this.entities,
    required this.structuredData,
  });

  static IntelligenceResult _extract(IntelligenceInput input) {
    final text = '${input.title} ${input.content} ${input.summary}';
    final normalizedText = ArabicTextNormalizer.normalize(text).toLowerCase();

    final category = determineCategory(
      normalizedText,
      validCategoryIds: input.validCategoryIds,
      title: input.title,
    );
    final sentiment = _calculateSentiment(normalizedText);
    final eventType = _determineEventType(normalizedText);
    final subcategory = _determineSubcategory(normalizedText);
    final entities = _extractEntities(normalizedText);
    final structuredData = <String, dynamic>{};

    return IntelligenceResult(
      category: category,
      sentiment: sentiment,
      eventType: eventType,
      subcategory: subcategory,
      entities: entities,
      structuredData: structuredData,
    );
  }

  static String determineCategory(
    String text, {
    String? url,
    List<String>? validCategoryIds,
    String? title,
  }) {
    final cached = NewsIntelligence._getCachedClassification(title ?? '', text);
    if (cached != null) return cached.category;

    final nlpScores = NewsIntelligence._calculateCategoryScores(text, title: title);
    if (nlpScores.isEmpty) {
      final fallback = _resolveFallback(validCategoryIds);
      return fallback;
    }

    // Soft URL hint boost (0.2 instead of 0.5) to break ties without overriding content
    if (url != null && url.isNotEmpty) {
      final urlLower = url.toLowerCase();
      final urlHints = {
        'SPORT': ['sports', 'رياضة', 'كرة', 'football', 'soccer'],
        'POLITICS': ['politics', 'سياسة', 'حكومة', 'parliament'],
        'ECONOMY': ['business', 'اقتصاد', 'مال', 'economy', 'finance', 'banking', 'bourse'],
        'TECH': ['tech', 'تقنية', 'تكنولوجيا', 'technology'],
        'HEALTH': ['health', 'صحة', 'طبي', 'medical'],
        'CULTURE': ['culture', 'ثقافة', 'livres', 'books'],
        'ENTERTAINMENT': ['entertainment', 'ترفيه', 'فن', 'arts', 'cinema', 'music', 'stars'],
        'SCIENCE': ['science', 'علم', 'علوم', 'espace', 'space'],
      };

      for (final entry in urlHints.entries) {
        final categoryName = entry.key;
        for (final hint in entry.value) {
          if (urlLower.contains(hint)) {
            nlpScores[categoryName] = (nlpScores[categoryName] ?? 0.0) + 0.2;
            break;
          }
        }
      }
    }

    final appScores = NewsIntelligence._translateNlpScoresToApp(nlpScores);
    if (appScores.isEmpty) {
      return _resolveFallback(validCategoryIds);
    }

    final validCategories = validCategoryIds ??
        (CategoryService.instance.initialized ? CategoryService.instance.categoryIds : null);

    final normalizedValid = validCategories?.map((c) => NewsIntelligence._normalizeAppCategory(c)).toSet();

    // Find the best match among valid categories if available
    String chosenCategory;
    double bestScore = 0.0;

    if (normalizedValid != null && normalizedValid.isNotEmpty) {
      final validEntries = appScores.entries.where((e) => normalizedValid.contains(e.key)).toList();
      if (validEntries.isNotEmpty) {
        final bestEntry = validEntries.reduce((a, b) => a.value >= b.value ? a : b);
        chosenCategory = bestEntry.key;
        bestScore = bestEntry.value;
      } else {
        final overallBest = appScores.entries.reduce((a, b) => a.value >= b.value ? a : b);
        chosenCategory = overallBest.key;
        bestScore = overallBest.value;
      }
    } else {
      final overallBest = appScores.entries.reduce((a, b) => a.value >= b.value ? a : b);
      chosenCategory = overallBest.key;
      bestScore = overallBest.value;
    }

    // Require minimum score to classify into a specialized category
    if (bestScore < 0.2) {
      chosenCategory = _resolveFallback(validCategoryIds);
    }

    NewsIntelligence._cacheClassification(title ?? '', text, (
      category: chosenCategory,
      confidence: bestScore,
      scores: appScores,
    ));

    return chosenCategory;
  }

  static String _resolveFallback(List<String>? validCategoryIds) {
    if (validCategoryIds != null && validCategoryIds.contains('general')) return 'general';
    if (validCategoryIds != null && validCategoryIds.isNotEmpty) return validCategoryIds.first;
    if (CategoryService.instance.initialized && CategoryService.instance.categoryIds.contains('general')) {
      return 'general';
    }
    return CategoryService.instance.initialized && CategoryService.instance.categoryIds.isNotEmpty
        ? CategoryService.instance.categoryIds.first
        : 'general';
  }

  static double _calculateSentiment(String text) {
    final positiveWords = {
      'good', 'great', 'excellent', 'positive', 'happy', 'joy', 'love', 'like',
      'amazing', 'wonderful', 'best', 'better', 'fantastic', 'terrific',
      'outstanding', 'superb', 'nice', 'perfect', 'brilliant', 'awesome',
      'نجاح', 'فوز', 'تطور', 'إيجابي', 'سعيد', 'ممتاز', 'جيد', 'ازدهار', 'انتصار',
    };
    final negativeWords = {
      'bad', 'terrible', 'awful', 'negative', 'sad', 'unhappy', 'hate', 'dislike',
      'horrible', 'worst', 'worse', 'disaster', 'fail', 'failure', 'poor', 'weak',
      'sick', 'ill', 'wrong', 'error', 'problem', 'issue', 'broken', 'damage',
      'crash', 'kill', 'die', 'dead', 'war', 'conflict',
      'فشل', 'خسارة', 'كارثة', 'سيء', 'أسوأ', 'حرب', 'صراع', 'موت', 'تدمير', 'أزمة',
    };

    int positiveCount = 0;
    int negativeCount = 0;
    final words = text
        .replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2);

    for (final word in words) {
      if (positiveWords.contains(word)) positiveCount++;
      if (negativeWords.contains(word)) negativeCount++;
    }

    final total = positiveCount + negativeCount;
    if (total == 0) return 0.0;
    return (positiveCount - negativeCount) / total;
  }

  static String _determineEventType(String text) {
    final lower = ArabicTextNormalizer.normalize(text).toLowerCase();
    if (lower.contains('war') || lower.contains('conflict') || lower.contains('attack') ||
        lower.contains('bomb') || lower.contains('shooting') ||
        lower.contains('حرب') || lower.contains('صراع') || lower.contains('هجوم') ||
        lower.contains('قنبلة') || lower.contains('إطلاق نار') || lower.contains('قصف') ||
        lower.contains('تدمير')) {
      return 'Conflict';
    }
    if (lower.contains('election') || lower.contains('vote') || lower.contains('campaign') ||
        lower.contains('انتخابات') || lower.contains('تصويت') || lower.contains('حملة') ||
        lower.contains('اقتراع') || lower.contains('ناخب')) {
      return 'Political';
    }
    if (lower.contains('match') || lower.contains('game') || lower.contains('tournament') ||
        lower.contains('مباراة') || lower.contains('لعبة') || lower.contains('بطولة') ||
        lower.contains('دوري') || lower.contains('كأس') || lower.contains('فريقين')) {
      return 'Sports';
    }
    if (lower.contains('concert') || lower.contains('festival') || lower.contains('show') ||
        lower.contains('حفل') || lower.contains('مهرجان') || lower.contains('عرض') ||
        lower.contains('فيلم') || lower.contains('سينما')) {
      return 'Entertainment';
    }
    return 'General';
  }

  static String _determineSubcategory(String text) {
    final lower = ArabicTextNormalizer.normalize(text).toLowerCase();
    if (lower.contains('football') || lower.contains('soccer') ||
        lower.contains('كرة قدم') || lower.contains('كورة') || lower.contains('كرة القدم')) {
      return 'Football';
    }
    if (lower.contains('basketball') || lower.contains('كرة سلة') || lower.contains('كرة السلة')) {
      return 'Basketball';
    }
    if (lower.contains('tennis') || lower.contains('كرة مضرب') || lower.contains('كرة المضرب')) {
      return 'Tennis';
    }
    if (lower.contains('politics') || lower.contains('government') ||
        lower.contains('سياسة') || lower.contains('حكومة') || lower.contains('انتخاب')) {
      return 'Politics';
    }
    if (lower.contains('technology') || lower.contains('tech') ||
        lower.contains('تقنية') || lower.contains('تكنولوجيا') || lower.contains('ذكاء اصطناعي') ||
        lower.contains('هاتف ذكي')) {
      return 'Technology';
    }
    if (lower.contains('health') || lower.contains('medical') ||
        lower.contains('صحة') || lower.contains('طبي') || lower.contains('علاج') ||
        lower.contains('مرض')) {
      return 'Health';
    }
    return 'General';
  }

  static List<Entity> _extractEntities(String text) {
    final entities = <Entity>[];

    final emailPattern = RegExp(r'\b[\w\.-]+@[\w\.-]+\.\w+\b');
    for (final match in emailPattern.allMatches(text)) {
      entities.add(Entity(type: 'email', value: match.group(0)!));
    }

    final phonePattern = RegExp(r'\b\d{3}[-.]?\d{3}[-.]?\d{4}\b');
    for (final match in phonePattern.allMatches(text)) {
      entities.add(Entity(type: 'phone', value: match.group(0)!));
    }

    final datePattern = RegExp(r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b');
    for (final match in datePattern.allMatches(text)) {
      entities.add(Entity(type: 'date', value: match.group(0)!));
    }

    final seen = <String>{};
    final uniqueEntities = <Entity>[];
    for (final entity in entities) {
      if (!seen.contains(entity.value)) {
        seen.add(entity.value);
        uniqueEntities.add(entity);
      }
    }

    return uniqueEntities;
  }
}

class Entity {
  final String type;
  final String value;

  Entity({
    required this.type,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'value': value,
      };
}

bool isLikelySectionPage(String url) {
  final lower = url.toLowerCase();
  if (lower.contains('/section/')) return true;
  if (lower.contains('/category/')) return true;
  if (lower.contains('/tag/')) return true;
  if (lower.contains('/page/')) return true;
  if (lower.contains('/channel/')) return true;
  if (lower.contains('#nav') ||
      lower.contains('#hpnavsec') ||
      lower.contains('#footer')) return true;
  if (lower.contains('google.com/preferences')) return true;
  return false;
}
