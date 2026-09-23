/// msn_image_fetcher.dart
///
/// Fetches relevant images from Bing Image Search (MSN backend) for a given
/// news article title. Returns 1–5 image URLs scraped from the first page of
/// results — no API key needed, uses the public HTML endpoint.
///
/// One random image (positions 1–5) is injected into each paragraph slot.

library msn_image_fetcher;

import 'dart:math';
import 'package:http/http.dart' as http;

class MsnImageFetcher {
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Safari/537.36';

  /// Minimum width/height we consider a "real" image (not icon/logo).
  static const int _minImageSize = 200;

  /// Cache: query → list of image URLs (in-process memory, cleared on restart)
  static final _cache = <String, List<String>>{};

  /// Fetch up to [maxImages] Bing image URLs for [query].
  /// Returns an empty list on any network / parse error.
  static Future<List<String>> fetchImages(
    String query, {
    int maxImages = 5,
  }) async {
    final cacheKey = query.trim().toLowerCase();
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    try {
      final encoded = Uri.encodeQueryComponent(query);
      // Bing image search endpoint — safe-search moderate, news filter
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

      final urls = _extractImageUrls(response.body, maxImages);
      if (urls.isNotEmpty) _cache[cacheKey] = urls;
      return urls;
    } catch (_) {
      return [];
    }
  }

  /// Fetch up to 5 Bing images then pick ONE at random (position 1–5).
  /// Each call to this method may return a different image for the same query
  /// because the random index is re-rolled every time.
  static Future<String?> fetchRandomImage(String query) async {
    final pool = await fetchImages(query, maxImages: 5);
    if (pool.isEmpty) return null;
    // Pick a random index in [0, min(5, pool.length) - 1]
    final idx = Random().nextInt(pool.length.clamp(1, 5));
    return pool[idx];
  }

  /// Synchronous wrapper — returns cached results only. Use when inside an isolate.
  static List<String> getCached(String query) =>
      _cache[query.trim().toLowerCase()] ?? [];

  // ── Private helpers ────────────────────────────────────────────────────────

  static List<String> _extractImageUrls(String html, int max) {
    final urls = <String>[];

    // Bing stores image metadata in JSON blobs like:
    // {"murl":"https://...","turl":"https://th.bing.com/th?...","..."}
    // We extract murl (master/full image URL) values.
    final murlRe = RegExp(r'"murl"\s*:\s*"(https?://[^"]+)"');
    for (final m in murlRe.allMatches(html)) {
      final url = m.group(1);
      if (url == null) continue;
      if (_isValidImageUrl(url)) {
        urls.add(url);
        if (urls.length >= max) break;
      }
    }

    // Fallback: og:image / meta image tags (for news pages)
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

    // Fallback: <img src="..."> with width/height hints
    if (urls.isEmpty) {
      final imgRe = RegExp(
          r'<img[^>]+src="(https?://[^"]+)"[^>]*(?:width="(\d+)")?',
          caseSensitive: false);
      for (final m in imgRe.allMatches(html)) {
        final url = m.group(1) ?? '';
        final w = int.tryParse(m.group(2) ?? '') ?? 0;
        if (w == 0 || w >= _minImageSize) {
          if (_isValidImageUrl(url)) {
            urls.add(url);
            if (urls.length >= max) break;
          }
        }
      }
    }

    return urls;
  }

  static bool _isValidImageUrl(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    // Must be an image extension or a known image CDN
    final validExt = lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.contains('images') ||
        lower.contains('th.bing.com') ||
        lower.contains('img') ||
        lower.contains('photo') ||
        lower.contains('picture') ||
        lower.contains('media');
    if (!validExt) return false;
    // Exclude icons, logos, ads, tracking pixels
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
/// [paragraphs] : list of plain-text paragraph strings
/// [imageUrls]  : pool of image URLs to draw from (shuffled, 1 per N paras)
/// [injectEveryN]: inject an image after every Nth paragraph (default 3)
/// Returns a single HTML-ready string.
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
/// If there are fewer than 2 paragraphs, it is injected at the end.
/// [paragraphs] : list of plain-text paragraph strings
/// [imageUrl]   : a single MSN image URL (can be null)
/// Returns a single HTML-ready string.
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

    // Inject the single image after the 2nd paragraph (index 1)
    // or at the end if there's only 1 paragraph.
    if (imageUrl != null && (i == 1 || (i == paragraphs.length - 1 && i < 1))) {
      buf.write('<img src="$imageUrl" style="$imgStyle" loading="lazy" />\n');
      imageUrl = null; // Ensure it's only injected once
    }
  }

  return buf.toString();
}
