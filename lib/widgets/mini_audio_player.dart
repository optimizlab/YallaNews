import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yallanews/models/news_model.dart';
import 'package:yallanews/l10n/app_localizations.dart';
import 'package:yallanews/services/tts_service.dart';
import 'package:yallanews/views/news_detail_page.dart';
import 'package:yallanews/widgets/cached_news_image.dart';

/// Persistent floating mini audio player shown while an article has active TTS.
/// Stays visible as the user navigates between views across the app.
class MiniAudioPlayer extends StatefulWidget {
  const MiniAudioPlayer({super.key});

  @override
  State<MiniAudioPlayer> createState() => _MiniAudioPlayerState();
}

class _MiniAudioPlayerState extends State<MiniAudioPlayer>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _waveController;
  late Animation<Offset> _slideAnimation;

  bool _hiddenForDetailPage = false;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    // Listen to article changes to slide in/out
    TTSService.instance.articleNotifier.addListener(_onArticleChanged);
    // If already playing, animate in immediately
    if (TTSService.instance.currentArticle != null) {
      _slideController.forward();
      if (TTSService.instance.isPlaying) _waveController.repeat(reverse: true);
    }
  }

  void _onArticleChanged() {
    if (!mounted) return;
    final article = TTSService.instance.currentArticle;
    if (article != null) {
      _slideController.forward();
    } else {
      _slideController.reverse();
    }
  }

  @override
  void dispose() {
    TTSService.instance.articleNotifier.removeListener(_onArticleChanged);
    _slideController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    TTSService.instance.togglePlayback();
  }

  void _dismiss() {
    TTSService.instance.clearCurrentArticle();
  }

  void _openArticle(NewsModel article) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NewsDetailPage(article: article)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tts = TTSService.instance;

    return AnimatedBuilder(
      animation: Listenable.merge([
        tts.playingNotifier,
        tts.articleNotifier,
        tts.activeDetailPageNotifier,
        tts.progressNotifier,
      ]),
      builder: (context, _) {
        final article = tts.currentArticle;
        final isPlaying = tts.isPlaying;
        final activeDetailUrl = tts.activeDetailPageUrl;

        // Manage waveform animation
        if (isPlaying && !_waveController.isAnimating) {
          _waveController.repeat(reverse: true);
        } else if (!isPlaying && _waveController.isAnimating) {
          _waveController.stop();
        }

        // Hide when no article is loaded
        if (article == null) {
          _hiddenForDetailPage = false;
          return const SizedBox.shrink();
        }

        if (activeDetailUrl != null && activeDetailUrl == article.url) {
          _hiddenForDetailPage = true;
          return const SizedBox.shrink();
        }

        if (MediaQuery.of(context).viewInsets.bottom > 0) {
          _hiddenForDetailPage = false;
          return const SizedBox.shrink();
        }

        if (_hiddenForDetailPage) {
          _hiddenForDetailPage = false;
          _slideController.value = 1.0;
        }

        final theme = Theme.of(context);
        final l10n = AppLocalizations.of(context);
        final isMobile = MediaQuery.of(context).size.width < 600;
        final isDark = theme.brightness == Brightness.dark;

        final bottomOffset = isMobile
            ? kBottomNavigationBarHeight +
                MediaQuery.of(context).padding.bottom +
                10
            : 14.0;

        final imageUrl = article.imageUrl.isNotEmpty
            ? article.imageUrl
            : NewsModel.getFallbackImage(article.category);

        final subtitleText = article.displaySourceName.isNotEmpty
            ? article.displaySourceName
            : (article.sourceName.isNotEmpty
                ? article.sourceName
                : article.category);

        final progress = tts.progressNotifier.value;

        // Card gradient
        final gradientColors = isDark
            ? [const Color(0xFF1C1C2E), const Color(0xFF252540)]
            : [theme.colorScheme.surface, theme.colorScheme.surfaceContainerLow];

        return Align(
          alignment: Alignment.bottomCenter,
          child: SlideTransition(
            position: _slideAnimation,
            child: Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                bottom: bottomOffset,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    onTap: () => _openArticle(article),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.18),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 6),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
                            child: Row(
                              children: [
                                // Article thumbnail with playing ring
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Animated ring when playing
                                    if (isPlaying)
                                      AnimatedBuilder(
                                        animation: _waveController,
                                        builder: (_, __) => Container(
                                          width: 64,
                                          height: 64,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: theme.colorScheme.primary.withValues(
                                                alpha: 0.3 + 0.3 * _waveController.value,
                                              ),
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: CachedNewsImage(
                                        imageUrl: imageUrl,
                                        searchQuery: article.title,
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        placeholder: Container(
                                          width: 56,
                                          height: 56,
                                          color: theme.colorScheme.surfaceContainerHighest,
                                          child: Center(
                                            child: Icon(
                                              Icons.newspaper_rounded,
                                              size: 24,
                                              color: theme.colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                        errorWidget: Container(
                                          width: 56,
                                          height: 56,
                                          color: theme.colorScheme.surfaceContainerHighest,
                                          child: Center(
                                            child: Icon(
                                              Icons.image_not_supported_rounded,
                                              size: 24,
                                              color: theme.colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                // Title, source & waveform
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Status label
                                      if (isPlaying) ...[
                                        Row(
                                          children: [
                                            _AnimatedWaveform(
                                              controller: _waveController,
                                              color: theme.colorScheme.primary,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              l10n.translate('listen'),
                                              style: GoogleFonts.outfit(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: theme.colorScheme.primary,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                      ],
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
                                      const SizedBox(height: 3),
                                      Text(
                                        subtitleText,
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Controls column
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Dismiss button
                                    GestureDetector(
                                      onTap: _dismiss,
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: theme.colorScheme.surfaceContainerHighest,
                                        ),
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 14,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Play/Pause button
                                    GestureDetector(
                                      onTap: _togglePlayback,
                                      child: Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: [
                                              theme.colorScheme.primary,
                                              theme.colorScheme.primary.withValues(alpha: 0.8),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: theme.colorScheme.primary.withValues(alpha: 0.35),
                                              blurRadius: 10,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          color: theme.colorScheme.onPrimary,
                                          size: 24,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Progress bar
                          ClipRRect(
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(20),
                              bottomRight: Radius.circular(20),
                            ),
                            child: SizedBox(
                              height: 3,
                              child: LinearProgressIndicator(
                                value: progress,
                                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.colorScheme.primary,
                                ),
                                minHeight: 3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Animated 3-bar waveform shown when playing
class _AnimatedWaveform extends StatelessWidget {
  const _AnimatedWaveform({
    required this.controller,
    required this.color,
  });

  final AnimationController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        const barCount = 3;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(barCount, (i) {
            final phase = (i / barCount) * math.pi;
            final height = 6 + 8 * math.sin(controller.value * math.pi + phase).abs();
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: 3,
              height: height,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}
