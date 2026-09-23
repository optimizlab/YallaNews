import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'arabic_normalizer.dart';
import 'category_service.dart';

class NewsIntelligence {
  static final Map<String, dynamic> _classificationCache = {};
  static final List<String> _classificationCacheKeys = [];
  static const int _classificationCacheLimit = 100;

  static String _norm(String text) => ArabicTextNormalizer.normalize(text);

  static ({String category, double confidence, Map<String, double> scores})? _getCachedClassification(String title, String content) {
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

  static void _cacheClassification(String title, String content, ({String category, double confidence, Map<String, double> scores}) result) {
    final t = _norm(title);
    final c = _norm(content);
    final key = '$t::$c';
    final cacheValue = {
      'category': result.category,
      'confidence': result.confidence,
      'scores': result.scores,
    };
    _classificationCache[key] = cacheValue;
    _classificationCacheKeys.add(key);
    if (_classificationCacheKeys.length > _classificationCacheLimit) {
      final removeCount = _classificationCacheKeys.length ~/ 2;
      for (int i = 0; i < removeCount; i++) {
        final k = _classificationCacheKeys.removeAt(0);
        _classificationCache.remove(k);
      }
    }
  }

  static Future<IntelligenceResult> extractAsync(String title, String content, String summary, {List<String>? validCategoryIds}) async {
    return compute(IntelligenceResult._extractFromInput, IntelligenceInput(
      title: title,
      content: content,
      summary: summary,
      validCategoryIds: validCategoryIds,
    ));
  }

  static IntelligenceResult extract(String title, String content, String summary, {List<String>? validCategoryIds}) {
    return IntelligenceResult._extractFromInput(IntelligenceInput(
      title: title,
      content: content,
      summary: summary,
      validCategoryIds: validCategoryIds,
    ));
  }

  static String classifyCategory(String text, {String? url, List<String>? validCategoryIds, String? titleOnly}) {
    return IntelligenceResult.determineCategory(text, url: url, validCategoryIds: validCategoryIds, titleOnly: titleOnly);
  }
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

  static IntelligenceResult _extractFromInput(IntelligenceInput input) {
    final text = '${input.title} ${input.content} ${input.summary}';
    final normalizedText = ArabicTextNormalizer.normalize(text).toLowerCase();

    final category = determineCategory(normalizedText, validCategoryIds: input.validCategoryIds);
    final sentiment = _calculateSentiment(normalizedText);
    final eventType = _determineEventType(normalizedText);
    final subcategory = _determineSubcategory(normalizedText);
    final entities = _extractEntities(text);
    final structuredData = <String, dynamic>{
      'sentiment_score': sentiment,
      'event_type': eventType,
      'subcategory': subcategory,
      'keywords_count': text.split(RegExp(r'\s+')).length,
    };

    return IntelligenceResult(
      category: category,
      sentiment: sentiment,
      eventType: eventType,
      subcategory: subcategory,
      entities: entities,
      structuredData: structuredData,
    );
  }

  /// Classify by scoring title tokens with 5× weight and body tokens with 1×.
  /// If the title alone is decisive (score ≥ 8) it wins; body noise cannot override it.
  static String determineCategory(String text,
      {String? url,
      List<String>? validCategoryIds,
      String? titleOnly}) {
    final categoryKeywords = <String, List<String>>{
      'sports': [
        'مباراة', 'لعبة', 'فريق', 'لاعب', 'هدف', 'بطولة', 'دوري', 'كأس', 'نتيجة',
        'رياضة', 'كرة', 'قدم', 'سلة', 'تنس', 'فوز', 'خسارة', 'مدرب', 'ملعب',
        'معلق', 'حكم', 'الدوري', 'الألماني', 'الإسباني', 'الإنجليزي', 'الإيطالي',
        'لايبزيغ', 'ريال مدريد', 'برشلونة', 'المرابط', 'حكيمي', 'صلاح', 'ميسي',
        'رونالدو', 'انتقالات', 'صفقة', 'منتخب', 'أهداف', 'الكان', 'المونديال',
        'pass', 'goal', 'match', 'game', 'team', 'player', 'score', 'league',
        'cup', 'championship', 'tournament', 'stadium', 'coach', 'victory',
        'defeat', 'referee', 'sport', 'bundesliga', 'laliga', 'premier', 'fifa',
      ],
      'politics': [
        'حكومة', 'انتخابات', 'رئيس', 'وزير', 'برلمان', 'قانون', 'سياسة', 'تصويت',
        'حملة', 'حزب', 'أحزاب', 'دبلوماسي', 'سفارة', 'احتجاج', 'حقوقي', 'تنديد',
        'وزراء', 'مجلس النواب', 'مستشارين', 'دستور', 'اتفاقية', 'معاهدة', 'معارضة',
        'بيان رسمي', 'قمة', 'أمم متحدة', 'انقلاب', 'سياسي', 'صراع سياسي',
        'government', 'election', 'president', 'minister', 'parliament', 'law',
        'policy', 'vote', 'campaign', 'treaty', 'sanction', 'diplomat', 'embassy',
        'protest', 'coup', 'politics', 'opposition', 'cabinet', 'senate',
      ],
      'business': [
        'اقتصاد', 'سوق', 'أسهم', 'مال', 'شركة', 'استثمار', 'تجارة', 'صناعة',
        'بنك', 'نفط', 'غاز', 'سعر', 'تضخم', 'إيرادات', 'أرباح', 'خسائر', 'أعمال',
        'عقارات', 'تداول', 'بورصة', 'صادرات', 'واردات', 'تمويل', 'قرض', 'فائدة',
        'درهم', 'دولار', 'يورو', 'تأمين', 'تعويضات', 'مستهلك', 'أسعار',
        'business', 'economy', 'market', 'stock', 'finance', 'company',
        'investment', 'trade', 'industry', 'bank', 'oil', 'gas', 'price',
        'inflation', 'revenue', 'profit', 'loss', 'startup', 'real estate',
      ],
      'technology': [
        'تقنية', 'تكنولوجيا', 'برمجيات', 'حاسوب', 'هاتف', 'تطبيق', 'ذكاء اصطناعي',
        'روبوت', 'إنترنت', 'رقمي', 'بيانات', 'سيبر', 'شركة ناشئة', 'جهاز', 'شاشة',
        'رقاقة', 'شفرة', 'خوارزمية', 'أمن سيبراني', 'سحابة', 'منصة', 'تحديث',
        'tech', 'software', 'hardware', 'computer', 'phone', 'app', 'ai',
        'robot', 'internet', 'digital', 'data', 'cyber', 'startup', 'device',
        'chip', 'code', 'programming', 'cloud', 'algorithm',
      ],
      'health': [
        'صحة', 'طبي', 'طب', 'مستشفى', 'مرض', 'لقاح', 'دكتور', 'طبيب', 'مريض',
        'عيادة', 'دواء', 'أدوية', 'فيروس', 'جائحة', 'علاج', 'جراحة', 'نفسي',
        'لياقة', 'نظام غذائي', 'صيدلية', 'تمريض', 'عدوى', 'أطباء', 'منظومة صحية',
        'health', 'medical', 'hospital', 'disease', 'vaccine', 'doctor',
        'patient', 'clinic', 'medicine', 'virus', 'pandemic', 'treatment',
        'surgery', 'mental', 'fitness', 'diet', 'pharma', 'infection',
      ],
      'science': [
        'علم', 'بحث', 'دراسة', 'اكتشاف', 'تجربة', 'عالم', 'مختبر', 'نظرية',
        'فضاء', 'كوكب', 'مناخ', 'طاقة', 'فيزياء', 'كيمياء', 'أحياء', 'فلك',
        'بيئة', 'احتباس حراري', 'تلسكوب', 'ناسا', 'طبيعة',
        'science', 'research', 'study', 'discovery', 'experiment', 'scientist',
        'laboratory', 'theory', 'space', 'planet', 'climate', 'energy', 'physics',
        'chemistry', 'biology', 'astronomy', 'nasa',
      ],
      'entertainment': [
        'فيلم', 'سينما', 'موسيقى', 'مغني', 'فنان', 'عرض', 'تلفزيون', 'حفل',
        'مهرجان', 'ترفيه', 'فن', 'ممثل', 'ممثلة', 'مخرج', 'مسرح', 'كوميديا',
        'دراما', 'مسلسل', 'أغنية', 'ثقافة', 'رواية', 'شعر', 'معرض',
        'movie', 'film', 'music', 'celebrity', 'star', 'show', 'tv', 'concert',
        'festival', 'actor', 'actress', 'director', 'theater', 'comedy', 'drama',
        'series', 'entertainment', 'culture', 'art', 'arts',
      ],
      'world': [
        'دولي', 'العالم', 'فلسطين', 'غزة', 'القدس', 'السودان', 'أوكرانيا', 'روسيا',
        'أمريكا', 'واشنطن', 'بكين', 'الصين', 'أوروبا', 'الشرق الأوسط', 'الأمم المتحدة',
        'مجلس الأمن', 'طوفان', 'حرب عالمية', 'دولية', 'خارجية',
        'world', 'international', 'global', 'palestine', 'gaza', 'ukraine',
        'russia', 'un', 'middle east', 'foreign',
      ],
    };

    // Pre-process texts by replacing all non-alphanumeric chars with spaces to ensure clean word boundaries
    final cleanTitle = (titleOnly ?? '').replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').toLowerCase();
    final paddedTitle = ' $cleanTitle ';
    
    final cleanText = text.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').toLowerCase();
    final paddedText = ' $cleanText ';

    // Helper to build a robust word-matching regex that handles common Arabic prefixes and suffixes
    RegExp buildWordRegex(String kw) {
      return RegExp(r' (?:ال|و|ف|ب|ك|ل)?' + RegExp.escape(kw.toLowerCase()) + r'(?:ات|ين|ون|ة|ه|هم|ها|ي)? ', caseSensitive: false);
    }

    // ── Step 1: score title separately (5× weight) ───────────────────────────
    final titleScores = <String, int>{};
    if (cleanTitle.trim().isNotEmpty) {
      for (final entry in categoryKeywords.entries) {
        int ts = 0;
        for (final kw in entry.value) {
          if (buildWordRegex(kw).hasMatch(paddedTitle)) {
            ts += (kw.length > 4 ? 2 : 1) * 5; // 5× weight
          }
        }
        if (ts > 0) titleScores[entry.key] = ts;
      }
    }

    // ── Step 2: score full text (title already included, weight 1×) ──────────
    final scores = <String, int>{};
    for (final entry in categoryKeywords.entries) {
      final categoryName = entry.key;
      int score = 0;

      for (final kw in entry.value) {
        final matches = buildWordRegex(kw).allMatches(paddedText).length;
        if (matches > 0) {
          score += matches * (kw.length > 4 ? 2 : 1);
        }
      }

      if (score > 0) {
        scores[categoryName] = score;
      }
    }

    // ── Step 3: if title gives a decisive signal, trust it alone ─────────────
    if (titleScores.isNotEmpty) {
      final bestTitleEntry = titleScores.entries.reduce((a, b) => a.value >= b.value ? a : b);
      // Decisive = top title score ≥ 8 AND at least 2× second best
      final sortedTitle = titleScores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final topTitleScore = sortedTitle.first.value;
      final secondTitleScore = sortedTitle.length > 1 ? sortedTitle[1].value : 0;
      if (topTitleScore >= 8 && topTitleScore >= secondTitleScore * 2) {
        // Title is decisive — return directly without body interference
        return _resolveToValidCategory(bestTitleEntry.key, validCategoryIds, categoryKeywords);
      }
    }

    if (url != null && url.isNotEmpty) {
      final urlLower = url.toLowerCase();
      final urlHints = {
        'sports': ['sports', 'sport', 'رياضة', 'كرة', 'koora', 'foot', 'botola'],
        'politics': ['politics', 'politic', 'سياسة', 'حكومة', 'parliament', 'nation'],
        'business': ['business', 'اقتصاد', 'مال', 'economy', 'finance', 'eco', 'bourse'],
        'technology': ['tech', 'تقنية', 'تكنولوجيا', 'it', 'digital'],
        'health': ['health', 'صحة', 'طبي', 'sante', 'med'],
        'entertainment': ['entertainment', 'ترفيه', 'فن', 'art', 'culture', 'cinema'],
        'science': ['science', 'علم', 'sciences'],
        'world': ['world', 'international', 'monde', 'دولي'],
      };

      for (final entry in urlHints.entries) {
        final categoryName = entry.key;
        final hints = entry.value;
        for (final hint in hints) {
          if (urlLower.contains(hint)) {
            scores[categoryName] = (scores[categoryName] ?? 0) + 6;
            break;
          }
        }
      }
    }

    // ── Step 4: blend title scores (4×) into body scores ────────────────────
    // Even when title is not decisively clear, amplify it in the blend.
    for (final entry in titleScores.entries) {
      scores[entry.key] = (scores[entry.key] ?? 0) + entry.value * 4;
    }

    String bestMatch = 'general';
    if (scores.isNotEmpty) {
      bestMatch = scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    // Mapping table between English category names and Arabic/multi-lingual category IDs
    final categoryAliases = <String, List<String>>{
      'sports': ['sports', 'رياضة', 'كرة القدم', 'كرة السلة', 'تنس', 'sport', 'football'],
      'politics': ['politics', 'سياسة', 'أخبار محلية', 'أخبار دولية', 'politic', 'political'],
      'business': ['business', 'اقتصاد', 'أعمال', 'أسواق ومال', 'عقارات', 'economy', 'finance'],
      'technology': ['technology', 'تكنولوجيا', 'تقنية', 'علوم وتكنولوجيا', 'tech'],
      'health': ['health', 'صحة', 'طب وصحة', 'علوم وطب', 'medical'],
      'entertainment': ['entertainment', 'ترفيه', 'فن', 'ثقافة', 'منوعات', 'فن وموسيقى', 'culture'],
      'science': ['science', 'علوم', 'علم', 'أبحاث'],
      'world': ['world', 'أخبار دولية', 'دولي', 'العالم', 'international'],
      'general': ['general', 'general_news', 'أخبار عامة', 'عام', 'الكل'],
    };

    final validCategories = validCategoryIds ??
        (CategoryService.instance.initialized ? CategoryService.instance.categoryIds : null);

    if (validCategories != null && validCategories.isNotEmpty) {
      // 1. Direct match with bestMatch
      for (final validCat in validCategories) {
        if (validCat.toLowerCase() == bestMatch.toLowerCase()) {
          return validCat;
        }
      }

      // 2. Alias match with validCategories
      final aliases = categoryAliases[bestMatch] ?? [];
      for (final validCat in validCategories) {
        final validLower = validCat.toLowerCase().trim();
        for (final alias in aliases) {
          if (validLower == alias.toLowerCase() || validLower.contains(alias.toLowerCase()) || alias.toLowerCase().contains(validLower)) {
            return validCat;
          }
        }
      }

      // 3. Score all validCategories directly against aliases
      for (final entry in categoryAliases.entries) {
        if (scores.containsKey(entry.key)) {
          for (final validCat in validCategories) {
            final validLower = validCat.toLowerCase().trim();
            for (final alias in entry.value) {
              if (validLower == alias.toLowerCase()) {
                return validCat;
              }
            }
          }
        }
      }
    }

    return _resolveToValidCategory(bestMatch, validCategoryIds, categoryAliases);
  }

  /// Maps an internal category name to a valid category ID from the available list.
  static String _resolveToValidCategory(
      String bestMatch,
      List<String>? validCategoryIds,
      Map<String, List<String>> categoryAliases) {
    final validCategories = validCategoryIds ??
        (CategoryService.instance.initialized ? CategoryService.instance.categoryIds : null);

    if (validCategories == null || validCategories.isEmpty) return bestMatch;

    // 1. Direct match
    for (final validCat in validCategories) {
      if (validCat.toLowerCase() == bestMatch.toLowerCase()) return validCat;
    }
    // 2. Alias match
    final aliases = categoryAliases[bestMatch] ?? [];
    for (final validCat in validCategories) {
      final vl = validCat.toLowerCase().trim();
      for (final alias in aliases) {
        if (vl == alias.toLowerCase() ||
            vl.contains(alias.toLowerCase()) ||
            alias.toLowerCase().contains(vl)) {
          return validCat;
        }
      }
    }
    return bestMatch;
  }

  static double _calculateSentiment(String text) {
    final positiveWords = [
      'ممتاز', 'رائع', 'جيد', 'إيجابي', 'سعيد', 'فرح', 'حب', 'نجاح', 'ناجح',
      'انتصار', 'فوز', 'تطور', 'تقدم', 'إنجاز', 'أمل', 'سلام', 'أمان', 'استقرار',
      'احتفال', 'تكريم', 'جائزة', 'افتتاح', 'إطلاق', 'تعاون', 'شراكة', 'شراكات',
      'ازدهار', 'نمو', 'خير', 'بركة', 'مساعدة', 'دعم', 'توافق', 'اتفاق', 'اتفاقية',
      'حل', 'إصلاح', 'تحسين', 'ارتفاع', 'زيادة', 'قوي', 'قوة', 'نهضة', 'شكر',
      'ترحيب', 'إشادة', 'تتويج', 'تميز', 'تفوق', 'أفضل', 'مكسب', 'ارتقاء', 'بناء',
      'good', 'great', 'excellent', 'positive', 'happy', 'joy', 'love', 'like',
      'amazing', 'wonderful', 'best', 'better', 'fantastic', 'terrific',
      'outstanding', 'superb', 'nice', 'fine', 'perfect', 'brilliant',
      'awesome', 'cool', 'sweet', 'lovely', 'success', 'win', 'victory',
      'achieve', 'progress', 'improve', 'growth', 'benefit', 'hope', 'peace',
      'safe', 'secure', 'celebrate', 'honor', 'award', 'launch', 'new',
    ];

    final negativeWords = [
      'سيئ', 'فظيع', 'سلبي', 'حزين', 'كره', 'كارثة', 'فشل', 'فقر', 'مرض', 'أمراض',
      'خطأ', 'مشكلة', 'أزمة', 'أزمات', 'خراب', 'ضرر', 'أضرار', 'حادث', 'حوادث',
      'قتل', 'موت', 'وفاة', 'وفيات', 'مقتل', 'اغتيال', 'حرب', 'حروب', 'صراع',
      'هجوم', 'اعتداء', 'انهيار', 'خسارة', 'خسائر', 'خطر', 'مخاطر', 'تهديد',
      'عنف', 'جريمة', 'جرائم', 'فساد', 'فضيحة', 'فضائح', 'احتجاج', 'احتجاجات',
      'توتر', 'خوف', 'قلق', 'أذى', 'اعتقال', 'إدانة', 'إصابة', 'إصابات',
      'ضحية', 'ضحايا', 'إرهاب', 'إرهابي', 'تدمير', 'نزيف', 'معاناة', 'شكوى',
      'bad', 'terrible', 'awful', 'negative', 'sad', 'unhappy', 'hate',
      'horrible', 'worst', 'worse', 'disaster', 'fail', 'failure', 'poor',
      'sick', 'ill', 'wrong', 'error', 'problem', 'issue', 'broken', 'damage',
      'crash', 'kill', 'die', 'dead', 'war', 'conflict', 'attack', 'bomb',
      'crisis', 'collapse', 'loss', 'danger', 'risk', 'threat', 'violence',
      'crime', 'corruption', 'scandal', 'protest', 'tension', 'fear',
    ];

    int positiveCount = 0;
    int negativeCount = 0;
    final words = text.split(RegExp(r'\s+'));
    for (final word in words) {
      final w = word.replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '');
      if (w.isEmpty) continue;
      if (positiveWords.contains(w)) positiveCount++;
      if (negativeWords.contains(w)) negativeCount++;
    }

    final total = positiveCount + negativeCount;
    if (total == 0) return 0.0;
    return ((positiveCount - negativeCount) / total).clamp(-1.0, 1.0);
  }

  static String _determineEventType(String text) {
    if (text.contains('حرب') || text.contains('صراع') || text.contains('هجوم') ||
        text.contains('قنبلة') || text.contains('إطلاق نار') || text.contains('قصف') ||
        text.contains('war') || text.contains('conflict') || text.contains('attack')) {
      return 'Conflict';
    }
    if (text.contains('انتخابات') || text.contains('تصويت') || text.contains('حملة') ||
        text.contains('برلمان') || text.contains('حكومة') || text.contains('وزير') ||
        text.contains('election') || text.contains('vote') || text.contains('politics')) {
      return 'Political';
    }
    if (text.contains('مباراة') || text.contains('بطولة') || text.contains('دوري') ||
        text.contains('كأس') || text.contains('لاعب') || text.contains('فريق') ||
        text.contains('match') || text.contains('game') || text.contains('tournament')) {
      return 'Sports';
    }
    if (text.contains('اقتصاد') || text.contains('استثمار') || text.contains('أسهم') ||
        text.contains('بنك') || text.contains('أرباح') || text.contains('تضخم') ||
        text.contains('business') || text.contains('economy') || text.contains('market')) {
      return 'Economic';
    }
    if (text.contains('حفل') || text.contains('مهرجان') || text.contains('سينما') ||
        text.contains('مسرح') || text.contains('فيلم') || text.contains('معرض') ||
        text.contains('concert') || text.contains('festival') || text.contains('show')) {
      return 'Entertainment';
    }
    if (text.contains('صحة') || text.contains('مستشفى') || text.contains('مرض') ||
        text.contains('لقاح') || text.contains('علاج') || text.contains('دواء')) {
      return 'Health';
    }
    return 'General';
  }

  static String _determineSubcategory(String text) {
    if (text.contains('كرة قدم') || text.contains('دوري') || text.contains('كأس') ||
        text.contains('football') || text.contains('soccer') || text.contains('لايبزيغ') ||
        text.contains('ريال مدريد') || text.contains('برشلونة')) return 'Football';
    if (text.contains('كرة سلة') || text.contains('basketball')) return 'Basketball';
    if (text.contains('تنس') || text.contains('tennis')) return 'Tennis';
    if (text.contains('سياسة') || text.contains('برلمان') || text.contains('حكومة')) return 'Politics';
    if (text.contains('ذكاء اصطناعي') || text.contains('ai') || text.contains('تطبيق') ||
        text.contains('هاتف') || text.contains('تقنية')) return 'Technology';
    if (text.contains('صحة') || text.contains('طبي') || text.contains('مستشفى')) return 'Health';
    if (text.contains('عقارات') || text.contains('أسواق') || text.contains('بورصة')) return 'Finance';
    return 'General';
  }

  static List<Entity> _extractEntities(String text) {
    final entities = <Entity>[];
    final seen = <String>{};

    // Named Persons with Arabic Title Prefixes
    final personPrefixRegex = RegExp(
      r'(?:الملك|الرئيس|الوزير|اللاعب|المدرب|الدكتور|السيد|المسؤول|المستشار|النائب|الأمين العام|الأستاذ|البطل)\s+([ء-ي]{2,15}(?:\s+[ء-ي]{2,15}){1,3})',
    );
    for (final match in personPrefixRegex.allMatches(text)) {
      final name = match.group(1)?.trim();
      if (name != null && name.length >= 3 && !seen.contains(name)) {
        seen.add(name);
        entities.add(Entity(type: 'person', value: name));
      }
    }

    // Well known Arabic persons/figures
    final knownFigures = [
      'محمد السادس', 'عزيز أخنوش', 'فوزي لقجع', 'وليد الركراكي', 'أشرف حكيمي',
      'سمير المرابط', 'حكيم زياش', 'محمد صلاح', 'سفيان أمرابط', 'ياسين بونو',
      'عبد الإله ابن كيران', 'ناصر بوريطة', 'عبد اللطيف لوديي', 'محمد بن سلمان',
      'تميم بن حمد', 'محمد بن زايد', 'عبد الفتاح السيسي', 'جو بايدن', 'دونالد ترامب',
      'إيمانويل ماكرون', 'فلاديمير بوتين', 'بنيامين نتنياهو',
    ];
    for (final figure in knownFigures) {
      if (text.contains(figure) && !seen.contains(figure)) {
        seen.add(figure);
        entities.add(Entity(type: 'person', value: figure));
      }
    }

    // Organizations
    final orgPrefixRegex = RegExp(
      r'(?:نادي|فريق|حكومة|وزارة|جامعة|برلمان|شركة|بنك|محكمة|منظمة|حزب|مجلس|اتحاد|جمعية|وكالة)\s+([ء-ي]{2,20}(?:\s+[ء-ي]{2,20}){1,3})',
    );
    for (final match in orgPrefixRegex.allMatches(text)) {
      final org = match.group(0)?.trim();
      if (org != null && org.length >= 4 && !seen.contains(org)) {
        seen.add(org);
        entities.add(Entity(type: 'organization', value: org));
      }
    }

    // Well known Organizations
    final knownOrgs = [
      'الأمم المتحدة', 'مجلس الأمن', 'الجامعة العربية', 'الاتحاد الإفريقي',
      'الاتحاد الأوروبي', 'الفيفا', 'الكاف', 'صندوق النقد الدولي', 'البنك الدولي',
      'الوداد', 'الرجاء', 'الجيش الملكي', 'ريال مدريد', 'برشلونة', 'لايبزيغ',
      'باريس سان جيرمان', 'مانشستر سيتي', 'ليفربول', 'الأهلي', 'الهلال',
    ];
    for (final org in knownOrgs) {
      if (text.contains(org) && !seen.contains(org)) {
        seen.add(org);
        entities.add(Entity(type: 'organization', value: org));
      }
    }

    // Locations
    final locations = [
      'الرباط', 'الدار البيضاء', 'مراكش', 'طنجة', 'فاس', 'أكادير', 'تطوان',
      'وجدة', 'مكناس', 'العيون', 'المغرب', 'الجزائر', 'تونس', 'مصر', 'السعودية',
      'الإمارات', 'قطر', 'فلسطين', 'غزة', 'القدس', 'القاهرة', 'الرياض', 'دبي',
      'الدوحة', 'باريس', 'مدريد', 'لندن', 'برلين', 'واشنطن', 'نيويورك', 'موسكو',
      'بكين', 'ألمانيا', 'إسبانيا', 'فرنسا', 'إنجلترا', 'إيطاليا',
    ];
    for (final loc in locations) {
      if (text.contains(loc) && !seen.contains(loc)) {
        seen.add(loc);
        entities.add(Entity(type: 'location', value: loc));
      }
    }

    // Dates
    final datePattern = RegExp(r'\b\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}\b|\b\d{4}[/\-.]\d{1,2}[/\-.]\d{1,2}\b');
    for (final match in datePattern.allMatches(text)) {
      final date = match.group(0)!;
      if (!seen.contains(date)) {
        seen.add(date);
        entities.add(Entity(type: 'date', value: date));
      }
    }

    return entities;
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

  factory Entity.fromJson(Map<String, dynamic> json) => Entity(
        type: json['type'] as String? ?? 'general',
        value: json['value'] as String? ?? '',
      );
}