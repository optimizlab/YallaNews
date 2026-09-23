import 'package:html/dom.dart' as dom;
import 'arabic_normalizer.dart';

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
    'watermark', 'badge', 'microsite', 'ad-banner', 'ad_banner'
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
    final lower = url.toLowerCase();

    if (!lower.startsWith('http')) return false;
    if (lower.startsWith('data:')) return false;
    if (url.length < 15) return false;

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

      // Reject extreme aspect ratios (e.g. 1000x10 is a banner, 10x1000 is a sidebar)
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
        
        // Boost if alt text explicitly mentions a key entity (like a sports team or politician)
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
}
