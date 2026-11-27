import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:yallanews/services/msn_image_fetcher.dart';

class CachedNewsImage extends StatefulWidget {
  final String imageUrl;
  final String? fallbackImageUrl;
  final String? searchQuery;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CachedNewsImage({
    Key? key,
    required this.imageUrl,
    this.fallbackImageUrl,
    this.searchQuery,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = const Alignment(0, -0.18),
    this.placeholder,
    this.errorWidget,
  }) : super(key: key);

  @override
  State<CachedNewsImage> createState() => _CachedNewsImageState();
}

class _CachedNewsImageState extends State<CachedNewsImage> {
  String? _currentUrl;
  bool _fallbackTried = false;
  bool _searchTried = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.imageUrl;
  }

  @override
  void didUpdateWidget(CachedNewsImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.fallbackImageUrl != widget.fallbackImageUrl ||
        oldWidget.searchQuery != widget.searchQuery) {
      _fallbackTried = false;
      _searchTried = false;
      _currentUrl = widget.imageUrl;
    }
  }

  bool get _shouldSkip => _currentUrl == null ||
      _currentUrl!.isEmpty ||
      MsnImageFetcher.isPlaceholderOrEmpty(_currentUrl) ||
      _currentUrl!.toLowerCase().contains('bing.com/images/search') ||
      _currentUrl!.toLowerCase().contains('google.com/search') ||
      _currentUrl!.toLowerCase().contains('duckduckgo.com') ||
      _currentUrl!.toLowerCase().contains('yahoo.com/search');

  Future<void> _trySearchFallback(String query) async {
    try {
      final found = await MsnImageFetcher.fetchRandomImage(query)
          .timeout(const Duration(seconds: 10));
      if (mounted && found != null && found.isNotEmpty) {
        setState(() {
          _currentUrl = found;
          _searchTried = true;
        });
        return;
      }
    } catch (_) {}
    if (mounted) {
      if (widget.fallbackImageUrl != null && !_fallbackTried) {
        _fallbackTried = true;
        setState(() => _currentUrl = widget.fallbackImageUrl);
      } else {
        setState(() => _searchTried = true);
      }
    }
  }

  Widget _buildPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return widget.placeholder ??
        Container(
          width: widget.width,
          height: widget.height,
          color: theme.colorScheme.surfaceContainer,
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
  }

  Widget _buildFallback(BuildContext context) {
    return widget.errorWidget ?? _buildPlaceholder(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldSkip) {
      if (widget.fallbackImageUrl != null && !_fallbackTried) {
        _fallbackTried = true;
        _currentUrl = widget.fallbackImageUrl;
      } else if (widget.searchQuery != null && !_searchTried && !_fallbackTried) {
        _searchTried = true;
        unawaited(_trySearchFallback(widget.searchQuery!));
      }
      return _buildPlaceholder(context);
    }

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    // Only constrain one dimension so ResizeImage preserves the original
    // aspect ratio and does not squash rectangular images into a square.
    final memWidth = widget.width != null &&
        widget.width!.isFinite &&
        widget.width! > 0
        ? (widget.width! * dpr).round()
        : null;

    return CachedNetworkImage(
      imageUrl: _currentUrl!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      // Mobile-first disk cache: images are stored on disk by default and
      // survive app restarts so they are never re-downloaded within the cache
      // window. Kept small to respect device storage while avoiding reloads on
      // every feed scroll. Cache duration is signaled via the Cache-Control
      // header below.
      memCacheWidth: memWidth,
      filterQuality: FilterQuality.medium,
      fadeInDuration: const Duration(milliseconds: 220),
      fadeInCurve: Curves.easeInOut,
      httpHeaders: const {'Cache-Control': 'public, max-age=604800'},
      placeholder: (context, url) => _buildPlaceholder(context),
      errorWidget: (context, url, error) {
        if (widget.searchQuery != null &&
            !_searchTried &&
            !_fallbackTried &&
            mounted) {
          _searchTried = true;
          unawaited(_trySearchFallback(widget.searchQuery!));
        } else if (widget.fallbackImageUrl != null &&
            !_fallbackTried &&
            mounted) {
          _fallbackTried = true;
          _currentUrl = widget.fallbackImageUrl;
        }
        return _buildFallback(context);
      },
    );
  }
}
