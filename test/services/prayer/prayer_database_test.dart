import 'dart:convert';
import 'dart:io' show Directory;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';

import '../../../lib/models/prayer_times.dart';

/// Builds one [PrayerTimes] record for [date] with all obligatory prayers.
PrayerTimes _makeTimes({
  required DateTime date,
  String countrySlug = 'morocco',
  String citySlug = 'casablanca',
  String provider = 'waqtazan',
  String method = 'default',
}) {
  final base = DateTime.utc(date.year, date.month, date.day, 5, 0);
  final times = <Prayer, PrayerTime>{};
  for (final prayer in kObligatoryPrayers) {
    final offset = switch (prayer) {
      Prayer.fajr => Duration.zero,
      Prayer.dhuhr => const Duration(hours: 7),
      Prayer.asr => const Duration(hours: 11),
      Prayer.maghrib => const Duration(hours: 17),
      Prayer.isha => const Duration(hours: 20),
      Prayer.sunrise => const Duration(hours: 5),
    };
    times[prayer] = PrayerTime(
      prayer: prayer,
      utcTime: base.add(offset),
      localTime: base.add(offset),
      formatted: '${base.add(offset).hour.toString().padLeft(2, '0')}:${base.add(offset).minute.toString().padLeft(2, '0')}',
    );
  }
  return PrayerTimes(
    countryIso: 'MA',
    countrySlug: countrySlug,
    countryName: 'Morocco',
    cityName: 'Casablanca',
    citySlug: citySlug,
    latitude: 33.5731,
    longitude: -7.5898,
    timeZone: 'Africa/Casablanca',
    localDate: date,
    hijriDate: '1448-04-15',
    isRamadan: false,
    times: times,
    provider: provider,
    method: method,
    lastSynced: DateTime.now(),
    fromCache: false,
  );
}

/// Serializes [times] into the same [times_json] format used by the database.
String _timesJson(PrayerTimes times) {
  return jsonEncode(times.times.map(
    (key, value) => MapEntry(
      key.index.toString(),
      {
        'utcTime': value.utcTime.toIso8601String(),
        'localTime': value.localTime.toIso8601String(),
        'formatted': value.formatted,
      },
    ),
  ));
}

