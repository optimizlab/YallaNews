import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
/// Normalized publication-date result.
class PublicationDate {
  /// Original publisher string (for provenance / debugging).
  final String raw;
  /// Parsed UTC date, or null when unknown / unparseable.
  final DateTime? utc;
  /// Confidence 0.0-1.0 in this date being the true publication date.
  final double confidence;
  /// Source of the date: rss | atom | sitemap | json-ld | opengraph | html-time | meta | visible | unknown
  final String source;

  const PublicationDate({
    required this.raw,
    this.utc,
    this.confidence = 0.0,
    this.source = 'unknown',
  });

  bool get isKnown => utc != null;

  /// ISO-8601 UTC string suitable for storage; empty when unknown.
  String get isoUtc => utc?.toUtc().toIso8601String() ?? '';

  /// epoch milliseconds suitable for storage; 0 when unknown.
  int get epochMs => utc?.millisecondsSinceEpoch ?? 0;
}

/// Extracts publication dates from RSS/Atom feeds, news sitemaps, JSON-LD,
/// Open Graph, HTML <time> elements and publisher meta tags.
///
/// Never fabricates a date: when nothing is found, [utc] is null.
class PublicationDateExtractor {
  PublicationDateExtractor();

  // ──────────────────────────────────────────────────────────────
  // RSS 2.0  <pubDate>
  // ──────────────────────────────────────────────────────────────
  PublicationDate? _fromRss(String html, Uri base) {
    final document = parse(html);
    for (final item in document.querySelectorAll('item, entry')) {
      // Only the first (newest) item matters for discovery-page dating.
      final pubDateEl = item.querySelector('pubDate');
      if (pubDateEl != null && pubDateEl.text.isNotEmpty) {
        final parsed = _tryParseRfc2822(pubDateEl.text.trim());
        if (parsed != null) {
          return PublicationDate(
            raw: pubDateEl.text.trim(),
            utc: parsed.toUtc(),
            confidence: 0.95,
            source: 'rss',
          );
        }
      }
      // Atom <published>
      final publishedEl = item.querySelector('published');
      if (publishedEl != null && publishedEl.text.isNotEmpty) {
        final parsed = DateTime.tryParse(publishedEl.text.trim());
        if (parsed != null) {
          return PublicationDate(
            raw: publishedEl.text.trim(),
            utc: parsed.toUtc(),
            confidence: 0.95,
            source: 'atom',
          );
        }
      }
    }
    return null;
  }

  // ──────────────────────────────────────────────────────────────
  // News sitemap  <news:publication_date>
  // ──────────────────────────────────────────────────────────────
  PublicationDate? _fromSitemap(String html) {
    final document = parse(html);
    // Try namespaced news:publication_date first, then plain publication_date.
    for (final el in [
      ...document.querySelectorAll('news\\:publication_date'),
      ...document.querySelectorAll('publication_date'),
    ]) {
      final text = el.text.trim();
      if (text.isEmpty) continue;
      final parsed = DateTime.tryParse(text);
      if (parsed != null) {
        return PublicationDate(
          raw: text,
          utc: parsed.toUtc(),
          confidence: 0.95,
          source: 'sitemap',
        );
      }
    }
    // Also scan <lastmod> as a weaker signal.
    for (final el in document.querySelectorAll('lastmod')) {
      final text = el.text.trim();
      if (text.isEmpty) continue;
      final parsed = DateTime.tryParse(text);
      if (parsed != null) {
        return PublicationDate(
          raw: text,
          utc: parsed.toUtc(),
          confidence: 0.70,
          source: 'sitemap-lastmod',
        );
      }
    }
    return null;
  }

