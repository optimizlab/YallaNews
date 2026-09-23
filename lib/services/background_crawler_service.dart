import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import '../database/news_db.dart';
import '../models/news_source.dart';
import '../models/news_model.dart';
import 'yalla_engine_service.dart';
import 'news_uri_parser.dart';
import 'news_intelligence.dart';
import 'app_settings.dart';
import 'arabic_normalizer.dart';
import 'server_api_service.dart';
import 'category_service.dart';
import 'image_validator_service.dart';
import 'knowledge_extraction_service.dart';
import 'connectivity_service.dart';
import 'content_ngram_scorer.dart';
import 'msn_image_fetcher.dart';

// ─── Background Isolate Helpers ────────────────────────────────────────────────

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
  text = text.replaceAll('&', '&');
  return text;
}

String _stripHtmlTags(String text) {
  if (text.isEmpty) return text;
  final withoutTags = text.replaceAll(RegExp(r'<[^>]*>'), '');
  return _decodeHtmlIsolate(withoutTags);
}

final _positiveWords = {
  'ممتاز', 'رائع', 'جيد', 'إيجابي', 'سعيد', 'فرح', 'حب', 'نجاح', 'ناجح',
  'انتصار', 'فوز', 'تطور', 'تقدم', 'إنجاز', 'أمل', 'سلام', 'أمان', 'استقرار',
  'احتفال', 'تكريم', 'جائزة', 'افتتاح', 'إطلاق', 'تعاون', 'شراكة', 'شراكات',
  'ازدهار', 'نمو', 'خير', 'بركة', 'مساعدة', 'دعم', 'توافق', 'اتفاق', 'اتفاقية',
  'حل', 'إصلاح', 'تحسين', 'ارتفاع', 'زيادة', 'قوي', 'قوة', 'نهضة', 'شكر',
  'ترحيب', 'إشادة', 'تتويج', 'تميز', 'تفوق', 'أفضل', 'مكسب', 'ارتقاء', 'بناء',
  'مذهل', 'جميل', 'مفيد', 'مثالي', 'تحدي', 'إبداعي', 'مميز', 'فريد',
  'سليم', 'صحي', 'آمن', 'مستقر', 'مطمئن', 'مشرق', 'واعد', 'منشود', 'مرغوب',
  'محبوب', 'مقبول', 'سهل', 'بسيط', 'ميسر', 'عظيم', 'كريم', 'مهم',
  'good', 'great', 'excellent', 'positive', 'happy', 'joy', 'love', 'like',
  'amazing', 'wonderful', 'best', 'better', 'fantastic', 'terrific',
  'outstanding', 'superb', 'nice', 'fine', 'perfect', 'brilliant',
  'awesome', 'cool', 'sweet', 'lovely', 'success', 'win', 'victory',
  'achieve', 'progress', 'improve', 'growth', 'benefit', 'hope', 'peace',
  'safe', 'secure', 'celebrate', 'honor', 'award', 'launch', 'new',
};

final _negativeWords = {
  'سيئ', 'فظيع', 'سلبي', 'حزين', 'كره', 'كارثة', 'فشل', 'فقر', 'مرض', 'أمراض',
  'خطأ', 'مشكلة', 'أزمة', 'أزمات', 'خراب', 'ضرر', 'أضرار', 'حادث', 'حوادث',
  'قتل', 'موت', 'وفاة', 'وفيات', 'مقتل', 'اغتيال', 'حرب', 'حروب', 'صراع',
  'هجوم', 'اعتداء', 'انهيار', 'خسارة', 'خسائر', 'خطر', 'مخاطر', 'تهديد',
  'عنف', 'جريمة', 'جرائم', 'فساد', 'فضيحة', 'فضائح', 'احتجاج', 'احتجاجات',
  'توتر', 'خوف', 'قلق', 'أذى', 'اعتقال', 'إدانة', 'إصابة', 'إصابات',
  'ضحية', 'ضحايا', 'إرهاب', 'إرهابي', 'تدمير', 'نزيف', 'معاناة', 'شكوى',
  'سيء', 'مؤسف', 'مخيف', 'خطير', 'اصابة', 'مصاب', 'دمار', 'تلوث',
  'وباء', 'كوارث', 'غش', 'تجاوز', 'انتهاك', 'قمع', 'ظلم', 'تعذيب',
  'مخيب', 'محبط', 'مرفوض', 'صعب', 'مستحيل', 'مشاكل',
  'bad', 'terrible', 'awful', 'negative', 'sad', 'unhappy', 'hate',
  'horrible', 'worst', 'worse', 'disaster', 'fail', 'failure', 'poor',
  'sick', 'ill', 'wrong', 'error', 'problem', 'issue', 'broken', 'damage',
  'crash', 'kill', 'die', 'dead', 'war', 'conflict', 'attack', 'bomb',
  'crisis', 'collapse', 'loss', 'danger', 'risk', 'threat', 'violence',
  'crime', 'corruption', 'scandal', 'protest', 'tension', 'fear',
};

double _calculateSentiment(String text) {
  if (text.isEmpty) return 0.0;
  final normalizedText = ArabicTextNormalizer.normalize(text).toLowerCase();
  int positiveCount = 0;
  int negativeCount = 0;
  final words = normalizedText.split(RegExp(r'\s+'));
  for (final word in words) {
    final w = word.replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '');
    if (w.isEmpty) continue;
    if (_positiveWords.contains(w)) positiveCount++;
    if (_negativeWords.contains(w)) negativeCount++;
  }
  final total = positiveCount + negativeCount;
  if (total == 0) return 0.0;
  return ((positiveCount - negativeCount) / total).clamp(-1.0, 1.0);
}

