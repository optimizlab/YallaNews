
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import '../../models/city_registry.dart';
import '../../models/prayer_times.dart';

/// Error thrown when a prayer times provider is unavailable or fails.
class PrayerProviderException implements Exception {
  const PrayerProviderException(this.message, {this.provider});

  final String message;
  final String? provider;

  @override
  String toString() => 'PrayerProviderException($provider): $message';
}

/// Metadata about which provider and calculation method produced a result.
class CalculationMetadata {
  const CalculationMetadata({
    required this.provider,
    required this.method,
    this.providerAvailable = true,
  });

  /// Provider identifier ("waqtazan" / "aladhan").
  final String provider;
  /// Calculation method used (e.g. "umm_al_qura", "21").
  final String method;
  /// Whether this provider was reachable / available at query time.
  final bool providerAvailable;
}

/// Abstraction over prayer times providers.
abstract class PrayerTimesProvider {
  /// Human-readable provider name.
  String get name;

  /// Provider identifier used in cache keys and settings.
  String get id;

  /// Whether this provider is currently considered available.
  Future<bool> isAvailable();

  /// Fetch prayer times for [city] on [date] (defaults to today).
  Future<PrayerTimes> fetchTimings(CityEntry city, {DateTime? date});

  /// Fetch prayer times for every day of [year]/[month] for [city].
  /// Returns a list of [PrayerTimes], one per day.
  Future<List<PrayerTimes>> fetchMonth(
    CityEntry city, {
    required int year,
    required int month,
  });

  /// Fetch prayer times for all 365/366 days of [year] for [city].
  /// Returns a list of [PrayerTimes], one per day.
  Future<List<PrayerTimes>> fetchYear(
    CityEntry city, {
    required int year,
  });

  /// Search for cities matching [query].
  Future<List<CitySearchResult>> searchCities(String query);

  /// Resolve the nearest city to a coordinate.
  Future<CitySearchResult> nearestCity(double latitude, double longitude);
}

/// Result of a city search / nearest-city lookup.
class CitySearchResult {
  const CitySearchResult({
    required this.countrySlug,
    required this.citySlug,
    required this.countryName,
    required this.cityName,
    required this.iso2,
    this.latitude,
    this.longitude,
  });

  final String countrySlug;
  final String citySlug;
  final String countryName;
  final String cityName;
  final String iso2;
  final double? latitude;
  final double? longitude;
}

/// A calculation method available from a provider.
class CalculationMethod {
  const CalculationMethod({
    required this.id,
    required this.label,
    required this.providerId,
  });

  final String id;
  final String label;
  final String providerId;
}

/// Ensures timezone data is loaded exactly once. Safe to call multiple times.
Future<void> ensureTimezoneInitialized() async {
  tz_data.initializeTimeZones();
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
    // Fallback to device local time if timezone database is unavailable.
    return utcTime.toLocal();
  }
}

