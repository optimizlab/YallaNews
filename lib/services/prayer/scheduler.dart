import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import '../../models/prayer_times.dart';
import '../prayer/prayer_database.dart';
import 'adhan_audio_service.dart';

/// Configuration for a single prayer's reminder, read from SharedPreferences.
class PrayerReminderConfig {
  const PrayerReminderConfig({
    required this.enabled,
    required this.offsetMinutes,
    this.sound = true,
    this.adhanSound = false,
  });

  final bool enabled;
  final int offsetMinutes;
  final bool sound;
  final bool adhanSound;

  PrayerReminderConfig copyWith({
    bool? enabled,
    int? offsetMinutes,
    bool? sound,
    bool? adhanSound,
  }) {
    return PrayerReminderConfig(
      enabled: enabled ?? this.enabled,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      sound: sound ?? this.sound,
      adhanSound: adhanSound ?? this.adhanSound,
    );
  }
}

/// Native Android alarm scheduling for Athan prayer times.
///
/// Reads prayer times exclusively from the local database and schedules one
/// exact wake-up alarm per future, enabled prayer (one per date × prayer).
/// Alarms persist across device reboot because the native side persists each
/// alarm to SharedPreferences and [PrayerBootReceiver] restores them on boot.
///
/// Uses [flutter_local_notifications] for the heads-up notification and a
/// MethodChannel ('inoov.app.yallanews/prayer_alarm') for the native exact
/// alarm that launches [AdhanAudioService] even when the app is closed.
class AthanScheduler {
  AthanScheduler({
    FlutterLocalNotificationsPlugin? localNotifications,
    PrayerDatabase? database,
  })  : _localNotifications = localNotifications ?? FlutterLocalNotificationsPlugin(),
        _database = database ?? PrayerDatabase.instance,
        _alarmChannel = const MethodChannel('inoov.app.yallanews/prayer_alarm');

  static const String _channelId = 'athan_reminders';
  static const String _channelName = 'Athan Reminders';
  static const String _channelDescription = 'Islamic prayer time reminders';
  static const int _notificationBase = 2000;

  final FlutterLocalNotificationsPlugin _localNotifications;
  final PrayerDatabase _database;
  final MethodChannel _alarmChannel;

  bool _initialized = false;

  // User configuration (re-read on every scheduling pass).
  bool _notificationsEnabled = false;
  bool _adhanMaster = false;
  String _muezzin = 'makkah';
  final Map<Prayer, PrayerReminderConfig> _configs = {};

  String _timeZone = 'UTC';

  // Windows-only: timer-based adhan checking (desktop has no native alarms).
  Timer? _windowsPollTimer;
  String? _winCountrySlug;
  String? _winCitySlug;
  String? _winProvider;
  String? _winMethod;
  final Set<int> _triggeredToday = <int>{};
  DateTime _lastTriggerDate = DateTime.now();

  Future<bool> initialize() async {
    if (_initialized) return true;
    tz_data.initializeTimeZones();

    if (Platform.isAndroid || Platform.isIOS) {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      final success = await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      ) ?? false;

      if (Platform.isAndroid) {
        _createAndroidChannel();
      }

      _initialized = success;
      return success;
    }

