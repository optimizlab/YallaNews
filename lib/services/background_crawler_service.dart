import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;

import '../database/news_db.dart';
import '../models/news_model.dart';
import '../models/news_source.dart';
import 'memory_optimizer.dart';
import 'yalla_engine_service.dart';
import 'news_uri_parser.dart';
import 'news_intelligence.dart';
import 'app_settings.dart';
import 'server_api_service.dart';
import 'category_service.dart';
import 'connectivity_service.dart';
import 'content_ngram_scorer.dart';
import 'msn_image_fetcher.dart';
import 'device_benchmark.dart';
import 'news_brain_ffi.dart';
import 'engine_ffi.dart';
import 'tiny_llm_service.dart';

String _normalizeCrawlerLanguage(String language) {
  final normalized = language.trim().toLowerCase().replaceAll('_', '-');
  if (normalized.startsWith('ar') || normalized == 'arabic') return 'ar';
  if (normalized.startsWith('fr') || normalized == 'french') return 'fr';
  if (normalized.startsWith('tr') || normalized == 'turkish') return 'tr';
  if (normalized.startsWith('en') || normalized == 'english') return 'en';
  return '';
}

String _resolveCrawlerLanguage(
  String sourceLanguage,
  String preferredLanguage,
) {
  final preferred = _normalizeCrawlerLanguage(preferredLanguage);
  final sourceLanguages = sourceLanguage
      .split(RegExp(r'[,;|]'))
      .map(_normalizeCrawlerLanguage)
      .where((language) => language.isNotEmpty)
      .toList();
  if (preferred.isNotEmpty && sourceLanguages.contains(preferred)) {
    return preferred;
  }
  if (sourceLanguages.isNotEmpty) return sourceLanguages.first;
  return preferred.isNotEmpty ? preferred : 'en';
}

// ─── Isolate Entry Points ──────────────────────────────────────────────────────

void _crawlerIsolateEntry(Map<String, dynamic> init) async {
  final SendPort sendPort = init['sendPort'] as SendPort;
  final ReceivePort receivePort = ReceivePort();
  sendPort.send({'type': 'ready', 'port': receivePort.sendPort});

  await for (final message in receivePort) {
    final Map<String, dynamic> task = message as Map<String, dynamic>;
    final String action = task['action'] as String;
    final int? requestId = task['requestId'] != null
        ? task['requestId'] as int
        : null;

    if (action == 'crawl') {
      try {
        final result = await _crawlSourceInIsolate(task);
        if (requestId != null) {
          sendPort.send({
            'type': 'result',
            'requestId': requestId,
            'result': result,
          });
        }
      } catch (e) {
        debugPrint('[CRAWLER ISOLATE] Request failed: $e');
        if (requestId != null) {
          sendPort.send({
            'type': 'error',
            'requestId': requestId,
            'error': e.toString(),
          });
        }
      }
    } else if (action == 'stop') {
      break;
    }
  }
}

