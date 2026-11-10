// Background Pipeline Service
// Runs the news intelligence pipeline in background using WorkManager

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:sqflite/sqflite.dart';
import 'package:yallanews/services/ai_service.dart';
import 'package:yallanews/services/model_download_manager.dart';
import 'package:yallanews/services/news_pipeline_service.dart'
    show NewsPipelineConfig, PipelineArticle, NewsPipelineService;
import 'package:yallanews/database/news_db.dart';
import 'package:yallanews/services/ai_ffi.dart' show YallaProviderConfig, YallaProviderType;

/// WorkManager task names
const String kPipelineTask = 'com.yallanews.pipeline_run';
const String kModelDownloadTask = 'com.yallanews.model_download';
const String kCleanupTask = 'com.yallanews.cleanup';

/// Initialize background services
Future<void> initializeBackgroundServices() async {
  await Workmanager().initialize(_callbackDispatcher, isInDebugMode: false);
  
  // Schedule daily pipeline run (every 6 hours)
  await Workmanager().registerPeriodicTask(
    'pipeline_daily',
    kPipelineTask,
    frequency: const Duration(hours: 6),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
      requiresCharging: false,
    ),
    initialDelay: const Duration(minutes: 5),
  );
  
  // Schedule weekly cleanup
  await Workmanager().registerPeriodicTask(
    'cleanup_weekly',
    kCleanupTask,
    frequency: const Duration(days: 7),
    constraints: Constraints(
      networkType: NetworkType.unmetered,
      requiresBatteryNotLow: true,
      requiresCharging: true,
    ),
    initialDelay: const Duration(hours: 1),
  );
}

/// WorkManager callback dispatcher - must be top-level function
@pragma('vm:entry-point')
void _callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    switch (taskName) {
      case kPipelineTask:
        return await _runPipelineInBackground(inputData);
      case kModelDownloadTask:
        return await _downloadModelInBackground(inputData);
      case kCleanupTask:
        return await _cleanupInBackground(inputData);
      default:
        return false;
    }
  });
}

/// Run news pipeline in background
Future<bool> _runPipelineInBackground(Map<String, dynamic>? inputData) async {
  try {
    // Initialize database
    await NewsDatabase.instance.database;
    
    // Initialize AI service
    final aiService = AIService.instance;
    await aiService.initialize();
    
    // Load model if available
    if (!aiService.isModelLoaded) {
      await aiService.loadModel(aiService.currentModel);
    }
    
    if (!aiService.isReady) {
      print('[BackgroundPipeline] AI not ready, skipping pipeline run');
      return true; // Don't retry
    }
    
    // Create pipeline configuration
    final config = NewsPipelineConfig(
      enableAI: true,
      aiModel: aiService.currentModel.id,
      enableSummarization: true,
      summaryMaxLength: 150,
      enableTranslation: true,
      targetLanguages: ['ar', 'en', 'fr'],
      enableDedup: true,
      dedupThreshold: 0.85,
      enableClassification: true,
      enableEntities: true,
      enableClustering: true,
      clusterAlgorithm: 1, // DBSCAN
      clusterEps: 0.5,
      clusterMinSamples: 2,
      maxArticlesPerProvider: 50,
      enableFactcheck: true,
      providers: _getDefaultProviders(),
    );
    
    // Create and run pipeline
    final pipelineService = NewsPipelineService.instance;
    if (!await pipelineService.initialize(config)) {
      print('[BackgroundPipeline] Failed to initialize pipeline');
      return false;
    }
    
    final result = await pipelineService.run();
    
    // Save results to database
    if (result.success && result.articles.isNotEmpty) {
      await _savePipelineResults(result.articles);
      print('[BackgroundPipeline] Processed ${result.articles.length} articles');
    } else {
      print('[BackgroundPipeline] Pipeline failed: ${result.errorMessage}');
    }
    
    return result.success;
  } catch (e) {
    print('[BackgroundPipeline] Error: $e');
    return false; // Retry on next schedule
  }
}

/// Download model in background
Future<bool> _downloadModelInBackground(Map<String, dynamic>? inputData) async {
  try {
    final modelId = inputData?['modelId'] as String?;
    if (modelId == null) return false;
    
    final model = AIModelType.values.firstWhere((m) => m.id == modelId);
    final downloadManager = ModelDownloadManager.instance;
    await downloadManager.initialize();
    
    final success = await downloadManager.startDownload(model);
    return success;
  } catch (e) {
    print('[BackgroundDownload] Error: $e');
    return false;
  }
}

