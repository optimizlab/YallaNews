// Daily Briefing Page
// Scheduled notification + digest view with personalized content

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import '../database/news_db.dart';
import '../services/ai_service.dart';
import '../services/category_service.dart';
import '../widgets/cached_news_image.dart';
import '../views/news_detail_page.dart';

class DailyBriefingPage extends StatefulWidget {
  const DailyBriefingPage({Key? key}) : super(key: key);

  @override
  State<DailyBriefingPage> createState() => _DailyBriefingPageState();
}

class _DailyBriefingPageState extends State<DailyBriefingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<NewsModel> _topStories = [];
  List<NewsModel> _personalized = [];
  List<NewsModel> _briefing = [];
  bool _isLoading = true;
  bool _notificationsEnabled = false;
  TimeOfDay _briefingTime = const TimeOfDay(hour: 7, minute: 0);
  Set<String> _selectedCategories = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSettings();
    _loadBriefing();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt('briefing_hour') ?? 7;
    final minute = prefs.getInt('briefing_minute') ?? 0;
    final enabled = prefs.getBool('briefing_enabled') ?? false;
    final cats = prefs.getStringList('briefing_categories') ?? [];

    if (mounted) {
      setState(() {
        _briefingTime = TimeOfDay(hour: hour, minute: minute);
        _notificationsEnabled = enabled;
        _selectedCategories = cats.toSet();
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('briefing_hour', _briefingTime.hour);
    await prefs.setInt('briefing_minute', _briefingTime.minute);
    await prefs.setBool('briefing_enabled', _notificationsEnabled);
    await prefs.setStringList('briefing_categories', _selectedCategories.toList());

    if (_notificationsEnabled) {
      await _scheduleBriefingNotification();
    } else {
      await Workmanager().cancelByUniqueName('daily_briefing');
    }
  }

  Future<void> _scheduleBriefingNotification() async {
    await Workmanager().registerPeriodicTask(
      'daily_briefing',
      'com.yallanews.daily_briefing',
      frequency: const Duration(hours: 24),
      initialDelay: _calculateInitialDelay(),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
    );
  }

  Duration _calculateInitialDelay() {
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, _briefingTime.hour, _briefingTime.minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled.difference(now);
  }

  Future<void> _loadBriefing() async {
    setState(() => _isLoading = true);

    try {
      final db = await NewsDatabase.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final dayAgo = now - (24 * 60 * 60 * 1000);

      // Get top stories (high relevance)
      final topQuery = await db.query(
        'crawled_articles',
        where: 'crawled_at > ?',
        whereArgs: [dayAgo],
        orderBy: 'crawled_at DESC',
        limit: 20,
      );

      final topArticles = topQuery.map((row) => NewsModel.fromJson(
        Map<String, dynamic>.from(row),
        row['url'] as String,
      )).toList();

      // Get personalized based on selected categories
      List<NewsModel> personalized = [];
      if (_selectedCategories.isNotEmpty) {
        final placeholders = _selectedCategories.map((_) => '?').join(',');
        final persQuery = await db.query(
          'crawled_articles',
          where: 'crawled_at > ? AND category IN ($placeholders)',
          whereArgs: [dayAgo, ..._selectedCategories],
          orderBy: 'crawled_at DESC',
          limit: 15,
        );
        personalized = persQuery.map((row) => NewsModel.fromJson(
          Map<String, dynamic>.from(row),
          row['url'] as String,
        )).toList();
      }

      // Generate AI briefing if available
      final aiService = AIService.instance;
      List<NewsModel> briefing = [];
      if (aiService.isReady && topArticles.isNotEmpty) {
        try {
          // Use AI to select and summarize top stories
          briefing = await _generateBriefing(topArticles);
        } catch (_) {
          briefing = topArticles.take(5).toList();
        }
      } else {
        briefing = topArticles.take(5).toList();
      }

      if (mounted) {
        setState(() {
          _topStories = topArticles;
          _personalized = personalized;
          _briefing = briefing;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<NewsModel>> _generateBriefing(List<NewsModel> articles) async {
    final aiService = AIService.instance;
    
    // Use AI to rank and select top 5
    final prompt = '''
Select the 5 most important news stories from this list for a daily briefing.
Consider: impact, recency, diversity of topics, and reader interest.
Return the URLs of the selected 5 articles, one per line.

Articles:
${articles.take(15).map((a) => '${a.url} | ${a.title} | ${a.category}').join('\n')}
''';

    final result = await aiService.generate(
      prompt: prompt,
      maxTokens: 200,
      temperature: 0.1,
    );

    final urls = result['text']
        ?.split('\n')
        .where((l) => l.trim().startsWith('http'))
        .toSet() ?? {};

    return articles.where((a) => urls.contains(a.url)).take(5).toList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.translate('dailyBriefing'),
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.translate('briefing')),
            Tab(text: l10n.translate('topStories')),
            Tab(text: l10n.translate('forYou')),
          ],
          indicatorColor: theme.colorScheme.primary,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            onPressed: _showSettingsDialog,
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? _buildSkeleton(context)
          : TabBarView(
              controller: _tabController,
              children: [
                _buildBriefingTab(context),
                _buildTopStoriesTab(context),
                _buildPersonalizedTab(context),
],
        );
      }

  Widget _buildSkeleton(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(3, (i) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
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
      ),
    );
  }

  Widget _buildBriefingTab(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (_briefing.isEmpty) {
      return _buildEmptyState(context, l10n.translate('noBriefingYet'));
    }

    return RefreshIndicator(
      onRefresh: _loadBriefing,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _briefing.length,
        itemBuilder: (context, index) {
          final article = _briefing[index];
          return _buildBriefingCard(context, article, index + 1);
        },
      ),
    );
  }

  Widget _buildTopStoriesTab(BuildContext context) {
    if (_topStories.isEmpty) {
      return _buildEmptyState(context, AppLocalizations.of(context).translate('noTopStories'));
    }

    return RefreshIndicator(
      onRefresh: _loadBriefing,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _topStories.length,
        itemBuilder: (context, index) {
          final article = _topStories[index];
          return _buildArticleCard(context, article);
        },
      ),
    );
  }

  Widget _buildPersonalizedTab(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (_selectedCategories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline_rounded, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                l10n.translate('personalizeBriefing'),
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.translate('selectCategoriesForBriefing'),
                style: GoogleFonts.outfit(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _showSettingsDialog,
                icon: const Icon(Icons.tune_rounded),
                label: Text(l10n.translate('customizeCategories')),
              ),
],
        );
      }

    if (_personalized.isEmpty) {
      return _buildEmptyState(context, l10n.translate('noPersonalizedArticles'));
    }

    return RefreshIndicator(
      onRefresh: _loadBriefing,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _personalized.length,
        itemBuilder: (context, index) {
          return _buildArticleCard(context, _personalized[index]);
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String message) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.newspaper_rounded, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              message,
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('pullToRefresh'),
              style: GoogleFonts.outfit(color: theme.colorScheme.onSurfaceVariant),
            ),
],
        ),
      );
    }

  Widget _buildBriefingCard(BuildContext context, NewsModel article, int index) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NewsDetailPage(article: article)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Number badge
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.colorScheme.primaryContainer, theme.colorScheme.primary],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onPrimaryContainer,
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
                          article.title,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                            height: 1.3,
                          ),
                        ),
                      ),
                      if (article.aiSummary.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            l10n.translate('aiSummary'),
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    article.summary.isNotEmpty ? article.summary : article.content.substring(0, 150),
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          CategoryService.getCategoryDisplayName(
                            {'id': article.category, 'name': article.category},
                            context,
                          ),
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (article.aiSummary.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 10,
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                l10n.translate('aiGenerated'),
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ],
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

  Widget _buildArticleCard(BuildContext context, NewsModel article) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NewsDetailPage(article: article)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 100,
                height: 80,
                child: article.imageUrl.isNotEmpty
                    ? CachedNewsImage(
                        imageUrl: article.imageUrl,
                        width: 100,
                        height: 80,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.image_not_supported_rounded,
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          CategoryService.getCategoryDisplayName(
                            {'id': article.category, 'name': article.category},
                            context,
                          ),
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _getTimeAgo(article.publishDate),
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

  void _showSettingsDialog() {
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
                    AppLocalizations.of(context).translate('briefingSettings'),
                    style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Notifications toggle
              SwitchListTile(
                title: Text(
                  AppLocalizations.of(context).translate('enableDailyBriefing'),
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  AppLocalizations.of(context).translate('dailyBriefingDesc'),
                  style: GoogleFonts.outfit(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                value: _notificationsEnabled,
                onChanged: (val) {
                  setState(() => _notificationsEnabled = val);
                  _saveSettings();
                },
                activeColor: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              // Time picker
              ListTile(
                leading: Icon(Icons.access_time_rounded, color: Theme.of(context).colorScheme.primary),
                title: Text(
                  AppLocalizations.of(context).translate('briefingTime'),
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _briefingTime.format(context),
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: _briefingTime,
                  );
                  if (time != null) {
                    setState(() => _briefingTime = time);
                    _saveSettings();
                  }
                },
              ),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context).translate('briefingCategories'),
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  'politics', 'business', 'technology', 'sports', 'health', 'science', 'culture', 'world', 'society', 'entertainment'
                ].map((cat) {
                  final selected = _selectedCategories.contains(cat);
                  return FilterChip(
                    label: Text(CategoryService.getCategoryDisplayName(
                      {'id': cat, 'name': cat},
                      context,
                    )),
                    selected: selected,
                    onSelected: (val) {
                      setState(() {
                        if (val) _selectedCategories.add(cat);
                        else _selectedCategories.remove(cat);
                      });
                      _saveSettings();
                    },
                    selectedColor: Theme.of(context).colorScheme.primary,
                    checkmarkColor: Theme.of(context).colorScheme.onPrimary,
                  );
                }).toList(),
              ),
            ],
),
      ),
    );
  }
}