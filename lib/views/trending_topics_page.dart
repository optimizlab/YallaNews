// Trending Topics Page
// Real-time topic ranking with category filters and time windows

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite/sqflite.dart';
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import '../database/news_db.dart';
import '../services/ai_service.dart';
import '../services/category_service.dart';
import '../services/app_settings.dart';
import '../views/news_detail_page.dart';

class TrendingTopicsPage extends StatefulWidget {
  const TrendingTopicsPage({super.key});

  @override
  State<TrendingTopicsPage> createState() => _TrendingTopicsPageState();
}

class _TrendingTopicsPageState extends State<TrendingTopicsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<TrendingTopic> _topics = [];
  bool _isLoading = true;
  String _selectedTimeWindow = '24h';
  String _selectedCategory = 'all';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadTrendingTopics();
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) => _loadTrendingTopics());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTrendingTopics() async {
    setState(() => _isLoading = true);

    try {
      final db = await NewsDatabase.instance.database;
      final timeWindowMs = _getTimeWindowMs(_selectedTimeWindow);
      final now = DateTime.now().millisecondsSinceEpoch;
      final cutoff = now - timeWindowMs;
      final activeLanguage = AppSettings.instance.locale?.languageCode ?? '';

      String whereClause = 'crawled_at > ?';
      List<dynamic> whereArgs = [cutoff];

      if (activeLanguage.isNotEmpty) {
        whereClause += ' AND language = ?';
        whereArgs.add(activeLanguage);
      }

      if (_selectedCategory != 'all') {
        whereClause += ' AND category = ?';
        whereArgs.add(_selectedCategory);
      }

      final articles = await db.query(
        'crawled_articles',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'crawled_at DESC',
        limit: 500,
      );

      final topics = await _extractTopics(articles);

      if (mounted) {
        setState(() {
          _topics = topics;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _getTimeWindowMs(String window) {
    switch (window) {
      case '1h':
        return 60 * 60 * 1000;
      case '6h':
        return 6 * 60 * 60 * 1000;
      case '24h':
        return 24 * 60 * 60 * 1000;
      case '7d':
        return 7 * 24 * 60 * 60 * 1000;
      default:
        return 24 * 60 * 60 * 1000;
    }
  }

  Future<List<TrendingTopic>> _extractTopics(List<Map<String, dynamic>> articles) async {
    final aiService = AIService.instance;

    if (aiService.isReady && articles.isNotEmpty) {
      try {
        articles.take(50).map((a) => {
          'title': a['title'],
          'content': a['content'],
          'category': a['category'],
        }).toList();

        await aiService.generate(
          prompt: 'Extract the top 10 trending topics from these news articles. For each topic, provide: topic name, brief description, category, and relevance score (1-100). Return as JSON array.',
          maxTokens: 1000,
          temperature: 0.3,
        );
      } catch (_) {}
    }

    return _keywordFrequencyAnalysis(articles);
  }

  List<TrendingTopic> _keywordFrequencyAnalysis(List<Map<String, dynamic>> articles) {
    final topicCounts = <String, TopicData>{};
    final stopWords = {
      'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by', 'from',
      'as', 'is', 'was', 'are', 'were', 'be', 'been', 'being', 'have', 'has', 'had', 'do', 'does', 'did',
      'will', 'would', 'could', 'should', 'may', 'might', 'must', 'can', 'this', 'that', 'these', 'those',
      'said', 'says', 'say', 'according', 'report', 'reports', 'news', 'new', 'breaking', 'latest',
      'ال', 'في', 'على', 'من', 'إلى', 'مع', 'عن', 'هذا', 'هذه', 'ذلك', 'تلك', 'التي', 'الذي',
      'le', 'la', 'les', 'un', 'une', 'des', 'et', 'ou', 'mais', 'dans', 'sur', 'à', 'de', 'du',
    };

    for (final article in articles) {
      final title = (article['title'] as String? ?? '').toLowerCase();
      final content = (article['content'] as String? ?? '').toLowerCase();
      final category = (article['category'] as String? ?? 'general');
      final url = (article['url'] as String? ?? '');
      final publishDate = DateTime.tryParse(article['publish_date'] as String? ?? '') ?? DateTime.now();
      String source = (article['source_name'] as String? ?? '');
      if (source.isEmpty) {
        source = (article['display_source_name'] as String? ?? '');
      }

      final text = '$title $content';
      final words = text.split(RegExp(r'\W+'));

      for (int i = 0; i < words.length - 1; i++) {
        final w1 = words[i];
        final w2 = words[i + 1];
        if (w1.length > 2 && w2.length > 2 && !stopWords.contains(w1) && !stopWords.contains(w2)) {
          final phrase = '$w1 $w2';
          final data = topicCounts.putIfAbsent(phrase, () => TopicData(
            name: phrase,
            category: category,
          ));
          data.count++;
          data.articleUrls.add(url);
          data.sources[source] = (data.sources[source] ?? 0) + 1;
          data.lastSeen = publishDate.isAfter(data.lastSeen) ? publishDate : data.lastSeen;
        }
      }
    }

    final topics = topicCounts.entries
        .where((e) => e.value.count >= 2)
        .map((e) => TrendingTopic.fromData(e.key, e.value))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return topics.take(20).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.translate('trendingTopics'),
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: ['1h', '6h', '24h', '7d'].map((w) => Tab(
                  child: Text(w, style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                )).toList(),
                onTap: (index) {
                  setState(() => _selectedTimeWindow = ['1h', '6h', '24h', '7d'][index]);
                  _loadTrendingTopics();
                },
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: ['all', 'politics', 'business', 'technology', 'sports', 'health', 'science', 'culture', 'world', 'society', 'entertainment']
                      .map((cat) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(
                                cat == 'all' ? l10n.translate('all') : CategoryService.getCategoryDisplayName(
                                  {'id': cat, 'name': cat},
                                  context,
                                ),
                              ),
                              selected: _selectedCategory == cat,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _selectedCategory = cat);
                                  _loadTrendingTopics();
                                }
                              },
                              selectedColor: theme.colorScheme.primary,
                              checkmarkColor: theme.colorScheme.onPrimary,
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? _buildSkeleton(context)
          : _topics.isEmpty
              ? _buildEmptyState(context)
              : RefreshIndicator(
                  onRefresh: _loadTrendingTopics,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _topics.length,
                    itemBuilder: (context, index) {
                      final topic = _topics[index];
                      return _buildTopicCard(context, topic, index + 1);
                    },
                  ),
                ),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(5, (i) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 16),
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
      ),
    ));
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
            Icon(Icons.trending_down_rounded, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              l10n.translate('noTrendingTopics'),
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('noTrendingTopicsDesc'),
              style: GoogleFonts.outfit(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicCard(BuildContext context, TrendingTopic topic, int rank) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return GestureDetector(
      onTap: () => _showTopicDetail(context, topic),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: rank <= 3
                    ? LinearGradient(
                        colors: rank == 1
                            ? [Colors.amber[700]!, Colors.amber[500]!]
                            : rank == 2
                                ? [Colors.grey[700]!, Colors.grey[500]!]
                                : [Colors.brown[700]!, Colors.brown[500]!],
                      )
                    : LinearGradient(
                        colors: [theme.colorScheme.primaryContainer, theme.colorScheme.primary],
                      ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '#$rank',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: rank <= 3 ? Colors.white : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          topic.name,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${topic.score}',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    topic.description,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          topic.category,
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ...topic.topSources.take(3).map((s) => Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              s.length > 12 ? '${s.substring(0, 12)}…' : s,
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )),
                      const Spacer(),
                      Text(
                        '${topic.articleCount} ${l10n.translate('articles')}',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
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

  void _showTopicDetail(BuildContext context, TrendingTopic topic) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    topic.name,
                    style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '#${_topics.indexOf(topic) + 1} • ${topic.score} ${AppLocalizations.of(context).translate('trendingScore')}',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                topic.description,
                style: GoogleFonts.outfit(fontSize: 15, height: 1.7),
              ),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context).translate('relatedArticles'),
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ...topic.articleUrls.take(5).map((url) => _buildTopicArticleItem(context, url)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopicArticleItem(BuildContext context, String url) {
    return FutureBuilder<Database>(
      future: NewsDatabase.instance.database,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final db = snapshot.data!;
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: db.query(
            'crawled_articles',
            where: 'url = ?',
            whereArgs: [url],
            limit: 1,
          ),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const SizedBox.shrink();
            }
            final article = NewsModel.fromJson(
              Map<String, dynamic>.from(snapshot.data!.first),
              snapshot.data!.first['url'] as String,
            );
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 60,
                  height: 45,
                  child: article.imageUrl.isNotEmpty
                      ? Image.network(article.imageUrl, fit: BoxFit.cover)
                      : Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                ),
              ),
              title: Text(
                article.title,
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                article.sourceName,
                style: GoogleFonts.outfit(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => NewsDetailPage(article: article)),
                );
              },
            );
          },
        );
      },
    );
  }
}

// Data classes for trending topics
class TrendingTopic {
  final String name;
  final String description;
  final String category;
  final int score;
  final int articleCount;
  final List<String> articleUrls;
  final List<String> topSources;
  final DateTime lastUpdated;

  TrendingTopic({
    required this.name,
    required this.description,
    required this.category,
    required this.score,
    required this.articleCount,
    required this.articleUrls,
    required this.topSources,
    required this.lastUpdated,
  });

  factory TrendingTopic.fromData(String name, TopicData data) {
    final sortedSources = data.sources.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return TrendingTopic(
      name: name,
      description: 'Trending topic with ${data.count} mentions across ${data.articleUrls.length} articles',
      category: data.category,
      score: data.count * 10 + data.articleUrls.length * 5,
      articleCount: data.articleUrls.length,
      articleUrls: data.articleUrls,
      topSources: sortedSources.take(5).map((e) => e.key).toList(),
      lastUpdated: data.lastSeen,
    );
  }
}

class TopicData {
  String name;
  String category;
  int count = 0;
  List<String> articleUrls = [];
  Map<String, int> sources = {};
  DateTime lastSeen = DateTime.now();

  TopicData({
    required this.name,
    required this.category,
    this.articleUrls = const [],
    this.sources = const {},
  });
}