    // Desktop (Windows): no native alarms/notifications. Use timer-based
    // prayer checking so the adhan still plays when a prayer time arrives.
    _initialized = true;
    return true;
  }

  void _createAndroidChannel() {
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );
    _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  void _onNotificationTapped(NotificationResponse details) {
    final payload = details.payload ?? '';
    if (payload.startsWith('adhan:')) {
      debugPrint('[AthanScheduler] Notification tapped: $payload');
    }
  }

  Future<bool> requestPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    final android =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final result = await android.requestNotificationsPermission();
      return result == true;
    }
    return false;
  }

  Future<bool> areNotificationsEnabled() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    final android =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final result = await android.areNotificationsEnabled();
      return result == true;
    }
    return true;
  }

  /// Read the latest user configuration from SharedPreferences. Called before
  /// every scheduling pass so setting changes take effect immediately.
  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _notificationsEnabled = prefs.getBool('prayer_notifications_enabled') ?? false;
    _adhanMaster = prefs.getBool('prayer_adhan_sound') ?? false;
    _muezzin = prefs.getString('adhan_muezzin') ?? 'makkah';
    _configs.clear();
    for (final p in kObligatoryPrayers) {
      _configs[p] = PrayerReminderConfig(
        enabled: prefs.getBool('prayer_${p.index}_enabled') ?? true,
        offsetMinutes: prefs.getInt('prayer_${p.index}_offset') ?? 0,
        sound: true,
        adhanSound:
            _adhanMaster && (prefs.getBool('prayer_${p.index}_adhan_sound') ?? false),
      );
    }
  }

  String _prayerTitle(Prayer prayer) {
    switch (prayer) {
      case Prayer.fajr:
        return 'Fajr';
      case Prayer.dhuhr:
        return 'Dhuhr';
      case Prayer.asr:
        return 'Asr';
      case Prayer.maghrib:
        return 'Maghrib';
      case Prayer.isha:
        return 'Isha';
      case Prayer.sunrise:
        return 'Sunrise';
    }
  }

  String _prayerBody(Prayer prayer, String formatted) {
    return '$prayer at $formatted';
  }

  AndroidNotificationDetails _buildAndroidDetails({
    required PrayerReminderConfig config,
    required String prayerName,
  }) {
    const stopAction = AndroidNotificationAction(
      'stop_adhan',
      'Stop Adhan',
    );
    return AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: config.sound,
      sound: config.sound
          ? const RawResourceAndroidNotificationSound('adhan')
          : null,
      fullScreenIntent: config.adhanSound,
      autoCancel: false,
      actions: <AndroidNotificationAction>[stopAction],
    );
  }

  /// Unique notification id per (date, prayer). Range 2000+.
  static int notificationId(DateTime localDate, Prayer prayer) {
    final dayOfYear = dayOfYearOf(localDate);
    return _notificationBase + (dayOfYear * 10) + prayer.index;
  }

  static int dayOfYearOf(DateTime date) {
    final startOfYear = DateTime(date.year);
    return date.difference(startOfYear).inDays + 1;
  }

  /// Unique native alarm request code per (date, prayer). Fits in a 32-bit
  /// int for any practical date range and is stable across reschedules so the
  /// native side can store/restore it across reboots.
  static int alarmRequestCode(DateTime localDate, Prayer prayer) {
    final daysSinceEpoch =
        localDate.difference(DateTime(2020, 1, 1)).inDays;
    return daysSinceEpoch * 10 + prayer.index;
  }

  /// Schedule every future, enabled prayer from the two required months
  /// (active month N and next month N+1) stored in the local database.
  ///
  /// Cancels all previously scheduled notifications and native alarms first,
  /// so there are never duplicate alarms or duplicate playback.
  Future<void> scheduleAllPrayers({
    required String countrySlug,
    required String citySlug,
    required String provider,
    required String method,
  }) async {
    await _loadConfig();

    // Remember city info for the Windows timer-based checker.
    _winCountrySlug = countrySlug;
    _winCitySlug = citySlug;
    _winProvider = provider;
    _winMethod = method;

    if (Platform.isWindows) {
      if (!_adhanMaster) {
        await cancelAll();
        return;
      }
      _startWindowsPrayerChecker();
      return;
    }

    if (!_notificationsEnabled) {
      await cancelAll();
      return;
    }

    final systemEnabled = await areNotificationsEnabled();
    if (!systemEnabled) {
      await cancelAll();
      return;
    }

    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return;
    }

    await cancelAll();

    final now = DateTime.now().toUtc();
    final months = <(int year, int month)>[
      (now.year, now.month),
      _nextMonth(now),
    ];

    for (final (year, month) in months) {
      final monthTimes = await _database.getMonthPrayerTimes(
        countrySlug: countrySlug,
        citySlug: citySlug,
        year: year,
        month: month,
        provider: provider,
        method: method,
      );

      final tzLocation = tz.getLocation(_timeZone);

      for (final times in monthTimes) {
        for (final prayer in kObligatoryPrayers) {
          final config = _configs[prayer];
          if (config == null || !config.enabled) continue;
          final prayerTime = times.times[prayer];
          if (prayerTime == null) continue;

          final targetUtc = prayerTime.utcTime.add(
            Duration(minutes: config.offsetMinutes),
          );

          // Skip prayers that have already passed.
          if (targetUtc.isBefore(now)) continue;

          final prayerName = _prayerTitle(prayer);
          final tzTarget = tz.TZDateTime.from(targetUtc, tzLocation);

          final androidDetails = _buildAndroidDetails(
            config: config,
            prayerName: prayerName,
          );
          final iosDetails = DarwinNotificationDetails(
            sound: 'adhan.caf',
            presentAlert: true,
            presentSound: true,
          );
          final details = NotificationDetails(
            android: androidDetails,
            iOS: iosDetails,
          );

          final id = notificationId(times.localDate, prayer);

          await _localNotifications.zonedSchedule(
            id,
            prayerName,
            '${_prayerBody(prayer, prayerTime.formatted)} - ${DateFormat.MMMd().format(times.localDate)}',
            tzTarget,
            details,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: config.adhanSound ? 'adhan:${prayer.name}' : null,
          );

          // Native exact alarm so the adhan plays natively even when the app
          // is closed. Only when adhan audio is enabled for this prayer.
          if (Platform.isAndroid && config.adhanSound) {
            try {
              await _alarmChannel.invokeMethod(
                'schedulePrayerAlarm',
                <String, dynamic>{
                  'prayerTimeMillis': targetUtc.millisecondsSinceEpoch,
                  'prayerName': prayerName,
                  'muezzin': _muezzin,
                  'requestCode': alarmRequestCode(times.localDate, prayer),
                },
              );
            } catch (e) {
              debugPrint(
                  '[AthanScheduler] Failed to set native alarm: $e');
            }
          }
        }
      }
    }

    debugPrint(
        '[AthanScheduler] Scheduled prayers for $countrySlug/$citySlug $provider/$method');
  }

  /// Start polling for prayer times on Windows (desktop has no native alarms).
  void _startWindowsPrayerChecker() {
    _windowsPollTimer?.cancel();
    _windowsPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_checkWindowsPrayerTimes());
    });
    // Check immediately in case a prayer time is already current.
    unawaited(_checkWindowsPrayerTimes());
  }

  /// Check today's prayer times and play the adhan when a scheduled time
  /// arrives (within the polling window). Runs on Windows only.
  Future<void> _checkWindowsPrayerTimes() async {
    if (!_adhanMaster) return;

    final now = DateTime.now().toUtc();
    final todayLocal = DateTime.now();
    final today = DateTime(todayLocal.year, todayLocal.month, todayLocal.day);

    // Reset the triggered set at the start of a new local day.
    if (_lastTriggerDate.day != todayLocal.day ||
        _lastTriggerDate.month != todayLocal.month ||
        _lastTriggerDate.year != todayLocal.year) {
      _triggeredToday.clear();
      _lastTriggerDate = todayLocal;
    }

    final slug = _winCountrySlug;
    final city = _winCitySlug;
    final prov = _winProvider;
    final meth = _winMethod;
    if (slug == null || city == null || prov == null || meth == null) return;

    final times = await _database.getTimesForDate(
      countrySlug: slug,
      citySlug: city,
      localDate: today,
      provider: prov,
      method: meth,
    );
    if (times == null) return;

    for (final prayer in kObligatoryPrayers) {
      final config = _configs[prayer];
      if (config == null || !config.enabled || !config.adhanSound) continue;
      final prayerTime = times.times[prayer];
      if (prayerTime == null) continue;

      final targetUtc = prayerTime.utcTime.add(
        Duration(minutes: config.offsetMinutes),
      );

      // Trigger when the prayer time is now (within the polling window).
      final diff = now.difference(targetUtc);
      if (diff.inSeconds < 0 || diff.inSeconds > 30) continue;

      final id = notificationId(times.localDate, prayer);
      if (_triggeredToday.contains(id)) continue;
      _triggeredToday.add(id);

      debugPrint(
          '[AthanScheduler] Windows adhan trigger: $prayer at ${prayerTime.formatted}');
      await AdhanAudioService.instance.playAdhan(muezzin: _muezzin);
    }
  }

  /// Cancel all Athan notifications and native alarms. Used before every
  /// reschedule to prevent duplicates, and when notifications are disabled.
  Future<void> cancelAll() async {
    _windowsPollTimer?.cancel();
    _windowsPollTimer = null;
    _triggeredToday.clear();

    // Cancel the full notification id range used by this scheduler.
    for (var id = _notificationBase;
        id < _notificationBase + 366 * 10 + 6;
        id++) {
      await _localNotifications.cancel(id);
    }
    if (Platform.isAndroid) {
      try {
        await _alarmChannel.invokeMethod('cancelAllPrayerAlarms', {});
      } catch (_) {}
    }
    debugPrint('[AthanScheduler] All Athan alarms cancelled');
  }

  /// Pending native/Dart notifications (useful for debugging/tests).
  Future<List<PendingNotificationRequest>> pendingNotifications() async {
    return await _localNotifications.pendingNotificationRequests();
  }

  (int year, int month) _nextMonth(DateTime d) {
    if (d.month == 12) return (d.year + 1, 1);
    return (d.year, d.month + 1);
  }

  void setTimeZone(String timeZone) {
    _timeZone = timeZone;
  }

  void dispose() {}
}
