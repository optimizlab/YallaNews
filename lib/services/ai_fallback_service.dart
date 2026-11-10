// Deterministic Fallback Service for AI Features
// Provides offline/fallback implementations when AI models are not available

import 'package:yallanews/services/ai_ffi.dart' show YallaLanguage;
import 'package:yallanews/services/tiny_llm_service.dart';

class AIFallbackService {
  static AIFallbackService? _instance;
  static AIFallbackService get instance => _instance ??= AIFallbackService._();
  AIFallbackService._();

  final TinyLLMService _tinyLLM = TinyLLMService.instance;

  /// Deterministic summarization using extractive methods
  String summarize({
    required String title,
    required String content,
    String language = 'en',
    int maxLength = 150,
  }) {
    try {
      // Use TinyLLM service if available
      if (_tinyLLM.isAvailable) {
        // This would call the deterministic clean/summarize from yalla_engine
      }
    } catch (_) {}

    // Simple extractive fallback
    final sentences = _splitIntoSentences(content, language);
    if (sentences.isEmpty) return '';

    // Score sentences by position and keyword overlap with title
    final titleWords = _extractKeywords(title, language);
    final scoredSentences = sentences.asMap().entries.map((entry) {
      final idx = entry.key;
      final sentence = entry.value;
      final sentenceWords = _extractKeywords(sentence, language);
      final overlap = titleWords.intersection(sentenceWords).length;
      final positionScore = 1.0 / (idx + 1);
      final score = overlap * 2.0 + positionScore;
      return _ScoredSentence(sentence: sentence, score: score);
    }).toList();

    scoredSentences.sort((a, b) => b.score.compareTo(a.score));
    
    final selected = scoredSentences.take(3).map((s) => s.sentence).join(' ');
    return selected.length > maxLength ? '${selected.substring(0, maxLength)}...' : selected;
  }

  /// Deterministic translation using dictionary/rule-based approach
  String translate({
    required String text,
    required YallaLanguage sourceLang,
    required YallaLanguage targetLang,
  }) {
    if (sourceLang == targetLang) return text;
    
    // For now, return a placeholder indicating translation is unavailable offline
    // In production, this would use a compact offline dictionary
    final sourceName = _languageDisplayName(sourceLang);
    final targetName = _languageDisplayName(targetLang);
    return '[$sourceName→$targetName translation unavailable offline] $text';
  }

