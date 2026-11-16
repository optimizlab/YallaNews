
import 'dart:async';
import 'package:timezone/timezone.dart' as tz;

import '../../models/prayer_times.dart';
import 'adhan_service.dart';

/// Result of next-prayer calculation.
class NextPrayerInfo {
  const NextPrayerInfo({
    required this.prayer,
    required this.time,
    required this.utcTime,
    required this.remaining,
    required this.isPast,
    this.isTomorrow = false,
  });

  final Prayer prayer;
  final DateTime time;
  final DateTime utcTime;
  final Duration remaining;
  final bool isPast;
  final bool isTomorrow;

  String get formattedRemaining {
    final total = remaining.inSeconds;
    if (total <= 0) return '00:00:00';
    final h = (total ~/ 3600).toString().padLeft(2, '0');
    final m = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class CountdownEngine {
  CountdownEngine({
    PrayerTimes? prayerTimes,
    this.tickInterval = const Duration(seconds: 1),
  }) : _prayerTimes = prayerTimes;

  final Duration tickInterval;
  PrayerTimes? _prayerTimes;

  Timer? _timer;
  final _listeners = <VoidCallback>{};

  bool get isRunning => _timer != null;

  PrayerTimes? get prayerTimes => _prayerTimes;

  NextPrayerInfo get nextPrayer => nextPrayerAt(DateTime.now());

  // Track the last remaining to detect crossing zero
  Duration _lastRemaining = const Duration(hours: 999);

  /// Calculate the next prayer at a specific [now] instant. Useful for testing.
  NextPrayerInfo nextPrayerAt(DateTime now) {
    if (_prayerTimes == null) {
      return NextPrayerInfo(
        prayer: Prayer.fajr,
        time: now,
        utcTime: now.toUtc(),
        remaining: Duration.zero,
        isPast: true,
      );
    }
    return _calculateNextPrayer(_prayerTimes!, now);
  }

  void updateTimes(PrayerTimes newTimes) {
    _prayerTimes = newTimes;
    for (final cb in _listeners) {
      cb();
    }
  }

  void start({VoidCallback? onTick}) {
    stop();
    if (onTick != null) _listeners.add(onTick);
    _timer = Timer.periodic(tickInterval, (_) {
      _checkPrayerArrival();
      for (final cb in _listeners) {
        cb();
      }
    });
  }

  /// Fires AdhanService when prayer time is reached (remaining crosses zero).
  void _checkPrayerArrival() {
    if (_prayerTimes == null) return;
    final info = nextPrayerAt(DateTime.now());
    final wasPositive = _lastRemaining.inSeconds > 0;
    final isNowZeroOrNeg = info.remaining.inSeconds <= 0;
    if (wasPositive && isNowZeroOrNeg) {
      AdhanService.instance.playAdhan();
    }
    _lastRemaining = info.remaining;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void addListener(VoidCallback callback) {
    _listeners.add(callback);
  }

  void removeListener(VoidCallback callback) {
    _listeners.remove(callback);
  }

  void dispose() {
    stop();
    _listeners.clear();
  }

  NextPrayerInfo _calculateNextPrayer(PrayerTimes times, DateTime now) {
    final next = times.nextPrayer(now);
    if (next == null) {
      return NextPrayerInfo(
        prayer: Prayer.fajr,
        time: now,
        utcTime: now.toUtc(),
        remaining: Duration.zero,
        isPast: true,
      );
    }
    final remaining = times.countdownTo(next.prayer, now) ?? Duration.zero;

    // Determine if the next prayer is tomorrow by comparing city-local dates.
    final nowCity = _toCityTime(now, times.timeZone);
    final isTomorrow =
        next.localTime.day != nowCity.day ||
        next.localTime.month != nowCity.month ||
        next.localTime.year != nowCity.year;

    return NextPrayerInfo(
      prayer: next.prayer,
      time: next.localTime,
      utcTime: next.utcTime,
      remaining: remaining,
      isPast: remaining.isNegative,
      isTomorrow: isTomorrow,
    );
  }
}

typedef VoidCallback = void Function();

/// Convert a UTC [DateTime] to the given IANA [timeZone], returning a local
/// [DateTime] in that timezone. Handles DST automatically.
DateTime _toCityTime(DateTime utcTime, String timeZone) {
  try {
    final location = tz.getLocation(timeZone);
    final tzDate = tz.TZDateTime.from(utcTime.toUtc(), location);
    return DateTime(
      tzDate.year,
      tzDate.month,
      tzDate.day,
      tzDate.hour,
      tzDate.minute,
      tzDate.second,
    );
  } catch (_) {
    return utcTime.toLocal();
  }
}
