import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import '../services/app_settings.dart';
import '../services/yalla_engine_service.dart';
import '../services/background_crawler_service.dart';
import '../services/server_api_service.dart';
import '../services/category_service.dart';
import '../services/connectivity_service.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/custom_logo.dart';
import '../widgets/banner_ad.dart';
import '../widgets/cached_news_image.dart';
import 'news_detail_page.dart';
import 'explore_page.dart';
import 'bookmarks_page.dart';
import 'settings_page.dart';
import 'auth/login_page.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/top_news_carousel.dart';
import '../arabic_news_processor.dart';
import '../services/news_blender_service.dart';

class HomePage extends StatefulWidget {
  final YallaEngineService engineService;

  const HomePage({
    Key? key,
    required this.engineService,
  }) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<NewsModel> _rawArticles = [];
  List<NewsModel> _articles = [];
  List<NewsModel> _allArticles = [];
  List<Map<String, dynamic>> _categories = [];
  List<String> _trendingSearches = [];
  String _searchQuery = '';
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isSearchActive = false;
  String _selectedCategory = 'all';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  StreamSubscription<NewsModel>? _articleSubscription;

  @override
  void initState() {
    super.initState();
    CategoryService.instance.addListener(_onCategoriesChanged);
    _loadData();
  }

  @override
  void dispose() {
    _articleSubscription?.cancel();
    CategoryService.instance.removeListener(_onCategoriesChanged);
    super.dispose();
  }

  void _onCategoriesChanged() {
    if (mounted) {
      setState(() {
        _categories = CategoryService.instance.categories;
      });
    }
  }

