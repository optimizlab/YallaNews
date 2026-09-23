import 'dart:core';

/// Represents parsed news URI metadata with small info gathered from URL parser
class ParsedNewsUri {
  final String url;
  final String host;
  final String category;
  final String dateHint;
  final List<String> slugKeywords;
  final double priority;
  final String? imageUrl;
  final String? imageAlt;

  const ParsedNewsUri({
    required this.url,
    required this.host,
    required this.category,
    required this.dateHint,
    required this.slugKeywords,
    required this.priority,
    this.imageUrl,
    this.imageAlt,
  });

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'host': host,
      'category': category,
      'dateHint': dateHint,
      'slugKeywords': slugKeywords,
      'priority': priority,
      'imageUrl': imageUrl,
      'imageAlt': imageAlt,
    };
  }
}

/// Service to parse, blacklist, validate, prioritize, and compute Jaccard similarity
/// on news URLs BEFORE crawling their full details.
/// Designed with zero Flutter/Material UI dependencies to run on background Isolates.
class NewsUriParser {
  // ── URL Blacklist Patterns ──
  static const Set<String> blacklistedDomains = {
    'facebook.com', 'twitter.com', 'x.com', 'instagram.com', 'youtube.com',
    'linkedin.com', 'pinterest.com', 'tiktok.com', 't.co', 'bit.ly', 'goo.gl',
    'apps.apple.com', 'play.google.com', 'telegram.org', 't.me',
    'chat.whatsapp.com', 'wa.me', 'reddit.com',
    'snapchat.com', 'discord.com', 'discord.gg', 'slack.com'
  };

  static const List<String> blacklistedPathSegments = [
    'wp-admin', 'wp-content', 'wp-includes', 'wp-json', 'xmlrpc', 'feed',
    'tag', 'tags', 'categories', 'category', 'author', 'search', 'weather', 'prayer', 'privacy',
    'terms', 'contact', 'about', 'login', 'register', 'signup', 'signin',
    'logout', 'subscribe', 'donate', 'advertise', 'jobs', 'careers', 'press',
    'sitemap', 'rss', 'widgets', 'ads', 'promo', 'sponsor', 'banner', 'popup',
    'classified', 'opinions', 'weather-forecast', 'prayer-times', 'live',
    'program', 'programcategory', 'sportcategory', 'almaraatv', 'aljarida',
    'video', 'videos', 'multimedia', 'gallery', 'photos', 'opinion', 'opinions',
    'livestream', 'live-tv', 'tv', 'radio', 'podcast',
    'writer', 'admin', 'mondial', 'pollsarchive', 'details',
    'newsletter', 'latest-news', 'most-read', 'trending', 'popular',
    'home', 'index', 'archive', 'archives', 'page', 'pages'
  ];

  static const List<String> blacklistedExtensions = [
    '.css', '.js', '.json', '.xml', '.png', '.jpg', '.jpeg', '.gif', '.svg',
    '.webp', '.ico', '.pdf', '.zip', '.exe', '.dll', '.apk', '.bin', '.woff',
    '.woff2', '.ttf', '.eot', '.otf', '.mp3', '.mp4', '.webm', '.php'
  ];

  // ── Arabic & English Stop Words for Slug Tokenization ──
  static const Set<String> arabicStopWords = {
    'من', 'في', 'على', 'إلى', 'عن', 'مع', 'هذا', 'هذه', 'ذلك', 'أن', 'إن', 'لا',
    'ما', 'هو', 'هي', 'كان', 'كانت', 'تم', 'تمت', 'بين', 'بعد', 'قبل', 'خلال',
    'ثم', 'قد', 'كل', 'أو', 'أم', 'الذي', 'التي', 'الذين', 'عبر', 'إثر', 'منذ',
    'لقد', 'حيث', 'كيف', 'متى', 'أين', 'سوف', 'بسبب', 'حتى', 'معا', 'أيضا'
  };

  static const Set<String> englishStopWords = {
    'the', 'and', 'for', 'with', 'that', 'this', 'from', 'was', 'were', 'been',
    'have', 'has', 'had', 'not', 'but', 'they', 'our', 'your', 'him', 'her', 'its',
    'their', 'what', 'which', 'who', 'whom', 'when', 'where', 'why', 'how', 'all',
    'any', 'both', 'each', 'few', 'more', 'most', 'some', 'such', 'than', 'too',
    'very', 'just', 'also', 'into', 'over', 'under', 'again', 'once', 'then', 'here'
  };

  /// Validates if a URL is not blacklisted and is structurally a valid article URL.
  static bool isValidArticleUrl(String url) {
    if (url.isEmpty || !url.startsWith('http')) return false;

    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;

    // 1. Domain Check
    final domain = uri.host.toLowerCase().replaceAll('www.', '');
    if (blacklistedDomains.contains(domain)) return false;

    // 2. Query Params Check (social shares, logins etc.)
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('utm_source=') ||
        lowerUrl.contains('utm_medium=') ||
        lowerUrl.contains('ref=') ||
        lowerUrl.contains('share=') ||
        lowerUrl.contains('track=')) {
      // It might be a tracking URL, but if it is still a valid article we can strip tracking params
      // However, if it contains login / account references, discard it
      if (lowerUrl.contains('/login') || lowerUrl.contains('/signup') || lowerUrl.contains('/account')) {
        return false;
      }
    }

