// News Pipeline Configuration and Service
// Dart wrapper for C++ NewsPipeline with Flutter integration

import 'dart:convert';
import 'package:yallanews/services/ai_service.dart';
import 'package:yallanews/services/ai_ffi.dart'
    show
        YallaAIService,
        YallaProviderConfig,
        YallaProviderType,
        NewsPipelineHandle;

/// Pipeline configuration
class NewsPipelineConfig {
  final bool enableAI;
  final String aiModel;
  final bool enableSummarization;
  final int summaryMaxLength;
  final bool enableTranslation;
  final List<String> targetLanguages;
  final bool enableDedup;
  final double dedupThreshold;
  final bool enableClassification;
  final bool enableEntities;
  final bool enableClustering;
  final int clusterAlgorithm;
  final double clusterEps;
  final int clusterMinSamples;
  final int maxArticlesPerProvider;
  final bool enableFactcheck;
  final List<YallaProviderConfig> providers;

  NewsPipelineConfig({
    this.enableAI = true,
    this.aiModel = 'qwen3-0.6b-q4',
    this.enableSummarization = true,
    this.summaryMaxLength = 150,
    this.enableTranslation = true,
    this.targetLanguages = const ['ar', 'en', 'fr'],
    this.enableDedup = true,
    this.dedupThreshold = 0.85,
    this.enableClassification = true,
    this.enableEntities = true,
    this.enableClustering = true,
    this.clusterAlgorithm = 1,
    this.clusterEps = 0.5,
    this.clusterMinSamples = 2,
    this.maxArticlesPerProvider = 50,
    this.enableFactcheck = true,
    required this.providers,
  });

  String toJson() {
    return jsonEncode({
      'enable_ai': enableAI,
      'ai_model': aiModel,
      'enable_summarization': enableSummarization,
      'summary_max_length': summaryMaxLength,
      'enable_translation': enableTranslation,
      'target_languages': targetLanguages,
      'enable_dedup': enableDedup,
      'dedup_threshold': dedupThreshold,
      'enable_classification': enableClassification,
      'enable_entities': enableEntities,
      'enable_clustering': enableClustering,
      'cluster_algorithm': clusterAlgorithm,
      'cluster_eps': clusterEps,
      'cluster_min_samples': clusterMinSamples,
      'max_articles_per_provider': maxArticlesPerProvider,
      'enable_factcheck': enableFactcheck,
      'providers': providers.map((p) => {
        'type': p.type.index,
        'provider_id': p.providerId,
        'api_key': p.apiKey,
        'base_url': p.baseUrl,
        'timeout_ms': p.timeoutMs,
        'rate_limit_rpm': p.rateLimitRpm,
        'max_retries': p.maxRetries,
        'custom_params': p.customParams,
      }).toList(),
    });
  }
}

/// Pipeline article from C++
class PipelineArticle {
  final String url;
  final String title;
  final String summary;
  final String content;
  final String imageUrl;
  final String category;
  final double sentiment;
  final List<String> keywords;
  final String language;
  final int publishDate;
  final String author;
  final String sourceUrl;
  final String providerId;
  final String providerName;
  final String license;
  final String attributionUrl;
  final Map<String, dynamic> rawProviderData;
  final String normalizedTitle;
  final String normalizedContent;
  final String aiSummary;
  final Map<String, String> translations;
  final List<PipelineEntity> entities;
  final String subcategory;
  final int clusterId;
  final bool isDuplicate;
  final double duplicateSimilarity;
  final bool verified;
  final String verificationSource;
  final double relevanceScore;

  PipelineArticle({
    required this.url,
    required this.title,
    required this.summary,
    required this.content,
    required this.imageUrl,
    required this.category,
    required this.sentiment,
    required this.keywords,
    required this.language,
    required this.publishDate,
    required this.author,
    required this.sourceUrl,
    required this.providerId,
    required this.providerName,
    required this.license,
    required this.attributionUrl,
    required this.rawProviderData,
    required this.normalizedTitle,
    required this.normalizedContent,
    required this.aiSummary,
    required this.translations,
    required this.entities,
    required this.subcategory,
    required this.clusterId,
    required this.isDuplicate,
    required this.duplicateSimilarity,
    required this.verified,
    required this.verificationSource,
    required this.relevanceScore,
  });

