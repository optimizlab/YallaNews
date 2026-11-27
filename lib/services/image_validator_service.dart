import 'dart:convert';
import 'package:html/dom.dart' as dom;
import 'arabic_normalizer.dart';
import 'msn_image_fetcher.dart';

class ImageCandidate {
  final String url;
  final String altText;
  final int width;
  final int height;
  final String source; // 'og', 'twitter', 'img'

  ImageCandidate({
    required this.url,
    this.altText = '',
    this.width = 0,
    this.height = 0,
    this.source = 'img',
  });

  @override
  String toString() => 'ImageCandidate(url: $url, source: $source, alt: $altText)';
}

class ImageValidatorService {
  // Rolling cache of recently used image URLs to prevent massive cross-article duplication
  static final Set<String> _usedImages = {};
  static const int _maxCacheSize = 500;

  static const List<String> _blacklistTerms = [
    'placeholder', 'default', 'spinner', 'loading', '1x1', 'pixel',
    'thumb_small', 'svg', 'favicon', 'profile-pic', 'coat-of-arms',
    'watermark', 'badge', 'microsite', 'ad-banner', 'ad_banner',
    'broken_image', 'placehold.co'
  ];

  static const List<String> _badPathSegments = [
    '/assets/', '/images/logos', '/static/img/', '/static/images/',
    '/graphics/', '/advertising/', '/ads/', '/banners/'
  ];

  static const List<String> _badExtensions = [
    '.css', '.js', '.json', '.xml', '.pdf', '.zip', '.exe', '.dll', '.apk',
    '.bin', '.woff', '.woff2', '.ttf', '.eot', '.otf', '.mp3', '.mp4',
    '.webm', '.php'
  ];

  static bool isValidImageUrl(String url) {
    final lower = url.toLowerCase().trim();

    if (!lower.startsWith('http://') && !lower.startsWith('https://')) return false;
    if (lower.startsWith('data:')) return false;
    if (lower.length < 15) return false;

    for (final term in _blacklistTerms) {
      if (lower.contains(term)) return false;
    }

    for (final segment in _badPathSegments) {
      if (lower.contains(segment)) return false;
    }

    for (final ext in _badExtensions) {
      if (lower.endsWith(ext)) return false;
    }

    return true;
  }

  static void _recordUsage(String url) {
    if (_usedImages.length >= _maxCacheSize) {
      _usedImages.remove(_usedImages.first);
    }
    _usedImages.add(url);
  }