  /// Deterministic classification using keyword matching
  String classify({
    required String title,
    required String content,
    String language = 'en',
  }) {
    final text = '$title $content'.toLowerCase();
    
    final categories = <String, List<String>>{
      'politics': ['government', 'president', 'minister', 'parliament', 'election', 'policy', 'diplomatic', 'congress', 'senate', 'legislation', 'cabinet', 'ambassador', 'treaty', 'summit', 'vote', 'candidate', 'campaign', 'referendum', 'coalition', 'opposition', 'bill', 'constitution', 'حكومة', 'رئيس', 'وزير', 'برلمان', 'انتخابات', 'سياسة', 'دبلوماسي', 'مجلس', 'نواب', 'وزارة', 'قانون', 'دستور', 'حزب', 'معارضة', 'ائتلاف', 'تصويت', 'مرشح', 'حملات', 'استفتاء'],
      'business': ['economy', 'market', 'stock', 'investment', 'bank', 'trade', 'financial', 'business', 'company', 'growth', 'inflation', 'budget', 'currency', 'profit', 'loss', 'shares', 'bonds', 'funding', 'revenue', 'earnings', 'quarterly', 'fiscal', 'monetary', 'اقتصاد', 'سوق', 'بورصة', 'استثمار', 'بنك', 'تجارة', 'مالي', 'شركة', 'نمو', 'تضخم', 'ميزانية', 'عملة', 'أسعار', 'ارباح', 'خسائر', 'اسهم', 'سندات', 'تمويل', 'مصرف'],
      'technology': ['technology', 'software', 'ai', 'artificial intelligence', 'digital', 'tech', 'innovation', 'phone', 'internet', 'app', 'programming', 'computer', 'robot', 'blockchain', 'crypto', 'cyber', 'security', 'startup', 'platform', 'algorithm', 'machine learning', 'cloud', 'تكنولوجيا', 'برمجيات', 'ذكاء اصطناعي', 'رقمي', 'تقنية', 'ابتكار', 'هاتف', 'انترنت', 'تطبيق', 'برمجة', 'حاسوب', 'روبوت', 'بلوكشين', 'عملات رقمية', 'سيبر', 'امن معلومات'],
      'sports': ['sports', 'football', 'soccer', 'match', 'team', 'player', 'championship', 'league', 'goal', 'cup', 'real madrid', 'barcelona', 'el clasico', 'national team', 'coach', 'stadium', 'referee', 'tournament', 'victory', 'defeat', 'score', 'transfer', 'injury', 'رياضة', 'كرة القدم', 'مباراة', 'فريق', 'لاعب', 'بطولة', 'دوري', 'هدف', 'كأس', 'ريال مدريد', 'برشلونة', 'الكلاسيكو', 'منتخب', 'مدرب', 'ملعب', 'حكم', 'بطاقة'],
      'health': ['health', 'hospital', 'doctor', 'disease', 'treatment', 'vaccine', 'medical', 'virus', 'pandemic', 'patient', 'medicine', 'pharmacy', 'lab', 'test', 'surgery', 'emergency', 'clinic', 'symptoms', 'diagnosis', 'therapy', 'prevention', 'who', 'cdc', 'صحة', 'مستشفى', 'طبيب', 'مرض', 'علاج', 'لقاح', 'طبي', 'فيروس', 'وباء', 'وزارة الصحة', 'مريض', 'دواء', 'صيدلية', 'مختبر', 'تحليل', 'جراحة', 'طوارئ', 'اسعاف'],
      'science': ['science', 'research', 'study', 'discovery', 'experiment', 'lab', 'space', 'planet', 'physics', 'chemistry', 'biology', 'nasa', 'moon', 'mars', 'iss', 'telescope', 'satellite', 'orbit', 'astronomy', 'quantum', 'genetics', 'climate', 'environment', 'علم', 'بحث', 'دراسة', 'اكتشاف', 'تجربة', 'مختبر', 'فضاء', 'كوكب', 'فيزياء', 'كيمياء', 'بيولوجيا', 'ناسا', 'قمر', 'مريخ', 'محطة فضاء', 'تلسكوب', 'قمر صناعي', 'مدار'],
      'culture': ['culture', 'art', 'museum', 'exhibition', 'heritage', 'festival', 'book', 'novel', 'poet', 'critic', 'theater', 'cinema', 'film', 'actor', 'music', 'concert', 'opera', 'ballet', 'archaeology', 'literature', 'painting', 'sculpture', 'gallery', 'ثقافة', 'فن', 'متحف', 'معرض', 'تراث', 'مهرجان', 'كتاب', 'رواية', 'شاعر', 'ناقد', 'مسرح', 'سينما', 'فيلم', 'ممثل', 'موسيقى', 'حفلة', 'اوبرا', 'باليه', 'اثار'],
      'world': ['world', 'international', 'global', 'country', 'nation', 'foreign', 'diplomacy', 'embassy', 'summit', 'america', 'europe', 'asia', 'africa', 'middle east', 'un', 'united nations', 'security council', 'treaty', 'alliance', 'sanctions', 'العالم', 'دولي', 'عالمي', 'عالم', 'دولة', 'أجنبي', 'خارجية', 'سفارة', 'قمة', 'امريكا', 'اوروبا', 'آسيا', 'افريقيا', 'شرق اوسط', 'امم متحدة', 'مجلس امن'],
      'society': ['society', 'family', 'education', 'youth', 'women', 'children', 'school', 'university', 'marriage', 'divorce', 'child protection', 'human rights', 'work', 'unemployment', 'poverty', 'housing', 'transport', 'traffic', 'crime', 'justice', 'law', 'مجتمع', 'عائلة', 'تعليم', 'شباب', 'مرأة', 'طفل', 'مدرسة', 'جامعة', 'زواج', 'طلاق', 'حماية الطفل', 'حقوق الانسان', 'عمل', 'بطالة', 'فقر', 'اسكان', 'نقل', 'مرور'],
      'entertainment': ['entertainment', 'celebrity', 'artist', 'singer', 'actor', 'show', 'tv', 'youtube', 'tiktok', 'instagram', 'snapchat', 'fashion', 'beauty', 'tourism', 'travel', 'restaurant', 'food', 'lifestyle', 'viral', 'trending', 'influencer', 'ترفيه', 'مشاهير', 'فنان', 'مغني', 'ممثل', 'برنامج', 'تلفزيون', 'يوتيوب', 'تيك توك', 'انستغرام', 'سناب شات', 'موضة', 'جمال', 'سياحة', 'سفر', 'مطعم', 'قهوة'],
    };

    String bestCategory = 'general';
    int bestScore = 0;

    for (final entry in categories.entries) {
      int score = 0;
      for (final keyword in entry.value) {
        if (text.contains(keyword.toLowerCase())) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        bestCategory = entry.key;
      }
    }

    return bestCategory;
  }

