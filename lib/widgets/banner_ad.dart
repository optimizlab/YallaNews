import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../l10n/app_localizations.dart';

/// Small rectangular banner ad that slides between news items in the feed.
///
/// Loads a banner ad and renders it styled like a news list item.
/// Always reserves a fixed-height ad slot so the feed never jumps or flashes
/// when an ad loads, fails, or the parent rebuilds.
class BannerAdWidget extends StatefulWidget {
  final String placement;
  final double? width;
  final double? height;

  const BannerAdWidget({
    super.key,
    this.placement = 'banner_1',
    this.width,
    this.height,
  });

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

enum _AdState { loading, loaded, failed }

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _ad;
  _AdState _state = _AdState.loading;

  static const String _adUnitId = 'ca-app-pub-2951683509728611/4930663860';

  // Fixed slot height so the feed layout is stable regardless of ad state.
  static const double _slotHeight = 110.0;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  void _loadAd() {
    if (_state != _AdState.loading || _ad != null) return;
    _state = _AdState.loading;

    final adUnitId = _adUnitId;

    final bannerAd = BannerAd(
      adUnitId: adUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          final banner = ad as BannerAd;
          setState(() {
            _ad = banner;
            _state = _AdState.loaded;
          });
          debugPrint(
            '[BANNER AD] Loaded placement=${widget.placement} size=${banner.size.width}x${banner.size.height}',
          );
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _state = _AdState.failed;
          });
          ad.dispose();
          debugPrint('[BANNER AD] Failed to load placement=${widget.placement}: $error');
        },
      ),
    );
    bannerAd.load();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;

    // Always reserve a fixed-height slot so the feed layout never shifts
    // when an ad loads, fails, or the parent rebuilds.
    if (ad == null) {
      return _buildPlaceholder();
    }

    final l10n = AppLocalizations.of(context);

    final adHeight = ad.size.height.toDouble();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      constraints: BoxConstraints(minHeight: adHeight + 50),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              children: [
                Icon(
                  Icons.campaign_rounded,
                  size: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.translate('sponsoredLabel') ?? 'Sponsored',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: adHeight,
            child: AdWidget(ad: ad),
          ),
        ],
      ),
    );
  }

  /// Fixed-height placeholder rendered while the ad is loading or after it
  /// has failed. Keeps the feed layout stable so the list never flashes.
  Widget _buildPlaceholder() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      height: _slotHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.15),
          style: BorderStyle.solid,
        ),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
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
    );
  }
}
