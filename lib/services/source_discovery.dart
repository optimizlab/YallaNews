import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;

import 'publication_date_extractor.dart';

/// A discovered article URL candidate with its publication date hint.
class DiscoveredUrl {
  final String url;
  final String discoveryMethod; // rss | sitemap | category | homepage | webview
  final PublicationDate? dateHint;
  final String? titleHint;
  final String? language;

  DiscoveredUrl({
    required this.url,
    required this.discoveryMethod,
    this.dateHint,
    this.titleHint,
    this.language,
  });
}

/// Discovers article URLs from a publisher using priority-ordered methods:
/// RSS/Atom → sitemap → chronological category page → homepage → WebView.
class SourceDiscovery {
  static const Duration _timeout = Duration(seconds: 10);

  /// Official RSS/Atom feed URLs per publisher (discovered from publisher sites).
  /// These are the canonical, permitted feeds.
  static const Map<String, List<String>> _knownFeeds = {
    'hespress.com': [
      'https://www.hespress.com/feed',
      'https://www.hespress.com/rss.xml',
    ],
    'almasryalyoum.com': [
      'https://www.almasryalyoum.com/rss.xml',
    ],
    'mosaiquefm.net': [
      'https://www.mosaiquefm.net/rss.xml',
    ],
    'lemonde.fr': [
      'https://www.lemonde.fr/rss/une.xml',
      'https://www.lemonde.fr/rss/une.xml?output=1',
    ],
    'reuters.com': [
      'https://www.reuters.com/rss/topNews',
      'https://www.reuters.com/rss/worldNews',
    ],
    'aljazeera.net': [
      'https://www.aljazeera.net/xml/rss/all.xml',
      'https://www.aljazeera.net/xml/rss/all.xml?output=1',
    ],
  };

  /// News sitemap URLs per publisher.
  static const Map<String, List<String>> _knownSitemaps = {
    'hespress.com': [
      'https://www.hespress.com/sitemap.xml',
      'https://www.hespress.com/news-sitemap.xml',
    ],
    'almasryalyoum.com': [
      'https://www.almasryalyoum.com/sitemap.xml',
    ],
    'mosaiquefm.net': [
      'https://www.mosaiquefm.net/sitemap.xml',
    ],
    'lemonde.fr': [
      'https://www.lemonde.fr/sitemap.xml',
    ],
    'reuters.com': [
      'https://www.reuters.com/sitemap.xml',
    ],
    'aljazeera.net': [
      'https://www.aljazeera.net/sitemap.xml',
    ],
  };

  /// Chronological latest-news / category pages per publisher (fallback before homepage).
  static const Map<String, List<String>> _knownChronological = {
    'hespress.com': [
      'https://www.hespress.com/dernieres-heures',
      'https://www.hespress.com/actualites',
    ],
    'almasryalyoum.com': [
      'https://www.almasryalyoum.com/latest',
    ],
    'mosaiquefm.net': [
      'https://www.mosaiquefm.net/actualites',
    ],
    'lemonde.fr': [
      'https://www.lemonde.fr/en-direct/',
    ],
    'reuters.com': [
      'https://www.reuters.com/world/',
      'https://www.reuters.com/business/',
    ],
    'aljazeera.net': [
      'https://www.aljazeera.net/latest',
    ],
  };

  String _host(String url) {
    try {
      final u = Uri.parse(url);
      var h = u.host.toLowerCase();
      if (h.startsWith('www.')) h = h.substring(4);
      return h;
    } catch (_) {
      return '';
    }
  }

  List<String> _feedsFor(String url) => _knownFeeds[_host(url)] ?? const [];
  List<String> _sitemapsFor(String url) => _knownSitemaps[_host(url)] ?? const [];
  List<String> _chronologicalFor(String url) => _knownChronological[_host(url)] ?? const [];