String _cleanTitleIsolate(String title, String url) {
  if (title.isEmpty) return title;
  String cleaned = title;
  final uri = Uri.tryParse(url);
  final domain = uri != null ? uri.host.toLowerCase() : '';
  final separators = [' - ', ' | ', ' :: ', ' — ', ' – ', ' : ', ' › ', ' « ', ' » '];
  for (final sep in separators) {
    if (cleaned.contains(sep)) {
      final parts = cleaned.split(sep);
      if (parts.length >= 2) {
        final lastPart = parts.last.trim();
        final words = lastPart.split(RegExp(r'\s+'));
        if (words.length <= 5 && !lastPart.contains('.') && !lastPart.contains('?')) {
          cleaned = parts.take(parts.length - 1).join(sep).trim();
        }
      }
      break;
    }
  }
  if (domain.isNotEmpty) {
    final domainParts = domain.split('.');
    final sourceName = domainParts.first;
    if (sourceName.length > 3 && cleaned.toLowerCase().endsWith(sourceName)) {
      final escaped = RegExp.escape(sourceName);
      final regex = RegExp('\\s*[-|:]?\\s*$escaped\\s*\$', caseSensitive: false);
      cleaned = cleaned.replaceAll(regex, '').trim();
    }
  }
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
  cleaned = cleaned.replaceAll(RegExp(r'[-|:]\s*$'), '').trim();
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned;
}

