import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/reward_ad_service.dart';
import '../services/native_ad_service.dart';
import '../l10n/app_localizations.dart';

class RewardAdWidget extends StatefulWidget {
  final String placement;
  final VoidCallback? onRewardEarned;
  final VoidCallback? onAdDismissed;
  final bool showOnlyWhenReady;

  const RewardAdWidget({
    super.key,
    required this.placement,
    this.onRewardEarned,
    this.onAdDismissed,
    this.showOnlyWhenReady = true,
  });

  @override
  State<RewardAdWidget> createState() => _RewardAdWidgetState();
}

class _RewardAdWidgetState extends State<RewardAdWidget> {
  bool _showAdButton = false;
  late StreamSubscription _eventSubscription;

  @override
  void initState() {
    super.initState();
    _eventSubscription = RewardAdService.instance.events.listen(_onAdEvent);
    _checkAdReady();
  }

  @override
  void dispose() {
    _eventSubscription.cancel();
    super.dispose();
  }

  void _onAdEvent(RewardAdEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case RewardAdEventType.loaded:
        _checkAdReady();
        break;
      case RewardAdEventType.shown:
      case RewardAdEventType.rewardEarned:
      case RewardAdEventType.failedToLoad:
      case RewardAdEventType.failedToShow:
      case RewardAdEventType.notShown:
        _checkAdReady();
        break;
    }
  }

  void _checkAdReady() {
    if (mounted) {
      setState(() {
        _showAdButton = RewardAdService.instance.isAdReady && !RewardAdService.instance.isLoading;
      });
    }
  }

  Future<void> _showAd() async {
    if (!RewardAdService.instance.isAdReady) return;

    final l10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.card_giftcard_rounded, color: Colors.amber, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.translate('rewardAdTitle') ?? 'Earn Reward',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.translate('rewardAdMessage') ??
                  'Watch a short video to support the app and earn a reward!',
              style: GoogleFonts.outfit(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.monetization_on_rounded, color: Colors.amber, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    l10n.translate('rewardAdReward') ?? 'Reward awaits!',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.translate('cancel') ?? 'Later', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await RewardAdService.instance.showAdIfAppropriate(
                context: context,
                placement: widget.placement,
                onRewardEarned: widget.onRewardEarned,
                onAdDismissed: widget.onAdDismissed,
              );
            },
            icon: const Icon(Icons.play_circle_fill_rounded, size: 20),
            label: Text(l10n.translate('watchAd') ?? 'Watch Ad', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showOnlyWhenReady && !_showAdButton) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.withOpacity(0.15),
            Colors.orange.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.card_giftcard_rounded, color: Colors.amber, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.translate('rewardAdTitle') ?? 'Support Yalla News',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.translate('rewardAdDescription') ??
                      'Watch a short ad to support the app and earn rewards',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (_showAdButton)
            ElevatedButton.icon(
              onPressed: _showAd,
              icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
              label: Text(
                l10n.translate('watchAd') ?? 'Watch Ad',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            )
          else
            SizedBox(
              width: 80,
              child: Center(
                child: RewardAdService.instance.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        l10n.translate('rewardAdLoading') ?? 'Preparing...',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class InlineRewardAdButton extends StatelessWidget {
  final String placement;
  final VoidCallback? onRewardEarned;
  final VoidCallback? onAdDismissed;

  const InlineRewardAdButton({
    super.key,
    required this.placement,
    this.onRewardEarned,
    this.onAdDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return StreamBuilder<RewardAdEvent>(
      stream: RewardAdService.instance.events,
      initialData: const RewardAdEvent.loaded(),
      builder: (context, snapshot) {
        final isReady = RewardAdService.instance.isAdReady;
        final isLoading = RewardAdService.instance.isLoading;

        return InkWell(
          onTap: isReady
              ? () async {
                  await RewardAdService.instance.showAdIfAppropriate(
                    context: context,
                    placement: placement,
                    onRewardEarned: onRewardEarned,
                    onAdDismissed: onAdDismissed,
                  );
                }
              : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: isReady
                  ? LinearGradient(
                      colors: [Colors.amber.shade600, Colors.orange.shade600],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                      ],
                    ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isReady ? Colors.transparent : Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                else
                  Icon(
                    isReady ? Icons.card_giftcard_rounded : Icons.hourglass_empty_rounded,
                    size: 20,
                    color: isReady ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                const SizedBox(width: 8),
                Text(
                  isReady
                      ? (l10n.translate('watchAdEarnReward') ?? 'Watch Ad & Earn Reward')
                      : (l10n.translate('rewardAdPreparing') ?? 'Preparing Reward...'),
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isReady ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isReady) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      l10n.translate('free') ?? 'FREE',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Native ad card that blends into the news feed.
///
/// Renders a preloaded native ad (see [NativeAdService]) when one is available
/// and reports it back when the card scrolls off screen so the ad object can be
/// disposed and the slot reused.
class NativeAdWidget extends StatefulWidget {
  final String placement;
  final EdgeInsetsGeometry margin;

  const NativeAdWidget({
    super.key,
    this.placement = 'home_feed_native',
    this.margin = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget> {
  NativeAd? _ad;
  bool _loadRequested = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _acquireAd();
  }

  Future<void> _acquireAd() async {
    if (_loadRequested || _isDisposed) return;
    _loadRequested = true;

    // The service keeps a pool warm; ask for one and retry on a short cadence
    // so a slow first fill doesn't remove the slot permanently.
    await NativeAdService.instance.initialize();
    for (var attempt = 0; attempt < 3 && !_isDisposed; attempt++) {
      final ad = await NativeAdService.instance.takeAd();
      if (_isDisposed) {
        ad?.dispose();
        return;
      }
      if (ad != null) {
        if (!mounted) {
          ad.dispose();
          return;
        }
        setState(() => _ad = ad);
        NativeAdService.instance.ensurePreloaded();
        return;
      }
      NativeAdService.instance.ensurePreloaded();
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(seconds: 4));
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    // The ad object is single-use: dispose it once it leaves the tree.
    Future<void>.microtask(() => _ad?.dispose());
    _ad = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;

    // Render nothing (no reserved space) when there is no ad to show so the
    // feed stays tight while the pool refills.
    if (ad == null) return const SizedBox.shrink();

    return Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Row(
              children: [
                Icon(
                  Icons.campaign_rounded,
                  size: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context).translate('sponsoredLabel') ?? 'Sponsored',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 400,
            width: double.infinity,
            child: AdWidget(ad: ad),
          ),
        ],
      ),
    );
  }
}

/// Native ad shown on the news detail page.
///
/// Loads its own ad directly (no engagement gating) so the detail placement
/// reliably renders an AdMob native ad when one loads. Renders nothing while
/// the ad is loading or failed, keeping the page layout tight.
class DetailNativeAdWidget extends StatefulWidget {
  const DetailNativeAdWidget({super.key});

  @override
  State<DetailNativeAdWidget> createState() => _DetailNativeAdWidgetState();
}

class _DetailNativeAdWidgetState extends State<DetailNativeAdWidget> {
  NativeAd? _ad;
  bool _loading = false;

  static const String _adUnitId = 'ca-app-pub-2951683509728611/1778840232';
  static const String _factoryId = 'yallanewsNativeAd';

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    if (_loading || _ad != null) return;
    _loading = true;
    NativeAd(
      adUnitId: _adUnitId,
      factoryId: _factoryId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (Ad ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _ad = ad as NativeAd;
            _loading = false;
          });
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _loading = false;
          });
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ad == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Row(
              children: [
                Icon(
                  Icons.campaign_rounded,
                  size: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context).translate('sponsoredLabel') ?? 'Sponsored',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 400,
            width: double.infinity,
            child: AdWidget(ad: _ad!),
          ),
        ],
      ),
    );
  }
}