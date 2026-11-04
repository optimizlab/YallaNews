import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show BuildContext;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RewardAdService {
  RewardAdService._internal();
  static final RewardAdService instance = RewardAdService._internal();

  static const String _adUnitId = 'ca-app-pub-2951683509728611/3219485811';

  static const String _prefsKeyLastAdTime = 'reward_ad_last_show_time';
  static const String _prefsKeyAdsShownToday = 'reward_ads_shown_today';
  static const String _prefsKeyAdsShownDate = 'reward_ads_shown_date';
  static const String _prefsKeyUserEngagementScore = 'reward_ad_engagement_score';
  static const String _prefsKeyTotalAdsShown = 'reward_ads_total_shown';
  static const String _prefsKeyTotalRewardsEarned = 'reward_ads_total_rewards';

  static const int _minIntervalBetweenAdsMinutes = 5;
  static const int _maxAdsPerDay = 10;
  static const int _minEngagementScoreForAd = 30;
  static const int _engagementBoostPerArticleRead = 10;
  static const int _engagementBoostPerAction = 5;
  static const int _engagementDecayPerHour = 2;

  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;
  bool _isInitialized = false;
  int _engagementScore = 0;
  int _adsShownToday = 0;
  int _totalAdsShown = 0;
  int _totalRewardsEarned = 0;

  final StreamController<RewardAdEvent> _eventController =
      StreamController<RewardAdEvent>.broadcast();

  Stream<RewardAdEvent> get events => _eventController.stream;

  bool get isAdReady => _rewardedAd != null;
  bool get isLoading => _isAdLoading;
  int get engagementScore => _engagementScore;
  int get adsShownToday => _adsShownToday;
  int get totalAdsShown => _totalAdsShown;
  int get totalRewardsEarned => _totalRewardsEarned;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    await _loadPersistedData();
    await _resetDailyCountersIfNeeded();
    _startEngagementDecayTimer();
    _preloadAd();
  }

  Future<void> _loadPersistedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _engagementScore = prefs.getInt(_prefsKeyUserEngagementScore) ?? 0;
      _adsShownToday = prefs.getInt(_prefsKeyAdsShownToday) ?? 0;
      _totalAdsShown = prefs.getInt(_prefsKeyTotalAdsShown) ?? 0;
      _totalRewardsEarned = prefs.getInt(_prefsKeyTotalRewardsEarned) ?? 0;
    } catch (_) {}
  }

  Future<void> _persistData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKeyUserEngagementScore, _engagementScore);
      await prefs.setInt(_prefsKeyAdsShownToday, _adsShownToday);
      await prefs.setInt(_prefsKeyTotalAdsShown, _totalAdsShown);
      await prefs.setInt(_prefsKeyTotalRewardsEarned, _totalRewardsEarned);
    } catch (_) {}
  }

  Future<void> _resetDailyCountersIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastDateStr = prefs.getString(_prefsKeyAdsShownDate);
      final today = DateTime.now().toIso8601String().split('T').first;

      if (lastDateStr != today) {
        _adsShownToday = 0;
        await prefs.setString(_prefsKeyAdsShownDate, today);
        await prefs.setInt(_prefsKeyAdsShownToday, 0);
      }
    } catch (_) {}
  }

  void _startEngagementDecayTimer() {
    Timer.periodic(const Duration(hours: 1), (_) {
      _engagementScore = (_engagementScore - _engagementDecayPerHour).clamp(0, 100);
      _persistData();
    });
  }

  void trackUserEngagement(EngagementType type) {
    switch (type) {
      case EngagementType.articleRead:
        _engagementScore = (_engagementScore + _engagementBoostPerArticleRead).clamp(0, 100);
        break;
      case EngagementType.articleShare:
      case EngagementType.articleSave:
      case EngagementType.articleLike:
      case EngagementType.categoryBrowse:
      case EngagementType.searchPerformed:
        _engagementScore = (_engagementScore + _engagementBoostPerAction).clamp(0, 100);
        break;
      case EngagementType.appOpen:
        _engagementScore = (_engagementScore + 5).clamp(0, 100);
        break;
    }
    _persistData();
    _maybePreloadAd();
  }

  bool _shouldShowAdNow() {
    if (_adsShownToday >= _maxAdsPerDay) return false;
    if (_engagementScore < _minEngagementScoreForAd) return false;

    try {
      final prefs = SharedPreferences.getInstance();
      prefs.then((p) {
        final lastTime = p.getInt(_prefsKeyLastAdTime) ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        final minutesSinceLastAd = (now - lastTime) / (1000 * 60);
        if (minutesSinceLastAd < _minIntervalBetweenAdsMinutes) return false;
      });
    } catch (_) {}

    return true;
  }

  void _maybePreloadAd() {
    if (!_isInitialized) return;
    if (_shouldShowAdNow() && !_isAdLoading && _rewardedAd == null) {
      _preloadAd();
    }
  }

  Future<void> _preloadAd() async {
    if (_isAdLoading || _rewardedAd != null) return;
    _isAdLoading = true;

    try {
      final adUnitId = _adUnitId;

      await RewardedAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) {
            _rewardedAd = ad;
            _isAdLoading = false;
            _eventController.add(const RewardAdEvent.loaded());
          },
          onAdFailedToLoad: (LoadAdError error) {
            _isAdLoading = false;
            _eventController.add(RewardAdEvent.failedToLoad(error.toString()));
            Future.delayed(const Duration(minutes: 2), _preloadAd);
          },
        ),
      );
    } catch (_) {
      _isAdLoading = false;
    }
  }

  Future<bool> showAdIfAppropriate({
    required BuildContext context,
    required String placement,
    VoidCallback? onRewardEarned,
    VoidCallback? onAdDismissed,
  }) async {
    if (!_shouldShowAdNow()) {
      _eventController.add(RewardAdEvent.notShown('Criteria not met'));
      return false;
    }

    if (_rewardedAd == null) {
      await _preloadAd();
      await Future.delayed(const Duration(seconds: 3));
      if (_rewardedAd == null) {
        _eventController.add(RewardAdEvent.notShown('Ad not ready'));
        return false;
      }
    }

    final completer = Completer<bool>();

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _eventController.add(RewardAdEvent.shown(placement));
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _recordAdShown();
        _preloadAd();
        onAdDismissed?.call();
        completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        _eventController.add(RewardAdEvent.failedToShow(error.toString()));
        _preloadAd();
        completer.complete(false);
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        _totalRewardsEarned++;
        _persistData();
        _eventController.add(RewardAdEvent.rewardEarned(placement, reward.amount.toInt()));
        onRewardEarned?.call();
      },
    );

    return completer.future;
  }

  void _recordAdShown() async {
    _adsShownToday++;
    _totalAdsShown++;
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKeyAdsShownToday, _adsShownToday);
      await prefs.setInt(_prefsKeyTotalAdsShown, _totalAdsShown);
      await prefs.setInt(_prefsKeyLastAdTime, now);
    } catch (_) {}

    _persistData();
    _engagementScore = (_engagementScore - 15).clamp(0, 100);
  }

  Future<void> forceShowAd({
    required BuildContext context,
    required String placement,
    VoidCallback? onRewardEarned,
    VoidCallback? onAdDismissed,
  }) async {
    if (_rewardedAd == null) {
      await _preloadAd();
      await Future.delayed(const Duration(seconds: 5));
    }

    if (_rewardedAd == null) {
      _eventController.add(RewardAdEvent.notShown('Ad not loaded'));
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _eventController.add(RewardAdEvent.shown(placement));
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _recordAdShown();
        _preloadAd();
        onAdDismissed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        _eventController.add(RewardAdEvent.failedToShow(error.toString()));
        _preloadAd();
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        _totalRewardsEarned++;
        _persistData();
        _eventController.add(RewardAdEvent.rewardEarned(placement, reward.amount.toInt()));
        onRewardEarned?.call();
      },
    );
  }

  void dispose() {
    _rewardedAd?.dispose();
    _eventController.close();
    _isInitialized = false;
  }
}

