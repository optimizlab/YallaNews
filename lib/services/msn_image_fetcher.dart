/// msn_image_fetcher.dart
///
/// Fetches relevant images for news articles across multiple famous search engines:
/// Bing/MSN, Google Images, DuckDuckGo, Yahoo Images, and Qwant.
///
/// Implements randomized engine selection: never uses only one search engine,
/// but dynamically randomizes between the famous search engines.

library msn_image_fetcher;

import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

enum FamousSearchEngine {
  bing,
  google,
  duckDuckGo,
  yahoo,
  qwant,
}

class MsnImageFetcher {
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Safari/537.36';

  /// Minimum width/height we consider a "real" image (not icon/logo).
  static const int _minImageSize = 200;

  /// Cache: query → list of image URLs (in-process memory, cleared on restart)
  static final _cache = <String, List<String>>{};

  /// Fetch up to [maxImages] image URLs for [query].
  /// Never uses only one search engine: randomizes between famous engines
  /// (Bing, Google, DuckDuckGo, Yahoo, Qwant) to find the best news images.
  static Future<List<String>> fetchImages(
    String query, {
    int maxImages = 5,
  }) async {
    final cleanQuery = cleanNewsTitleForSearch(query);
    final cacheKey = cleanQuery.trim().toLowerCase();
    if (_cache.containsKey(cacheKey) && _cache[cacheKey]!.isNotEmpty) {
      return _cache[cacheKey]!;
    }

    final urls = <String>[];

    // Randomize between famous search engines
    final engines = [
      FamousSearchEngine.bing,
      FamousSearchEngine.google,
      FamousSearchEngine.duckDuckGo,
      FamousSearchEngine.yahoo,
      FamousSearchEngine.qwant,
    ]..shuffle(Random());

    for (final engine in engines) {
      if (urls.length >= maxImages) break;
      try {
        List<String> engineUrls = [];
        switch (engine) {
          case FamousSearchEngine.bing:
            engineUrls = await _fetchFromBing(cleanQuery, maxImages - urls.length);
            break;
          case FamousSearchEngine.google:
            engineUrls = await _fetchFromGoogle(cleanQuery, maxImages - urls.length);
            break;
          case FamousSearchEngine.duckDuckGo:
            engineUrls = await _fetchFromDuckDuckGo(cleanQuery, maxImages - urls.length);
            break;
          case FamousSearchEngine.yahoo:
            engineUrls = await _fetchFromYahoo(cleanQuery, maxImages - urls.length);
            break;
          case FamousSearchEngine.qwant:
            engineUrls = await _fetchFromQwant(cleanQuery, maxImages - urls.length);
            break;
        }

        for (final u in engineUrls) {
          if (!urls.contains(u) && _isValidImageUrl(u) && !isPlaceholderOrEmpty(u)) {
            urls.add(u);
          }
        }
      } catch (_) {}
    }

    final unique = urls.toSet().toList();
    if (unique.isNotEmpty) _cache[cacheKey] = unique;
    return unique;
  }