Future<Map<String, dynamic>> _processArticleTask(Map<String, dynamic> task) async {
  final url = task['url'] as String;
  final validCategoryIds = task['validCategoryIds'] as List<String>?;
  final sourceLanguage = task['sourceLanguage'] as String? ?? '';

  try {
    final response = await http.get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(
      const Duration(seconds: 10),
    );

    if (response.statusCode != 200) {
      return {'success': false, 'url': url, 'reason': 'HTTP ${response.statusCode}'};
    }

    final html = response.body;
    final isSource = !NewsUriParser.isValidArticleUrl(url);

    if (isSource) {
      final document = parse(html);
      final baseUri = Uri.parse(url);
      final Set<String> articleUrls = {};
      
      // Collect all candidate article links with their context
      final List<Map<String, dynamic>> candidates = [];
      
      for (final element in document.querySelectorAll('a[href]')) {
        final href = element.attributes['href'];
        if (href == null || href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) continue;
        Uri linkUri;
        try {
          linkUri = Uri.parse(href);
        } catch (_) {
          continue;
        }
        if (linkUri.host.isEmpty && !href.startsWith('/')) continue;
        final absolute = linkUri.hasEmptyPath && linkUri.host.isEmpty
            ? Uri.parse(baseUri.origin).resolve(href)
            : linkUri;
        if (absolute.host != baseUri.host) continue;
        final path = absolute.path;
        if (path.length < 10 || path.contains('/wp-') || path.contains('/tag/') || path.contains('/category/')) continue;
        
        // Calculate relevance score for this link
        int score = 0;
        
        // 1. First-page links are more relevant (shallow paths score higher)
        final depth = path.split('/').where((s) => s.isNotEmpty).length;
        score += max(0, 10 - depth * 2);
        
        // 2. Links with social media tags in the target page are more relevant
        // We can't check target page without fetching, so we score based on link text
        final linkText = element.text.trim().toLowerCase();
        if (linkText.length > 20 && linkText.length < 200) {
          score += 5; // Descriptive link text
        }
        if (linkText.contains('news') || linkText.contains('article') || linkText.contains('report')) {
          score += 3;
        }
        
        // 3. Clean URL patterns score higher
        if (path.contains('/202') && path.contains('/')) {
          score += 5; // Date-based URLs are usually articles
        }
        if (path.contains('-') && !path.contains('?')) {
          score += 2; // Clean URLs without query strings
        }
        
        // 4. Links with more words in the path are usually more descriptive
        final pathWords = path.split('/').last.split('-').length;
        score += min(pathWords, 5);
        
        candidates.add({
          'url': absolute.toString(),
          'score': score,
        });
      }
      
      // Sort by score descending (higher score = more relevant)
      candidates.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
      
      // Take top candidates
      final limited = candidates.take(50).map((c) => c['url'] as String).toList();
      return {'success': true, 'is_source': true, 'articles': limited};
    }

    final titleMatch = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false).firstMatch(html);
    final title = titleMatch != null ? titleMatch.group(1)! : 'Untitled';

    final descMatch = RegExp("""<meta[^>]+name=["']description["'][^>]+content=["']([^"']*)["'][^>]*>""", caseSensitive: false).firstMatch(html);
    final summary = descMatch != null ? descMatch.group(1)! : '';

    final ogDescMatch = RegExp("""<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']*)["'][^>]*>""", caseSensitive: false).firstMatch(html);
    final ogDescription = ogDescMatch != null ? ogDescMatch.group(1)! : '';
    final effectiveSummary = summary.length > ogDescription.length ? summary : ogDescription;

    final ogTitleMatch = RegExp("""<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']*)["'][^>]*>""", caseSensitive: false).firstMatch(html);
    final twitterTitleMatch = RegExp("""<meta[^>]+name=["']twitter:title["'][^>]+content=["']([^"']*)["'][^>]*>""", caseSensitive: false).firstMatch(html);
    final metaTitle = ogTitleMatch != null ? ogTitleMatch.group(1)! : (twitterTitleMatch != null ? twitterTitleMatch.group(1)! : '');

    final twitterDescMatch = RegExp("""<meta[^>]+name=["']twitter:description["'][^>]+content=["']([^"']*)["'][^>]*>""", caseSensitive: false).firstMatch(html);
    final twitterDescription = twitterDescMatch != null ? twitterDescMatch.group(1)! : '';

    final hasValidMetaTitle = metaTitle.isNotEmpty && metaTitle.length >= 3;
    final hasValidSummary = effectiveSummary.isNotEmpty && effectiveSummary.length >= 10;
    final hasValidTwitter = twitterTitleMatch != null || twitterDescMatch != null;

    if (!hasValidMetaTitle && !hasValidSummary && !hasValidTwitter) {
      return {'success': false, 'url': url, 'reason': 'No valid meta/social tags found'};
    }

    String content = html.replaceAll(RegExp(r'<script\b[^>]*>.*?</script>', dotAll: true, caseSensitive: false), '');
    content = content.replaceAll(RegExp(r'<style\b[^>]*>.*?</style>', dotAll: true, caseSensitive: false), '');

    final contentPatterns = [
      "<article[^>]*>(.*?)</article>",
      "<main[^>]*>(.*?)</main>",
      "<div[^>]+class=[\"'][^\"']*(?:article|content|post|entry)[^\"']*[\"'][^>]*>(.*?)</div>",
      "<div[^>]+id=[\"'][^\"']*(?:article|content|post|entry)[^\"']*[\"'][^>]*>(.*?)</div>",
    ];

    String extractedContent = '';
    for (final pattern in contentPatterns) {
      final match = RegExp(pattern, dotAll: true, caseSensitive: false).firstMatch(content);
      if (match != null && match.group(1) != null) {
        extractedContent = match.group(1)!;
        break;
      }
    }

    if (extractedContent.isEmpty) {
      final bodyMatch = RegExp(r'<body[^>]*>(.*?)</body>', dotAll: true, caseSensitive: false).firstMatch(html);
      extractedContent = bodyMatch != null ? bodyMatch.group(1)! : '';
    }

    extractedContent = extractedContent.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    final decodedTitle = _decodeHtmlIsolate(metaTitle.isNotEmpty ? metaTitle : title);
    final cleanedTitle = _cleanTitleIsolate(decodedTitle, url);
    final decodedSummary = _stripHtmlTags(_decodeHtmlIsolate(effectiveSummary));

    // ── N-gram paragraph scorer (TinyLLM-style) ─────────────────────────────
    // Score every paragraph in the raw HTML against title+description n-grams.
    // Only relevant paragraphs are kept, in original top-to-bottom page order.
    final ngramContent = ContentNgramScorer.buildRichContent(
      rawHtml: html,
      title: cleanedTitle,
      description: decodedSummary,
    );

    // Split the scored output back into paragraphs for image injection
    final paragraphs = ngramContent
        .split('\n\n')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    // ── Fetch ONE random MSN/Bing image (position 1–5, random each call) ────
    // Fetches up to 5 Bing results then picks one at random so every article
    // may show a different image even if the title is similar.
    String? msnImage;
    try {
      msnImage = await MsnImageFetcher.fetchRandomImage(cleanedTitle);
    } catch (_) {}

    // Build final rich HTML content: paragraphs wrapped in <p> tags,
    // with the single randomly-selected MSN image injected after paragraph 2.
    var decodedContent = injectSingleImage(paragraphs, msnImage);
    if (decodedContent.isEmpty) decodedContent = decodedSummary;

    // NOTE: removed LLM content rewriting to preserve real article content.
    // The app now uses extracted real content only.

    // Classification: use title+summary as signal (scorer cleaned body already)
    final classificationText = '$decodedTitle $decodedSummary';
    final detectedCategory = NewsIntelligence.classifyCategory(
      classificationText,
      url: url,
      validCategoryIds: validCategoryIds,
      titleOnly: cleanedTitle,
    );

    final sourceUri = Uri.tryParse(url);
    final sourceHost = sourceUri?.host.toLowerCase() ?? '';
    final bool sourceIsArabic = sourceLanguage.toLowerCase().contains('ar');

    if (sourceIsArabic) {
      final arabicPattern = RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]');
      final hasArabic = arabicPattern.hasMatch(classificationText);
      if (!hasArabic) {
        return {
          'success': false,
          'reason': 'non_arabic_content',
          'url': url,
        };
      }
    }

    final ogImageMatch = RegExp("""<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']*)["'][^>]*>""", caseSensitive: false).firstMatch(html);
    final twitterImageMatch = RegExp("""<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']*)["'][^>]*>""", caseSensitive: false).firstMatch(html);
    final metaImageUrl = ogImageMatch != null ? ogImageMatch.group(1)! : (twitterImageMatch != null ? twitterImageMatch.group(1)! : '');

    final imgRegex = RegExp(r'<img[^>]*src="[^"]*"[^>]*>', caseSensitive: false);
    final allImgMatches = imgRegex.allMatches(html).map((m) {
      final srcMatch = RegExp(r'src="([^"]*)"').firstMatch(m.group(0)!);
      return srcMatch?.group(1) ?? '';
    }).toList();

    String imageUrl = '';
    final List<String> extraImageUrls = [];
    final baseUri = Uri.tryParse(url);

    if (metaImageUrl.isNotEmpty) {
      final resolvedMeta = baseUri != null && !metaImageUrl.startsWith('http')
          ? baseUri.resolve(metaImageUrl).toString()
          : metaImageUrl;
      if (ImageValidatorService.isValidImageUrl(resolvedMeta)) {
        imageUrl = resolvedMeta;
      }
    }

    final filteredImgUrls = <String>[];
    for (final rawImg in allImgMatches) {
      final resolved = baseUri != null && !rawImg.startsWith('http')
          ? baseUri.resolve(rawImg).toString()
          : rawImg;
      if (ImageValidatorService.isValidImageUrl(resolved)) {
        filteredImgUrls.add(resolved);
      }
    }

    if (imageUrl.isEmpty && filteredImgUrls.isNotEmpty) {
      imageUrl = filteredImgUrls.first;
    }

    for (final img in filteredImgUrls) {
      if (img != imageUrl) {
        extraImageUrls.add(img);
      }
    }

    if (imageUrl.isEmpty) {
      final categorySlug = detectedCategory.toLowerCase();
      final seed = Uri.parse(url).path.hashCode.abs() % 1000;
      imageUrl = 'https://placehold.co/600x400/EEE/31343C?text=$categorySlug+$seed';
    }

    var enrichedContent = decodedContent;
    if (extraImageUrls.isNotEmpty && decodedContent.isNotEmpty) {
      enrichedContent = _injectImagesIntoContent(
        decodedContent,
        extraImageUrls,
        title: cleanedTitle,
        description: decodedSummary.length > 200 ? decodedSummary.substring(0, 200) : null,
        metaKeywords: YallaEngineService.extractKeywords(cleanedTitle, decodedContent, detectedCategory),
      );
    }

    final urlHash = baseUri != null ? '${baseUri.host}${baseUri.path}' : url;

    return {
      'success': true,
      'is_source': false,
      'url': url,
      'url_hash': urlHash,
      'title': cleanedTitle,
      'summary': decodedSummary.isEmpty ? 'Latest updates from this source.' : decodedSummary,
      'sentiment': _calculateSentiment('$cleanedTitle $decodedSummary'),
      'image_url': imageUrl,
      'category': detectedCategory,
      'author': '',
      'publishDate': DateTime.now().toIso8601String(),
      'content': enrichedContent,
      'meta_tags': {
        'og_title': ogTitleMatch != null ? ogTitleMatch.group(1)! : '',
        'twitter_title': twitterTitleMatch != null ? twitterTitleMatch.group(1)! : '',
        'og_description': ogDescription,
        'twitter_description': twitterDescription,
        'og_image': ogImageMatch != null ? ogImageMatch.group(1)! : '',
        'twitter_image': twitterImageMatch != null ? twitterImageMatch.group(1)! : '',
      },
    };
  } catch (e) {
    return {'success': false, 'url': url, 'reason': e.toString()};
  }
}

