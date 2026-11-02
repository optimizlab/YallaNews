import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._internal();
  static final AppSettings instance = AppSettings._internal();

  static const String _keyThemeMode = 'theme_mode';
  static const String _keyLocale = 'locale';
  static const String _keyCountryCode = 'country_code';

  static const String _keyTopSourcesCount = 'top_sources_count';
  static const String _keyMaxUrlsPerSource = 'max_urls_per_source';
  static const String _keyFirstRunCompleted = 'first_run_completed';
  static const String _keyBackgroundCrawlerEnabled = 'background_crawler_enabled';

  /// News & Magazines freshness configuration.
  /// Current-events (breaking/urgent) articles must be no older than this many days.
  static const String _keyFreshnessCurrentEventsDays = 'freshness_current_events_days';
  /// Other news and magazine content must be no older than this many months.
  static const String _keyFreshnessGeneralMonths = 'freshness_general_months';

  static const int defaultFreshnessCurrentEventsDays = 30;
  static const int defaultFreshnessGeneralMonths = 3;

  static const ThemeMode defaultThemeMode = ThemeMode.system;  static const Locale defaultLocale = Locale('ar');

  static const int defaultTopSourcesCount = 5;
  static const int defaultMaxUrlsPerSource = 30;

  ThemeMode _themeMode = defaultThemeMode;
  Locale? _locale = defaultLocale;
  String _countryCode = '';
  bool _initialized = false;

  ThemeMode get themeMode => _themeMode;
  Locale? get locale => _locale;
  String get countryCode => _countryCode;
  bool get initialized => _initialized;

  Future<SharedPreferences> get _prefs async =>
      await SharedPreferences.getInstance();

  Future<SharedPreferences> getPrefs() async => await _prefs;

  Future<bool> isBackgroundCrawlerEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_keyBackgroundCrawlerEnabled) ?? true;
  }

  Future<void> setBackgroundCrawlerEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_keyBackgroundCrawlerEnabled, enabled);
  }

  Future<void> loadSettings() async {
    final prefs = await _prefs;
    final themeModeIndex = prefs.getInt(_keyThemeMode) ?? defaultThemeMode.index;
    _themeMode = ThemeMode.values[themeModeIndex];

    final localeString = prefs.getString(_keyLocale);
    if (localeString != null) {
      final parts = localeString.split('_');
      _locale = Locale(parts.first, parts.length > 1 ? parts.last : null);
    } else {
      _locale = defaultLocale;
    }

    _countryCode = prefs.getString(_keyCountryCode) ?? '';

    _initialized = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await _prefs;
    await prefs.setInt(_keyThemeMode, mode.index);
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    final prefs = await _prefs;
    await prefs.setString(_keyLocale, locale.toLanguageTag());
    notifyListeners();
  }

  Future<void> setCountryCode(String countryCode) async {
    _countryCode = countryCode;
    final prefs = await _prefs;
    await prefs.setString(_keyCountryCode, countryCode);
    notifyListeners();
  }

  Future<int> getTopSourcesCount() async {
    final prefs = await _prefs;
    return prefs.getInt(_keyTopSourcesCount) ?? defaultTopSourcesCount;
  }

  Future<void> setTopSourcesCount(int value) async {
    final prefs = await _prefs;
    await prefs.setInt(_keyTopSourcesCount, value);
  }

  Future<int> getMaxUrlsPerSource() async {
    final prefs = await _prefs;
    return prefs.getInt(_keyMaxUrlsPerSource) ?? defaultMaxUrlsPerSource;
  }

  Future<void> setMaxUrlsPerSource(int value) async {
    final prefs = await _prefs;
    await prefs.setInt(_keyMaxUrlsPerSource, value);
  }

  Future<bool> isFirstRun() async {
    final prefs = await _prefs;
    return prefs.getBool(_keyFirstRunCompleted) != true;
  }

  Future<void> completeFirstRun() async {
    final prefs = await _prefs;
    await prefs.setBool(_keyFirstRunCompleted, true);
  }

  // ─── News & Magazines freshness thresholds ──────────────────────────
  // Current-events (breaking/urgent) articles: max 30 days old.
  // Other news/magazine content: max 3 months old.
  // Values are stored in SharedPreferences so the publisher can tune them
  // without a release; never use the import/crawler date as publication date.

  Future<int> getFreshnessCurrentEventsDays() async {
    final prefs = await _prefs;
    return prefs.getInt(_keyFreshnessCurrentEventsDays) ?? defaultFreshnessCurrentEventsDays;
  }

  Future<void> setFreshnessCurrentEventsDays(int value) async {
    final prefs = await _prefs;
    await prefs.setInt(_keyFreshnessCurrentEventsDays, value);
  }

  Future<int> getFreshnessGeneralMonths() async {
    final prefs = await _prefs;
    return prefs.getInt(_keyFreshnessGeneralMonths) ?? defaultFreshnessGeneralMonths;
  }

  Future<void> setFreshnessGeneralMonths(int value) async {
    final prefs = await _prefs;
    await prefs.setInt(_keyFreshnessGeneralMonths, value);
  }
}