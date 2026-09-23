import 'dart:convert';

class NewsIntelligenceModel {
  final String url;
  final String title;
  final String summary;
  final String content;
  final String imageUrl;
  final String category;
  final double sentiment;
  final List<String> keywords;
  final List<ExtractedEntity> entities;
  final String eventType;
  final String subcategory;
  final Map<String, dynamic> structuredData;
  final String author;
  final String publishDate;
  final String intelligenceJson;
  final List<String> semanticTags;
  final String geopoliticalRegion;
  final double confidence;
  final List<String> datesIso;
  final Map<String, dynamic> sportsData;

  NewsIntelligenceModel({
    required this.url,
    required this.title,
    required this.summary,
    required this.content,
    required this.imageUrl,
    required this.category,
    required this.sentiment,
    required this.keywords,
    required this.entities,
    required this.eventType,
    required this.subcategory,
    required this.structuredData,
    required this.author,
    required this.publishDate,
    required this.intelligenceJson,
    this.semanticTags = const [],
    this.geopoliticalRegion = 'global',
    this.confidence = 0.5,
    this.datesIso = const [],
    this.sportsData = const {},
  });

  factory NewsIntelligenceModel.fromJson(Map<String, dynamic> json, String url) {
    final entities = (json['entities'] as List<dynamic>?)?.map((e) => ExtractedEntity.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final structuredData = (json['structured_data'] as Map<String, dynamic>?) ?? {};

    final intelligenceJson = jsonEncode({
      'entities': entities.map((e) => e.toJson()).toList(),
      'event_type': json['event_type'] ?? 'general',
      'sentiment': json['sentiment'] ?? 0.0,
      'category': json['category'] ?? 'general',
      'subcategory': json['subcategory'] ?? 'general',
      'structured_data': structuredData,
    });

    return NewsIntelligenceModel(
      url: url,
      title: json['title'] ?? '',
      summary: json['summary'] ?? '',
      content: json['content'] ?? '',
      imageUrl: json['image_url'] ?? '',
      category: json['category'] ?? 'general',
      sentiment: (json['sentiment'] as num?)?.toDouble() ?? 0.0,
      keywords: List<String>.from(json['keywords'] ?? []),
      entities: entities,
      eventType: json['event_type'] ?? 'general',
      subcategory: json['subcategory'] ?? 'general',
      structuredData: structuredData,
      author: json['author'] ?? '',
      publishDate: json['publish_date'] ?? '',
      intelligenceJson: intelligenceJson,
      semanticTags: List<String>.from(structuredData['semantic_tags'] ?? []),
      geopoliticalRegion: structuredData['geopolitical_region'] ?? 'global',
      confidence: (structuredData['confidence'] as num?)?.toDouble() ?? 0.5,
      datesIso: List<String>.from(structuredData['dates']?.map((d) => d['iso']) ?? []),
      sportsData: structuredData['sports_data'] ?? {},
    );
  }
}

class ExtractedEntity {
  final String type;
  final String value;

  ExtractedEntity({required this.type, required this.value});

  factory ExtractedEntity.fromJson(Map<String, dynamic> json) {
    return ExtractedEntity(
      type: json['type'] as String,
      value: json['value'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'type': type, 'value': value};
}
