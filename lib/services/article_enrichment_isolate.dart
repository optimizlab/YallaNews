import 'package:http/http.dart' as http;

Future<EnrichResult> enrichArticleIsolate(Map<String, dynamic> params) async {
  final String url = params['url'] as String;
  final int timeoutSeconds = params['timeoutSeconds'] as int? ?? 10;

  try {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13; SM-G981B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'ar,en-US;q=0.9,en;q=0.8',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Upgrade-Insecure-Requests': '1',
      },
    ).timeout(Duration(seconds: timeoutSeconds));
    if (response.statusCode != 200) {
      return EnrichResult(success: false, reason: 'HTTP ${response.statusCode}');
    }

    final html = response.body;
    String? fetchedImage;
    final ogImageMatch = RegExp(r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"[^>]*>', caseSensitive: false).firstMatch(html);
    if (ogImageMatch != null) {
      fetchedImage = _resolveImageUrl(ogImageMatch.group(1) ?? '', url);
    }

    String cleaned = _extractArticleContent(html);
    cleaned = _decodeHtml(cleaned);
    cleaned = cleaned.trim();

    if (cleaned.length < 120) {
      final pTags = RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true, caseSensitive: false)
          .allMatches(html)
          .map((m) => m.group(1) ?? '')
          .toList();
      if (pTags.isNotEmpty) {
        cleaned = pTags.join('\n\n');
        cleaned = cleaned.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
        cleaned = _decodeHtml(cleaned);
      }
    }

    return EnrichResult(
      success: true,
      content: cleaned,
      imageUrl: fetchedImage ?? '',
    );
  } catch (e) {
    return EnrichResult(success: false, reason: e.toString());
  }
}

String _resolveImageUrl(String raw, String pageUrl) {
  var value = raw.trim().replaceAll('&amp;', '&').replaceAll('&#x2F;', '/').replaceAll('&quot;', '"').replaceAll(r'\/', '/');
  if (value.startsWith('//')) value = 'https:$value';
  final parsed = Uri.tryParse(value);
  if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) return parsed.toString();
  final base = Uri.tryParse(pageUrl);
  if (base == null) return value;
  final resolved = base.resolve(value);
  return resolved.hasScheme && resolved.host.isNotEmpty ? resolved.toString() : value;
}

String _extractArticleContent(String html) {
  String cleaned = html;
  cleaned = cleaned.replaceAll(RegExp(r'<script\b[^>]*>.*?</script>', dotAll: true, caseSensitive: false), '');
  cleaned = cleaned.replaceAll(RegExp(r'<style\b[^>]*>.*?</style>', dotAll: true, caseSensitive: false), '');
  cleaned = cleaned.replaceAll(RegExp(r'<nav\b[^>]*>.*?</nav>', dotAll: true, caseSensitive: false), '');
  cleaned = cleaned.replaceAll(RegExp(r'<header\b[^>]*>.*?</header>', dotAll: true, caseSensitive: false), '');
  cleaned = cleaned.replaceAll(RegExp(r'<footer\b[^>]*>.*?</footer>', dotAll: true, caseSensitive: false), '');
  cleaned = cleaned.replaceAll(RegExp(r'<aside\b[^>]*>.*?</aside>', dotAll: true, caseSensitive: false), '');
  cleaned = cleaned.replaceAll(RegExp(r'<iframe\b[^>]*>.*?</iframe>', dotAll: true, caseSensitive: false), '');

  final articlePatterns = [
    RegExp(r'<article[^>]*>(.*?)</article>', dotAll: true, caseSensitive: false),
    RegExp('<div[^>]+class=["\'][^"\']*(?:article|content|post|entry|body)[^"\']*["\'][^>]*>(.*?)</div>', dotAll: true, caseSensitive: false),
    RegExp('<div[^>]+id=["\'][^"\']*(?:article|content|post|entry|body)[^"\']*["\'][^>]*>(.*?)</div>', dotAll: true, caseSensitive: false),
    RegExp(r'<main[^>]*>(.*?)</main>', dotAll: true, caseSensitive: false),
  ];

  String extracted = '';
  int bestLength = 0;
  for (final pattern in articlePatterns) {
    for (final match in pattern.allMatches(cleaned)) {
      final candidate = match.group(1) ?? '';
      if (candidate.length > bestLength) {
        bestLength = candidate.length;
        extracted = candidate;
      }
    }
  }

  String working = extracted;
  if (working.isEmpty) {
    final bodyMatch = RegExp(r'<body[^>]*>(.*?)</body>', dotAll: true, caseSensitive: false).firstMatch(cleaned);
    working = bodyMatch != null ? bodyMatch.group(1)! : cleaned;
  }

  final pTags = RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true, caseSensitive: false)
      .allMatches(working)
      .map((m) => (m.group(1) ?? '').trim())
      .where((t) => t.isNotEmpty)
      .toList();

  if (pTags.isEmpty) {
    working = working.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    working = working.replaceAll(RegExp(r'</?(p|div|li|tr|td|h[1-6]|blockquote|pre|ul|ol|section|article)[^>]*>', caseSensitive: false), '\n');
    working = working.replaceAll(RegExp(r'<[^>]+>'), ' ');
    working = working.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    working = working.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    working = working.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    return working;
  }

  final buffer = StringBuffer();
  for (final p in pTags) {
    final text = p.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
    if (text.isEmpty) continue;
    if (buffer.length > 0) buffer.writeln();
    buffer.writeln(text);
  }

  var result = buffer.toString().trim();
  if (result.isEmpty) {
    result = working.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    result = result.replaceAll(RegExp(r'</?(p|div|li|tr|td|h[1-6]|blockquote|pre|ul|ol|section|article)[^>]*>', caseSensitive: false), '\n');
    result = result.replaceAll(RegExp(r'<[^>]+>'), ' ');
    result = result.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    result = result.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }

  result = result.replaceAll(RegExp(r'تابعنا على.*', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'اشترك في.*', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'حقوق النشر.*', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'جميع الحقوق.*', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'اضغط هنا.*', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'شارك المقال.*', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'شارك\s+(Telegram|LinkedIn|Messenger|Facebook|Twitter|WhatsApp|Instagram|YouTube|TikTok).*', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'(Telegram|LinkedIn|Messenger|Facebook|Twitter|WhatsApp|Instagram|YouTube|TikTok)\s+.*?(?:share|شارك).*', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'للمزيد من الأخبار.*', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'الرئيسية\s*/\s*الأخبار\s*/.*', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'الرئيسية\s*/\s*.*', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'الصفحه\s+الرئيسية.*', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'الصفحه\s+الرئيسيه.*', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'تطبيق.*', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'www\..*?\.(com|ma|net|org)', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'https?://[^\s]+', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\p{P}\p{N}]', caseSensitive: false), ' ');
  result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  result = result.replaceAll(RegExp(r'[ \t]+'), ' ').trim();

  final paragraphs = result.split('\n').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  final seen = <String>{};
  final unique = <String>[];
  for (final p in paragraphs) {
    final key = p.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    if (seen.add(key)) {
      unique.add(p);
    }
  }
  result = unique.join('\n\n');

  return result;
}