  // ──────────────────────────────────────────────────────────────
  // JSON-LD  datePublished / dateModified
  // ──────────────────────────────────────────────────────────────
  PublicationDate? _fromJsonLd(String html) {
    final document = parse(html);
    for (final script in document.querySelectorAll('script[type="application/ld+json"]')) {
      final text = script.text.trim();
      if (text.isEmpty) continue;
      try {
        final decoded = jsonDecode(text);
        final date = _extractJsonLdDate(decoded);
        if (date != null) return date;
      } catch (_) {}
      // Some pages embed an array of JSON-LD objects.
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          for (final item in decoded) {
            final date = _extractJsonLdDate(item);
            if (date != null) return date;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  PublicationDate? _extractJsonLdDate(dynamic item) {
    if (item is! Map<String, dynamic>) return null;

    // Prefer datePublished over dateModified.
    final candidates = <String>[];
    final dp = item['datePublished'] ?? item['date_published'];
    if (dp is String && dp.isNotEmpty) candidates.add(dp);
    final dm = item['dateModified'] ?? item['date_modified'];
    if (dm is String && dm.isNotEmpty) candidates.add(dm);

    // Some publishers nest dates under @graph or mainEntity.
    if (candidates.isEmpty) {
      for (final key in ['mainEntity', 'publisher', 'author']) {
        final v = item[key];
        if (v is Map) {
          final d = v['datePublished'] ?? v['dateModified'];
          if (d is String && d.isNotEmpty) candidates.add(d);
        }
      }
    }

    for (final raw in candidates) {
      final parsed = DateTime.tryParse(raw.trim());
      if (parsed != null) {
        final source = candidates.first == raw ? 'json-ld' : 'json-ld-nested';
        final isModified = raw.contains('Modified') ||
            item['dateModified'] == raw ||
            item['date_modified'] == raw;
        return PublicationDate(
          raw: raw.trim(),
          utc: parsed.toUtc(),
          confidence: isModified ? 0.60 : 0.90,
          source: source,
        );
      }
    }
    return null;
  }

  // ──────────────────────────────────────────────────────────────
  // Open Graph article:published_time / article:modified_time
  // ──────────────────────────────────────────────────────────────
  PublicationDate? _fromOpenGraph(String html) {
    final document = parse(html);
    // Open Graph uses property=, not name=.
    final el = document.querySelector('meta[property="article:published_time"]');
    if (el != null) {
      final published = el.attributes['content']?.trim();
      if (published != null && published.isNotEmpty) {
        final parsed = DateTime.tryParse(published.trim());
        if (parsed != null) {
          return PublicationDate(
            raw: published.trim(),
            utc: parsed.toUtc(),
            confidence: 0.85,
            source: 'opengraph',
          );
        }
      }
    }
    // Weaker signal: og:updated_time / article:modified_time
    final modifiedEl = document.querySelector('meta[property="article:modified_time"]')
        ?? document.querySelector('meta[property="og:updated_time"]');
    if (modifiedEl != null) {
      final modified = modifiedEl.attributes['content']?.trim();
      if (modified != null && modified.isNotEmpty) {
        final parsed = DateTime.tryParse(modified.trim());
        if (parsed != null) {
          return PublicationDate(
            raw: modified.trim(),
            utc: parsed.toUtc(),
            confidence: 0.55,
            source: 'opengraph-modified',
          );
        }
      }
    }
    return null;
  }

  String _firstMeta(String html, String property) {
    final document = parse(html);
    // Iterate meta tags directly to avoid CSS-selector colon-escaping issues
    // with names like "article:published_time".
    for (final el in document.querySelectorAll('meta')) {
      final name = el.attributes['name'] ?? '';
      final prop = el.attributes['property'] ?? '';
      final itemprop = el.attributes['itemprop'] ?? '';
      if (name == property || prop == property || itemprop == property) {
        final content = el.attributes['content']?.trim();
        if (content != null && content.isNotEmpty) return content;
      }
    }
    return '';
  }

  // ──────────────────────────────────────────────────────────────
  // HTML <time datetime=...>  and <time> visible text
  // ──────────────────────────────────────────────────────────────
  PublicationDate? _fromHtmlTime(String html) {
    final document = parse(html);
    for (final el in document.querySelectorAll('time')) {
      final datetime = el.attributes['datetime']?.trim();
      if (datetime != null && datetime.isNotEmpty) {
        final parsed = DateTime.tryParse(datetime);
        if (parsed != null) {
          return PublicationDate(
            raw: datetime,
            utc: parsed.toUtc(),
            confidence: 0.80,
            source: 'html-time',
          );
        }
      }
      // Fallback to visible text of <time>.
      final visible = el.text.trim();
      if (visible.isNotEmpty) {
        final parsed = _tryParseVisible(visible);
        if (parsed != null) {
          return PublicationDate(
            raw: visible,
            utc: parsed.toUtc(),
            confidence: 0.60,
            source: 'html-time-visible',
          );
        }
      }
    }
    return null;
  }

  // ──────────────────────────────────────────────────────────────
  // Meta tags: article:published_time, date, dc.date, etc.
  // ──────────────────────────────────────────────────────────────
  PublicationDate? _fromMeta(String html) {
    final document = parse(html);
    final metaNames = [
      'article:published_time',
      'date',
      'dc.date',
      'dc.date.issued',
      'dcterms.created',
      'original_publication_date',
      'publish_date',
      'article_created',
      'article:created_time',
    ];
    for (final name in metaNames) {
      final el = document.querySelector('meta[name="$name"], meta[property="$name"]');
      if (el != null) {
        final content = el.attributes['content']?.trim();
        if (content != null && content.isNotEmpty) {
          final parsed = DateTime.tryParse(content);
          if (parsed != null) {
            return PublicationDate(
              raw: content,
              utc: parsed.toUtc(),
              confidence: 0.75,
              source: 'meta-$name',
            );
          }
        }
      }
    }
    return null;
  }

  // ──────────────────────────────────────────────────────────────
  // Public entry points
  // ──────────────────────────────────────────────────────────────

  /// Extract the best-known publication date from an article page HTML.
  /// Returns null when no date can be determined (never fabricates).
  PublicationDate extractFromArticleHtml(String html, {Uri? baseUri}) {
    // Highest-confidence sources first.
    final candidates = <PublicationDate?>[
      _fromJsonLd(html),           // datePublished / dateModified
      _fromOpenGraph(html),        // article:published_time
      _fromHtmlTime(html),         // <time datetime>
      _fromSitemap(html),          // news sitemap (rare on article page)
      _fromMeta(html),             // meta tags
    ];
    // Return the highest-confidence non-null candidate.
    final best = candidates.whereType<PublicationDate>().fold<PublicationDate?>(
      null,
      (a, b) => a == null || b.confidence > a.confidence ? b : a,
    );
    if (best != null) return best;
    // Unknown date — return a sentinel so callers know we tried.
    return const PublicationDate(raw: '', utc: null, confidence: 0.0, source: 'unknown');
  }

  /// Extract publication dates from a feed / sitemap page. Returns the
  /// newest date found (first item), or null.
  PublicationDate? extractFromFeedOrSitemap(String html, {Uri? baseUri}) {
    final rss = _fromRss(html, baseUri ?? Uri.base);
    if (rss != null) return rss;
    final sitemap = _fromSitemap(html);
    if (sitemap != null) return sitemap;
    return null;
  }

  // ──────────────────────────────────────────────────────────────
  // Parsing helpers
  // ──────────────────────────────────────────────────────────────

  DateTime? _tryParseRfc2822(String raw) {
    // Dart's DateTime.tryParse handles ISO-8601 but not full RFC-2822.
    // Try ISO first.
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed;

    // RFC-2822: "Mon, 21 Nov 2023 10:00:00 GMT" or "21 Nov 2023 10:00:00 +0100".
    final rfcMatch = RegExp(
      r'^(?:[A-Za-z]{3},\s*)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([A-Za-z0-9:+-]+)?',
    ).firstMatch(raw);
    if (rfcMatch == null) return null;

    final day = int.tryParse(rfcMatch.group(1)!) ?? 1;
    final month = _monthNameToInt(rfcMatch.group(2)!);
    if (month == null) return null;
    final year = int.tryParse(rfcMatch.group(3)!) ?? 1970;
    final hour = int.tryParse(rfcMatch.group(4)!) ?? 0;
    final minute = int.tryParse(rfcMatch.group(5)!) ?? 0;
    final second = int.tryParse(rfcMatch.group(6)!) ?? 0;

    // Handle timezone offset.
    final tz = rfcMatch.group(7);
    int offsetMinutes = 0;
    if (tz != null) {
      offsetMinutes = _parseRfcTimezone(tz);
    }

    final local = DateTime(year, month, day, hour, minute, second);
    return local.subtract(Duration(minutes: offsetMinutes));
  }

  static int? _monthNameToInt(String m) {
    switch (m.toLowerCase()) {
      case 'jan': return 1;
      case 'feb': return 2;
      case 'mar': return 3;
      case 'apr': return 4;
      case 'may': return 5;
      case 'jun': return 6;
      case 'jul': return 7;
      case 'aug': return 8;
      case 'sep': return 9;
      case 'oct': return 10;
      case 'nov': return 11;
      case 'dec': return 12;
      default: return null;
    }
  }

  static int _parseRfcTimezone(String tz) {
    tz = tz.toUpperCase();
    switch (tz) {
      case 'GMT': return 0;
      case 'UTC': return 0;
      case 'EST': return -300;
      case 'EDT': return -240;
      case 'CST': return -360;
      case 'CDT': return -300;
      case 'MST': return -420;
      case 'MDT': return -360;
      case 'PST': return -480;
      case 'PDT': return -420;
    }
    // Numeric offset like +0100 or -0500.
    final numMatch = RegExp(r'^([+-])(\d{2})(\d{2})$').firstMatch(tz);
    if (numMatch != null) {
      final sign = numMatch.group(1) == '+' ? 1 : -1;
      final hours = int.tryParse(numMatch.group(2)!) ?? 0;
      final mins = int.tryParse(numMatch.group(3)!) ?? 0;
      return sign * (hours * 60 + mins);
    }
    return 0;
  }

  DateTime? _tryParseVisible(String raw) {
    // Very best-effort for visible timestamps like "21 Nov 2023" or "3 hours ago".
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed != null) return parsed;
    // "X hours/minutes ago" -> relative to now (low confidence).
    final agoMatch = RegExp(r'(\d+)\s*(minute|hour|day|week|month|year)s?\s*ago', caseSensitive: false).firstMatch(raw);
    if (agoMatch != null) {
      final amount = int.tryParse(agoMatch.group(1)!) ?? 0;
      final unit = agoMatch.group(2)!.toLowerCase();
      DateTime now = DateTime.now();
      switch (unit) {
        case 'minute': now = now.subtract(Duration(minutes: amount));
        case 'hour': now = now.subtract(Duration(hours: amount));
        case 'day': now = now.subtract(Duration(days: amount));
        case 'week': now = now.subtract(Duration(days: amount * 7));
        case 'month': now = DateTime(now.year, now.month - amount, now.day);
        case 'year': now = DateTime(now.year - amount, now.month, now.day);
      }
      return now;
    }
    return null;
  }
}

/// Convenience: fetch a URL and extract its publication date.
Future<PublicationDate> extractDateFromUrl(String url,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final extractor = PublicationDateExtractor();
  final response = await http
      .get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'})
      .timeout(timeout);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    return const PublicationDate(raw: '', utc: null, confidence: 0.0, source: 'unknown');
  }
  return extractor.extractFromArticleHtml(response.body, baseUri: Uri.parse(url));
}
