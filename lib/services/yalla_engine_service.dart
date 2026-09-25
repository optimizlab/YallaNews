// IMPORT DART ASYNC
import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;

import '../models/news_model.dart';
import 'tiny_llm_service.dart';
import 'news_uri_parser.dart';
import 'image_validator_service.dart';
import 'engine_ffi.dart';
import 'arabic_normalizer.dart';

enum EngineMode {
  ffi, // Native Direct C++ DLL via Dart FFI
  server, // Standalone C++ WinSock HTTP Server
  emulator, // Built-in Dart Simulation Fallback
}

class YallaEngineService extends ChangeNotifier {
  static final TinyLLMService _llmInstance = TinyLLMService.instance;
  static TinyLLMService get llm => _llmInstance;
  
  EngineMode _mode = EngineMode.emulator;
  bool _isConnecting = false;
  String _currentLogs = "";
  final List<String> _consoleLogs = [];
  final List<NewsModel> _articles = [];

  static const Set<String> garbageTitles = {
    'home',
    'homepage',
    'index',
    'error',
    '404',
    '404 not found',
    'not found',
    'forbidden',
    'unauthorized',
    'page not found',
    'security check',
    'just a moment...',
    'access denied',
  };

  // Controllers for streaming logs to UI
  final _logStreamController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logStreamController.stream;

  EngineMode get mode => _mode;
  bool get isConnecting => _isConnecting;
  String get currentLogs => _currentLogs;
  List<String> get consoleLogs => _consoleLogs;
  List<NewsModel> get articles => _articles;

  String get modeDescription {
    switch (_mode) {
      case EngineMode.ffi:
        return "C++ Engine: Direct DLL (FFI)";
      case EngineMode.server:
        return "C++ Engine: Local Server (Port 8080)";
      case EngineMode.emulator:
        return "Built-in Dart Emulator (C++ Offline)";
    }
  }

  YallaEngineService() {
    autoDetectEngine();
  }

  void addLog(String log) {
    _consoleLogs.add(log);
    _logStreamController.add(log);
    notifyListeners();
    debugPrint(log); // Also appears in `flutter run` terminal
  }

  void clearLogs() {
    _consoleLogs.clear();
    _currentLogs = "";
    notifyListeners();
  }