  /// Deterministic entity extraction using regex patterns
  List<String> extractEntities({
    required String title,
    required String content,
    String language = 'en',
  }) {
    final text = '$title $content';
    final entities = <String>{};

    // Person patterns
    final personRegex = RegExp(
      r'\b(?:Mr\.|Mrs\.|Ms\.|Dr\.|Prof\.)\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b',
      caseSensitive: false,
    );
    entities.addAll(personRegex.allMatches(text).map((m) => m.group(0)!));

    // Organization patterns
    final orgRegex = RegExp(
      r'\b(?:Inc\.|Corp\.|LLC|Ltd\.|Company|Corporation|Group|Organization|Foundation|Institute|University|Association)\b',
      caseSensitive: false,
    );
    entities.addAll(orgRegex.allMatches(text).map((m) => m.group(0)!));

    // Date patterns
    final dateRegex = RegExp(
      r'\b\d{1,2}[-/]\d{1,2}[-/]\d{2,4}\b|\b\d{4}[-/]\d{1,2}[-/]\d{1,2}\b|\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},?\s+\d{4}\b',
      caseSensitive: false,
    );
    entities.addAll(dateRegex.allMatches(text).map((m) => m.group(0)!));

    // Money patterns
    final moneyRegex = RegExp(
      r'\$\s*\d+(?:,\d{3})*(?:\.\d{2})?|\b\d+(?:,\d{3})*(?:\.\d{2})?\s*(?:USD|EUR|GBP|SAR|AED|EGP|MAD|TND|JOD|KWD|BHD|OMR|QAR)\b',
      caseSensitive: false,
    );
    entities.addAll(moneyRegex.allMatches(text).map((m) => m.group(0)!));

    // Arabic-specific patterns
    if (language == 'ar') {
      final arabicPersonRegex = RegExp(r'(?:السيد|السيدة|الدكتور|البروفيسور|الأستاذ|الوزير|الرئيس|الملك|الأمير|الشيخ)\s+[\u0600-\u06FF]+(?:\s+[\u0600-\u06FF]+)*');
      entities.addAll(arabicPersonRegex.allMatches(text).map((m) => m.group(0)!));

      final arabicOrgRegex = RegExp(r'(?:شركة|مؤسسة|بنك|جامعة|وزارة|هيئة|منظمة|جمعية|مركز|مجموعة|قوة|جيش|شرطة|حكومة)\s+[\u0600-\u06FF]+');
      entities.addAll(arabicOrgRegex.allMatches(text).map((m) => m.group(0)!));
    }

    return entities.toList();
  }

  /// Deterministic sentiment analysis
  double analyzeSentiment(String text) {
    final positiveWords = {
      'good', 'great', 'excellent', 'positive', 'success', 'win', 'victory', 'happy', 'joy', 'love', 'best', 'amazing', 'wonderful', 'fantastic', 'beautiful', 'perfect', 'outstanding', 'brilliant', 'superb', 'magnificent',
      'جيد', 'ممتاز', 'إيجابي', 'نجاح', 'فوز', 'انتصار', 'سعيد', 'فرح', 'حب', 'أفضل', 'رائع', 'مذهل', 'رائع', 'جميل', 'مثالي', 'بارز', 'متميز', 'رائع',
      'bon', 'excellent', 'positif', 'succès', 'victoire', 'heureux', 'joie', 'amour', 'meilleur', 'incroyable', 'merveilleux', 'fantastique', 'beau', 'parfait', 'exceptionnel',
    };
    
    final negativeWords = {
      'bad', 'terrible', 'awful', 'negative', 'fail', 'failure', 'loss', 'sad', 'angry', 'hate', 'worst', 'horrible', 'disgusting', 'awful', 'poor', 'disappointing', 'devastating', 'tragic', 'crisis', 'disaster',
      'سيء', 'فظيع', 'مروع', 'سلبي', 'فشل', 'خسارة', 'حزين', 'غاضب', 'كره', 'أسوأ', 'مروع', 'مقزز', 'رديء', 'مخيب', 'مدمر', 'مأساوي', 'أزمة', 'كارثة',
      'mauvais', 'terrible', 'affreux', 'négatif', 'échec', 'perte', 'triste', 'en colère', 'haine', 'pire', 'horrible', 'dégoûtant', 'pauvre', 'décevant', 'dévastateur', 'tragique', 'crise', 'catastrophe',
    };

    final words = text.toLowerCase().split(RegExp(r'\W+'));
    int positive = 0;
    int negative = 0;

    for (final word in words) {
      if (positiveWords.contains(word)) positive++;
      if (negativeWords.contains(word)) negative++;
    }

    if (positive + negative == 0) return 0.0;
    return (positive - negative) / (positive + negative);
  }