  Future<String> _fetchText(String u) async {
    final response = await http
        .get(Uri.parse(u),
            headers: {
              'User-Agent': 'Mozilla/5.0 (compatible; YallaNews/1.0)',
              'Accept': 'application/rss+xml, application/atom+xml, application/xml, text/xml, text/html',
            })
        .timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) return '';
    return response.body;
  }

  /// Extract article URLs from RSS/Atom XML using the date extractor for hints.
  List<DiscoveredUrl> _fromFeed(String xml, String sourceUrl) {
    final found = <DiscoveredUrl>[];
    final document = parse(xml);
    final base = Uri.parse(sourceUrl);
    for (final item in document.querySelectorAll('item, entry')) {
      final linkEl = item.querySelector('link') ?? item.querySelector('url');
      final link = (linkEl?.attributes['href'] ?? linkEl?.text ?? '').trim();
      if (link.isEmpty) continue;
      final uri = base.resolve(link);
      final title = item.querySelector('title')?.text.trim();
      final pubDate = item.querySelector('pubDate') ?? item.querySelector('published');
      final pubText = pubDate?.text.trim();
      PublicationDate? dateHint;
      if (pubText != null && pubText.isNotEmpty) {
        final parsed = DateTime.tryParse(pubText);
        if (parsed == null) {
          // RFC-2822
          final p2 = PublicationDateExtractor().extractFromFeedOrSitemap('<rss><channel><item><pubDate>$pubText</pubDate></item></channel></rss>');
          if (p2 != null) dateHint = p2;
        } else {
          dateHint = PublicationDate(raw: pubText, utc: parsed.toUtc(), confidence: 0.95, source: 'rss');
        }
      }
      found.add(DiscoveredUrl(
        url: uri.toString(),
        discoveryMethod: 'rss',
        dateHint: dateHint,
        titleHint: title,
      ));
    }
    return found;
  }

  /// Extract article URLs from a news sitemap XML.
  List<DiscoveredUrl> _fromSitemap(String xml, String sourceUrl) {
    final found = <DiscoveredUrl>[];
    final document = parse(xml);
    final base = Uri.parse(sourceUrl);
    for (final el in [
      ...document.querySelectorAll('url'),
      ...document.querySelectorAll('news\\:url'),
    ]) {
      final loc = el.querySelector('loc')?.text.trim();
      if (loc == null || loc.isEmpty) continue;
      final uri = base.resolve(loc);
      final pubDate = el.querySelector('news\\:publication_date') ??
          el.querySelector('publication_date') ??
          el.querySelector('lastmod');
      PublicationDate? dateHint;
      if (pubDate != null) {
        final parsed = DateTime.tryParse(pubDate.text.trim());
        if (parsed != null) {
          dateHint = PublicationDate(raw: pubDate.text.trim(), utc: parsed.toUtc(), confidence: 0.9, source: 'sitemap');
        }
      }
      found.add(DiscoveredUrl(url: uri.toString(), discoveryMethod: 'sitemap', dateHint: dateHint));
    }
    return found;
  }

  /// Extract article URLs from an HTML page (chronological/category/homepage).
  List<DiscoveredUrl> _fromHtml(String html, String sourceUrl) {
    final found = <DiscoveredUrl>[];
    final document = parse(html);
    final base = Uri.parse(sourceUrl);
    final seen = <String>{};
    for (final el in document.querySelectorAll('a[href]')) {
      final href = el.attributes['href'];
      if (href == null || href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) continue;
      final uri = base.resolve(href);
      final key = uri.toString();
      if (seen.contains(key)) continue;
      seen.add(key);
      final path = uri.path;
      // Heuristic: article URLs have date segments or slug-like last segments.
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) continue;
      final last = segments.last.toLowerCase();
      bool looksLikeArticle = false;
      if (last.length >= 5 && last.contains('-')) looksLikeArticle = true;
      if (RegExp(r'^\d{4}/\d{2}/\d{2}/').hasMatch(path)) looksLikeArticle = true;
      if (RegExp(r'/(20\d{2})/').hasMatch(path)) looksLikeArticle = true;
      if (!looksLikeArticle) continue;
      found.add(DiscoveredUrl(url: key, discoveryMethod: 'homepage'));
    }
    return found;
  }

  // ──────────────────────────────────────────────────────────────
  // Public discovery entry point
  // ──────────────────────────────────────────────────────────────

  /// Discover article URLs for a publisher using priority-ordered methods.
  /// Stops at the first method that yields results (respecting [maxUrls]).
  Future<List<DiscoveredUrl>> discover(String sourceUrl, {int maxUrls = 20}) async {
    final host = _host(sourceUrl);

    // 1. Official RSS/Atom feeds
    for (final feedUrl in _feedsFor(sourceUrl)) {
      try {
        final xml = await _fetchText(feedUrl);
        if (xml.isNotEmpty) {
          final found = _fromFeed(xml, sourceUrl);
          if (found.isNotEmpty) {
            return found.take(maxUrls).toList();
          }
        }
      } catch (_) {}
    }

    // 2. News sitemap
    for (final smUrl in _sitemapsFor(sourceUrl)) {
      try {
        final xml = await _fetchText(smUrl);
        if (xml.isNotEmpty) {
          final found = _fromSitemap(xml, sourceUrl);
          if (found.isNotEmpty) {
            return found.take(maxUrls).toList();
          }
        }
      } catch (_) {}
    }

    // 3. Chronological / category pages
    for (final pageUrl in _chronologicalFor(sourceUrl)) {
      try {
        final html = await _fetchText(pageUrl);
        if (html.isNotEmpty) {
          final found = _fromHtml(html, pageUrl);
          if (found.isNotEmpty) {
            return found.take(maxUrls).toList();
          }
        }
      } catch (_) {}
    }

    // 4. Homepage HTML
    try {
      final html = await _fetchText(sourceUrl);
      if (html.isNotEmpty) {
        final found = _fromHtml(html, sourceUrl);
        if (found.isNotEmpty) {
          return found.take(maxUrls).toList();
        }
      }
    } catch (_) {}

    // 5. WebView fallback is handled by the caller (requires BuildContext).
    return <DiscoveredUrl>[];
  }
}
