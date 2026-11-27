import 'dart:core';

import '../models/news_model.dart';

/// Deterministic, local validator that checks whether a crawled page is a real
/// news article (as opposed to a homepage, category page, nav link, ad, or
/// extraction artifact). No AI/API calls are used; all checks are rule-based
/// and language-agnostic where possible, with Arabic/French/English awareness.
///
/// A separate instance should be used per crawl run so that duplicate
/// fingerprint tracking does not leak across unrelated jobs.
class RealNewsValidator {
  RealNewsValidator({bool enableDuplicateTracking = true})
      : _enableDuplicateTracking = enableDuplicateTracking;

  final bool _enableDuplicateTracking;
  final Set<String> _titleFingerprints = <String>{};
  final Set<String> _contentFingerprints = <String>{};
  final Set<String> _urlFingerprints = <String>{};

  // ───────────────────────────────────────────────────────────────────────────
  // Public entry point
  // ───────────────────────────────────────────────────────────────────────────

  /// Validates [article] and returns a [Result]. When [valid] is false,
  /// [reason] explains why.
  Result validate(NewsModel article) {
    final title = article.title.trim();
    final url = article.url.trim();
    final content = article.content.trim();
    final summary = article.summary.trim();

    // ── 1. URL structural checks ──
    final urlCheck = _validateUrl(url);
    if (!urlCheck.valid) {
      return Result(
        valid: false,
        reason: 'URL: ${urlCheck.reason}',
        titleFingerprint: _fingerprintTitle(title),
        contentFingerprint: _fingerprintContent(content.isNotEmpty ? content : summary),
      );
    }

    // ── 2. Title checks ──
    final titleCheck = _validateTitle(title);
    if (!titleCheck.valid) {
      return Result(
        valid: false,
        reason: 'Title: ${titleCheck.reason}',
        titleFingerprint: _fingerprintTitle(title),
        contentFingerprint: _fingerprintContent(content.isNotEmpty ? content : summary),
      );
    }

    // ── 3. Content checks ──
    final contentCheck = _validateContent(
      content.isNotEmpty ? content : summary,
      title: title,
    );
    if (!contentCheck.valid) {
      return Result(
        valid: false,
        reason: 'Content: ${contentCheck.reason}',
        titleFingerprint: _fingerprintTitle(title),
        contentFingerprint: _fingerprintContent(content.isNotEmpty ? content : summary),
      );
    }

    // ── 4. Title / body mismatch ──
    final mismatchCheck = _validateTitleBodyMatch(title, content.isNotEmpty ? content : summary);
    if (!mismatchCheck.valid) {
      return Result(
        valid: false,
        reason: 'Mismatch: ${mismatchCheck.reason}',
        titleFingerprint: _fingerprintTitle(title),
        contentFingerprint: _fingerprintContent(content.isNotEmpty ? content : summary),
      );
    }

    // ── 5. Duplicate fingerprint detection ──
    final titleFp = _fingerprintTitle(title);
    final contentFp = _fingerprintContent(content.isNotEmpty ? content : summary);
    final urlFp = _fingerprintUrl(url);

    if (_enableDuplicateTracking) {
      if (_titleFingerprints.contains(titleFp) &&
          _contentFingerprints.contains(contentFp)) {
        return Result(
          valid: false,
          reason: 'Duplicate: identical title and content already seen',
          titleFingerprint: titleFp,
          contentFingerprint: contentFp,
        );
      }
      if (_urlFingerprints.contains(urlFp)) {
        return Result(
          valid: false,
          reason: 'Duplicate: URL already processed',
          titleFingerprint: titleFp,
          contentFingerprint: contentFp,
        );
      }
      _titleFingerprints.add(titleFp);
      _contentFingerprints.add(contentFp);
      _urlFingerprints.add(urlFp);
    }

    return Result(
      valid: true,
      reason: '',
      titleFingerprint: titleFp,
      contentFingerprint: contentFp,
    );
  }

  /// Clear all tracked fingerprints. Useful when starting a new crawl job.
  void clearDuplicates() {
    _titleFingerprints.clear();
    _contentFingerprints.clear();
    _urlFingerprints.clear();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // URL validation
  // ───────────────────────────────────────────────────────────────────────────

  _UrlCheck _validateUrl(String url) {
    if (url.isEmpty) return _UrlCheck(false, 'empty URL');
    if (url.length < 10) return _UrlCheck(false, 'URL too short');

    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || uri.host.isEmpty) {
        return _UrlCheck(false, 'no scheme/host');
      }
    } catch (_) {
      return _UrlCheck(false, 'unparseable URL');
    }

