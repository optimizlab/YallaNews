import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'arabic_normalizer.dart';
import 'category_service.dart';

class NewsIntelligence {
  static final Map<String, dynamic> _classificationCache = {};
  static final List<String> _classificationCacheKeys = [];
  static const int _classificationCacheLimit = 100;

  static String _norm(String text) => ArabicTextNormalizer.normalize(text);

  static const Map<String, List<String>> _categoryKeywords = {
    'CULTURE': ['ثقافة', 'كتاب', 'متحف', 'فنون', 'أدب', 'فنان', 'معرض', 'مسرح', 'سينما', 'رواية', 'شاعر', 'ناقد'],
    'ECONOMY': ['اقتصاد', 'مال', 'سوق', 'بنك', 'استثمار', 'تجارة', 'عملة', 'أسعار', 'شركة', 'نمو', 'تضخم', 'ميزانية'],
    'ARTS': ['فن', 'رسم', 'موسيقى', 'غناء', 'مسرح', 'سينما', 'فنان', 'لوحة', 'عرض', 'جallery', 'معرض فني'],
    'FACTS': ['حوادث', 'جريمة', 'حريق', 'accident', 'حادث', 'سرقة', 'قتل', 'اصابة', 'تحقيق', 'قضية'],
    'HEALTH': ['صحة', 'طب', 'مستشفى', 'دواء', 'مرض', 'علاج', 'فيروس', 'لقاح', 'طبيب', 'وباء', 'وزارة الصحة'],
    'ISLAMIC': ['إسلام', 'مسجد', 'صلاة', 'قرآن', 'حديث', 'رمضان', 'حج', 'زكاة', 'زكاة', 'مسلم'],
    'POLITICS': ['سياسة', 'حكومة', 'رئيس', 'وزير', 'برلمان', 'انتخاب', 'حزب', 'قانون', 'دستور', 'مجلس نواب', 'وزارة'],
    'SOCIETY': ['مجتمع', 'عائلة', 'تعليم', 'شباب', 'مرأة', 'طفل', 'مدرسة', 'جامعة', 'زواج', 'طلاق', 'حماية الطفل'],
    'SPORT': ['رياضة', 'كرة', 'مباراة', 'فريق', 'لاعب', 'هدف', 'بطولة', 'دوري', 'كأس', 'ملعب', 'اتحاد'],
    'TECH': ['تقنية', 'تكنولوجيا', 'حاسوب', 'هاتف', 'إنترنت', 'ذكاء اصطناعي', 'روبوت', 'تطبيق', 'تطبيقات', 'برمجة'],
    'VARIETIES': ['منوعات', 'غريب', 'عجيب', 'ظريف', 'مضحك', 'نصيحة', 'وصفة', 'ترفيه'],
    'WOMEN': ['مرأة', 'أنثى', 'جمال', 'موضة', 'أزياء', 'زينة', 'makeup', 'عائلة', 'حواء'],
    'WORLD': ['العالم', 'دولي', 'أمريكا', 'أوروبا', 'آسيا', 'أفريقيا', 'شرق أوسط', 'أمريكي', 'أوروبي'],
    'SCIENCE': ['علم', 'بحث', 'دراسة', 'اكتشاف', 'تجربة', 'مختبر', 'فضاء', 'كوكب', 'فيزياء', 'كيمياء', 'بيولوجيا'],
  };

  static const Map<String, String> _nlpToAppCategory = {
    'CULTURE': 'entertainment',
    'ECONOMY': 'business',
    'ARTS': 'entertainment',
    'FACTS': 'general',
    'HEALTH': 'health',
    'ISLAMIC': 'local',
    'POLITICS': 'politics',
    'SOCIETY': 'local',
    'SPORT': 'sports',
    'TECH': 'technology',
    'VARIETIES': 'entertainment',
    'WOMEN': 'local',
    'WORLD': 'world',
    'SCIENCE': 'science',
  };