  /// Cleans the news title by removing source attributions and trailing tags
  /// (e.g., "| BBC News", "- CNN", " | الجزيرة نت") so the search engine query
  /// targets the actual topic and gets relevant images.
  static String cleanNewsTitleForSearch(String title) {
    var cleaned = title.trim();
    // Strip common site branding at the end: | BBC News, - Reuters, etc.
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s*([|–—\-:]\s*(BBC News|BBC|CNN|Reuters|Associated Press|AP|Al Jazeera|الجزيرة|العربية|سكاي نيوز|Sky News|France 24|The Guardian|The New York Times|Fox News|Yahoo News|Google News|News|اخبار|أخبار).*)$',
        caseSensitive: false,
      ),
      '',
    );
    // Remove extra punctuation
    cleaned = cleaned.replaceAll(RegExp(r'["“”«»]'), ' ').trim();
    return cleaned.isNotEmpty ? cleaned : title.trim();
  }

  /// Fetch up to [maxImages] news images from randomized famous engines then pick ONE.
  static Future<String?> fetchRandomImage(String query) async {
    final pool = await fetchImages(query, maxImages: 5);
    if (pool.isEmpty) return null;
    final idx = Random().nextInt(pool.length.clamp(1, 5));
    return pool[idx];
  }

  /// Synchronous wrapper — returns cached results only. Use when inside an isolate.
  static List<String> getCached(String query) =>
      _cache[query.trim().toLowerCase()] ?? [];

  /// Strict validator for placeholder, blank, broken, or empty image URLs.
  static bool isPlaceholderOrEmpty(String? url) {
    if (url == null) return true;
    final trimmed = url.trim().toLowerCase();
    if (trimmed.isEmpty || trimmed.length < 15) return true;
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) return true;

    final badPatterns = [
      'placehold.co',
      'placeholder',
      'default-image',
      'default_image',
      'no-image',
      'image_not_found',
      '1x1',
      'pixel',
      'blank.png',
      'blank.gif',
      'transparent.png',
      'spinner',
      'loading',
      'broken_image',
      'image.png',
      'favicon',
      'profile-pic',
      'profile_pic',
    ];

    for (final pattern in badPatterns) {
      if (trimmed.contains(pattern)) return true;
    }

    return false;
  }

  /// Builds a concise search query from a paragraph's text.
  static String buildParagraphQuery(String paragraph, {String? fallbackTitle}) {
    final cleaned = paragraph
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    const stopWords = {
      'the', 'and', 'for', 'with', 'that', 'this', 'from', 'was', 'were',
      'are', 'have', 'has', 'had', 'not', 'but', 'into', 'about', 'after',
      'dans', 'avec', 'pour', 'que', 'qui', 'une', 'des', 'les', 'est', 'sont',
      'sur', 'par', 'plus', 'cette', 'son', 'ses', 'aux', 'mais',
      'من', 'في', 'على', 'إلى', 'عن', 'مع', 'هذا', 'هذه', 'ذلك', 'أن', 'إن',
      'كان', 'كانت', 'التي', 'الذي', 'الذين', 'بين', 'بعد', 'قبل', 'خلال', 'كما',
    };
    final words = cleaned
        .split(' ')
        .where((w) => w.length >= 3 && !stopWords.contains(w.toLowerCase()))
        .take(7)
        .toList();
    if (words.length >= 2) {
      return words.join(' ');
    }
    return (fallbackTitle ?? cleaned).trim();
  }

  /// Searches web images for a paragraph's text and picks one randomly.
  static Future<String?> fetchRandomImageForParagraph(
    String paragraph, {
    String? fallbackTitle,
    Set<String> excludeUrls = const {},
  }) async {
    final query = buildParagraphQuery(paragraph, fallbackTitle: fallbackTitle);
    if (query.isEmpty) return null;
    final pool = (await fetchImages(query, maxImages: 5))
        .where((u) => !excludeUrls.contains(u) && !isPlaceholderOrEmpty(u))
        .toList();
    if (pool.isEmpty) return null;
    final idx = Random().nextInt(pool.length.clamp(1, 5));
    return pool[idx];
  }

  // ── Engine 1: Bing / MSN Images ────────────────────────────────────────────

  static Future<List<String>> _fetchFromBing(String query, int max) async {
    final encoded = Uri.encodeQueryComponent(query);
    final searchUrl =
        'https://www.bing.com/images/search?q=${encoded}+news'
        '&form=HDRSC2&safeSearch=Moderate&first=1';

    final response = await http
        .get(Uri.parse(searchUrl), headers: {
          'User-Agent': _ua,
          'Accept-Language': 'ar,en;q=0.9',
        })
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) return [];
    return _extractBingImageUrls(response.body, max);
  }

  static List<String> _extractBingImageUrls(String html, int max) {
    final urls = <String>[];

    final murlRe = RegExp(r'"murl"\s*:\s*"(https?://[^"]+)"');
    for (final m in murlRe.allMatches(html)) {
      final url = m.group(1);
      if (url == null) continue;
      if (_isValidImageUrl(url)) {
        urls.add(url);
        if (urls.length >= max) break;
      }
    }

    if (urls.isEmpty) {
      final ogRe = RegExp(
          r'<meta[^>]+(?:property="og:image"|name="twitter:image")[^>]+content="([^"]+)"',
          caseSensitive: false);
      for (final m in ogRe.allMatches(html)) {
        final url = m.group(1);
        if (url != null && _isValidImageUrl(url)) {
          urls.add(url);
          if (urls.length >= max) break;
        }
      }
    }

    return urls;
  }

  // ── Engine 2: Google Images ────────────────────────────────────────────────

  static Future<List<String>> _fetchFromGoogle(String query, int max) async {
    final encoded = Uri.encodeQueryComponent(query);
    final searchUrl =
        'https://www.google.com/search?tbm=isch&q=${encoded}+news&hl=en&gl=us';

    final response = await http
        .get(Uri.parse(searchUrl), headers: {
          'User-Agent': _ua,
          'Accept-Language': 'en-US,en;q=0.9,ar;q=0.8',
          'Referer': 'https://www.google.com/',
        })
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) return [];

    final urls = <String>[];
    // Google embedded JSON format for images
    final pattern = RegExp(
      r'\["(https?://[^"]+\.(?:jpe?g|png|webp)(?:\?[^"]*)?)",\s*\d+,\s*\d+\]',
      caseSensitive: false,
    );
    for (final m in pattern.allMatches(response.body)) {
      final u = m.group(1);
      if (u != null && _isValidImageUrl(u) && !urls.contains(u)) {
        urls.add(u);
        if (urls.length >= max) break;
      }
    }

    // Secondary fallback: encrypted gstatic thumbnails
    if (urls.isEmpty) {
      final tbnPattern = RegExp(
        r'src="(https://encrypted-tbn0\.gstatic\.com/images\?q=[^"]+)"',
      );
      for (final m in tbnPattern.allMatches(response.body)) {
        final u = m.group(1);
        if (u != null && !urls.contains(u)) {
          urls.add(u);
          if (urls.length >= max) break;
        }
      }
    }

    return urls;
  }

  // ── Engine 3: DuckDuckGo Images ────────────────────────────────────────────

  static Future<List<String>> _fetchFromDuckDuckGo(String query, int max) async {
    final encoded = Uri.encodeQueryComponent(query);
    // Step 1: get vqd token
    final tokenUrl = 'https://duckduckgo.com/?q=${encoded}&iar=images&iax=images&ia=images';
    final tokenResp = await http
        .get(Uri.parse(tokenUrl), headers: {
          'User-Agent': _ua,
          'Accept-Language': 'en-US,en;q=0.9',
        })
        .timeout(const Duration(seconds: 6));

    if (tokenResp.statusCode != 200) return [];

    final vqdMatch = RegExp(r'vqd=([0-9-_]+)').firstMatch(tokenResp.body) ??
        RegExp(r'vqd="([^"]+)"').firstMatch(tokenResp.body);
    if (vqdMatch == null) return [];
    final vqd = vqdMatch.group(1);

    // Step 2: request image json
    final iUrl = 'https://duckduckgo.com/i.js?l=us-en&o=json&q=$encoded&vqd=$vqd&f=,,,&p=1';
    final iResp = await http
        .get(Uri.parse(iUrl), headers: {
          'User-Agent': _ua,
          'Accept': 'application/json',
          'Referer': 'https://duckduckgo.com/',
        })
        .timeout(const Duration(seconds: 8));

    if (iResp.statusCode != 200) return [];

    final data = jsonDecode(iResp.body) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>? ?? [];
    final urls = <String>[];

    for (final item in results) {
      if (item is Map<String, dynamic>) {
        final img = item['image'] as String?;
        if (img != null && _isValidImageUrl(img)) {
          urls.add(img);
          if (urls.length >= max) break;
        }
      }
    }

    return urls;
  }

  // ── Engine 4: Yahoo Images ─────────────────────────────────────────────────

  static Future<List<String>> _fetchFromYahoo(String query, int max) async {
    final encoded = Uri.encodeQueryComponent(query);
    final searchUrl = 'https://images.search.yahoo.com/search/images?p=${encoded}+news';

    final response = await http
        .get(Uri.parse(searchUrl), headers: {
          'User-Agent': _ua,
          'Accept-Language': 'en-US,en;q=0.9',
        })
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) return [];

    final urls = <String>[];
    final yahooRe = RegExp(r'data-src="(https?://[^"]+)"');
    for (final m in yahooRe.allMatches(response.body)) {
      final u = m.group(1);
      if (u != null && _isValidImageUrl(u) && !urls.contains(u)) {
        urls.add(u);
        if (urls.length >= max) break;
      }
    }

    if (urls.isEmpty) {
      final iurlRe = RegExp(r'"iurl"\s*:\s*"(https?://[^"]+)"');
      for (final m in iurlRe.allMatches(response.body)) {
        final u = m.group(1);
        if (u != null && _isValidImageUrl(u) && !urls.contains(u)) {
          urls.add(u);
          if (urls.length >= max) break;
        }
      }
    }

    return urls;
  }

  // ── Engine 5: Qwant Images ─────────────────────────────────────────────────

  static Future<List<String>> _fetchFromQwant(String query, int max) async {
    final encoded = Uri.encodeQueryComponent(query);
    final searchUrl = 'https://www.qwant.com/?l=en&t=images&q=$encoded';

    final response = await http
        .get(Uri.parse(searchUrl), headers: {
          'User-Agent': _ua,
          'Accept-Language': 'ar,en;q=0.9',
        })
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) return [];
    return _extractQwantImageUrls(response.body, max);
  }

  static List<String> _extractQwantImageUrls(String html, int max) {
    final urls = <String>[];

    final qwantRe = RegExp(r'"media"\s*:\s*"(https?://[^"]+)"');
    for (final m in qwantRe.allMatches(html)) {
      final url = m.group(1);
      if (url == null) continue;
      if (_isValidImageUrl(url)) {
        urls.add(url);
        if (urls.length >= max) break;
      }
    }

    return urls;
  }

  static bool _isValidImageUrl(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    final validExt = lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.contains('images') ||
        lower.contains('th.bing.com') ||
        lower.contains('encrypted-tbn0.gstatic.com') ||
        lower.contains('img') ||
        lower.contains('photo') ||
        lower.contains('picture') ||
        lower.contains('media');
    if (!validExt) return false;
    if (lower.contains('logo') ||
        lower.contains('icon') ||
        lower.contains('favicon') ||
        lower.contains('pixel') ||
        lower.contains('tracking') ||
        lower.contains('ad.')) return false;
    return true;
  }
}