Future<Map<String, dynamic>> _crawlSourceInIsolate(
  Map<String, dynamic> task,
) async {
  final String sourceUrl = task['sourceUrl'] as String;
  final int maxUrls = task['maxUrls'] as int;
  final String sourceLanguage = _resolveCrawlerLanguage(
    task['sourceLanguage'] as String? ?? '',
    task['sourceLanguage'] as String? ?? 'en',
  );

  try {
    final response = await http
        .get(Uri.parse(sourceUrl), headers: {'User-Agent': 'Mozilla/5.0'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      debugPrint(
        '[CRAWLER ISOLATE] HTTP ${response.statusCode} source=$sourceUrl',
      );
      // Some publishers block their homepage while leaving their RSS feed
      // public. Try the feed before giving up on the source.
      final feedArticles = await _discoverRssArticles(sourceUrl, maxUrls);
      if (feedArticles.isNotEmpty) {
        return {'success': true, 'is_source': true, 'articles': feedArticles};
      }
      return {
        'success': false,
        'url': sourceUrl,
        'reason': 'HTTP ${response.statusCode}',
      };
    }

    final html = response.body;
    final isSource = !NewsUriParser.isValidArticleUrl(sourceUrl);

    if (isSource) {
      final document = parse(html);
      final baseUri = Uri.parse(sourceUrl);
      final Set<String> articleUrls = {};
      final List<Map<String, dynamic>> candidates = [];

      for (final element in document.querySelectorAll('a[href]')) {
        final href = element.attributes['href'];
        if (href == null ||
            href.isEmpty ||
            href.startsWith('#') ||
            href.startsWith('javascript:'))
          continue;
        Uri linkUri;
        try {
          linkUri = Uri.parse(href);
        } catch (_) {
          continue;
        }
        if (linkUri.host.isEmpty && !href.startsWith('/')) continue;
        // Resolve relative publisher links against the source page. The
        // previous condition only resolved links with an empty path, causing
        // normal links such as `/news/story-slug` to be discarded because
        // their host was still empty.
        final absolute = linkUri.host.isEmpty ? baseUri.resolve(href) : linkUri;
        if (absolute.host != baseUri.host) continue;
        final path = absolute.path;
        if (path.length < 10 ||
            path.contains('/wp-') ||
            path.contains('/tag/') ||
            path.contains('/category/'))
          continue;

        final lowerPath = path.toLowerCase();
        // `/news/` and `/articles/` are commonly valid article paths. Only
        // reject known listing/section paths here.
        if (lowerPath.contains('/section/')) continue;

        final segments = absolute.pathSegments
            .where((s) => s.isNotEmpty)
            .toList();
        // Many publishers use short two-segment article URLs such as
        // `/story-slug` or `/news/story-slug`.
        if (segments.length < 1) continue;
        final lastSegment = segments.last.toLowerCase();
        if (lastSegment.length < 5 && !RegExp(r'^\d+$').hasMatch(lastSegment))
          continue;

        final normalized = absolute.toString();
        if (!NewsUriParser.isValidArticleUrl(normalized)) continue;
        if (!articleUrls.add(normalized)) {
          continue;
        }

        int score = 0;
        final depth = path.split('/').where((s) => s.isNotEmpty).length;
        score += max(0, 10 - depth * 2);

        final linkText = element.text.trim().toLowerCase();
        if (linkText.length > 20 && linkText.length < 200) score += 5;
        if (linkText.contains('news') ||
            linkText.contains('article') ||
            linkText.contains('report'))
          score += 3;

        if (path.contains('/202') && path.contains('/')) score += 5;
        if (path.contains('-') && !path.contains('?')) score += 2;

        final pathWords = path.split('/').last.split('-').length;
        score += min(pathWords, 5);

        candidates.add({'url': normalized, 'score': score});
      }

      candidates.sort(
        (a, b) => (b['score'] as int).compareTo(a['score'] as int),
      );
      var limited = candidates
          .take(maxUrls)
          .map((c) => c['url'] as String)
          .toList();
      // Prefer RSS when the homepage is JS-rendered, has no article links, or
      // only contains navigation links. This is also useful for publishers
      // that intentionally omit stories from their public landing page.
      if (limited.isEmpty) {
        limited = await _discoverRssArticles(sourceUrl, maxUrls);
      }
      debugPrint(
        '[CRAWLER ISOLATE] source=$sourceUrl links=${candidates.length} selected=${limited.length}',
      );
      return {'success': true, 'is_source': true, 'articles': limited};
    }

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

    final ogDescMatch = RegExp(
      """<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']*)["'][^>]*>""",
      caseSensitive: false,
    ).firstMatch(html);
    final ogDescription = ogDescMatch != null ? ogDescMatch.group(1)! : '';
    final effectiveSummary = summary.length > ogDescription.length
        ? summary
        : ogDescription;

    final ogTitleMatch = RegExp(
      """<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']*)["'][^>]*>""",
      caseSensitive: false,
    ).firstMatch(html);
    final twitterTitleMatch = RegExp(
      """<meta[^>]+name=["']twitter:title["'][^>]+content=["']([^"']*)["'][^>]*>""",
      caseSensitive: false,
    ).firstMatch(html);
    final metaTitle = ogTitleMatch != null
        ? ogTitleMatch.group(1)!
        : (twitterTitleMatch != null ? twitterTitleMatch.group(1)! : '');

    final twitterDescMatch = RegExp(
      """<meta[^>]+name=["']twitter:description["'][^>]+content=["']([^"']*)["'][^>]*>""",
      caseSensitive: false,
    ).firstMatch(html);

    final hasValidMetaTitle = metaTitle.isNotEmpty && metaTitle.length >= 3;
    final hasValidSummary =
        effectiveSummary.isNotEmpty && effectiveSummary.length >= 10;
    final hasValidTwitter =
        twitterTitleMatch != null || twitterDescMatch != null;
    final hasValidTitle = title.isNotEmpty && title.length >= 3;

    if (!hasValidMetaTitle &&
        !hasValidSummary &&
        !hasValidTwitter &&
        !hasValidTitle) {
      return {
        'success': false,
        'url': sourceUrl,
        'reason': 'No valid meta/social tags found',
      };
    }

    String content = html.replaceAll(
      RegExp(
        r'<script\b[^>]*>.*?</script>',
        dotAll: true,
        caseSensitive: false,
      ),
      '',
    );
    content = content.replaceAll(
      RegExp(r'<style\b[^>]*>.*?</style>', dotAll: true, caseSensitive: false),
      '',
    );

    final contentPatterns = [
      "<article[^>]*>(.*?)</article>",
      "<main[^>]*>(.*?)</main>",
      "<div[^>]+class=[\"'][^\"']*(?:article|content|post|entry)[^\"']*[\"'][^>]*>(.*?)</div>",
      "<div[^>]+id=[\"'][^\"']*(?:article|content|post|entry)[^\"']*[\"'][^>]*>(.*?)</div>",
    ];

    String extractedContent = '';
    for (final pattern in contentPatterns) {
      final match = RegExp(
        pattern,
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(content);
      if (match != null && match.group(1) != null) {
        extractedContent = match.group(1)!;
        break;
      }
    }

    if (extractedContent.isEmpty) {
      final bodyMatch = RegExp(
        r'<body[^>]*>(.*?)</body>',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(html);
      extractedContent = bodyMatch != null ? bodyMatch.group(1)! : '';
    }

    extractedContent = extractedContent
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final decodedTitle = _decodeHtmlIsolate(
      metaTitle.isNotEmpty ? metaTitle : title,
    );
    final sourceName = (task['sourceName'] as String?)?.trim();
    final cleanedTitle = _cleanTitleIsolate(
      decodedTitle,
      sourceUrl,
      sourceName == null || sourceName.isEmpty ? null : <String>[sourceName],
    );
    final decodedSummary = _stripHtmlTags(_decodeHtmlIsolate(effectiveSummary));

    final ngramContent = ContentNgramScorer.buildRichContent(
      rawHtml: html,
      title: cleanedTitle,
      description: decodedSummary,
    );

    final paragraphs = ngramContent
        .split('\n\n')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && !_isPageMetadataLineIsolate(p))
        .toList();

    // 1. Extract genuine article image from OpenGraph, Twitter card, or HTML tags
    String? originalArticleImage;
    final ogImageMatch =
        RegExp(
          r"""<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']*)["'][^>]*>""",
          caseSensitive: false,
        ).firstMatch(html) ??
        RegExp(
          r"""<meta[^>]+content=["']([^"']*)["'][^>]+property=["']og:image["'][^>]*>""",
          caseSensitive: false,
        ).firstMatch(html);
    if (ogImageMatch != null &&
        ogImageMatch.group(1) != null &&
        ogImageMatch.group(1)!.trim().isNotEmpty) {
      originalArticleImage = ogImageMatch.group(1)!.trim();
    }

    if (originalArticleImage == null || originalArticleImage.isEmpty) {
      final twitterImageMatch =
          RegExp(
            r"""<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']*)["'][^>]*>""",
            caseSensitive: false,
          ).firstMatch(html) ??
          RegExp(
            r"""<meta[^>]+content=["']([^"']*)["'][^>]+name=["']twitter:image["'][^>]*>""",
            caseSensitive: false,
          ).firstMatch(html);
      if (twitterImageMatch != null &&
          twitterImageMatch.group(1) != null &&
          twitterImageMatch.group(1)!.trim().isNotEmpty) {
        originalArticleImage = twitterImageMatch.group(1)!.trim();
      }
    }

    if (originalArticleImage == null || originalArticleImage.isEmpty) {
      final articleImgMatch = RegExp(
        r"""<(?:article|main)[^>]*>.*?<img[^>]+src=["']([^"']+)["']""",
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(html);
      if (articleImgMatch != null && articleImgMatch.group(1) != null) {
        final src = articleImgMatch.group(1)!.trim();
        originalArticleImage = _resolveCrawlerImageUrl(src, sourceUrl);
      }
    }

    // Resolve relative URL if needed
    if (originalArticleImage != null && originalArticleImage.isNotEmpty) {
      originalArticleImage = _resolveCrawlerImageUrl(
        originalArticleImage,
        sourceUrl,
      );
    }

    // Fast fallback only if HTML contained no image
    String? articleImage = originalArticleImage;
    if (articleImage == null || articleImage.isEmpty) {
      try {
        articleImage = await MsnImageFetcher.fetchRandomImage(
          cleanedTitle,
        ).timeout(const Duration(seconds: 2));
      } catch (_) {}
    }

    var decodedContent = injectSingleImage(paragraphs, articleImage);
    if (decodedContent.isEmpty) decodedContent = decodedSummary;

    if (RegExp(
          r'<img\s+src=',
          caseSensitive: false,
        ).allMatches(decodedContent).length >
        3) {
      final imgRegex = RegExp(
        r'<img\s+src="([^"]+)"[^>]*>',
        caseSensitive: false,
      );
      final matches = imgRegex.allMatches(decodedContent).toList();
      if (matches.length > 3) {
        final first = matches.first;
        decodedContent = decodedContent.substring(0, first.end);
        decodedContent = '$decodedContent\n\n$decodedSummary';
      }
    }

    final formatted = TinyLLMService.instance.formatArticleFields(
      title: cleanedTitle,
      summary: decodedSummary,
      content: decodedContent,
    );
    final formattedTitle = formatted['title']!.isEmpty
        ? cleanedTitle
        : formatted['title']!;
    final formattedSummary = formatted['summary']!;
    // TinyLLM can preserve or rejoin page chrome after the first extraction.
    // Apply the metadata filter again to the final text so dates, labels and
    // author rows never become visible story paragraphs.
    final formattedContent = _cleanFormattedContentIsolate(
      formatted['content']!.isEmpty ? decodedContent : formatted['content']!,
    );
    final classificationText = '$formattedTitle $formattedSummary';
    final detectedCategory = await NewsIntelligence.classifyCategory(
      classificationText,
      url: sourceUrl,
      title: cleanedTitle,
    );

    return {
      'success': true,
      'is_source': false,
      'url': sourceUrl,
      'title': formattedTitle,
      'summary': formattedSummary,
      'content': formattedContent,
      'category': detectedCategory,
      'language': sourceLanguage,
      'image_url': articleImage ?? '',
      'publishDate': '',
      'status': 'published',
    };
  } catch (e) {
    return {'success': false, 'url': sourceUrl, 'reason': e.toString()};
  }
}

bool _isPageMetadataLineIsolate(String value) {
  final hasDate = RegExp(
    r'(?:الأحد|الإثنين|الثلاثاء|الأربعاء|الخميس|الجمعة|السبت)،?\s*\d{1,2}\s+(?:يناير|فبراير|مارس|أبريل|مايو|يونيو|يوليو|أغسطس|سبتمبر|أكتوبر|نوفمبر|ديسمبر)\s+\d{4}|\d{1,2}:\d{2}\s*[صم]',
    caseSensitive: false,
  ).hasMatch(value);
  if (hasDate && value.length < 90) return true;
  if (RegExp(
    r'^(?:كتب|بقلم|المصدر|محرر|تصوير|متابعة)\s*[:：]',
    caseSensitive: false,
  ).hasMatch(value))
    return true;
  if (value.length < 45 && !RegExp(r'[.!؟،؛:：]').hasMatch(value)) {
    const labels = [
      'فريق',
      'ملعب',
      'استاد',
      'كأس',
      'دوري',
      'بطولة',
      'وادي',
      'الزمالك',
      'الأهلي',
    ];
    if (labels.any(value.contains)) return true;
  }
  return false;
}

String _resolveCrawlerImageUrl(String raw, String pageUrl) {
  return NewsModel.resolveImageUrl(raw, pageUrl);
}

String _cleanFormattedContentIsolate(String value) {
  final parts = value
      .replaceAll('\r\n', '\n')
      .split(RegExp(r'\n\s*\n'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty && !_isPageMetadataLineIsolate(part))
      .toList();
  return parts.join('\n\n');
}

Future<List<String>> _discoverRssArticles(String sourceUrl, int maxUrls) async {
  final base = Uri.tryParse(sourceUrl);
  if (base == null || base.host.isEmpty) return <String>[];

  final candidates = <Uri>[
    base.resolve('/feed/'),
    base.resolve('/rss'),
    base.resolve('/rss.xml'),
    base.resolve('/feed.xml'),
  ];
  final found = <String>{};
  for (final feedUri in candidates) {
    try {
      final response = await http
          .get(
            feedUri,
            headers: {
              'User-Agent': 'Mozilla/5.0 (compatible; YallaNews/1.0)',
              'Accept':
                  'application/rss+xml, application/atom+xml, application/xml, text/xml',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 300) continue;

      final document = parse(response.body);
      for (final item in document.querySelectorAll('item, entry')) {
        final linkElement = item.querySelector('link');
        final link =
            (linkElement?.attributes['href'] ?? linkElement?.text)?.trim() ??
            '';
        if (link.isEmpty) continue;
        final uri = Uri.tryParse(link);
        if (uri == null || uri.host.isEmpty) continue;
        if (uri.host != base.host && !uri.host.endsWith('.${base.host}'))
          continue;
        if (NewsUriParser.isValidArticleUrl(uri.toString()))
          found.add(uri.toString());
        if (found.length >= maxUrls) return found.toList();
      }
    } catch (_) {}
  }
  return found.toList();
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _decodeHtmlIsolate(String text) {
  if (text.isEmpty) return text;
  text = text.replaceAll('&quot;', '"');
  text = text.replaceAll('&#34;', '"');
  text = text.replaceAll('&apos;', "'");
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
  return text;
}

String _stripHtmlTags(String text) {
  if (text.isEmpty) return text;
  final withoutTags = text.replaceAll(RegExp(r'<[^>]*>'), '');
  return _decodeHtmlIsolate(withoutTags);
}

String _cleanTitleIsolate(
  String title,
  String url, [
  List<String>? sourceNames,
]) {
  if (title.isEmpty) return title;
  String cleaned = title;
  final uri = Uri.tryParse(url);
  final domain = uri != null ? uri.host.toLowerCase() : '';
  final separators = [
    ' - ',
    ' | ',
    ' :: ',
    ' — ',
    ' – ',
    ' : ',
    ' › ',
    ' « ',
    ' » ',
  ];
  bool removedSuffix;
  do {
    removedSuffix = false;
    for (final sep in separators) {
      final index = cleaned.lastIndexOf(sep);
      if (index < 0) continue;
      final lastPart = cleaned.substring(index + sep.length).trim();
      final words = lastPart.split(RegExp(r'\s+'));
      if (words.length <= 8 &&
          !lastPart.contains('.') &&
          !lastPart.contains('?') &&
          _looksLikePublisherSuffix(lastPart)) {
        cleaned = cleaned.substring(0, index).trim();
        removedSuffix = true;
        break;
      }
    }
  } while (removedSuffix);

  final namesToStrip = <String>[];
  if (domain.isNotEmpty) {
    final domainParts = domain.split('.');
    final sourceName = domainParts.first;
    if (sourceName.length > 3) {
      namesToStrip.add(sourceName);
    }
  }
  if (sourceNames != null) {
    namesToStrip.addAll(sourceNames.where((n) => n.length > 2));
  }

  for (final name in namesToStrip) {
    final escaped = RegExp.escape(name);
    final pattern = RegExp(
      '(?:\\s*(?:لـ|من|إلى|مع|عبر|بواسطة|في|عند)\\s+)?$escaped',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceAll(pattern, '').trim();
    cleaned = cleaned
        .replaceAll(RegExp(r'^[\s\-\|:»]+|[\s\-\|:»]+$'), '')
        .trim();
  }

  if (domain.isNotEmpty) {
    final domainParts = domain.split('.');
    final sourceName = domainParts.first;
    if (sourceName.length > 3 && cleaned.toLowerCase().endsWith(sourceName)) {
      final escaped = RegExp.escape(sourceName);
      final regex = RegExp(
        '\\s*[-|:]?\\s*$escaped\\s*\$',
        caseSensitive: false,
      );
      cleaned = cleaned.replaceAll(regex, '').trim();
    }
    final aliases = <String, List<String>>{
      'hesport': ['هسبورت', 'هيسبورت', 'hesport'],
      'hespress': ['هسبريس', 'hespress'],
      'arageek': ['أراجيك', 'اراجيك', 'arageek'],
      'kooora': ['كووورة', 'kora', 'kooora'],
      'alyaoum24': ['اليوم 24', 'اليوم24', 'alyaoum24'],
      'le360': ['لي360', 'le360'],
    };
    for (final alias in aliases[sourceName] ?? const <String>[]) {
      final pattern =
          '(?:\\s*(?:لـ|من|إلى|مع|عبر|بواسطة|في|عند)\\s+)?${RegExp.escape(alias)}\\s*' +
          r'$';
      cleaned = cleaned
          .replaceFirst(RegExp(pattern, caseSensitive: false), '')
          .trim();
    }
  }
  final categoryWords = [
    'أخبار',
    'رياضة',
    'اقتصاد',
    'سياسة',
    'تكنولوجيا',
    'ثقافة',
    'فن',
    'ترفيه',
    'صحة',
    'علم',
    'بيئة',
    'سفر',
    'سياحة',
    'ألعاب',
    'تعليم',
    'محافظات',
    'دولي',
    'محلي',
    'عاجل',
    'حصري',
    'ممتاز',
    'رأي',
    'مقالات',
    'تحقيقات',
    'حوادث',
    'منوعات',
    'ميديا',
    'فيديو',
    'صور',
    'بث مباشر',
    'مباشر',
  ];
  for (final word in categoryWords) {
    final escaped = RegExp.escape(word);
    final regex = RegExp('\\s*[-|:]?\\s*$escaped\\s*\$');
    cleaned = cleaned.replaceAll(regex, '').trim();
  }
  cleaned = cleaned.replaceAll(RegExp(r'[-|:]\s*$'), '').trim();
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned;
}

bool _looksLikePublisherSuffix(String text) {
  final lower = text.toLowerCase();
  const markers = <String>[
    'جريدة',
    'صحيفة',
    'مجلة',
    'موقع',
    'وكالة',
    'شبكة',
    'قناة',
    'إذاعة',
    'نت',
    'نيوز',
    'news',
    'times',
    'post',
    'press',
    'daily',
    'media',
    'kooora',
    'كووورة',
    'المنتخب',
    'الرياضية',
    'الاقتصادية',
    'الجزيرة',
    'هسبريس',
    'اليوم24',
    'le360',
    'رويترز',
    'reuters',
  ];
  if (markers.any(lower.contains)) return true;
  final words = lower.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
  return words.length >= 2 &&
      words.length <= 8 &&
      !RegExp(r'[.!؟،؛]').hasMatch(text);
}

String injectSingleImage(List<String> paragraphs, String? imageUrl) {
  if (imageUrl == null || imageUrl.isEmpty) return paragraphs.join('\n\n');
  if (paragraphs.isEmpty) return '<img src="$imageUrl" />';
  final mid = paragraphs.length ~/ 2;
  final result = List<String>.from(paragraphs);
  result.insert(
    mid,
    '<img src="$imageUrl" style="width:100%;max-height:380px;object-fit:cover;border-radius:12px;margin:16px 0;display:block;" />',
  );
  return result.join('\n\n');
}

class CrawlerState {
  final bool running;
  final bool reset;
  final int processedSources;
  final int totalSources;

  const CrawlerState({
    this.running = false,
    this.reset = false,
    this.processedSources = 0,
    this.totalSources = 0,
  });

  CrawlerState copyWith({
    bool? running,
    bool? reset,
    int? processedSources,
    int? totalSources,
  }) {
    return CrawlerState(
      running: running ?? this.running,
      reset: reset ?? this.reset,
      processedSources: processedSources ?? this.processedSources,
      totalSources: totalSources ?? this.totalSources,
    );
  }
}

// ─── Background Isolate Crawler Service ──────────────────────────────────────

class BackgroundCrawlerService {
  BackgroundCrawlerService._internal();
  static final BackgroundCrawlerService instance =
      BackgroundCrawlerService._internal();

  bool _isRunning = false;
  bool get isRunning => _isRunning;
  int _crawlGeneration = 0;

  Isolate? _crawlerIsolate;
  ReceivePort? _receivePort;
  SendPort? _crawlerSendPort;

  final Map<int, Completer<Map<String, dynamic>?>> _pendingRequests = {};
  int _nextRequestId = 0;
  StreamSubscription<dynamic>? _receiveSubscription;

  Timer? _memoryWatchdog;
  static const int _memoryWarningThresholdMb = 500;
  static const int _memoryCriticalThresholdMb = 900;

  StreamSubscription? _connectivitySubscription;
  Future<void>? _activeCrawl;

  final _articleStreamController = StreamController<NewsModel>.broadcast();
  Stream<NewsModel> get articleStream => _articleStreamController.stream;

  final _stateStreamController = StreamController<CrawlerState>.broadcast();
  Stream<CrawlerState> get stateStream => _stateStreamController.stream;

  Future<void> stop() async {
    _crawlGeneration++;
    _isRunning = false;
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _stopMemoryWatchdog();
    await _stopCrawlerIsolate();
    _stateStreamController.add(const CrawlerState(running: false));
    await _activeCrawl;
  }

  Future<int> get _topSourcesCount async =>
      await AppSettings.instance.getTopSourcesCount();

  Future<int> get _maxUrlsPerSource async =>
      await AppSettings.instance.getMaxUrlsPerSource();

  bool _isSmallMemoryPlatform() => MemoryOptimizer.isSmallMemory;

  Future<void> startSilentCrawl({
    required YallaEngineService engineService,
    VoidCallback? onProgress,
    VoidCallback? onComplete,
    bool requireWifi = true,
  }) {
    final active = _activeCrawl;
    if (active != null) {
      onComplete?.call();
      return active;
    }

    late final Future<void> crawl;
    crawl =
        _runSilentCrawl(
          engineService: engineService,
          onProgress: onProgress,
          onComplete: onComplete,
          requireWifi: requireWifi,
        ).whenComplete(() {
          if (identical(_activeCrawl, crawl)) {
            _activeCrawl = null;
          }
        });
    _activeCrawl = crawl;
    return crawl;
  }

  Future<void> _runSilentCrawl({
    required YallaEngineService engineService,
    VoidCallback? onProgress,
    VoidCallback? onComplete,
    bool requireWifi = true,
  }) async {
    final generation = ++_crawlGeneration;
    debugPrint(
      '[SILENT CRAWLER] start requested requireWifi=$requireWifi running=$_isRunning',
    );
    if (_isRunning) {
      onComplete?.call();
      return;
    }

    if (requireWifi) {
      final isWifi = await ConnectivityService.isWifi();
      if (generation != _crawlGeneration) return;
      if (!isWifi) {
        engineService.addLog(
          '[SILENT CRAWLER] WiFi not connected. Resetting crawler scheduler per process_2 policy.',
        );
        _stateStreamController.add(const CrawlerState(reset: true));
        onComplete?.call();
        return;
      }
    }

    final smallMemory = _isSmallMemoryPlatform();
    final throttle = smallMemory
        ? max(1, await _topSourcesCount - 2)
        : await _topSourcesCount;
    if (generation != _crawlGeneration) return;

    _isRunning = true;
    debugPrint('[SILENT CRAWLER] started');
    _stateStreamController.add(const CrawlerState(running: true));
    engineService.addLog(
      '[SILENT CRAWLER] Starting background-isolate crawler.',
    );

    try {
      _stopMemoryWatchdog();
      await _startCrawlerIsolate(engineService);
      if (generation != _crawlGeneration) return;
      debugPrint('[SILENT CRAWLER] isolate ready');
      engineService.addLog('[SILENT CRAWLER] Isolate ready.');

      _startMemoryWatchdog(engineService);

      final db = NewsDatabase.instance;
      final appLanguage = AppSettings.instance.locale?.languageCode ?? 'ar';
      final appCountry = AppSettings.instance.countryCode;
      final lastCrawlTime = await db.getLastCrawlTime('__global__');
      final lastVisitedTimestamp = lastCrawlTime?.millisecondsSinceEpoch ?? 0;

      final sourcesToCrawl = <NewsSource>[];
      // Sync sources from the API first so all languages are available,
      // then fall back to the local DB. If no sources match the user's
      // language, crawl all available sources so the feed is never empty.
      final allLocalSources = await db.getAllSources(syncApi: true);
      final matchedSources = allLocalSources.where((s) {
        final languageMatch =
            s.language.trim().isEmpty ||
            _resolveCrawlerLanguage(s.language, appLanguage) == appLanguage;
        final countryMatch =
            appCountry.isEmpty ||
            s.countryCode.isEmpty ||
            s.countryCode == appCountry;
        return languageMatch && countryMatch;
      }).toList();
      final sourcesToUse = matchedSources.isNotEmpty
          ? matchedSources
          : allLocalSources;
      sourcesToUse.shuffle();
      final selected = throttle < sourcesToUse.length
          ? sourcesToUse.take(throttle).toList()
          : List<NewsSource>.from(sourcesToUse);
      sourcesToCrawl.addAll(selected);
      debugPrint(
        '[SILENT CRAWLER] local sources=${sourcesToCrawl.length} language=$appLanguage',
      );
      debugPrint(
        '[SILENT CRAWLER] sources selected=${sourcesToCrawl.length} language=$appLanguage',
      );

      if (sourcesToCrawl.isEmpty) {
        debugPrint('[SILENT CRAWLER] no sources available');
        engineService.addLog('[SILENT CRAWLER] No sources available.');
        _isRunning = false;
        onComplete?.call();
        return;
      }

      BenchmarkResult benchmarkProfile;
      try {
        final benchmarkSource = sourcesToCrawl.isNotEmpty
            ? (sourcesToCrawl..shuffle()).first
            : null;
        if (benchmarkSource == null) {
          engineService.addLog(
            '[BENCHMARK] No sources available for benchmark.',
          );
          benchmarkProfile = _safeStartupBenchmark();
        } else {
          // Do not block the first crawl on a network benchmark. Some news
          // sites keep connections open or return bot-check pages, which made
          // the crawler appear stuck before it processed any source.
          engineService.addLog(
            '[BENCHMARK] Skipped for startup; crawling with safe limits.',
          );
          benchmarkProfile = _safeStartupBenchmark();
        }
      } catch (e) {
        engineService.addLog('[BENCHMARK] Benchmark failed: $e');
        benchmarkProfile = await _fallbackBenchmark(engineService);
      }

      final limits = benchmarkProfile.limits;
      final maxUrls = limits.urlsPerSource;
      final perSourceLimit = limits.perSourceLimit;
      final pauseBetweenArticles = limits.pauseBetweenArticles;
      final pauseBetweenSources = limits.pauseBetweenSources;

      engineService.addLog(
        '[BENCHMARK] Complete: tier=${benchmarkProfile.tier} '
        'mem=${benchmarkProfile.memoryMb}MB cpu=${benchmarkProfile.cpuScore} '
        'sources=${limits.sourcesToCrawl} articlesPerSource=${limits.urlsPerSource} '
        'pause=${limits.pauseBetweenArticles.inMilliseconds}ms',
      );

      if (sourcesToCrawl.isEmpty) {
        engineService.addLog('[SILENT CRAWLER] No sources to crawl.');
        _isRunning = false;
        _stateStreamController.add(const CrawlerState(running: false));
        onComplete?.call();
        return;
      }

      final limitedSources = sourcesToCrawl
          .take(limits.sourcesToCrawl)
          .toList();
      limitedSources.shuffle(Random());
      debugPrint(
        '[SILENT CRAWLER] queued=${limitedSources.length} maxUrls=$maxUrls',
      );
      _stateStreamController.add(
        CrawlerState(running: true, totalSources: limitedSources.length),
      );
      engineService.addLog(
        '[SILENT CRAWLER] Queued ${limitedSources.length} sources.',
      );

      for (int i = 0; i < limitedSources.length; i++) {
        if (!_isRunning) break;

        final source = limitedSources[i];
        debugPrint('[SILENT CRAWLER] processing source=${source.url}');
        final last = await db.getLastCrawlTime(source.url);
        // A fresh app session must be able to refresh sources again. The old
        // 35-minute gate made the crawler appear dead after a previous run,
        // especially during testing and on devices that restart the app.
        if (last != null && DateTime.now().difference(last).inMinutes < 5) {
          engineService.addLog(
            '[SILENT CRAWLER] [${i + 1}/${limitedSources.length}] ${source.name}: last crawled ${DateTime.now().difference(last).inMinutes} min ago, skipping.',
          );
          onProgress?.call();
          continue;
        }

        engineService.addLog(
          '[SILENT CRAWLER] [${i + 1}/${limitedSources.length}] Crawling: ${source.name}',
        );

        try {
          // A single unreachable or slow publisher must never block the whole
          // crawler queue. Network calls inside a source crawler can otherwise
          // leave the Android isolate waiting indefinitely.
          final quality =
              await _crawlSourceInBackground(
                source,
                engineService,
                maxUrls: maxUrls,
                perSourceLimit: perSourceLimit,
                pauseBetweenArticles: pauseBetweenArticles,
              ).timeout(
                const Duration(seconds: 25),
                onTimeout: () {
                  debugPrint('[SILENT CRAWLER] timeout source=${source.url}');
                  engineService.addLog(
                    '[SILENT CRAWLER] timeout ${source.name}; continuing.',
                  );
                  return null;
                },
              );
          debugPrint(
            '[SILENT CRAWLER] source result=${source.url} quality=$quality',
          );
          onProgress?.call();
          try {
            await ServerApiService.updateSourceCrawlTime(source.url);
          } catch (_) {}
          if (quality != null && quality > 0) {
            try {
              await ServerApiService.updateSourceScore(source.url, quality);
            } catch (_) {}
          }
          engineService.addLog('[SILENT CRAWLER] √ ${source.name} done.');
        } catch (e) {
          engineService.addLog('[SILENT CRAWLER] X ${source.name} failed: $e');
        }

        await Future.delayed(pauseBetweenSources);
      }

      engineService.addLog('[SILENT CRAWLER] Background crawl complete!');
    } catch (e) {
      engineService.addLog('[SILENT CRAWLER] Fatal error: $e');
    } finally {
      _stopMemoryWatchdog();
      _isRunning = false;
      await _stopCrawlerIsolate();
      _stateStreamController.add(const CrawlerState(running: false));
      onComplete?.call();
    }
  }

  Future<void> _startCrawlerIsolate(YallaEngineService engineService) async {
    final ReceivePort receivePort = ReceivePort();
    _receivePort = receivePort;

    _crawlerIsolate = await Isolate.spawn(_crawlerIsolateEntry, {
      'sendPort': receivePort.sendPort,
    });

    _receiveSubscription = _receivePort!.listen((message) {
      final Map<String, dynamic> msg = message as Map<String, dynamic>;
      final String type = msg['type'] as String;
      if (type == 'ready') {
        _crawlerSendPort = msg['port'] as SendPort;
      } else if (type == 'result') {
        final int requestId = msg['requestId'] as int;
        final completer = _pendingRequests.remove(requestId);
        if (completer != null && !completer.isCompleted) {
          completer.complete(msg['result'] as Map<String, dynamic>?);
        }
      } else if (type == 'error') {
        final int? requestId = msg['requestId'] as int?;
        final error = msg['error'] as String;
        if (requestId != null) {
          final completer = _pendingRequests.remove(requestId);
          if (completer != null && !completer.isCompleted) {
            completer.completeError(Exception(error));
          }
        } else {
          engineService.addLog('[SILENT CRAWLER] Isolate error: $error');
        }
      }
    });
  }

  Future<void> _stopCrawlerIsolate() async {
    if (_crawlerSendPort != null) {
      try {
        _crawlerSendPort!.send({'action': 'stop'});
      } catch (_) {}
    }
    await _receiveSubscription?.cancel();
    _receiveSubscription = null;
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    _pendingRequests.clear();
    final port = _receivePort;
    if (port != null) {
      port.close();
    }
    _crawlerIsolate?.kill(priority: Isolate.immediate);
    _crawlerIsolate = null;
    _receivePort = null;
    _crawlerSendPort = null;
  }

  void _startMemoryWatchdog(YallaEngineService engineService) {
    _memoryWatchdog?.cancel();
    final warningThreshold = _isSmallMemoryPlatform()
        ? 200
        : _memoryWarningThresholdMb;
    final criticalThreshold = _isSmallMemoryPlatform()
        ? 320
        : _memoryCriticalThresholdMb;
    _memoryWatchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_isRunning) return;
      try {
        final info = ProcessInfo.currentRss;
        final memoryMb = info ~/ 1024 ~/ 1024;
        if (memoryMb >= criticalThreshold) {
          engineService.addLog(
            '[MEMORY] Critical memory usage: ${memoryMb}MB. Pausing crawler to avoid freeze.',
          );
          _isRunning = false;
        } else if (memoryMb >= warningThreshold) {
          engineService.addLog(
            '[MEMORY] High memory usage: ${memoryMb}MB. Slowing crawler.',
          );
        }
      } catch (_) {}
    });
  }

  void _stopMemoryWatchdog() {
    _memoryWatchdog?.cancel();
    _memoryWatchdog = null;
  }

  Future<Map<String, dynamic>?> _processArticleUrl(
    String url, {
    String? sourceLanguage,
    String? sourceName,
  }) async {
    if (_crawlerSendPort == null) return null;

    final requestId = _nextRequestId++;
    final completer = Completer<Map<String, dynamic>?>();
    _pendingRequests[requestId] = completer;

    _crawlerSendPort!.send({
      'action': 'crawl',
      'requestId': requestId,
      'sourceUrl': url,
      'sourceName': sourceName,
      'maxUrls': 1,
      'sourceLanguage': sourceLanguage,
    });

    try {
      final result = await completer.future.timeout(
        const Duration(seconds: 15),
      );
      return result;
    } catch (e) {
      debugPrint('[CRAWLER] Article parser request failed: $e');
      return <String, dynamic>{
        'success': false,
        'url': url,
        'reason': e.toString(),
      };
    } finally {
      _pendingRequests.remove(requestId);
    }
  }

  Future<double?> _crawlSourceInBackground(
    NewsSource source,
    YallaEngineService engineService, {
    required int maxUrls,
    required int perSourceLimit,
    required Duration pauseBetweenArticles,
  }) async {
    if (_crawlerSendPort == null) return null;
    final crawlLanguage = _resolveCrawlerLanguage(
      source.language,
      AppSettings.instance.locale?.languageCode ?? 'ar',
    );

    final requestId = _nextRequestId++;
    final completer = Completer<Map<String, dynamic>?>();
    _pendingRequests[requestId] = completer;

    _crawlerSendPort!.send({
      'action': 'crawl',
      'requestId': requestId,
      'sourceUrl': source.url,
      'sourceName': source.name,
      'maxUrls': maxUrls,
      'perSourceLimit': perSourceLimit,
      'validCategoryIds': CategoryService.instance.initialized
          ? CategoryService.instance.categoryIds
          : null,
      'sourceLanguage': crawlLanguage,
    });

    try {
      final result = await completer.future.timeout(
        const Duration(seconds: 30),
      );
      if (result == null || result['success'] != true) {
        engineService.addLog(
          '[CRAWL PASS 1] Failed for ${source.url}: ${result?['reason'] ?? 'unknown error'}',
        );
        return null;
      }

      List<String> rawUrls = [];
      if (result['is_source'] == true) {
        final raw = result['articles'] ?? const [];
        if (raw is List) {
          rawUrls = raw.map((u) => u.toString()).toList();
        }
      } else {
        NewsModel article;
        if (!kIsWeb && NewsBrainService.instance.isAvailable) {
          try {
            final brainArticle = await NewsBrainService.instance
                .extractArticleUrl(source.url);
            if (brainArticle != null) {
              article = brainArticle.toNewsModel(category: source.category);
              engineService.addLog(
                '[NEWSBRAIN] Extracted single article via C++ engine: ${article.title}',
              );
            } else {
              article = NewsModel.fromJson(result, source.url);
            }
          } catch (_) {
            article = NewsModel.fromJson(result, source.url);
          }
        } else {
          article = NewsModel.fromJson(result, source.url);
        }
        article = article.copyWith(
          sourceName: article.sourceName.isEmpty
              ? source.name
              : article.sourceName,
          sourceUrl: article.sourceUrl.isEmpty ? source.url : article.sourceUrl,
          language: article.language.isEmpty
              ? crawlLanguage
              : _resolveCrawlerLanguage(article.language, crawlLanguage),
        );
        if (!YallaEngineService.hasValidTitle(article.title) ||
            !_isValidCrawledNews(article)) {
          engineService.addLog(
            '[VALIDATION] Skipped invalid article: ${article.url}',
          );
          return 0.0;
        }
        final categoryIds = CategoryService.instance.categoryIds;
        final classifiedCategory = await NewsIntelligence.classifyCategory(
          '${article.title} ${article.summary}',
          url: article.url,
          title: article.title,
          validCategoryIds: categoryIds.isEmpty ? null : categoryIds,
        );
        article = article.copyWith(category: classifiedCategory);
        if (article.imageUrl.isEmpty) {
          article = article.copyWith(
            imageUrl: NewsModel.getFallbackImage(article.category),
          );
        }
        if (hasNativeEngine &&
            scoreArticleQuality(
                  article.title,
                  article.content,
                  article.summary,
                ) <
                0.45) {
          engineService.addLog(
            '[QUALITY GATE] Rejected non-news page: ${article.url}',
          );
          return 0.0;
        }
        await _publishValidatedArticle(article, engineService);
        return 0.5;
      }

      if (rawUrls.isEmpty) {
        engineService.addLog(
          '[CRAWL PASS 1] No articles discovered from ${source.url}',
        );
        return null;
      }

      engineService.addLog(
        '[CRAWL PASS 1] Discovered ${rawUrls.length} candidate URLs.',
      );

      if (rawUrls.length > maxUrls) {
        rawUrls = rawUrls.take(maxUrls).toList();
      }

      final sourceUri = Uri.tryParse(source.url);
      String sourceHost = sourceUri?.host.toLowerCase() ?? '';
      if (sourceHost.startsWith('www.')) sourceHost = sourceHost.substring(4);

      if (sourceHost.isNotEmpty) {
        rawUrls = rawUrls.where((url) {
          final uri = Uri.tryParse(url);
          if (uri == null) return false;
          String host = uri.host.toLowerCase();
          if (host.startsWith('www.')) host = host.substring(4);
          return host == sourceHost || host.endsWith('.$sourceHost');
        }).toList();
      }

      if (rawUrls.isEmpty) {
        engineService.addLog(
          '[CRAWL FILTER] No URLs passed source-domain filter for ${source.url}.',
        );
        return 0.0;
      }

      final db = NewsDatabase.instance;
      final blacklistCheckedUrls = <String>[];
      for (final url in rawUrls) {
        final urlHash = NewsModel.hashUrl(url);
        final isBlacklisted = await db.isUrlBlacklisted(urlHash);
        if (!isBlacklisted) blacklistCheckedUrls.add(url);
      }

      if (blacklistCheckedUrls.isEmpty) {
        engineService.addLog('[CRAWL PASS 2] All URLs blacklisted.');
        return 0.0;
      }

      final limitedUrls = blacklistCheckedUrls.take(perSourceLimit).toList();
      int successCount = 0;
      int failureCount = 0;

      final bool smallMemory = _isSmallMemoryPlatform();
      final bool forceSingleUrl =
          smallMemory && await ConnectivityService.isWifi();
      final int effectivePerSourceLimit = forceSingleUrl ? 1 : perSourceLimit;
      final int effectiveBatchSize = forceSingleUrl ? 1 : 3;

      if (forceSingleUrl) {
        engineService.addLog(
          '[CRAWL] Small memory + WiFi: forcing single-URL crawl',
        );
      }

      final Set<String> seenHashes = <String>{};
      final List<NewsModel> batchArticles = <NewsModel>[];
      for (final url in limitedUrls.take(effectivePerSourceLimit)) {
        if (!_isRunning) break;

        final urlHash = NewsModel.hashUrl(url);
        if (seenHashes.contains(urlHash)) {
          engineService.addLog(
            '[DEDUP] Skipping duplicate URL hash in this run: $url',
          );
          failureCount++;
          continue;
        }
        seenHashes.add(urlHash);

        final alreadyInDb = await db.articleUrlExists(url);
        if (alreadyInDb) {
          engineService.addLog('[DEDUP] Skipping existing article in DB: $url');
          failureCount++;
          continue;
        }

        try {
          NewsModel? article;
          bool usedNewsBrain = false;

          if (!kIsWeb && NewsBrainService.instance.isAvailable) {
            try {
              final brainArticle = await NewsBrainService.instance
                  .extractArticleUrl(url);
              if (brainArticle != null) {
                article = brainArticle.toNewsModel();
                usedNewsBrain = true;
                engineService.addLog(
                  '[NEWSBRAIN] Extracted article via C++ engine: ${article.title}',
                );
              }
            } catch (_) {}
          }

          if (article == null ||
              !YallaEngineService.hasValidTitle(article.title) ||
              !_isValidCrawledNews(article)) {
            if (usedNewsBrain) {
              engineService.addLog(
                '[NEWSBRAIN] Article failed validation, falling back to isolate parser for: $url',
              );
            }
            final result = await _processArticleUrl(
              url,
              sourceLanguage: crawlLanguage,
              sourceName: source.name,
            );
            if (result == null ||
                result['success'] != true ||
                result['is_source'] == true) {
              failureCount++;
              engineService.addLog(
                '[CRAWL PASS 2] Failed to extract $url: '
                '${result?['reason'] ?? 'unknown error'}',
              );
              continue;
            }
            article = NewsModel.fromJson(result, url);
          }

          var currentArticle = article.copyWith(
            sourceName: article.sourceName.isEmpty
                ? source.name
                : article.sourceName,
            sourceUrl: article.sourceUrl.isEmpty
                ? source.url
                : article.sourceUrl,
            language: article.language.isEmpty
                ? crawlLanguage
                : _resolveCrawlerLanguage(article.language, crawlLanguage),
          );
          final validCategoryIds = CategoryService.instance.categoryIds;
          final classifiedCategory = await NewsIntelligence.classifyCategory(
            '${currentArticle.title} ${currentArticle.summary}',
            url: currentArticle.url,
            title: currentArticle.title,
            validCategoryIds: validCategoryIds.isEmpty
                ? null
                : validCategoryIds,
          );
          currentArticle = currentArticle.copyWith(
            category: classifiedCategory,
          );

          if (currentArticle.imageUrl.isEmpty) {
            final categorySlug = currentArticle.category.toLowerCase();
            final seed = Uri.parse(url).path.hashCode.abs() % 1000;
            currentArticle = currentArticle.copyWith(
              imageUrl:
                  'https://placehold.co/600x400/EEE/31343C?text=$categorySlug+$seed',
            );
          }

          if (!_isValidCrawledNews(currentArticle)) {
            engineService.addLog('[VALIDATION] Skipped invalid article: $url');
            failureCount++;
            continue;
          }

          if (hasNativeEngine) {
            final qualityScore = scoreArticleQuality(
              currentArticle.title,
              currentArticle.content,
              currentArticle.summary,
            );
            if (qualityScore < 0.45) {
              engineService.addLog(
                '[QUALITY GATE] Rejected low-score page (${qualityScore.toStringAsFixed(2)}): $url',
              );
              failureCount++;
              continue;
            }
          }

          batchArticles.add(currentArticle);
          successCount++;

          if (batchArticles.length >= effectiveBatchSize) {
            for (final a in batchArticles) {
              await _publishValidatedArticle(a, engineService);
            }
            batchArticles.clear();
            await Future.delayed(pauseBetweenArticles);
          }
        } catch (e) {
          failureCount++;
          engineService.addLog('[CRAWL] Error processing $url: $e');
        }

        await Future.delayed(pauseBetweenArticles);
      }

      if (batchArticles.isNotEmpty) {
        for (final a in batchArticles) {
          await _publishValidatedArticle(a, engineService);
        }
        batchArticles.clear();
      }

      final quality = successCount / max(limitedUrls.length, 1);
      engineService.addLog(
        '[CRAWL PASS 3] Complete. Success: $successCount, Failures: $failureCount, Quality: ${quality.toStringAsFixed(2)}.',
      );
      return quality;
    } finally {
      _pendingRequests.remove(requestId);
    }
  }

  Future<void> _publishValidatedArticle(
    NewsModel article,
    YallaEngineService engineService,
  ) async {
    final absoluteImageUrl = NewsModel.resolveImageUrl(
      article.imageUrl,
      article.url,
    );
    final articleToPublish = article.copyWith(
      imageUrl: absoluteImageUrl.isEmpty
          ? NewsModel.getFallbackImage(article.category)
          : absoluteImageUrl,
    );
    _emitArticle(articleToPublish);
    if (kIsWeb) return;

    try {
      await NewsDatabase.instance.saveCrawledArticles([
        articleToPublish,
      ], articleToPublish.sourceUrl);
    } catch (e) {
      engineService.addLog(
        '[LOCAL] Save failed for ${articleToPublish.url}: $e',
      );
    }

    try {
      await ServerApiService.saveArticle(
        articleToPublish,
      ).timeout(const Duration(seconds: 10));
      engineService.addLog('[SERVER] Pushed article: ${articleToPublish.url}');
    } catch (e) {
      engineService.addLog(
        '[SERVER] Push failed for ${articleToPublish.url}: $e',
      );
    }
  }

  void _emitArticle(NewsModel article) {
    if (!_articleStreamController.isClosed) {
      _articleStreamController.add(article);
    }
  }

  void dispose() {
    _stopMemoryWatchdog();
    _connectivitySubscription?.cancel();
    _articleStreamController.close();
    _stateStreamController.close();
    _stopCrawlerIsolate();
  }

  Future<void> forceRefresh({
    required YallaEngineService engineService,
    VoidCallback? onProgress,
    VoidCallback? onComplete,
  }) async {
    if (_isRunning) return;

    if (_isSmallMemoryPlatform()) {
      engineService.addLog(
        '[SILENT CRAWLER] Skipped: device is in small-memory mode.',
      );
      onComplete?.call();
      return;
    }

    final onWifi = await ConnectivityService.isWifi();
    if (!onWifi) {
      engineService.addLog(
        '[SILENT CRAWLER] Not on Wi-Fi — skipping force refresh, use API refresh instead.',
      );
      onComplete?.call();
      return;
    }

    _isRunning = true;
    _startMemoryWatchdog(engineService);
    engineService.addLog(
      '[SILENT CRAWLER] Wi-Fi detected — force refresh started...',
    );

    try {
      final db = NewsDatabase.instance;
      final allSources = await db.getAllSources(syncApi: true);

      final appLanguage = AppSettings.instance.locale?.languageCode ?? 'ar';
      final appCountry = AppSettings.instance.countryCode;

      final List<NewsSource> matchedSources = allSources.where((s) {
        final languageMatch =
            s.language.trim().isEmpty ||
            _resolveCrawlerLanguage(s.language, appLanguage) == appLanguage;
        final countryMatch =
            appCountry.isEmpty ||
            s.countryCode.isEmpty ||
            s.countryCode == appCountry;
        return languageMatch && countryMatch;
      }).toList();
      final sourcesToUse = matchedSources.isNotEmpty
          ? matchedSources
          : allSources;
      final List<NewsSource> topSources = List.from(sourcesToUse)
        ..sort((a, b) => b.rank.compareTo(a.rank));
      final sourcesToCrawl = topSources.take(await _topSourcesCount).toList();

      sourcesToCrawl.shuffle(Random());

      BenchmarkResult benchmarkProfile;
      try {
        final benchmarkSource = sourcesToCrawl.isNotEmpty
            ? (sourcesToCrawl..shuffle()).first
            : null;
        if (benchmarkSource == null) {
          engineService.addLog(
            '[BENCHMARK] No sources available for benchmark.',
          );
          benchmarkProfile = await _fallbackBenchmark(engineService);
        } else {
          final benchmarkUrl = await _pickValidArticleUrl(benchmarkSource);
          if (benchmarkUrl == null) {
            engineService.addLog(
              '[BENCHMARK] No article URL found for ${benchmarkSource.name}.',
            );
            benchmarkProfile = await _fallbackBenchmark(engineService);
          } else {
            benchmarkProfile = await _runCrawlBenchmark(
              engineService,
              benchmarkSource,
              benchmarkUrl,
            );
          }
        }
      } catch (e) {
        engineService.addLog('[BENCHMARK] Benchmark failed: $e');
        benchmarkProfile = await _fallbackBenchmark(engineService);
      }

      final limits = benchmarkProfile.limits;

      for (int i = 0; i < sourcesToCrawl.length; i++) {
        final source = sourcesToCrawl[i];
        engineService.addLog(
          '[SILENT CRAWLER] [${i + 1}/${sourcesToCrawl.length}] Refreshing: ${source.name}',
        );

        try {
          await _crawlSourceInBackground(
            source,
            engineService,
            maxUrls: limits.urlsPerSource,
            perSourceLimit: limits.perSourceLimit,
            pauseBetweenArticles: limits.pauseBetweenArticles,
          );
          onProgress?.call();
          try {
            await ServerApiService.updateSourceCrawlTime(source.url);
          } catch (_) {}
        } catch (e) {
          engineService.addLog('[SILENT CRAWLER] X ${source.name} failed: $e');
        }
      }

      engineService.addLog('[SILENT CRAWLER] Force refresh complete!');
    } catch (e) {
      engineService.addLog('[SILENT CRAWLER] Fatal error: $e');
    } finally {
      _stopMemoryWatchdog();
      _isRunning = false;
      onComplete?.call();
    }
  }

  bool _isValidCrawledNews(NewsModel article) {
    final title = article.title.trim();
    final url = article.url.trim();
    final content = article.content.trim();

    if (title.isEmpty || url.isEmpty || url.length < 10) return false;
    if (content.isEmpty && article.summary.trim().isEmpty) return false;

    return true;
  }

  Future<String?> _pickValidArticleUrl(NewsSource source) async {
    try {
      final response = await http
          .get(Uri.parse(source.url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final document = parse(response.body);
      final anchors = document.querySelectorAll('a[href]');
      final base = Uri.parse(source.url);
      final seen = <String>{};
      for (final node in anchors) {
        final href = node.attributes['href'];
        if (href == null || href.isEmpty) continue;
        final absolute = base.resolve(href).toString();
        if (!NewsUriParser.isValidArticleUrl(absolute)) continue;
        final normalized = absolute.split('?').first;
        if (seen.add(normalized)) return normalized;
      }
    } catch (_) {}
    return null;
  }

  Future<BenchmarkResult> _fallbackBenchmark(
    YallaEngineService engineService,
  ) async {
    final memoryMb = await DeviceBenchmark.instance.measureMemoryMb();
    final cpuScore = await DeviceBenchmark.instance.measureCpuScore();
    final networkProfile = const NetworkProfile(
      connectionType: ConnectionType.none,
      isWifi: false,
      speedMbps: null,
      latencyMs: null,
    );
    final tier = DeviceBenchmark.instance.classifyTier(
      memoryMb,
      cpuScore,
      networkProfile,
    );
    final limits = DeviceBenchmark.instance.recommendLimits(
      tier,
      networkProfile,
    );
    return BenchmarkResult(
      memoryMb: memoryMb,
      cpuScore: cpuScore,
      networkProfile: networkProfile,
      tier: tier,
      limits: limits,
      measuredAt: DateTime.now(),
    );
  }

  BenchmarkResult _safeStartupBenchmark() {
    return BenchmarkResult(
      memoryMb: 0,
      cpuScore: 0,
      networkProfile: const NetworkProfile(
        connectionType: ConnectionType.none,
        isWifi: false,
      ),
      tier: DeviceTier.medium,
      limits: const CrawlLimits(
        sourcesToCrawl: 5,
        urlsPerSource: 3,
        perSourceLimit: 3,
        pauseBetweenArticles: Duration(milliseconds: 800),
        pauseBetweenSources: Duration(milliseconds: 1000),
        maxConcurrentRequests: 1,
        batchSize: 2,
      ),
      measuredAt: DateTime.now(),
    );
  }

  Future<BenchmarkResult> _runCrawlBenchmark(
    YallaEngineService engineService,
    NewsSource source,
    String articleUrl,
  ) async {
    final benchmark = DeviceBenchmark.instance;
    final existing = benchmark.hasValidBenchmark ? benchmark.lastResult : null;
    if (existing != null) {
      return existing;
    }

    engineService.addLog(
      '[BENCHMARK] Running single-article benchmark on ${source.name}...',
    );
    final sw = Stopwatch()..start();
    Map<String, dynamic>? result;
    try {
      result = await _processArticleUrl(
        articleUrl,
        sourceLanguage: source.language,
        sourceName: source.name,
      );
    } catch (_) {
      result = null;
    }
    sw.stop();
    final processMs = sw.elapsedMilliseconds;

    final memoryMb = await benchmark.measureMemoryMb();
    final cpuScore = await benchmark.measureCpuScore();
    final networkProfile = await benchmark.measureNetworkProfile(
      engineService,
      articleUrl,
    );

    final tier = benchmark.classifyTier(memoryMb, cpuScore, networkProfile);
    final limits = benchmark.recommendLimits(tier, networkProfile);

    final success = result != null && result['success'] == true;
    engineService.addLog(
      '[BENCHMARK] Single-article benchmark finished: success=$success '
      'processMs=$processMs mem=${memoryMb}MB cpu=$cpuScore tier=$tier',
    );

    return BenchmarkResult(
      memoryMb: memoryMb,
      cpuScore: cpuScore,
      networkProfile: networkProfile,
      tier: tier,
      limits: limits,
      measuredAt: DateTime.now(),
    );
  }
}

// ─── Adaptive Crawler Scheduler ──────────────────────────────────────────────

class CrawlerScheduler {
  CrawlerScheduler._();
  static final CrawlerScheduler instance = CrawlerScheduler._();

  Timer? _timer;
  Timer? _initialCrawlTimer;
  DateTime? _lastRun;
  int _generation = 0;

  static Duration intervalForTier(DeviceTier tier) {
    final base = switch (tier) {
      DeviceTier.high => const Duration(minutes: 15),
      DeviceTier.medium => const Duration(minutes: 30),
      DeviceTier.low => const Duration(minutes: 60),
    };
    // Add random jitter (±25%) so crawls don't run at fixed times across devices.
    final jitter = base.inMilliseconds * 0.25;
    final randomDelay = (Random().nextDouble() * jitter * 2 - jitter).toInt();
    return Duration(milliseconds: base.inMilliseconds + randomDelay);
  }

  Future<DeviceTier> _detectTier(YallaEngineService engineService) async {
    final benchmark = DeviceBenchmark.instance;
    if (benchmark.hasValidBenchmark) {
      return benchmark.lastResult!.tier;
    }

    final memoryMb = await benchmark.measureMemoryMb();
    final cpuScore = await benchmark.measureCpuScore();
    final networkProfile = await benchmark.measureNetworkProfile(
      engineService,
      null,
    );

    final tier = benchmark.classifyTier(memoryMb, cpuScore, networkProfile);
    engineService.addLog(
      '[SCHEDULER] Detected device tier=$tier mem=${memoryMb}MB cpu=$cpuScore',
    );
    return tier;
  }

  Future<void> start({
    required YallaEngineService engineService,
    VoidCallback? onProgress,
    VoidCallback? onComplete,
    bool requireWifi = false,
  }) async {
    stop();
    final generation = _generation;

    final tier = await _detectTier(engineService);
    if (generation != _generation) return;
    final interval = intervalForTier(tier);
    final limits = DeviceBenchmark.instance.recommendLimits(
      tier,
      const NetworkProfile(connectionType: ConnectionType.none, isWifi: false),
    );

    engineService.addLog(
      '[SCHEDULER] Starting adaptive crawl interval=${interval.inMinutes}min tier=$tier',
    );

    _timer = Timer.periodic(interval, (_) async {
      if (generation != _generation) return;
      if (BackgroundCrawlerService.instance.isRunning) {
        return;
      }

      // Only crawl when WiFi is available, on all devices.
      final isWifi = await ConnectivityService.isWifi();
      if (generation != _generation) return;
      if (!isWifi) {
        engineService.addLog('[SCHEDULER] No WiFi — skipping scheduled crawl.');
        return;
      }

      final db = NewsDatabase.instance;
      final lastCrawl = await db.getLastCrawlTime('__global__');
      if (generation != _generation) return;
      if (lastCrawl != null &&
          DateTime.now().difference(lastCrawl) < interval) {
        return;
      }

      BackgroundCrawlerService.instance.startSilentCrawl(
        engineService: engineService,
        onProgress: onProgress,
        onComplete: onComplete,
        requireWifi: true,
      );
      _lastRun = DateTime.now();
    });

    // Run an initial crawl after a random delay if WiFi is connected,
    // on all devices. Never start without WiFi.
    if (!BackgroundCrawlerService.instance.isRunning) {
      final isWifi = await ConnectivityService.isWifi();
      if (isWifi) {
        final randomSeconds = 5 + Random().nextInt(20); // 5-25 seconds
        engineService.addLog(
          '[SCHEDULER] WiFi detected — scheduling first crawl in ${randomSeconds}s',
        );
        _initialCrawlTimer = Timer(Duration(seconds: randomSeconds), () async {
          if (generation == _generation &&
              !BackgroundCrawlerService.instance.isRunning) {
            await BackgroundCrawlerService.instance.startSilentCrawl(
              engineService: engineService,
              onProgress: onProgress,
              onComplete: onComplete,
              requireWifi: true,
            );
            _lastRun = DateTime.now();
          }
        });
      } else {
        engineService.addLog(
          '[SCHEDULER] No WiFi — skipping initial crawl, will retry on next interval.',
        );
      }
    }
  }

  Future<void> stop() async {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _initialCrawlTimer?.cancel();
    _initialCrawlTimer = null;
  }

  DateTime? get lastRun => _lastRun;
}