Future<void> _insertPrayerTime(Database db, PrayerTimes times) async {
  await db.insert(
    'prayer_times_cache',
    {
      'cache_key': times.cacheKey(),
      'country_iso': times.countryIso,
      'country_slug': times.countrySlug,
      'country_name': times.countryName,
      'city_name': times.cityName,
      'city_slug': times.citySlug,
      'latitude': times.latitude,
      'longitude': times.longitude,
      'time_zone': times.timeZone,
      'local_date': times.localDate.toIso8601String().split('T').first,
      'hijri_date': times.hijriDate,
      'is_ramadan': times.isRamadan ? 1 : 0,
      'times_json': _timesJson(times),
      'provider': times.provider,
      'method': times.method,
      'last_synced': times.lastSynced.millisecondsSinceEpoch,
      'from_cache': times.fromCache ? 1 : 0,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

void main() {
  late Database db;
  final dir = p.join(
    Directory.current.path,
    'test_db_${DateTime.now().millisecondsSinceEpoch}.db',
  );

  setUpAll(() async {
    sqfliteFfiInit();
  });

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    db = await databaseFactory.openDatabase(dir);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS prayer_times_cache (
        cache_key TEXT PRIMARY KEY,
        country_iso TEXT NOT NULL,
        country_slug TEXT NOT NULL,
        country_name TEXT NOT NULL,
        city_name TEXT NOT NULL,
        city_slug TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        time_zone TEXT NOT NULL,
        local_date TEXT NOT NULL,
        hijri_date TEXT NOT NULL,
        is_ramadan INTEGER NOT NULL DEFAULT 0,
        times_json TEXT NOT NULL,
        provider TEXT NOT NULL,
        method TEXT NOT NULL,
        last_synced INTEGER NOT NULL,
        from_cache INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_prayer_cache_unique ON prayer_times_cache(country_slug, city_slug, local_date, provider, method)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS prayer_adhan_config (
        prayer_index INTEGER PRIMARY KEY,
        adhan_sound INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS athan_meta (
        meta_key TEXT PRIMARY KEY,
        meta_value TEXT NOT NULL
      )
    ''');
    await db.insert('athan_meta',
        {'meta_key': 'athan_db_initialized', 'meta_value': '0'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    // Start each test with a clean prayer cache.
    await db.delete('prayer_times_cache');
  });

  tearDown(() async {
    await db.close();
  });

  group('prayer_times_cache schema', () {
    test('unique index prevents duplicate prayer records', () async {
      final times = _makeTimes(date: DateTime(2026, 11, 22));
      await _insertPrayerTime(db, times);

      // Inserting the same key again must replace, not duplicate.
      await _insertPrayerTime(db, times);
      final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM prayer_times_cache WHERE cache_key = ?',
        [times.cacheKey()],
      ));
      expect(count, 1);

      // A different day is a distinct record.
      final tomorrow = _makeTimes(date: DateTime(2026, 11, 23));
      await _insertPrayerTime(db, tomorrow);
      final total = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM prayer_times_cache',
      ));
      expect(total, 2);
    });
  });

  group('month queries', () {
    test('countMonthDays counts records for a month', () async {
      for (var d = 1; d <= 10; d++) {
        await _insertPrayerTime(db, _makeTimes(date: DateTime(2026, 11, d)));
      }
      final count = Sqflite.firstIntValue(await db.rawQuery(
        '''SELECT COUNT(*) as cnt FROM prayer_times_cache
           WHERE country_slug = ? AND city_slug = ? AND provider = ? AND method = ?
           AND local_date >= ? AND local_date <= ?''',
        ['morocco', 'casablanca', 'waqtazan', 'default',
         '2026-11-01', '2026-11-30'],
      ));
      expect(count, 10);
    });

    test('deleteMonth removes only the requested month', () async {
      await _insertPrayerTime(db, _makeTimes(date: DateTime(2026, 10, 15)));
      await _insertPrayerTime(db, _makeTimes(date: DateTime(2026, 11, 15)));
      await _insertPrayerTime(db, _makeTimes(date: DateTime(2026, 12, 15)));

      await db.delete('prayer_times_cache',
          where: 'local_date >= ? AND local_date <= ?',
          whereArgs: ['2026-11-01', '2026-11-30']);

      final nov = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM prayer_times_cache WHERE local_date LIKE '2026-11-%'",
      ));
      final oct = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM prayer_times_cache WHERE local_date LIKE '2026-10-%'",
      ));
      final dec = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM prayer_times_cache WHERE local_date LIKE '2026-12-%'",
      ));
      expect(nov, 0);
      expect(oct, 1);
      expect(dec, 1);
    });
  });

  group('athan_meta sync state', () {
    test('get/set last successful sync and initialized flag', () async {
      await db.update('athan_meta',
          {'meta_value': '1'}, where: 'meta_key = ?',
          whereArgs: ['athan_db_initialized']);
      final init = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT meta_value FROM athan_meta WHERE meta_key = 'athan_db_initialized'",
      ));
      expect(init, 1);

      final now = DateTime.utc(2026, 11, 22, 10, 0);
      await db.insert('athan_meta',
          {'meta_key': 'athan_last_successful_sync',
           'meta_value': now.toUtc().toIso8601String()},
          conflictAlgorithm: ConflictAlgorithm.replace);
      final stored = (await db.rawQuery(
        "SELECT meta_value FROM athan_meta WHERE meta_key = 'athan_last_successful_sync'",
      )).first['meta_value'] as String?;
      expect(stored, isNotNull);
    });
  });
}
