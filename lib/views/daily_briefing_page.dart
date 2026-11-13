// Daily Briefing Page - Reporter-style briefing from today's top news

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import '../database/news_db.dart';
import '../services/tiny_llm_service.dart';
import '../services/background_crawler_service.dart';
import '../services/news_grouping_service.dart';
import '../services/app_settings.dart';
import '../views/news_detail_page.dart';
import '../widgets/cached_news_image.dart';

class DailyBriefingPage extends StatefulWidget {
  const DailyBriefingPage({super.key});

  @override
  State<DailyBriefingPage> createState() => _DailyBriefingPageState();
}

class _DailyBriefingPageState extends State<DailyBriefingPage> {
  List<NewsModel> _topStories = [];
  String _briefingText = '';
  bool _isLoading = true;
  bool _briefingGenerated = false;
  StreamSubscription<NewsModel>? _crawlerSubscription;

  @override
  void initState() {
    super.initState();
    _loadBriefing();
    _listenToCrawler();
    debugPrint('[DAILY BRIEFING] Page initialized');
  }

  @override
  void dispose() {
    _crawlerSubscription?.cancel();
    super.dispose();
  }

  void _listenToCrawler() {
    _crawlerSubscription =
        BackgroundCrawlerService.instance.articleStream.listen((article) {
      if (!mounted) return;
      debugPrint('[DAILY BRIEFING] Crawler stream article: ${article.title}');
      _loadBriefing();
    });
  }

  Future<void> _loadBriefing() async {
    debugPrint('[DAILY BRIEFING] _loadBriefing started');
    setState(() => _isLoading = true);

    try {
      final db = await NewsDatabase.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final dayAgo = now - (24 * 60 * 60 * 1000);
      final activeLanguage = AppSettings.instance.locale?.languageCode ?? '';

      String whereClause = 'crawled_at > ?';
      List<dynamic> whereArgs = [dayAgo];
      if (activeLanguage.isNotEmpty) {
        whereClause += ' AND language = ?';
        whereArgs.add(activeLanguage);
      }

      final allArticles = (await db.query(
        'crawled_articles',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'crawled_at DESC',
        limit: 50,
      )).cast<Map<String, dynamic>>();
      debugPrint(
          '[DAILY BRIEFING] Retrieved ${allArticles.length} articles from DB');

      if (allArticles.isEmpty) {
        // Fallback: load any articles regardless of age
        String fallbackWhere = '1';
        List<dynamic> fallbackArgs = [];
        if (activeLanguage.isNotEmpty) {
          fallbackWhere = 'language = ?';
          fallbackArgs = [activeLanguage];
        }
        final fallbackArticles = (await db.query(
          'crawled_articles',
          where: fallbackWhere,
          whereArgs: fallbackArgs,
          orderBy: 'crawled_at DESC',
          limit: 50,
        )).cast<Map<String, dynamic>>();
        debugPrint(
            '[DAILY BRIEFING] Fallback retrieved ${fallbackArticles.length} articles');

        if (fallbackArticles.isNotEmpty) {
          await _generateAndSetBriefing(fallbackArticles);
        } else {
          if (mounted) {
            final l10n = AppLocalizations.of(context);
            setState(() {
              _topStories = [];
              _briefingText = l10n.translate('noArticles');
              _isLoading = false;
              _briefingGenerated = true;
            });
          }
        }
        return;
      }

      await _generateAndSetBriefing(allArticles);
    } catch (e) {
      debugPrint('[DAILY BRIEFING] Error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _generateAndSetBriefing(List<Map<String, dynamic>> articles) async {
    final topStories = <NewsModel>[];
    for (int i = 0; i < articles.length && i < 10; i++) {
      final row = articles[i];
      try {
        final article = NewsModel.fromJson(
          Map<String, dynamic>.from(row),
          row['url']?.toString() ?? '',
        );
        topStories.add(article);
      } catch (e) {
        debugPrint('[DAILY BRIEFING] Failed to parse article $i: $e');
      }
    }

      if (topStories.isEmpty) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          setState(() {
            _topStories = [];
            _briefingText = l10n.translate('noArticles');
            _isLoading = false;
            _briefingGenerated = true;
          });
        }
        return;
      }

      final clustered = NewsGroupingService.instance
          .getRepresentativeArticles(topStories)
          .take(10)
          .toList();

      final locale = AppSettings.instance.locale;
      final language = locale?.languageCode.toLowerCase() ?? 'ar';

      String briefingText = '';
      try {
        briefingText = await TinyLLMService.generateBriefing(
          articles: articles.take(10).toList(),
          language: language,
        );
      } catch (e) {
        debugPrint('[DAILY BRIEFING] TinyLLM error: $e');
        final top3 = articles.take(3).map((a) => a['title']?.toString() ?? 'Untitled');
        final headline = top3.join('; ');
        if (language == 'ar') {
          briefingText = 'نشرة الأخبار اليومية: أهم عناوين اليوم تشمل $headline.';
        } else if (language == 'fr') {
          briefingText = 'Briefing quotidien: Les titres principaux incluent $headline.';
        } else if (language == 'tr') {
          briefingText = 'Günlük özet: Başlıklar arasında $headline yer alıyor.';
        } else {
          briefingText = 'Daily Briefing: Top stories include $headline.';
        }
      }

      if (mounted) {
        setState(() {
          _topStories = clustered;
          _briefingText = briefingText;
          _isLoading = false;
          _briefingGenerated = true;
        });
        debugPrint(
            '[DAILY BRIEFING] Generated briefing: ${briefingText.length} chars, ${clustered.length} stories');
      }
    }

