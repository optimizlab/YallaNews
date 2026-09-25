import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // For compute
import 'package:google_fonts/google_fonts.dart';
import '../models/news_model.dart';
import '../models/news_source.dart';
import '../services/yalla_engine_service.dart';
import '../services/news_uri_parser.dart';
import '../services/news_intelligence.dart';
import '../services/app_settings.dart';
import '../services/arabic_normalizer.dart';
import '../services/category_service.dart';
import '../database/news_db.dart';
import '../widgets/shimmer_loading.dart';
import 'news_detail_page.dart';

class SourceArticlesPage extends StatefulWidget {
  final NewsSource source;
  final YallaEngineService engineService;

  const SourceArticlesPage({
    Key? key,
    required this.source,
    required this.engineService,
  }) : super(key: key);

  @override
  State<SourceArticlesPage> createState() => _SourceArticlesPageState();
}

class _SourceArticlesPageState extends State<SourceArticlesPage> {
  List<NewsModel> _articles = [];
  bool _isLoading = false;
  bool _showConsole = true;
  final ScrollController _consoleScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadArticles();
    widget.engineService.addListener(_onEngineUpdate);
  }

  @override
  void dispose() {
    widget.engineService.removeListener(_onEngineUpdate);
    _consoleScrollController.dispose();
    super.dispose();
  }

  void _onEngineUpdate() {
    if (mounted) {
      setState(() {});
      if (_showConsole && _consoleScrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (_consoleScrollController.hasClients) {
            try {
              _consoleScrollController.animateTo(
                _consoleScrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOut,
              );
            } catch (_) {}
          }
        });
      }
    }
  }

  Future<void> _loadArticles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final db = NewsDatabase.instance;
      final cached = await db.getArticlesBySource(widget.source.url);

      if (cached.isNotEmpty) {
        setState(() {
          _articles = cached;
          _isLoading = false;
        });
        widget.engineService.addLog("[SYSTEM] Loaded ${cached.length} articles from offline database for ${widget.source.name}.");
      } else {
        // If not cached, trigger crawling pipeline automatically
        await _crawlSource();
      }
    } catch (e) {
      widget.engineService.addLog("[ERROR] Failed to load offline articles: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _crawlSource() async {
    setState(() {
      _isLoading = true;
      _articles = [];
    });

    widget.engineService.clearLogs();
    widget.engineService.addLog("[SYSTEM] Triggering Two-Pass Crawling Pipeline for source: ${widget.source.name}");

    try {
      final jsonStr = await rootBundle.loadString('assets/news_local_db.json');
      
      // PASS 1: Catch candidate URLs from source homepage
      widget.engineService.addLog("[PIPELINE] Pass 1: Crawling source homepage URL to catch article URLs...");
      final sourceResult = await widget.engineService.processNewsUrl(widget.source.url, jsonStr);
      
      if (sourceResult['success'] == true) {
        if (sourceResult['is_source'] == true) {
          List<dynamic> rawUrlsDynamic = sourceResult['articles'] ?? [];
          List<String> rawUrls = rawUrlsDynamic.map((u) => u.toString()).toList();
          widget.engineService.addLog("[SYSTEM] Discovered ${rawUrls.length} candidate URLs.");
          
          final maxUrls = await AppSettings.instance.getMaxUrlsPerSource();
          if (rawUrls.length > maxUrls) {
            widget.engineService.addLog("[PIPELINE] Limiting to $maxUrls URLs per source to avoid overload.");
            rawUrls = rawUrls.take(maxUrls).toList();
          }
          
          // PASS 2: URL filtering, Jaccard Deduplication, and priority sorting inside Isolate
          widget.engineService.addLog("[PIPELINE] Pass 2: Offloading URL filtering, Jaccard deduplication & priority sorting to background Isolate...");
          final Map<String, String> urlToCategoryMap = {
            for (final url in rawUrls) url: widget.source.category
          };

          final List<Map<String, dynamic>> parsedResults = await compute(
            NewsUriParser.runDeduplicationIsolate,
            {
              'rawUrls': rawUrls,
              'urlToCategoryMap': urlToCategoryMap,
              'similarityThreshold': 0.55,
            },
          );

          final List<String> sortedArticleUrls = parsedResults
              .map((item) => item['url'] as String)
              .toList();

          final int filteredCount = rawUrls.length - sortedArticleUrls.length;
          widget.engineService.addLog("[SYSTEM] Deduplicated and filtered $filteredCount invalid/similar URLs.");
          widget.engineService.addLog("[SYSTEM] Prioritized crawl queue has ${sortedArticleUrls.length} unique articles.");

// PASS 3: Crawl each unique article sequentially
            for (int i = 0; i < sortedArticleUrls.length; i++) {
              final String artUrl = sortedArticleUrls[i];

              if (isLikelySectionPage(artUrl)) {
                widget.engineService.addLog("[PIPELINE] Pass 3: Skipping non-article URL: $artUrl");
                continue;
              }

              final parsedInfo = parsedResults.firstWhere((p) => p['url'] == artUrl);
              final double priority = parsedInfo['priority'] as double;

              widget.engineService.addLog("[PIPELINE] Pass 3 [${i + 1}/${sortedArticleUrls.length}]: Crawling article details (Priority: ${priority.toStringAsFixed(1)}) for $artUrl...");
              
              final artResult = await widget.engineService.processNewsUrl(artUrl, jsonStr);
              if (artResult['success'] == true) {
                // Only use source category as fallback if AI didn't determine a category
                if (artResult['category'] == null || 
                    artResult['category'].isEmpty) {
                  artResult['category'] = widget.source.category;
                }
                final article = NewsModel.fromJson(artResult, artUrl);
                final String classificationText = '${article.title} ${article.summary} ${article.content}';
                final String detectedCategory = NewsIntelligence.classifyCategory(classificationText, url: artUrl, validCategoryIds: CategoryService.instance.categoryIds);
                final classifiedArticle = article.copyWith(category: detectedCategory);
                widget.engineService.addLog("[CATEGORY] Detected: \"$detectedCategory\" for URL: $artUrl");

                if (!YallaEngineService.hasValidTitle(classifiedArticle.title)) {
                  widget.engineService.addLog("[VALIDATION] Skipped invalid title for URL: $artUrl");
                  continue;
                }

                var finalArticle = classifiedArticle;
                if (classifiedArticle.imageUrl.isNotEmpty) {
                  final alreadyInPage = _articles.any((a) => a.imageUrl == classifiedArticle.imageUrl && a.url != classifiedArticle.url);
                  final alreadyInDb = await NewsDatabase.instance.isImageUsedByOtherArticle(classifiedArticle.imageUrl, classifiedArticle.url, sourceUrl: widget.source.url);
                  if (alreadyInPage || alreadyInDb) {
                    widget.engineService.addLog("[IMAGE] Duplicate image detected for URL: $artUrl. Trying Bing for unique image...");
                    try {
                      final uniqueImages = await widget.engineService.fetchBingImages('${classifiedArticle.title} news photo');
                      if (uniqueImages.isNotEmpty) {
                        finalArticle = classifiedArticle.copyWith(imageUrl: uniqueImages.first);
                        widget.engineService.addLog("[IMAGE] Replaced with unique Bing image: ${uniqueImages.first}");
                      } else {
                        final uniqueFallback = '${NewsModel.getFallbackImage(classifiedArticle.category)}&unique=${classifiedArticle.url.hashCode.abs() % 10000}';
                        finalArticle = classifiedArticle.copyWith(imageUrl: uniqueFallback);
                        widget.engineService.addLog("[IMAGE] Bing failed. Using unique fallback: $uniqueFallback");
                      }
                    } catch (e) {
                      final uniqueFallback = '${NewsModel.getFallbackImage(classifiedArticle.category)}&unique=${classifiedArticle.url.hashCode.abs() % 10000}';
                      finalArticle = classifiedArticle.copyWith(imageUrl: uniqueFallback);
                      widget.engineService.addLog("[IMAGE] Bing error. Using unique fallback: $uniqueFallback");
                    }
                  }
                }

                 // Check for duplicates before adding
                 final isDuplicate = _articles.any((existing) {
                   final cleanNew = ArabicTextNormalizer.normalize(finalArticle.title.toLowerCase());
                   final cleanExisting = ArabicTextNormalizer.normalize(existing.title.toLowerCase());
                   if (cleanNew.isEmpty || cleanExisting.isEmpty) return false;
                   
                   final wordsNew = cleanNew.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
                   final wordsExisting = cleanExisting.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
                   if (wordsNew.isEmpty || wordsExisting.isEmpty) return false;
                   
                   final intersection = wordsNew.intersection(wordsExisting).length;
                   final union = wordsNew.union(wordsExisting).length;
                   return union > 0 && (intersection / union) > 0.5;
                 });
                
                 if (!isDuplicate) {
                   _articles.add(finalArticle);
                 } else {
                   widget.engineService.addLog("[PIPELINE] Pass 3: Skipped duplicate title for $artUrl");
                 }
               
               // Update UI immediately after each article is processed
               if (mounted) {
                 setState(() {});
               }
              } else {
                widget.engineService.addLog("[ERROR] Failed to crawl article: $artUrl");
              }

             // Sequential delay to prevent CPU thrashing
             await Future.delayed(const Duration(milliseconds: 500));
           }

            // Save to offline articles DB
            if (_articles.isNotEmpty) {
              final db = NewsDatabase.instance;
              await db.saveCrawledArticles(_articles, widget.source.url);
              
              widget.engineService.addLog("[SYSTEM] Successfully saved ${_articles.length} news items into Offline DB.");
            }
            
            if (mounted) {
              setState(() {});
            }
        } else {
          // Single article URL target crawled directly!
          widget.engineService.addLog("[SYSTEM] Detected Single Article URL. Executing Direct Scraping...");
          final article = NewsModel.fromJson(sourceResult, widget.source.url);
          final db = NewsDatabase.instance;
          await db.saveCrawledArticles([article], widget.source.url);
          
          setState(() {
            _articles = [article];
          });
          widget.engineService.addLog("[SYSTEM] Successfully saved custom crawled news item into Offline DB.");
        }
      } else {
        widget.engineService.addLog("[ERROR] Stage 1 failed: Source URL crawling could not resolve article list.");
      }
    } catch (e) {
      widget.engineService.addLog("[ERROR] Pipeline execution crash: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
      try {
        final saved = await NewsDatabase.instance.getArticlesBySource(widget.source.url);
        if (mounted) {
          setState(() {
            _articles = saved;
          });
        }
      } catch (e) {
        widget.engineService.addLog("[ERROR] Failed to reload articles from DB: $e");
      }
    }
  }

  Future<void> _recrawlSource() async {
    final db = NewsDatabase.instance;
    await db.clearArticlesForSource(widget.source.url);
    await _crawlSource();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.source.name,
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'إعادة جلب المصدر',
            onPressed: _isLoading ? null : _recrawlSource,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: 3,
                      separatorBuilder: (_, __) => const SizedBox(height: 1),
                      itemBuilder: (_, __) => const ShimmerLoadingCard(),
                    )
                  : _articles.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: _articles.length,
                          itemBuilder: (context, index) {
                            final article = _articles[index];
                            final sentimentScore = article.sentiment;
                            
                             return Card(
                               margin: const EdgeInsets.only(bottom: 12),
                               elevation: 2,
                               color: Theme.of(context).colorScheme.surface,
                               shape: RoundedRectangleBorder(
                                 borderRadius: BorderRadius.circular(12),
                               ),
                               child: InkWell(
                                 borderRadius: BorderRadius.circular(12),
                                 onTap: () {
                                   Navigator.push(
                                     context,
                                     MaterialPageRoute(
                                       builder: (context) => NewsDetailPage(article: article),
                                     ),
                                   );
                                 },
                                 child: Padding(
                                   padding: const EdgeInsets.all(12.0),
                                   child: Row(
                                     crossAxisAlignment: CrossAxisAlignment.start,
                                     children: [
                                       Expanded(
                                         child: Column(
                                           crossAxisAlignment: CrossAxisAlignment.start,
                                           children: [
                                             Row(
                                               children: [
                                                 // Category Badge
                                                 Container(
                                                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                   decoration: BoxDecoration(
                                                     color: Theme.of(context).colorScheme.surfaceContainer,
                                                     borderRadius: BorderRadius.circular(8),
                                                   ),
                                                    child: Text(
                                                      CategoryService.getCategoryLabel(article.category, context),
                                                      style: GoogleFonts.outfit(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.bold,
                                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                      ),
                                                    ),
                                                 ),
                                                const SizedBox(width: 8),
                                                // Sentiment Indicator
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: sentimentScore > 0.3
                                                        ? const Color(0xFFE2F3E5)
                                                        : sentimentScore < -0.3
                                                            ? const Color(0xFFFFEBEE)
                                                            : const Color(0xFFFFF3E0),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    sentimentScore > 0.3
                                                        ? "إيجابي"
                                                        : sentimentScore < -0.3
                                                            ? "سلبي"
                                                            : "محايد",
                                                    style: GoogleFonts.outfit(
                                                      fontSize: 8,
                                                      fontWeight: FontWeight.w800,
                                                      color: sentimentScore > 0.3
                                                          ? const Color(0xFF2E7D32)
                                                          : sentimentScore < -0.3
                                                              ? const Color(0xFFC62828)
                                                              : const Color(0xFFE65100),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                             Text(
                                               article.title,
                                               style: GoogleFonts.outfit(
                                                 fontSize: 15,
                                                 fontWeight: FontWeight.bold,
                                                 color: Theme.of(context).colorScheme.onSurface,
                                                 height: 1.25,
                                               ),
                                             ),
                                             const SizedBox(height: 6),
                                             Text(
                                               article.summary,
                                               style: GoogleFonts.outfit(
                                                 fontSize: 12,
                                                 color: Theme.of(context).colorScheme.onSurfaceVariant,
                                               ),
                                               maxLines: 2,
                                               overflow: TextOverflow.ellipsis,
                                             ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Image Preview
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: article.imageUrl.startsWith('http')
                                            ? Image.network(
                                                article.imageUrl,
                                                width: 76,
                                                height: 76,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => _buildFallbackImage(article.category),
                                              )
                                            : _buildFallbackImage(article.category),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            if (_showConsole) _buildConsolePanel(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(
          _showConsole ? Icons.terminal : Icons.terminal_outlined,
          color: Theme.of(context).colorScheme.onPrimary,
        ),
        onPressed: () {
          setState(() {
            _showConsole = !_showConsole;
          });
        },
      ),
    );
  }

  Widget _buildFallbackImage(String category) {
    return Container(
      width: 76,
      height: 76,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.newspaper_outlined, size: 28),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_download_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              "لم يتم العثور على مقالات محفوظة.",
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              "اضغط على تحديث في الأعلى أو أعد المحاولة لجلب البيانات من محرك C++.",
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsolePanel() {
    return Container(
      height: 150,
      width: double.infinity,
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            color: const Color(0xFF2C2C2C),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.developer_board, size: 14, color: Color(0xFF4CAF50)),
                    const SizedBox(width: 6),
                    Text(
                      "سجلات تشغيل محرك C++ في الوقت الفعلي",
                      style: GoogleFonts.robotoMono(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFEAEAEA),
                      ),
                    ),
                  ],
                ),
                Text(
                  widget.engineService.modeDescription.toUpperCase(),
                  style: GoogleFonts.robotoMono(
                    fontSize: 9,
                    color: const Color(0xFFFFB300),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8.0),
              width: double.infinity,
              child: widget.engineService.consoleLogs.isEmpty
                  ? Center(
                      child: Text(
                        "شاشة التحكم فارغة. اضغط على تحديث لبدء المعالجة والاطلاع على السجلات.",
                        style: GoogleFonts.robotoMono(color: Colors.grey, fontSize: 11),
                      ),
                    )
                  : ListView.builder(
                      controller: _consoleScrollController,
                      itemCount: widget.engineService.consoleLogs.length,
                      itemBuilder: (context, index) {
                        final log = widget.engineService.consoleLogs[index];
                        Color logColor = Colors.white70;

                        if (log.contains("[C++ CRAWLER]")) {
                          logColor = const Color(0xFF64B5F6);
                        } else if (log.contains("[C++ DATA MINER]")) {
                          logColor = const Color(0xFFFFB74D);
                        } else if (log.contains("[C++ DEEP ANALYSER]")) {
                          logColor = const Color(0xFFBA68C8);
                        } else if (log.contains("[C++ TINY-LLM]")) {
                          logColor = const Color(0xFF81C784);
                        } else if (log.contains("[ERROR]")) {
                          logColor = const Color(0xFFE57373);
                        } else if (log.contains("[SYSTEM]")) {
                          logColor = const Color(0xFFEEEEEE);
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text(
                            log,
                            style: GoogleFonts.robotoMono(
                              fontSize: 11,
                              color: logColor,
                              height: 1.3,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