  /// Selects the best image from a list of candidates.
  static String selectBestImage(
    List<ImageCandidate> candidates, 
    String articleTitle, 
    List<String> extractedEntities
  ) {
    if (candidates.isEmpty) return '';

    // Filter out blacklisted URLs, small images, and duplicates
    final validCandidates = candidates.where((c) {
      final lowerUrl = c.url.toLowerCase();
      
      // Basic format check
      if (!lowerUrl.startsWith('http')) return false;
      if (lowerUrl.endsWith('.svg') || lowerUrl.endsWith('.gif')) return false;

      // Reject heavily used breaking news or default images
      if (_usedImages.contains(c.url)) return false;

      // Reject based on URL heuristics
      for (final term in _blacklistTerms) {
        if (lowerUrl.contains(term)) return false;
      }

      // Reject based on explicitly parsed tiny dimensions
      if (c.width > 0 && c.width < 300) return false;
      if (c.height > 0 && c.height < 200) return false;

      // Reject extreme aspect ratios
      if (c.width > 0 && c.height > 0) {
        final ratio = c.width / c.height;
        if (ratio > 3.0 || ratio < 0.33) return false;
      }

      return true;
    }).toList();

    if (validCandidates.isEmpty) return '';

    // Score candidates
    ImageCandidate? bestImage;
    double bestScore = -1.0;

    final normTitle = ArabicTextNormalizer.normalize(articleTitle);
    final titleWords = normTitle.split(RegExp(r'\s+')).toSet();

    // Normalize entities to easily match against image alt tags
    final normalizedEntities = extractedEntities
        .map((e) => ArabicTextNormalizer.normalize(e))
        .toList();

    for (final c in validCandidates) {
      double score = 0.0;

      // Base score depending on the source metadata (OG images are usually very good)
      if (c.source == 'og' || c.source == 'twitter') {
        score += 10.0;
      }

      // Semantic matching using alt text / figcaption
      if (c.altText.isNotEmpty) {
        final normAlt = ArabicTextNormalizer.normalize(c.altText);
        
        // Boost if alt text explicitly mentions a key entity
        for (final ent in normalizedEntities) {
          if (ent.length > 3 && normAlt.contains(ent)) {
            score += 25.0; // Massive boost for entity match
          }
        }

        // Basic TF-IDF overlap with the title
        final altWords = normAlt.split(RegExp(r'\s+')).toSet();
        final intersection = altWords.intersection(titleWords).length;
        score += intersection * 2.0;
      }

      // If dimensions exist, prefer larger, high-res images
      if (c.width >= 800) score += 5.0;

      if (score > bestScore) {
        bestScore = score;
        bestImage = c;
      }
    }

    final finalUrl = bestImage?.url ?? validCandidates.first.url;
    _recordUsage(finalUrl);
    return finalUrl;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // NewsBrain Core Image Engine:
  // 1. Check if social schema image exists -> it is the correct image!
  // 2. If no, check other images found with alt/title matching news title in context -> it is valid!
  // 3. Else search for the image of the main news in search engine (randomizing between famous engines).
  // ──────────────────────────────────────────────────────────────────────────

  /// Resolves relative image URLs against a base page URL.
  static String resolveImageUrl(String raw, String pageUrl) {
    var value = raw
        .trim()
        .replaceAll('&amp;', '&')
        .replaceAll('&#x2F;', '/')
        .replaceAll('&quot;', '"')
        .replaceAll(r'\/', '/');
    if (value.startsWith('url(') && value.endsWith(')')) {
      value = value.substring(4, value.length - 1).trim();
      if ((value.startsWith("'") && value.endsWith("'")) ||
          (value.startsWith('"') && value.endsWith('"'))) {
        value = value.substring(1, value.length - 1);
      }
    }
    if (value.startsWith('//')) value = 'https:$value';
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) return parsed.toString();
    final base = Uri.tryParse(pageUrl);
    if (base == null) return value;
    final resolved = base.resolve(value);
    return (resolved.hasScheme && resolved.host.isNotEmpty) ? resolved.toString() : value;
  }