    final path = Uri.parse(url).path.toLowerCase();

    // Homepage / root patterns
    final pathSegments = Uri.parse(url).pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    if (pathSegments.isEmpty || (pathSegments.length == 1 && pathSegments.first.length <= 3)) {
      if (pathSegments.isEmpty ||
          pathSegments.first == 'index.html' ||
          pathSegments.first == 'index.php' ||
          pathSegments.first == 'home') {
        return _UrlCheck(false, 'homepage URL');
      }
    }

    // Category / section / tag patterns
    final categoryKeywords = [
      'category', 'categorie', 'categoría', 'categorie', 'section', 'rubrique',
      'rubriques', 'tag', 'tags', 'étiquette', 'étiquettes', 'mot-clé', 'mot-cles',
      'search', 'recherche', 'buscar', 'suche', 'archive', 'archives',
      'author', 'auteur', 'publisher', 'about', 'contact', 'privacy', 'cookie',
      'terms', 'condition', 'sitemap', 'rss', 'feed', 'newsletter',
      'video', 'vidéo', 'videos', 'vidéos', 'watch', 'live', 'direct',
      'photo', 'photos', 'gallery', 'gallerie', 'album', 'infographic',
      'opinion', 'éditorial', 'editorial', 'letters', 'corrections',
      'weather', 'météo', 'horoscope', 'lottery', 'loto',
    ];

    for (final kw in categoryKeywords) {
      if (path.contains('/$kw/') || path.endsWith('/$kw') || path.contains('?$kw=') ||
          path.contains('$kw=')) {
        return _UrlCheck(false, 'category/section/tag URL ($kw)');
      }
    }

    // Pagination patterns
    final paginationPatterns = [
      RegExp(r'/page/\d+'),
      RegExp(r'/p/\d+'),
      RegExp(r'/?page=\d+'),
      RegExp(r'/?paged=\d+'),
      RegExp(r'/?start=\d+'),
      RegExp(r'/?offset=\d+'),
    ];
    for (final re in paginationPatterns) {
      if (re.hasMatch(url)) {
        return _UrlCheck(false, 'pagination URL');
      }
    }

    return _UrlCheck(true, '');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Title validation
  // ───────────────────────────────────────────────────────────────────────────