Future<List<Map<String, dynamic>>> _processArticleBatch(List<Map<String, dynamic>> tasks) async {
  final results = <Map<String, dynamic>>[];
  for (final task in tasks) {
    results.add(await _processArticleTask(task));
  }
  return results;
}

String _injectImagesIntoContent(
  String content,
  List<String> imageUrls, {
  String? title,
  String? description,
  List<String>? metaKeywords,
}) {
  if (imageUrls.isEmpty || content.isEmpty) return content;

  const imgStyle =
      'width:100%;max-height:380px;object-fit:cover;border-radius:12px;margin:16px 0;display:block;';

  final segments = _splitContentIntoSegments(
    content,
    title: title,
    description: description,
    metaKeywords: metaKeywords,
  );

  if (segments.length < 2) {
    final buf = StringBuffer(content);
    for (final img in imageUrls) {
      buf.write('\n\n<img src="$img" style="imgStyle" />');
    }
    return buf.toString();
  }

  final buf = StringBuffer();
  int imgIdx = 0;
  for (int i = 0; i < segments.length; i++) {
    buf.write(segments[i]);
    if ((i + 1) % 2 == 0 && imgIdx < imageUrls.length) {
      buf.write('<img src="${imageUrls[imgIdx++]}" style="imgStyle" />');
    }
    if (i < segments.length - 1) {
      buf.write('\n\n');
    }
  }
  while (imgIdx < imageUrls.length) {
    buf.write('<img src="${imageUrls[imgIdx++]}" style="imgStyle" />\n\n');
  }
  return buf.toString().trimRight();
}