/// Injects image HTML tags between content paragraphs.
String injectImagesIntoParagraphs(
  List<String> paragraphs,
  List<String> imageUrls, {
  int injectEveryN = 3,
}) {
  if (paragraphs.isEmpty) return '';

  final rng = Random();
  final shuffled = List<String>.from(imageUrls)..shuffle(rng);
  int imgIdx = 0;

  const imgStyle =
      'width:100%;max-height:420px;object-fit:cover;'
      'border-radius:14px;margin:18px 0 10px 0;display:block;'
      'box-shadow:0 4px 18px rgba(0,0,0,0.13);';

  const paraStyle =
      'font-size:16px;line-height:1.9;margin:0 0 14px 0;'
      'color:inherit;text-align:justify;';

  final buf = StringBuffer();
  for (int i = 0; i < paragraphs.length; i++) {
    final para = paragraphs[i].trim();
    if (para.isEmpty) continue;

    buf.write('<p style="$paraStyle">$para</p>\n');

    // Inject image after every Nth paragraph
    if ((i + 1) % injectEveryN == 0 && imgIdx < shuffled.length) {
      final imgUrl = shuffled[imgIdx++];
      buf.write('<img src="$imgUrl" style="$imgStyle" loading="lazy" />\n');
    }
  }

  return buf.toString();
}

/// Injects a single image exactly once after paragraph 2.
String injectSingleImage(List<String> paragraphs, String? imageUrl) {
  if (paragraphs.isEmpty) return '';

  const imgStyle =
      'width:100%;max-height:420px;object-fit:cover;'
      'border-radius:14px;margin:18px 0 10px 0;display:block;'
      'box-shadow:0 4px 18px rgba(0,0,0,0.13);';

  const paraStyle =
      'font-size:16px;line-height:1.9;margin:0 0 14px 0;'
      'color:inherit;text-align:justify;';

  final buf = StringBuffer();
  for (int i = 0; i < paragraphs.length; i++) {
    final para = paragraphs[i].trim();
    if (para.isEmpty) continue;

    buf.write('<p style="$paraStyle">$para</p>\n');

    if (imageUrl != null && (i == 1 || (i == paragraphs.length - 1 && i < 1))) {
      buf.write('<img src="$imageUrl" style="$imgStyle" loading="lazy" />\n');
      imageUrl = null;
    }
  }

  return buf.toString();
}
