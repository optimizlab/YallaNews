import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
  /// Official RSS/Atom feed URLs per publisher (discovered from publisher sites).
  /// These are the canonical, permitted feeds.
  static const Map<String, List<String>> _knownFeeds = {
    'hespress.com': [
      'https://www.hespress.com/feed',
      'https://www.hespress.com/rss.xml',
      'https://www.hespress.com/feed/',
      'https://hespress.com/feed',
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
    'aawsat.com': [
      'https://www.aawsat.com/rss',
    ],
    'alaraby.co.uk': [
      'https://www.alaraby.co.uk/rss',
    ],
  };

  /// News sitemap URLs per publisher.
  static const Map<String, List<String>> _knownSitemaps = {
    'hespress.com': [
      'https://www.hespress.com/sitemap.xml',
      'https://www.hespress.com/news-sitemap.xml',
      'https://www.hespress.com/sitemap_index.xml',
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
    'aawsat.com': [
      'https://www.aawsat.com/sitemap.xml',
    ],
    'alaraby.co.uk': [
      'https://www.alaraby.co.uk/sitemap.xml',
    ],
  };

  /// Chronological latest-news / category pages per publisher (fallback before homepage).
  static const Map<String, List<String>> _knownChronological = {
    'hespress.com': [
      'https://www.hespress.com/dernieres-heures',
      'https://www.hespress.com/actualites',
      'https://www.hespress.com/societe',
      'https://www.hespress.com/politique',
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
    'aawsat.com': [
      'https://www.aawsat.com/latest',
    ],
    'alaraby.co.uk': [
      'https://www.alaraby.co.uk/latest',
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
    HttpClient? client;
    try {
      final uri = Uri.parse(u);
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6)
        ..idleTimeout = const Duration(seconds: 6);
      final request = await client.openUrl('GET', uri);
      request.headers.add(
        'User-Agent',
        'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      );
      request.headers.add('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
      final response = await request.close().timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 300) return '';
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return '';
    } finally {
      client?.close();
    }
  }

  /// Extract article URLs from RSS/Atom XML using the date extractor for hints.
  List<DiscoveredUrl> _fromFeed(String xml, String sourceUrl) {
    final found = <DiscoveredUrl>[];
    final base = Uri.parse(sourceUrl);

    // Note: package:html parses HTML5 where <link> is a void element, so
    // <link>https://...</link> in RSS 2.0 loses its text content!
    // Extract <item>...</item> via regex first for RSS 2.0, then fall back to DOM for Atom.
    final itemMatches = RegExp(
      r'<item\b[^>]*>(.*?)</item>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(xml);

    for (final m in itemMatches) {
      final block = m.group(1) ?? '';
      final linkMatch = RegExp(
        r'<link[^>]*>(?:\s*<!\[CDATA\[)?\s*([^<\s]+)\s*(?:\]\]>\s*)?</link>',
        caseSensitive: false,
      ).firstMatch(block);
      final link = linkMatch?.group(1)?.trim() ?? '';
      if (link.isEmpty || !link.startsWith('http')) continue;
      final uri = base.resolve(link);
      final titleMatch = RegExp(
        r'<title[^>]*>(?:\s*<!\[CDATA\[)?(.*?)(?:\]\]>)?\s*</title>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(block);
      final title = titleMatch?.group(1)?.trim();
      final pubMatch = RegExp(
        r'<pubDate[^>]*>(.*?)</pubDate>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(block);
      final pubText = pubMatch?.group(1)?.trim();
      PublicationDate? dateHint;
      if (pubText != null && pubText.isNotEmpty) {
        final parsed = DateTime.tryParse(pubText);
        if (parsed == null) {
          final p2 = PublicationDateExtractor().extractFromFeedOrSitemap(
            '<rss><channel><item><pubDate>$pubText</pubDate></item></channel></rss>',
          );
          if (p2 != null) dateHint = p2;
        } else {
          dateHint = PublicationDate(
            raw: pubText,
            utc: parsed.toUtc(),
            confidence: 0.95,
            source: 'rss',
          );
        }
      }
      found.add(DiscoveredUrl(
        url: uri.toString(),
        discoveryMethod: 'rss',
        dateHint: dateHint,
        titleHint: title,
      ));
    }

    if (found.isNotEmpty) return found;

    final document = parse(xml);
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
    final baseHost = _host(sourceUrl);
    final seen = <String>{};
    for (final el in document.querySelectorAll('a[href]')) {
      final href = el.attributes['href'];
      if (href == null ||
          href.isEmpty ||
          href.startsWith('#') ||
          href.startsWith('javascript:') ||
          href.startsWith('mailto:') ||
          href.startsWith('tel:')) continue;
      final uri = base.resolve(href);
      final host = _host(uri.toString());
      // Same-domain only.
      if (host.isNotEmpty && host != baseHost) continue;
      final key = uri.toString();
      if (seen.contains(key)) continue;
      seen.add(key);
      final path = uri.path;
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) continue;
      final last = segments.last.toLowerCase();
      // Skip single-segment category/section pages (e.g. /faits-divers, /sport)
      // unless they look like an actual article (.html, contains digits, or long slug).
      if (segments.length == 1 &&
          !last.endsWith('.html') &&
          !last.endsWith('.htm') &&
          !RegExp(r'\d').hasMatch(last) &&
          last.length < 25) {
        continue;
      }
      // Skip static assets and common non-article paths.
      if (RegExp(r'\.(css|js|png|jpg|jpeg|gif|svg|ico|woff|woff2|ttf|eot|pdf|zip|xml|rss|atom)(\?|$)')
          .hasMatch(last)) continue;
      if (path.contains('/wp-') ||
          path.contains('/tag/') ||
          path.contains('/category/') ||
          path.contains('/section/') ||
          path.contains('/author/') ||
          path.contains('/page/') ||
          path.contains('/search') ||
          path.contains('/login') ||
          path.contains('/register') ||
          path.contains('/contact') ||
          path.contains('/about') ||
          path.contains('/privacy') ||
          path.contains('/terms') ||
          path.contains('/sitemap') ||
          path.contains('/feed') ||
          path.contains('/rss')) continue;
      bool looksLikeArticle = false;
      // Date-based paths: /2024/01/15/slug or /2024/01/
      if (RegExp(r'^\d{4}/\d{2}/\d{2}/').hasMatch(path)) looksLikeArticle = true;
      if (RegExp(r'/(20\d{2})/').hasMatch(path)) looksLikeArticle = true;
      // Slug with hyphen: /societe/article-title
      if (last.length >= 5 && last.contains('-')) looksLikeArticle = true;
      // Numeric ID: /12345 or /12345.html
      if (RegExp(r'^\d+$').hasMatch(last.replaceAll('.html', ''))) looksLikeArticle = true;
      // .html extension with reasonable length
      if (last.endsWith('.html') && last.length > 6) looksLikeArticle = true;
      // ASP.NET / PHP style: /article.aspx?id= or /news.php?id=
      if (RegExp(r'\.(aspx|php|asp)(\?|$)').hasMatch(last)) looksLikeArticle = true;
      if (!looksLikeArticle) continue;
      found.add(DiscoveredUrl(url: key, discoveryMethod: 'homepage'));
    }
    debugPrint('[DISCOVERY HTML] $sourceUrl: totalLinks=${seen.length} accepted=${found.length}');
    return found;
  }

  // ──────────────────────────────────────────────────────────────
  // Public discovery entry point
  // ──────────────────────────────────────────────────────────────

  /// Discover article URLs for a publisher using priority-ordered methods.
  /// Stops at the first method that yields results (respecting [maxUrls]).
  /// [deadline] caps total discovery time so a slow/unresponsive site
  /// cannot block the crawler indefinitely.
  Future<List<DiscoveredUrl>> discover(
    String sourceUrl, {
    int maxUrls = 20,
    DateTime? deadline,
  }) async {
    final host = _host(sourceUrl);
    final stop = () => deadline != null && DateTime.now().isAfter(deadline!);

    // 1. Official RSS/Atom feeds (try primary feed first so we don't burn the deadline)
    final feeds = _feedsFor(sourceUrl);
    if (feeds.isNotEmpty && !stop()) {
      try {
        final xml = await _fetchText(feeds.first);
        if (xml.isNotEmpty) {
          final found = _fromFeed(xml, sourceUrl);
          if (found.isNotEmpty) {
            return found.take(maxUrls).toList();
          }
        }
      } catch (_) {}
    }

    // 2. Homepage HTML (fast & reliable when RSS is unavailable or blocked)
    if (!stop()) {
      try {
        final html = await _fetchText(sourceUrl);
        if (html.isNotEmpty) {
          final found = _fromHtml(html, sourceUrl);
          if (found.isNotEmpty) {
            return found.take(maxUrls).toList();
          }
        }
      } catch (_) {}
    }

    // 2. News sitemap
    for (final smUrl in _sitemapsFor(sourceUrl)) {
      if (stop()) break;
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
      if (stop()) break;
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

    // 4. WebView fallback is handled by the caller (requires BuildContext).
    return <DiscoveredUrl>[];
  }
}
