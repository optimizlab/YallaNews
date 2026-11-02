import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/news_model.dart';
import 'app_settings.dart';
import 'server_api_service.dart';

/// In-app user behavior analytics.
///
/// Collects real usage events (article opens, read progress, likes, saves,
/// shares, comments, searches, screen views...) and ships them in batches to
/// `api/stats/event.php` so the admin dashboard shows real, live data.
///
/// Events are queued locally (SharedPreferences) so nothing is lost when the
/// device is offline; the queue is flushed periodically and on app background.
class AnalyticsService {
  AnalyticsService._internal();
  static final AnalyticsService instance = AnalyticsService._internal();

  static const String _queueKey = 'yn_analytics_queue';
  static const String _installedKey = 'yn_analytics_installed';
  static const int _maxQueue = 500;
  static const int _flushIntervalSeconds = 30;
  static const int _flushAtEvents = 15;

  final List<Map<String, dynamic>> _queue = [];
  Timer? _flushTimer;
  bool _initialized = false;
  bool _flushing = false;
  bool _enabled = true;

  bool get isEnabled => _enabled;
  int get pendingEvents => _queue.length;

  /// Load any queued events persisted by a previous run.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('yn_analytics_enabled') ?? true;
      final raw = prefs.getString(_queueKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map) _queue.add(Map<String, dynamic>.from(e));
          }
        }
      }
      // Stamp install-time once so "total installs" survives app restarts
      final alreadyStamped = prefs.getBool(_installedKey) ?? false;
      if (!alreadyStamped) {
        await prefs.setBool(_installedKey, true);
        track('app_open', metadata: {'first_launch': true});
      } else {
        track('app_open');
      }
      // Persist + schedule flushes
      await _persist();
      _flushTimer?.cancel();
      _flushTimer = Timer.periodic(
        const Duration(seconds: _flushIntervalSeconds),
        (_) => flush(),
      );
    } catch (_) {}
  }

  /// Opt-in/opt-out of analytics collection (respects user preference).
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (!value) {
      _queue.clear();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_queueKey);
      } catch (_) {}
    }
    if (value) flush();
  }

  // ─── Event helpers ─────────────────────────────────────────────────────────

  /// Queue a single event. Cheap, synchronous, never throws.
  void track(
    String type, {
    String? articleId,
    String? articleTitle,
    String? category,
    int durationMs = 0,
    Map<String, dynamic>? metadata,
  }) {
    if (!_enabled) return;
    try {
      final event = <String, dynamic>{
        'type': type,
        'ts': DateTime.now().millisecondsSinceEpoch,
        if (articleId != null) 'articleId': articleId,
        if (articleTitle != null) 'articleTitle': articleTitle,
        if (category != null) 'category': category,
        if (durationMs > 0) 'durationMs': durationMs,
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      };
      _queue.add(event);
      if (_queue.length > _maxQueue) {
        _queue.removeRange(0, _queue.length - _maxQueue);
      }
      if (_queue.length >= _flushAtEvents) {
        flush();
      } else {
        _persist();
      }
    } catch (_) {}
  }

  // ─── Convenience API ───────────────────────────────────────────────────────

  void trackAppOpen() => track('app_open');

  void trackArticleOpen(NewsModel article) => track(
        'article_open',
        articleId: article.url,
        articleTitle: article.title,
        category: article.category,
      );

  void trackArticleRead(NewsModel article, {required int durationMs, double? scrollDepth}) =>
      track(
        'article_read',
        articleId: article.url,
        articleTitle: article.title,
        category: article.category,
        durationMs: durationMs,
        metadata: scrollDepth != null ? {'scrollDepth': scrollDepth} : null,
      );

  void trackLike(NewsModel article) => track(
        'like',
        articleId: article.url,
        articleTitle: article.title,
        category: article.category,
      );

  void trackUnlike(NewsModel article) => track(
        'unlike',
        articleId: article.url,
        articleTitle: article.title,
        category: article.category,
      );

  void trackSave(NewsModel article) => track(
        'save',
        articleId: article.url,
        articleTitle: article.title,
        category: article.category,
      );

  void trackUnsave(NewsModel article) => track(
        'unsave',
        articleId: article.url,
        articleTitle: article.title,
        category: article.category,
      );

  void trackShare(NewsModel article) => track(
        'share',
        articleId: article.url,
        articleTitle: article.title,
        category: article.category,
      );

  void trackComment(NewsModel article) => track(
        'comment',
        articleId: article.url,
        articleTitle: article.title,
        category: article.category,
      );

  void trackSearch(String term) {
    final q = term.trim();
    if (q.length < 2) return;
    track('search', metadata: {'term': q});
  }

  void trackCategoryView(String categoryId) => track(
        'category_view',
        category: categoryId,
      );

  void trackScreen(String name) => track('screen_view', metadata: {'screen': name});

  void trackTtsPlay(NewsModel article) => track(
        'tts_play',
        articleId: article.url,
        articleTitle: article.title,
        category: article.category,
      );

  // ─── Shipping ──────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_queue.isEmpty) {
        await prefs.remove(_queueKey);
      } else {
        await prefs.setString(_queueKey, jsonEncode(_queue));
      }
    } catch (_) {}
  }

  /// Send queued events to the server. Safe to call often; a flush is a no-op
  /// when the queue is empty or a flush is already in flight. Events are kept
  /// in the queue when the request fails and retried later.
  Future<void> flush() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    List<Map<String, dynamic>>? batch;
    try {
      // Snapshot and clear so concurrent tracks keep accumulating
      batch = List<Map<String, dynamic>>.from(_queue);
      _queue.clear();
      await _persist();

      String countryCode = 'EG';
      try {
        countryCode = AppSettings.instance.countryCode.isNotEmpty
            ? AppSettings.instance.countryCode
            : Platform.localeName.split(RegExp('[-_]')).last.toUpperCase();
      } catch (_) {}

      String? userId;
      try {
        final user = await ServerApiService.getSavedUser();
        userId = user?['id']?.toString();
      } catch (_) {}

      await ServerApiService.postJson('stats/event.php', {
        'sessionId': ServerApiService.sessionId,
        'userId': userId,
        'deviceOs': _deviceOs(),
        'appVersion': '1.0.0',
        'countryCode': countryCode,
        'events': batch,
      });
    } catch (_) {
      // Offline or server error: restore the batch for retry on next flush
      if (batch != null && batch.isNotEmpty) {
        final restored = List<Map<String, dynamic>>.from(batch);
        restored.addAll(_queue);
        _queue
          ..clear()
          ..addAll(restored);
      }
      await _persist();
    } finally {
      _flushing = false;
    }
  }

  static String _deviceOs() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// Called when the app goes to background: flush immediately.
  void onAppPaused() => flush();

  void dispose() {
    _flushTimer?.cancel();
    flush();
  }
}
