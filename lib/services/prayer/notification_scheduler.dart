
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import '../../models/prayer_times.dart';
import 'adhan_audio_service.dart';

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
        _timeZone = timeZone ?? 'UTC';

  final FlutterLocalNotificationsPlugin _localNotifications;
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
      unawaited(AdhanAudioService.instance.playAdhan());
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

  Future<void> schedulePrayers(PrayerTimes times,
      {required Map<Prayer, PrayerReminderConfig> configs}) async {
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

  Future<void> cancelAll() async {
    for (final prayer in kObligatoryPrayers) {
      await _localNotifications.cancel(_notificationId(prayer));
    }
  }

  Future<void> _scheduleOne({
    required Prayer prayer,
    required PrayerTime prayerTime,
    required DateTime targetUtc,
    required PrayerReminderConfig config,
  }) async {
    final tzLocation = tz.getLocation(_timeZone);
    final tzTarget = tz.TZDateTime.from(targetUtc, tzLocation);

    final androidDetails = AndroidNotificationDetails(
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
      autoCancel: true,
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
  }

  Future<void> cancelPrayer(Prayer prayer) async {
    await _localNotifications.cancel(_notificationId(prayer));
  }

  Future<List<PendingNotificationRequest>> pendingNotifications() async {
    return await _localNotifications.pendingNotificationRequests();
  }

  void dispose() {}
}