String _decodeHtml(String text) {
  if (text.isEmpty) return text;
  try {
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (text[i] == '&') {
        final semi = text.indexOf(';', i);
        if (semi > i && semi - i < 10) {
          final entity = text.substring(i, semi + 1);
          if (entity.startsWith('&#x') || entity.startsWith('&#X')) {
            final hex = entity.substring(3, entity.length - 1);
            final code = int.tryParse(hex, radix: 16);
            if (code != null) { buffer.writeCharCode(code); i = semi; continue; }
          } else if (entity.startsWith('&#')) {
            final num = entity.substring(2, entity.length - 1);
            final code = int.tryParse(num);
            if (code != null) { buffer.writeCharCode(code); i = semi; continue; }
          } else {
            final decoded = _namedEntity(entity);
            if (decoded != null) { buffer.write(decoded); i = semi; continue; }
          }
        }
      }
      buffer.write(text[i]);
    }
    return buffer.toString();
  } on Exception {
    return text;
  }
}

String? _namedEntity(String entity) {
  switch (entity) {
    case '&quot;': return '"';
    case '&apos;': return "'";
    case '&#34;': return '"';
    case '&#39;': return "'";
    case '&lt;': return '<';
    case '&gt;': return '>';
    case '&amp;': return '&';
    case '&nbsp;': return ' ';
    case '&thinsp;': return ' ';
    case '&ensp;': return ' ';
    case '&emsp;': return ' ';
    case '&mdash;': return '—';
    case '&ndash;': return '–';
    case '&hellip;': return '…';
    case '&bull;': return '•';
    case '&lsquo;': return '\u2018';
    case '&rsquo;': return '\u2019';
    case '&ldquo;': return '\u201C';
    case '&rdquo;': return '\u201D';
    case '&copy;': return '©';
    case '&reg;': return '®';
    case '&trade;': return '™';
    case '&euro;': return '€';
    case '&pound;': return '£';
    case '&yen;': return '¥';
    case '&deg;': return '°';
    default: return null;
  }
}

class EnrichResult {
  final bool success;
  final String content;
  final String imageUrl;
  final String reason;

  EnrichResult({
    required this.success,
    this.content = '',
    this.imageUrl = '',
    this.reason = '',
  });

  Map<String, dynamic> toJson() => {
    'success': success,
    'content': content,
    'imageUrl': imageUrl,
    'reason': reason,
  };
}
