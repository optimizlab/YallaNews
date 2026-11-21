import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import '../../models/prayer_times.dart';

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
  /// When true, play the embedded adhan audio for ~30s at prayer time,
  /// even when the app is closed (via a foreground audio service).
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

class PrayerNotificationScheduler {
  PrayerNotificationScheduler({
    FlutterLocalNotificationsPlugin? localNotifications,
    String? timeZone,
  })  : _localNotifications =
            localNotifications ?? FlutterLocalNotificationsPlugin(),
        _timeZone = timeZone ?? 'UTC',
        _alarmChannel = const MethodChannel('inoov.app.yallanews/prayer_alarm');

  final FlutterLocalNotificationsPlugin _localNotifications;
  final MethodChannel _alarmChannel;
  String _timeZone;
  bool _initialized = false;

  static const String _channelId = 'prayer_reminders';
  static const String _channelName = 'Prayer Times Reminders';
  static const String _channelDescription = 'Islamic prayer time notifications';

  static int _notificationId(Prayer prayer) => 1000 + prayer.index;

  void setTimeZone(String timeZone) {
    _timeZone = timeZone;
  }

  Future<bool> initialize() async {
    if (_initialized) return true;
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    tz_data.initializeTimeZones();

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
      // User tapped the prayer notification; open the app (handled by Flutter).
      // The adhan audio is already playing natively via the alarm trigger.
      debugPrint('[PrayerNotificationScheduler] Notification tapped: $payload');
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

  /// Build Android notification details with a "Stop Adhan" action button.
  AndroidNotificationDetails _buildAndroidDetails({
    required PrayerReminderConfig config,
    required String prayerName,
  }) {
    // Stop action: sends broadcast to PrayerNotificationReceiver which stops the adhan service.
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
      // Full-screen (heads-up) intent so the notification wakes the device
      // and the adhan audio can start even when the app is closed/hidden.
      fullScreenIntent: config.adhanSound,
      autoCancel: false,
      actions: <AndroidNotificationAction>[stopAction],
    );
  }

  /// Schedule a single prayer notification AND a native exact alarm.
  /// The native alarm triggers [PrayerNotificationReceiver] which starts
  /// [AdhanAudioService] to play the adhan even when the app is closed.
  Future<void> _scheduleOne({
    required Prayer prayer,
    required PrayerTime prayerTime,
    required DateTime targetUtc,
    required PrayerReminderConfig config,
    required String muezzin,
  }) async {
    final tzLocation = tz.getLocation(_timeZone);
    final tzTarget = tz.TZDateTime.from(targetUtc, tzLocation);

    final androidDetails = _buildAndroidDetails(
      config: config,
      prayerName: _prayerTitle(prayer),
    );

    const iosDetails = DarwinNotificationDetails(
      sound: 'adhan.caf',
      presentAlert: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.zonedSchedule(
      _notificationId(prayer),
      _prayerTitle(prayer),
      _prayerBody(prayer, prayerTime.formatted),
      tzTarget,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: config.adhanSound ? 'adhan:${prayer.name}' : null,
    );

    // Also set a native exact alarm so the adhan plays even when the app is closed.
    if (Platform.isAndroid && config.adhanSound) {
      try {
        await _alarmChannel.invokeMethod('schedulePrayerAlarm', <String, dynamic>{
          'prayerTimeMillis': targetUtc.millisecondsSinceEpoch,
          'prayerName': _prayerTitle(prayer),
          'muezzin': muezzin,
        });
      } catch (e) {
        debugPrint('[PrayerNotificationScheduler] Failed to set native alarm: $e');
      }
    }
  }

  /// Schedule daily prayer notifications for [times].
  Future<void> schedulePrayers(
    PrayerTimes times, {
    required Map<Prayer, PrayerReminderConfig> configs,
    required String muezzin,
  }) async {
    if (!_initialized) await initialize();
    await cancelAll();

    final now = DateTime.now();
    for (final prayer in kObligatoryPrayers) {
      final config = configs[prayer];
      if (config == null || !config.enabled) continue;
      final prayerTime = times.times[prayer];
      if (prayerTime == null) continue;

      final targetUtc = prayerTime.utcTime.add(
        Duration(minutes: config.offsetMinutes),
      );

      if (targetUtc.isBefore(now.toUtc())) continue;

      await _scheduleOne(
        prayer: prayer,
        prayerTime: prayerTime,
        targetUtc: targetUtc,
        config: config,
        muezzin: muezzin,
      );
    }
  }

  Future<void> cancelAll() async {
    for (final prayer in kObligatoryPrayers) {
      await _localNotifications.cancel(_notificationId(prayer));
    }
    if (Platform.isAndroid) {
      try {
        await _alarmChannel.invokeMethod('cancelAllPrayerAlarms', {});
      } catch (_) {}
    }
  }

  /// Schedule notifications for every obligatory prayer of every day in a
  /// [PrayerTimes] list (e.g. a full month). Each notification fires once at
  /// its exact date/time rather than repeating daily.
  ///
  /// Uses notification ID range 2000+ to avoid collisions with the daily
  /// scheduler (1000+).
  Future<void> scheduleMonth(
    List<PrayerTimes> monthTimes, {
    required Map<Prayer, PrayerReminderConfig> configs,
    required String muezzin,
  }) async {
    if (!_initialized) await initialize();
    await cancelMonth();

    final now = DateTime.now();
    for (final times in monthTimes) {
      final tzLocation = tz.getLocation(times.timeZone);
      for (final prayer in kObligatoryPrayers) {
        final config = configs[prayer];
        if (config == null || !config.enabled) continue;
        final prayerTime = times.times[prayer];
        if (prayerTime == null) continue;

        final targetUtc = prayerTime.utcTime.add(
          Duration(minutes: config.offsetMinutes),
        );

        // Skip prayers that have already passed.
        if (targetUtc.isBefore(now.toUtc())) continue;

        final id = _monthNotificationId(times.localDate, prayer);
        final tzTarget = tz.TZDateTime.from(targetUtc, tzLocation);

        final androidDetails = _buildAndroidDetails(
          config: config,
          prayerName: _prayerTitle(prayer),
        );

        const iosDetails = DarwinNotificationDetails(
          sound: 'adhan.caf',
          presentAlert: true,
          presentSound: true,
        );

        final details = NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        );

        await _localNotifications.zonedSchedule(
          id,
          _prayerTitle(prayer),
          '${_prayerBody(prayer, prayerTime.formatted)} - ${DateFormat.MMMd().format(times.localDate)}',
          tzTarget,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: config.adhanSound ? 'adhan:${prayer.name}' : null,
        );

        // Native alarm for background playback.
        if (Platform.isAndroid && config.adhanSound) {
          try {
            await _alarmChannel.invokeMethod('schedulePrayerAlarm', <String, dynamic>{
              'prayerTimeMillis': targetUtc.millisecondsSinceEpoch,
              'prayerName': _prayerTitle(prayer),
              'muezzin': muezzin,
            });
          } catch (e) {
            debugPrint('[PrayerNotificationScheduler] Failed to set native alarm: $e');
          }
        }
      }
    }
  }

