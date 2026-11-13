import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:yallanews/services/ai_language_ext.dart';

class NewsModel {
  final String url;
  final String urlHash;
  final String title;
  final String shortTitle;
  final String summary;
  final String content;
  final String imageUrl;
  final String category;
  final String language;
  final double sentiment;
  final List<String> keywords;
  final String logs;
  final String author;
  final String publishDate;
  final String eventType;
  final String subcategory;
  final List<String> entities;
  final Map<String, dynamic> structuredData;
  final String intelligenceJson;
  final Map<String, dynamic> metaTags;
  final String hashtags;
  final String youtubeVideoId;
  final String instagramVideoId;
  final String twitterVideoUrl;
  final String imageId;
  List<NewsModel> relatedArticles = [];

  final int sourceCount;
  final List<String> sources;
  final bool
  isFresh; // true if publish date is within last 3 months (News & Magazines policy)

  /// Original publisher name (source_name). Never fabricated: empty when unknown.
  final String sourceName;

  /// Original publisher website (source_url). Empty when unknown.
  final String sourceUrl;

  /// Original author name (author_name). Empty when not provided by the publisher.
  final String authorName;

  /// Original publication timestamp (published_at), epoch ms or ISO-8601 string.
  final String publishedAt;

  /// Last update timestamp (updated_at), epoch ms or ISO-8601 string.
  final String updatedAt;

  /// Image credit line provided by the publisher (image_credit).
  final String imageCredit;

  /// Source URL of the article image (image_source_url).
  final String imageSourceUrl;

  /// Geographic coordinates for map display
  final double? latitude;
  final double? longitude;

  /// AI-generated summary
  final String aiSummary;

  /// Translations (lang_code -> translated_content)
  final Map<String, String> translations;

  /// Relevance score for personalized feed (0.0 - 1.0)
  final double relevanceScore;

  NewsModel({
    required this.url,
    this.urlHash = '',
    required this.title,
    this.shortTitle = '',
    required this.summary,
    required this.content,
    required this.imageUrl,
    required this.category,
    this.language = '',
    required this.sentiment,
    required this.keywords,
    required this.logs,
    required this.author,
    required this.publishDate,
    this.eventType = 'general',
    this.subcategory = 'general',
    this.entities = const [],
    this.structuredData = const {},
    this.intelligenceJson = '',
    this.metaTags = const {},
    this.hashtags = '',
    this.youtubeVideoId = '',
    this.instagramVideoId = '',
    this.twitterVideoUrl = '',
    this.imageId = '',
    this.sourceCount = 1,
    this.sources = const [],
    this.isFresh = true,
    this.sourceName = '',
    this.sourceUrl = '',
    this.authorName = '',
    this.publishedAt = '',
    this.updatedAt = '',
    this.imageCredit = '',
    this.imageSourceUrl = '',
    this.latitude,
    this.longitude,
    this.aiSummary = '',
    this.translations = const {},
    this.relevanceScore = 0.5,
  });

  /// True if the article is synthesized from multiple sources or marked as blended
  bool get isBlended =>
      sourceCount > 1 ||
      sources.length > 1 ||
      (structuredData['is_blended'] == true);

  /// True if the article's publish date is within the last 3 months (News & Magazines policy).
  bool get isContentFresh => isWithinMonths(3);

