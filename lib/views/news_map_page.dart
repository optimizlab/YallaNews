// News Map Page - Geographic Entity Visualization
// Shows article locations on an interactive map with clustering

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import '../database/news_db.dart' show NewsDatabase;
import '../views/news_detail_page.dart';

class NewsMapPage extends StatefulWidget {
  const NewsMapPage({super.key});

  @override
  State<NewsMapPage> createState() => _NewsMapPageState();
}

class _NewsMapPageState extends State<NewsMapPage> {
  late WebViewController _webViewController;
  bool _isLoading = true;
  String _error = '';
  List<NewsModel> _articles = [];
  String _selectedCategory = 'all';
  String _timeRange = '7d';

  @override
  void initState() {
    super.initState();
    _initWebView();
    _loadArticles();
  }

  Future<void> _initWebView() async {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => setState(() => _isLoading = true),
          onPageFinished: (url) => setState(() => _isLoading = false),
          onWebResourceError: (error) {
            setState(() {
              _error = error.description;
              _isLoading = false;
            });
          },
        ),
      )
      ..addJavaScriptChannel(
        'Flutter',
        onMessageReceived: (message) {
          final data = message.message;
          if (data.startsWith('article:')) {
            final url = data.substring(8);
            _openArticle(url);
          }
        },
      )
      ..loadHtmlString(_generateMapHtml());
  }

  Future<void> _loadArticles() async {
    try {
      final database = await NewsDatabase.instance.database;
      final timeRangeMs = _getTimeRangeMs(_timeRange);
      final now = DateTime.now().millisecondsSinceEpoch;
      final cutoff = now - timeRangeMs;

      String whereClause = 'crawled_at > ? AND latitude IS NOT NULL AND longitude IS NOT NULL';
      List<dynamic> whereArgs = [cutoff];

      if (_selectedCategory != 'all') {
        whereClause += ' AND category = ?';
        whereArgs.add(_selectedCategory);
      }

      final articles = await database.query(
        'crawled_articles',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'crawled_at DESC',
        limit: 200,
      );

      final loadedArticles = articles.map((row) => NewsModel.fromJson(
        Map<String, dynamic>.from(row),
        row['url'] as String,
      )).where((a) => a.latitude != null && a.longitude != null).toList();

      if (mounted) {
        setState(() => _articles = loadedArticles);
        _updateMapMarkers();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  int _getTimeRangeMs(String range) {
    switch (range) {
      case '1h':
        return 60 * 60 * 1000;
      case '6h':
        return 6 * 60 * 60 * 1000;
      case '24h':
        return 24 * 60 * 60 * 1000;
      case '7d':
        return 7 * 24 * 60 * 60 * 1000;
      case '30d':
        return 30 * 24 * 60 * 60 * 1000;
      default:
        return 7 * 24 * 60 * 60 * 1000;
    }
  }

  void _updateMapMarkers() {
    if (_articles.isEmpty) return;

    final markersJs = _articles.map((a) {
      return '''
        {
          lat: ${a.latitude},
          lng: ${a.longitude},
          title: "${a.title.replaceAll('"', '\\"').replaceAll('\n', ' ')}",
          category: "${a.category}",
          url: "${a.url}",
          image: "${a.imageUrl}",
          source: "${a.sourceName.isNotEmpty ? a.sourceName : a.displaySourceName}"
        }
      ''';
    }).join(',');

    final js = '''
      if (window.updateMarkers) {
        window.updateMarkers([$markersJs]);
      }
    ''';
    _webViewController.runJavaScript(js);
  }

  void _openArticle(String url) {
    final article = _articles.firstWhere(
      (a) => a.url == url,
      orElse: () => NewsModel.empty(url),
    );
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NewsDetailPage(article: article)),
      );
    }
  }

  String _generateMapHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>News Map</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body, #map { height: 100%; width: 100%; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
    .leaflet-popup-content-wrapper { border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.15); }
    .leaflet-popup-content { margin: 0; padding: 12px; min-width: 220px; max-width: 280px; }
    .news-popup { display: flex; flex-direction: column; gap: 8px; }
    .news-popup-img { width: 100%; height: 100px; object-fit: cover; border-radius: 8px; }
    .news-popup-title { font-size: 14px; font-weight: 700; line-height: 1.3; color: #1a1a2e; }
    .news-popup-meta { display: flex; gap: 8px; font-size: 11px; color: #666; }
    .news-popup-category { background: #e8eaf6; color: #283593; padding: 2px 8px; border-radius: 10px; font-weight: 600; }
    .news-popup-source { color: #888; }
    .news-popup-link { display: block; text-align: center; margin-top: 8px; padding: 8px; background: #1a1a2e; color: white; border-radius: 8px; text-decoration: none; font-weight: 600; font-size: 13px; }
    .news-popup-link:active { background: #c62828; }
    .cluster-marker { background: #1a1a2e; border: 3px solid white; border-radius: 50%; display: flex; align-items: center; justify-content: center; color: white; font-weight: 800; font-size: 12px; }
    .cluster-marker.small { width: 30px; height: 30px; }
    .cluster-marker.medium { width: 40px; height: 40px; font-size: 14px; }
    .cluster-marker.large { width: 50px; height: 50px; font-size: 16px; }
  </style>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <script src="https://unpkg.com/leaflet.markercluster@1.5.3/dist/leaflet.markercluster.js"></script>
  <link rel="stylesheet" href="https://unpkg.com/leaflet.markercluster@1.5.3/dist/MarkerCluster.css" />
  <link rel="stylesheet" href="https://unpkg.com/leaflet.markercluster@1.5.3/dist/MarkerCluster.Default.css" />
</head>
<body>
  <div id="map"></div>
  <script>
    // Initialize map centered on world
    const map = L.map('map', {
      zoomControl: false,
      attributionControl: false,
      preferCanvas: true,
    }).setView([20, 0], 2);

    // Dark/light tile layers
    const lightTiles = L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
      maxZoom: 18,
      attribution: '&copy; OpenStreetMap &copy; CARTO'
    });

    const darkTiles = L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
      maxZoom: 18,
      attribution: '&copy; OpenStreetMap &copy; CARTO'
    });

    // Detect system theme
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    (prefersDark ? darkTiles : lightTiles).addTo(map);

    // Listen for theme changes
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', e => {
      map.removeLayer(e.matches ? lightTiles : darkTiles);
      map.addLayer(e.matches ? darkTiles : lightTiles);
    });

    // Zoom controls
    L.control.zoom({ position: 'bottomright' }).addTo(map);

    // Marker cluster group
    const markers = L.markerClusterGroup({
      spiderfyOnMaxZoom: true,
      showCoverageOnHover: false,
      zoomToBoundsOnClick: true,
      maxClusterRadius: 50,
      iconCreateFunction: (cluster) => {
        const count = cluster.getChildCount();
        let size = 'small';
        if (count >= 100) size = 'large';
        else if (count >= 10) size = 'medium';
        return L.divIcon({
          html: `<div class="cluster-marker \${size}">\${count}</div>`,
          className: '',
          iconSize: size === 'large' ? [50, 50] : size === 'medium' ? [40, 40] : [30, 30],
        });
      },
    });

    map.addLayer(markers);

    // Store markers for updates
    window.markers = markers;
    window.map = map;

    // Function to update markers from Flutter
    window.updateMarkers = function(articles) {
      markers.clearLayers();
      
      articles.forEach(article => {
        if (!article.lat || !article.lng) return;
        
        const marker = L.marker([article.lat, article.lng], {
          icon: L.divIcon({
            html: '<div style="width: 32px; height: 32px; background: #c62828; border: 3px solid white; border-radius: 50%; box-shadow: 0 2px 8px rgba(0,0,0,0.3);"></div>',
            className: '',
            iconSize: [32, 32],
            iconAnchor: [16, 16],
          }),
        });

        const popupContent = `
          <div class="news-popup">
            \${article.image ? '<img src="\${article.image}" class="news-popup-img" alt="">' : ''}
            <div class="news-popup-title">\${article.title}</div>
            <div class="news-popup-meta">
              <span class="news-popup-category">\${article.category}</span>
              <span class="news-popup-source">\${article.source}</span>
            </div>
            <a href="#" class="news-popup-link" onclick="Flutter.postMessage('article:' + article.url); return false;">
              Read Article
            </a>
          </div>
        `;

        marker.bindPopup(popupContent, {
          maxWidth: 300,
          minWidth: 220,
          className: 'news-popup-container',
        });

        markers.addLayer(marker);
      });

      map.addLayer(markers);
      
      // Fit bounds if markers exist
      if (markers.getLayers().length > 0) {
        const group = L.featureGroup(markers.getLayers());
        map.fitBounds(group.getBounds().pad(0.1));
      }
    };

    // Handle Flutter messages
    if (window.Flutter) {
      window.Flutter.postMessage = function(message) {
        // Handled by Flutter side
      };
    }
  </script>
</body>
</html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.translate('newsMap'),
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() => _selectedCategory = value);
              _loadArticles();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All Categories')),
              const PopupMenuItem(value: 'politics', child: Text('Politics')),
              const PopupMenuItem(value: 'business', child: Text('Business')),
              const PopupMenuItem(value: 'technology', child: Text('Technology')),
              const PopupMenuItem(value: 'sports', child: Text('Sports')),
              const PopupMenuItem(value: 'health', child: Text('Health')),
              const PopupMenuItem(value: 'science', child: Text('Science')),
              const PopupMenuItem(value: 'world', child: Text('World')),
            ],
            icon: const Icon(Icons.filter_list_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() => _timeRange = value);
              _loadArticles();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: '1h', child: Text('Last Hour')),
              const PopupMenuItem(value: '6h', child: Text('Last 6 Hours')),
              const PopupMenuItem(value: '24h', child: Text('Last 24 Hours')),
              const PopupMenuItem(value: '7d', child: Text('Last 7 Days')),
              const PopupMenuItem(value: '30d', child: Text('Last 30 Days')),
            ],
            icon: const Icon(Icons.schedule_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _webViewController),
          _buildLoadingIndicator(context, l10n),
          _buildErrorBanner(context, l10n),
          _buildArticleCountBadge(context),
          _buildLegend(context),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return _isLoading
        ? Container(
            color: theme.colorScheme.surface.withValues(alpha: 0.9),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    l10n.translate('loadingMap'),
                    style: GoogleFonts.outfit(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          )
        : const SizedBox.shrink();
  }

  Widget _buildErrorBanner(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return _error.isNotEmpty
        ? Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error,
                      style: GoogleFonts.outfit(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() => _error = '');
                      _initWebView();
                    },
                    icon: Icon(Icons.refresh, color: theme.colorScheme.error),
                  ),
                ],
              ),
            ),
          )
        : const SizedBox.shrink();
  }

  Widget _buildArticleCountBadge(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      top: 16,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public_rounded, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              '${_articles.length} ${AppLocalizations.of(context).translate('articlesOnMap')}',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Positioned(
      bottom: 100,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildLegendItem(
              context,
              Icons.location_on_rounded,
              theme.colorScheme.primary,
              l10n.translate('singleArticle'),
            ),
            const SizedBox(height: 8),
            _buildLegendItem(
              context,
              Icons.scatter_plot_rounded,
              theme.colorScheme.secondary,
              l10n.translate('articleCluster'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(BuildContext context, IconData icon, Color color, String label) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}