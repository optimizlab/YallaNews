import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/news_model.dart';
import '../models/news_source.dart';
import '../services/yalla_engine_service.dart';
import '../services/news_intelligence.dart';
import '../services/arabic_normalizer.dart';
import '../services/category_service.dart';
import '../services/knowledge_extraction_service.dart';
import '../database/news_db.dart';

/// Main Arabic News Processor - Event-driven, modular system for processing Arabic news
class ArabicNewsProcessor {
  // Singleton pattern
  ArabicNewsProcessor._privateConstructor();
  static final ArabicNewsProcessor instance = ArabicNewsProcessor._privateConstructor();

  // Core components
  final YallaEngineService _engineService = YallaEngineService();
  final NewsDatabase _db = NewsDatabase.instance;
  
  // State management
  bool _isRunning = false;
  final Map<String, Timer> _sourceTimers = {};
  final Map<String, DateTime> _lastCrawlTimes = {};
  final StreamController<String> _logController = StreamController<String>.broadcast();
  final StreamController<NewsModel> _articleController = StreamController<NewsModel>.broadcast();
  
  // Configuration
  static const int _minCrawlInterval = 300; // 5 minutes minimum
  static const int _maxCrawlInterval = 3600; // 1 hour maximum
  static const int _defaultCrawlInterval = 900; // 15 minutes default
  
  Stream<String> get logStream => _logController.stream;
  Stream<NewsModel> get articleStream => _articleController.stream;
  
  /// Start the Arabic news processing system
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    
    _log('[SYSTEM] Starting Arabic News Processor...');
    