    // 3. Extension Check
    final path = uri.path.toLowerCase();
    for (final ext in blacklistedExtensions) {
      if (path.endsWith(ext)) return false;
    }
    // Also block general PHP scripts
    if (path.contains('.php')) return false;

    // 4. Blacklisted Path Segments Check
    for (final segment in blacklistedPathSegments) {
      if (path.contains('/$segment/') || path.contains('/$segment') || path.endsWith(segment)) {
        return false;
      }
    }

    // 5. Structural Check: article URLs should have path segments
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return false; // Homepage

    // If there is only 1 segment, it should be substantial (likely a slug)
    if (segments.length == 1 && segments.first.length < 10) {
      return false; // Likely a category / section index page
    }

    // 6. URL Pattern Check: reject obvious non-article patterns
    final pathLower = path.toLowerCase();
    if (pathLower.contains('author/') || pathLower.contains('authors/')) return false;
    if (pathLower.contains('user/') || pathLower.contains('profile/')) return false;
    if (pathLower.contains('tag/') || pathLower.contains('tags/')) return false;
    if (pathLower.contains('category/') || pathLower.contains('categories/')) return false;
    if (pathLower.contains('search?') || pathLower.contains('query=')) return false;
    if (pathLower.contains('login') || pathLower.contains('signup')) return false;
    if (pathLower.contains('newsletter')) return false;
    if (pathLower.contains('latest-news')) return false;
    if (pathLower.contains('most-read') || pathLower.contains('trending') || pathLower.contains('popular')) return false;
    
    // 7. Numeric-only segments after first path often indicate IDs rather than articles
    final numericSegments = segments.where((s) => RegExp(r'^\d+$').hasMatch(s)).length;
    if (segments.length >= 2 && numericSegments == segments.length - 1 && segments.first.length < 5) {
      return false;
    }

