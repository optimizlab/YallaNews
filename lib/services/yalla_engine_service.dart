// IMPORT DART ASYNC
import 'dart:async';
import 'dart:convert';
import 'dart:core';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;

import '../models/news_model.dart';
import 'tiny_llm_service.dart';
import 'news_uri_parser.dart';
import 'image_validator_service.dart';
import 'engine_ffi.dart';

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
  static List<String> _extractKeywords(
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

  /// Injects image HTML tags at regular intervals between content paragraphs.
  static String _injectImagesIntoContent(
    String content,
    List<String> imageUrls,
  ) {
    if (imageUrls.isEmpty || content.isEmpty) return content;

    const imgStyle =
        'width:100%;max-height:380px;object-fit:cover;border-radius:12px;margin:16px 0;display:block;';

    final segments = _splitContentIntoSegments(content);

    if (segments.length < 2) {
      final buf = StringBuffer(content);
      for (final img in imageUrls) {
        buf.write('\n\n<img src="$img" style="$imgStyle" />');
      }
      return buf.toString();
    }

    final buf = StringBuffer();
    int imgIdx = 0;
    for (int i = 0; i < segments.length; i++) {
      buf.write(segments[i]);
      if ((i + 1) % 2 == 0 && imgIdx < imageUrls.length) {
        buf.write('<img src="${imageUrls[imgIdx++]}" style="$imgStyle" />');
      }
      if (i < segments.length - 1) {
        buf.write('\n\n');
      }
    }
    while (imgIdx < imageUrls.length) {
      buf.write('<img src="${imageUrls[imgIdx++]}" style="$imgStyle" />\n\n');
    }
    return buf.toString().trimRight();
  }

  static List<String> _splitContentIntoSegments(String content) {
    if (content.isEmpty) return const [];
    
    final segments = content
        .split(RegExp(r'(?<=[.!?؟!])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.length >= 5)
        .toList();
    
    if (segments.length >= 2) {
      return segments;
    }
    
    final paragraphs = content
        .split(RegExp(r'\n\s*\n|\n{2,}'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.length >= 3)
        .toList();
    
    if (paragraphs.length >= 2) {
      return paragraphs;
    }
    
    return [content.trim()];
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
      // Fall back to photo engine
      final photoResult = await _runPhotoEngine(
        title: title,
        imageUrl: '',
        content: content,
        category: category,
      );
      return photoResult;
    }

    // Score each image
    final keywords = _extractKeywords(title, content, '');
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

      // Score based on type
      if (type == 'og' || type == 'twitter' || type == 'meta') {
        // Base score for social/meta images
        score += 1.0;
      }

      // Score based on URL containing keywords
      for (final word in titleWords) {
        if (url.contains(word)) {
          score += 1.0;
        }
      }

      // For img tags, also score alt and title
      if (type == 'img') {
        for (final word in titleWords) {
          if (alt.contains(word)) {
            score += 2.0; // alt is more important
          }
          if (titleText.contains(word)) {
            score += 1.0;
          }
        }
        if (alt.isNotEmpty) {
          score += 0.5; // bonus for having alt text
        }
      }

      scores.add(score);
    }

    // Sort indices by score descending
    final indices = List.generate(extractedImages.length, (i) => i);
    indices.sort((a, b) => scores[b].compareTo(scores[a]));

    // Determine if we have a good enough image (score >= 1.0)
    final hasGoodImage = scores.isNotEmpty && scores[indices.first] >= 1.0;

    String finalImageUrl;
    List<String> additionalImages = [];

    if (hasGoodImage) {
      // Use the highest scoring image as the main image
      finalImageUrl = extractedImages[indices.first];
      // Take up to 3 additional images (next highest scoring)
      for (int i = 1; i < indices.length && i <= 3; i++) {
        additionalImages.add(extractedImages[indices[i]]);
      }
    } else {
      // No good image found, fall back to photo engine for main image
      final photoResult = await _runPhotoEngine(
        title: title,
        imageUrl: '',
        content: content,
        category: category,
      );
      finalImageUrl = photoResult['imageUrl']!;
      // The photo engine already returns content with images injected, so we return early
      return photoResult;
    }

    // Inject additional images into content
    if (additionalImages.isNotEmpty) {
      content = _injectImagesIntoContent(content, additionalImages);
    }

    return {'imageUrl': finalImageUrl, 'content': content};
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
    try {
      // This would typically involve calling YallaFFIService.loadLibrary()
      // For now, return false to simulate FFI not available
      return false;
    } catch (_) {
      return false;
    }
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
      finalContent = _injectImagesIntoContent(finalContent, paragraphImages);
      addLog('[PHOTO ENGINE] Injected ${paragraphImages.length} paragraph image(s).');
    }

    addLog('[PHOTO ENGINE] Complete.');
    return {'imageUrl': mainImage, 'content': finalContent};
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
      extractedContent = extractedContent.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
      
      // Decode HTML entities
      final decodedTitle = _decodeHtml(title);
      final cleanedTitle = cleanTitle(decodedTitle, url);
      final decodedSummary = _decodeHtml(effectiveSummary);
      var decodedContent = _decodeHtml(extractedContent);
      
      // If still empty, use a fallback
      if (decodedContent.isEmpty) {
        final fallbackContent = 'Content extracted from $url';
        decodedContent = fallbackContent;
      }
      
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
          : 0.0;
      
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
        final newsModel = NewsModel(
          url: url,
          title: cleanedTitle,
          shortTitle: '',
          summary: decodedSummary,
          content: tinyLlmCleanedContent,
          imageUrl: imageUrl,
          category: 'general', // Would be determined from content analysis
          sentiment: optimizedSentiment,
          keywords: _extractKeywords(cleanedTitle, decodedSummary, tinyLlmCleanedContent),
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
        // In debug mode, print stack trace
if (kDebugMode) {
           print(stackTrace);
         }
       }
       return {};
     }
   }
}