    try {
      // Initialize database
      await _db.database;
      
      // Load all Arabic news sources
      final sources = await _db.getAllSources();
      _log('[SYSTEM] Loaded ${sources.length} Arabic news sources');
      
      // Start processing each source based on its priority
      for (final source in sources) {
        await _scheduleSourceCrawl(source);
      }
      
      _log('[SYSTEM] Arabic News Processor started successfully');
    } catch (e) {
      _log('[ERROR] Failed to start Arabic News Processor: $e');
      _isRunning = false;
    }
  }
  
  /// Stop the Arabic news processing system
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    
    // Cancel all scheduled timers
    for (final timer in _sourceTimers.values) {
      timer.cancel();
    }
    _sourceTimers.clear();
    
    await _logController.close();
    _log('[SYSTEM] Arabic News Processor stopped');
  }
  
  /// Schedule a source for crawling based on its priority and last crawl time
  Future<void> _scheduleSourceCrawl(NewsSource source) async {
    if (!_isRunning) return;
    
    // Calculate next crawl time based on source priority and last crawl
    final int interval = _calculateCrawlInterval(source);
    final DateTime now = DateTime.now();
    final DateTime? lastCrawl = _lastCrawlTimes[source.url];
    
    // If we've never crawled this source or enough time has passed, crawl now
    final bool shouldCrawlNow = lastCrawl == null || 
        now.difference(lastCrawl!).inSeconds >= interval;
    
    if (shouldCrawlNow) {
      await _crawlSource(source);
    }
    
    // Schedule next crawl
    _sourceTimers[source.url]?.cancel();
    _sourceTimers[source.url] = Timer(Duration(seconds: interval), () {
      _scheduleSourceCrawl(source);
    });
  }
  
  /// Calculate crawl interval based on source priority (rank)
  int _calculateCrawlInterval(NewsSource source) {
    // Higher rank (lower number) = more frequent crawling
    // Rank 1 = highest priority, crawl more often
    // Rank 10 = lowest priority, crawl less often
    final int rank = source.rank.clamp(1, 10);
    final double priorityFactor = (11 - rank) / 10.0; // 1.0 for rank 1, 0.1 for rank 10
    
    // Calculate interval: higher priority = shorter interval
    final int interval = (_maxCrawlInterval - 
        ((_maxCrawlInterval - _minCrawlInterval) * priorityFactor)).toInt();
    
    return interval.clamp(_minCrawlInterval, _maxCrawlInterval);
  }
  
  /// Crawl a single news source (implements the 10-stage pipeline)
  Future<void> _crawlSource(NewsSource source) async {
    if (!_isRunning) return;
    
    final DateTime startTime = DateTime.now();
    _log('[PIPELINE] Starting crawl for ${source.name} (${source.url})');
    
    try {
      // STAGE 1: Source Manager (already handled by NewsSource object)
      _log('[SOURCE-MANAGER] Processing source: ${source.name}');
      
      // STAGE 2: Smart Scheduler (handled by _calculateCrawlInterval)
      
      // STAGE 3: Lightweight Fetcher
      final String localDbJson = await _getLocalDatabaseJson();
      final Map<String, dynamic> fetchResult = 
          await _engineService.processNewsUrl(source.url, localDbJson);
          
      if (fetchResult['success'] != true) {
        _log('[ERROR] Failed to fetch source ${source.name}: ${fetchResult['error']}');
        return;
      }
      
      if (fetchResult['is_source'] != true) {
        _log('[WARNING] ${source.url} is not recognized as a source page');
        return;
      }
      
      final List<dynamic> rawUrlsDynamic = fetchResult['articles'] ?? [];
      final List<String> rawUrls = rawUrlsDynamic.map((u) => u.toString()).toList();
      _log('[FETCHER] Discovered ${rawUrls.length} candidate URLs from ${source.name}');
      
      // STAGE 4: Change Detection
      final List<String> newUrls = await _filterNewUrls(source.url, rawUrls);
      _log('[CHANGE-DETECTION] ${newUrls.length} new/updated URLs detected');
      
      if (newUrls.isEmpty) {
        _log('[INFO] No new articles found for ${source.name}');
        _lastCrawlTimes[source.url] = DateTime.now();
        return;
      }
      
      // STAGE 5: Content Extraction (via Yalla Engine)
      final List<NewsModel> articles = await _extractArticles(newUrls, source);
      _log('[EXTRACTION] Successfully extracted ${articles.length} articles');
      
      // STAGE 6: Arabic NLP Processing
      final List<NewsModel> processedArticles = 
          await _processArabicNLP(articles);
      _log('[NLP] Arabic NLP processing complete for ${processedArticles.length} articles');
      
      // STAGE 7: Classification
      final List<NewsModel> classifiedArticles = 
          await _classifyArticles(processedArticles);
      _log('[CLASSIFICATION] Article classification complete');
      
      // STAGE 8: Duplicate & Event Detection
      final List<NewsModel> deduplicatedArticles = 
          await _detectDuplicatesAndEvents(classifiedArticles);
      _log('[DEDUPLICATION] Reduced to ${deduplicatedArticles.length} unique articles/events');
      
      // STAGE 9: Local Storage & Search
      await _storeArticles(deduplicatedArticles, source.url);
      _log('[STORAGE] Stored ${deduplicatedArticles.length} articles to local database');
      
      for (final article in deduplicatedArticles) {
        _articleController.add(article);
      }
      
      // STAGE 10: Monitoring
      final Duration elapsed = DateTime.now().difference(startTime);
      _log('[MONITORING] Crawl completed for ${source.name} in ${elapsed.inSeconds}s');
      _log('[MONITORING] Performance: ${(deduplicatedArticles.length / elapsed.inSeconds).toStringAsFixed(2)} articles/second');
      
      // Update last crawl time
      _lastCrawlTimes[source.url] = DateTime.now();
      
    } catch (e) {
      _log('[ERROR] Pipeline failed for ${source.name}: $e');
    }
  }
  
  /// Get local database JSON for the engine service
  Future<String> _getLocalDatabaseJson() async {
    try {
      final List<NewsSource> sources = await _db.getAllSources();
      final List<Map<String, dynamic>> sourceMaps = sources
          .map((source) => {
                'url': source.url,
                'category': source.category,
                'name': source.name,
              })
          .toList();
      return jsonEncode(sourceMaps);
    } catch (e) {
      _log('[WARNING] Failed to build local DB JSON: $e');
      return '[]';
    }
  }
  
  /// Filter URLs to only new or updated ones (Change Detection)
  Future<List<String>> _filterNewUrls(String sourceUrl, List<String> urls) async {
    final List<String> newUrls = [];
    
    for (final url in urls) {
      try {
        // Check if we've crawled this URL recently
        final DateTime? lastCrawl = await _db.getLastCrawlTime(url);
        if (lastCrawl == null) {
          // Never crawled before
          newUrls.add(url);
        } else {
          // Check if content might have changed (simple approach: re-crawl if >1 hour old)
          final DateTime now = DateTime.now();
          if (now.difference(lastCrawl).inHours > 1) {
            newUrls.add(url);
          }
        }
      } catch (e) {
        // If we can't check, assume it's new to be safe
        newUrls.add(url);
      }
    }
    
    return newUrls;
  }
  
  /// Extract article content from URLs (Content Extraction)
  Future<List<NewsModel>> _extractArticles(List<String> urls, NewsSource source) async {
    final List<NewsModel> articles = [];
    final String localDbJson = await _getLocalDatabaseJson();
    
    // Process articles sequentially to avoid overwhelming resources
    for (final url in urls) {
      if (!_isRunning) break;
      
      try {
        final Map<String, dynamic> result = 
            await _engineService.processNewsUrl(url, localDbJson);
            
        if (result['success'] == true && result['is_source'] == false) {
          var article = NewsModel.fromJson(result, url);
          // Override category with source category if AI didn't determine one
          if (article.category == 'General' || article.category.isEmpty) {
            article = article.copyWith(category: source.category);
          }
          articles.add(article);
        }
      } catch (e) {
        _log('[ERROR] Failed to extract article from $url: $e');
        continue;
      }
      
      // Small delay to prevent resource exhaustion
      await Future.delayed(const Duration(milliseconds: 200));
    }
    
    return articles;
  }
  
  /// Apply Arabic NLP processing (normalization, entity extraction, etc.)
  Future<List<NewsModel>> _processArabicNLP(List<NewsModel> articles) async {
    final List<NewsModel> processed = [];
    
    for (final article in articles) {
      if (!_isRunning) break;
      
      try {
        // Normalize Arabic text
        final String normalizedTitle = 
            ArabicTextNormalizer.normalize(article.title);
        final String normalizedContent = 
            ArabicTextNormalizer.normalize(article.content);
        final String normalizedSummary = 
            ArabicTextNormalizer.normalize(article.summary);
        
        // Re-extract keywords from normalized content
        final List<String> normalizedKeywords = 
            _extractKeywordsFromText('$normalizedTitle $normalizedSummary $normalizedContent');
        
        // Create new article with normalized fields
        final NewsModel processedArticle = NewsModel(
          url: article.url,
          title: normalizedTitle,
          shortTitle: article.shortTitle,
          summary: normalizedSummary,
          content: normalizedContent,
          imageUrl: article.imageUrl,
          category: article.category,
          sentiment: article.sentiment,
          keywords: normalizedKeywords,
          logs: article.logs,
          author: article.author,
          publishDate: article.publishDate,
          eventType: article.eventType,
          subcategory: article.subcategory,
          entities: article.entities,
          structuredData: article.structuredData,
          intelligenceJson: article.intelligenceJson,
          sourceCount: article.sourceCount,
          sources: article.sources,
        );
        
        processed.add(processedArticle);
      } catch (e) {
        _log('[ERROR] Failed to process NLP for ${article.url}: $e');
        processed.add(article); // Keep original if processing fails
      }
    }
    
    return processed;
  }
  
  /// Extract keywords from text (simple implementation)
  List<String> _extractKeywordsFromText(String text) {
    final String lowerText = text.toLowerCase();
    const Set<String> stopWords = {
      'في', 'من', 'إلى', 'على', 'هذا', 'هذه', 'أن', 'كان', 'كانت', 'ليس',
      'لكن', 'أو', 'ثم', 'أي', 'كل', 'some', 'the', 'a', 'an', 'and', 'or',
      'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by', 'is', 'are',
      'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had', 'do', 'does',
      'did', 'will', 'would', 'could', 'should', 'may', 'might', 'shall', 'can'
    };
    
    final List<String> words = lowerText
        .replaceAll(RegExp(r'[^\w\u0600-\u06FF\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !stopWords.contains(w))
        .toList();
    
    // Count frequency
    final Map<String, int> freq = {};
    for (final word in words) {
      freq[word] = (freq[word] ?? 0) + 1;
    }
    
    // Return top 10 by frequency
    final sortedEntries = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
      
    return sortedEntries
      .take(10)
      .map((e) => e.key)
      .toList();
  }
  
  /// Classify articles using news intelligence service
  Future<List<NewsModel>> _classifyArticles(List<NewsModel> articles) async {
    final List<NewsModel> classified = [];
    
    for (final article in articles) {
      if (!_isRunning) break;
      
      try {
        final textForLanguage = '${article.title} ${article.summary} ${article.content}';
        final detectedLanguage = ArabicTextNormalizer.detectLanguage(textForLanguage);

        final updatedStructuredData = Map<String, dynamic>.from(article.structuredData);
        updatedStructuredData['language'] = detectedLanguage;

        final IntelligenceResult intelligence = await NewsIntelligence.extractAsync(
          article.title,
          article.content,
          article.summary,
          validCategoryIds: CategoryService.instance.categoryIds,
        );
        
        final NewsModel classifiedArticle = NewsModel(
          url: article.url,
          title: article.title,
          shortTitle: article.shortTitle,
          summary: article.summary,
          content: article.content,
          imageUrl: article.imageUrl,
          category: intelligence.category,
          sentiment: intelligence.sentiment,
          keywords: article.keywords,
          logs: article.logs,
          author: article.author,
          publishDate: article.publishDate,
          eventType: intelligence.eventType,
          subcategory: intelligence.subcategory,
          entities: intelligence.entities.map((e) => e.value).toList(),
          structuredData: updatedStructuredData,
          intelligenceJson: article.intelligenceJson,
          sourceCount: article.sourceCount,
          sources: article.sources,
        );
        
        classified.add(classifiedArticle);
      } catch (e) {
        _log('[ERROR] Failed to classify article ${article.url}: $e');
        classified.add(article); // Keep original if classification fails
      }
    }
    
    return classified;
  }
  
  /// Detect duplicates and group related articles into events
  Future<List<NewsModel>> _detectDuplicatesAndEvents(List<NewsModel> articles) async {
    if (articles.isEmpty) return [];
    return compute(_deduplicateIsolate, _DeduplicateInput(articles));
  }
  
  /// Store articles in local database and maintain search indexes
  Future<void> _storeArticles(List<NewsModel> articles, String sourceUrl) async {
    if (articles.isEmpty) return;
    
    try {
      await _db.saveCrawledArticles(articles, sourceUrl);
      for (final article in articles) {
        await KnowledgeExtractionService.instance.extractAndStore(
          article.url,
          article.title,
          article.content.isNotEmpty ? article.content : article.summary,
          article.category,
        );
      }
    } catch (e) {
      _log('[ERROR] Failed to store articles: $e');
    }
  }
  
  /// Log a message to the controller and console
  void _log(String message) {
    final String timestamp = DateTime.now().toIso8601String();
    final String logMessage = '[$timestamp] $message';
    _logController.add(logMessage);
    if (kDebugMode) print(logMessage);
  }
  
  /// Get current processor status
  Map<String, dynamic> getStatus() {
    return {
      'isRunning': _isRunning,
      'activeSources': _sourceTimers.length,
      'lastUpdate': DateTime.now().toIso8601String(),
    };
  }
  
  /// Manually trigger a crawl for a specific source
  Future<void> crawlSourceNow(NewsSource source) async {
    _log('[MANUAL] Triggering manual crawl for ${source.name}');
    await _crawlSource(source);
  }
  
  /// Get statistics about processed articles
  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final int articleCount = await _db.getArticleCount();
      final List<String> sourceNames = await _db.getCrawledSourceNames();
      
      return {
        'totalArticles': articleCount,
        'activeSources': sourceNames.length,
        'sources': sourceNames,
        'lastUpdated': DateTime.now().toIso8601String(),
        'isRunning': _isRunning,
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'isRunning': _isRunning,
      };
    }
  }
}

