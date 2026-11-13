import 'dart:async';
import 'package:flutter/material.dart';

class CachedNewsImage extends StatefulWidget {
  final String imageUrl;
  final String? fallbackImageUrl;
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
  bool _isLoading = true;
  String? _error;
  ImageProvider? _imageProvider;
  bool _fallbackTried = false;

  @override
  void initState() {
    super.initState();
    _loadImage(widget.imageUrl);
  }

  @override
  void didUpdateWidget(CachedNewsImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.fallbackImageUrl != widget.fallbackImageUrl) {
      _fallbackTried = false;
      _isLoading = true;
      _error = null;
      _imageProvider = null;
      _loadImage(widget.imageUrl);
    }
  }

  Future<void> _loadImage(String url) async {
    if (url.isEmpty) {
      if (widget.fallbackImageUrl != null && !_fallbackTried) {
        _fallbackTried = true;
        await _loadImage(widget.fallbackImageUrl!);
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'empty';
        });
      }
      return;
    }

    final lower = url.toLowerCase();
    // Prevent image.png from being processed as it's a model instruction file
    if (url.contains('image.png')) {
      if (widget.fallbackImageUrl != null && !_fallbackTried) {
        _fallbackTried = true;
        await _loadImage(widget.fallbackImageUrl!);
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'model_instruction';
        });
      }
      return;
    }

    if (lower.contains('bing.com/images/search') ||
        lower.contains('google.com/search') ||
        lower.contains('yahoo.com/search')) {
      if (widget.fallbackImageUrl != null && !_fallbackTried) {
        _fallbackTried = true;
        await _loadImage(widget.fallbackImageUrl!);
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'invalid';
        });
      }
      return;
    }

    ImageStream? stream;
    ImageStreamListener? listener;
    try {
      final provider = NetworkImage(url);
      final completer = Completer<void>();
      stream = provider.resolve(const ImageConfiguration());
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (error, _) {
          if (!completer.isCompleted) completer.completeError(error);
        },
      );
      final s = stream;
      final l = listener;
      s.addListener(l);
      await completer.future.timeout(const Duration(seconds: 8));
      s.removeListener(l);
      if (mounted) {
        setState(() {
          _imageProvider = provider;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (stream != null && listener != null) {
        stream.removeListener(listener);
      }
      if (widget.fallbackImageUrl != null && !_fallbackTried) {
        _fallbackTried = true;
        await _loadImage(widget.fallbackImageUrl!);
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.placeholder ??
          Container(
            width: widget.width,
            height: widget.height,
            color: Colors.grey[300],
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          );
    }

    if (_error != null || _imageProvider == null) {
      return widget.errorWidget ?? _buildPlaceholder(context);
    }

    return Image(
      image: _imageProvider!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      errorBuilder: (context, error, stackTrace) =>
          widget.errorWidget ?? _buildPlaceholder(context),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: widget.width,
      height: widget.height,
      color: theme.colorScheme.surfaceContainer,
      child: Center(
        child: Icon(
          Icons.image_rounded,
          size: 32,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
