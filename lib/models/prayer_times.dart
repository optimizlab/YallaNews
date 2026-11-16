
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

/// The five obligatory prayers plus sunrise (which is not a prayer).
enum Prayer { fajr, sunrise, dhuhr, asr, maghrib, isha }

/// Obligatory prayers that carry an adhan / notification. Sunrise is excluded.
const List<Prayer> kObligatoryPrayers = <Prayer>[
  Prayer.fajr,
  Prayer.dhuhr,
  Prayer.asr,
  Prayer.maghrib,
  Prayer.isha,
];

/// Localization key used to render a prayer's name in the current app language.
String prayerLabelKey(Prayer prayer) {
  switch (prayer) {
    case Prayer.fajr:
      return 'prayerFajr';
    case Prayer.sunrise:
      return 'prayerSunrise';
    case Prayer.dhuhr:
      return 'prayerDhuhr';
    case Prayer.asr:
      return 'prayerAsr';
    case Prayer.maghrib:
      return 'prayerMaghrib';
    case Prayer.isha:
      return 'prayerIsha';
  }
}

/// One prayer time, carrying a single UTC instant converted to the city's
/// local time exactly once.
class PrayerTime {
  const PrayerTime({
    required this.prayer,
    required this.utcTime,
    required this.localTime,
    required this.formatted,
  });

  final Prayer prayer;
  /// True UTC instant, used for countdowns and scheduling.
  final DateTime utcTime;
  /// City-local time derived from [utcTime] via the IANA timezone exactly once.
  final DateTime localTime;
  /// Already-localized, human-readable time string.
  final String formatted;

  bool get isObligatory => kObligatoryPrayers.contains(prayer);
}

/// Normalized prayer times for one city, date, provider and calculation method.
class PrayerTimes {
  const PrayerTimes({
    required this.countryIso,
    required this.countrySlug,
    required this.countryName,
    required this.cityName,
    required this.citySlug,
    this.latitude,
    this.longitude,
    required this.timeZone,
    required this.localDate,
    required this.hijriDate,
    required this.isRamadan,
    required this.times,
    required this.provider,
    required this.method,
    required this.lastSynced,
    this.fromCache = false,
  });

  /// ISO country code (e.g. "MA").
  final String countryIso;
  /// Stable Waqtazan country slug (never changes with locale).
  final String countrySlug;
  /// Localized country name.
  final String countryName;
  /// Localized city name.
  final String cityName;
  /// Stable city slug.
  final String citySlug;
  /// Coordinates when available.
  final double? latitude;
  final double? longitude;
  /// IANA timezone of the city.
  final String timeZone;
  /// Local calendar date for which these times apply.
  final DateTime localDate;
  /// Hijri date string as reported by the provider.
  final String hijriDate;
  final bool isRamadan;
  /// Prayer times keyed by [Prayer]. Sunrise is present but not obligatory.
  final Map<Prayer, PrayerTime> times;
  /// Provider that supplied these times ("waqtazan" / "aladhan").
  final String provider;
  /// Calculation method used (e.g. "umm_al_qura", "21").
  final String method;
  /// Last successful synchronization instant.
  final DateTime lastSynced;
  /// Whether this instance was restored from the local cache.
  final bool fromCache;

  PrayerTime? get sunrise => times[Prayer.sunrise];

  /// The obligatory prayer times sorted by local time.
  List<PrayerTime> get obligatoryTimes {
    return kObligatoryPrayers
        .map((p) => times[p])
        .whereType<PrayerTime>()
        .toList()
      ..sort((a, b) => a.localTime.compareTo(b.localTime));
  }

  /// Next upcoming obligatory prayer relative to [now] (any timezone).
  /// Compares UTC instants to avoid timezone mismatch between device and city.
  /// Returns tomorrow's Fajr when every obligatory prayer today has passed,
  /// handling midnight and the day transition correctly.
  PrayerTime? nextPrayer(DateTime now) {
    final nowUtc = now.toUtc();
    final today = obligatoryTimes.where((t) => t.utcTime.isAfter(nowUtc));
    if (today.isNotEmpty) return today.first;
    // All prayers passed: next is Fajr of the next local day.
    final fajr = times[Prayer.fajr];
    if (fajr == null) return null;
    final tomorrowUtc = fajr.utcTime.add(const Duration(days: 1));
    return PrayerTime(
      prayer: Prayer.fajr,
      utcTime: tomorrowUtc,
      localTime: toCityTime(tomorrowUtc, timeZone),
      formatted: fajr.formatted,
    );
  }

