import 'dart:async';
import 'package:flutter/material.dart';

class CachedNewsImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CachedNewsImage({
    Key? key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
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

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(CachedNewsImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (widget.imageUrl.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'empty';
      });
      return;
    }

    final lower = widget.imageUrl.toLowerCase();
    if (lower.contains('bing.com/images/search') ||
        lower.contains('google.com/search') ||
        lower.contains('yahoo.com/search')) {
      setState(() {
        _isLoading = false;
        _error = 'invalid';
      });
      return;
    }

    try {
      final provider = NetworkImage(widget.imageUrl);
      final completer = Completer<void>();
      final stream = provider.resolve(const ImageConfiguration());
      final listener = ImageStreamListener((info, _) {
        if (!completer.isCompleted) completer.complete();
      }, onError: (error, _) {
        if (!completer.isCompleted) completer.completeError(error);
      });
      stream.addListener(listener);
      await completer.future.timeout(const Duration(seconds: 8));
      if (mounted) {
        setState(() {
          _imageProvider = provider;
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
      return widget.errorWidget ??
        Container(
          width: widget.width,
          height: widget.height,
          color: Colors.grey[300],
          child: Icon(
            Icons.image_rounded,
            size: 32,
            color: Colors.grey[400],
          ),
        );
    }

    return Image(
      image: _imageProvider!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) => widget.errorWidget ?? _buildPlaceholder(context),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[300],
      child: Icon(
        Icons.image_rounded,
        size: 32,
        color: Colors.grey[400],
      ),
    );
  }
}