  factory PipelineArticle.fromJson(Map<String, dynamic> json) {
    return PipelineArticle(
      url: json['url'] ?? '',
      title: json['title'] ?? '',
      summary: json['summary'] ?? '',
      content: json['content'] ?? '',
      imageUrl: json['image_url'] ?? '',
      category: json['category'] ?? '',
      sentiment: (json['sentiment'] ?? 0.0).toDouble(),
      keywords: (json['keywords'] as List<dynamic>?)?.cast<String>() ?? [],
      language: json['language'] ?? '',
      publishDate: json['publish_date'] ?? 0,
      author: json['author'] ?? '',
      sourceUrl: json['source_url'] ?? '',
      providerId: json['provider_id'] ?? '',
      providerName: json['provider_name'] ?? '',
      license: json['license'] ?? '',
      attributionUrl: json['attribution_url'] ?? '',
      rawProviderData: json['raw_provider_data'] ?? {},
      normalizedTitle: json['normalized_title'] ?? '',
      normalizedContent: json['normalized_content'] ?? '',
      aiSummary: json['ai_summary'] ?? '',
      translations: (json['translations'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? {},
      entities: (json['entities'] as List<dynamic>?)?.map((e) => PipelineEntity.fromJson(e)).toList() ?? [],
      subcategory: json['subcategory'] ?? '',
      clusterId: json['cluster_id'] ?? -1,
      isDuplicate: json['is_duplicate'] ?? false,
      duplicateSimilarity: (json['duplicate_similarity'] ?? 0.0).toDouble(),
      verified: json['verified'] ?? false,
      verificationSource: json['verification_source'] ?? '',
      relevanceScore: (json['relevance_score'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'title': title,
      'summary': summary,
      'content': content,
      'image_url': imageUrl,
      'category': category,
      'sentiment': sentiment,
      'keywords': keywords,
      'language': language,
      'publish_date': publishDate,
      'author': author,
      'source_url': sourceUrl,
      'provider_id': providerId,
      'provider_name': providerName,
      'license': license,
      'attribution_url': attributionUrl,
      'raw_provider_data': rawProviderData,
      'normalized_title': normalizedTitle,
      'normalized_content': normalizedContent,
      'ai_summary': aiSummary,
      'translations': translations,
      'entities': entities.map((e) => e.toJson()).toList(),
      'subcategory': subcategory,
      'cluster_id': clusterId,
      'is_duplicate': isDuplicate,
      'duplicate_similarity': duplicateSimilarity,
      'verified': verified,
      'verification_source': verificationSource,
      'relevance_score': relevanceScore,
    };
  }
}

/// Pipeline entity
class PipelineEntity {
  final String type;
  final String value;
  final String canonical;
  final String language;
  final double confidence;

  PipelineEntity({
    required this.type,
    required this.value,
    required this.canonical,
    required this.language,
    required this.confidence,
  });

  factory PipelineEntity.fromJson(Map<String, dynamic> json) {
    return PipelineEntity(
      type: json['type'] ?? '',
      value: json['value'] ?? '',
      canonical: json['canonical'] ?? '',
      language: json['language'] ?? '',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'value': value,
      'canonical': canonical,
      'language': language,
      'confidence': confidence,
    };
  }
}

/// Pipeline stage result
class StageResult {
  final bool success;
  final String errorMessage;
  final int articlesIn;
  final int articlesOut;
  final int durationMs;
  final Map<String, dynamic> metadata;

  StageResult({
    required this.success,
    required this.errorMessage,
    required this.articlesIn,
    required this.articlesOut,
    required this.durationMs,
    required this.metadata,
  });

  factory StageResult.fromJson(Map<String, dynamic> json) {
    return StageResult(
      success: json['success'] ?? false,
      errorMessage: json['error_message'] ?? '',
      articlesIn: json['articles_in'] ?? 0,
      articlesOut: json['articles_out'] ?? 0,
      durationMs: json['duration_ms'] ?? 0,
      metadata: json['metadata'] ?? {},
    );
  }
}

/// Pipeline result
class PipelineResult {
  final bool success;
  final String errorMessage;
  final List<PipelineArticle> articles;
  final List<StageResult> stageResults;
  final int totalDurationMs;

  PipelineResult({
    required this.success,
    required this.errorMessage,
    required this.articles,
    required this.stageResults,
    required this.totalDurationMs,
  });

  factory PipelineResult.fromJson(String jsonStr) {
    final json = jsonDecode(jsonStr);
    return PipelineResult(
      success: json['success'] ?? false,
      errorMessage: json['error_message'] ?? '',
      articles: (json['articles'] as List<dynamic>?)
          ?.map((a) => PipelineArticle.fromJson(a))
          .toList() ?? [],
      stageResults: (json['stages'] as List<dynamic>?)
          ?.map((s) => StageResult.fromJson(s))
          .toList() ?? [],
      totalDurationMs: json['total_duration_ms'] ?? 0,
    );
  }
}

/// News Pipeline Service - Dart wrapper for C++ NewsPipeline
class NewsPipelineService {
  static NewsPipelineService? _instance;
  static NewsPipelineService get instance => _instance ??= NewsPipelineService._();
  NewsPipelineService._();

  final AIService _aiService = AIService.instance;
  NewsPipelineHandle? _pipeline;
  bool _isRunning = false;
  String? _lastError;
  
  // Progress callbacks
  Function(String stage, int progress, String message)? onProgress;
  Function(PipelineResult result)? onComplete;

  bool get isRunning => _isRunning;
  String? get lastError => _lastError;

  Future<bool> initialize(NewsPipelineConfig config) async {
    if (_pipeline != null) {
      await dispose();
    }

    try {
      // Ensure AI service is ready
      if (config.enableAI) {
        await _aiService.initialize();
        if (!_aiService.isModelLoaded) {
          await _aiService.loadModel(_aiService.currentModel);
        }
        if (!_aiService.isReady) {
          _lastError = 'AI service not ready';
          return false;
        }
      }

      // Create pipeline via C++ FFI
      _pipeline = YallaAIService.createNewsPipeline(config.toJson());
      if (_pipeline == null) {
        _lastError = 'Failed to create pipeline';
        return false;
      }

      // Set callbacks
      if (onProgress != null) {
        YallaAIService.setPipelineProgressCallback(_pipeline!, (stage, progress, message) {
          onProgress!(stage, progress, message);
        });
      }

      if (onComplete != null) {
        YallaAIService.setPipelineCompletionCallback(_pipeline!, (resultJson) {
          final result = PipelineResult.fromJson(resultJson);
          onComplete!(result);
        });
      }

      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  Future<PipelineResult> run() async {
    if (_pipeline == null) {
      return PipelineResult(
        success: false,
        errorMessage: 'Pipeline not initialized',
        articles: [],
        stageResults: [],
        totalDurationMs: 0,
      );
    }

    _isRunning = true;
    _lastError = null;

    try {
      final resultJson = YallaAIService.runPipeline(_pipeline!);
      final result = PipelineResult.fromJson(resultJson);
      _isRunning = false;
      return result;
    } catch (e) {
      _isRunning = false;
      _lastError = e.toString();
      return PipelineResult(
        success: false,
        errorMessage: e.toString(),
        articles: [],
        stageResults: [],
        totalDurationMs: 0,
      );
    }
  }

  void cancel() {
    if (_pipeline != null) {
      // Pipeline doesn't have explicit cancel, but we can unload model
      _aiService.cancelGeneration();
    }
  }

  Future<void> dispose() async {
    if (_pipeline != null) {
      YallaAIService.destroyNewsPipeline(_pipeline!);
      _pipeline = null;
    }
    _isRunning = false;
  }
}