  /// True if the article's publish date is within the last [months] months.
  bool _isPublishDateWithinMonths(int months) {
    if (publishDate.isEmpty)
      return true; // unknown date — don't reject, but flag
    final parsed = _parsePublishDate(publishDate);
    if (parsed == null)
      return true; // unparseable — keep rather than lose content
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month - months, now.day);
    return parsed.isAfter(cutoff);
  }

  /// Parsed original publication date, or null when missing/malformed.
  /// The import/crawler date is never used as a substitute.
  DateTime? get publicationDate =>
      _parsePublishDate(publishDate.isNotEmpty ? publishDate : publishedAt);

  /// True if the article's publish date is within the last [days] days.
  bool isWithinDays(int days) {
    final parsed = publicationDate;
    if (parsed == null)
      return true; // unknown date — keep rather than lose content
    if (parsed.isAfter(DateTime.now()))
      return false; // future date — treat as not verifiably current
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day - days);
    return parsed.isAfter(cutoff);
  }

  /// True if the article's publish date is within the last [months] months.
  bool isWithinMonths(int months) {
    final parsed = publicationDate;
    if (parsed == null) return true;
    if (parsed.isAfter(DateTime.now())) return false;
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month - months, now.day);
    return parsed.isAfter(cutoff);
  }

  /// News & Magazines policy: current-events (breaking/urgent) articles must
  /// be no more than [currentEventsMaxAgeDays] days old; other news and
  /// magazine content must be no more than [generalMaxAgeMonths] months old.
  /// Missing or unparseable dates are kept (not fabricated); future dates are
  /// never artificially adjusted.
  bool isFreshForFeed({
    int currentEventsMaxAgeDays = 30,
    int generalMaxAgeMonths = 3,
  }) {
    final parsed = publicationDate;
    if (parsed == null) return true; // unknown date — do not reject content
    if (parsed.isAfter(DateTime.now())) return true; // future date — keep as-is
    final now = DateTime.now();
    final cutoff = isCurrentEvent
        ? DateTime(now.year, now.month, now.day - currentEventsMaxAgeDays)
        : DateTime(now.year, now.month - generalMaxAgeMonths, now.day);
    return parsed.isAfter(cutoff);
  }

  /// True when the article looks like current-events (breaking/urgent) news.
  bool get isCurrentEvent {
    final et = eventType.toLowerCase();
    if (et == 'breaking' ||
        et == 'urgent' ||
        et == 'live' ||
        et == 'breakingnews')
      return true;
    final cat = category.toLowerCase();
    if (cat == 'breaking' ||
        cat == 'breakingnews' ||
        cat.contains('breaking') ||
        cat.contains('عاجل'))
      return true;
    return false;
  }

  /// Human-readable source name: the original publisher name when available,
  /// otherwise the domain of the article URL. Never a fabricated publisher name.
  String get displaySourceName {
    if (sourceName.isNotEmpty) return sourceName;
    final d = _extractDomain(sourceUrl.isNotEmpty ? sourceUrl : url);
    return d.isNotEmpty ? d : '';
  }

  static DateTime? _parsePublishDate(String raw) {
    if (raw.isEmpty) return null;
    var value = raw.trim();
    if (value.contains('T') && !RegExp(r'^\d+$').hasMatch(value)) {
      value = value.split('T')[0];
    }
    DateTime? dateTime;
    if (RegExp(r'^\d{10,}$').hasMatch(value)) {
      final epoch = int.tryParse(value);
      if (epoch == null) return null;
      dateTime = epoch > 100000000000
          ? DateTime.fromMillisecondsSinceEpoch(epoch)
          : DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
    } else {
      dateTime = DateTime.tryParse(value);
    }
    return dateTime;
  }

  static bool computeFreshness(String publishDate) {
    if (publishDate.isEmpty) return true;
    final parsed = _parsePublishDate(publishDate);
    if (parsed == null) return true;
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month - 3, now.day);
    return parsed.isAfter(cutoff);
  }

  /// Key highlights extracted across all contributing sources
  List<String> get highlights {
    if (structuredData['highlights'] is List) {
      return (structuredData['highlights'] as List)
          .map((e) => e.toString())
          .toList();
    }
    return const [];
  }

  /// Structured source attributions (outlet name, domain, title, url, publishDate)
  List<Map<String, dynamic>> get sourceAttributions {
    if (structuredData['source_attributions'] is List) {
      final list = structuredData['source_attributions'] as List;
      return list.map((item) {
        if (item is Map) {
          return Map<String, dynamic>.from(item);
        }
        return {
          'url': item.toString(),
          'name': _extractDomain(item.toString()),
          'domain': _extractDomain(item.toString()),
        };
      }).toList();
    }

    if (sources.isNotEmpty) {
      return sources.map((sUrl) {
        final domain = _extractDomain(sUrl);
        return {
          'name': _domainToName(domain),
          'domain': domain,
          'url': sUrl,
          'title': sUrl == url ? title : '',
          'publishDate': publishDate,
        };
      }).toList();
    }

    final d = _extractDomain(sourceUrl.isNotEmpty ? sourceUrl : url);
    return [
      {
        'name': sourceName.isNotEmpty ? sourceName : _domainToName(d),
        'domain': d,
        'url': sourceUrl.isNotEmpty ? sourceUrl : url,
        'title': title,
        'publishDate': publishDate,
        'author': authorName,
      },
    ];
  }

  static String extractDomain(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      var host = uri.host.toLowerCase();
      if (host.startsWith('www.')) host = host.substring(4);
      return host.isNotEmpty ? host : rawUrl;
    } catch (_) {
      return rawUrl;
    }
  }

  static String domainToName(String domain) {
    final lc = domain.toLowerCase();
    if (lc.contains('hespress')) return 'هسبريس';
    if (lc.contains('le360')) return 'Le360';
    if (lc.contains('alyaoum24')) return 'اليوم 24';
    if (lc.contains('almountakhab')) return 'المنتخب';
    if (lc.contains('chouftv')) return 'شوف تيفي';
    if (lc.contains('febrayer')) return 'فبراير';
    if (lc.contains('rue20')) return 'زنقة 20';
    if (lc.contains('barlamane')) return 'برلمان.كوم';
    if (lc.contains('al3omk')) return 'العمق المغربي';
    if (lc.contains('ifada')) return 'إفادة';
    if (lc.contains('aljazeera')) return 'الجزيرة';
    if (lc.contains('alarabiya')) return 'العربية';
    if (lc.contains('skynews')) return 'سكاي نيوز';
    if (lc.contains('bbc')) return 'BBC عربي';
    if (lc.contains('france24')) return 'فرانس 24';
    return domain.isNotEmpty ? domain : 'مصدر إخباري';
  }

  static String _extractDomain(String rawUrl) => extractDomain(rawUrl);
  static String _domainToName(String domain) => domainToName(domain);

  static String getFallbackImage(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('sport') || lower.contains('رياضة')) {
      return 'https://images.unsplash.com/photo-1461896836934-ffe607ba8211?w=500';
    }
    if (lower.contains('tech') ||
        lower.contains('تقنية') ||
        lower.contains('تكنولوجيا')) {
      return 'https://images.unsplash.com/photo-1518770660439-4636190af475?w=500';
    }
    if (lower.contains('business') ||
        lower.contains('اقتصاد') ||
        lower.contains('أعمال')) {
      return 'https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=500';
    }
    if (lower.contains('health') ||
        lower.contains('صحة') ||
        lower.contains('طب')) {
      return 'https://images.unsplash.com/photo-1505751172876-fa1923c5c528?w=500';
    }
    if (lower.contains('science') ||
        lower.contains('علم') ||
        lower.contains('علوم')) {
      return 'https://images.unsplash.com/photo-1507679799987-c73779587ccf?w=500';
    }
    if (lower.contains('politic') || lower.contains('سياسة')) {
      return 'https://images.unsplash.com/photo-1529107386315-e1a2f48d54d6?w=500';
    }
    if (lower.contains('world') ||
        lower.contains('العالم') ||
        lower.contains('دولي')) {
      return 'https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=500';
    }
    if (lower.contains('culture') ||
        lower.contains('ثقافة') ||
        lower.contains('فن')) {
      return 'https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=500';
    }
    if (lower.contains('islamic') || lower.contains('إسلاميات')) {
      return 'https://images.unsplash.com/photo-1533561797506-022eacd4f4e8?w=500';
    }
    if (lower.contains('woman') || lower.contains('مرأة')) {
      return 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=500';
    }
    return 'https://images.unsplash.com/photo-1504711434969-e33886168f5c?w=500';
  }

  static List<String> _parseKeywords(dynamic value) {
    if (value == null) return [];
    if (value is List<String>) return value;
    if (value is List) return value.cast<String>();
    if (value is String) {
      return value.split(',').where((s) => s.trim().isNotEmpty).map((s) => s.trim()).toList();
    }
    return [];
  }

  static Map<String, String> _parseStringMap(dynamic value) {
    if (value == null) return const {};
    if (value is Map<String, String>) return value;
    if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v.toString()));
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
      return const {};
    }
    return const {};
  }

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];
    if (value is List<String>) return value;
    if (value is List) return value.cast<String>();
    if (value is String) {
      return value.split(',').where((s) => s.trim().isNotEmpty).map((s) => s.trim()).toList();
    }
    return [];
  }

  static String hashUrl(String url) {
    final normalized = url.trim().toLowerCase();
    var hash = 0;
    for (final codeUnit in normalized.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x8000000000000000;
    }
    return '$hash';
  }

  static String resolveImageUrl(String rawImageUrl, String pageUrl) {
    final value = rawImageUrl
        .trim()
        .replaceAll('&amp;', '&')
        .replaceAll('&#x2F;', '/')
        .replaceAll('&quot;', '"')
        .replaceAll(r'\/', '/');
    if (value.isEmpty) return '';

    final pageUri = Uri.tryParse(pageUrl);
    final imageUri = Uri.tryParse(value);
    if (imageUri == null) return '';
    final resolved = imageUri.hasScheme ? imageUri : pageUri?.resolve(value);
    if (resolved == null ||
        (resolved.scheme != 'http' && resolved.scheme != 'https') ||
        resolved.host.isEmpty) {
      return '';
    }
    return resolved.toString();
  }

  factory NewsModel.fromJson(Map<String, dynamic> json, String url) {
    final cat = json['category'] ?? 'General';
    final rawHash = json['url_hash'] as String?;
    final computedHash = rawHash?.isNotEmpty == true ? rawHash! : hashUrl(url);
    final pubDate = json['publishDate'] ?? '';
    final rawSource = json['source'];
    final source = rawSource is Map
        ? Map<String, dynamic>.from(rawSource)
        : const <String, dynamic>{};
    return NewsModel(
      url: url,
      urlHash: computedHash,
      title: json['title'] ?? '',
      shortTitle: json['short_title'] ?? '',
      summary: json['summary'] ?? '',
      content: json['content'] ?? '',
      imageUrl: json['image_url'] ?? getFallbackImage(cat),
      category: cat,
      language: (json['language'] ?? json['lang'] ?? '').toString(),
      sentiment: (json['sentiment'] as num?)?.toDouble() ?? 0.0,
      keywords: _parseKeywords(json['keywords']),
      logs: json['logs'] ?? '',
      author: json['author'] ?? '',
      authorName: json['author_name'] ?? '',
      publishDate: pubDate,
      publishedAt: json['published_at'] ?? pubDate,
      updatedAt: json['updated_at'] ?? '',
      sourceName:
          (json['source_name'] ?? json['sourceName'] ?? source['name'] ?? '')
              .toString(),
      sourceUrl:
          (json['source_url'] ?? json['sourceUrl'] ?? source['url'] ?? '')
              .toString(),
      imageCredit: json['image_credit'] ?? '',
      imageSourceUrl: json['image_source_url'] ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      aiSummary: json['ai_summary'] ?? '',
      translations: _parseStringMap(json['translations']),
      relevanceScore: (json['relevance_score'] as num?)?.toDouble() ?? 0.5,
      eventType: json['event_type'] ?? 'general',
      subcategory: json['subcategory'] ?? 'general',
      entities: _parseStringList(json['entities']),
      structuredData: json['structured_data'] != null
          ? _parseStringMap(json['structured_data'])
          : (json['structuredData'] != null
                ? _parseStringMap(json['structuredData'])
                : const {}),
      intelligenceJson: json['intelligence_json'] ?? '',
      metaTags: _parseStringMap(json['meta_tags']),
      hashtags: json['hashtags'] ?? '',
      youtubeVideoId: json['youtube_video_id'] ?? '',
      instagramVideoId: json['instagram_video_id'] ?? '',
      twitterVideoUrl: json['twitter_video_url'] ?? '',
      imageId: json['image_id'] ?? '',
      sourceCount: (json['source_count'] as num?)?.toInt() ?? 1,
      sources: _parseStringList(json['sources']),
      isFresh: computeFreshness(pubDate),
    );
  }

  factory NewsModel.empty(String url) {
    return NewsModel(
      url: url,
      urlHash: hashUrl(url),
      title: 'Loading News...',
      shortTitle: '',
      summary: '',
      content: '',
      imageUrl: '',
      category: 'General',
      sentiment: 0.0,
      keywords: [],
      logs: '',
      author: '',
      publishDate: '',
      eventType: 'general',
      subcategory: 'general',
      intelligenceJson: '',
      hashtags: '',
      youtubeVideoId: '',
      instagramVideoId: '',
      twitterVideoUrl: '',
      imageId: '',
      isFresh: true,
      aiSummary: '',
      translations: const {},
      relevanceScore: 0.5,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'url_hash': urlHash,
      'title': title,
      'short_title': shortTitle,
      'summary': summary,
      'content': content,
      'image_url': imageUrl,
      'category': category,
      'language': language,
      'sentiment': sentiment,
      'keywords': keywords,
      'logs': logs,
      'author': author,
      'publishDate': publishDate,
      'eventType': eventType,
      'subcategory': subcategory,
      'entities': entities,
      'structuredData': structuredData,
      'intelligenceJson': intelligenceJson,
      'meta_tags': metaTags,
      'hashtags': hashtags,
      'youtube_video_id': youtubeVideoId,
      'instagram_video_id': instagramVideoId,
      'twitter_video_url': twitterVideoUrl,
      'image_id': imageId,
      'source_count': sourceCount,
      'sources': sources,
      'is_fresh': isFresh,
      'source_name': sourceName,
      'source_url': sourceUrl,
      'author_name': authorName,
      'published_at': publishedAt,
      'updated_at': updatedAt,
      'image_credit': imageCredit,
      'image_source_url': imageSourceUrl,
      'latitude': latitude,
      'longitude': longitude,
      'ai_summary': aiSummary,
      'translations': translations,
      'relevance_score': relevanceScore,
    };
  }

  NewsModel copyWith({
    String? url,
    String? urlHash,
    String? title,
    String? shortTitle,
    String? summary,
    String? content,
    String? imageUrl,
    String? category,
    String? language,
    double? sentiment,
    List<String>? keywords,
    String? logs,
    String? author,
    String? publishDate,
    String? eventType,
    String? subcategory,
    List<String>? entities,
    Map<String, dynamic>? structuredData,
    Map<String, dynamic>? metaTags,
    String? hashtags,
    String? youtubeVideoId,
    String? instagramVideoId,
    String? twitterVideoUrl,
    String? imageId,
    int? sourceCount,
    List<String>? sources,
    String? intelligenceJson,
    bool? isFresh,
    String? sourceName,
    String? sourceUrl,
    String? authorName,
    String? publishedAt,
    String? updatedAt,
    String? imageCredit,
    String? imageSourceUrl,
    double? latitude,
    double? longitude,
    String? aiSummary,
    Map<String, String>? translations,
    double? relevanceScore,
    List<NewsModel>? relatedArticles,
  }) {
    final updated = NewsModel(
      url: url ?? this.url,
      urlHash: urlHash ?? this.urlHash,
      title: title ?? this.title,
      shortTitle: shortTitle ?? this.shortTitle,
      summary: summary ?? this.summary,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      language: language ?? this.language,
      sentiment: sentiment ?? this.sentiment,
      keywords: keywords ?? this.keywords,
      logs: logs ?? this.logs,
      author: author ?? this.author,
      authorName: authorName ?? this.authorName,
      publishDate: publishDate ?? this.publishDate,
      publishedAt: publishedAt ?? this.publishedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      eventType: eventType ?? this.eventType,
      subcategory: subcategory ?? this.subcategory,
      entities: entities ?? this.entities,
      structuredData: structuredData ?? this.structuredData,
      metaTags: metaTags ?? this.metaTags,
      hashtags: hashtags ?? this.hashtags,
      youtubeVideoId: youtubeVideoId ?? this.youtubeVideoId,
      instagramVideoId: instagramVideoId ?? this.instagramVideoId,
      twitterVideoUrl: twitterVideoUrl ?? this.twitterVideoUrl,
      imageId: imageId ?? this.imageId,
      sourceCount: sourceCount ?? this.sourceCount,
      sources: sources ?? this.sources,
      sourceName: sourceName ?? this.sourceName,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      imageCredit: imageCredit ?? this.imageCredit,
      imageSourceUrl: imageSourceUrl ?? this.imageSourceUrl,
      intelligenceJson: intelligenceJson ?? this.intelligenceJson,
      isFresh: isFresh ?? this.isFresh,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      aiSummary: aiSummary ?? this.aiSummary,
      translations: translations ?? this.translations,
      relevanceScore: relevanceScore ?? this.relevanceScore,
    );
    updated.relatedArticles = relatedArticles ?? this.relatedArticles;
    return updated;
  }
}
