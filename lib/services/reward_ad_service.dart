import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show BuildContext;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RewardAdService {
  RewardAdService._internal();
  static final RewardAdService instance = RewardAdService._internal();

  static const String _adUnitId = 'ca-app-pub-2951683509728611/3533646704';

  static const String _prefsKeyLastAdTime = 'reward_ad_last_show_time';
  static const String _prefsKeyAdsShownToday = 'reward_ads_shown_today';
  static const String _prefsKeyAdsShownDate = 'reward_ads_shown_date';
  static const String _prefsKeyUserEngagementScore = 'reward_ad_engagement_score';
  static const String _prefsKeyTotalAdsShown = 'reward_ads_total_shown';
  static const String _prefsKeyTotalRewardsEarned = 'reward_ads_total_rewards';
  static const String _prefsKeyArticlesReadCount = 'reward_ad_articles_read_count';
  static const String _prefsKeyAppStartTime = 'reward_ad_app_start_time';

  static const int _minIntervalBetweenAdsMinutes = 5;
  static const int _maxAdsPerDay = 10;
  static const int _minEngagementScoreForAd = 0;
  static const int _engagementBoostPerArticleRead = 10;
  static const int _engagementBoostPerAction = 5;
  static const int _engagementDecayPerHour = 2;

  // ── Reward ad trigger thresholds ──────────────────────────────────────────
  static const int _minArticlesReadBeforeRewardAd = 2;
  static const int _minSecondsSpentBeforeRewardAd = 5;

  RewardedInterstitialAd? _rewardedInterstitialAd;
  bool _isAdLoading = false;
  bool _isInitialized = false;
  int _engagementScore = 0;
  int _adsShownToday = 0;
  int _totalAdsShown = 0;
  int _totalRewardsEarned = 0;
  int _articlesReadCount = 0;
  int? _sessionStartTime;

  final StreamController<RewardAdEvent> _eventController =
      StreamController<RewardAdEvent>.broadcast();

  Stream<RewardAdEvent> get events => _eventController.stream;

  bool get isAdReady => _rewardedInterstitialAd != null;
  bool get isLoading => _isAdLoading;
  int get engagementScore => _engagementScore;
  int get adsShownToday => _adsShownToday;
  int get totalAdsShown => _totalAdsShown;
  int get totalRewardsEarned => _totalRewardsEarned;
  int get articlesReadCount => _articlesReadCount;

  /// Returns true when enough articles have been read and enough time has
  /// been spent in the app to warrant showing a reward ad.
  bool get shouldShowRewardAdOnRead {
    if (_articlesReadCount < _minArticlesReadBeforeRewardAd) return false;
    if (_sessionStartTime == null) return false;
    final elapsed = DateTime.now().millisecondsSinceEpoch - _sessionStartTime!;
    return elapsed >= _minSecondsSpentBeforeRewardAd * 1000;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    await _loadPersistedData();
    await _resetDailyCountersIfNeeded();
    _startEngagementDecayTimer();
    _sessionStartTime ??= DateTime.now().millisecondsSinceEpoch;
    // Do not auto-preload on app start; preload only after user engagement
    // (article read) so the user can read at least 2 items before ads appear.
  }

  /// Call when the user finishes reading an article. Increments the read count
  /// and shows a reward ad when thresholds are met.
  ///
  /// [context] is unused — [RewardedInterstitialAd.show] does not require a
  /// BuildContext. It is accepted for API compatibility.
  Future<void> recordArticleRead(BuildContext? context, {
    required String placement,
    VoidCallback? onRewardEarned,
    VoidCallback? onAdDismissed,
  }) async {
    _articlesReadCount++;
    trackUserEngagement(EngagementType.articleRead);
    await _persistData();
    debugPrint(
      '[REWARD AD] Articles read: $_articlesReadCount, engagement=$_engagementScore, shouldShow=${shouldShowRewardAdOnRead}',
    );
    if (shouldShowRewardAdOnRead) {
      await showAdIfAppropriate(
        placement: placement,
        onRewardEarned: onRewardEarned,
        onAdDismissed: onAdDismissed,
      );
    }
  }

  Future<void> _loadPersistedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _engagementScore = prefs.getInt(_prefsKeyUserEngagementScore) ?? 0;
      _adsShownToday = prefs.getInt(_prefsKeyAdsShownToday) ?? 0;
      _totalAdsShown = prefs.getInt(_prefsKeyTotalAdsShown) ?? 0;
      _totalRewardsEarned = prefs.getInt(_prefsKeyTotalRewardsEarned) ?? 0;
      _articlesReadCount = prefs.getInt(_prefsKeyArticlesReadCount) ?? 0;
    } catch (_) {}
  }

  Future<void> _persistData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKeyUserEngagementScore, _engagementScore);
      await prefs.setInt(_prefsKeyAdsShownToday, _adsShownToday);
      await prefs.setInt(_prefsKeyTotalAdsShown, _totalAdsShown);
      await prefs.setInt(_prefsKeyTotalRewardsEarned, _totalRewardsEarned);
      await prefs.setInt(_prefsKeyArticlesReadCount, _articlesReadCount);
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

  Future<bool> _shouldShowAdNow() async {
    debugPrint(
      '[REWARD AD] _shouldShowAdNow: adsShownToday=$_adsShownToday (max=$_maxAdsPerDay), engagement=$_engagementScore (min=$_minEngagementScoreForAd)',
    );
    if (_adsShownToday >= _maxAdsPerDay) {
      debugPrint('[REWARD AD] Blocked: daily limit reached');
      return false;
    }
    if (_engagementScore < _minEngagementScoreForAd) {
      debugPrint('[REWARD AD] Blocked: engagement too low');
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastTime = prefs.getInt(_prefsKeyLastAdTime) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final minutesSinceLastAd = (now - lastTime) / (1000 * 60);
      debugPrint(
        '[REWARD AD] Last ad time: $lastTime, minutes since: $minutesSinceLastAd',
      );
      if (minutesSinceLastAd < _minIntervalBetweenAdsMinutes) {
        debugPrint('[REWARD AD] Blocked: interval not elapsed');
        return false;
      }
    } catch (_) {}

    debugPrint('[REWARD AD] All criteria met');
    return true;
  }

  void _maybePreloadAd() {
    if (!_isInitialized) return;
    if (!_isAdLoading && _rewardedInterstitialAd == null) {
      _preloadAd();
    }
  }

  Future<void> _preloadAd() async {
    if (_isAdLoading || _rewardedInterstitialAd != null) return;
    _isAdLoading = true;

    debugPrint('[REWARD AD] Preloading reward interstitial ad: $_adUnitId');

    try {
      final adUnitId = _adUnitId;

      await RewardedInterstitialAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback:
            RewardedInterstitialAdLoadCallback(
          onAdLoaded: (RewardedInterstitialAd ad) {
            _rewardedInterstitialAd = ad;
            _isAdLoading = false;
            debugPrint('[REWARD AD] Reward interstitial ad loaded successfully');
            _eventController.add(const RewardAdEvent.loaded());
          },
          onAdFailedToLoad: (LoadAdError error) {
            _isAdLoading = false;
            debugPrint('[REWARD AD] Reward interstitial ad failed to load: $error');
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
    BuildContext? context,
    required String placement,
    VoidCallback? onRewardEarned,
    VoidCallback? onAdDismissed,
  }) async {
    debugPrint(
      '[REWARD AD] showAdIfAppropriate: placement=$placement, adsShownToday=$_adsShownToday, engagement=$_engagementScore, rewardedAd==null=${_rewardedInterstitialAd == null}',
    );
    if (!await _shouldShowAdNow()) {
      _eventController.add(RewardAdEvent.notShown('Criteria not met'));
      return false;
    }

    if (_rewardedInterstitialAd == null) {
      await _preloadAd();
      await Future.delayed(const Duration(seconds: 3));
      if (_rewardedInterstitialAd == null) {
        _eventController.add(RewardAdEvent.notShown('Ad not ready'));
        return false;
      }
    }

    final completer = Completer<bool>();

    _rewardedInterstitialAd!.fullScreenContentCallback =
        FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _eventController.add(RewardAdEvent.shown(placement));
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedInterstitialAd = null;
        _recordAdShown();
        _preloadAd();
        onAdDismissed?.call();
        completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedInterstitialAd = null;
        _eventController.add(RewardAdEvent.failedToShow(error.toString()));
        _preloadAd();
        completer.complete(false);
      },
    );

    _rewardedInterstitialAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        _totalRewardsEarned++;
        _persistData();
        _eventController.add(
          RewardAdEvent.rewardEarned(placement, reward.amount.toInt()),
        );
        debugPrint('[REWARD AD] Reward earned: ${reward.amount}');
        onRewardEarned?.call();
      },
    );

    debugPrint('[REWARD AD] Interstitial ad shown: $placement');
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
    BuildContext? context,
    required String placement,
    VoidCallback? onRewardEarned,
    VoidCallback? onAdDismissed,
  }) async {
    if (_rewardedInterstitialAd == null) {
      await _preloadAd();
      await Future.delayed(const Duration(seconds: 5));
    }

    if (_rewardedInterstitialAd == null) {
      _eventController.add(RewardAdEvent.notShown('Ad not loaded'));
      return;
    }

    _rewardedInterstitialAd!.fullScreenContentCallback =
        FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _eventController.add(RewardAdEvent.shown(placement));
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedInterstitialAd = null;
        _recordAdShown();
        _preloadAd();
        onAdDismissed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedInterstitialAd = null;
        _eventController.add(RewardAdEvent.failedToShow(error.toString()));
        _preloadAd();
      },
    );

    _rewardedInterstitialAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        _totalRewardsEarned++;
        _persistData();
        _eventController.add(
          RewardAdEvent.rewardEarned(placement, reward.amount.toInt()),
        );
        onRewardEarned?.call();
      },
    );
  }

  void dispose() {
    _rewardedInterstitialAd?.dispose();
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