  Widget _buildBriefingCard(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.announcement_rounded,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.translate('dailyBriefing'),
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outline.withOpacity(0.1),
                ),
              ),
              child: Text(
                _briefingText,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  height: 1.6,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '${_topStories.length} stories',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _loadBriefing,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(l10n.translate('refresh')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryCard(BuildContext context, AppLocalizations l10n, NewsModel article, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: _buildStoryImage(article, index),
        title: Text(
          article.title,
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getCategoryDisplayName(article.category, l10n),
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getTimeAgo(article.publishDate),
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              article.summary.isNotEmpty
                  ? article.summary
                  : (article.content.length > 120
                      ? article.content.substring(0, 120)
                      : article.content),
              style: GoogleFonts.outfit(
                fontSize: 13,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          size: 20,
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NewsDetailPage(article: article),
          ),
        ),
      ),
    );
  }

  Color themeColorForIndex(int index) {
    final colors = [
      Colors.blue, Colors.green, Colors.orange, Colors.red, Colors.purple,
      Colors.teal, Colors.pink, Colors.indigo, Colors.lime, Colors.amber,
    ];
    return colors[index % colors.length];
  }

  Widget _buildStoryImage(NewsModel article, int index) {
    final images = <String>[];
    if (article.imageUrl.isNotEmpty &&
        !article.imageUrl.contains('placeholder') &&
        !article.imageUrl.contains('image.png')) {
      images.add(article.imageUrl);
    }
    for (final related in article.relatedArticles.take(6)) {
      if (related.imageUrl.isNotEmpty &&
          !related.imageUrl.contains('placeholder') &&
          !related.imageUrl.contains('image.png') &&
          !images.contains(related.imageUrl)) {
        images.add(related.imageUrl);
      }
    }

    if (images.isEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: themeColorForIndex(index),
        child: Text(
          '${index + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNewsImage(
              imageUrl: images.first,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
            ),
          ),
        ),
        for (int i = 1; i < images.length && i < 4; i++)
          Positioned(
            left: (i * 15.0).clamp(0.0, 30.0),
            top: (i * 15.0).clamp(0.0, 30.0),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNewsImage(
                  imageUrl: images[i],
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _getCategoryDisplayName(String category, AppLocalizations l10n) {
    switch (category) {
      case 'politics':
        return l10n.translate('politics');
      case 'business':
        return l10n.translate('business');
      case 'technology':
        return l10n.translate('technology');
      case 'sports':
        return l10n.translate('sports');
      case 'health':
        return l10n.translate('health');
      case 'science':
        return l10n.translate('science');
      case 'culture':
        return l10n.translate('culture');
      case 'world':
        return l10n.translate('world');
      case 'society':
        return l10n.translate('society');
      case 'entertainment':
        return l10n.translate('entertainment');
      default:
        return category;
    }
  }

  String _getTimeAgo(String publishDate) {
    try {
      final date = DateTime.parse(publishDate);
      final diff = DateTime.now().difference(date);
      if (diff.inDays > 0) return '${diff.inDays}d';
      if (diff.inHours > 0) return '${diff.inHours}h';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m';
      return 'now';
    } catch (_) {
      return '';
    }
  }

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: List.generate(3, (i) => Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 16,
                    width: 200,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 120,
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ],
              ),
            )),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _isLoading
        ? _buildSkeleton(context)
        : _briefingGenerated
            ? SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBriefingCard(context, l10n),
                      const SizedBox(height: 16),
                      Text(
                        l10n.translate('topStories'),
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...List.generate(
                        _topStories.length,
                        (index) => _buildStoryCard(
                          context, l10n, _topStories[index], index,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              )
            : _buildEmptyState(context, l10n);
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.announcement_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.translate('noBriefingYet'),
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _loadBriefing,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppLocalizations.of(context).translate('refresh')),
            ),
          ],
        ),
      ),
    );
  }
}