  /// Countdown to a specific prayer relative to [now], using UTC instants.
  Duration? countdownTo(Prayer prayer, DateTime now) {
    final time = times[prayer];
    if (time == null) return null;
    return time.utcTime.difference(now.toUtc());
  }

  /// Build a cache key as specified: Country + City + Local Date + Provider +
  /// Calculation Method.
  String cacheKey() {
    final df = DateFormat('yyyy-MM-dd');
    return '$countrySlug|$citySlug|${df.format(localDate)}|$provider|$method';
  }

  PrayerTimes copyWith({
    String? countryIso,
    String? countrySlug,
    String? countryName,
    String? cityName,
    String? citySlug,
    double? latitude,
    double? longitude,
    String? timeZone,
    DateTime? localDate,
    String? hijriDate,
    bool? isRamadan,
    Map<Prayer, PrayerTime>? times,
    String? provider,
    String? method,
    DateTime? lastSynced,
    bool? fromCache,
  }) {
    return PrayerTimes(
      countryIso: countryIso ?? this.countryIso,
      countrySlug: countrySlug ?? this.countrySlug,
      countryName: countryName ?? this.countryName,
      cityName: cityName ?? this.cityName,
      citySlug: citySlug ?? this.citySlug,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timeZone: timeZone ?? this.timeZone,
      localDate: localDate ?? this.localDate,
      hijriDate: hijriDate ?? this.hijriDate,
      isRamadan: isRamadan ?? this.isRamadan,
      times: times ?? this.times,
      provider: provider ?? this.provider,
      method: method ?? this.method,
      lastSynced: lastSynced ?? this.lastSynced,
      fromCache: fromCache ?? this.fromCache,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'countryIso': countryIso,
      'countrySlug': countrySlug,
      'countryName': countryName,
      'cityName': cityName,
      'citySlug': citySlug,
      'latitude': latitude,
      'longitude': longitude,
      'timeZone': timeZone,
      'localDate': localDate.toIso8601String(),
      'hijriDate': hijriDate,
      'isRamadan': isRamadan ? 1 : 0,
      'times': times.map((key, value) => MapEntry(
            key.index.toString(),
            {
              'utcTime': value.utcTime.toIso8601String(),
              'localTime': value.localTime.toIso8601String(),
              'formatted': value.formatted,
            },
          )),
      'provider': provider,
      'method': method,
      'lastSynced': lastSynced.toIso8601String(),
      'fromCache': fromCache ? 1 : 0,
    };
  }

  factory PrayerTimes.fromJson(Map<String, dynamic> json) {
    final timesMap = <Prayer, PrayerTime>{};
    final rawTimes = json['times'] as Map? ?? {};
    rawTimes.forEach((key, value) {
      final index = int.tryParse(key.toString()) ?? -1;
      final prayer = Prayer.values.where((p) => p.index == index).firstOrNull;
      if (prayer != null && value is Map) {
        timesMap[prayer] = PrayerTime(
          prayer: prayer,
          utcTime: DateTime.parse(value['utcTime'] as String),
          localTime: DateTime.parse(value['localTime'] as String),
          formatted: value['formatted'] as String? ?? '',
        );
      }
    });
    return PrayerTimes(
      countryIso: json['countryIso'] as String? ?? '',
      countrySlug: json['countrySlug'] as String? ?? '',
      countryName: json['countryName'] as String? ?? '',
      cityName: json['cityName'] as String? ?? '',
      citySlug: json['citySlug'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      timeZone: json['timeZone'] as String? ?? 'UTC',
      localDate: DateTime.parse(json['localDate'] as String),
      hijriDate: json['hijriDate'] as String? ?? '',
      isRamadan: (json['isRamadan'] as int?) == 1,
      times: timesMap,
      provider: json['provider'] as String? ?? '',
      method: json['method'] as String? ?? '',
      lastSynced: DateTime.parse(json['lastSynced'] as String),
      fromCache: (json['fromCache'] as int?) == 1,
    );
  }
}

extension <T> on List<T> {
  T? firstOrNull(bool Function(T element)? test) {
    if (test == null) return isEmpty ? null : first;
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

/// Convert a UTC [DateTime] to the given IANA [timeZone], returning a local
/// [DateTime] in that timezone. Handles DST automatically.
DateTime toCityTime(DateTime utcTime, String timeZone) {
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
