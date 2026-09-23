import 'dart:convert';

class NewsModel {
  final String url;
  final String urlHash;
  final String title;
  final String shortTitle;
  final String summary;
  final String content;
  final String imageUrl;
  final String category;
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

  NewsModel({
    required this.url,
    this.urlHash = '',
    required this.title,
    this.shortTitle = '',
    required this.summary,
    required this.content,
    required this.imageUrl,
    required this.category,
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
  });

  /// True if the article is synthesized from multiple sources or marked as blended
  bool get isBlended => sourceCount > 1 || sources.length > 1 || (structuredData['is_blended'] == true);

  /// Key highlights extracted across all contributing sources
  List<String> get highlights {
    if (structuredData['highlights'] is List) {
      return (structuredData['highlights'] as List).map((e) => e.toString()).toList();
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
        return {'url': item.toString(), 'name': _extractDomain(item.toString()), 'domain': _extractDomain(item.toString())};
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

    final d = _extractDomain(url);
    return [{
      'name': _domainToName(d),
      'domain': d,
      'url': url,
      'title': title,
      'publishDate': publishDate,
    }];
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
    if (lower.contains('tech') || lower.contains('تقنية') || lower.contains('تكنولوجيا')) {
      return 'https://images.unsplash.com/photo-1518770660439-4636190af475?w=500';
    }
    if (lower.contains('business') || lower.contains('اقتصاد') || lower.contains('أعمال')) {
      return 'https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=500';
    }
    if (lower.contains('health') || lower.contains('صحة') || lower.contains('طب')) {
      return 'https://images.unsplash.com/photo-1505751172876-fa1923c5c528?w=500';
    }
    if (lower.contains('science') || lower.contains('علم') || lower.contains('علوم')) {
      return 'https://images.unsplash.com/photo-1507679799987-c73779587ccf?w=500';
    }
    if (lower.contains('politic') || lower.contains('سياسة')) {
      return 'https://images.unsplash.com/photo-1529107386315-e1a2f48d54d6?w=500';
    }
    if (lower.contains('world') || lower.contains('العالم') || lower.contains('دولي')) {
      return 'https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=500';
    }
    if (lower.contains('culture') || lower.contains('ثقافة') || lower.contains('فن')) {
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

  static String hashUrl(String url) {
    final normalized = url.trim().toLowerCase();
    var hash = 0;
    for (final codeUnit in normalized.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x8000000000000000;
    }
    return '$hash';
  }

  factory NewsModel.fromJson(Map<String, dynamic> json, String url) {
    final cat = json['category'] ?? 'General';
    final rawHash = json['url_hash'] as String?;
    final computedHash = rawHash?.isNotEmpty == true ? rawHash! : hashUrl(url);
    return NewsModel(
      url: url,
      urlHash: computedHash,
      title: json['title'] ?? '',
      shortTitle: json['short_title'] ?? '',
      summary: json['summary'] ?? '',
      content: json['content'] ?? '',
      imageUrl: json['image_url'] ?? getFallbackImage(cat),
      category: cat,
      sentiment: (json['sentiment'] as num?)?.toDouble() ?? 0.0,
      keywords: List<String>.from(json['keywords'] ?? []),
      logs: json['logs'] ?? '',
      author: json['author'] ?? '',
      publishDate: json['publishDate'] ?? '',
      eventType: json['event_type'] ?? 'general',
      subcategory: json['subcategory'] ?? 'general',
      entities: json['entities'] != null ? List<String>.from(json['entities']) : const [],
      structuredData: json['structured_data'] != null
          ? Map<String, dynamic>.from(json['structured_data'])
          : (json['structuredData'] != null ? Map<String, dynamic>.from(json['structuredData']) : const {}),
      intelligenceJson: json['intelligence_json'] ?? '',
      metaTags: json['meta_tags'] != null ? Map<String, dynamic>.from(json['meta_tags']) : const {},
      hashtags: json['hashtags'] ?? '',
      youtubeVideoId: json['youtube_video_id'] ?? '',
      instagramVideoId: json['instagram_video_id'] ?? '',
      twitterVideoUrl: json['twitter_video_url'] ?? '',
      imageId: json['image_id'] ?? '',
      sourceCount: json['source_count'] ?? 1,
      sources: json['sources'] != null ? List<String>.from(json['sources']) : const [],
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
      sentiment: sentiment ?? this.sentiment,
      keywords: keywords ?? this.keywords,
      logs: logs ?? this.logs,
      author: author ?? this.author,
      publishDate: publishDate ?? this.publishDate,
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
      intelligenceJson: intelligenceJson ?? this.intelligenceJson,
    );
    updated.relatedArticles = relatedArticles ?? this.relatedArticles;
    return updated;
  }
}
