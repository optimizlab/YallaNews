import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz2;

// ============================================================================
// Platform stubs for Windows/web where Android-only plugins aren't available.
// ============================================================================

// ── URL Launcher stubs ──
class LaunchMode {
  static const LaunchMode externalApplication = LaunchMode._();
  const LaunchMode._();
}
Future<bool> launchUrl(Uri uri, {LaunchMode? mode}) async => false;
Future<bool> canLaunchUrl(Uri uri) async => false;

// ── WebView stubs ──
class WebViewController {
  Future<void> initialize() async {}
  Future<void> loadUrl(String url) async {}
  Future<void> loadRequest(request) async {}
  Future<void> setJavaScriptMode(mode) async {}
  Future<void> setPopupWindowPolicy(policy) async {}
  Future<void> setDefaultContextMenusEnabled(bool enabled) async {}
  Future<void> loadHtmlString(String html) async {}
  Future<void> loadFile(String asset) async {}
  Future<String> getCurrentUrl() async => '';
  void dispose() {}
  var value;
}

class JavaScriptMode {
  static const JavaScriptMode unrestricted = JavaScriptMode._();
  const JavaScriptMode._();
}

class WebViewWidget extends StatelessWidget {
  final WebViewController controller;
  const WebViewWidget({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class WebViewPopupWindowPolicy {
  static const WebViewPopupWindowPolicy deny = WebViewPopupWindowPolicy._();
  const WebViewPopupWindowPolicy._();
}

class NavigationDelegate {}

// ── Google Mobile Ads stubs ──
class BannerAd {
  BannerAd({required String adUnitId, required AdSize size, required AdRequest request, required BannerAdListener listener});
  void load() {}
  void dispose() {}
}

class BannerAdListener {
  void onAdLoaded(Ad ad) {}
  void onAdFailedToLoad(Ad ad, LoadAdError error) {}
  void onAdOpened(Ad ad) {}
  void onAdClosed(Ad ad) {}
  void onAdImpression(Ad ad) {}
  void onAdClicked(Ad ad) {}
}

class Ad {
  void dispose() {}
}

class AdSize {
  static const AdSize banner = AdSize._();
  const AdSize._();
}

class AdRequest {}
class LoadAdError {}

class AdWidget {
  final Ad ad;
  const AdWidget({required this.ad});
}

class RewardedInterstitialAd {
  static Future<RewardedInterstitialAd?> load({required String adUnitId, required AdRequest request, required RewardedInterstitialAdLoadCallback loadCallback}) async => null;
  void show({required void Function(RewardedInterstitialAd) onAdLoaded, required void Function(LoadAdError) onAdFailedToLoad}) {}
  void dispose() {}
}

class RewardedInterstitialAdLoadCallback {
  void onAdLoaded(RewardedInterstitialAd ad) {}
  void onAdFailedToLoad(LoadAdError error) {}
}

class AdWithoutView {
  AdWithoutView({required String adUnitId, required AdRequest request});
  void show({required void Function(AdWithoutView) onAdLoaded, required void Function(AdWithoutView, AdError) onAdFailedToLoad}) {}
}

class RewardItem {
  String get type => '';
  int get amount => 0;
}

class FullScreenContentCallback {
  void onAdDismissedFullScreenContent(AdWithoutView ad) {}
  void onAdFailedToShowFullScreenContent(AdWithoutView ad, AdError error) {}
  void onAdShowedFullScreenContent(AdWithoutView ad) {}
}

class AdError {}

class NativeAd {
  NativeAd({required String adUnitId, required AdRequest request, required NativeAdListener listener, required int numberOfAds});
  void load() {}
  void dispose() {}
}

class NativeAdListener {
  void onAdLoaded(Ad ad) {}
  void onAdFailedToLoad(Ad ad, LoadAdError error) {}
}

// ── Audio Players stubs ──
class AudioPlayer {
  Future<void> play(AssetSource source) async {}
  Future<void> pause() async {}
  Future<void> stop() async {}
  Future<void> release() async {}
  Future<void> dispose() async => release();
  Future<void> setSource(AssetSource source) async {}
  Future<void> setUrl(String url) async {}
  PlayerState get state => PlayerState.stopped;
  Stream<PlayerState> get onPlayerStateChanged => _stateController.stream;
  final _stateController = StreamController<PlayerState>.broadcast();
  Stream<PlayerState> get onPlayerComplete => _stateController.stream;
  void _emit(PlayerState s) => _stateController.add(s);
}

class AssetSource {
  final String path;
  AssetSource(this.path);
  factory AssetSource.file(String path) => AssetSource(path);
  factory AssetSource.bytes(List<int> bytes) => AssetSource('');
}

class PlayerState {
  static const PlayerState stopped = PlayerState._('stopped');
  static const PlayerState playing = PlayerState._('playing');
  static const PlayerState paused = PlayerState._('paused');
  static const PlayerState completed = PlayerState._('completed');
  const PlayerState._(this.value);
  final String value;
}

// ── Flutter TTS stubs ──
class FlutterTts {
  Future<void> speak(String text) async {}
  Future<void> stop() async {}
  Future<void> setLanguage(String lang) async {}
  Future<void> setPitch(double pitch) async {}
  Future<void> setSpeechRate(double rate) async {}
}

// ── Workmanager stubs ──
class Workmanager {
  static Future<void> initialize(callbackDispatcher, {bool isInDebugMode = false}) async {}
  static Future<void> registerPeriodicTask(String taskName, String taskName2, {Duration? frequency, Constraints? constraints, Duration? initialDelay}) async {}
  static Future<void> executeTask(callback) async {}
  static Future<void> cancelByUniqueName(String name) async {}
}

class Constraints {
  Constraints({networkType, requiresBatteryNotLow, requiresCharging});
}

class NetworkType {
  static const NetworkType connected = NetworkType._();
  static const NetworkType unmetered = NetworkType._();
  const NetworkType._();
}

// ── Geolocator stubs ──
class Geolocator {
  static Future<LocationPermission> checkPermission() async => LocationPermission.always;
  static Future<LocationPermission> requestPermission() async => LocationPermission.always;
  static Future<Position> getCurrentPosition({LocationAccuracy? accuracy}) async => Position(latitude: 0, longitude: 0);
}

class LocationPermission {
  static const LocationPermission always = LocationPermission._('always');
  static const LocationPermission whileInUse = LocationPermission._('whileInUse');
  static const LocationPermission denied = LocationPermission._('denied');
  static const LocationPermission deniedForever = LocationPermission._('deniedForever');
  static const LocationPermission unableToDetermine = LocationPermission._('unableToDetermine');
  const LocationPermission._(this.value);
  final String value;
}

class LocationAccuracy {
  static const LocationAccuracy best = LocationAccuracy._('best');
  const LocationAccuracy._(this.value);
  final String value;
}

class Position {
  final double latitude;
  final double longitude;
  Position({required this.latitude, required this.longitude});
}

// ── Flutter Local Notifications stubs ──
class FlutterLocalNotificationsPlugin {
  Future<void> initialize(InitializationSettings settings) async {}
  Future<void> show(int id, String? title, String? body, NotificationDetails details) async {}
  Future<void> cancel(int id) async {}
  Future<void> zonedSchedule(int id, String? title, String? body, tz2.TZDateTime scheduledDate, NotificationDetails details, {bool? androidAllowWhileIdle}) async {}
}

class InitializationSettings {
  InitializationSettings({AndroidInitializationSettings? android, IOSInitializationSettings? iOS});
}

class AndroidInitializationSettings {
  AndroidInitializationSettings(String icon);
}

class IOSInitializationSettings {}

class NotificationDetails {
  NotificationDetails({AndroidNotificationDetails? android, IOSNotificationDetails? iOS});
}

class AndroidNotificationDetails {
  AndroidNotificationDetails(String channelId, String channelName, {String? channelDescription, Importance? importance, Priority? priority});
}

class IOSNotificationDetails {}

class NotificationResponse {
  final String? payload;
  NotificationResponse({this.payload});
}

class AndroidNotificationAction {}

class PendingNotificationRequest {}

class Importance {
  static const Importance max = Importance._();
  const Importance._();
}

class Priority {
  static const Priority high = Priority._();
  const Priority._();
}

// ── Connectivity stubs ──
class Connectivity {
  static Future<ConnectivityResult> checkConnectivity() async => ConnectivityResult.wifi;
}

class ConnectivityResult {
  static const ConnectivityResult wifi = ConnectivityResult._('wifi');
  static const ConnectivityResult mobile = ConnectivityResult._('mobile');
  static const ConnectivityResult none = ConnectivityResult._('none');
  static const ConnectivityResult ethernet = ConnectivityResult._('ethernet');
  static const ConnectivityResult vpn = ConnectivityResult._('vpn');
  const ConnectivityResult._(this.value);
  final String value;
  bool contains(ConnectivityResult other) => this == other;
}

// ── PlatformAds stubs ──
class PlatformAds {
  static bool get isAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  static void initialize() {}
  static void loadRewardedAd() {}
  static void showRewardedAd() {}
  static void loadNativeAd() {}
  static void loadBannerAd() {}
  static void disposeBannerAd() {}
}