  static String _mapNlpToApp(String nlpCategory) {
    return _nlpToAppCategory[nlpCategory] ?? 'general';
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

  static String classifyCategory(String text, {String? url, List<String>? validCategoryIds}) {
    return IntelligenceResult.determineCategory(text, url: url, validCategoryIds: validCategoryIds);
  }

  static Map<String, double> _naiveBayesCategoryScores(String text) {
    final words = ArabicTextNormalizer.split(text);
    if (words.isEmpty) return {};

    final normalizedWords = words.map((w) => ArabicTextNormalizer.normalize(w).toLowerCase()).toList();
    final totalDocs = _categoryKeywords.length;
    final scores = <String, double>{};

    for (final entry in _categoryKeywords.entries) {
      final category = entry.key;
      final keywords = entry.value.map((k) => ArabicTextNormalizer.normalize(k).toLowerCase()).toList();

      int matchCount = 0;
      int totalWords = normalizedWords.length;
      
      for (final word in normalizedWords) {
        for (final kw in keywords) {
          if (word == kw || word.contains(kw) || kw.contains(word)) {
            matchCount++;
            break;
          }
        }
      }

      if (totalWords == 0) {
        scores[category] = 0.0;
        continue;
      }

      double rawScore = matchCount / totalWords;
      if (rawScore > 0) {
        rawScore = rawScore * math.log(totalWords + 1);
      }
      
      scores[category] = rawScore;
    }

    final maxScore = scores.values.fold<double>(0.0, math.max);
    if (maxScore == 0.0) {
      return {};
    }

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

    final category = determineCategory(normalizedText, validCategoryIds: input.validCategoryIds);
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

  static String determineCategory(String text, {String? url, List<String>? validCategoryIds}) {
    final nlpScores = NewsIntelligence._naiveBayesCategoryScores(text);
    if (nlpScores.isEmpty) {
      final fallback = validCategoryIds?.firstOrNull ??
          (CategoryService.instance.initialized ? CategoryService.instance.categoryIds.firstOrNull : null) ??
          'general';
      return fallback;
    }

    if (url != null && url.isNotEmpty) {
      final urlLower = url.toLowerCase();
      final urlHints = {
        'SPORT': ['sports', 'رياضة', 'كرة'],
        'POLITICS': ['politics', 'سياسة', 'حكومة', 'parliament', 'local'],
        'ECONOMY': ['business', 'اقتصاد', 'مال', 'economy', 'finance', 'banking'],
        'TECH': ['tech', 'تقنية', 'تكنولوجيا'],
        'HEALTH': ['health', 'صحة', 'طبي'],
        'ARTS': ['entertainment', 'ترفيه', 'فن', 'movie', 'travel', 'tourism', 'fashion'],
        'SCIENCE': ['science', 'علم'],
      };

      for (final entry in urlHints.entries) {
        final categoryName = entry.key;
        final hints = entry.value;
        for (final hint in hints) {
          if (urlLower.contains(hint)) {
            nlpScores[categoryName] = (nlpScores[categoryName] ?? 0) + 0.5;
            break;
          }
        }
      }
    }

    final appScores = NewsIntelligence._translateNlpScoresToApp(nlpScores);
    if (appScores.isEmpty) {
      final fallback = validCategoryIds?.firstOrNull ??
          (CategoryService.instance.initialized ? CategoryService.instance.categoryIds.firstOrNull : null) ??
          'general';
      return fallback;
    }

    final bestAppMatch = appScores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final bestScore = appScores[bestAppMatch] ?? 0.0;

    final validCategories = validCategoryIds ??
        (CategoryService.instance.initialized ? CategoryService.instance.categoryIds : null);

    if (bestScore >= 0.1) {
      if (validCategories != null && validCategories.isNotEmpty) {
        final validEntries = appScores.entries.where((e) => validCategories.contains(e.key)).toList();
        if (validEntries.isNotEmpty) {
          final chosen = validEntries.reduce((a, b) => a.value >= b.value ? a : b).key;
          NewsIntelligence._cacheClassification(text, text, (
            category: chosen,
            confidence: bestScore,
            scores: appScores,
          ));
          return chosen;
        }
      }
      NewsIntelligence._cacheClassification(text, text, (
        category: bestAppMatch,
        confidence: bestScore,
        scores: appScores,
      ));
      return bestAppMatch;
    }

    if (validCategories != null && validCategories.isNotEmpty) {
      final validWithScores = appScores.entries
          .where((e) => validCategories.contains(e.key))
          .toList();
      if (validWithScores.isNotEmpty) {
        return validWithScores.reduce((a, b) => a.value >= b.value ? a : b).key;
      }
      return validCategories.first;
    }

    return 'general';
  }

  static double _calculateSentiment(String text) {
    final positiveWords = [
      'good', 'great', 'excellent', 'positive', 'happy', 'joy', 'love', 'like',
      'amazing', 'wonderful', 'best', 'better', 'fantastic', 'terrific',
      'outstanding', 'superb', 'nice', 'fine', 'okay', 'ok', 'love', 'like',
      'perfect', 'brilliant', 'awesome', 'cool', 'sweet', 'lovely',
      'نجاح', 'فوز', 'تطور', 'إيجابي', 'سعيد', 'ممتاز', 'جيد',
    ];
    final negativeWords = [
      'bad', 'terrible', 'awful', 'negative', 'sad', 'unhappy', 'hate', 'dislike',
      'horrible', 'worst', 'worse', 'disaster', 'fail', 'failure', 'poor', 'weak',
      'sick', 'ill', 'wrong', 'error', 'problem', 'issue', 'broken', 'damage',
      'crash', 'kill', 'die', 'dead', 'war', 'conflict',
      'فشل', 'خسارة', 'خسارة', 'كارثة', 'سيء', 'أسوأ', 'حرب', 'صراع', 'موت',
    ];

    int positiveCount = 0;
    int negativeCount = 0;
    final words = text.split(RegExp(r'\s+'));
    for (final word in words) {
      if (positiveWords.contains(word)) positiveCount++;
      if (negativeWords.contains(word)) negativeCount++;
    }

    final total = positiveCount + negativeCount;
    if (total == 0) return 0.0;
    return (positiveCount - negativeCount) / total;
  }

  static String _determineEventType(String text) {
    if (text.contains('war') || text.contains('conflict') || text.contains('attack') ||
        text.contains('bomb') || text.contains('shooting') ||
        text.contains('حرب') || text.contains('صراع') || text.contains('هجوم') ||
        text.contains('قنبلة') || text.contains('إطلاق نار')) {
      return 'Conflict';
    }
    if (text.contains('election') || text.contains('vote') || text.contains('campaign') ||
        text.contains('انتخابات') || text.contains('تصويت') || text.contains('حملة')) {
      return 'Political';
    }
    if (text.contains('match') || text.contains('game') || text.contains('tournament') ||
        text.contains('مباراة') || text.contains('لعبة') || text.contains('بطولة')) {
      return 'Sports';
    }
    if (text.contains('concert') || text.contains('festival') || text.contains('show') ||
        text.contains('حفل') || text.contains('مهرجان') || text.contains('عرض')) {
      return 'Entertainment';
    }
    return 'General';
  }

  static String _determineSubcategory(String text) {
    if (text.contains('football') || text.contains('soccer') ||
        text.contains('كرة قدم') || text.contains('كورة')) return 'Football';
    if (text.contains('basketball')) return 'Basketball';
    if (text.contains('tennis')) return 'Tennis';
    if (text.contains('politics') || text.contains('government') ||
        text.contains('سياسة') || text.contains('حكومة')) return 'Politics';
    if (text.contains('technology') || text.contains('tech') ||
        text.contains('تقنية') || text.contains('تكنولوجيا')) return 'Technology';
    if (text.contains('health') || text.contains('medical') ||
        text.contains('صحة') || text.contains('طبي')) return 'Health';
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