  /// Extracts social schema images (OpenGraph, Twitter Cards, Schema.org / JSON-LD, Microdata).
  static String? extractSocialSchemaImage(String html, {String pageUrl = ''}) {
    if (html.isEmpty) return null;

    // 1. Open Graph: og:image, og:image:url, og:image:secure_url
    final ogPatterns = [
      RegExp(r"""<meta[^>]+(?:property|name)=["']og:image(?::url|:secure_url)?["'][^>]+content=["']([^"']+)["']""", caseSensitive: false),
      RegExp(r"""<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']og:image(?::url|:secure_url)?["']""", caseSensitive: false),
    ];
    for (final p in ogPatterns) {
      final m = p.firstMatch(html);
      if (m != null && m.group(1) != null) {
        final resolved = resolveImageUrl(m.group(1)!, pageUrl);
        if (isValidImageUrl(resolved) && !MsnImageFetcher.isPlaceholderOrEmpty(resolved)) {
          return resolved;
        }
      }
    }

    // 2. Twitter Cards: twitter:image, twitter:image:src
    final twitterPatterns = [
      RegExp(r"""<meta[^>]+(?:name|property)=["']twitter:image(?::src)?["'][^>]+content=["']([^"']+)["']""", caseSensitive: false),
      RegExp(r"""<meta[^>]+content=["']([^"']+)["'][^>]+(?:name|property)=["']twitter:image(?::src)?["']""", caseSensitive: false),
    ];
    for (final p in twitterPatterns) {
      final m = p.firstMatch(html);
      if (m != null && m.group(1) != null) {
        final resolved = resolveImageUrl(m.group(1)!, pageUrl);
        if (isValidImageUrl(resolved) && !MsnImageFetcher.isPlaceholderOrEmpty(resolved)) {
          return resolved;
        }
      }
    }

    // 3. JSON-LD / Schema.org: NewsArticle / Article schema image
    final jsonLdMatches = RegExp(
      '<script[^>]+type=[\"\']+application\/ld\\+json[\"\']+[^>]*>(.*?)<\/script>',
      dotAll: true,
      caseSensitive: false,
    ).allMatches(html);

    for (final jm in jsonLdMatches) {
      final jsonText = jm.group(1)?.trim();
      if (jsonText == null || jsonText.isEmpty) continue;
      try {
        final dynamic parsed = jsonDecode(jsonText);
        final found = _findImageInJsonLd(parsed);
        if (found != null && found.isNotEmpty) {
          final resolved = resolveImageUrl(found, pageUrl);
          if (isValidImageUrl(resolved) && !MsnImageFetcher.isPlaceholderOrEmpty(resolved)) {
            return resolved;
          }
        }
      } catch (_) {
        // Fallback regex for non-standard or malformed JSON-LD
        final imgMatch = RegExp(r'"image"\s*:\s*"(https?:[^"]+)"').firstMatch(jsonText) ??
            RegExp(r'"thumbnailUrl"\s*:\s*"(https?:[^"]+)"').firstMatch(jsonText) ??
            RegExp(r'"url"\s*:\s*"(https?:[^"]+\.(?:jpe?g|png|webp)[^"]*)"').firstMatch(jsonText);
        if (imgMatch != null && imgMatch.group(1) != null) {
          final resolved = resolveImageUrl(imgMatch.group(1)!, pageUrl);
          if (isValidImageUrl(resolved) && !MsnImageFetcher.isPlaceholderOrEmpty(resolved)) {
            return resolved;
          }
        }
      }
    }

    // 4. HTML Microdata & Link tags
    final microdataMatches = [
      RegExp(r"""<meta[^>]+itemprop=["']image["'][^>]+content=["']([^"']+)["']""", caseSensitive: false),
      RegExp(r"""<link[^>]+rel=["']image_src["'][^>]+href=["']([^"']+)["']""", caseSensitive: false),
      RegExp(r"""<meta[^>]+name=["']thumbnail["'][^>]+content=["']([^"']+)["']""", caseSensitive: false),
    ];
    for (final p in microdataMatches) {
      final m = p.firstMatch(html);
      if (m != null && m.group(1) != null) {
        final resolved = resolveImageUrl(m.group(1)!, pageUrl);
        if (isValidImageUrl(resolved) && !MsnImageFetcher.isPlaceholderOrEmpty(resolved)) {
          return resolved;
        }
      }
    }

    return null;
  }

