// Related Articles Widget
// Shows cluster-based related articles with multi-source support

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import '../database/news_db.dart' show NewsDatabase;
import '../services/category_service.dart';
import '../views/news_detail_page.dart';

class RelatedArticlesWidget extends StatefulWidget {
  final NewsModel article;
  final int maxArticles;
  final bool showClusterBadge;

  const RelatedArticlesWidget({
    super.key,
    required this.article,
    this.maxArticles = 6,
    this.showClusterBadge = true,
  });

  @override
  State<RelatedArticlesWidget> createState() => _RelatedArticlesWidgetState();
}

class _RelatedArticlesWidgetState extends State<RelatedArticlesWidget> {
  List<NewsModel> _relatedArticles = [];
  bool _isLoading = false;
  int _clusterId = -1;

  @override
  void initState() {
    super.initState();
    _loadRelatedArticles();
  }

  Future<void> _loadRelatedArticles() async {
    setState(() => _isLoading = true);

    try {
      final db = await NewsDatabase.instance.database;
      final clusterResult = await db.query(
        'yn_events',
        columns: ['cluster_id'],
        where: 'article_url = ?',
        whereArgs: [widget.article.url],
        limit: 1,
      );

      if (clusterResult.isNotEmpty) {
        _clusterId = clusterResult.first['cluster_id'] as int? ?? -1;
      }

      List<NewsModel> related = [];

      if (_clusterId >= 0) {
        final clusterArticles = await db.query(
          'yn_events',
          where: 'cluster_id = ? AND article_url != ?',
          whereArgs: [_clusterId, widget.article.url],
          limit: widget.maxArticles,
        );

        for (final row in clusterArticles) {
          final articleUrl = row['article_url'] as String;
          final articleData = await db.query(
            'crawled_articles',
            where: 'url = ?',
            whereArgs: [articleUrl],
            limit: 1,
          );
          if (articleData.isNotEmpty) {
            related.add(NewsModel.fromJson(
              Map<String, dynamic>.from(articleData.first),
              articleData.first['url'] as String,
            ));
          }
        }
      }

      if (related.length < widget.maxArticles) {
        final category = widget.article.category;
        final language = widget.article.language;
        final excludeUrl = widget.article.url;

        final fallbackArticles = await db.query(
          'crawled_articles',
          where: 'category = ? AND language = ? AND url != ?',
          whereArgs: [category, language, excludeUrl],
          orderBy: 'crawled_at DESC',
          limit: widget.maxArticles - related.length,
        );

        for (final row in fallbackArticles) {
          related.add(NewsModel.fromJson(
            Map<String, dynamic>.from(row),
            row['url'] as String,
          ));
        }
      }

      if (mounted) {
        setState(() {
          _relatedArticles = related.take(widget.maxArticles).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (_isLoading) {
      return _buildSkeleton(context);
    }

    if (_relatedArticles.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.topic_rounded,
                    size: 20,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _clusterId >= 0
                      ? l10n.translate('relatedInEvent')
                      : l10n.translate('relatedArticles'),
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (widget.showClusterBadge && _clusterId >= 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${l10n.translate('event')} #$_clusterId',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _relatedArticles.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final article = _relatedArticles[index];
              return _buildRelatedCard(context, article, index);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: List.generate(3, (index) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 80,
              height: 60,
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
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 12,
                    width: 120,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      )),
    );
  }

  Widget _buildRelatedCard(BuildContext context, NewsModel article, int index) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NewsDetailPage(article: article)),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 80,
                height: 60,
                child: article.imageUrl.isNotEmpty
                    ? Image.network(
                        article.imageUrl,
                        width: 80,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholderImage(context),
                      )
                    : _placeholderImage(context),
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
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _getCategoryDisplayName(article.category, context),
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

  Widget _placeholderImage(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 80,
      height: 60,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
            theme.colorScheme.surfaceContainerHighest,
          ],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(
          Icons.image_not_supported_rounded,
          size: 24,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  String _getCategoryDisplayName(String category, BuildContext context) {
    return CategoryService.getCategoryDisplayName(
      {'id': category, 'name': category},
      context,
    );
  }

  String _getTimeAgo(String publishDate) {
    try {
      final date = DateTime.parse(publishDate);
      final diff = DateTime.now().difference(date);
      final l10n = AppLocalizations.of(context);
      if (diff.inDays > 0) return '${diff.inDays} ${l10n.translate('timeDays')}';
      if (diff.inHours > 0) return '${diff.inHours} ${l10n.translate('timeHours')}';
      if (diff.inMinutes > 0) return '${diff.inMinutes} ${l10n.translate('timeMinutes')}';
      return l10n.translate('timeNow');
    } catch (_) {
      return '';
    }
  }
}