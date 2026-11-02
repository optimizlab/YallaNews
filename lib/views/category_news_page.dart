import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import '../services/category_service.dart';
import '../services/analytics_service.dart';
import '../services/server_api_service.dart';
import '../widgets/cached_news_image.dart';
import '../widgets/shimmer_loading.dart';
import 'news_detail_page.dart';

class CategoryNewsPage extends StatefulWidget {
  final Map<String, dynamic> category;

  const CategoryNewsPage({
    Key? key,
    required this.category,
  }) : super(key: key);

  @override
  State<CategoryNewsPage> createState() => _CategoryNewsPageState();
}

class _CategoryNewsPageState extends State<CategoryNewsPage> {
  final List<NewsModel> _articles = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  late final ScrollController _scrollController;
  String _searchQuery = '';

  String get categoryId => widget.category['id']?.toString() ?? 'general';

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadNews();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore && !_isLoading) {
        _loadMore();
      }
    }
  }

  Future<void> _loadNews() async {
    setState(() {
      _isLoading = true;
      _currentPage = 1;
      _hasMore = true;
    });

    try {
      final fetched = await ServerApiService.getNews(
        limit: 20,
        page: 1,
        category: categoryId,
      );

      if (mounted) {
        setState(() {
          _articles.clear();
          _articles.addAll(fetched);
          _hasMore = fetched.length >= 20;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final fetched = await ServerApiService.getNews(
        limit: 20,
        page: nextPage,
        category: categoryId,
      );

      if (mounted) {
        setState(() {
          _currentPage = nextPage;
          final existingUrls = _articles.map((a) => a.url).toSet();
          for (final a in fetched) {
            if (!existingUrls.contains(a.url)) {
              _articles.add(a);
            }
          }
          _hasMore = fetched.length >= 20;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  List<NewsModel> get _filteredArticles {
    if (_searchQuery.trim().isEmpty) return _articles;
    final q = _searchQuery.toLowerCase();
    return _articles.where((a) => a.title.toLowerCase().contains(q) || a.summary.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categoryName = CategoryService.getCategoryDisplayName(widget.category, context);
    final icon = CategoryService.getCategoryIcon(categoryId);
    final color = CategoryService.getCategoryColor(categoryId);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              isRtl ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            tooltip: l10n.translate('back') ?? 'Back',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            categoryName,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          centerTitle: true,
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${widget.category['newsCount'] ?? _articles.length}',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadNews,
            color: color,
            child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _buildCategoryBanner(context, categoryName, icon, color),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: l10n.translate('searchHint') ?? 'بحث في هذا القسم...',
                      hintStyle: GoogleFonts.outfit(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      prefixIcon: Icon(Icons.search_rounded, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: color, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
              if (_isLoading)
                const SliverFillRemaining(
                  child: ShimmerLoadingList(),
                )
              else if (_filteredArticles.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(context, l10n, color),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index == _filteredArticles.length) {
                          if (_isLoadingMore) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: CircularProgressIndicator(color: color),
                              ),
                            );
                          }
                          return const SizedBox(height: 24);
                        }
                        return _buildArticleCard(context, _filteredArticles[index]);
                      },
                      childCount: _filteredArticles.length + (_hasMore ? 1 : 0),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildCategoryBanner(BuildContext context, String name, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.16),
            color.withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'أحدث التغطيات والأخبار الحصرية',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleCard(BuildContext context, NewsModel article) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            AnalyticsService.instance.trackArticleOpen(article);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => NewsDetailPage(article: article)),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: CachedNewsImage(
                      imageUrl: article.imageUrl,
                      fit: BoxFit.cover,
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (article.summary.isNotEmpty)
                        Text(
                          article.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (article.author.isNotEmpty) ...[
                            Text(
                              article.author,
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          const Spacer(),
                          Icon(
                            Icons.access_time_rounded,
                            size: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDate(article.publishDate),
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    );
  }

  String _formatDate(String publishDate) {
    if (publishDate.isEmpty) return '';
    try {
      final timestamp = int.tryParse(publishDate);
      if (timestamp != null) {
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final diff = DateTime.now().difference(date);
        if (diff.inMinutes < 60) return '${diff.inMinutes} د';
        if (diff.inHours < 24) return '${diff.inHours} س';
        return '${diff.inDays} ي';
      }
    } catch (_) {}
    return publishDate.split('T').first;
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n, Color color) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.newspaper_rounded, size: 36, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.translate('noArticles') ?? 'لا توجد أخبار في هذا القسم حالياً',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'اسحب لأسفل لتحديث الأخبار',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
