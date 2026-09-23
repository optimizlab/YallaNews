import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import '../database/news_db.dart';
import 'news_detail_page.dart';

class BookmarksPage extends StatefulWidget {
  const BookmarksPage({Key? key}) : super(key: key);

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  List<NewsModel> _bookmarks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    setState(() => _isLoading = true);
    try {
      final db = NewsDatabase.instance;
      final articles = await db.getAllArticles(limit: 100);
      setState(() {
        _bookmarks = articles.take(3).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.translate('savedArticles'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.translate('youHaveSavedArticles'),
                  style: GoogleFonts.outfit(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  l10n.translate('replaceBookmarks'),
                  style: GoogleFonts.outfit(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          _isLoading
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(),
                ))
              : _bookmarks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Text(
                          l10n.translate('noSavedArticles'),
                          style: GoogleFonts.outfit(fontSize: 16, color: const Color(0xFF999999)),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _bookmarks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final article = _bookmarks[index];
                        return _buildBookmarkCard(article, context);
                      },
                    ),
        ],
      ),
    );
  }

  Widget _buildBookmarkCard(NewsModel article, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => NewsDetailPage(article: article)));
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface, height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.favorite_border_rounded, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          '${(article.sentiment * 1000).toInt()}',
                          style: GoogleFonts.outfit(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${l10n.translate('yalla')} ${_getSourceName(article, context)}',
                          style: GoogleFonts.outfit(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _getCategoryLabel(article.category, context),
                            style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getReadTime(article, context),
                          style: GoogleFonts.outfit(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  article.imageUrl,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildFallbackImage(article.category),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackImage(String category) {
    return Container(
      width: 72,
      height: 72,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.newspaper_outlined, size: 24, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  String _getCategoryLabel(String category, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (category.toLowerCase()) {
      case 'technology':
        return l10n.translate('technology');
      case 'sports':
        return l10n.translate('sports');
      case 'politics':
        return l10n.translate('politics');
      case 'business':
        return l10n.translate('business');
      case 'health':
        return l10n.translate('health');
      case 'science':
        return l10n.translate('science');
      case 'entertainment':
        return l10n.translate('entertainment');
      case 'world':
        return l10n.translate('world');
      default:
        return l10n.translate('generalNews');
    }
  }

  String _getReadTime(NewsModel article, BuildContext context) {
    final words = article.content.split(' ').length;
    final minutes = (words / 200).ceil();
    return '$minutes ${AppLocalizations.of(context).translate('readTimeUnit')}';
  }

  String _getSourceName(NewsModel article, BuildContext context) {
    try {
      final uri = Uri.parse(article.url);
      return uri.host.split('.').first;
    } catch (_) {
      return AppLocalizations.of(context).translate('news');
    }
  }
}