  static String? _findImageInJsonLd(dynamic json) {
    if (json is Map<String, dynamic>) {
      if (json.containsKey('image')) {
        final img = json['image'];
        if (img is String && img.isNotEmpty) return img;
        if (img is List && img.isNotEmpty && img.first is String) return img.first as String;
        if (img is Map && img.containsKey('url') && img['url'] is String) return img['url'] as String;
      }
      if (json.containsKey('thumbnailUrl') && json['thumbnailUrl'] is String) {
        return json['thumbnailUrl'] as String;
      }
      if (json.containsKey('@graph') && json['@graph'] is List) {
        for (final item in json['@graph']) {
          final found = _findImageInJsonLd(item);
          if (found != null) return found;
        }
      }
    } else if (json is List) {
      for (final item in json) {
        final found = _findImageInJsonLd(item);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Checks if an image's `alt` or `title` matches the news title in context.
  static bool matchesTitleInContext(String altOrTitle, String newsTitle) {
    final cleanAlt = altOrTitle.trim();
    if (cleanAlt.isEmpty || cleanAlt.length < 3) return false;

    final cleanedNewsTitle = MsnImageFetcher.cleanNewsTitleForSearch(newsTitle);
    if (cleanedNewsTitle.isEmpty) return false;

    // Normalization
    final normAlt = ArabicTextNormalizer.normalize(cleanAlt).toLowerCase();
    final normTitle = ArabicTextNormalizer.normalize(cleanedNewsTitle).toLowerCase();

    // 1. Direct match or substring
    if (normAlt == normTitle) return true;
    if (normAlt.length >= 10 && normTitle.contains(normAlt)) return true;
    if (normTitle.length >= 10 && normAlt.contains(normTitle)) return true;

    // 2. Tokenized contextual overlap
    const stopWords = {
      'the', 'and', 'for', 'with', 'that', 'this', 'from', 'was', 'were',
      'are', 'have', 'has', 'had', 'not', 'but', 'into', 'about', 'after',
      'dans', 'avec', 'pour', 'que', 'qui', 'une', 'des', 'les', 'est', 'sont',
      'من', 'في', 'على', 'إلى', 'عن', 'مع', 'هذا', 'هذه', 'ذلك', 'أن', 'إن',
      'كان', 'كانت', 'التي', 'الذي', 'الذين', 'بين', 'بعد', 'قبل', 'خلال', 'كما',
      'news', 'photo', 'image', 'picture', 'update', 'latest',
    };

    final altWords = normAlt
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !stopWords.contains(w))
        .toSet();

    final titleWords = normTitle
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !stopWords.contains(w))
        .toSet();

    if (altWords.isEmpty || titleWords.isEmpty) return false;

    final intersection = altWords.intersection(titleWords).length;
    // If at least 2 significant words match, or >= 35% of title words match
    if (intersection >= 2) return true;
    if (intersection >= 1 && (intersection / titleWords.length) >= 0.35) return true;

    return false;
  }

  /// Extracts an article image whose `alt` or `title` matches the news title in context.
  static String? extractContextualArticleImage(
    String html, 
    String newsTitle, 
    {String pageUrl = ''}
  ) {
    if (html.isEmpty || newsTitle.isEmpty) return null;

    final imgTagPattern = RegExp(
      r'<img[^>]+>',
      caseSensitive: false,
    );

    for (final match in imgTagPattern.allMatches(html)) {
      final tag = match.group(0) ?? '';

      // Extract source
      final srcMatch = RegExp(r"""(?:src|data-src|data-original|data-lazy-src)=["']([^"']+)["']""", caseSensitive: false).firstMatch(tag);
      if (srcMatch == null || srcMatch.group(1) == null) continue;
      final src = srcMatch.group(1)!.trim();
      if (src.isEmpty || src.startsWith('data:')) continue;

      // Extract alt and title
      final altMatch = RegExp(r"""alt=["']([^"']*)["']""", caseSensitive: false).firstMatch(tag);
      final titleMatch = RegExp(r"""title=["']([^"']*)["']""", caseSensitive: false).firstMatch(tag);
      final alt = altMatch?.group(1)?.trim() ?? '';
      final titleText = titleMatch?.group(1)?.trim() ?? '';

      // Check context match with news title
      final hasMatchingAlt = alt.isNotEmpty && matchesTitleInContext(alt, newsTitle);
      final hasMatchingTitle = titleText.isNotEmpty && matchesTitleInContext(titleText, newsTitle);

      if (hasMatchingAlt || hasMatchingTitle) {
        final resolved = resolveImageUrl(src, pageUrl);
        if (isValidImageUrl(resolved) && !MsnImageFetcher.isPlaceholderOrEmpty(resolved)) {
          return resolved;
        }
      }
    }

    return null;
  }

  /// Master newsBrain image catching function implementing the exact instructions:
  /// 1. Check if social schemas image exists -> social image is the correct image!
  /// 2. If no, check other images found with alt/title matching the news title in context -> valid!
  /// 3. Else search for the image of main news in search engine, randomizing between famous search engines.
  static Future<String> catchNewsImage({
    required String html,
    required String title,
    String pageUrl = '',
  }) async {
    // 1. Social schema image of post (OpenGraph, Twitter, Schema.org / JSON-LD, microdata)
    final socialImage = extractSocialSchemaImage(html, pageUrl: pageUrl);
    if (socialImage != null && socialImage.isNotEmpty && isValidImageUrl(socialImage)) {
      return socialImage;
    }

    // 2. If no, check other images found with alt/title matching news title in context
    final contextualImage = extractContextualArticleImage(html, title, pageUrl: pageUrl);
    if (contextualImage != null && contextualImage.isNotEmpty && isValidImageUrl(contextualImage)) {
      return contextualImage;
    }

    // 3. Else search for the image of main news in the search engine (randomizing between famous engines)
    final cleanedTitle = MsnImageFetcher.cleanNewsTitleForSearch(title);
    if (cleanedTitle.isNotEmpty) {
      try {
        final searchImage = await MsnImageFetcher.fetchRandomImage(cleanedTitle)
            .timeout(const Duration(seconds: 8));
        if (searchImage != null &&
            searchImage.isNotEmpty &&
            isValidImageUrl(searchImage) &&
            !MsnImageFetcher.isPlaceholderOrEmpty(searchImage)) {
          return searchImage;
        }
      } catch (_) {}
    }

    return '';
  }
}