  int _monthNotificationId(DateTime localDate, Prayer prayer) {
    // Day of year (1-366) * 10 + prayer index (0-5), offset by 2000.
    final dayOfYear = _dayOfYear(localDate);
    return 2000 + (dayOfYear * 10) + prayer.index;
  }

  int _dayOfYear(DateTime date) {
    final startOfYear = DateTime(date.year);
    return date.difference(startOfYear).inDays + 1;
  }

  /// Cancel all monthly notifications (ID range 2000+).
  Future<void> cancelMonth() async {
    // Cancel a reasonable range covering all days of a year.
    for (var id = 2000; id < 2000 + 366 * 10 + 6; id++) {
      await _localNotifications.cancel(id);
    }
    if (Platform.isAndroid) {
      try {
        await _alarmChannel.invokeMethod('cancelAllPrayerAlarms', {});
      } catch (_) {}
    }
  }

  /// Schedule notifications for every obligatory prayer of every day in a
  /// full year of [PrayerTimes]. Each notification fires once at its exact
  /// date/time rather than repeating daily.
  ///
  /// Uses notification ID range 2000+ (same as month scheduler) so a year
  /// replaces any previously scheduled month/year notifications.
  Future<void> scheduleYear(
    List<PrayerTimes> yearTimes, {
    required Map<Prayer, PrayerReminderConfig> configs,
    required String muezzin,
  }) async {
    if (!_initialized) await initialize();
    await cancelYear();

    final now = DateTime.now();
    for (final times in yearTimes) {
      final tzLocation = tz.getLocation(times.timeZone);
      for (final prayer in kObligatoryPrayers) {
        final config = configs[prayer];
        if (config == null || !config.enabled) continue;
        final prayerTime = times.times[prayer];
        if (prayerTime == null) continue;

        final targetUtc = prayerTime.utcTime.add(
          Duration(minutes: config.offsetMinutes),
        );

        // Skip prayers that have already passed.
        if (targetUtc.isBefore(now.toUtc())) continue;

        final id = _monthNotificationId(times.localDate, prayer);
        final tzTarget = tz.TZDateTime.from(targetUtc, tzLocation);

        final androidDetails = _buildAndroidDetails(
          config: config,
          prayerName: _prayerTitle(prayer),
        );

        const iosDetails = DarwinNotificationDetails(
          sound: 'adhan.caf',
          presentAlert: true,
          presentSound: true,
        );

        final details = NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        );

        await _localNotifications.zonedSchedule(
          id,
          _prayerTitle(prayer),
          '${_prayerBody(prayer, prayerTime.formatted)} - ${DateFormat.yMMMd().format(times.localDate)}',
          tzTarget,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: config.adhanSound ? 'adhan:${prayer.name}' : null,
        );

        // Native alarm for background playback.
        if (Platform.isAndroid && config.adhanSound) {
          try {
            await _alarmChannel.invokeMethod('schedulePrayerAlarm', <String, dynamic>{
              'prayerTimeMillis': targetUtc.millisecondsSinceEpoch,
              'prayerName': _prayerTitle(prayer),
              'muezzin': muezzin,
            });
          } catch (e) {
            debugPrint('[PrayerNotificationScheduler] Failed to set native alarm: $e');
          }
        }
      }
    }
  }

  /// Cancel all year notifications (ID range 2000+).
  Future<void> cancelYear() async {
    // Cancel a reasonable range covering all days of a year.
    for (var id = 2000; id < 2000 + 366 * 10 + 6; id++) {
      await _localNotifications.cancel(id);
    }
    if (Platform.isAndroid) {
      try {
        await _alarmChannel.invokeMethod('cancelAllPrayerAlarms', {});
      } catch (_) {}
    }
  }

  Future<List<PendingNotificationRequest>> pendingNotifications() async {
    return await _localNotifications.pendingNotificationRequests();
  }

  void dispose() {}
}