/// Cleanup old data in background
Future<bool> _cleanupInBackground(Map<String, dynamic>? inputData) async {
  try {
    final db = await NewsDatabase.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final thirtyDaysAgo = now - (30 * 24 * 60 * 60 * 1000);
    final ninetyDaysAgo = now - (90 * 24 * 60 * 60 * 1000);
    
    final batch = db.batch();
    
    // Delete old AI summaries (older than 90 days)
    batch.delete('ai_summaries', where: 'created_at < ?', whereArgs: [ninetyDaysAgo]);
    
    // Delete old translations (older than 90 days)
    batch.delete('translations', where: 'created_at < ?', whereArgs: [ninetyDaysAgo]);
    
    // Delete expired provider cache
    batch.delete('provider_cache', where: 'expires_at < ?', whereArgs: [now]);
    
    // Delete completed processing jobs older than 30 days
    batch.delete('processing_jobs', where: 'completed_at < ? AND status = ?', whereArgs: [thirtyDaysAgo, 'completed']);
    
    // Delete old bookmarks for deleted articles
    batch.rawDelete('''
      DELETE FROM bookmarks WHERE article_url NOT IN (SELECT url FROM crawled_articles)
    ''');
    
    await batch.commit(noResult: true);
    
    print('[BackgroundCleanup] Cleanup completed');
    return true;
  } catch (e) {
    print('[BackgroundCleanup] Error: $e');
    return false;
  }
}

/// Save pipeline results to database
Future<void> _savePipelineResults(List<PipelineArticle> articles) async {
  final db = await NewsDatabase.instance.database;
  final now = DateTime.now().millisecondsSinceEpoch;
  final batch = db.batch();
  
  for (final article in articles) {
    // Save/update main article
    batch.insert('crawled_articles', {
      'source_url': article.sourceUrl,
      'url': article.url,
      'url_hash': _hashUrl(article.url),
      'title': article.title,
      'summary': article.summary,
      'content': article.content,
      'image_url': article.imageUrl,
      'category': article.category,
      'sentiment': article.sentiment,
      'keywords': article.keywords.join(','),
      'logs': '',
      'crawled_at': now,
      'author': article.author,
      'publish_date': article.publishDate.toString(),
      'language': article.language,
      'meta_tags': '{}',
      'source_count': 1,
      'sources': article.sourceUrl,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    
    // Save AI summary
    if (article.aiSummary.isNotEmpty) {
      batch.insert('ai_summaries', {
        'id': _generateId(),
        'article_url': article.url,
        'model_version': 'qwen3-0.6b-q4',
        'summary': article.aiSummary,
        'tokens_used': 0,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    
    // Save translations
    for (final entry in article.translations.entries) {
      batch.insert('translations', {
        'id': _generateId(),
        'article_url': article.url,
        'target_lang': entry.key,
        'translated_title': '', // Would need title translation
        'translated_content': entry.value,
        'model_version': 'qwen3-0.6b-q4',
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    
    // Save entities
    for (final entity in article.entities) {
      batch.insert('yn_entities', {
        'id': _generateId(),
        'article_url': article.url,
        'type': entity.type,
        'value': entity.value,
        'normalized': entity.canonical,
        'language': entity.language,
        'context': '',
        'confidence': entity.confidence,
        'extracted_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    
    // Save cluster info
    if (article.clusterId >= 0) {
      // Update or insert cluster
      // In practice, would have a separate clusters table
    }
  }
  
  await batch.commit(noResult: true);
}

/// Default provider configurations
List<YallaProviderConfig> _getDefaultProviders() {
  return [
    YallaProviderConfig(
      type: YallaProviderType.rss,
      providerId: 'rss_bbc',
      customParams: '{"feeds":["https://feeds.bbci.co.uk/news/rss.xml"]}',
      rateLimitRpm: 30,
    ),
    YallaProviderConfig(
      type: YallaProviderType.rss,
      providerId: 'rss_reuters',
      customParams: '{"feeds":["https://www.reuters.com/rssFeed/topNews"]}',
      rateLimitRpm: 30,
    ),
    YallaProviderConfig(
      type: YallaProviderType.rss,
      providerId: 'rss_aljazeera',
      customParams: '{"feeds":["https://www.aljazeera.com/xml/rss/all.xml"]}',
      rateLimitRpm: 30,
    ),
    YallaProviderConfig(
      type: YallaProviderType.rss,
      providerId: 'rss_lemonde',
      customParams: '{"feeds":["https://www.lemonde.fr/rss/une.xml"]}',
      rateLimitRpm: 30,
    ),
    YallaProviderConfig(
      type: YallaProviderType.gdelt,
      providerId: 'gdelt',
      rateLimitRpm: 10,
    ),
    YallaProviderConfig(
      type: YallaProviderType.factcheck,
      providerId: 'factcheck',
      apiKey: '', // Set from config
      rateLimitRpm: 30,
    ),
    YallaProviderConfig(
      type: YallaProviderType.wikimedia,
      providerId: 'wikimedia',
      rateLimitRpm: 60,
    ),
  ];
}

/// Generate unique ID
String _generateId() {
  return DateTime.now().millisecondsSinceEpoch.toString() + 
         (DateTime.now().microsecond % 1000).toString().padLeft(3, '0');
}

/// Simple URL hash
String _hashUrl(String url) {
  return url.hashCode.abs().toString();
}