  /// Deterministic keyword extraction
  List<String> extractKeywords(String text, {int maxKeywords = 10}) {
    final words = text.toLowerCase().split(RegExp(r'\W+'));
    final stopWords = {
      'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by', 'from', 'as', 'is', 'was', 'are', 'were', 'be', 'been', 'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could', 'should', 'may', 'might', 'must', 'can', 'this', 'that', 'these', 'those', 'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her', 'us', 'them', 'my', 'your', 'his', 'her', 'its', 'our', 'their',
      'ال', 'في', 'على', 'من', 'إلى', 'مع', 'عن', 'هذا', 'هذه', 'ذلك', 'تلك', 'التي', 'الذي', 'اللذين', 'اللواتي', 'ما', 'من', 'كيف', 'متى', 'أين', 'لماذا',
      'le', 'la', 'les', 'un', 'une', 'des', 'et', 'ou', 'mais', 'dans', 'sur', 'à', 'de', 'du', 'pour', 'avec', 'par', 'ce', 'cette', 'ces', 'qui', 'que', 'dont', 'où', 'quand', 'comment', 'pourquoi',
    };

    final freq = <String, int>{};
    for (final word in words) {
      if (word.length < 3) continue;
      if (stopWords.contains(word)) continue;
      freq[word] = (freq[word] ?? 0) + 1;
    }

    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(maxKeywords).map((e) => e.key).toList();
  }

  // Helper methods
  List<String> _splitIntoSentences(String text, String language) {
    if (language == 'ar') {
      return text.split(RegExp(r'[.!?。؟]+\s*')).where((s) => s.trim().isNotEmpty).map((s) => s.trim()).toList();
    }
    return text.split(RegExp(r'[.!?]+\s+')).where((s) => s.trim().isNotEmpty).map((s) => s.trim()).toList();
  }

  Set<String> _extractKeywords(String text, String language) {
    final words = text.toLowerCase().split(RegExp(r'\W+'));
    final stopWords = {
      'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by', 'from', 'as', 'is', 'was', 'are', 'were', 'be', 'been', 'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could', 'should', 'may', 'might', 'must', 'can', 'this', 'that', 'these', 'those', 'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her', 'us', 'them', 'my', 'your', 'his', 'her', 'its', 'our', 'their',
      'ال', 'في', 'على', 'من', 'إلى', 'مع', 'عن', 'هذا', 'هذه', 'ذلك', 'تلك', 'التي', 'الذي', 'اللذين', 'اللواتي', 'ما', 'من', 'كيف', 'متى', 'أين', 'لماذا',
      'le', 'la', 'les', 'un', 'une', 'des', 'et', 'ou', 'mais', 'dans', 'sur', 'à', 'de', 'du', 'pour', 'avec', 'par', 'ce', 'cette', 'ces', 'qui', 'que', 'dont', 'où', 'quand', 'comment', 'pourquoi',
    };
    return words.where((w) => w.length >= 3 && !stopWords.contains(w)).toSet();
  }

  String _languageDisplayName(YallaLanguage lang) {
    switch (lang) {
      case YallaLanguage.arabic:
        return 'Arabic';
      case YallaLanguage.french:
        return 'French';
      case YallaLanguage.english:
      default:
        return 'English';
    }
  }
}

class _ScoredSentence {
  final String sentence;
  final double score;

  _ScoredSentence({required this.sentence, required this.score});
}