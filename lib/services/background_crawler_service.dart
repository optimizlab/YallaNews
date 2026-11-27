import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;

import '../database/news_db.dart';
import '../models/news_model.dart';
import '../models/news_source.dart';
import 'candidate_queue.dart';
import 'freshness_engine.dart';
import 'memory_optimizer.dart';
import 'publication_date_extractor.dart';
import 'source_discovery.dart';
import 'source_scheduler.dart';
import 'web_view_crawler_service.dart';
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
import 'real_news_validator.dart';
import 'image_validator_service.dart';

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

    debugPrint(
      '[CRAWLER ISOLATE] HTTP ${response.statusCode} (${response.body.length} chars) URI=$sourceUrl',
    );

    if (response.statusCode != 200) {
      debugPrint(
        '[CRAWLER ISOLATE] HTTP ${response.statusCode} source=$sourceUrl',
      );
      final feedArticles = await _discoverRssArticles(sourceUrl, maxUrls);
      if (feedArticles.isNotEmpty) {
        debugPrint(
          '[CRAWLER ISOLATE] RSS fallback found ${feedArticles.length} articles for $sourceUrl',
        );
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
        final absolute = linkUri.host.isEmpty ? baseUri.resolve(href) : linkUri;
        if (absolute.host != baseUri.host) continue;
        final path = absolute.path;
        if (path.length < 10 ||
            path.contains('/wp-') ||
            path.contains('/tag/') ||
            path.contains('/category/'))
          continue;

        final lowerPath = path.toLowerCase();
        if (lowerPath.contains('/section/')) continue;

        final segments = absolute.pathSegments
            .where((s) => s.isNotEmpty)
            .toList();
        if (segments.length < 1) continue;
        final lastSegment = segments.last.toLowerCase();
        if (lastSegment.length < 5 && !RegExp(r'^\d+$').hasMatch(lastSegment))
          continue;

        final normalized = absolute.toString();
        if (!NewsUriParser.isValidArticleUrl(normalized)) continue;
        if (!articleUrls.add(normalized)) continue;

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
      if (limited.isEmpty) {
        limited = await _discoverRssArticles(sourceUrl, maxUrls);
      }
      debugPrint(
        '[CRAWLER ISOLATE] source=$sourceUrl links=${candidates.length} selected=${limited.length}',
      );
      return {'success': true, 'is_source': true, 'articles': limited};
    }

    // Single article extraction — now WITH publication date.
    final extracted = await _extractArticleFromHtml(
      html,
      sourceUrl,
      sourceLanguage,
    );
    extracted['response_length'] = html.length;
    extracted['status_code'] = response.statusCode;
    return extracted;
  } catch (e) {
    debugPrint('[CRAWLER ISOLATE] Exception extracting $sourceUrl: $e');
    return {'success': false, 'url': sourceUrl, 'reason': e.toString()};
  }
}

