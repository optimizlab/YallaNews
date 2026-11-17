
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models/prayer_times.dart';

class PrayerDatabase {
  PrayerDatabase._privateConstructor();
  static final PrayerDatabase instance = PrayerDatabase._privateConstructor();

  static Database? _db;
  static const int _dbVersion = 2;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      databaseFactory = databaseFactoryFfi;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'prayer_times.db');

    return openDatabase(
      dbPath,
      version: _dbVersion,
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS prayer_adhan_config (
              prayer_index INTEGER PRIMARY KEY,
              adhan_sound INTEGER NOT NULL DEFAULT 0
            )
          ''');
        }
      },
      onCreate: (Database db, int version) async {
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
          'CREATE INDEX IF NOT EXISTS idx_prayer_cache_lookup ON prayer_times_cache(country_slug, city_slug, local_date, provider, method)',
        );
        await db.execute('''
          CREATE TABLE IF NOT EXISTS prayer_adhan_config (
            prayer_index INTEGER PRIMARY KEY,
            adhan_sound INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
  }

  Future<void> cacheTimes(PrayerTimes times) async {
    final db = await database;
    final key = times.cacheKey();
    await db.insert(
      'prayer_times_cache',
      {
        'cache_key': key,
        'country_iso': times.countryIso,
        'country_slug': times.countrySlug,
        'country_name': times.countryName,
        'city_name': times.cityName,
        'city_slug': times.citySlug,
        'latitude': times.latitude,
        'longitude': times.longitude,
        'time_zone': times.timeZone,
        'local_date': times.localDate.toIso8601String(),
        'hijri_date': times.hijriDate,
        'is_ramadan': times.isRamadan ? 1 : 0,
        'times_json': jsonEncode(
          times.times.map(
            (key, value) => MapEntry(
              key.index.toString(),
              {
                'utcTime': value.utcTime.toIso8601String(),
                'localTime': value.localTime.toIso8601String(),
                'formatted': value.formatted,
              },
            ),
          ),
        ),
        'provider': times.provider,
        'method': times.method,
        'last_synced': times.lastSynced.millisecondsSinceEpoch,
        'from_cache': times.fromCache ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<PrayerTimes?> getCachedTimes(String cacheKey) async {
    final db = await database;
    final maps = await db.query(
      'prayer_times_cache',
      where: 'cache_key = ?',
      whereArgs: [cacheKey],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return _mapToPrayerTimes(maps.first, fromCache: true);
  }

  Future<PrayerTimes?> getCachedTimesFor({
    required String countrySlug,
    required String citySlug,
    required DateTime localDate,
    required String provider,
    required String method,
  }) async {
    final db = await database;
    final df = _dateFormat(localDate);
    final maps = await db.query(
      'prayer_times_cache',
      where:
          'country_slug = ? AND city_slug = ? AND local_date = ? AND provider = ? AND method = ?',
      whereArgs: [countrySlug, citySlug, df, provider, method],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return _mapToPrayerTimes(maps.first, fromCache: true);
  }

  Future<void> pruneOldCache({required DateTime olderThan}) async {
    final db = await database;
    await db.delete(
      'prayer_times_cache',
      where: 'last_synced < ?',
      whereArgs: [olderThan.millisecondsSinceEpoch],
    );
  }

  Future<void> clearCache() async {
    final db = await database;
    await db.delete('prayer_times_cache');
  }

  PrayerTimes _mapToPrayerTimes(Map<String, dynamic> map,
      {required bool fromCache}) {
    final timesMap = <int, PrayerTime>{};
    final rawTimes = jsonDecode(map['times_json'] as String) as Map?;
    if (rawTimes != null) {
      rawTimes.forEach((key, value) {
        final index = int.tryParse(key.toString()) ?? -1;
        if (value is Map) {
          timesMap[index] = PrayerTime(
            prayer: Prayer.values[index],
            utcTime: DateTime.parse(value['utcTime'] as String),
            localTime: DateTime.parse(value['localTime'] as String),
            formatted: value['formatted'] as String? ?? '',
          );
        }
      });
    }
    final Map<Prayer, PrayerTime> typedTimes = {};
    timesMap.forEach((index, prayerTime) {
      typedTimes[Prayer.values[index]] = prayerTime;
    });
    return PrayerTimes(
      countryIso: map['country_iso'] as String? ?? '',
      countrySlug: map['country_slug'] as String? ?? '',
      countryName: map['country_name'] as String? ?? '',
      cityName: map['city_name'] as String? ?? '',
      citySlug: map['city_slug'] as String? ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      timeZone: map['time_zone'] as String? ?? 'UTC',
      localDate: DateTime.parse(map['local_date'] as String),
      hijriDate: map['hijri_date'] as String? ?? '',
      isRamadan: (map['is_ramadan'] as int?) == 1,
      times: typedTimes,
      provider: map['provider'] as String? ?? '',
      method: map['method'] as String? ?? '',
      lastSynced: DateTime.fromMillisecondsSinceEpoch(
        map['last_synced'] as int,
      ),
      fromCache: fromCache,
    );
  }

  String _dateFormat(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