List<String> _splitContentIntoSegments(
  String content, {
  String? title,
  String? description,
  List<String>? metaKeywords,
}) {
  if (content.isEmpty) return const [];

  final allKeywords = <String>[];
  if (title != null && title.isNotEmpty) {
      allKeywords.addAll(YallaEngineService.tokenizeSegment(title));
    }
    if (description != null && description.isNotEmpty) {
      allKeywords.addAll(YallaEngineService.tokenizeSegment(description));
    }
    if (metaKeywords != null) {
      for (final kw in metaKeywords) {
        if (kw.isNotEmpty) allKeywords.addAll(YallaEngineService.tokenizeSegment(kw));
    }
  }

  final keywordSet = allKeywords.toSet();

  final rawSegments = content
      .split(RegExp(r'\n\s*\n|\n{2,}'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && s.length >= 20)
      .toList();

  if (rawSegments.isEmpty) {
    final sentences = content
        .split(RegExp(r'(?<=[.!?؟!])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.length >= 15)
        .toList();
    if (sentences.length >= 2) return sentences;
    return [content.trim()];
  }

  if (rawSegments.length == 1) {
    final text = rawSegments.first;
    final sentences = text
        .split(RegExp(r'(?<=[.!?؟!])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.length >= 15)
        .toList();
    if (sentences.length >= 2) return sentences;
    return rawSegments;
  }

  if (keywordSet.isNotEmpty) {
    final scored = rawSegments.map((segment) {
      final tokens = YallaEngineService.tokenizeSegment(segment);
      if (tokens.isEmpty) return (segment, 0.0);
      final matches = tokens.where((t) => keywordSet.contains(t)).length;
      return (segment, matches / tokens.length);
    }).toList();

    scored.sort((a, b) => b.$2.compareTo(a.$2));

    final relevantSegments = scored
        .where((item) => item.$2 > 0.0)
        .map((item) => item.$1)
        .toList();

    if (relevantSegments.length >= 2) {
      return relevantSegments;
    }
  }

  if (rawSegments.length > 6) {
    return rawSegments.take(6).toList();
  }

  return rawSegments;
}



/// Silent background crawler service.
/// Runs automatically on app launch to populate the news feed
/// without any user interaction required.
class BackgroundCrawlerService {
  BackgroundCrawlerService._internal();
  static final BackgroundCrawlerService instance =
      BackgroundCrawlerService._internal();

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// Stream of crawled articles - UI can listen to this for real-time updates
  final _articleStreamController = StreamController<NewsModel>.broadcast();
  Stream<NewsModel> get articleStream => _articleStreamController.stream;

  Future<int> get _topSourcesCount async =>
      await AppSettings.instance.getTopSourcesCount();

  Future<int> get _maxUrlsPerSource async =>
      await AppSettings.instance.getMaxUrlsPerSource();

  /// Start a silent background crawl.
  /// Only runs on Wi-Fi. Falls back silently on mobile data so the UI uses
  /// the API exclusively.
  /// [onProgress] is called after each source is processed.
  /// [onComplete] is called when all sources are done.
  Future<void> startSilentCrawl({
    required YallaEngineService engineService,
    VoidCallback? onProgress,
    VoidCallback? onComplete,
    bool requireWifi = true,
  }) async {
    if (_isRunning) return;

    // ── Wi-Fi gate: never crawl on mobile data unless explicitly bypassed ─────
    if (requireWifi) {
      final onWifi = await ConnectivityService.isWifi();
      if (!onWifi) {
        engineService.addLog(
            '[SILENT CRAWLER] Not on Wi-Fi — skipping crawl, API will serve content.');
        onComplete?.call();
        return;
      }
    }

    _isRunning = true;
    engineService.addLog('[SILENT CRAWLER] Starting background crawler...');

    try {
      final db = NewsDatabase.instance;
      final allSources = await db.getAllSources();

      if (allSources.isEmpty) {
        engineService.addLog('[SILENT CRAWLER] No sources found in DB.');
        _isRunning = false;
        return;
      }

      // Filter for Moroccan Arabic sources only
      final List<NewsSource> moroccanSources = allSources
          .where((s) => s.language.contains('ar') && s.countryCode == 'MA')
          .toList();

      if (moroccanSources.isEmpty) {
        engineService.addLog('[SILENT CRAWLER] No Moroccan sources found in DB.');
        _isRunning = false;
        return;
      }

      final List<NewsSource> topSources = List.from(moroccanSources)
        ..sort((a, b) => b.rank.compareTo(a.rank));
      final sourcesToCrawl =
          topSources.take(await _topSourcesCount).toList();

      engineService.addLog(
          '[SILENT CRAWLER] Queued ${sourcesToCrawl.length} top sources for background crawling.');

      // Load local URL DB JSON once
      String jsonStr = '[]';
      try {
        jsonStr = await rootBundle.loadString('assets/news_local_db.json');
      } catch (_) {
        engineService.addLog('[SILENT CRAWLER] Could not load local DB JSON, using empty.');
      }

      for (int i = 0; i < sourcesToCrawl.length; i++) {
        final source = sourcesToCrawl[i];

         // Skip only if crawled in the last 1 minute (prevents hammering sources)
         final last = await db.getLastCrawlTime(source.url);
         if (last != null && DateTime.now().difference(last).inMinutes < 1) {
          engineService.addLog(
              '[SILENT CRAWLER] [${i + 1}/${sourcesToCrawl.length}] ${source.name}: last crawled ${DateTime.now().difference(last).inMinutes} min ago, skipping.');
          continue;
        }

        engineService.addLog(
            '[SILENT CRAWLER] [${i + 1}/${sourcesToCrawl.length}] Crawling: ${source.name} (${source.url})');

        try {
          await _crawlSource(source, jsonStr, engineService);
          onProgress?.call();
          engineService.addLog('[SILENT CRAWLER] √ ${source.name} done.');
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          engineService.addLog('[SILENT CRAWLER] X ${source.name} failed: $e');
        }
      }

      engineService.addLog('[SILENT CRAWLER] Background crawl complete!');
    } catch (e) {
      engineService.addLog('[SILENT CRAWLER] Fatal error: $e');
    } finally {
      _isRunning = false;
      onComplete?.call();
    }
  }

  /// Add an article to the stream for real-time UI updates
  void _emitArticle(NewsModel article) {
    if (!_articleStreamController.isClosed) {
      _articleStreamController.add(article);
    }
  }

  void dispose() {
    _articleStreamController.close();
  }

  /// Force re-crawl all top sources, ignoring cached articles.
  /// Only runs on Wi-Fi.
  /// [onProgress] is called after each source is processed.
  /// [onComplete] is called when all sources are done.
  Future<void> forceRefresh({
    required YallaEngineService engineService,
    VoidCallback? onProgress,
    VoidCallback? onComplete,
  }) async {
    if (_isRunning) return;

    // ── Wi-Fi gate ───────────────────────────────────────────────────────────
    final onWifi = await ConnectivityService.isWifi();
    if (!onWifi) {
      engineService.addLog(
          '[SILENT CRAWLER] Not on Wi-Fi — skipping force refresh, use API refresh instead.');
      onComplete?.call();
      return;
    }

    _isRunning = true;
    engineService.addLog('[SILENT CRAWLER] Wi-Fi detected — force refresh started...');

    try {
      final db = NewsDatabase.instance;
      final allSources = await db.getAllSources();

      // Filter for Moroccan Arabic sources
      final List<NewsSource> moroccanSources = allSources
          .where((s) => s.language.contains('ar') && s.countryCode == 'MA')
          .toList();

      final List<NewsSource> topSources = List.from(moroccanSources)
        ..sort((a, b) => b.rank.compareTo(a.rank));
      final sourcesToCrawl = topSources.take(await _topSourcesCount).toList();

      String jsonStr = '[]';
      try {
        jsonStr = await rootBundle.loadString('assets/news_local_db.json');
      } catch (_) {}

      for (int i = 0; i < sourcesToCrawl.length; i++) {
        final source = sourcesToCrawl[i];
        engineService.addLog(
            '[SILENT CRAWLER] [${i + 1}/${sourcesToCrawl.length}] Refreshing: ${source.name}');

        try {
          // Clear old articles first
          await db.clearArticlesForSource(source.url);
          await _crawlSource(source, jsonStr, engineService);
          onProgress?.call();
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          engineService.addLog('[SILENT CRAWLER] ✗ ${source.name} failed: $e');
        }
      }

      engineService.addLog('[SILENT CRAWLER] Force refresh complete!');
    } catch (e) {
      engineService.addLog('[SILENT CRAWLER] Fatal error: $e');
    } finally {
      _isRunning = false;
      onComplete?.call();
    }
  }

  /// Multi-Pass, Isolate-Threaded news crawl pipeline for a single source.
  Future<void> _crawlSource(
    NewsSource source,
    String jsonStr,
    YallaEngineService engineService,
  ) async {
    // PASS 1: Discover candidate article URLs from source homepage
    engineService.addLog('[CRAWL PASS 1] Discovering article URLs from ${source.name}...');
    final sourceResult =
        await engineService.processNewsUrl(source.url, jsonStr, silent: true);

    if (sourceResult['success'] != true) {
      engineService.addLog('[CRAWL PASS 1] Failed to discover articles from ${source.url}: ${sourceResult['reason'] ?? 'unknown error'}');
      throw Exception('Stage 1 failed for ${source.url}: ${sourceResult['error'] ?? sourceResult['reason']}');
    }

    List<String> rawUrls = [];

    if (sourceResult['is_source'] == true) {
      final List<dynamic> rawUrlsDynamic = sourceResult['articles'] ?? [];
      rawUrls = rawUrlsDynamic.map((u) => u.toString()).toList();
    } else {
      // Already an article – treat directly
      final article = NewsModel.fromJson(sourceResult, source.url);
      await NewsDatabase.instance.saveCrawledArticles([article], source.url);
      return;
    }

    if (rawUrls.isEmpty) {
      engineService.addLog('[CRAWL PASS 1] No raw articles found from ${source.url}');
      throw Exception('No articles discovered from ${source.url}');
    }

    engineService.addLog('[CRAWL PASS 1] Discovered ${rawUrls.length} candidate URLs.');

    final maxUrls = await _maxUrlsPerSource;
    if (rawUrls.length > maxUrls) {
      engineService.addLog('[CRAWL PASS 1] Limiting to $maxUrls URLs per source to avoid overload.');
      rawUrls = rawUrls.take(maxUrls).toList();
    }

    final sourceUri = Uri.tryParse(source.url);
    final sourceHost = sourceUri?.host.toLowerCase() ?? '';
    final bool sourceIsArabic = source.language.toLowerCase().contains('ar');

    if (sourceHost.isNotEmpty) {
      final beforeDomainFilter = rawUrls.length;
      rawUrls = rawUrls.where((url) {
        final uri = Uri.tryParse(url);
        final host = uri?.host.toLowerCase() ?? '';
        return host == sourceHost || host.endsWith('.$sourceHost');
      }).toList();
      final afterDomainFilter = rawUrls.length;
      if (afterDomainFilter < beforeDomainFilter) {
        engineService.addLog('[CRAWL DOMAIN FILTER] Kept $afterDomainFilter/$beforeDomainFilter URLs matching source domain "$sourceHost".');
      }
    }

    if (rawUrls.isEmpty) {
      engineService.addLog('[CRAWL FILTER] No URLs passed source-domain filter for ${source.url}.');
      return;
    }

    // PASS 2: URL Pre-Validation, Blacklist filtering, Jaccard Similarity Deduplication, and Priority Ranking (Threaded Isolate)
    engineService.addLog('[CRAWL PASS 2] Offloading URL filtering, deduplication, and ranking to background Isolate...');

    final Map<String, String> urlToCategoryMap = {
      for (final url in rawUrls) url: source.category
    };

    final List<Map<String, dynamic>> parsedResults = await compute(
      NewsUriParser.runDeduplicationIsolate,
      {
        'rawUrls': rawUrls,
        'urlToCategoryMap': urlToCategoryMap,
        'similarityThreshold': 0.55,
      },
    );

    final List<String> sortedArticleUrls = parsedResults
        .map((item) => item['url'] as String)
        .toList();

    final int filteredCount = rawUrls.length - sortedArticleUrls.length;
    engineService.addLog(
        '[CRAWL PASS 2] Background thread complete. Filtered/Deduplicated $filteredCount duplicate or invalid URLs.');
    engineService.addLog(
        '[CRAWL PASS 2] Finalized prioritized queue contains ${sortedArticleUrls.length} unique news articles.');

    if (sortedArticleUrls.isEmpty) {
      engineService.addLog('[CRAWL PASS 2] Zero unique news articles survived the deduplication pipeline.');
      return;
    }

    // PASS 3: Background-isolate Crawling & AI Analysis
    final List<NewsModel> fetchedArticles = [];
    int successCount = 0;
    int failureCount = 0;

    engineService.addLog('[CRAWL PASS 3] Initiating background-isolate article processing...');

    const int batchSize = 5;
    final int totalBatches = (sortedArticleUrls.length / batchSize).ceil();

    for (int batchIndex = 0; batchIndex < totalBatches; batchIndex++) {
      final start = batchIndex * batchSize;
      final end = (start + batchSize).clamp(start, sortedArticleUrls.length);
      final batchUrls = sortedArticleUrls.sublist(start, end);

      engineService.addLog('[CRAWL PASS 3] Processing batch ${batchIndex + 1}/$totalBatches (${batchUrls.length} articles)...');

      final batchTasks = batchUrls.map((artUrl) {
        return <String, dynamic>{
          'url': artUrl,
          'validCategoryIds': CategoryService.instance.initialized ? CategoryService.instance.categoryIds : null,
          'sourceLanguage': source.language,
        };
      }).toList();

      try {
        final List<Map<String, dynamic>> batchResults = await compute(
          _processArticleBatch,
          batchTasks,
        );

        for (final result in batchResults) {
          if (result['success'] != true) {
            failureCount++;
            engineService.addLog('[CRAWL PASS 3] Scraper skipped article: ${result['reason'] ?? 'unknown'}');
            continue;
          }

          final articleRaw = NewsModel.fromJson(result, result['url'] as String);
          final String classificationText = '${articleRaw.title} ${articleRaw.summary} ${articleRaw.content}';
          final String detectedCategory = NewsIntelligence.classifyCategory(
            classificationText,
            url: result['url'] as String,
            validCategoryIds: CategoryService.instance.categoryIds,
            titleOnly: articleRaw.title,
          );
          var article = articleRaw.copyWith(category: detectedCategory);
          engineService.addLog('[CATEGORY] Raw: "${articleRaw.category}", Detected: "$detectedCategory" for URL: ${result['url']}');

          if (!YallaEngineService.hasValidTitle(article.title)) {
            engineService.addLog('[VALIDATION] Skipped invalid title for URL: ${result['url']}');
            continue;
          }

          final bool alreadyInBatch = fetchedArticles.any((a) => a.url == article.url);
          final bool alreadyInDb = await NewsDatabase.instance.articleUrlExists(article.url);
          if (alreadyInBatch) {
            engineService.addLog('[DUPLICATE] Skipping already processed URL: ${article.url}');
            continue;
          }
          if (alreadyInDb) {
            engineService.addLog('[DUPLICATE] Skipping existing article in DB: ${article.url}');
            continue;
          }

          if (article.imageUrl.isEmpty) {
            engineService.addLog('[IMAGE] No image found for URL: ${result['url']}. Using category-based image...');
            final categorySlug = article.category.toLowerCase();
            final seed = Uri.parse(result['url'] as String).path.hashCode.abs() % 1000;
            article = article.copyWith(
              imageUrl: 'https://placehold.co/600x400/EEE/31343C?text=$categorySlug+$seed',
            );
            engineService.addLog('[IMAGE] Category image selected: ${article.imageUrl}');
          }

          if (!_isDuplicateByTitle(fetchedArticles, article) &&
              !_isDuplicateWithSameImageButDifferentTitle(fetchedArticles, article)) {
            fetchedArticles.add(article);
            successCount++;
          } else {
            if (_isDuplicateByTitle(fetchedArticles, article)) {
              engineService.addLog('[CRAWL PASS 3] Skipped duplicate: similar title detected.');
            } else {
              engineService.addLog('[CRAWL PASS 3] Skipped duplicate: same image but different title detected.');
            }
            successCount++;
          }

          if (!kIsWeb) {
            try {
              await ServerApiService.saveArticle(article);
            } catch (e) {
              engineService.addLog('[SERVER] Failed to sync article: $e');
            }
            await Future.delayed(const Duration(milliseconds: 1500));
          }
          _emitArticle(article);
        }
      } catch (e) {
        engineService.addLog('[CRAWL PASS 3] Batch failed: $e');
        failureCount += batchUrls.length;
      }

      // Yield to UI and let system rest between batches
      await Future.delayed(const Duration(milliseconds: 200));
    }

    if (fetchedArticles.isNotEmpty) {
      final groupedArticles = _groupSimilarNews(fetchedArticles, source.name);
      await NewsDatabase.instance.saveCrawledArticles(groupedArticles, source.url);

      for (final article in groupedArticles) {
        try {
          await KnowledgeExtractionService.instance.extractAndStore(
            article.url,
            article.title,
            article.content,
            article.category,
            language: 'ar',
          );
        } catch (e) {
          engineService.addLog('[KNOWLEDGE] Failed to extract knowledge for ${article.url}: $e');
        }
      }

      if (!kIsWeb) {
        try {
          final limited = groupedArticles.take(8).toList();
          for (final article in limited) {
            await ServerApiService.saveArticle(article);
            await Future.delayed(const Duration(milliseconds: 1500));
          }
        } catch (e) {
          engineService.addLog('[SERVER] Failed to sync batch: $e');
        }
      }
    }
    engineService.addLog(
        '[CRAWL PASS 3] Crawl complete. Success: $successCount, Failures: $failureCount.');
  }

  static List<NewsModel> _groupSimilarNews(List<NewsModel> articles, String sourceName) {
    final groups = <String, List<NewsModel>>{};

    for (final article in articles) {
      final normalizedTitle = ArabicTextNormalizer.normalize(article.title.toLowerCase());
      final words = normalizedTitle.split(RegExp(r'\s+')).where((w) => w.length > 3).toSet();

      bool foundGroup = false;
      for (final groupKey in groups.keys) {
        final groupWords = groupKey.split('|').toSet();
        if (words.isNotEmpty && groupWords.isNotEmpty) {
          final intersection = words.intersection(groupWords).length;
          final union = words.union(groupWords).length;
          final similarity = union > 0 ? intersection / union : 0.0;
          if (similarity > 0.5) {
            groups[groupKey]!.add(article);
            foundGroup = true;
            break;
          }
        }
      }

      if (!foundGroup) {
        final groupKey = words.join('|');
        groups[groupKey] = [article];
      }
    }

    final result = <NewsModel>[];
    for (final group in groups.values) {
      if (group.length == 1) {
        result.add(group.first);
      } else {
        group.sort((a, b) => b.publishDate.compareTo(a.publishDate));
        final primary = group.first;
        final allSources = group.map((a) => a.sources.isNotEmpty ? a.sources.first : sourceName).toList();
        final uniqueSources = allSources.toSet().toList();
        result.add(primary.copyWith(
          sourceCount: uniqueSources.length,
          sources: uniqueSources,
        ));
      }
    }

    return result;
  }

  /// Checks if a new article is a duplicate with the same image but different title.
  /// Articles with identical images but different titles need fresh image searches.
  static bool _isDuplicateWithSameImageButDifferentTitle(List<NewsModel> existing, NewsModel newArticle) {
    if (newArticle.imageUrl.isEmpty) return false;

    for (final existingArticle in existing) {
      if (existingArticle.imageUrl == newArticle.imageUrl && existingArticle.imageUrl.isNotEmpty) {
        final cleanTitle1 = newArticle.title.toLowerCase().replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '');
        final cleanTitle2 = existingArticle.title.toLowerCase().replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '');
        final words1 = cleanTitle1.split(RegExp(r'\s+')).where((w) => w.length > 3).toSet();
        final words2 = cleanTitle2.split(RegExp(r'\s+')).where((w) => w.length > 3).toSet();

        if (words1.isNotEmpty && words2.isNotEmpty) {
          final intersection = words1.intersection(words2).length;
          final union = words1.union(words2).length;
          final titleSim = intersection / union;
          if (titleSim < 0.5) {
            return true;
          }
        } else if (words1.isEmpty || words2.isEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _isDuplicateByTitle(List<NewsModel> existing, NewsModel newArticle) {
    if (newArticle.title.isEmpty) return false;

    final cleanNew = ArabicTextNormalizer.normalize(newArticle.title.toLowerCase());
    if (cleanNew.isEmpty) return false;

    for (final existingArticle in existing) {
      final cleanExisting = ArabicTextNormalizer.normalize(existingArticle.title.toLowerCase());
      if (cleanExisting.isEmpty) continue;

      final wordsNew = cleanNew.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
      final wordsExisting = cleanExisting.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();

      if (wordsNew.isEmpty || wordsExisting.isEmpty) continue;

      final intersection = wordsNew.intersection(wordsExisting).length;
      final union = wordsNew.union(wordsExisting).length;
      final titleSim = intersection / union;

      if (titleSim > 0.5) {
        return true;
      }
    }
    return false;
  }
}

bool isLikelySectionPage(String url) {
  final lower = url.toLowerCase();
  if (lower.contains('/section/')) return true;
  if (lower.contains('/category/')) return true;
  if (lower.contains('/tag/')) return true;
  if (lower.contains('/page/')) return true;
  if (lower.contains('/channel/')) return true;
  if (lower.contains('#nav') ||
      lower.contains('#hpnavsec') ||
      lower.contains('#footer')) return true;
  if (lower.contains('google.com/preferences')) return true;
  return false;
}