  // ─── HTML Entity Decoder ──────────────────────────────────────────────────────
  static String _decodeHtml(String text) {
    if (text.isEmpty) return text;

    text = text.replaceAll('&quot;', '"');
    text = text.replaceAll('&#34;', '"');
    text = text.replaceAll('&#x22;', '"');
    text = text.replaceAll('\u0022', '"');
    text = text.replaceAll('&apos;', "'");
    text = text.replaceAll('\'', "'");
    text = text.replaceAll('&#039;', "'");
    text = text.replaceAll('&lt;', '<');
    text = text.replaceAll('&gt;', '>');
    text = text.replaceAll('&nbsp;', ' ');
    text = text.replaceAll('&thinsp;', ' ');
    text = text.replaceAll('&ensp;', ' ');
    text = text.replaceAll('&emsp;', ' ');
    text = text.replaceAll('&mdash;', '—');
    text = text.replaceAll('&ndash;', '–');
    text = text.replaceAll('&hellip;', '…');
    text = text.replaceAll('&bull;', '•');
    text = text.replaceAll('&lsquo;', '\u2018');
    text = text.replaceAll('&rsquo;', '\u2019');
    text = text.replaceAll('&ldquo;', '\u201C');
    text = text.replaceAll('&rdquo;', '\u201D');
    text = text.replaceAll('&copy;', '©');
    text = text.replaceAll('&reg;', '®');
    text = text.replaceAll('&trade;', '™');
    text = text.replaceAll('&euro;', '€');
    text = text.replaceAll('&pound;', '£');
    text = text.replaceAll('&yen;', '¥');
    text = text.replaceAll('&deg;', '°');
    text = text.replaceAllMapped(RegExp(r'&#x([0-9A-Fa-f]+);'), (m) {
      try {
        return String.fromCharCode(int.parse(m.group(1)!, radix: 16));
      } catch (_) {
        return '';
      }
    });
    text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      try {
        return String.fromCharCode(int.parse(m.group(1)!));
      } catch (_) {
        return '';
      }
    });
    text = text.replaceAll('&amp;', '&');
    return text;
  }

  static String _stripHtmlTags(String text) {
    if (text.isEmpty) return text;
    final withoutTags = text.replaceAll(RegExp(r'<[^>]*>'), '');
    return _decodeHtml(withoutTags);
  }

  static final _positiveWords = {
    'ممتاز', 'رائع', 'جيد', 'إيجابي', 'سعيد', 'فرح', 'حب', 'نجاح', 'ناجح',
    'انتصار', 'فوز', 'تطور', 'تقدم', 'إنجاز', 'أمل', 'سلام', 'أمان', 'استقرار',
    'احتفال', 'تكريم', 'جائزة', 'افتتاح', 'إطلاق', 'تعاون', 'شراكة', 'شراكات',
    'ازدهار', 'نمو', 'خير', 'بركة', 'مساعدة', 'دعم', 'توافق', 'اتفاق', 'اتفاقية',
    'حل', 'إصلاح', 'تحسين', 'ارتفاع', 'زيادة', 'قوي', 'قوة', 'نهضة', 'شكر',
    'ترحيب', 'إشادة', 'تتويج', 'تميز', 'تفوق', 'أفضل', 'مكسب', 'ارتقاء', 'بناء',
    'مذهل', 'جميل', 'مفيد', 'مثالي', 'تحدي', 'إبداعي', 'مميز', 'فريد',
    'سليم', 'صحي', 'آمن', 'مستقر', 'مطمئن', 'مشرق', 'واعد', 'منشود', 'مرغوب',
    'محبوب', 'مقبول', 'سهل', 'بسيط', 'ميسر', 'عظيم', 'كريم', 'مهم',
    'good', 'great', 'excellent', 'positive', 'happy', 'joy', 'love', 'like',
    'amazing', 'wonderful', 'best', 'better', 'fantastic', 'terrific',
    'outstanding', 'superb', 'nice', 'fine', 'perfect', 'brilliant',
    'awesome', 'cool', 'sweet', 'lovely', 'success', 'win', 'victory',
    'achieve', 'progress', 'improve', 'growth', 'benefit', 'hope', 'peace',
    'safe', 'secure', 'celebrate', 'honor', 'award', 'launch', 'new',
  };

  static final _negativeWords = {
    'سيئ', 'فظيع', 'سلبي', 'حزين', 'كره', 'كارثة', 'فشل', 'فقر', 'مرض', 'أمراض',
    'خطأ', 'مشكلة', 'أزمة', 'أزمات', 'خراب', 'ضرر', 'أضرار', 'حادث', 'حوادث',
    'قتل', 'موت', 'وفاة', 'وفيات', 'مقتل', 'اغتيال', 'حرب', 'حروب', 'صراع',
    'هجوم', 'اعتداء', 'انهيار', 'خسارة', 'خسائر', 'خطر', 'مخاطر', 'تهديد',
    'عنف', 'جريمة', 'جرائم', 'فساد', 'فضيحة', 'فضائح', 'احتجاج', 'احتجاجات',
    'توتر', 'خوف', 'قلق', 'أذى', 'اعتقال', 'إدانة', 'إصابة', 'إصابات',
    'ضحية', 'ضحايا', 'إرهاب', 'إرهابي', 'تدمير', 'نزيف', 'معاناة', 'شكوى',
    'سيء', 'مؤسف', 'مخيف', 'خطير', 'اصابة', 'مصاب', 'دمار', 'تلوث',
    'وباء', 'كوارث', 'غش', 'تجاوز', 'انتهاك', 'قمع', 'ظلم', 'تعذيب',
    'مخيب', 'محبط', 'مرفوض', 'صعب', 'مستحيل', 'مشاكل',
    'bad', 'terrible', 'awful', 'negative', 'sad', 'unhappy', 'hate',
    'horrible', 'worst', 'worse', 'disaster', 'fail', 'failure', 'poor',
    'sick', 'ill', 'wrong', 'error', 'problem', 'issue', 'broken', 'damage',
    'crash', 'kill', 'die', 'dead', 'war', 'conflict', 'attack', 'bomb',
    'crisis', 'collapse', 'loss', 'danger', 'risk', 'threat', 'violence',
    'crime', 'corruption', 'scandal', 'protest', 'tension', 'fear',
  };

  static double _calculateSentiment(String text) {
    if (text.isEmpty) return 0.0;
    final normalizedText = ArabicTextNormalizer.normalize(text).toLowerCase();
    int positiveCount = 0;
    int negativeCount = 0;
    final words = normalizedText.split(RegExp(r'\s+'));
    for (final word in words) {
      final w = word.replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '');
      if (w.isEmpty) continue;
      if (_positiveWords.contains(w)) positiveCount++;
      if (_negativeWords.contains(w)) negativeCount++;
    }
    final total = positiveCount + negativeCount;
    if (total == 0) return 0.0;
    return ((positiveCount - negativeCount) / total).clamp(-1.0, 1.0);
  }

  // ─── Title Cleaner ────────────────────────────────────────────────────────────
  static String cleanTitle(String title, String url) {
    if (title.isEmpty) return title;

    String cleaned = title;

    // Extract domain from URL for source-name removal
    final uri = Uri.tryParse(url);
    final domain = uri != null ? uri.host.toLowerCase() : '';

    // Common separators between title and source/category
    final separators = [' - ', ' | ', ' :: ', ' — ', ' – ', ' : ', ' › ', ' « ', ' » '];

    for (final sep in separators) {
      if (cleaned.contains(sep)) {
        final parts = cleaned.split(sep);
        if (parts.length >= 2) {
          final lastPart = parts.last.trim();
          // If the last part looks like a source name or category (short, no sentence structure)
          final words = lastPart.split(RegExp(r'\s+'));
          if (words.length <= 5 && !lastPart.contains('.') && !lastPart.contains('?')) {
            cleaned = parts.take(parts.length - 1).join(sep).trim();
          }
        }
        break;
      }
    }

    // Remove domain-derived source name if present at end
    if (domain.isNotEmpty) {
      final domainParts = domain.split('.');
      final sourceName = domainParts.first;
      if (sourceName.length > 3 && cleaned.toLowerCase().endsWith(sourceName)) {
        final escaped = RegExp.escape(sourceName);
        final regex = RegExp('\\s*[-|:]?\\s*$escaped\\s*\$', caseSensitive: false);
        cleaned = cleaned.replaceAll(regex, '').trim();
      }
    }

    // Remove common category words that appear at end of titles
    final categoryWords = [
      'أخبار', 'رياضة', 'اقتصاد', 'سياسة', 'تكنولوجيا', 'ثقافة', 'فن', 'ترفيه',
      'صحة', 'علم', 'بيئة', 'سفر', 'سياحة', 'ألعاب', 'تعليم', 'محافظات', 'دولي',
      'محلي', 'عاجل', 'حصري', 'ممتاز', 'رأي', 'مقالات', 'تحقيقات', 'حوادث',
      'منوعات', 'ميديا', 'فيديو', 'صور', 'بث مباشر', 'مباشر',
    ];
    for (final word in categoryWords) {
      final escaped = RegExp.escape(word);
      final regex = RegExp('\\s*[-|:]?\\s*$escaped\\s*\$');
      cleaned = cleaned.replaceAll(regex, '').trim();
    }

    // Remove trailing separators
    cleaned = cleaned.replaceAll(RegExp(r'[-|:]\s*$'), '').trim();

    // Normalize whitespace
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    return cleaned;
  }

  static bool hasValidTitle(String? title) {
    if (title == null || title.isEmpty) return false;
    final words = title.trim().split(RegExp(r'\s+'));
    return words.length >= 3;
  }

  // ─── Keyword Extractor ────────────────────────────────────────────────────────
  static List<String> extractKeywords(
    String title,
    String summary,
    String content,
  ) {
    final combined = '$title $summary $content'.toLowerCase();

    const stopWords = {
      'the',
      'a',
      'an',
      'and',
      'or',
      'but',
      'in',
      'on',
      'at',
      'to',
      'for',
      'of',
      'with',
      'by',
      'from',
      'is',
      'are',
      'was',
      'were',
      'be',
      'been',
      'being',
      'have',
      'has',
      'had',
      'do',
      'does',
      'did',
      'will',
      'would',
      'could',
      'should',
      'may',
      'might',
      'shall',
      'can',
      'this',
      'that',
      'these',
      'those',
      'i',
      'we',
      'you',
      'he',
      'she',
      'it',
      'they',
      'my',
      'our',
      'your',
      'his',
      'her',
      'its',
      'their',
      'what',
      'which',
      'who',
      'whom',
      'when',
      'where',
      'why',
      'how',
      'all',
      'each',
      'every',
      'both',
      'few',
      'more',
      'most',
      'other',
      'some',
      'such',
      'no',
      'not',
      'only',
      'same',
      'so',
      'than',
      'too',
      'very',
      'just',
      'also',
      'as',
      'into',
      'up',
      'out',
      'about',
      'over',
      'after',
      'now',
      'news',
      'said',
      'new',
      'one',
      'two',
      'three',
      'get',
      'got',
      'go',
      'year',
      'years',
      'day',
      'days',
      'time',
      'way',
      'says',
      'say',
      'him',
      'them',
      'then',
      'there',
      'here',
      'if',
      'else',
      'while',
      'per',
      'via',
      'using',
      'used',
      'use',
      'make',
      'made',
      'take',
      'took',
      'like',
      'well',
      'back',
      'even',
      'still',
      'come',
      'came',
      'much',
      'many',
      'around',
      'however',
      'without',
      'between',
      'since',
      'during',
      'before',
      'against',
      'among',
      'through',
      'within',
      'across',
      'off',
      'down',
      'under',
      'again',
      'further',
      'once',
      'until',
    };

    // Tokenize: allow Latin + Arabic characters
    final words = combined
        .replaceAll(RegExp(r"[^\w\u0600-\u06FF\s]"), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !stopWords.contains(w))
        .toList();

    // Count word frequency
    final freq = <String, int>{};
    for (final word in words) {
      freq[word] = (freq[word] ?? 0) + 1;
    }

    // Return top 10 by frequency
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final keywords = sorted.take(10).map((e) => e.key).toList();
    return keywords.isNotEmpty ? keywords : ['news', 'update'];
  }

  /// Check if image alt text is relevant to the article title/keywords
  static bool _isImageAltRelevant(
    String altText,
    String title,
    List<String> keywords,
  ) {
    if (altText.isEmpty) return false;
    final lowerAlt = altText.toLowerCase();
    final lowerTitle = title.toLowerCase();

    // Check if alt text contains title keywords
    for (final keyword in keywords) {
      if (keyword.length > 3 && lowerAlt.contains(keyword.toLowerCase())) {
        return true;
      }
    }

    // Check if alt text shares significant words with title
    final altWords = lowerAlt
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3)
        .toSet();
    final titleWords = lowerTitle
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3)
        .toSet();

    if (altWords.isEmpty || titleWords.isEmpty) return false;

    final intersection = altWords.intersection(titleWords);
    return intersection.length >= 2;
  }

  /// Check if image URL or alt text is relevant to the article title (for duplicate detection)
  static bool isImageRelevantToTitle(
    String imageUrl,
    String imageAlt,
    String title,
    List<String> keywords,
  ) {
    if (imageUrl.isEmpty) return false;

    final lowerUrl = imageUrl.toLowerCase();
    final lowerAlt = imageAlt.toLowerCase();
    final lowerTitle = title.toLowerCase();

    // Check if image URL path contains title keywords
    final urlPath = Uri.tryParse(imageUrl)?.path.toLowerCase() ?? '';
    for (final keyword in keywords) {
      if (keyword.length > 3 && urlPath.contains(keyword.toLowerCase())) {
        return true;
      }
    }

    // Check if image alt contains title keywords
    for (final keyword in keywords) {
      if (keyword.length > 3 && lowerAlt.contains(keyword.toLowerCase())) {
        return true;
      }
    }

    // Check if alt shares words with title
    if (lowerAlt.isNotEmpty) {
      final altWords = lowerAlt
          .replaceAll(RegExp(r'[^\w\s]'), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 3)
          .toSet();
      final titleWords = lowerTitle
          .replaceAll(RegExp(r'[^\w\s]'), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 3)
          .toSet();
      if (altWords.isNotEmpty && titleWords.isNotEmpty) {
        final intersection = altWords.intersection(titleWords);
        if (intersection.length >= 2) return true;
      }
    }

    return false;
  }

  // ─── C++ TinyLLM Photo Engine ─────────────────────────────────────────────────
  /// Searches Bing Image Search for image URLs matching the given query.
  Future<List<String>> fetchBingImages(String query) async {
    final List<String> images = [];
    try {
      final encoded = Uri.encodeComponent(query);
      final uniqueTerm = Uri.encodeComponent(' ${DateTime.now().millisecondsSinceEpoch % 10000} ${(query.length * 7 + query.hashCode % 1000)}');
      final url =
          'https://www.bing.com/images/search?q=$encoded$uniqueTerm&form=HDRSC3&first=1&adlt=strict&tsc=ImageHoverTitle';

      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
              'Accept-Language': 'en-US,en;q=0.5',
              'Referer': 'https://www.bing.com/',
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        // Strategy 1: extract from embedded murl JSON values
        final murlPattern = RegExp(r'"murl":"(https?://[^"]+)"');
        for (final match in murlPattern.allMatches(response.body)) {
          final imgUrl = match.group(1);
          if (imgUrl != null && images.length < 5) {
            final lower = imgUrl.toLowerCase();
            if (lower.contains('.jpg') ||
                lower.contains('.jpeg') ||
                lower.contains('.png') ||
                lower.contains('.webp')) {
              images.add(imgUrl);
            }
          }
          if (images.length >= 5) break;
        }

        // Strategy 2: extract from <img class="mimg" src="...">
        if (images.isEmpty) {
          final imgPattern = RegExp(
            r'<img[^>]+class="[^"]*mimg[^"]*"[^>]+src="(https?://[^"]+)"',
            caseSensitive: false,
          );
          for (final match in imgPattern.allMatches(response.body)) {
            final imgUrl = match.group(1);
            if (imgUrl != null && images.length < 5) {
              images.add(imgUrl);
            }
          }
        }
      }
    } catch (_) {
      // Silently fail — photo engine is best-effort
    }
    return images;
  }

  /// Injects image HTML tags into content based on paragraph relevance.
  static String _injectImagesIntoContent(
    String content,
    List<String> imageUrls, {
    String? title,
    String? description,
    List<String>? metaKeywords,
  }) {
    if (imageUrls.isEmpty || content.isEmpty) return content;

    const imgStyle =
        'width:100%;max-height:380px;object-fit:cover;border-radius:12px;margin:16px 0;display:block;';

    final segments = _splitContentIntoSegments(
      content,
      title: title,
      description: description,
      metaKeywords: metaKeywords,
    );

    if (segments.isEmpty) return content;

    if (segments.length < 2) {
      final buf = StringBuffer(content);
      for (final img in imageUrls) {
        buf.write('\n\n<img src="$img" style="$imgStyle" />');
      }
      return buf.toString();
    }

    final usedImages = <String>{};
    int imgIdx = 0;

    final scoredSegments = <(int index, double bestScore, String segment, int bestImgIdx)>[];

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      var bestScore = 0.0;
      int bestIdx = -1;
      for (int j = 0; j < imageUrls.length; j++) {
        final url = imageUrls[j];
        if (usedImages.contains(url)) continue;
        final urlLower = url.toLowerCase();
        final score = _scoreImageForSegment(urlLower, segment);
        if (score > bestScore) {
          bestScore = score;
          bestIdx = j;
        }
      }
      if (bestIdx >= 0) {
        scoredSegments.add((i, bestScore, segment, bestIdx));
        usedImages.add(imageUrls[bestIdx]);
        imgIdx = bestIdx;
      }
    }

    scoredSegments.sort((a, b) => b.$2.compareTo(a.$2));

    final insertCount = imageUrls.length <= segments.length
        ? imageUrls.length
        : segments.length;

    final selectedInsert = <(int index, double score, String segment, int imgIdx)>[];
    for (int i = 0; i < insertCount; i++) {
      if (i < scoredSegments.length && scoredSegments[i].$2 >= 1.5) {
        selectedInsert.add(scoredSegments[i]);
      }
    }

    selectedInsert.sort((a, b) => a.$1.compareTo(b.$1));

    final buf = StringBuffer();
    int usedIdx = 0;
    for (int i = 0; i < segments.length; i++) {
      buf.write(segments[i]);
      (int index, double score, String segment, int imgIdx)? matching;
      for (final item in selectedInsert) {
        if (item.$1 == i) {
          matching = item;
          break;
        }
      }
      if (matching != null && usedIdx < insertCount) {
        final image = imageUrls[usedIdx++];
        buf.write('\n\n<img src="$image" style="$imgStyle" />');
      }
      if (i < segments.length - 1) {
        buf.write('\n\n');
      }
    }

    for (; usedIdx < imageUrls.length; usedIdx++) {
      buf.write('\n\n<img src="${imageUrls[usedIdx]}" style="$imgStyle" />');
    }

    return buf.toString().trimRight();
  }

  static double _scoreImageForSegment(String imageUrl, String segment) {
    final urlLower = imageUrl.toLowerCase();
    double score = 0.0;

    final segmentTokens = tokenizeSegment(segment);

    if (segmentTokens.isEmpty) return 0.0;

    for (final token in segmentTokens) {
      final urlTokens = tokenizeSegment(urlLower);
      for (final urlToken in urlTokens) {
        if (token == urlToken || token.contains(urlToken) || urlToken.contains(token)) {
          score += 1.0;
        }
      }
    }

    if (urlLower.contains('https://') || urlLower.contains('http://')) {
      score += 0.1;
    }

    final imageExtensions = ['.jpg', '.jpeg', '.png', '.webp'];
    final hasValidExtension = imageExtensions.any((ext) => urlLower.contains(ext));
    if (hasValidExtension) {
      score += 0.2;
    }

    final invalidPatterns = ['banner', 'logo', 'icon', 'avatar', 'profile', 'placeholder', 'sprite', '1x1', 'pixel', 'transparent', 'blank'];
    final hasInvalidPattern = invalidPatterns.any((pattern) => urlLower.contains(pattern));
    if (hasInvalidPattern) {
      score -= 2.0;
    }

    final contentWords = segment.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    for (final word in contentWords) {
      if (urlLower.contains(word)) {
        score += 0.5;
      }
    }

    return score;
  }

  static List<String> tokenizeSegment(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    final words = cleaned.split(' ').where((w) => w.length > 2).toList();
    return words;
  }

  static List<String> _splitContentIntoSegments(
    String content, {
    String? title,
    String? description,
    List<String>? metaKeywords,
  }) {
    if (content.isEmpty) return const [];

    final allKeywords = <String>[];
    if (title != null && title.isNotEmpty) {
      allKeywords.addAll(tokenizeSegment(title));
    }
    if (description != null && description.isNotEmpty) {
      allKeywords.addAll(tokenizeSegment(description));
    }
    if (metaKeywords != null) {
      for (final kw in metaKeywords) {
        if (kw.isNotEmpty) allKeywords.addAll(tokenizeSegment(kw));
      }
    }

    final keywordSet = allKeywords.toSet();

    final rawSegments = content
        .split(RegExp(r'\n\s*\n|\n{2,}'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.length >= 20)
        .toList();

    if (rawSegments.isEmpty) {
      final sentences = content
          .split(RegExp(r'(?<=[.!?؟!])\s+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && s.length >= 15)
          .toList();
      if (sentences.length >= 2) return sentences;
      return [content.trim()];
    }

    if (rawSegments.length == 1) {
      final text = rawSegments.first;
      final sentences = text
          .split(RegExp(r'(?<=[.!?؟!])\s+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && s.length >= 15)
          .toList();
      if (sentences.length >= 2) return sentences;
      return rawSegments;
    }

    if (keywordSet.isNotEmpty) {
      final scored = rawSegments.map((segment) {
        final tokens = tokenizeSegment(segment);
        if (tokens.isEmpty) return (segment, 0.0);
        final matches = tokens.where((t) => keywordSet.contains(t)).length;
        return (segment, matches / tokens.length);
      }).toList();

      scored.sort((a, b) => b.$2.compareTo(a.$2));

      final relevantSegments = scored
          .where((item) => item.$2 > 0.0)
          .map((item) => item.$1)
          .toList();

      if (relevantSegments.length >= 2) {
        return relevantSegments;
      }
    }

    if (rawSegments.length > 6) {
      return rawSegments.take(6).toList();
    }

    return rawSegments;
  }

  // ─── Image Extraction & Enrichment ──────────────────────────────────────────
  /// Extracts images from img tags, Open Graph, and Twitter Card meta tags.
  /// Scores images based on relevance to the article title (and optionally content).
  /// Returns a map with the best image as 'imageUrl' and the content with additional images injected.
  Future<Map<String, String>> _extractImagesAndEnrichContent({
    required String html,
    required String content,
    required String title,
    required String category,
    required String url,
    required String metaImageUrl,
  }) async {
    final List<String> extractedImages = [];
    final List<String> imageAlts = [];
    final List<String> imageTitles = []; // for img tags, we store title; for others, empty
    final List<String> imageTypes = []; // 'img', 'og', 'twitter', 'meta'

    // 1. Extract images from <img> tags (with alt and title)
    final imgRegex = RegExp(
      r'<img[^>]+src="([^"]+)"[^>]*alt="([^"]*)"[^>]*title="([^"]*)"[^>]*',
      caseSensitive: false,
    );
    final imgOnlyRegex = RegExp(
      r'<img[^>]+src="([^"]*)"[^>]*',
      caseSensitive: false,
    );

    // First pass: img tags with alt and title
    for (final match in imgRegex.allMatches(html)) {
      final imgUrl = match.group(1)?.trim() ?? '';
      final altText = match.group(2)?.trim() ?? '';
      final titleText = match.group(3)?.trim() ?? '';
      if (imgUrl.isEmpty) continue;

      // Make URL absolute if needed
      final uri = Uri.tryParse(url);
      final origin = uri?.origin ?? "";
      final String resolvedUrl = _resolveImageUrl(imgUrl, uri, origin);
      if (!ImageValidatorService.isValidImageUrl(resolvedUrl)) {
        continue;
      }

      extractedImages.add(resolvedUrl);
      imageAlts.add(altText);
      imageTitles.add(titleText);
      imageTypes.add('img');
    }

    // Second pass: img tags without alt (but we still want the URL)
    for (final match in imgOnlyRegex.allMatches(html)) {
      final imgUrl = match.group(1)?.trim() ?? '';
      if (imgUrl.isEmpty) continue;

      // Avoid duplicates
      if (extractedImages.contains(imgUrl)) continue;

      final uri = Uri.tryParse(url);
      final origin = uri?.origin ?? "";
      final String resolvedUrl = _resolveImageUrl(imgUrl, uri, origin);
      if (!ImageValidatorService.isValidImageUrl(resolvedUrl)) {
        continue;
      }

      extractedImages.add(resolvedUrl);
      imageAlts.add(''); // no alt
      imageTitles.add(''); // no title
      imageTypes.add('img');
    }

    // Extract Open Graph image
    final ogRegex = RegExp(r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"[^>]*>', caseSensitive: false);
    for (final match in ogRegex.allMatches(html)) {
      final imgUrl = match.group(1)?.trim() ?? '';
      if (imgUrl.isEmpty) continue;

      final uri = Uri.tryParse(url);
      final origin = uri?.origin ?? "";
      final String resolvedUrl = _resolveImageUrl(imgUrl, uri, origin);
      if (resolvedUrl.isEmpty) continue;

      if (ImageValidatorService.isValidImageUrl(resolvedUrl)) {
        extractedImages.add(resolvedUrl);
        imageAlts.add(''); // no alt
        imageTitles.add(''); // no title
        imageTypes.add('og');
      }
    }

    // Extract Twitter Image
    final twitterRegex = RegExp(r'<meta[^>]+name="twitter:image"[^>]+content="([^"]+)"[^>]*>', caseSensitive: false);
    for (final match in twitterRegex.allMatches(html)) {
      final imgUrl = match.group(1)?.trim() ?? '';
      if (imgUrl.isEmpty) continue;

      final uri = Uri.tryParse(url);
      final origin = uri?.origin ?? "";
      final String resolvedUrl = _resolveImageUrl(imgUrl, uri, origin);
      if (resolvedUrl.isEmpty) continue;

      if (ImageValidatorService.isValidImageUrl(resolvedUrl)) {
        extractedImages.add(resolvedUrl);
        imageAlts.add(''); // no alt
        imageTitles.add(''); // no title
        imageTypes.add('twitter');
      }
    }

    // Add the metaImageUrl (passed in) as a potential image (treated as 'meta')
    if (metaImageUrl.isNotEmpty) {
      final uri = Uri.tryParse(url);
      final origin = uri?.origin ?? "";
      final String resolvedUrl = _resolveImageUrl(metaImageUrl, uri, origin);
      if (resolvedUrl.isNotEmpty && ImageValidatorService.isValidImageUrl(resolvedUrl)) {
        extractedImages.add(resolvedUrl);
        imageAlts.add(''); // no alt
        imageTitles.add(''); // no title
        imageTypes.add('meta');
      }
    }

    // If no images found, return early
    if (extractedImages.isEmpty) {
      final photoResult = await _runPhotoEngine(
        title: title,
        imageUrl: '',
        content: content,
        category: category,
      );
      return photoResult;
    }

    // Score each image
    final keywords = extractKeywords(title, content, category);
    final titleWords = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toSet();

    final scores = <double>[];
    for (int i = 0; i < extractedImages.length; i++) {
      double score = 0.0;
      final url = extractedImages[i].toLowerCase();
      final alt = imageAlts[i].toLowerCase();
      final titleText = imageTitles[i].toLowerCase();
      final type = imageTypes[i];

      // Reject obviously non-content images
      if (_isRejectedImage(url, alt, titleText)) {
        scores.add(-999.0);
        continue;
      }

      // og/twitter/meta get a small base bonus, but still need content relevance
      if (type == 'og' || type == 'twitter' || type == 'meta') {
        score += 0.5;
      }

      // Strong signal: alt/title overlap with article title
      for (final word in titleWords) {
        if (word.length < 3) continue;
        if (url.contains(word)) score += 1.5;
        if (alt.contains(word)) score += 2.5;
        if (titleText.contains(word)) score += 1.5;
      }

      // Keyword overlap with article body
      for (final kw in keywords) {
        final kwLower = kw.toLowerCase();
        if (kwLower.length < 3) continue;
        if (url.contains(kwLower)) score += 1.0;
        if (alt.contains(kwLower)) score += 1.5;
        if (titleText.contains(kwLower)) score += 1.0;
      }

      // Bonus for real image file extensions
      final imageExtensions = ['.jpg', '.jpeg', '.png', '.webp'];
      final hasValidExtension = imageExtensions.any((ext) => url.contains(ext));
      if (hasValidExtension) score += 0.3;

      scores.add(score);
    }

    // Sort indices by score descending
    final indices = List.generate(extractedImages.length, (i) => i);
    indices.sort((a, b) => scores[b].compareTo(scores[a]));

    // TinyLLM-based relevance validation: reject images that are clearly off-topic.
    // Only validate the top candidates to avoid excessive async work.
    final validatedIndices = <int>[];
    for (final idx in indices) {
      if (scores[idx] < 0.0) continue; // already rejected by regex rules
      final isValid = await _validateImageWithTinyLlm(
        title: title,
        content: content,
        description: content.length > 200 ? content.substring(0, 200) : null,
        imageUrl: extractedImages[idx],
      );
      if (isValid) {
        validatedIndices.add(idx);
      } else {
        addLog('[TinyLLM] Filtered out image: ${extractedImages[idx]}');
      }
    }

    // Best image must have meaningful relevance
    final bestIndex = validatedIndices.isNotEmpty ? validatedIndices.first : -1;
    final bestScore = bestIndex >= 0 ? scores[bestIndex] : 0.0;
    final hasGoodImage = bestIndex >= 0 && bestScore >= 3.0;

    String finalImageUrl;
    List<String> additionalImages = [];

    if (hasGoodImage) {
      finalImageUrl = extractedImages[bestIndex];
      for (int i = 1; i < validatedIndices.length && i <= 1; i++) {
        final idx = validatedIndices[i];
        if (scores[idx] >= 2.0) {
          additionalImages.add(extractedImages[idx]);
        }
      }
    } else {
      final photoResult = await _runPhotoEngine(
        title: title,
        imageUrl: '',
        content: content,
        category: category,
      );
      finalImageUrl = photoResult['imageUrl']!;
      return photoResult;
    }

    // Inject additional images into content
    if (additionalImages.isNotEmpty) {
      content = _injectImagesIntoContent(
        content,
        additionalImages,
        title: title,
        description: content.length > 200 ? content.substring(0, 200) : null,
        metaKeywords: keywords,
      );
    }

    return {'imageUrl': finalImageUrl, 'content': content};
  }

  static bool _isRejectedImage(String url, String alt, String titleText) {
    final text = '$url $alt $titleText'.toLowerCase();

    final rejectPatterns = [
      'logo', 'banner', 'icon', 'avatar', 'profile', 'placeholder', 'sprite',
      '1x1', 'pixel', 'transparent', 'blank', 'spinner', 'loading', 'hamburger',
      'menu', 'nav', 'header', 'footer', 'sidebar', 'ad-', 'ads-', 'advert',
      'facebook', 'twitter', 'instagram', 'youtube', 'tiktok', 'social',
      'share', 'rss', 'feed', 'print', 'email', 'mail', 'phone', 'contact',
      'radio', 'podcast', 'audio', 'video', 'play', 'pause', 'stop',
      'search', 'filter', 'sort', 'arrow', 'chevron', 'caret', 'triangle',
      'close', 'cancel', 'delete', 'remove', 'add', 'plus', 'minus',
      'check', 'radio', 'checkbox', 'toggle', 'switch', 'slider',
      'calendar', 'clock', 'time', 'date', 'location', 'map', 'pin',
      'weather', 'temperature', 'thermometer', 'humidity', 'wind',
      'personne', 'arrete', 'justice', 'prison', 'salle', 'tribunal',
      'barlamane', 'radio', 'hespress', 'medi1', '2m', 'snrt',
    ];

    for (final pattern in rejectPatterns) {
      if (text.contains(pattern)) return true;
    }

    // Reject images with suspiciously short filenames or generic names
    final filename = url.split('/').last;
    if (filename.length < 5) return true;
    if (filename.contains('?')) return true;

    return false;
  }

// Helper to resolve relative image URLs to absolute URLs.
  String _resolveImageUrl(String imgUrl, Uri? pageUri, String origin) {
    if (imgUrl.startsWith('http://') || imgUrl.startsWith('https://')) {
      return imgUrl;
    }
    if (imgUrl.startsWith('//')) {
      return 'https:$imgUrl';
    }
    if (imgUrl.startsWith('/')) {
      return '$origin$imgUrl';
    }
    // Relative to the page path
    final String basePath = pageUri != null && pageUri.path.isNotEmpty
        ? '${pageUri.origin}${pageUri.path}/'
        : '$origin/';
    return '$basePath$imgUrl';
  }

  // Business logic methods (restored with fixes)
  
  /// Detects which engine (server, FFI, or emulator) to use.
  Future<void> autoDetectEngine() async {
    _isConnecting = true;
    notifyListeners();
    
    addLog("[SYSTEM] Starting engine detection...");
    
    // Try server mode first
    try {
      final response = await http
          .get(Uri.parse("http://localhost:8080/logs"))
          .timeout(const Duration(milliseconds: 1000));
      
      if (response.statusCode == 200) {
        _mode = EngineMode.server;
        addLog("[SYSTEM] Detected Running Standalone C++ Server on Port 8080!");
        _isConnecting = false;
        notifyListeners();
        return;
      }
    } catch (_) {
      // Ignore and try next method
    }
    
    // Try FFI if not on web
    if (!kIsWeb) {
      try {
        if (await _tryLoadFFI()) {
          _mode = EngineMode.ffi;
          addLog("[SYSTEM] Loaded yalla_engine.dll via Dart FFI!");
          _isConnecting = false;
          notifyListeners();
          return;
        }
      } catch (_) {
        // Ignore and try emulator
      }
    }
    
    // Fall back to emulator
    _mode = EngineMode.emulator;
    _isConnecting = false;
    addLog("[SYSTEM] Starting built-in Dart News Pipeline Emulator.");
    notifyListeners();
  }
  
  /// Helper method to try loading FFI DLL
  Future<bool> _tryLoadFFI() async {
    return hasNativeEngine;
  }
  
  /// Fallback photo engine for when no suitable images are found
  Future<Map<String, String>> _runPhotoEngine({
    required String title,
    required String imageUrl,
    required String content,
    required String category,
  }) async {
    addLog('[PHOTO ENGINE] Selecting relevant images...');

    final categorySlug = category.toLowerCase();
    final query = Uri.encodeComponent('$categorySlug news');
    final mainImage = imageUrl.isNotEmpty
        ? imageUrl
        : 'https://www.bing.com/images/search?q=$query&first=1';
    final paragraphImages = <String>[
      'https://www.bing.com/images/search?q=$query&first=1',
      'https://www.bing.com/images/search?q=${Uri.encodeComponent(categorySlug)}&first=1',
      'https://www.bing.com/images/search?q=${Uri.encodeComponent(title)}&first=1',
    ];

    String finalContent = content;
    if (paragraphImages.isNotEmpty && finalContent.isNotEmpty) {
      finalContent = _injectImagesIntoContent(
        finalContent,
        paragraphImages,
        title: title,
        description: content.length > 200 ? content.substring(0, 200) : null,
        metaKeywords: extractKeywords(title, content, category),
      );
      addLog('[PHOTO ENGINE] Injected ${paragraphImages.length} paragraph image(s).');
    }

    addLog('[PHOTO ENGINE] Complete.');
    return {'imageUrl': mainImage, 'content': finalContent};
  }

  Future<bool> _validateImageWithTinyLlm({
    required String title,
    required String content,
    String? description,
    required String imageUrl,
  }) async {
    try {
      final result = await compute<Map<String, dynamic>, Map<String, dynamic>>(
        (input) {
          try {
            return validateImageRelevance(
              title: input['title'] as String,
              content: input['content'] as String,
              description: input['description'] as String? ?? '',
              imageUrl: input['imageUrl'] as String,
            );
          } catch (e) {
            return {'relevant': 0, 'score': 0.0, 'reasons': ['exception']};
          }
        },
        {'title': title, 'content': content, 'description': description ?? '', 'imageUrl': imageUrl},
      );
      final relevant = result['relevant'] == 1;
      final score = (result['score'] as num?)?.toDouble() ?? 0.0;
      if (!relevant) {
        addLog('[TinyLLM] Rejected image: $imageUrl (score=$score, reasons=${result['reasons']})');
      }
      return relevant;
    } catch (_) {
      return false;
    }
  }

  /// Processes a news URL and returns a news model
  Future<Map<String, dynamic>> processNewsUrl(
    String url,
    String localDbJson, {
    bool silent = false,
  }) async {
    try {
      if (!silent) {
        addLog('[SYSTEM] Processing URL: $url');
      }
      
      // Fetch the content from the URL
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );
      
      if (response.statusCode != 200) {
        if (!silent) {
          addLog('[ERROR] Failed to fetch URL: HTTP ${response.statusCode}');
        }
        return {};
      }
      
      final html = response.body;

      if (!NewsUriParser.isValidArticleUrl(url)) {
        addLog('[SYSTEM] Source homepage detected. Extracting article links...');
        final document = parse(html);
        final baseUri = Uri.parse(url);
        final Set<String> articleUrls = {};

        for (final element in document.querySelectorAll('a[href]')) {
          final href = element.attributes['href'];
          if (href == null || href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) continue;

          Uri linkUri;
          try {
            linkUri = Uri.parse(href);
          } catch (_) {
            continue;
          }

          if (!linkUri.hasScheme) {
            linkUri = baseUri.resolve(href);
          }

          final linkUrl = linkUri.toString();
          if (NewsUriParser.isValidArticleUrl(linkUrl)) {
            articleUrls.add(linkUrl);
          }
        }

        final parsed = articleUrls.map((u) => NewsUriParser.parseUri(u)).toList();
        parsed.sort((a, b) => b.priority.compareTo(a.priority));
        final limited = parsed.take(50).map((p) => p.url).toList();

        return {
          'success': true,
          'is_source': true,
          'articles': limited,
        };
      }
      
      // Extract title from HTML
      final titleMatch = RegExp(
        r'<title[^>]*>([^<]+)</title>',
        caseSensitive: false,
      ).firstMatch(html);
      final title = titleMatch != null ? titleMatch.group(1)! : 'Untitled';
      
final descMatch = RegExp(
         """<meta[^>]+name=["']description["'][^>]+content=["']([^"']*)["'][^>]*>""",
         caseSensitive: false,
       ).firstMatch(html);
       final summary = descMatch != null ? descMatch.group(1)! : '';
       
       // Extract Open Graph description as fallback
       final ogDescMatch = RegExp(
         """<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']*)["'][^>]*>""",
         caseSensitive: false,
       ).firstMatch(html);
       final ogDescription = ogDescMatch != null ? ogDescMatch.group(1)! : '';
       
       // Use the longer of the two descriptions
       final effectiveSummary = summary.length > ogDescription.length 
           ? summary : ogDescription;
      
      // Extract main content (simplified - in reality this would be more complex)
      // Remove scripts and styles
      String content = html.replaceAll(RegExp(r'<script\b[^>]*>.*?</script>', 
          dotAll: true, caseSensitive: false), '');
      content = content.replaceAll(RegExp(r'<style\b[^>]*>.*?</style>', 
          dotAll: true, caseSensitive: false), '');
      
      // Extract text content from common article tags
      final contentPatterns = [
        "<article[^>]*>(.*?)</article>",
        "<main[^>]*>(.*?)</main>",
        "<div[^>]+class=[\"'][^\"']*(?:article|content|post|entry)[^\"']*[\"'][^>]*>(.*?)</div>",
        "<div[^>]+id=[\"'][^\"']*(?:article|content|post|entry)[^\"']*[\"'][^>]*>(.*?)</div>",
      ];
      
      String extractedContent = '';
      for (final pattern in contentPatterns) {
        final match = RegExp(pattern, dotAll: true, caseSensitive: false)
            .firstMatch(content);
        if (match != null && match.group(1) != null) {
          extractedContent = match.group(1)!;
          break;
        }
      }
      
      // If no specific content found, use body text
      if (extractedContent.isEmpty) {
        final bodyMatch = RegExp(r'<body[^>]*>(.*?)</body>', 
            dotAll: true, caseSensitive: false).firstMatch(html);
        extractedContent = bodyMatch != null ? bodyMatch.group(1)! : '';
      }
      
      // Fallback: extract from <p> tags if content is still too short
      if (extractedContent.length < 200) {
        final pTags = RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true, caseSensitive: false)
            .allMatches(content)
            .map((m) => m.group(1) ?? '')
            .toList();
        if (pTags.isNotEmpty) {
          extractedContent = pTags.join('\n\n');
        }
      }
      
      // Clean HTML tags from content while preserving paragraph structure
      extractedContent = extractedContent.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
      extractedContent = extractedContent.replaceAll(RegExp(r'</?(p|div|li|tr|td|h[1-6]|blockquote|pre|ul|ol)[^>]*>', caseSensitive: false), '\n');
      extractedContent = extractedContent.replaceAll(RegExp(r'<[^>]+>'), ' ');
      extractedContent = extractedContent.replaceAll(RegExp(r'[ \t]+\n'), '\n');
      extractedContent = extractedContent.replaceAll(RegExp(r'\n{3,}'), '\n\n');
      extractedContent = extractedContent.replaceAll(RegExp(r'\s*#\w+(?:\s*#\w+)*\s*'), ' ');
      extractedContent = extractedContent.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
      
      // Remove breadcrumb/navigation text from raw HTML content
      extractedContent = extractedContent.replaceAll(RegExp(r'الرئيسية\s*/\s*الأخبار\s*/.*', caseSensitive: false), '');
      extractedContent = extractedContent.replaceAll(RegExp(r'الرئيسية\s*/\s*.*', caseSensitive: false), '');
      extractedContent = extractedContent.replaceAll(RegExp(r'الصفحه\s+الرئيسية.*', caseSensitive: false), '');
      extractedContent = extractedContent.replaceAll(RegExp(r'الصفحه\s+الرئيسيه.*', caseSensitive: false), '');
      extractedContent = extractedContent.replaceAll(RegExp(r'الرئيسيه\s*/\s*.*', caseSensitive: false), '');
      
      // Decode HTML entities and strip HTML tags for summary
      final decodedTitle = _decodeHtml(title);
      final cleanedTitle = cleanTitle(decodedTitle, url);
      final decodedSummary = _stripHtmlTags(_decodeHtml(effectiveSummary));
      var decodedContent = _decodeHtml(extractedContent);
      
      // If still empty, use a fallback
      if (decodedContent.isEmpty) {
        final fallbackContent = 'Content extracted from $url';
        decodedContent = fallbackContent;
      }
      
      // Remove duplicate paragraphs before TinyLLM cleaning
      final paragraphs = decodedContent.split('\n').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
      final seen = <String>{};
      final unique = <String>[];
      for (final p in paragraphs) {
        final key = p.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
        if (seen.add(key)) {
          unique.add(p);
        }
      }
      decodedContent = unique.join('\n\n');
      
      // TinyLLM C++ Content Cleaning
      String tinyLlmCleanedContent = decodedContent;
      Map<String, dynamic> storyElements = {};
      if (hasNativeEngine) {
        try {
          final cleanResult = cleanArticleContentJson(cleanedTitle, decodedContent);
          if (cleanResult.isNotEmpty) {
            tinyLlmCleanedContent = cleanResult['cleaned_content'] ?? decodedContent;
            final removed = cleanResult['removed_segments'] as List<dynamic>?;
            if (removed != null && removed.isNotEmpty) {
              addLog('[TinyLLM] Removed ${removed.length} off-topic/garbled segments');
            }
          }
          
          storyElements = extractStoryElementsJson(cleanedTitle, tinyLlmCleanedContent);
          if (storyElements.isNotEmpty) {
            final persons = (storyElements['persons'] as List<dynamic>?) ?? [];
            final dates = (storyElements['dates'] as List<dynamic>?) ?? [];
            final events = (storyElements['events'] as List<dynamic>?) ?? [];
            addLog('[TinyLLM] Extracted ${persons.length} persons, ${dates.length} dates, ${events.length} events');
          }
        } catch (_) {
          // Non-fatal: continue with uncleaned content
        }
      }
      
      // Remove duplicate paragraphs again after TinyLLM cleaning
      final postParagraphs = tinyLlmCleanedContent.split('\n').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
      final postSeen = <String>{};
      final postUnique = <String>[];
      for (final p in postParagraphs) {
        final key = p.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
        if (postSeen.add(key)) {
          postUnique.add(p);
        }
      }
      tinyLlmCleanedContent = postUnique.join('\n\n');
      
      // Local Ollama rewrite: removed to preserve real article content
      // The app now uses extracted real content only, no LLM-generated news text
      
      // Extract and enhance images
      final imageResult = await _extractImagesAndEnrichContent(
        html: html,
        content: tinyLlmCleanedContent,
        title: cleanedTitle,
        category: 'general', // Default category, could be enhanced with AI
        url: url,
        metaImageUrl: '', // Could be extracted from og:image
      );
      
      final processedContent = imageResult['content'] ?? tinyLlmCleanedContent;
      String imageUrl = (imageResult['imageUrl'] ?? '').trim();

      if (imageUrl.isEmpty) {
        final categorySlug = 'general';
        imageUrl = 'https://placehold.co/800x500/1A1A2E/C62828?text=$categorySlug';
      }
      
      // Optimized sentiment analysis
      final optimizedSentiment = hasNativeEngine
          ? optimizeSentiment('$cleanedTitle $tinyLlmCleanedContent')
          : _calculateSentiment('$cleanedTitle $decodedSummary');
      
      // Build structured data from story elements
      final structuredData = <String, dynamic>{
        'persons': (storyElements['persons'] as List<dynamic>?) ?? [],
        'dates': (storyElements['dates'] as List<dynamic>?) ?? [],
        'events': (storyElements['events'] as List<dynamic>?) ?? [],
        'title_keywords': (storyElements['title_keywords'] as List<dynamic>?) ?? [],
        'removed_segments': (storyElements['removed_segments'] as List<dynamic>?) ?? [],
      };
      
      // Build entities from story elements
      final entities = <String>[];
      final persons = (storyElements['persons'] as List<dynamic>?) ?? [];
      for (final p in persons) {
        entities.add(p.toString());
      }
      final dates = (storyElements['dates'] as List<dynamic>?) ?? [];
      for (final d in dates) {
        entities.add(d.toString());
      }
      
      // Determine event type
      String eventType = 'general';
      final events = (storyElements['events'] as List<dynamic>?) ?? [];
      if (events.isNotEmpty) {
        eventType = 'event_detected';
      }
      
         // Create news model
         String generatedShortTitle = cleanedTitle;
         if (cleanedTitle.length > 60) {
           final sentences = cleanedTitle.split(RegExp(r'[.؟!]'));
           if (sentences.length > 1 && sentences.first.trim().length >= 20) {
             generatedShortTitle = sentences.first.trim();
           } else {
             final words = cleanedTitle.split(RegExp(r'\s+'));
             generatedShortTitle = words.take(12).join(' ');
             if (cleanedTitle.length > generatedShortTitle.length) {
               generatedShortTitle += '...';
             }
           }
         }
         final newsModel = NewsModel(
           url: url,
           title: cleanedTitle,
           shortTitle: generatedShortTitle,
           summary: decodedSummary,
          content: tinyLlmCleanedContent,
          imageUrl: imageUrl,
          category: 'general', // Would be determined from content analysis
          sentiment: optimizedSentiment,
          keywords: extractKeywords(cleanedTitle, decodedSummary, tinyLlmCleanedContent),
          logs: '', // Could be populated with processing logs
          author: '', // Could be extracted from meta tags
          publishDate: DateTime.now().toIso8601String(),
          eventType: eventType,
          subcategory: 'general',
          entities: entities,
          structuredData: structuredData,
          intelligenceJson: '',
          sourceCount: 1,
          sources: [url],
        );
       
       if (!silent) {
         addLog('[SYSTEM] Successfully processed article: "${cleanedTitle}"');
       }
      
      final result = newsModel.toJson();
      result['success'] = true;
      result['is_source'] = false;
      return result;
    } catch (e, stackTrace) {
      if (!silent) {
        addLog('[ERROR] Failed to process URL: $e');
        if (kDebugMode) {
          print(stackTrace);
        }
      }
      return {};
    }
  }

  static String _buildHashtags(String keywords, String category) {
    final buffer = StringBuffer('#أخبار ');
    final normalizedCategory = category.trim();
    if (normalizedCategory.isNotEmpty) {
      buffer.write('#$normalizedCategory ');
    }

    if (keywords.isNotEmpty) {
      final tags = keywords
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map((e) => e.replaceAll(RegExp(r'\s+'), '_'))
          .toSet()
          .take(8)
          .toList();
      for (final tag in tags) {
        buffer.write('#$tag ');
      }
    }

    return buffer.toString().trim();
  }

  static String _extractYouTubeVideoId(String title, String html) {
    final embedPattern = RegExp(r'youtube\.com/embed/([\w\-]+)', caseSensitive: false);
    final matches = embedPattern.allMatches(html);
    final ids = matches.map((m) => m.group(1)!).toSet().toList();
    if (ids.isEmpty) return '';
    return ids.first;
  }

  static String _extractInstagramVideoId(String html) {
    final pattern = RegExp(r'instagram\.com/(?:p|reel|tv)/([^/?\s"]+)', caseSensitive: false);
    final match = pattern.firstMatch(html);
    return match != null && match.groupCount >= 1 ? match.group(1)! : '';
  }

  static String _extractTwitterVideoUrl(String html) {
    final pattern = RegExp(r'https?://(?:twitter\.com|x\.com)/[a-z0-9_]+/status/\d+', caseSensitive: false);
    final match = pattern.firstMatch(html);
    return match != null ? match.group(0)! : '';
  }

  static String _generateImageId() {
    final rand = Random();
    final timestamp = DateTime.now().microsecondsSinceEpoch.toString();
    final randomPart = String.fromCharCodes(List.generate(8, (_) => 65 + rand.nextInt(26)));
    final numberPart = (rand.nextInt(900) + 100).toString();
    return '$numberPart$randomPart';
  }
}