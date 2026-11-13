// Event Detail Page - Multi-source Event View

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import '../database/news_db.dart';
import '../widgets/cached_news_image.dart';
import 'news_detail_page.dart';

class EventDetailPage extends StatefulWidget {
  final int clusterId;
  final String? eventLabel;

  const EventDetailPage({
    super.key,
    required this.clusterId,
    this.eventLabel,
  });

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  final Map<String, dynamic> _eventData = {};
  List<NewsModel> _articles = [];
  bool _isLoading = true;
  String? _error;
  Map<String, int> _sourceCounts = {};
  Map<String, List<String>> _entitiesByType = {};

  @override
  void initState() {
    super.initState();
    _loadEvent();
  }

  Future<void> _loadEvent() async {
    setState(() => _isLoading = true);

    try {
      final db = await NewsDatabase.instance.database;

      final eventInfo = await db.query(
        'yn_events',
        where: 'cluster_id = ?',
        whereArgs: [widget.clusterId],
        limit: 1,
      );

      if (eventInfo.isNotEmpty) {
        _eventData.addAll(Map<String, dynamic>.from(eventInfo.first));
      }

      final articleUrls = await db.query(
        'yn_events',
        columns: ['article_url'],
        where: 'cluster_id = ?',
        whereArgs: [widget.clusterId],
      );

      final articles = <NewsModel>[];
      for (final row in articleUrls) {
        final url = row['article_url'] as String;
        final articleDb = await NewsDatabase.instance.database;
        final articleData = await articleDb.query(
          'crawled_articles',
          where: 'url = ?',
          whereArgs: [url],
          limit: 1,
        );
        if (articleData.isNotEmpty) {
          articles.add(NewsModel.fromJson(
            Map<String, dynamic>.from(articleData.first),
            articleData.first['url'] as String,
          ));
        }
      }

      articles.sort((a, b) {
        try {
          final dateA = DateTime.parse(a.publishDate);
          final dateB = DateTime.parse(b.publishDate);
          return dateB.compareTo(dateA);
        } catch (_) {
          return 0;
        }
      });

      final sourceCounts = <String, int>{};
      for (final article in articles) {
        final source = article.sourceName.isNotEmpty
            ? article.sourceName
            : article.displaySourceName;
        if (source.isNotEmpty) {
          sourceCounts[source] = (sourceCounts[source] ?? 0) + 1;
        }
      }

      final entitiesByType = <String, List<String>>{};
      for (final article in articles) {
        for (final entity in article.entities) {
          entitiesByType.putIfAbsent('entities', () => []).add(entity);
        }
      }

      if (mounted) {
        setState(() {
          _articles = articles;
          _sourceCounts = sourceCounts;
          _entitiesByType = entitiesByType;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.eventLabel ?? l10n.translate('eventDetail'),
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: _isLoading
          ? _buildSkeleton(context)
          : _error != null
              ? _buildError(context)
              : _buildContent(context),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate(3, (i) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
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
                    Container(
                      height: 16,
                      width: 150,
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 12,
                      width: 200,
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ],
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).translate('errorLoadingEvent'),
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: GoogleFonts.outfit(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadEvent,
              child: Text(AppLocalizations.of(context).translate('tryAgain')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.eventLabel != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.eventLabel!,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  _eventData['label'] as String? ?? l10n.translate('eventDetail'),
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildStatChip(
                      context,
                      Icons.article_rounded,
                      _articles.length.toString(),
                      l10n.translate('sources'),
                    ),
                    const SizedBox(width: 12),
                    _buildStatChip(
                      context,
                      Icons.topic_rounded,
                      _sourceCounts.length.toString(),
                      l10n.translate('publishers'),
                    ),
                    const SizedBox(width: 12),
                    _buildStatChip(
                      context,
                      Icons.timeline_rounded,
                      _getDateRange(),
                      l10n.translate('timespan'),
                    ),
                  ],
                ),
                if (_entitiesByType.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    l10n.translate('keyEntities'),
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _entitiesByType.entries
                        .take(10)
                        .map((entry) => Chip(
                          label: Text(entry.key),
                          avatar: Icon(_getEntityIcon(entry.key), size: 16),
                          backgroundColor:
                              theme.colorScheme.primaryContainer.withOpacity(0.3),
                        ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _buildSourcesSection(context),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final article = _articles[index];
                return _buildArticleTimelineItem(context, article, index);
              },
              childCount: _articles.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatChip(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.1),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDateRange() {
    if (_articles.isEmpty) return '';
    try {
      final dates = _articles
          .map((a) => DateTime.tryParse(a.publishDate))
          .whereType<DateTime>()
          .toList();
      if (dates.isEmpty) return '';
      final earliest = dates.reduce(
        (a, b) => a.isBefore(b) ? a : b,
      );
      final latest = dates.reduce(
        (a, b) => a.isAfter(b) ? a : b,
      );
      final diff = latest.difference(earliest).inDays;
      if (diff == 0) return 'Today';
      if (diff == 1) return '1 day';
      if (diff < 7) return '$diff days';
      if (diff < 30) return '${(diff / 7).ceil()} weeks';
      return '${(diff / 30).ceil()} months';
    } catch (_) {
      return '';
    }
  }

  Widget _buildSourcesSection(BuildContext context) {
    final theme = Theme.of(context);
    final sortedSources = _sourceCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.source_rounded,
                  color: theme.colorScheme.secondary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  AppLocalizations.of(context).translate('sources'),
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...sortedSources.take(10).map((entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            entry.key.isNotEmpty
                                ? entry.key[0].toUpperCase()
                                : '?',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onPrimaryContainer,
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
                              entry.key,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${entry.value} ${AppLocalizations.of(context).translate('articles')}',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${entry.value}',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildArticleTimelineItem(
    BuildContext context,
    NewsModel article,
    int index,
  ) {
    final theme = Theme.of(context);
    final isLast = index == _articles.length - 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 3,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: theme.colorScheme.outline.withOpacity(0.3),
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NewsDetailPage(article: article),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: article.imageUrl.isNotEmpty
                            ? CachedNewsImage(
                                imageUrl: article.imageUrl,
                                fallbackImageUrl:
                                    NewsModel.getFallbackImage(article.category),
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.image_not_supported_rounded,
                                  color: theme.colorScheme
                                      .onSurfaceVariant
                                      .withOpacity(0.5),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _getTimeDisplay(article.publishDate),
                                  style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  article.sourceName.isNotEmpty
                                      ? article.sourceName
                                      : article.displaySourceName,
                                  style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme
                                        .onPrimaryContainer,
                                  ),
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
            ),
          ),
        ],
      ),
    );
  }

  String _getTimeDisplay(String publishDate) {
    try {
      final date = DateTime.parse(publishDate);
      final now = DateTime.now();
      final diff = now.difference(date);
      final l10n = AppLocalizations.of(context);
      if (diff.inDays > 0) return '${diff.inDays} ${l10n.translate('timeDays')}';
      if (diff.inHours > 0) return '${diff.inHours} ${l10n.translate('timeHours')}';
      if (diff.inMinutes > 0) return '${diff.inMinutes} ${l10n.translate('timeMinutes')}';
      return l10n.translate('timeNow');
    } catch (_) {
      return '';
    }
  }

  IconData _getEntityIcon(String entityType) {
    switch (entityType.toLowerCase()) {
      case 'person':
      case 'people':
        return Icons.person_rounded;
      case 'organization':
      case 'org':
        return Icons.business_rounded;
      case 'location':
      case 'place':
        return Icons.location_on_rounded;
      case 'date':
      case 'time':
        return Icons.calendar_today_rounded;
      case 'money':
      case 'currency':
        return Icons.attach_money_rounded;
      default:
        return Icons.label_rounded;
    }
  }
}