/// Extract a single article from HTML, including publication date.
Future<Map<String, dynamic>> _extractArticleFromHtml(
    String html, String pageUrl, String sourceLanguage) async {
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
      'url': pageUrl,
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
  final sourceName = '';
  final cleanedTitle = _cleanTitleIsolate(
    decodedTitle,
    pageUrl,
    sourceName.isEmpty ? null : <String>[sourceName],
  );
  final decodedSummary = _stripHtmlTags(_decodeHtmlIsolate(effectiveSummary));

  // ── Publication date extraction ──
  final dateExtractor = PublicationDateExtractor();
  final pubDate = dateExtractor.extractFromArticleHtml(html, baseUri: Uri.parse(pageUrl));
  final publishedAt = pubDate.isoUtc;
  final updatedAt = pubDate.source.contains('modified') ? publishedAt : '';

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

  // newsBrain image catching rules:
  // 1. Social schema image of post if exists -> correct image
  // 2. In-page image with alt/title matching news title in context -> valid
  // 3. Else search for the main news image in randomized famous search engines
  String? articleImage = await ImageValidatorService.catchNewsImage(
    html: html,
    title: cleanedTitle,
    pageUrl: pageUrl,
  );
  if (MsnImageFetcher.isPlaceholderOrEmpty(articleImage)) {
    articleImage = null;
  }

  // Enrich story paragraphs with web-searched images relevant to each paragraph.
  final Map<int, String> paragraphImages = {};
  if (paragraphs.length >= 2) {
    final usedUrls = <String>{
      if (articleImage != null && articleImage.isNotEmpty) articleImage,
    };
    final slotIndices = <int>{
      (paragraphs.length ~/ 3).clamp(0, paragraphs.length - 1),
      if (paragraphs.length >= 5)
        ((paragraphs.length * 2) ~/ 3).clamp(0, paragraphs.length - 1),
    }.toList()
      ..sort();

    for (final slotIdx in slotIndices) {
      try {
        final img = await MsnImageFetcher.fetchRandomImageForParagraph(
          paragraphs[slotIdx],
          fallbackTitle: cleanedTitle,
          excludeUrls: usedUrls,
        ).timeout(const Duration(seconds: 4));
        if (img != null && img.isNotEmpty) {
          paragraphImages[slotIdx] = img;
          usedUrls.add(img);
        }
      } catch (_) {}
    }
  }

  String decodedContent;
  if (paragraphImages.isNotEmpty) {
    const imgStyle =
        'width:100%;max-height:380px;object-fit:cover;border-radius:12px;margin:16px 0;display:block;';
    final buf = StringBuffer();
    for (int i = 0; i < paragraphs.length; i++) {
      if (i > 0) buf.write('\n\n');
      buf.write(paragraphs[i]);
      final inlineImg = paragraphImages[i];
      if (inlineImg != null) {
        buf.write('\n\n<img src="$inlineImg" style="$imgStyle" />');
      }
    }
    decodedContent = buf.toString();
  } else {
    decodedContent = injectSingleImage(paragraphs, articleImage);
  }
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
  final formattedContent = _cleanFormattedContentIsolate(
    formatted['content']!.isEmpty ? decodedContent : formatted['content']!,
  );
  final classificationText = '$formattedTitle $formattedSummary';
  final detectedCategory = await NewsIntelligence.classifyCategory(
    classificationText,
    url: pageUrl,
    title: cleanedTitle,
  );

  return {
    'success': true,
    'is_source': false,
    'url': pageUrl,
    'title': formattedTitle,
    'summary': formattedSummary,
    'content': formattedContent,
    'category': detectedCategory,
    'language': sourceLanguage,
    'image_url': articleImage ?? '',
    'publishDate': publishedAt,
    'published_at': publishedAt,
    'updated_at': updatedAt,
    'date_source': pubDate.source,
    'date_confidence': pubDate.confidence,
    'status': 'published',
  };
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
  int _totalArticlesEmitted = 0;

  Isolate? _crawlerIsolate;
  ReceivePort? _receivePort;
  SendPort? _crawlerSendPort;

  final Map<int, Completer<Map<String, dynamic>?>> _pendingRequests = {};
  final Set<int> _abandonedRequestIds = <int>{};
  int _nextRequestId = 0;
  StreamSubscription<dynamic>? _receiveSubscription;

  Timer? _memoryWatchdog;
  static const int _memoryWarningThresholdMb = 500;
  static const int _memoryCriticalThresholdMb = 900;

  final FreshnessEngine _freshnessEngine = FreshnessEngine();
  final CandidateQueue _candidateQueue = CandidateQueue();
  final RealNewsValidator _realNewsValidator = RealNewsValidator();
  final SourceScheduler _sourceScheduler = SourceScheduler.instance;

  StreamSubscription? _connectivitySubscription;
  Future<void>? _activeCrawl;
  BuildContext? _webViewContext;

  final _articleStreamController = StreamController<NewsModel>.broadcast();
  Stream<NewsModel> get articleStream => _articleStreamController.stream;

  final _stateStreamController = StreamController<CrawlerState>.broadcast();
  Stream<CrawlerState> get stateStream => _stateStreamController.stream;

  final List<NewsModel> _pendingServerPushes = <NewsModel>[];
  bool _isFlushingServerPushes = false;

  void _enqueueServerPush(NewsModel article, YallaEngineService engineService) {
    if (_pendingServerPushes.any((a) => a.url == article.url)) return;
    _pendingServerPushes.add(article);
    if (!_isFlushingServerPushes) {
      // Fire-and-forget flush so article extraction isn't blocked by network latency.
      unawaited(_flushServerPushQueue(engineService));
    }
  }

  Future<void> _flushServerPushQueue(YallaEngineService engineService) async {
    if (_isFlushingServerPushes) return;
    _isFlushingServerPushes = true;
    try {
      while (_pendingServerPushes.isNotEmpty) {
        final article = _pendingServerPushes.removeAt(0);
        bool pushed = false;
        for (int attempt = 1; attempt <= 2; attempt++) {
          try {
            await ServerApiService.saveArticle(article)
                .timeout(const Duration(seconds: 12));
            debugPrint('[SERVER-PUSH] OK: ${article.url}');
            engineService.addLog(
              '[SERVER-PUSH] Active URI: ${article.url} | State: PUSHED TO SERVER | Title: "${article.title}" | Summary: "${article.summary}" | Category: ${article.category}',
            );
            pushed = true;
            break;
          } catch (e) {
            debugPrint('[SERVER-PUSH] ERR (attempt $attempt): ${article.url} -> $e');
            if (attempt < 2) {
              await Future.delayed(Duration(seconds: attempt * 2));
            } else {
              engineService.addLog(
                '[SERVER-PUSH] Active URI: ${article.url} | State: PUSH FAILED ($e)',
              );
            }
          }
        }
        if (!pushed) {
          // Keep going with the rest of the queue.
        }
      }
    } finally {
      _isFlushingServerPushes = false;
    }
  }

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
    BuildContext? context,
    VoidCallback? onProgress,
    VoidCallback? onComplete,
    bool requireWifi = false,
  }) {
    if (context != null) {
      _webViewContext = context;
    }
    if (_isRunning) {
      onComplete?.call();
      return _activeCrawl ?? Future<void>.value();
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
    _isRunning = true;
    _totalArticlesEmitted = 0;
    debugPrint(
      '[SILENT CRAWLER] start requested requireWifi=$requireWifi running=$_isRunning',
    );

    // Clear duplicate tracking for this crawl run.
    _realNewsValidator.clearDuplicates();

    // Never Wi-Fi gated: crawl on any connection.
    if (requireWifi) {
      final isWifi = await ConnectivityService.isWifi();
      if (generation != _crawlGeneration) return;
      if (!isWifi) {
        engineService.addLog(
          '[SILENT CRAWLER] Not on Wi-Fi — crawling on available connection instead.',
        );
        // Do NOT return; continue on mobile data.
      }
    }

    // Never crawl without an active internet connection.
    final hasInternet = await ConnectivityService.hasInternet();
    if (generation != _crawlGeneration) return;
    if (!hasInternet) {
      engineService.addLog(
        '[SILENT CRAWLER] No internet connection — skipping crawl.',
      );
      onComplete?.call();
      return;
    }

    final smallMemory = _isSmallMemoryPlatform();
    final throttle = smallMemory
        ? max(3, await _topSourcesCount)
        : await _topSourcesCount;
    if (generation != _crawlGeneration) return;

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

      // Register per-source schedules so each source is crawled on its own cadence.
      _registerSourceSchedules(db, appLanguage, appCountry);

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
      final sourcesToUse = matchedSources;
      final selected = throttle < sourcesToUse.length
          ? sourcesToUse.take(throttle).toList()
          : List<NewsSource>.from(sourcesToUse);

      if (selected.isEmpty) {
        debugPrint('[SILENT CRAWLER] no sources available');
        engineService.addLog('[SILENT CRAWLER] No sources available.');
        _isRunning = false;
        onComplete?.call();
        return;
      }

      BenchmarkResult benchmarkProfile;
      try {
        benchmarkProfile = DeviceBenchmark.instance.hasValidBenchmark
            ? DeviceBenchmark.instance.lastResult!
            : await _fallbackBenchmark(engineService);
      } catch (e) {
        engineService.addLog('[BENCHMARK] Benchmark failed: $e');
        benchmarkProfile = _safeStartupBenchmark();
      }

      final limits = benchmarkProfile.limits;
      final maxUrls = max(10, limits.urlsPerSource);
      final perSourceLimit = max(5, limits.perSourceLimit);
      final pauseBetweenArticles = limits.pauseBetweenArticles;
      final pauseBetweenSources = limits.pauseBetweenSources;

      engineService.addLog(
        '[BENCHMARK] Complete: tier=${benchmarkProfile.tier} '
        'mem=${benchmarkProfile.memoryMb}MB cpu=${benchmarkProfile.cpuScore} '
        'sources=${limits.sourcesToCrawl} articlesPerSource=${limits.urlsPerSource} '
        'pause=${limits.pauseBetweenArticles.inMilliseconds}ms',
      );

      if (selected.isEmpty) {
        engineService.addLog('[SILENT CRAWLER] No sources to crawl.');
        _isRunning = false;
        _stateStreamController.add(const CrawlerState(running: false));
        onComplete?.call();
        return;
      }

      // Order sources by oldest/never-crawled first so we always prioritize
      // sources that haven't been crawled recently.
      final lastCrawlMap = <String, DateTime?>{};
      for (final s in selected) {
        lastCrawlMap[s.url] = await db.getLastCrawlTime(s.url);
      }
      selected.sort((a, b) {
        final la = lastCrawlMap[a.url];
        final lb = lastCrawlMap[b.url];
        if (la == null && lb == null) return 0;
        if (la == null) return -1;
        if (lb == null) return 1;
        return la.compareTo(lb);
      });
      final sourcesLimit = max(3, limits.sourcesToCrawl);
      final limitedSources = selected
          .take(sourcesLimit)
          .toList();
      final sourceUris = limitedSources.map((s) => '${s.name} (${s.url})').join(', ');
      debugPrint(
        '[SILENT CRAWLER] queued=${limitedSources.length} maxUrls=$maxUrls activeUris=[$sourceUris]',
      );
      _stateStreamController.add(
        CrawlerState(running: true, totalSources: limitedSources.length),
      );
      engineService.addLog(
        '[SILENT CRAWLER] queued=${limitedSources.length} maxUrls=$maxUrls activeUris=[$sourceUris]',
      );

      for (int i = 0; i < limitedSources.length; i++) {
        if (!_isRunning) break;

        final source = limitedSources[i];
        debugPrint('[SILENT CRAWLER] [${i + 1}/${limitedSources.length}] Active Source: ${source.name} | Active URI: ${source.url}');

        // Per-source due check via scheduler (respects backoff).
        final sched = _sourceScheduler.getSchedule(source.url);
        if (sched != null && !sched.isDue) {
          engineService.addLog(
            '[SILENT CRAWLER] [${i + 1}/${limitedSources.length}] ${source.name} (${source.url}): not due yet, skipping.',
          );
          onProgress?.call();
          continue;
        }

        final last = await db.getLastCrawlTime(source.url);
        if (last != null && DateTime.now().difference(last).inSeconds < 90) {
          engineService.addLog(
            '[SILENT CRAWLER] [${i + 1}/${limitedSources.length}] ${source.name} (${source.url}): last crawled ${DateTime.now().difference(last).inSeconds}s ago, skipping.',
          );
          onProgress?.call();
          continue;
        }

        engineService.addLog(
          '[SILENT CRAWLER] [${i + 1}/${limitedSources.length}] Active Source: ${source.name} | URI: ${source.url}',
        );

        try {
          final crawlDeadline = DateTime.now()
              .add(const Duration(seconds: 45));
          debugPrint('[CRAWL] Starting _crawlSourceInBackground for ${source.url}');
          final quality = await _crawlSourceInBackground(
            source,
            engineService,
            maxUrls: maxUrls,
            perSourceLimit: perSourceLimit,
            pauseBetweenArticles: pauseBetweenArticles,
            deadline: crawlDeadline,
          ).timeout(const Duration(seconds: 55));
          debugPrint('[CRAWL] _crawlSourceInBackground done for ${source.url} quality=$quality');
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
          _sourceScheduler.markSuccess(source.url);
          engineService.addLog('[SILENT CRAWLER] √ ${source.name} done.');
        } catch (e) {
          _sourceScheduler.markError(source.url);
          engineService.addLog('[SILENT CRAWLER] X ${source.name} failed: $e');
        }

        await Future.delayed(pauseBetweenSources);
      }

      await _flushServerPushQueue(engineService);
      engineService.addLog('[SILENT CRAWLER] Background crawl complete! Total articles emitted: $_totalArticlesEmitted');
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

  /// Register per-source schedules for all known sources.
  void _registerSourceSchedules(
      NewsDatabase db, String appLanguage, String appCountry) {
    // Default per-publisher schedules (respectful rate limits).
    final defaults = <SourceSchedule>[
      SourceSchedule(
        sourceUrl: 'https://www.hespress.com',
        sourceName: 'Hespress',
        refreshInterval: const Duration(hours: 1),
        maxCandidatesPerRun: 50,
        maxDownloadsPerRun: 10,
        priority: 100,
        enabled: true,
      ),
      SourceSchedule(
        sourceUrl: 'https://www.almasryalyoum.com',
        sourceName: 'Al Masry Al Youm',
        refreshInterval: const Duration(hours: 1),
        maxCandidatesPerRun: 50,
        maxDownloadsPerRun: 10,
        priority: 90,
        enabled: true,
      ),
      SourceSchedule(
        sourceUrl: 'https://www.mosaiquefm.net',
        sourceName: 'Mosaique FM',
        refreshInterval: const Duration(hours: 2),
        maxCandidatesPerRun: 30,
        maxDownloadsPerRun: 8,
        priority: 80,
        enabled: true,
      ),
      SourceSchedule(
        sourceUrl: 'https://www.lemonde.fr',
        sourceName: 'Le Monde',
        refreshInterval: const Duration(hours: 1),
        maxCandidatesPerRun: 50,
        maxDownloadsPerRun: 10,
        priority: 95,
        enabled: true,
      ),
      SourceSchedule(
        sourceUrl: 'https://www.reuters.com',
        sourceName: 'Reuters',
        refreshInterval: const Duration(hours: 1),
        maxCandidatesPerRun: 50,
        maxDownloadsPerRun: 10,
        priority: 90,
        enabled: true,
      ),
      SourceSchedule(
        sourceUrl: 'https://www.aljazeera.net',
        sourceName: 'Al Jazeera',
        refreshInterval: const Duration(hours: 1),
        maxCandidatesPerRun: 50,
        maxDownloadsPerRun: 10,
        priority: 95,
        enabled: true,
      ),
    ];
    _sourceScheduler.registerAll(defaults);
  }

  Future<void> _startCrawlerIsolate(YallaEngineService engineService) async {
    final ReceivePort receivePort = ReceivePort();
    _receivePort = receivePort;

    final readyCompleter = Completer<void>();
    final readyTimeout = Future.delayed(const Duration(seconds: 5), () {
      readyCompleter.completeError(Exception('isolate ready timeout'));
    });

    _receiveSubscription = _receivePort!.listen((message) {
      final Map<String, dynamic> msg = message as Map<String, dynamic>;
      final String type = msg['type'] as String;
      if (type == 'ready') {
        _crawlerSendPort = msg['port'] as SendPort;
        if (!readyCompleter.isCompleted) readyCompleter.complete();
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

    _crawlerIsolate = await Isolate.spawn(_crawlerIsolateEntry, {
      'sendPort': receivePort.sendPort,
    });

    await Future.any([readyCompleter.future, readyTimeout]);
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
    _abandonedRequestIds.clear();
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
        ? 350
        : _memoryWarningThresholdMb;
    final criticalThreshold = _isSmallMemoryPlatform()
        ? 520
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
    if (_abandonedRequestIds.contains(requestId)) {
      _abandonedRequestIds.remove(requestId);
      return null;
    }
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
    debugPrint('[CRAWLER] Requesting article extraction: $url');

    try {
      final result = await completer.future.timeout(
        const Duration(seconds: 15),
      );
      debugPrint(
        '[CRAWLER] Article extraction result for $url: success=${result?['success']}',
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
      _abandonedRequestIds.remove(requestId);
    }
  }

  Future<double?> _crawlSourceInBackground(
    NewsSource source,
    YallaEngineService engineService, {
    required int maxUrls,
    required int perSourceLimit,
    required Duration pauseBetweenArticles,
    DateTime? deadline,
  }) async {
    debugPrint('[CRAWL-ENTER] _crawlSourceInBackground for ${source.url}, sendPort=${_crawlerSendPort != null}');
    engineService.addLog(
      '[CRAWL-ENTER] _crawlSourceInBackground for ${source.url} (sendPort=${_crawlerSendPort != null})',
    );
    if (_crawlerSendPort == null) return null;
    final db = NewsDatabase.instance;
    final crawlLanguage = _resolveCrawlerLanguage(
      source.language,
      AppSettings.instance.locale?.languageCode ?? 'ar',
    );

    // ── Discovery: RSS → sitemap → category → homepage → WebView ──
    final discovery = SourceDiscovery();
    final discovered = <DiscoveredUrl>[];
    try {
      discovered.addAll(await Future.any([
        discovery.discover(source.url, maxUrls: maxUrls, deadline: deadline),
        Future.delayed(const Duration(seconds: 20), () => <DiscoveredUrl>[]),
      ]).timeout(const Duration(seconds: 25)));
    } catch (e) {
      engineService.addLog('[DISCOVERY] Failed for ${source.url}: $e');
    }
    debugPrint('[DISCOVERY] ${source.url}: found ${discovered.length} URLs');
    engineService.addLog(
      '[DISCOVERY] Active URI: ${source.url} | Found ${discovered.length} URLs: ${discovered.take(3).map((d) => d.url).join(", ")}',
    );

    // WebView fallback for JS-heavy sites when discovery found nothing.
    if (discovered.isEmpty && _webViewContext != null) {
      engineService.addLog(
        '[WEBVIEW CRAWLER] No links via feeds/sitemap/homepage for ${source.url}, trying WebView...',
      );
      try {
        final webviewUrls = await WebViewCrawlerService.instance
            .extractArticleUrls(
              context: _webViewContext!,
              url: source.url,
              loadTimeout: const Duration(seconds: 20),
            )
            .timeout(const Duration(seconds: 25));
        for (final u in webviewUrls) {
          discovered.add(DiscoveredUrl(
            url: u,
            discoveryMethod: 'webview',
          ));
        }
        engineService.addLog(
          '[WEBVIEW CRAWLER] WebView discovered ${webviewUrls.length} links from ${source.url}',
        );
      } catch (e) {
        engineService.addLog(
          '[WEBVIEW CRAWLER] WebView failed for ${source.url}: $e',
        );
      }
    }

    if (discovered.isEmpty) {
      engineService.addLog(
        '[DISCOVERY] No article URLs found for ${source.url}, skipping source.',
      );
      return 0.0;
    }

    // Build candidates and enqueue with freshness hints.
    final candidates = <CrawlCandidate>[];
    for (final d in discovered) {
      final pub = d.dateHint;
      final freshness = pub != null && pub.utc != null
          ? _freshnessEngine.classify(
              NewsModel.empty(d.url).copyWith(publishedAt: pub.isoUtc))
          : FreshnessClass.unknownDate;
      candidates.add(CrawlCandidate(
        url: d.url,
        sourceId: source.url,
        sourceUrl: source.url,
        titleHint: d.titleHint,
        publishedAt: pub?.utc,
        updatedAt: pub?.utc,
        discoveryMethod: d.discoveryMethod,
        language: d.language ?? crawlLanguage,
        freshness: freshness,
        sourcePriority: 0,
      ));
    }

    // Deduplicate and enqueue (never enqueue the source URL itself).
    int queued = 0;
    final normalizedSourceUrl = source.url.trim().replaceAll(RegExp(r'/+$'), '');
    final seen = <String>{normalizedSourceUrl};
    for (final c in candidates) {
      final normalizedCandidateUrl = c.url.trim().replaceAll(RegExp(r'/+$'), '');
      if (normalizedCandidateUrl.isEmpty || seen.contains(normalizedCandidateUrl)) continue;
      seen.add(normalizedCandidateUrl);
      final db = NewsDatabase.instance;
      final already = await db.articleUrlExists(c.url);
      if (already) continue;
      if (_candidateQueue.add(c)) queued++;
    }

    debugPrint('[CRAWL] ${source.url}: discovered=${discovered.length} queued=$queued');
    engineService.addLog(
      '[DISCOVERY] ${source.name}: ${discovered.length} found, $queued new candidates queued.',
    );

    if (queued == 0) {
      engineService.addLog(
        '[CRAWL PASS 1] No new candidates from ${source.url}',
      );
      return 0.0;
    }

    // Process queue.
    int successCount = 0;
    int failureCount = 0;
    final processed = <String>{};

    while (true) {
      if (!_isRunning) break;
      if (deadline != null && DateTime.now().isAfter(deadline)) {
        engineService.addLog(
          '[SILENT CRAWLER] deadline reached for ${source.url}, stopping.',
        );
        break;
      }
      final candidate = _candidateQueue.pop();
      if (candidate == null) break;
      if (processed.contains(candidate.url)) continue;
      processed.add(candidate.url);

      engineService.addLog(
        '[CRAWLER] Active URI: ${candidate.url} | State: processing | Queue remaining: ${_candidateQueue.length}',
      );

      final urlHash = NewsModel.hashUrl(candidate.url);
      final alreadyInDb = await db.articleUrlExists(candidate.url);
      if (alreadyInDb) {
        _candidateQueue.done(candidate, status: CrawlStatus.skipped);
        failureCount++;
        continue;
      }

      NewsModel? article;
      bool usedNewsBrain = false;
      if (!kIsWeb && NewsBrainService.instance.isAvailable) {
        try {
          final brainArticle = await NewsBrainService.instance
              .extractArticleUrl(candidate.url);
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
            '[NEWSBRAIN] Article failed validation, falling back to isolate parser for: ${candidate.url}',
          );
        }
        final result = await _processArticleUrl(
          candidate.url,
          sourceLanguage: crawlLanguage,
          sourceName: source.name,
        );
        final statusCode = result?['status_code'] ?? (result?['success'] == true ? 200 : 0);
        final respLen = result?['response_length'] ?? 0;
        final resTitle = result?['title'] ?? '';
        final resSummary = result?['summary'] ?? '';
        final contentLen = (result?['content'] as String?)?.length ?? 0;
        final shortSummary = resSummary.length > 60 ? '${resSummary.substring(0, 60)}...' : resSummary;
        engineService.addLog(
          '[CRAWLER] Active URI: ${candidate.url} | HTTP $statusCode ($respLen chars) | Title: "$resTitle" | Summary: "$shortSummary" | Content: $contentLen chars | Success: ${result?['success']}',
        );
        if (result == null ||
            result['success'] != true ||
            result['is_source'] == true) {
          failureCount++;
          _candidateQueue.retry(candidate, error: result?['reason'] ?? 'unknown');
          engineService.addLog(
            '[CRAWL PASS 2] Failed to extract ${candidate.url}: ${result?['reason'] ?? 'unknown error'}',
          );
          continue;
        }
        article = NewsModel.fromJson(result, candidate.url);
      }

      var currentArticle = article.copyWith(
        sourceName: article.sourceName.isEmpty ? source.name : article.sourceName,
        sourceUrl: article.sourceUrl.isEmpty ? source.url : article.sourceUrl,
        language: article.language.isEmpty
            ? crawlLanguage
            : _resolveCrawlerLanguage(article.language, crawlLanguage),
      );

      // Override published_at from discovery hint if the parser didn't find one.
      if ((currentArticle.publishedAt.isEmpty ||
              currentArticle.publishDate.isEmpty) &&
          candidate.publishedAt != null) {
        final iso = candidate.publishedAt!.toUtc().toIso8601String();
        currentArticle = currentArticle.copyWith(
          publishedAt: iso,
          publishDate: iso,
          updatedAt: candidate.updatedAt?.toUtc().toIso8601String() ?? '',
        );
      }

      final validCategoryIds = CategoryService.instance.categoryIds;
      final classifiedCategory = await NewsIntelligence.classifyCategory(
        '${currentArticle.title} ${currentArticle.summary}',
        url: currentArticle.url,
        title: currentArticle.title,
        validCategoryIds: validCategoryIds.isEmpty ? null : validCategoryIds,
      );
      currentArticle = currentArticle.copyWith(
        category: classifiedCategory,
      );

      if (MsnImageFetcher.isPlaceholderOrEmpty(currentArticle.imageUrl)) {
        String? searchImg;
        try {
          searchImg = await MsnImageFetcher.fetchRandomImage(
            currentArticle.title,
          ).timeout(const Duration(seconds: 8));
        } catch (_) {}
        if (searchImg != null &&
            searchImg.isNotEmpty &&
            !MsnImageFetcher.isPlaceholderOrEmpty(searchImg)) {
          currentArticle = currentArticle.copyWith(imageUrl: searchImg);
        } else {
          currentArticle = currentArticle.copyWith(
            imageUrl: NewsModel.getFallbackImage(currentArticle.category),
          );
        }
      }

      if (!_isValidCrawledNews(currentArticle)) {
        debugPrint('[CRAWL-REJECT] invalid: ${candidate.url} title="${currentArticle.title}" contentLen=${currentArticle.content.length}');
        engineService.addLog('[VALIDATION] Skipped invalid article: ${candidate.url}');
        failureCount++;
        _candidateQueue.done(candidate, status: CrawlStatus.skipped);
        continue;
      }

      // RealNewsValidator: strict title/URL/content/quality validation.
      final realNewsResult = _realNewsValidator.validate(currentArticle);
      if (!realNewsResult.valid) {
        debugPrint('[CRAWL-REJECT] realNews: ${candidate.url} reason=${realNewsResult.reason}');
        engineService.addLog(
          '[REAL NEWS] Rejected ${candidate.url}: ${realNewsResult.reason}',
        );
        failureCount++;
        _candidateQueue.done(candidate, status: CrawlStatus.skipped);
        continue;
      }

      if (hasNativeEngine) {
        final qualityScore = scoreArticleQuality(
          currentArticle.title,
          currentArticle.content,
          currentArticle.summary,
        );
        if (qualityScore > 0.0 && qualityScore < 0.35) {
          debugPrint('[CRAWL-REJECT] quality=${qualityScore.toStringAsFixed(2)}: ${candidate.url}');
          engineService.addLog(
            '[QUALITY GATE] Rejected low-score page (${qualityScore.toStringAsFixed(2)}): ${candidate.url}',
          );
          failureCount++;
          _candidateQueue.done(candidate, status: CrawlStatus.skipped);
          continue;
        }
      }

      // Annotate with freshness class.
      final annotated = _freshnessEngine.annotate(currentArticle);
      // Emit + publish.
      final absImage = NewsModel.resolveImageUrl(
        annotated.imageUrl,
        annotated.url,
      );
      final toPublish = annotated.copyWith(
        imageUrl: absImage.isEmpty
            ? NewsModel.getFallbackImage(annotated.category)
            : absImage,
      );
      _emitArticle(toPublish);
      try {
          await NewsDatabase.instance.saveCrawledArticles([toPublish], source.url);
        } catch (e) {
          engineService.addLog(
            '[LOCAL] Save failed for ${toPublish.url}: $e',
          );
        }
        _enqueueServerPush(toPublish, engineService);

      successCount++;
      engineService.addLog(
        '[ARTICLE EXTRACTED] title="${currentArticle.title}" class="${currentArticle.category}" desc="${currentArticle.summary}" url="${candidate.url}" freshness=${_freshnessEngine.classify(currentArticle).label}',
      );
      _candidateQueue.done(candidate, status: CrawlStatus.extracted);

      if (successCount >= perSourceLimit) break;
      await Future.delayed(pauseBetweenArticles);
    }

    final quality = successCount / max(discovered.length, 1);
    engineService.addLog(
      '[CRAWL PASS 3] Complete. Success: $successCount, Failures: $failureCount, Quality: ${quality.toStringAsFixed(2)}, Queue remaining: ${_candidateQueue.length}.',
    );
    return quality;
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

    try {
      await NewsDatabase.instance.saveCrawledArticles([
        articleToPublish,
      ], articleToPublish.sourceUrl);
    } catch (e) {
      engineService.addLog(
        '[LOCAL] Save failed for ${articleToPublish.url}: $e',
      );
    }

    _enqueueServerPush(articleToPublish, engineService);
  }

  void _emitArticle(NewsModel article) {
    _totalArticlesEmitted++;
    debugPrint('[CRAWL DEBUG] Article #$_totalArticlesEmitted emitted: ${article.title} (${article.url})');
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
    BuildContext? context,
    VoidCallback? onProgress,
    VoidCallback? onComplete,
  }) async {
    if (context != null) {
      _webViewContext = context;
    }
    if (_isRunning) return;

    if (_isSmallMemoryPlatform()) {
      engineService.addLog(
        '[SILENT CRAWLER] Skipped: device is in small-memory mode.',
      );
      onComplete?.call();
      return;
    }

    // Clear duplicate tracking for this crawl run.
    _realNewsValidator.clearDuplicates();

    _isRunning = true;
    _totalArticlesEmitted = 0;
    _startMemoryWatchdog(engineService);
    engineService.addLog(
      '[SILENT CRAWLER] Force refresh started...',
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
      final sourcesToUse = matchedSources;
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
          _sourceScheduler.markSuccess(source.url);
        } catch (e) {
          _sourceScheduler.markError(source.url);
          engineService.addLog('[SILENT CRAWLER] X ${source.name} failed: $e');
        }
      }

      engineService.addLog('[SILENT CRAWLER] Force refresh complete! Total articles emitted: $_totalArticlesEmitted');
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
    final summary = article.summary.trim();

    if (title.isEmpty || url.isEmpty || url.length < 10) return false;
    if (content.isEmpty && summary.isEmpty) return false;

    // Reject placeholder / noise titles
    if (title.length < 5 || title.length > 200) return false;
    if (RegExp(r'^\s*[\.\-_,:;!?…]{2,}\s*$').hasMatch(title)) return false;
    final tl = title.toLowerCase();
    if (tl == 'test' || tl == 'news') return false;

    // Reject mixed-script titles (Arabic + Chinese etc.) — scraping artifacts
    bool hasArabic = title.contains(RegExp(r'[\u0600-\u06FF]'));
    bool hasCjk = title.contains(RegExp(r'[\u4E00-\u9FFF\u3400-\u4DBF]'));
    bool hasCyrillic = title.contains(RegExp(r'[\u0400-\u04FF]'));
    int scriptCount = (hasArabic ? 1 : 0) + (hasCjk ? 1 : 0) + (hasCyrillic ? 1 : 0);
    if (scriptCount > 1) return false;

    // Reject site-name-only titles
    const siteOnly = {
      'al jazeera','الجزيرة','bbc','cnn','reuters','le monde','hespress',
      'mosaique fm','almasryalyoum','google','facebook','twitter','instagram',
      'youtube','whatsapp','telegram'
    };
    if (siteOnly.contains(tl)) return false;

    // Content must have some real words, not just punctuation
    final textToCheck = (content.isNotEmpty ? content : summary);
    final wordCount = textToCheck.split(RegExp(r'\s+')).where((w) => w.length > 2).length;
    if (wordCount < 3) return false;

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
        urlsPerSource: 20,
        perSourceLimit: 12,
        pauseBetweenArticles: Duration(milliseconds: 500),
        pauseBetweenSources: Duration(milliseconds: 800),
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

// ─── Per-Source Scheduler ───────────────────────────────────────────────────

class CrawlerScheduler {
  CrawlerScheduler._();
  static final CrawlerScheduler instance = CrawlerScheduler._();

  Timer? _timer;
  Timer? _initialCrawlTimer;
  DateTime? _lastRun;
  int _generation = 0;

  static Duration intervalForTier(DeviceTier tier) {
    final base = switch (tier) {
      DeviceTier.high => const Duration(minutes: 5),
      DeviceTier.medium => const Duration(minutes: 10),
      DeviceTier.low => const Duration(minutes: 15),
    };
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
    BuildContext? context,
    VoidCallback? onProgress,
    VoidCallback? onComplete,
    bool requireWifi = false,
  }) async {
    if (context != null) {
      BackgroundCrawlerService.instance._webViewContext = context;
    }
    stop();
    final generation = _generation;

    final tier = await _detectTier(engineService);
    if (generation != _generation) return;
    final interval = intervalForTier(tier);

    engineService.addLog(
      '[SCHEDULER] Starting adaptive crawl interval=${interval.inMinutes}min tier=$tier',
    );

    _timer = Timer.periodic(interval, (_) async {
      if (generation != _generation) return;
      if (BackgroundCrawlerService.instance.isRunning) {
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
        context: context,
        onProgress: onProgress,
        onComplete: onComplete,
        requireWifi: true,
      );
      _lastRun = DateTime.now();
    });

    // Run an initial crawl after a random delay on all devices.
    if (!BackgroundCrawlerService.instance.isRunning) {
      final randomSeconds = 2 + Random().nextInt(4); // 2-5 seconds
      engineService.addLog(
        '[SCHEDULER] Scheduling first crawl in ${randomSeconds}s',
      );
      _initialCrawlTimer = Timer(Duration(seconds: randomSeconds), () async {
        if (generation == _generation &&
            !BackgroundCrawlerService.instance.isRunning) {
          await BackgroundCrawlerService.instance.startSilentCrawl(
            engineService: engineService,
            context: context,
            onProgress: onProgress,
            onComplete: onComplete,
            requireWifi: true,
          );
          _lastRun = DateTime.now();
        }
      });
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