/// Primary provider: Waqtazan.
class WaqtazanProvider implements PrayerTimesProvider {
  WaqtazanProvider({http.Client? client, this.baseUrl = 'https://waqtazan.com'})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 15);

  @override
  String get name => 'Waqtazan';

  @override
  String get id => 'waqtazan';

  @override
  Future<bool> isAvailable() async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/search?q=cairo');
      final response = await _client.get(uri).timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<PrayerTimes> fetchTimings(CityEntry city, {DateTime? date}) async {
    final dateParam = date != null ? '?date=${_fmt(date)}' : '';
    final uri = Uri.parse(
      '$baseUrl/api/v1/timings/${city.countrySlug}/${city.slug}$dateParam',
    );
    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw PrayerProviderException(
        'HTTP ${response.statusCode}',
        provider: id,
      );
    }
    return _parseResponse(response.body, city);
  }

  @override
  Future<List<PrayerTimes>> fetchMonth(
    CityEntry city, {
    required int year,
    required int month,
  }) async {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final results = <PrayerTimes>[];
    for (final day in List.generate(daysInMonth, (i) => i + 1)) {
      final date = DateTime(year, month, day);
      try {
        final times = await fetchTimings(city, date: date);
        results.add(times);
      } catch (_) {
        // Skip individual day failures; continue with remaining days.
      }
    }
    return results;
  }

  /// Fetch all 365/366 days of [year] by iterating through each month.
  /// Waqtazan does not have a single-year endpoint, so we aggregate
  /// monthly results.
  @override
  Future<List<PrayerTimes>> fetchYear(
    CityEntry city, {
    required int year,
  }) async {
    final results = <PrayerTimes>[];
    final missingDays = <int>[];

    for (final month in List.generate(12, (i) => i + 1)) {
      try {
        final monthResults = await fetchMonth(city, year: year, month: month);
        results.addAll(monthResults);
      } catch (_) {
        // If an entire month fails, mark all its days as missing.
        final daysInMonth = DateTime(year, month + 1, 0).day;
        final startDay = DateTime(year, month, 1)
            .difference(DateTime(year, 1, 1))
            .inDays
            .abs()
            .toInt()
            + 1;
        for (final d in List.generate(daysInMonth, (i) => startDay + i)) {
          missingDays.add(d);
        }
      }
    }

    // Validate all calendar dates are present.
    final presentDays = <int>{};
    for (final r in results) {
      presentDays.add(r.localDate.day);
    }
    final expectedDays = DateTime(year + 1, 1, 0).day;
    for (final d in List.generate(expectedDays, (i) => i + 1)) {
      if (!presentDays.contains(d)) missingDays.add(d);
    }

    if (missingDays.isNotEmpty) {
      throw PrayerProviderException(
        'missing ${missingDays.length} days: ${missingDays.take(10).join(", ")}',
        provider: id,
      );
    }

    return results;
  }

  @override
  Future<List<CitySearchResult>> searchCities(String query) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1/search?q=${Uri.encodeComponent(query)}',
    );
    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw PrayerProviderException(
        'HTTP ${response.statusCode}',
        provider: id,
      );
    }
    return _parseSearch(response.body);
  }

  @override
  Future<CitySearchResult> nearestCity(double latitude, double longitude) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1/nearest?lat=$latitude&lng=$longitude',
    );
    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw PrayerProviderException(
        'HTTP ${response.statusCode}',
        provider: id,
      );
    }
    final results = _parseSearch(response.body);
    if (results.isEmpty) {
      throw PrayerProviderException('no nearest city', provider: id);
    }
    return results.first;
  }

  PrayerTimes _parseResponse(String body, CityEntry city) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final cityData = data['city'] as Map? ?? {};
    final timesIso = data['timesISO'] as Map? ?? {};
    final timesPretty = data['times'] as Map? ?? {};

    final Map<Prayer, PrayerTime> prayerTimes = {};
    for (final prayer in kObligatoryPrayers) {
      final key = _waqtazanKey(prayer);
      final iso = timesIso[key] as String?;
      final pretty = timesPretty[key] as String?;
      if (iso == null || pretty == null) continue;
      final utc = DateTime.parse(iso).toUtc();
      prayerTimes[prayer] = PrayerTime(
        prayer: prayer,
        utcTime: utc,
        localTime: toCityTime(utc, city.timeZone),
        formatted: pretty,
      );
    }

    // Sunrise is not a prayer but is included for reference (Fajr ends at sunrise).
    final sunriseIso = timesIso['sunrise'] as String?;
    final sunrisePretty = timesPretty['sunrise'] as String?;
    if (sunriseIso != null && sunrisePretty != null) {
      final utc = DateTime.parse(sunriseIso).toUtc();
      prayerTimes[Prayer.sunrise] = PrayerTime(
        prayer: Prayer.sunrise,
        utcTime: utc,
        localTime: toCityTime(utc, city.timeZone),
        formatted: sunrisePretty,
      );
    }

    return PrayerTimes(
      countryIso: city.countryIso,
      countrySlug: city.countrySlug,
      countryName: cityData['name_ar'] as String? ?? city.countryName,
      cityName: cityData['name_ar'] as String? ?? city.cityName,
      citySlug: city.slug,
      latitude: city.latitude,
      longitude: city.longitude,
      timeZone: city.timeZone,
      localDate: DateTime.parse(data['date'] as String? ?? _today()),
      hijriDate: data['hijri'] as String? ?? '',
      isRamadan: data['isRamadan'] == true,
      times: prayerTimes,
      provider: id,
      method: data['method'] as String? ?? '',
      lastSynced: DateTime.now(),
      fromCache: false,
    );
  }

  /// Maps a [Prayer] enum to the Waqtazan API's string key (e.g. "fajr", "dhuhr").
  static String _waqtazanKey(Prayer prayer) {
    switch (prayer) {
      case Prayer.fajr:
        return 'fajr';
      case Prayer.sunrise:
        return 'sunrise';
      case Prayer.dhuhr:
        return 'dhuhr';
      case Prayer.asr:
        return 'asr';
      case Prayer.maghrib:
        return 'maghrib';
      case Prayer.isha:
        return 'isha';
    }
  }

  List<CitySearchResult> _parseSearch(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final results = data['results'] as List? ?? <dynamic>[];
    return results
        .whereType<Map>()
        .map((e) => CitySearchResult(
              // Waqtazan search uses country_slug/slug; nearest uses country/city.
              countrySlug: e['country_slug'] as String? ??
                  e['country'] as String? ??
                  '',
              citySlug: e['slug'] as String? ??
                  e['city'] as String? ??
                  '',
              countryName: e['country_ar'] as String? ?? '',
              cityName: e['name_ar'] as String? ?? '',
              iso2: e['iso2'] as String? ?? '',
              latitude: (e['lat'] as num?)?.toDouble(),
              longitude: (e['lng'] as num?)?.toDouble(),
            ))
        .toList();
  }

  String _fmt(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

/// Fallback provider: AlAdhan.
class AlAdhanProvider implements PrayerTimesProvider {
  AlAdhanProvider({http.Client? client, this.baseUrl = 'https://api.aladhan.com'})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 15);

  /// Default calculation method for Morocco (method 21 per requirements).
  static const String defaultMoroccoMethod = '21';

  @override
  String get name => 'AlAdhan';

  @override
  String get id => 'aladhan';

  @override
  Future<bool> isAvailable() async {
    try {
      final uri = Uri.parse(
        '$baseUrl/v1/timingsByCity/2026-01-01?city=cairo&country=Egypt&method=2',
      );
      final response = await _client.get(uri).timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<PrayerTimes> fetchTimings(CityEntry city, {DateTime? date}) async {
    final target = date ?? DateTime.now();
    final dateStr = _fmt(target);
    final method = _defaultMethodFor(country: city.countrySlug);
    final uri = Uri.parse(
      '$baseUrl/v1/timingsByCity/$dateStr?city=${Uri.encodeComponent(city.cityName)}&country=${Uri.encodeComponent(city.countryName)}&method=$method',
    );
    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw PrayerProviderException(
        'HTTP ${response.statusCode}',
        provider: id,
      );
    }
    return _parseResponse(response.body, city, method: method);
  }

  @override
  Future<List<PrayerTimes>> fetchMonth(
    CityEntry city, {
    required int year,
    required int month,
  }) async {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final method = _defaultMethodFor(country: city.countrySlug);
    final results = <PrayerTimes>[];
    for (final day in List.generate(daysInMonth, (i) => i + 1)) {
      final date = DateTime(year, month, day);
      final dateStr = _fmt(date);
      try {
        final uri = Uri.parse(
          '$baseUrl/v1/timingsByCity/$dateStr?city=${Uri.encodeComponent(city.cityName)}&country=${Uri.encodeComponent(city.countryName)}&method=$method',
        );
        final response = await _client.get(uri).timeout(_timeout);
        if (response.statusCode != 200) continue;
        results.add(_parseResponse(response.body, city, method: method));
      } catch (_) {
        // Skip individual day failures; continue with remaining days.
      }
    }
    return results;
  }

  /// Fetch all 365/366 days of [year] in one API call using AlAdhan's
  /// calendar endpoint: /v1/calendar/{year}?latitude=&longitude=
  @override
  Future<List<PrayerTimes>> fetchYear(
    CityEntry city, {
    required int year,
  }) async {
    final method = _defaultMethodFor(country: city.countrySlug);
    final uri = Uri.parse(
      '$baseUrl/v1/calendar/$year'
      '?latitude=${city.latitude}'
      '&longitude=${city.longitude}'
      '&method=$method',
    );
    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw PrayerProviderException(
        'HTTP ${response.statusCode}',
        provider: id,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final code = data['code'] as int?;
    if (code != 200) {
      throw PrayerProviderException(
        'API returned code $code',
        provider: id,
      );
    }

    final rawList = data['data'] as List?;
    if (rawList == null || rawList.isEmpty) {
      throw PrayerProviderException(
        'empty calendar data',
        provider: id,
      );
    }

    final results = <PrayerTimes>[];
    final expectedDays = DateTime(year + 1, 1, 0).day;
    final missingDays = <int>[];

    for (final item in rawList) {
      final timings = item['timings'] as Map? ?? {};
      final dateInfo = item['date'] as Map? ?? {};
      final gregorian = dateInfo['gregorian'] as Map? ?? {};
      final day = gregorian['day'] as int?;
      final month = gregorian['month'] as int?;
      final year = gregorian['year'] as int?;
      final hijri = dateInfo['hijri'] as Map? ?? {};

      if (day == null || month == null || year == null) {
        missingDays.add(missingDays.length + 1);
        continue;
      }

      final target = DateTime(year, month, day);
      final prayerMapping = <Prayer, String>{
        Prayer.fajr: 'Fajr',
        Prayer.dhuhr: 'Dhuhr',
        Prayer.asr: 'Asr',
        Prayer.maghrib: 'Maghrib',
        Prayer.isha: 'Isha',
      };

      final Map<Prayer, PrayerTime> prayerTimes = {};
      prayerMapping.forEach((prayer, key) {
        final value = timings[key] as String?;
        if (value == null) return;
        final local = _parseAlAdhanTime(value, target: target);
        final utc = local.toUtc();
        prayerTimes[prayer] = PrayerTime(
          prayer: prayer,
          utcTime: utc,
          localTime: toCityTime(utc, city.timeZone),
          formatted: value,
        );
      });

      final sunrise = timings['Sunrise'] as String?;
      if (sunrise != null) {
        final local = _parseAlAdhanTime(sunrise, target: target);
        final utc = local.toUtc();
        prayerTimes[Prayer.sunrise] = PrayerTime(
          prayer: Prayer.sunrise,
          utcTime: utc,
          localTime: toCityTime(utc, city.timeZone),
          formatted: sunrise,
        );
      }

      results.add(PrayerTimes(
        countryIso: city.countryIso,
        countrySlug: city.countrySlug,
        countryName: city.countryName,
        cityName: city.cityName,
        citySlug: city.slug,
        latitude: city.latitude,
        longitude: city.longitude,
        timeZone: city.timeZone,
        localDate: target,
        hijriDate: hijri['date'] as String? ?? '',
        isRamadan: false,
        times: prayerTimes,
        provider: id,
        method: method,
        lastSynced: DateTime.now(),
        fromCache: false,
      ));
    }

    // Validate all calendar dates are present.
    final presentDays = <int>{};
    for (final r in results) {
      presentDays.add(r.localDate.day);
    }
    for (final d in List.generate(expectedDays, (i) => i + 1)) {
      if (!presentDays.contains(d)) missingDays.add(d);
    }

    if (missingDays.isNotEmpty) {
      throw PrayerProviderException(
        'missing ${missingDays.length} days: ${missingDays.take(10).join(", ")}',
        provider: id,
      );
    }

    return results;
  }

  @override
  Future<List<CitySearchResult>> searchCities(String query) async {
    // AlAdhan has no public search endpoint; return empty so the manager falls
    // back to Waqtazan for search.
    return const <CitySearchResult>[];
  }

  @override
  Future<CitySearchResult> nearestCity(double latitude, double longitude) async {
    // AlAdhan has no nearest endpoint; throw so the manager uses Waqtazan.
    throw UnimplementedError('AlAdhan does not support nearest-city lookup');
  }

  PrayerTimes _parseResponse(String body, CityEntry city,
      {required String method}) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final meta = data['data'] as Map? ?? {};
    final timings = meta['timings'] as Map? ?? {};
    final date = meta['date'] as Map? ?? {};

    final Map<Prayer, PrayerTime> prayerTimes = {};
    final prayerMapping = <Prayer, String>{
      Prayer.fajr: 'Fajr',
      Prayer.dhuhr: 'Dhuhr',
      Prayer.asr: 'Asr',
      Prayer.maghrib: 'Maghrib',
      Prayer.isha: 'Isha',
    };
    final target = targetDate(date);
    prayerMapping.forEach((prayer, key) {
      final value = timings[key] as String?;
      if (value == null) return;
      final local = _parseAlAdhanTime(value, target: target);
      final utc = local.toUtc();
      prayerTimes[prayer] = PrayerTime(
        prayer: prayer,
        utcTime: utc,
        localTime: toCityTime(utc, city.timeZone),
        formatted: value,
      );
    });

    final sunrise = timings['Sunrise'] as String?;
    if (sunrise != null) {
      final local = _parseAlAdhanTime(sunrise, target: target);
      final utc = local.toUtc();
      prayerTimes[Prayer.sunrise] = PrayerTime(
        prayer: Prayer.sunrise,
        utcTime: utc,
        localTime: toCityTime(utc, city.timeZone),
        formatted: sunrise,
      );
    }

    return PrayerTimes(
      countryIso: city.countryIso,
      countrySlug: city.countrySlug,
      countryName: city.countryName,
      cityName: city.cityName,
      citySlug: city.slug,
      latitude: city.latitude,
      longitude: city.longitude,
      timeZone: city.timeZone,
      localDate: target,
      hijriDate: date['hijri'] as String? ?? '',
      isRamadan: false,
      times: prayerTimes,
      provider: id,
      method: method,
      lastSynced: DateTime.now(),
      fromCache: false,
    );
  }

  DateTime targetDate(Map? date) {
    final gregorian = (date?['gregorian'] as Map?) ?? {};
    final day = gregorian['day'] as int? ?? DateTime.now().day;
    final month = gregorian['month'] as int? ?? DateTime.now().month;
    final year = gregorian['year'] as int? ?? DateTime.now().year;
    return DateTime(year, month, day);
  }

  DateTime _parseAlAdhanTime(String time, {required DateTime target}) {
    // AlAdhan returns "HH:mm" in the city's local time. Interpret as local
    // then convert to UTC for storage.
    final parts = time.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return DateTime(target.year, target.month, target.day, hour, minute);
  }

  String _defaultMethodFor({required String country}) {
    // Morocco: evaluate against method 21 and official Moroccan calendar.
    if (country == 'morocco') return defaultMoroccoMethod;
    return '2';
  }

  String _fmt(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