enum EngagementType {
  appOpen,
  articleRead,
  articleShare,
  articleSave,
  articleLike,
  categoryBrowse,
  searchPerformed,
}

enum RewardAdEventType {
  loaded,
  shown,
  rewardEarned,
  failedToLoad,
  failedToShow,
  notShown,
}

class RewardAdEvent {
  final RewardAdEventType type;
  final String? placement;
  final String? error;
  final int? rewardAmount;

  const RewardAdEvent.loaded() : this._(type: RewardAdEventType.loaded);

  const RewardAdEvent.shown(String placement)
      : this._(type: RewardAdEventType.shown, placement: placement);

  const RewardAdEvent.rewardEarned(String placement, int rewardAmount)
      : this._(
          type: RewardAdEventType.rewardEarned,
          placement: placement,
          rewardAmount: rewardAmount,
        );

  const RewardAdEvent.failedToLoad(String error)
      : this._(type: RewardAdEventType.failedToLoad, error: error);

  const RewardAdEvent.failedToShow(String error)
      : this._(type: RewardAdEventType.failedToShow, error: error);

  const RewardAdEvent.notShown(String reason)
      : this._(type: RewardAdEventType.notShown, error: reason);

  const RewardAdEvent._({
    required this.type,
    this.placement,
    this.error,
    this.rewardAmount,
  });
}