    return true;
  }

  /// Parses a valid article URL into metadata and priorities.
  static ParsedNewsUri parseUri(String url, {String? defaultCategory}) {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase().replaceAll('www.', '');

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    // 1. Extacted Category
    String category = defaultCategory ?? 'general';
    if (segments.length > 1) {
      // First substantial segment is often category (e.g. /politics/2026/...)
      final potentialCat = segments.first.toLowerCase();
      if (potentialCat.length > 2 && potentialCat.length < 15 && 
          !RegExp(r'^\d+$').hasMatch(potentialCat) && 
          !potentialCat.contains('-')) {
        category = potentialCat;
      }
    }

    // 2. Extracted Date Hints (e.g. looking for 4-digit years, months, days)
    String dateHint = '';
    final yearRegex = RegExp(r'^20\d{2}$');
    final monthDayRegex = RegExp(r'^\d{1,2}$');
    
    List<String> dateSegments = [];
    for (final segment in segments) {
      if (yearRegex.hasMatch(segment)) {
        dateSegments.add(segment);
      } else if (dateSegments.isNotEmpty && monthDayRegex.hasMatch(segment)) {
        dateSegments.add(segment);
      }
    }
    if (dateSegments.isNotEmpty) {
      dateHint = dateSegments.join('-');
    }

    // 3. Slug Keywords Extraction from the final segment
    List<String> slugKeywords = [];
    if (segments.isNotEmpty) {
      String lastSegment = segments.last;
      
      // Strip any extension if present
      if (lastSegment.contains('.')) {
        lastSegment = lastSegment.split('.').first;
      }

      // Percentage decoding (crucial for percentage encoded Arabic titles in URLs!)
      try {
        lastSegment = Uri.decodeComponent(lastSegment);
      } catch (_) {}

      // Normalize string: replace delimiters with spaces
      final cleanText = lastSegment
          .replaceAll(RegExp(r'[-_\+\s]+'), ' ')
          .replaceAll(RegExp(r'[^\w\u0600-\u06FF\s]'), '') // Keep alphanumeric + Arabic chars
          .toLowerCase();

      final words = cleanText.split(RegExp(r'\s+'));
      for (final word in words) {
        if (word.length >= 3 && 
            !arabicStopWords.contains(word) && 
            !englishStopWords.contains(word) &&
            !RegExp(r'^\d+$').hasMatch(word)) {
          slugKeywords.add(word);
        }
      }
    }

    // 4. Calculate News Priority Score (0.0 to 10.0 scale)
    double priority = 5.0; // Base score

    // Date/Freshness weight
    if (dateHint.isNotEmpty) {
      priority += 2.0; // Has a date signature -> more likely a fresh article
      if (dateHint.contains('2026') || dateHint.contains('2025')) {
        priority += 1.0; // Highly fresh year
      }
    }

    // Keyword relevance boost
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('breaking') || lowerUrl.contains('urgent') || lowerUrl.contains('عاجل')) {
      priority += 2.0; // Urgent news boost
    }
    if (lowerUrl.contains('news') || lowerUrl.contains('خبر') || lowerUrl.contains('أخبار')) {
      priority += 0.5; // General news signature
    }

    // Category relevance boost
    if (category == 'politics' || category == 'world' || category == 'business' || category == 'sports') {
      priority += 1.0; // Top-interest categories
    }

    // Path complexity: articles are typically deep, but not too deep
    if (segments.length >= 3 && segments.length <= 5) {
      priority += 0.5; // Sweet spot for typical news URL formats
    }

    // Rich slug boost: longer meaningful slugs imply rich titles
    if (slugKeywords.length >= 4) {
      priority += 1.0;
    } else if (slugKeywords.length < 2) {
      priority -= 1.5; // Very short slug is likely index or generic page
    }

    return ParsedNewsUri(
      url: url,
      host: host,
      category: category,
      dateHint: dateHint,
      slugKeywords: slugKeywords,
      priority: priority.clamp(0.0, 10.0),
    );
  }

  /// Calculates the Jaccard Similarity of slug keywords between two parsed URIs.
  /// Returns a score between 0.0 (no match) and 1.0 (identical match).
  static double calculateSimilarity(ParsedNewsUri a, ParsedNewsUri b) {
    if (a.slugKeywords.isEmpty || b.slugKeywords.isEmpty) return 0.0;

    final setA = a.slugKeywords.toSet();
    final setB = b.slugKeywords.toSet();

    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;

    double slugSim = intersection / union;

    // Image-based deduplication: If both have images from same URL but different slugs
    if (a.imageUrl != null && b.imageUrl != null && a.imageUrl == b.imageUrl) {
      // Same image detected - check if titles/slugs are different
      if (slugSim < 0.5) {
        // Same image but different content = likely duplicate, boost similarity
        return 0.7;
      }
    }

    return slugSim;
  }

  /// Groups similar URLs and returns a deduplicated, prioritized list of representative URLs.
  /// Runs fully in background isolates.
  ///
  /// Takes a List of raw URLs, resolves their categories, and applies Jaccard grouping
  /// to make the crawler extremely lite on repetitive work.
  static List<ParsedNewsUri> groupAndDeduplicate(
    List<String> rawUrls, {
    Map<String, String>? urlToCategoryMap,
    double similarityThreshold = 0.55,
  }) {
    final List<ParsedNewsUri> parsedList = [];

    // Step 1: Pre-validate and Parse all URLs
    for (final url in rawUrls) {
      if (!isValidArticleUrl(url)) continue;

      final category = urlToCategoryMap?[url];
      final parsed = parseUri(url, defaultCategory: category);
      parsedList.add(parsed);
    }

    // Step 2: Group identical/similar news articles using Jaccard Similarity on slugs
    final List<List<ParsedNewsUri>> clusters = [];

    for (final parsed in parsedList) {
      bool clustered = false;

      for (final cluster in clusters) {
        final representative = cluster.first;
        final similarity = calculateSimilarity(parsed, representative);

        if (similarity >= similarityThreshold) {
          cluster.add(parsed);
          clustered = true;
          break;
        }
      }

      if (!clustered) {
        clusters.add([parsed]);
      }
    }

    // Step 3: For each cluster, pick the highest priority URL as the representative
    final List<ParsedNewsUri> deduplicatedList = [];
    for (final cluster in clusters) {
      if (cluster.isEmpty) continue;

      // Sort cluster by priority descending, then by length of keywords to pick the best article slug
      cluster.sort((a, b) {
        final priorityComp = b.priority.compareTo(a.priority);
        if (priorityComp != 0) return priorityComp;
        return b.slugKeywords.length.compareTo(a.slugKeywords.length);
      });

      deduplicatedList.add(cluster.first);
    }

    // Step 4: Additional deduplication - check for same image URLs with different titles
    for (int i = 0; i < deduplicatedList.length; i++) {
      final current = deduplicatedList[i];
      if (current.imageUrl == null) continue;

      for (int j = i + 1; j < deduplicatedList.length; j++) {
        final next = deduplicatedList[j];
        if (next.imageUrl == null) continue;

        // Same image URL means duplicate - keep the one with higher priority
        if (current.imageUrl == next.imageUrl) {
          deduplicatedList.removeAt(j);
          j--;
        }
      }
    }

    // Step 5: Sort final representative articles by priority score descending
    deduplicatedList.sort((a, b) => b.priority.compareTo(a.priority));

    return deduplicatedList;
  }

  /// Isolate Entry Point: Groups and prioritizes URLs.
  /// Accepts Map of parameters to satisfy `compute` signature.
  static List<Map<String, dynamic>> runDeduplicationIsolate(Map<String, dynamic> params) {
    final rawUrls = List<String>.from(params['rawUrls'] ?? []);
    final urlToCategoryMap = (params['urlToCategoryMap'] as Map?)?.cast<String, String>();
    final threshold = (params['similarityThreshold'] as num?)?.toDouble() ?? 0.55;

    final results = groupAndDeduplicate(
      rawUrls,
      urlToCategoryMap: urlToCategoryMap,
      similarityThreshold: threshold,
    );

    return results.map((r) => r.toJson()).toList();
  }
}