  Future<bool> _getIsWifi() async {
    try {
      final connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult.contains(ConnectivityResult.wifi)) {
        return true;
      }
      if (connectivityResult.contains(ConnectivityResult.mobile)) {
        return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _applyBlendedArticles(List<NewsModel> rawList) async {
    _rawArticles = rawList;
    List<NewsModel> blended;
    try {
      blended = await NewsBlenderService.instance.blendArticlesAsync(rawList);
    } catch (e) {
      debugPrint('[HOME] Ollama blending failed, using sync fallback: $e');
      blended = NewsBlenderService.instance.blendArticles(rawList);
    }
    if (!mounted) return;
    setState(() {
      _allArticles = blended;
      if (_selectedCategory == 'all') {
        _articles = List.from(_allArticles);
      } else if (_selectedCategory == 'blended') {
        _articles = _allArticles.where((a) => a.isBlended).toList();
      } else {
        _articles = _allArticles.where((a) => _matchesCategory(a.category, _selectedCategory)).toList();
      }
    });
    CategoryService.instance.updateCategoryCounts(_allArticles);
  }

  Future<void> _loadData() async {
    debugPrint('[HOME] _loadData started');
    setState(() => _isLoading = true);
    try {
      // Always load from API first — works on Wi-Fi AND mobile data
      final rawList = await _loadArticles();
      debugPrint('[HOME] Loaded ${rawList.length} articles from API');
      final trending = await ServerApiService.getTrending(limit: 10);
      if (mounted) {
        _rawArticles = rawList;
        _allArticles = rawList;
        _articles = rawList;
        setState(() {
          _selectedCategory = 'all';
          _categories = CategoryService.instance.categories;
          _trendingSearches = trending.map((t) => t.title).where((q) => q.isNotEmpty).toList();
          _isLoading = false;
        });
        CategoryService.instance.updateCategoryCounts(_allArticles);
        _applyBlendedArticles(rawList);
      }

      if (!kIsWeb) {
        final settings = await AppSettings.instance.getPrefs();
        final backgroundEnabled = settings.getBool('background_crawler_enabled') ?? true;
        final onWifi = await ConnectivityService.isWifi();

        if (backgroundEnabled && onWifi) {
          // On Wi-Fi: start the background crawler to discover fresh articles
          debugPrint('[HOME] Wi-Fi detected — starting background crawler');
          _articleSubscription?.cancel();
          _articleSubscription = BackgroundCrawlerService.instance.articleStream.listen((article) {
            if (mounted) {
              setState(() {
                final existingIndex = _rawArticles.indexWhere((a) => a.url == article.url);
                if (existingIndex >= 0) {
                  _rawArticles[existingIndex] = article;
                } else {
                  _rawArticles.insert(0, article);
                }
              });
              _applyBlendedArticles(_rawArticles);
            }
          });

          BackgroundCrawlerService.instance.startSilentCrawl(
            engineService: widget.engineService,
            onComplete: () async {
              await _articleSubscription?.cancel();
              _articleSubscription = null;
              if (mounted) {
                final refreshed = await _loadArticles();
                _rawArticles = refreshed;
                setState(() {
                  _articles = refreshed;
                });
                _applyBlendedArticles(refreshed);
                CategoryService.instance.updateCategoryCounts(_allArticles);
              }
            },
          );
        } else if (backgroundEnabled && !onWifi) {
          // On mobile data: API only, no crawl
          debugPrint('[HOME] Mobile data detected — API-only mode, no crawl');
        }
      } else {
        // Web / Desktop: use ArabicNewsProcessor stream
        _articleSubscription?.cancel();
        _articleSubscription = ArabicNewsProcessor.instance.articleStream.listen((article) {
          if (mounted) {
            setState(() {
              final existingIndex = _rawArticles.indexWhere((a) => a.url == article.url);
              if (existingIndex >= 0) {
                _rawArticles[existingIndex] = article;
              } else {
                _rawArticles.insert(0, article);
              }
            });
            _applyBlendedArticles(_rawArticles);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<List<NewsModel>> _loadArticles() async {
    try {
      debugPrint('[HOME] Loading articles from server API...');
      final locale = AppSettings.instance.locale;
      final language = locale?.languageCode == 'ar' ? 'ar' : null;
      final serverArticles = await ServerApiService.getNews(limit: 100, language: language);
      debugPrint('[HOME] Server returned ${serverArticles.length} articles');
      return serverArticles;
    } catch (e) {
      debugPrint('[HOME] Failed to load articles: $e');
      return [];
    }
  }

  Future<void> _onRefresh() async {
    try {
      if (!kIsWeb) {
        final settings = await AppSettings.instance.getPrefs();
        final backgroundEnabled = settings.getBool('background_crawler_enabled') ?? true;
        final onWifi = await ConnectivityService.isWifi();

        if (backgroundEnabled && onWifi) {
          // Wi-Fi: trigger a crawler force-refresh
          _articleSubscription?.cancel();
          _articleSubscription = BackgroundCrawlerService.instance.articleStream.listen((article) {
            if (mounted) {
              setState(() {
                final existingIndex = _allArticles.indexWhere((a) => a.url == article.url);
                if (existingIndex >= 0) {
                  _allArticles[existingIndex] = article;
                  _articles = List<NewsModel>.from(_allArticles);
                } else {
                  _articles = [article, ..._articles];
                  _allArticles = [article, ..._allArticles];
                }
              });
            }
          });

          BackgroundCrawlerService.instance.forceRefresh(
            engineService: widget.engineService,
            onComplete: () async {
              await _articleSubscription?.cancel();
              _articleSubscription = null;
              if (mounted) {
                final refreshed = await _loadArticles();
                _rawArticles = refreshed;
                setState(() {
                  _articles = refreshed;
                });
                _applyBlendedArticles(refreshed);
                CategoryService.instance.updateCategoryCounts(_allArticles);
              }
            },
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Crawling started in background, please wait...'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return;
        }
        // Mobile data or crawler disabled: fall through to API refresh
      }

      // API-only refresh (mobile data or web)
      final List<NewsModel> refreshed = await _loadArticles();
      if (mounted) {
        _rawArticles = refreshed;
        setState(() {
          _articles = refreshed;
        });
        _applyBlendedArticles(refreshed);
        CategoryService.instance.updateCategoryCounts(_allArticles);
      }
    } catch (e) {
      // silently fail
    }
  }

  void _activateSearch() {
    setState(() => _isSearchActive = true);
  }

  void _deactivateSearch() {
    setState(() {
      _isSearchActive = false;
      _searchQuery = '';
    });
  }

  List<NewsModel> get _searchResults {
    if (_searchQuery.isEmpty) return const [];
    final q = _searchQuery.toLowerCase();
    return _allArticles.where((a) => a.title.toLowerCase().contains(q) || a.summary.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AdaptiveLayout(
      currentIndex: _currentIndex,
      onNavigationChanged: (i) => setState(() => _currentIndex = i),
      destinations: [
        AdaptiveNavigationDestination(icon: Icons.home_rounded, label: l10n.translate('home')),
        AdaptiveNavigationDestination(icon: Icons.explore_rounded, label: l10n.translate('explore')),
        AdaptiveNavigationDestination(icon: Icons.bookmark_rounded, label: l10n.translate('bookmarks')),
        AdaptiveNavigationDestination(icon: Icons.settings_rounded, label: l10n.translate('settingsNav')),
      ],
      scaffoldKey: _scaffoldKey,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        leading: _isSearchActive
            ? IconButton(
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                onPressed: _deactivateSearch,
              )
            : IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
        title: _isSearchActive
            ? SizedBox(
                width: MediaQuery.of(context).size.width * 0.7,
                child: TextField(
                  autofocus: true,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: l10n.translate('searchHint'),
                    hintStyle: GoogleFonts.outfit(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
              )
            :  YallaNewsLogo(size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: _activateSearch,
          ),
          FutureBuilder<bool>(
            future: ServerApiService.isLoggedIn(),
            builder: (context, snapshot) {
              final isLoggedIn = snapshot.data ?? false;
              if (!isLoggedIn) {
                return IconButton(
                  icon: const Icon(Icons.person_add_rounded),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage())),
                );
              }
              return IconButton(
                icon: CircleAvatar(radius: 14, backgroundColor: const Color(0xFF1565C0), child: Text('U', style: const TextStyle(color: Colors.white, fontSize: 12))),
                onPressed: () async {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: const Color(0xFF2A2A4A),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                    builder: (context) => SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('User', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  await ServerApiService.logout();
                                  if (mounted) setState(() {});
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFC62828),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text(l10n.translate('logout'), style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: _buildCurrentPage(),
    );
  }

  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case 0:
        return _buildHomeContent(context);
      case 1:
        return const ExplorePage();
      case 2:
        return const BookmarksPage();
      case 3:
        return const SettingsPage();
      default:
        return _buildHomeContent(context);
    }
  }

  Widget _buildHomeContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_isLoading) {
      return const ShimmerLoadingList();
    }

    if (_isSearchActive) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_searchQuery.isEmpty) _buildTrendingSearches(context),
            if (_searchQuery.isNotEmpty) ..._searchResults.map((article) => _buildArticleCard(article)),
          ],
        ),
      );
    }

    if (_articles.isEmpty) {
      return RefreshIndicator(
        onRefresh: _onRefresh,
        color: const Color(0xFFC62828),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - kToolbarHeight - MediaQuery.of(context).padding.top,
            ),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(Icons.newspaper_rounded, size: 40, color: Theme.of(context).colorScheme.primary.withOpacity(0.4)),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.translate('noArticles'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.translate('autoLoadMessage'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(l10n.translate('refresh'), style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC62828),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage())),
                  icon: const Icon(Icons.person_add_rounded, size: 18),
                  label: Text(l10n.translate('login'), style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 750;
        final topArticles = _articles.take(9).toList();
        final remainingArticles = _articles.length > 3 ? _articles.sublist(3) : _articles;
        final pairsCount = isWide ? (remainingArticles.length / 2).ceil() : remainingArticles.length;

        return RefreshIndicator(
          onRefresh: _onRefresh,
          color: const Color(0xFFC62828),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: 2 + pairsCount + 1,
            itemBuilder: (context, index) {
              if (index == 0) return _buildCategoryChips(context);
              if (index == 1) {
                if (_articles.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    TopNewsCarousel(
                      articles: topArticles,
                      onArticleTap: (article) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => NewsDetailPage(article: article)));
                      },
                      getCategoryLabel: (cat) => _getCategoryLabel(cat, context),
                      getReadTime: (art) => _getReadTime(art, context),
                      getSourceName: (art) => _getSourceName(art),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 18,
                            decoration: BoxDecoration(
                              color: const Color(0xFFC62828),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _selectedCategory == 'all' ? l10n.translate('all') : _getCategoryLabel(_selectedCategory, context),
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                );
              }

              final articleRowIndex = index - 2;
              if (articleRowIndex >= pairsCount) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: BannerAdWidget(),
                );
              }

              if (isWide) {
                final idx1 = articleRowIndex * 2;
                final idx2 = idx1 + 1;
                final art1 = remainingArticles[idx1];
                final art2 = idx2 < remainingArticles.length ? remainingArticles[idx2] : null;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildArticleCard(art1)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: art2 != null ? _buildArticleCard(art2) : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildArticleCard(remainingArticles[articleRowIndex]),
              );
            },
          ),
        );
      },
    );
  }

  bool _matchesCategory(String articleCat, String selectedCat) {
    if (selectedCat.toLowerCase() == 'all') return true;
    final a = articleCat.toLowerCase().trim();
    final s = selectedCat.toLowerCase().trim();
    if (a == s) return true;

    final categoryAliases = <String, List<String>>{
      'sports': ['sports', 'رياضة', 'كرة القدم', 'كرة السلة', 'تنس', 'sport', 'football'],
      'politics': ['politics', 'سياسة', 'أخبار محلية', 'أخبار دولية', 'politic'],
      'business': ['business', 'اقتصاد', 'أعمال', 'أسواق ومال', 'عقارات', 'economy', 'finance'],
      'technology': ['technology', 'تكنولوجيا', 'تقنية', 'علوم وتكنولوجيا', 'tech'],
      'health': ['health', 'صحة', 'طب وصحة', 'علوم وطب', 'medical'],
      'entertainment': ['entertainment', 'ترفيه', 'فن', 'ثقافة', 'منوعات', 'فن وموسيقى', 'culture'],
      'science': ['science', 'علوم', 'علم'],
      'world': ['world', 'أخبار دولية', 'دولي', 'العالم'],
      'general': ['general', 'general_news', 'أخبار عامة', 'عام'],
    };

    for (final aliases in categoryAliases.values) {
      final matchesA = aliases.any((x) => x == a || a.contains(x) || x.contains(a));
      final matchesS = aliases.any((x) => x == s || s.contains(x) || x.contains(s));
      if (matchesA && matchesS) return true;
    }

    return false;
  }

  Widget _buildCategoryChips(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allCats = <Map<String, dynamic>>[{'id': 'all', 'name': l10n.translate('all'), 'nameEn': 'All'}];
    final blendedCount = _allArticles.where((a) => a.isBlended).length;
    if (blendedCount > 0) {
      allCats.add({'id': 'blended', 'name': l10n.translate('blendedBadge'), 'nameEn': 'Blended'});
    }
    allCats.addAll(_categories);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: allCats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final cat = allCats[i];
          final catKey = cat['id']?.toString() ?? 'all';
          final catName = cat['name']?.toString() ?? catKey;
          final int count = catKey == 'all'
              ? _allArticles.length
              : (catKey == 'blended'
                  ? blendedCount
                  : _allArticles.where((a) => _matchesCategory(a.category, catKey) || _matchesCategory(a.category, catName)).length);
          final isSelected = _selectedCategory == catKey;

          return FilterChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (catKey == 'blended') ...[
                  const Icon(Icons.auto_awesome_rounded, size: 12, color: Colors.amber),
                  const SizedBox(width: 4),
                ],
                Text(
                  catName,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.25)
                        : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            selected: isSelected,
            onSelected: (bool selected) {
              if (!selected) return;
              setState(() {
                _selectedCategory = catKey;
                if (catKey == 'all') {
                  _articles = List.from(_allArticles);
                } else if (catKey == 'blended') {
                  _articles = _allArticles.where((a) => a.isBlended).toList();
                } else {
                  _articles = _allArticles.where((a) => _matchesCategory(a.category, catKey) || _matchesCategory(a.category, catName)).toList();
                }
              });
            },
            selectedColor: Theme.of(context).colorScheme.primary,
            checkmarkColor: Theme.of(context).colorScheme.onPrimary,
            side: BorderSide.none,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          );
        },
      ),
    );
  }

  Widget _buildTrendingSearches(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final terms = _trendingSearches.isEmpty ? [''] : _trendingSearches;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            l10n.translate('trendingSearches'),
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: terms.map((term) {
            return GestureDetector(
              onTap: () {
                setState(() => _searchQuery = term);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Text(
                  term,
                  style: GoogleFonts.outfit(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFeaturedArticle(NewsModel article) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => NewsDetailPage(article: article)));
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: CachedNewsImage(
                    imageUrl: article.imageUrl.isEmpty ? 'https://placehold.co/800x220/1A1A2E/C62828?text=${_getCategoryLabel(article.category, context)}' : article.imageUrl,
                    width: double.infinity,
                    height: 220,
                    fit: BoxFit.cover,
                    errorWidget: Container(
                      height: 220,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF1A1A2E), Color(0xFFC62828)],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC62828),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      AppLocalizations.of(context).translate('urgent'),
                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getCategoryLabel(article.category, context),
                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface, height: 1.3),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        _getReadTime(article, context),
                        style: GoogleFonts.outfit(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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

  Widget _buildArticleCard(NewsModel article) {
    final l10n = AppLocalizations.of(context);
    final isBlended = article.isBlended;
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => NewsDetailPage(article: article)));
        if (result != null && result is Map<String, dynamic> && result['search'] != null) {
          final searchQuery = result['search'] as String;
          setState(() {
            _searchQuery = searchQuery;
            _isSearchActive = true;
          });
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: isBlended
              ? Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.35), width: 1.2)
              : null,
          boxShadow: [
            BoxShadow(
              color: isBlended
                  ? const Color(0xFF1565C0).withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
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
                    if (isBlended) ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.auto_awesome_rounded, size: 11, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  '${l10n.translate('blendedBadge')} • ${article.sourceCount} مصادر',
                                  style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      article.title,
                      style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface, height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (isBlended) ...[
                          const Icon(Icons.layers_rounded, size: 13, color: Color(0xFF1565C0)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              article.sourceAttributions.take(2).map((a) => a['name']).join(' + ') +
                                  (article.sourceAttributions.length > 2 ? ' +${article.sourceAttributions.length - 2}' : ''),
                              style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF1565C0)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ] else ...[
                          Icon(Icons.favorite_border_rounded, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            '${(article.sentiment * 1000).toInt()}',
                            style: GoogleFonts.outfit(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${AppLocalizations.of(context).translate('yalla')} ${_getSourceName(article)}',
                              style: GoogleFonts.outfit(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNewsImage(
                  imageUrl: article.imageUrl.isEmpty ? 'https://placehold.co/72x72/1A1A2E/C62828?text=${_getCategoryLabel(article.category, context)[0]}' : article.imageUrl,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorWidget: _buildFallbackImage(article.category),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackImage(String category) {
    final label = _getCategoryLabel(category, context);
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.secondaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          label.isNotEmpty ? label[0] : '?',
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  String _getCategoryLabel(String category, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cat = category.toLowerCase().trim();
    if (cat == 'sports' || cat == 'رياضة' || cat == 'كرة القدم' || cat == 'كرة السلة' || cat == 'تنس') return l10n.translate('sports');
    if (cat == 'politics' || cat == 'سياسة' || cat == 'أخبار دولية' || cat == 'أخبار محلية') return l10n.translate('politics');
    if (cat == 'business' || cat == 'economy' || cat == 'اقتصاد' || cat == 'أعمال' || cat == 'أسواق ومال' || cat == 'عقارات') return l10n.translate('business');
    if (cat == 'technology' || cat == 'tech' || cat == 'تكنولوجيا' || cat == 'تقنية') return l10n.translate('technology');
    if (cat == 'health' || cat == 'صحة' || cat == 'طب وصحة' || cat == 'medical') return l10n.translate('health');
    if (cat == 'science' || cat == 'علوم' || cat == 'علم') return l10n.translate('science');
    if (cat == 'entertainment' || cat == 'ترفيه' || cat == 'فن' || cat == 'ثقافة') return l10n.translate('entertainment');
    if (cat == 'world' || cat == 'دولي' || cat == 'العالم') return l10n.translate('world');
    return category.isNotEmpty ? category : l10n.translate('generalNews');
  }

  String _getReadTime(NewsModel article, BuildContext context) {
    final words = article.content.split(' ').length;
    final minutes = (words / 200).ceil();
    return '$minutes ${AppLocalizations.of(context).translate('readTimeUnit')}';
  }

  String _getSourceName(NewsModel article) {
    try {
      final uri = Uri.parse(article.url);
      return uri.host.split('.').first;
    } catch (_) {
      return AppLocalizations.of(context).translate('news');
    }
  }

  Widget _buildDrawer(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.zero,
              ),
              child: Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: YallaNewsLogo(size: 28),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _DrawerItem(
              icon: Icons.home_rounded,
              label: l10n.translate('home'),
              isSelected: _currentIndex == 0,
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentIndex = 0);
              },
            ),
            _DrawerItem(
              icon: Icons.explore_rounded,
              label: l10n.translate('explore'),
              isSelected: _currentIndex == 1,
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentIndex = 1);
              },
            ),
            _DrawerItem(
              icon: Icons.bookmark_rounded,
              label: l10n.translate('bookmarks'),
              isSelected: _currentIndex == 2,
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentIndex = 2);
              },
            ),
            _DrawerItem(
              icon: Icons.settings_rounded,
              label: l10n.translate('settingsNav'),
              isSelected: _currentIndex == 3,
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentIndex = 3);
              },
            ),
            Divider(height: 32, thickness: 1, color: Theme.of(context).colorScheme.outlineVariant),
            _DrawerItem(
              icon: Icons.info_rounded,
              label: l10n.translate('about'),
              onTap: () {
                Navigator.pop(context);
                _showAboutDialog(context);
              },
            ),
            _DrawerItem(
              icon: Icons.policy_rounded,
              label: l10n.translate('privacyPolicy'),
              onTap: () {
                Navigator.pop(context);
                // TODO: open privacy policy
              },
            ),
            _DrawerItem(
              icon: Icons.article_rounded,
              label: l10n.translate('terms'),
              onTap: () {
                Navigator.pop(context);
                // TODO: open terms
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showAboutDialog(
      context: context,
      applicationName: l10n.translate('appName'),
      applicationVersion: 'v1.0.0',
      applicationIcon: Icon(Icons.newspaper_rounded, size: 48, color: Theme.of(context).colorScheme.primary),
      children: [
        Text(
          'تطبيق إخباري ذكي مدعوم بمحرك C++ ونموذج LLM مدمج',
          style: GoogleFonts.outfit(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.12) : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 14),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}