class _DeduplicateInput {
  final List<NewsModel> articles;
  _DeduplicateInput(this.articles);
}

NewsModel _arabicCreateRepresentative(List<NewsModel> articles) {
  if (articles.isEmpty) return NewsModel.empty('');
  if (articles.length == 1) return articles.first;
  final base = articles.first;
  final sources = articles.map((a) => a.url).toList();
  final allKeywords = <String>{};
  for (final article in articles) {
    allKeywords.addAll(article.keywords);
  }
  final maxSentiment = articles.map((a) => a.sentiment).reduce((a, b) => a > b ? a : b);
  final latestPublishDate = articles
      .where((a) => a.publishDate.isNotEmpty)
      .map((a) => a.publishDate)
      .reduce((a, b) => a.compareTo(b) > 0 ? a : b);
  return NewsModel(
    url: base.url,
    title: base.title,
    shortTitle: base.shortTitle,
    summary: base.summary,
    content: base.content,
    imageUrl: base.imageUrl,
    category: base.category,
    sentiment: maxSentiment,
    keywords: allKeywords.toList(),
    logs: base.logs,
    author: base.author,
    publishDate: latestPublishDate.isNotEmpty ? latestPublishDate : base.publishDate,
    eventType: base.eventType,
    subcategory: base.subcategory,
    entities: base.entities,
    structuredData: base.structuredData,
    intelligenceJson: base.intelligenceJson,
    sourceCount: sources.length,
    sources: sources,
  );
}

double _arabicTitleSimilarity(NewsModel a, NewsModel b) {
  final wordsA = a.title.toLowerCase()
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 2)
      .toSet();
  final wordsB = b.title.toLowerCase()
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 2)
      .toSet();
  if (wordsA.isEmpty || wordsB.isEmpty) return 0.0;
  return wordsA.intersection(wordsB).length / wordsA.union(wordsB).length;
}

List<NewsModel> _deduplicateIsolate(_DeduplicateInput input) {
  final articles = input.articles;
  if (articles.isEmpty) return [];
  final deduplicated = <NewsModel>[];
  final processedUrls = <String>{};
  for (final article in articles) {
    if (processedUrls.contains(article.url)) continue;
    final similarArticles = <NewsModel>[article];
    processedUrls.add(article.url);
    for (final other in articles) {
      if (processedUrls.contains(other.url)) continue;
      if (other.url == article.url) continue;
      final similarity = _arabicTitleSimilarity(article, other);
      if (similarity > 0.7) {
        similarArticles.add(other);
        processedUrls.add(other.url);
      }
    }
    if (similarArticles.length == 1) {
      deduplicated.add(article);
    } else {
      deduplicated.add(_arabicCreateRepresentative(similarArticles));
    }
  }
  return deduplicated;
}