  _TitleCheck _validateTitle(String title) {
    if (title.isEmpty) return _TitleCheck(false, 'empty title');
    if (title.length < 5) return _TitleCheck(false, 'title too short (<5 chars)');
    if (title.length > 200) return _TitleCheck(false, 'title too long (>200 chars)');

    // Punctuation-only or placeholder titles
    if (RegExp(r'^[\s\.\-_,:;!?…«»()\[\]{}]{2,}$').hasMatch(title)) {
      return _TitleCheck(false, 'title is punctuation/placeholder only');
    }

    final tl = title.toLowerCase();

    // Exact generic single-word titles
    final genericTitles = {
      'news', 'latest', 'breaking', 'home', 'accueil', 'principal',
      'politics', 'politique', 'sport', 'sports', 'économie',
      'economy', 'business', 'international', 'world', 'monde',
      'technology', 'technologie', 'culture', 'health', 'santé',
      'science', 'science et technologie', 'regions', 'régions',
      'local', 'national', 'faits divers', 'société', 'society',
    };
    if (genericTitles.contains(tl.trim())) {
      return _TitleCheck(false, 'generic single-word title ("$tl")');
    }

    // Site-name-only titles (already partly handled upstream, re-check here)
    final siteOnly = {
      'al jazeera','الجزيرة','bbc','cnn','reuters','le monde','hespress',
      'mosaique fm','almasryalyoum','google','facebook','twitter','instagram',
      'youtube','whatsapp','telegram','alaraby','alarabiya','sky news',
      'france 24','dw','dw.com','ap news','associated press','afp',
    };
    if (siteOnly.contains(tl.trim())) {
      return _TitleCheck(false, 'site-name-only title');
    }

    // Titles that are just a publisher suffix with no article subject
    final publisherSuffixes = [
      'اليوم 24', 'اليوم24', 'اليوم', 'جريدة المنتخب', 'المنتخب', 'جريدة',
      'صحيفة', 'هسبريس', 'هبة بريس', 'لي360', 'le360', 'كووورة', 'kora',
      'الجزيرة', 'alarabiya', 'العربية', 'سكاي نيوز',
      'reuters', 'bbc', 'cnn', 'al jazeera', 'ap news', 'associated press',
      'le360', 'lematin', 'lematin.ma', 'telquel', 'aujourdhui',
    ];
    for (final suffix in publisherSuffixes) {
      if (tl == suffix.trim()) {
        return _TitleCheck(false, 'publisher-name-only title ("$suffix")');
      }
    }

    // Titles that are purely a category label
    final categoryLabels = {
      'الأخبار','الرياضة','الاقتصاد','السياسة','الثقافة','التكنولوجيا',
      'الصحة','العالم','المغرب','العربي','دولي','محلي','faits divers',
      'actus', 'actualités', 'actualite', 'news', 'info', 'infos',
    };
    if (categoryLabels.contains(tl.trim())) {
      return _TitleCheck(false, 'category-label-only title');
    }

    // Mixed-script detection (scraping artifacts)
    bool hasArabic = title.contains(RegExp(r'[\u0600-\u06FF]'));
    bool hasCjk = title.contains(RegExp(r'[\u4E00-\u9FFF\u3400-\u4DBF]'));
    bool hasCyrillic = title.contains(RegExp(r'[\u0400-\u04FF]'));
    bool hasGreek = title.contains(RegExp(r'[\u0370-\u03FF]'));
    int scriptCount = (hasArabic ? 1 : 0) + (hasCjk ? 1 : 0) +
        (hasCyrillic ? 1 : 0) + (hasGreek ? 1 : 0);
    if (scriptCount > 1) {
      return _TitleCheck(false, 'mixed-script title (scraping artifact)');
    }

    return _TitleCheck(true, '');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Content validation
  // ───────────────────────────────────────────────────────────────────────────

  _ContentCheck _validateContent(String content, {required String title}) {
    if (content.isEmpty) return _ContentCheck(false, 'empty content');

    final tl = content.toLowerCase();
    final trimmed = content.trim();

    // Minimum length
    if (trimmed.length < 40) {
      return _ContentCheck(false, 'content too short (<40 chars)');
    }

    // Boilerplate / nav / cookie / ad detection
    final boilerplateIndicators = [
      'cookie', 'cookies', 'politique de confidentialité', 'privacy policy',
      'mentions légales', 'terms of service', 'conditions générales',
      'about us', 'à propos', 'contactez-nous', 'contact us',
      'newsletter', 'inscrivez-vous', 'subscribe', 'abonnement',
      'publicité', 'advertisement', 'sponsored', 'contenu sponsorisé',
      'rejoignez-nous', 'follow us', 'suivez-nous', 'téléchargez notre',
      'application mobile', 'app store', 'google play',
      'all rights reserved', 'tous droits réservés',
      'copyright', 'droits d’auteur', 'powered by',
    ];

    int boilerplateHits = 0;
    for (final indicator in boilerplateIndicators) {
      if (tl.contains(indicator)) boilerplateHits++;
    }

    // If more than half the "content" is boilerplate keywords, reject
    final wordCount = trimmed.split(RegExp(r'\s+')).where((w) => w.length > 1).length;
    if (wordCount > 0) {
      final boilerplateRatio = boilerplateHits / (wordCount / 10).clamp(1, 1000);
      if (boilerplateRatio > 0.5) {
        return _ContentCheck(false, 'content appears to be boilerplate/nav/ads');
      }
    }

    // Real-news signal: must contain at least one verb-like or noun-dense signal.
    // Very light heuristic: look for sentence-ending punctuation and at least
    // a few content words (not just function words).
    final contentWords = trimmed.split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();
    if (contentWords.length < 5) {
      return _ContentCheck(false, 'content has too few real words (<5)');
    }

    // Sentence structure check: real articles usually have multiple sentences
    // or at least one full stop / question / exclamation.
    final sentenceEnders = RegExp(r'[.!?؟!?…]');
    final sentenceCount = sentenceEnders.allMatches(trimmed).length;
    if (sentenceCount < 1 && trimmed.length > 200) {
      return _ContentCheck(false, 'content lacks sentence structure (no terminal punctuation)');
    }

    // Reject content that is mostly a list of links / nav items (many short lines)
    final lines = trimmed.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length > 5) {
      final shortLines = lines.where((l) => l.trim().length < 30).length;
      if (shortLines / lines.length > 0.7) {
        return _ContentCheck(false, 'content appears to be a link list / nav menu');
      }
    }

    return _ContentCheck(true, '');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Title / body mismatch
  // ───────────────────────────────────────────────────────────────────────────

  _MismatchCheck _validateTitleBodyMatch(String title, String content) {
    // Lightweight: extract significant words (length >= 4) from title and check
    // whether at least one appears (in some form) in the content. This catches
    // cases where the extracted title belongs to a different article than the
    // extracted body (e.g. sidebar widget title + main page body).
    final titleWords = title
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 4)
        .map((w) => _stripDiacritics(w.toLowerCase()))
        .toSet();

    if (titleWords.isEmpty) return _MismatchCheck(true, '');

    final contentNormalized = _stripDiacritics(content.toLowerCase());

    int matches = 0;
    for (final word in titleWords) {
      if (contentNormalized.contains(word)) {
        matches++;
        continue;
      }
      // For Arabic/inflected words, also check without leading prefixes (ال, و, ب, ل, ف, ك).
      final stem = word.replaceFirst(RegExp(r'^[وفبلك]?ال'), '');
      if (stem.length >= 3 && contentNormalized.contains(stem)) {
        matches++;
      }
    }

    // Require at least one title word to appear in the content.
    if (matches == 0) {
      return _MismatchCheck(false, 'title words not found in body (title/body mismatch)');
    }

    return _MismatchCheck(true, '');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Fingerprint helpers
  // ───────────────────────────────────────────────────────────────────────────

  String _fingerprintTitle(String title) {
    final normalized = _normalizeForFingerprint(title);
    return _hashString(normalized);
  }

  String _fingerprintContent(String content) {
    final normalized = _normalizeForFingerprint(content);
    // Use first 200 chars + length to catch near-duplicates without storing
    // entire bodies.
    final trimmed = normalized.length > 200 ? normalized.substring(0, 200) : normalized;
    return _hashString('$trimmed|${normalized.length}');
  }

  String _fingerprintUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path.toLowerCase();
      // Strip query params and trailing slashes for dedup
      return _hashString('${uri.host.toLowerCase()}$path');
    } catch (_) {
      return _hashString(url.toLowerCase());
    }
  }

  String _normalizeForFingerprint(String text) {
    final noDiacritics = _stripDiacritics(text.toLowerCase());
    // Collapse whitespace and punctuation
    return noDiacritics
        .replaceAll(RegExp(r'[^\w\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _stripDiacritics(String text) {
    // Arabic: strip common diacritics (tashkeel)
    var result = text.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    // French accents -> base letter (best-effort ASCII folding)
    const from = 'àáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿ';
    const to   = 'aaaaaaaceeeeiiiiionoooooouuuuyyy';
    for (var i = 0; i < from.length; i++) {
      result = result.replaceAll(from[i], to[i]);
    }
    return result;
  }

  String _hashString(String input) {
    // Simple deterministic FNV-1a hash (good enough for dedup fingerprints)
    var hash = 2166136261;
    for (var i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

/// Result of validation.
class Result {
  /// True when the article passed all checks.
  final bool valid;
  /// Human-readable rejection reason (empty when [valid] is true).
  final String reason;
  /// Normalized title fingerprint (for external dedup if desired).
  final String titleFingerprint;
  /// Normalized content fingerprint.
  final String contentFingerprint;

  Result({
    required this.valid,
    required this.reason,
    required this.titleFingerprint,
    required this.contentFingerprint,
  });
}

// ───────────────────────────────────────────────────────────────────────────
// Internal result holders
// ───────────────────────────────────────────────────────────────────────────

class _UrlCheck {
  final bool valid;
  final String reason;
  _UrlCheck(this.valid, this.reason);
}

class _TitleCheck {
  final bool valid;
  final String reason;
  _TitleCheck(this.valid, this.reason);
}

class _ContentCheck {
  final bool valid;
  final String reason;
  _ContentCheck(this.valid, this.reason);
}

class _MismatchCheck {
  final bool valid;
  final String reason;
  _MismatchCheck(this.valid, this.reason);
}
