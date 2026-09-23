import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/news_model.dart';
import '../l10n/app_localizations.dart';
import 'cached_news_image.dart';

class TopNewsCarousel extends StatefulWidget {
  final List<NewsModel> articles;
  final ValueChanged<NewsModel> onArticleTap;
  final String Function(String category) getCategoryLabel;
  final String Function(NewsModel article) getReadTime;
  final String Function(NewsModel article) getSourceName;

  const TopNewsCarousel({
    super.key,
    required this.articles,
    required this.onArticleTap,
    required this.getCategoryLabel,
    required this.getReadTime,
    required this.getSourceName,
  });

  @override
  State<TopNewsCarousel> createState() => _TopNewsCarouselState();
}

class _TopNewsCarouselState extends State<TopNewsCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;
  Timer? _autoPlayTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startAutoPlay();
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || widget.articles.isEmpty) return;
      // auto play advance
      final cardsPerPage = _getCardsPerPage(MediaQuery.of(context).size.width);
      final totalPages = (widget.articles.length / cardsPerPage).ceil();
      if (totalPages <= 1) return;

      final nextPage = (_currentPage + 1) % totalPages;
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  int _getCardsPerPage(double width) {
    if (width >= 960) return 3;
    if (width >= 620) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.articles.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cardsPerPage = _getCardsPerPage(width);
        final totalArticles = widget.articles.length;
        final totalPages = (totalArticles / cardsPerPage).ceil();

        // Clamp currentPage if layout changed
        final activePage = _currentPage.clamp(0, (totalPages - 1).clamp(0, 999));

        return MouseRegion(
          onEnter: (_) => _autoPlayTimer?.cancel(),
          onExit: (_) => _startAutoPlay(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Carousel Header (Title + Arrow navigation buttons)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC62828).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        size: 18,
                        color: Color(0xFFC62828),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.translate('urgent'),
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '•',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.translate('all'),
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (totalPages > 1) ...[
                      // Previous Page Arrow (Right arrow in RTL)
                      _buildNavigationButton(
                        icon: isRtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                        onPressed: activePage > 0
                            ? () {
                                _pageController.previousPage(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeInOutCubic,
                                );
                              }
                            : null,
                      ),
                      const SizedBox(width: 6),
                      // Next Page Arrow (Left arrow in RTL)
                      _buildNavigationButton(
                        icon: isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                        onPressed: activePage < totalPages - 1
                            ? () {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeInOutCubic,
                                );
                              }
                            : null,
                      ),
                    ],
                    const Spacer(),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Carousel PageView Area
              SizedBox(
                height: cardsPerPage == 1 ? 280 : 310,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: totalPages,
                  onPageChanged: (page) {
                    setState(() => _currentPage = page);
                  },
                  itemBuilder: (context, pageIndex) {
                    final startIndex = pageIndex * cardsPerPage;
                    final pageArticles = <NewsModel>[];
                    for (int i = 0; i < cardsPerPage; i++) {
                      final itemIdx = startIndex + i;
                      if (itemIdx < totalArticles) {
                        pageArticles.add(widget.articles[itemIdx]);
                      }
                    }

                    if (cardsPerPage == 1) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _buildTopCard(pageArticles.first, isSingle: true),
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = 0; i < pageArticles.length; i++) ...[
                          if (i > 0) const SizedBox(width: 14),
                          Expanded(
                            child: _buildTopCard(pageArticles[i], isSingle: false),
                          ),
                        ],
                        // Fill remaining empty spots in the last row to maintain grid width
                        for (int i = 0; i < (cardsPerPage - pageArticles.length); i++) ...[
                          const SizedBox(width: 14),
                          const Expanded(child: SizedBox.shrink()),
                        ],
                      ],
                    );
                  },
                ),
              ),

              // Carousel Dots Indicator
              if (totalPages > 1) ...[
                const SizedBox(height: 12),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(totalPages, (index) {
                      final isSelected = index == activePage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        height: 6,
                        width: isSelected ? 22 : 6,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFC62828)
                              : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavigationButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final isEnabled = onPressed != null;
    return Material(
      color: isEnabled
          ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
          : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 20,
            color: isEnabled
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  Widget _buildTopCard(NewsModel article, {required bool isSingle}) {
    final categoryLabel = widget.getCategoryLabel(article.category);
    final readTime = widget.getReadTime(article);
    final sourceName = widget.getSourceName(article);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onArticleTap(article),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card Image with Badges
              Expanded(
                flex: 11,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                      child: CachedNewsImage(
                        imageUrl: article.imageUrl.isEmpty
                            ? 'https://placehold.co/600x300/1A1A2E/C62828?text=$categoryLabel'
                            : article.imageUrl,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        errorWidget: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF1A1A2E), Color(0xFFC62828)],
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              categoryLabel.isNotEmpty ? categoryLabel[0] : 'Y',
                              style: GoogleFonts.outfit(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Gradient shadow over bottom of image for contrast
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.4),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Urgent Badge
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFC62828),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFC62828).withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          AppLocalizations.of(context).translate('urgent'),
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // Category Badge
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          categoryLabel,
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Card Title & Metadata Details
              Expanded(
                flex: 9,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        article.title,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            readTime,
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          if (sourceName.isNotEmpty) ...[
                            Text(
                              sourceName,
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
