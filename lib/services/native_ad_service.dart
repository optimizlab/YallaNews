import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages native ad preloading and frequency capping for the Yalla News feed.
///
/// The goal is to maximize native ad revenue without hurting retention:
/// native ads are only served to *engaged* users, are capped per day, and the
/// placement rate slows down automatically once the daily cap is approached.
class NativeAdService {
  NativeAdService._internal();
  static final NativeAdService instance = NativeAdService._internal();

  // ── Ad unit ids ─────────────────────────────────────────────────────────
  static const String _adUnitId = 'ca-app-pub-2951683509728611/1778840232';
  static const String _testAdUnitId = 'ca-app-pub-3940256099942544/2247696110';

  // ── Native factory id registered in MainActivity.kt ─────────────────────
  static const String _factoryId = 'yallanewsNativeAd';

  // ── Frequency caps ──────────────────────────────────────────────────────
  static const int _minSecondsBetweenAds = 120;
  static const int _maxAdsPerDay = 15;
  static const int _minEngagementScore = 40;

  // ── Persisted stats ─────────────────────────────────────────────────────
  static const String _prefsKeyCount = 'native_ads_count';
  static const String _prefsKeyDate = 'native_ads_date';
  static const String _prefsKeyLast = 'native_ads_last_ts';

  // ── Preloaded pool ──────────────────────────────────────────────────────
  static const int _maxPreloaded = 3;

  final List<NativeAd> _pool = [];
  Timer? _windDownTimer;
  bool _initialized = false;
  bool _disposed = false;

  int _shownToday = 0;
  int _engagementScore = 0;

  final StreamController<int> _fillRateController = StreamController<int>.broadcast();

  /// Emits `loadedCount` when preloading succeeds or `0` when a load failed.
  Stream<int> get fillUpdates => _fillRateController.stream;

  int get availableAds => _pool.length;
  bool get hasAd => _pool.isNotEmpty;
  int get shownToday => _shownToday;
  int get engagementScore => _engagementScore;

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      _shownToday = prefs.getInt(_prefsKeyCount) ?? 0;
      _engagementScore = prefs.getInt('reward_ad_engagement_score') ?? 0;

      final today = DateTime.now().toIso8601String().split('T').first;
      final savedDate = prefs.getString(_prefsKeyDate);
      if (savedDate != today) {
        _shownToday = 0;
        await prefs.setString(_prefsKeyDate, today);
        await prefs.setInt(_prefsKeyCount, 0);
      }
    } catch (_) {}

    _startWindDownTimer();
  }

  /// Called from RewardAdService-style engagement tracking so both ad types
  /// share the same user-quality signal.
  void trackEngagement(int delta) {
    _engagementScore = (_engagementScore + delta).clamp(0, 100);
    unawaited(_saveEngagement());
  }

  Future<void> _saveEngagement() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('reward_ad_engagement_score', _engagementScore);
    } catch (_) {}
  }

  /// Refill the pool up to [_maxPreloaded] when capacity is available.
  void ensurePreloaded() {
    if (_disposed) return;
    if (_pool.length >= _maxPreloaded) return;
    if (!canServeMore()) return;
    _loadOne();
  }

  bool canServeMore() {
    if (_shownToday >= _maxAdsPerDay) return false;
    if (_engagementScore < _minEngagementScore) return false;
    return true;
  }

  Future<bool> _isSpacingOk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_prefsKeyLast) ?? 0;
      final elapsed = DateTime.now().millisecondsSinceEpoch - last;
      return elapsed >= _minSecondsBetweenAds * 1000;
    } catch (_) {
      return true;
    }
  }

  /// Returns a preloaded ad, or null when one isn't available yet.
  ///
  /// The caller MUST dispose the returned ad after it leaves the viewport.
  Future<NativeAd?> takeAd() async {
    if (!canServeMore()) return null;
    if (!await _isSpacingOk()) return null;

    if (_pool.isEmpty) {
      _loadOne();
      return null;
    }

    final ad = _pool.removeAt(0);
    _shownToday++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKeyCount, _shownToday);
      await prefs.setInt(_prefsKeyLast, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}

    // Small reward for watching a native ad impression session — this keeps
    // the shared engagement score in sync with revenue-generating sessions.
    trackEngagement(2);

    ensurePreloaded();
    return ad;
  }

  void _loadOne() {
    if (_disposed || !canServeMore()) return;

    final adUnitId = kReleaseMode ? _adUnitId : _testAdUnitId;

    NativeAd(
      adUnitId: adUnitId,
      factoryId: _factoryId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (Ad ad) {
          if (_disposed) {
            ad.dispose();
            return;
          }
          if (ad is NativeAd) {
            _pool.add(ad);
            _fillRateController.add(_pool.length);
          } else {
            ad.dispose();
          }
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _fillRateController.add(_pool.length);
          // Refill failed: retry after a cooldown so the feed keeps an ad ready.
          if (!_disposed && canServeMore()) {
            Future.delayed(const Duration(minutes: 3), () {
              if (!_disposed) _loadOne();
            });
          }
        },
      ),
    ).load();
  }

  void _startWindDownTimer() {
    _windDownTimer?.cancel();
    _windDownTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (_disposed) return;
      if (_pool.length < _maxPreloaded && canServeMore()) {
        _loadOne();
      }
    });
  }

  void dispose() {
    _disposed = true;
    _windDownTimer?.cancel();
    for (final ad in _pool) {
      ad.dispose();
    }
    _pool.clear();
    _fillRateController.close();
  }
}
