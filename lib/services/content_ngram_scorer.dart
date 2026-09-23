/// content_ngram_scorer.dart
///
/// On-device TinyLLM-style paragraph scorer using character + word n-grams.
/// Given an article query (title + description), scores every candidate
/// paragraph from raw HTML and returns only relevant ones in original
/// top-to-bottom page order — garbage, nav, link-dumps and off-topic blocks
/// are silently discarded.
///
/// Zero external dependencies — safe in background isolates.

library content_ngram_scorer;

class ScoredParagraph {
  final String text;
  final double score; // 0.0 → 1.0
  final int originalIndex; // position in page (top = 0)
  const ScoredParagraph({required this.text, required this.score, required this.originalIndex});
}

class ContentNgramScorer {
  // ── Tuning ────────────────────────────────────────────────────────────────
  static const int _cn = 3; // char n-gram size (trigram)
  static const int _wn = 2; // word n-gram size (bigram)
  static const double _cw = 0.35; // char weight
  static const double _ww = 0.65; // word weight
  static const int _minLen = 45;
  static const int _maxLen = 3200;
  static const double defaultThreshold = 0.07;
  static const int defaultMaxParagraphs = 28;

  // ── Noise patterns ────────────────────────────────────────────────────────
  static final _noise = <RegExp>[
    RegExp(r'^(share|tweet|like|follow|subscribe|copy link|رابط|شارك|تغريد|تابع)\b', caseSensitive: false),
    RegExp(r'^.{1,60}[›|→»«]\s*$'),
    RegExp(r'(cookie|gdpr|privacy policy|كوكيز|سياسة الخصوصية)', caseSensitive: false),
    RegExp(r'^[\s\W]{0,10}$'),
    RegExp(r'https?://\S+\s*$'),
    RegExp(r'^(tags?|الوسوم|keywords?)\s*:', caseSensitive: false),
    RegExp(r'(©|\bcopyright\b|جميع الحقوق محفوظة)', caseSensitive: false),
    RegExp(r'^\d+\s*/\s*\d+\s*$'),
    RegExp(r'^(اقرأ أيض|read (also|more)|voir aussi)', caseSensitive: false),
    RegExp(r'(إعلان|sponsored|advertisement|publicité)', caseSensitive: false),
    RegExp(r'^[\d\s\W]{0,25}$'), // lines that are just numbers/punctuation
  ];

  // ── Public API ────────────────────────────────────────────────────────────

  /// Main entry point.
  /// [rawHtml]   : raw HTML of the crawled page
  /// [title]     : article title (query anchor)
  /// [description]: article meta-description (query anchor)
  /// Returns clean, relevance-filtered plain-text content with paragraphs
  /// joined by double-newlines, in original page order.
  static String buildRichContent({
    required String rawHtml,
    required String title,
    required String description,
    double threshold = defaultThreshold,
    int maxParagraphs = defaultMaxParagraphs,
  }) {
    final plain = _stripHtml(rawHtml);
    final candidates = _splitParagraphs(plain);

    final clean = candidates
        .where((p) => !_isNoise(p) && p.length >= _minLen && p.length <= _maxLen)
        .toList();

    if (clean.isEmpty) return description.isNotEmpty ? description : title;

    final query = '$title. $description';
    final qChar = _charNgrams(query.toLowerCase(), _cn);
    final qWord = _wordNgrams(query.toLowerCase(), _wn);

    final scored = <ScoredParagraph>[];
    for (int i = 0; i < clean.length; i++) {
      final s = _score(clean[i], qChar, qWord);
      if (s >= threshold) {
        scored.add(ScoredParagraph(text: clean[i], score: s, originalIndex: i));
      }
    }

    if (scored.isEmpty) {
      // Fallback: return top-5 best-scoring paragraphs
      final all = List.generate(clean.length,
          (i) => ScoredParagraph(text: clean[i], score: _score(clean[i], qChar, qWord), originalIndex: i));
      all.sort((a, b) => b.score.compareTo(a.score));
      final top = all.take(5).toList()..sort((a, b) => a.originalIndex.compareTo(b.originalIndex));
      return top.map((p) => p.text).join('\n\n');
    }

    // Keep original page order, cap
    scored.sort((a, b) => a.originalIndex.compareTo(b.originalIndex));
    return scored.take(maxParagraphs).map((p) => p.text).join('\n\n');
  }

  // ── Strip HTML → plain text ───────────────────────────────────────────────
  static String _stripHtml(String html) {
    var t = html
        .replaceAll(RegExp(r'<script\b[^>]*>.*?</script>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style\b[^>]*>.*?</style>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ')
        // Block-level → newline (preserve paragraph structure)
        .replaceAll(RegExp(
            r'<(?:br|p|div|section|article|header|footer|h[1-6]|li|tr|td|th|blockquote|figure|aside|nav)[^>]*>',
            caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&amp;', '&').replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<').replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"').replaceAll('&#39;', "'")
        .replaceAll('&hellip;', '…').replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–').replaceAll('&rsquo;', '\u2019')
        .replaceAll('&lsquo;', '\u2018').replaceAll('&ldquo;', '\u201C')
        .replaceAll('&rdquo;', '\u201D');
    t = t.replaceAllMapped(RegExp(r'&#x([0-9A-Fa-f]+);'), (m) {
      try { return String.fromCharCode(int.parse(m.group(1)!, radix: 16)); } catch (_) { return ''; }
    });
    t = t.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      try { return String.fromCharCode(int.parse(m.group(1)!)); } catch (_) { return ''; }
    });
    return t.replaceAll(RegExp(r'[ \t]+'), ' ');
  }

  static List<String> _splitParagraphs(String text) =>
      text.split(RegExp(r'\n\s*\n|\n'))
          .map((s) => s.replaceAll(RegExp(r'\s+'), ' ').trim())
          .where((s) => s.isNotEmpty)
          .toList();

  static bool _isNoise(String para) {
    for (final re in _noise) {
      if (re.hasMatch(para.trim())) return true;
    }
    final alphaCount = para.runes.where(_isAlpha).length;
    if (para.length > 20 && alphaCount / para.length < 0.45) return true;
    if (!para.contains(' ') && para.contains('/') && para.length > 30) return true;
    return false;
  }

  static bool _isAlpha(int r) =>
      (r >= 0x30 && r <= 0x39) || (r >= 0x41 && r <= 0x5A) ||
      (r >= 0x61 && r <= 0x7A) || (r >= 0x0600 && r <= 0x06FF) ||
      (r >= 0xFB50 && r <= 0xFDFF) || (r >= 0xFE70 && r <= 0xFEFF);

  // ── N-grams ───────────────────────────────────────────────────────────────
  static Set<String> _charNgrams(String t, int n) {
    if (t.length < n) return {};
    final s = <String>{};
    for (int i = 0; i <= t.length - n; i++) s.add(t.substring(i, i + n));
    return s;
  }

  static Set<String> _wordNgrams(String t, int n) {
    final words = t.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
    if (words.length < n) return {};
    final s = <String>{};
    for (int i = 0; i <= words.length - n; i++) s.add(words.sublist(i, i + n).join(' '));
    return s;
  }

  // ── Scoring ───────────────────────────────────────────────────────────────
  static double _score(String para, Set<String> qChar, Set<String> qWord) {
    final l = para.toLowerCase();
    return _cw * _jaccard(qChar, _charNgrams(l, _cn)) +
           _ww * _jaccard(qWord, _wordNgrams(l, _wn));
  }

  static double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final i = a.intersection(b).length;
    final u = a.length + b.length - i;
    return u == 0 ? 0.0 : i / u;
  }
}
