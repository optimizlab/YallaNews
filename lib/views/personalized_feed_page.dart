// Personalized Feed Page
// User interests + relevance ranking with adaptive learning

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import '../database/news_db.dart';
import '../services/ai_service.dart';
import '../services/ai_fallback_service.dart';
import '../services/ai_language_ext.dart';
import '../services/category_service.dart';
import '../widgets/cached_news_image.dart';
import '../views/news_detail_page.dart';

class PersonalizedFeedPage extends StatefulWidget {
  const PersonalizedFeedPage({super.key});

  @override
  State<PersonalizedFeedPage> createState() => _PersonalizedFeedPageState();
}

class _PersonalizedFeedPageState extends State<PersonalizedFeedPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<NewsModel> _feed = [];
  List<NewsModel> _allArticles = [];
  bool _isLoading = true;
  String _sortBy = 'relevance'; // relevance, recent, popular
  Map<String, double> _userInterests = {};
  Map<String, int> _interactionCounts = {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserInterests();
    _loadFeed();
    _refreshTimer = Timer.periodic(const Duration(minutes: 10), (_) => _loadFeed());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserInterests() async {
    try {
      final db = await NewsDatabase.instance.database;
      final interests = await db.query('user_interests');
      final interactions = await db.query('processing_jobs', where: "type = 'interaction'");

      final interestsMap = <String, double>{};
      for (final row in interests) {
        interestsMap[row['topic'] as String] = (row['weight'] as num).toDouble();
      }

      final interactionMap = <String, int>{};
      for (final row in interactions) {
        final payload = row['payload_json'] as String;
        // Parse interaction data
      }

      if (mounted) {
        setState(() {
          _userInterests = interestsMap;
          _interactionCounts = interactionMap;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadFeed() async {
    setState(() => _isLoading = true);

    try {
      final db = await NewsDatabase.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final cutoff = now - (48 * 60 * 60 * 1000); // Last 48 hours

      // Get recent articles
      final articles = await db.query(
        'crawled_articles',
        where: 'crawled_at > ?',
        whereArgs: [cutoff],
        orderBy: 'crawled_at DESC',
        limit: 200,
      );

      final articlesList = articles.map((row) => NewsModel.fromJson(
        Map<String, dynamic>.from(row),
        row['url'] as String,
      )).toList();

      // Score and rank articles
      final ranked = _rankArticles(articlesList);

      // Apply sort
      switch (_sortBy) {
        case 'recent':
          ranked.sort((a, b) {
            try {
              return DateTime.parse(b.publishDate).compareTo(DateTime.parse(a.publishDate));
            } catch (_) {
              return 0;
            }
          });
          break;
        case 'popular':
          ranked.sort((a, b) => (b.relevanceScore * 100).compareTo((a.relevanceScore * 100)));
          break;
        default: // relevance
          ranked.sort((a, b) => (b.relevanceScore * 100).compareTo((a.relevanceScore * 100)));
      }

      if (mounted) {
        setState(() {
          _allArticles = articlesList;
          _feed = ranked;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double _calculateRelevance(NewsModel article) {
    double score = 0.5; // Base score

    // Interest matching
    for (final entity in article.entities ?? []) {
      final interest = _userInterests[entity.toLowerCase()] ?? 0.0;
      score += interest * 0.15;
    }

    // Category interest
    final catInterest = _userInterests[article.category.toLowerCase()] ?? 0.0;
    score += catInterest * 0.1;

    // Recency boost
    try {
      final pubDate = DateTime.parse(article.publishDate);
      final hoursAgo = DateTime.now().difference(pubDate).inHours;
      if (hoursAgo < 1) score += 0.2;
      else if (hoursAgo < 6) score += 0.15;
      else if (hoursAgo < 24) score += 0.1;
      else if (hoursAgo < 48) score += 0.05;
    } catch (_) {}

    // AI enrichment bonus
    if (article.aiSummary.isNotEmpty) score += 0.1;
    if (article.translations.isNotEmpty) score += 0.05;

    // Source credibility
    final premiumSources = ['reuters', 'ap', 'bbc', 'nytimes', 'aljazeera'];
    if (premiumSources.any((s) => article.sourceName.toLowerCase().contains(s))) {
      score += 0.1;
    }

    // Interaction history
    final interactions = _interactionCounts[article.url] ?? 0;
    score += (interactions * 0.02).clamp(0.0, 0.2);

    return score.clamp(0.0, 1.0);
  }

  List<NewsModel> _rankArticles(List<NewsModel> articles) {
    return articles.map((article) {
      final relevance = _calculateRelevance(article);
      return article.copyWith(
        structuredData: {
          ...article.structuredData,
          'relevance_score': relevance,
        },
      );
    }).toList();
  }

  void _recordInteraction(String url, String type) async {
    // Record user interaction for learning
    final db = await NewsDatabase.instance.database;
    await db.insert('processing_jobs', {
      'id': '${url}_${type}_${DateTime.now().millisecondsSinceEpoch}',
      'type': 'interaction',
      'status': 'completed',
      'payload_json': '{"url":"$url","type":"$type","timestamp":${DateTime.now().millisecondsSinceEpoch}}',
      'result_json': '{}',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'started_at': DateTime.now().millisecondsSinceEpoch,
      'completed_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Update local cache
    _interactionCounts[url] = (_interactionCounts[url] ?? 0) + 1;
    setState(() => _feed = _rankArticles(_feed));
  }

  Future<void> _saveInterest(String topic, double weight) async {
    final db = await NewsDatabase.instance.database;
    await db.insert('user_interests', {
      'id': topic,
      'user_id': 'default',
      'topic': topic,
      'weight': weight,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    _userInterests[topic] = weight;
    setState(() => _feed = _rankArticles(_feed));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.translate('personalizedFeed'),
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.translate('forYou')),
            Tab(text: l10n.translate('following')),
          ],
          indicatorColor: theme.colorScheme.primary,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() => _sortBy = value);
              _loadFeed();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'relevance', child: Text('Relevance (AI)')),
              const PopupMenuItem(value: 'recent', child: Text('Most Recent')),
              const PopupMenuItem(value: 'popular', child: Text('Most Popular')),
            ],
            icon: const Icon(Icons.sort_rounded),
            tooltip: l10n.translate('sortBy'),
          ),
          IconButton(
            onPressed: _loadFeed,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? _buildSkeleton(context)
          : TabBarView(
              controller: _tabController,
              children: [
                _buildForYouTab(),
                _buildFollowingTab(),
              ],
            ),
      );
    }
  }

  Widget _buildForYouTab() {
    if (_feed.isEmpty) {
      return _buildEmptyState(context);
    }

    return RefreshIndicator(
      onRefresh: _loadFeed,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _feed.length,
        itemBuilder: (context, index) {
          final article = _feed[index];
          final relevance = (article.structuredData['relevance_score'] as num?)?.toDouble() ?? 0.5;
          return _buildFeedCard(context, article, index, relevance);
        },
      ),
    );
  }

  Widget _buildFollowingTab() {
    // Show articles from explicitly followed sources/topics
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.rss_feed_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).translate('noFollowedSources'),
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).translate('followSourcesDesc'),
              style: GoogleFonts.outfit(color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showManageSources(),
              icon: const Icon(Icons.add_rounded),
              label: Text(AppLocalizations.of(context).translate('manageSources')),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildSkeleton(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(5, (i) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 100,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 16, width: 150, color: theme.colorScheme.surfaceContainerHighest),
                  const SizedBox(height: 8),
                  Container(height: 12, width: 200, color: theme.colorScheme.surfaceContainerHighest),
                ],
              ),
            ),
          ],
        ),
      ));
    });
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_rounded, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              l10n.translate('buildingYourFeed'),
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('feedBuildingDesc'),
              style: GoogleFonts.outfit(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadFeed,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.translate('refresh')),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildFeedCard(BuildContext context, NewsModel article, int index, double relevance) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return GestureDetector(
      onTap: () {
        _recordInteraction(article.url, 'click');
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => NewsDetailPage(article: article)),
        );
      },
      onLongPress: () => _showArticleActions(article),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero image
            if (article.imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNewsImage(
                    imageUrl: article.imageUrl,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: Icon(
                          Icons.image_not_supported_rounded,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Relevance indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getRelevanceColor(relevance),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.psychology_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${(relevance * 100).round()}% ${AppLocalizations.of(context).translate('match')}',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (article.aiSummary.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 10,
                                color: Theme.of(context).colorScheme.onSecondaryContainer,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                AppLocalizations.of(context).translate('aiSummary'),
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    article.title,
                    style: GoogleFonts.outfit(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                      height: 1.25,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          CategoryService.getCategoryDisplayName(
                            {'id': article.category, 'name': article.category},
                            context,
                          ),
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (article.sourceName.isNotEmpty)
                        Text(
                          article.sourceName,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      const Spacer(),
                      Text(
                        _getTimeAgo(article.publishDate),
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    article.summary.isNotEmpty ? article.summary : article.content.substring(0, 150),
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      height: 1.6,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (article.aiSummary.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.secondary.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 14,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                AppLocalizations.of(context).translate('aiSummary'),
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.secondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            article.aiSummary,
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              height: 1.6,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildActionButton(
                        context,
                        Icons.thumb_up_alt_outlined,
                        AppLocalizations.of(context).translate('like'),
                        () => _recordInteraction(article.url, 'like'),
                      ),
                      const SizedBox(width: 12),
                      _buildActionButton(
                        context,
                        Icons.share_outlined,
                        AppLocalizations.of(context).translate('share'),
                        () => _shareArticle(article),
                      ),
                      const SizedBox(width: 12),
                      _buildActionButton(
                        context,
                        Icons.bookmark_outline,
                        AppLocalizations.of(context).translate('save'),
                        () => _recordInteraction(article.url, 'save'),
                      ),
                      const Spacer(),
                      _buildActionButton(
                        context,
                        Icons.more_vert,
                        '',
                        () => _showArticleActions(article),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getRelevanceColor(double relevance) {
    if (relevance >= 0.8) return Colors.green[700]!;
    if (relevance >= 0.6) return Colors.blue[700]!;
    if (relevance >= 0.4) return Colors.orange[700]!;
    return Colors.grey[700]!;
  }

  Widget _buildActionButton(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showArticleActions(NewsModel article) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                article.title,
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.thumb_up_alt_outlined),
                title: Text(AppLocalizations.of(context).translate('like')),
                onTap: () {
                  Navigator.pop(context);
                  _recordInteraction(article.url, 'like');
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: Text(AppLocalizations.of(context).translate('share')),
                onTap: () {
                  Navigator.pop(context);
                  _shareArticle(article);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: Text(AppLocalizations.of(context).translate('save')),
                onTap: () {
                  Navigator.pop(context);
                  _recordInteraction(article.url, 'save');
                },
              ),
              ListTile(
                leading: const Icon(Icons.translate_outlined),
                title: Text(AppLocalizations.of(context).translate('translate')),
                onTap: () {
                  Navigator.pop(context);
                  _showTranslationDialog(article);
                },
              ),
              ListTile(
                leading: const Icon(Icons.psychology_outlined),
                title: Text(AppLocalizations.of(context).translate('askThisNews')),
                onTap: () {
                  Navigator.pop(context);
                  _showAskNewsDialog(article);
                },
              ),
              ListTile(
                leading: Icon(Icons.report_outlined, color: Theme.of(context).colorScheme.error),
                title: Text(
                  AppLocalizations.of(context).translate('report'),
                  style: GoogleFonts.outfit(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _reportArticle(article);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTranslationDialog(NewsModel article) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).translate('translate')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['ar', 'en', 'fr'].map((lang) => ListTile(
            leading: Text(YallaLanguageExt.fromString(lang).flag),
            title: Text(YallaLanguageExt.fromString(lang).nativeName),
            onTap: () {
              Navigator.pop(context);
              _translateArticle(article, lang);
            },
          )).toList(),
        ),
      ),
    );
  }

  Future<void> _translateArticle(NewsModel article, String targetLang) async {
    // Implementation would use AI service
  }

  void _showAskNewsDialog(NewsModel article) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(AppLocalizations.of(context).translate('askThisNews'))),
          body: AskThisNewsWidget(article: article, startOpen: true),
        ),
      ),
    );
  }

  void _shareArticle(NewsModel article) {
    // Share implementation
  }

  void _reportArticle(NewsModel article) {
    // Report implementation
  }

  void _showManageSources() {
    // Navigate to sources management
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

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }
}