
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/prayer_times.dart';

class PrayerDatabase {
  PrayerDatabase._privateConstructor();
  static final PrayerDatabase instance = PrayerDatabase._privateConstructor();

  static Database? _db;
  static const int _dbVersion = 4;

  /// Meta keys persisted in [athan_meta] for sync state and initialization.
  static const String _keyDbInitialized = 'athan_db_initialized';
  static const String _keyLastSuccessfulSync = 'athan_last_successful_sync';
  static const String _keyLastSyncMonth = 'athan_last_sync_month';

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    // databaseFactory is set once in main.dart via sqfliteFfiInit()
    // (desktop only). Do not reassign here to avoid the sqflite
    // "changing default factory" warning on every database open.
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
        if (oldVersion < 3) {
          await _createMetaTable(db);
          await _insertMetaDefaults(db);
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE prayer_times_cache ADD COLUMN hijri_month INTEGER',
          );
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
            hijri_month INTEGER,
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
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_prayer_cache_lookup ON prayer_times_cache(country_slug, city_slug, local_date, provider, method)',
        );
        await db.execute('''
          CREATE TABLE IF NOT EXISTS prayer_adhan_config (
            prayer_index INTEGER PRIMARY KEY,
            adhan_sound INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await _createMetaTable(db);
        await _insertMetaDefaults(db);
      },
    );
  }

  static Future<void> _createMetaTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS athan_meta (
        meta_key TEXT PRIMARY KEY,
        meta_value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _insertMetaDefaults(Database db) async {
    await db.insert(
      'athan_meta',
      {'meta_key': _keyDbInitialized, 'meta_value': '0'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'athan_meta',
      {'meta_key': _keyLastSuccessfulSync, 'meta_value': ''},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'athan_meta',
      {'meta_key': _keyLastSyncMonth, 'meta_value': ''},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Whether the local Athan database has been initialized (first-install
  /// population completed).
  Future<bool> isInitialized() async {
    final db = await database;
    final maps = await db.query(
      'athan_meta',
      where: 'meta_key = ?',
      whereArgs: [_keyDbInitialized],
      limit: 1,
    );
    if (maps.isEmpty) return false;
    return (maps.first['meta_value'] as String?) == '1';
  }

  /// Mark the Athan database as initialized after successful first-install
  /// persistence.
  Future<void> markInitialized() async {
    final db = await database;
    await db.update(
      'athan_meta',
      {'meta_value': '1'},
      where: 'meta_key = ?',
      whereArgs: [_keyDbInitialized],
    );
  }

  /// Get the last successful synchronization timestamp.
  Future<DateTime?> getLastSuccessfulSync() async {
    final db = await database;
    final maps = await db.query(
      'athan_meta',
      where: 'meta_key = ?',
      whereArgs: [_keyLastSuccessfulSync],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final value = maps.first['meta_value'] as String?;
    if (value == null || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  /// Record the last successful synchronization timestamp.
  Future<void> setLastSuccessfulSync(DateTime time) async {
    final db = await database;
    await db.update(
      'athan_meta',
      {'meta_value': time.toUtc().toIso8601String()},
      where: 'meta_key = ?',
      whereArgs: [_keyLastSuccessfulSync],
    );
  }

  /// Get the "yyyy-MM" month of the last successful sync (for transition
  /// detection).
  Future<String?> getLastSyncMonth() async {
    final db = await database;
    final maps = await db.query(
      'athan_meta',
      where: 'meta_key = ?',
      whereArgs: [_keyLastSyncMonth],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first['meta_value'] as String?;
  }

  /// Record the "yyyy-MM" month of the last successful sync.
  Future<void> setLastSyncMonth(String month) async {
    final db = await database;
    await db.update(
      'athan_meta',
      {'meta_value': month},
      where: 'meta_key = ?',
      whereArgs: [_keyLastSyncMonth],
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
        'hijri_month': times.hijriDateMonth,
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

  /// Batch-cache an entire year of prayer times.
  ///
  /// Throws if the database batch commit fails.
  Future<void> cacheYear(List<PrayerTimes> timesList) async {
    if (timesList.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final times in timesList) {
      final key = times.cacheKey();
      batch.insert(
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
        'local_date': times.localDate.toIso8601String().split('T').first,
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
    try {
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('[PrayerDatabase] cacheYear commit error: $e');
      rethrow;
    }
  }

  /// Batch-cache an entire month of prayer times.
  ///
  /// Throws if the database batch commit fails.
  Future<void> cacheMonth(List<PrayerTimes> timesList) async {
    if (timesList.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final times in timesList) {
      final key = times.cacheKey();
      batch.insert(
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
        'local_date': times.localDate.toIso8601String().split('T').first,
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
    try {
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('[PrayerDatabase] cacheMonth commit error: $e');
      rethrow;
    }
  }

  /// Returns all cached prayer times for a given year (all days).
  Future<List<PrayerTimes>> getCachedYear({
    required String countrySlug,
    required String citySlug,
    required int year,
    required String provider,
    required String method,
  }) async {
    final db = await database;
    final startDate = DateTime(year, 1, 1);
    final endDate = DateTime(year, 12, 31);
    final maps = await db.query(
      'prayer_times_cache',
      where:
          'country_slug = ? AND city_slug = ? AND provider = ? AND method = ? AND local_date >= ? AND local_date <= ?',
      whereArgs: [
        countrySlug,
        citySlug,
        provider,
        method,
        startDate.toIso8601String().split('T').first,
        endDate.toIso8601String().split('T').first,
      ],
      orderBy: 'local_date ASC',
    );
    return maps.map((m) => _mapToPrayerTimes(m, fromCache: true)).toList();
  }

  /// Returns all cached prayer times for a given month (year-month).
  Future<List<PrayerTimes>> getCachedMonth({
    required String countrySlug,
    required String citySlug,
    required int year,
    required int month,
    required String provider,
    required String method,
  }) async {
    final db = await database;
    final startDate = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final endDate = DateTime(year, month, daysInMonth);
    final maps = await db.query(
      'prayer_times_cache',
      where:
          'country_slug = ? AND city_slug = ? AND provider = ? AND method = ? AND local_date >= ? AND local_date <= ?',
      whereArgs: [
        countrySlug,
        citySlug,
        provider,
        method,
        startDate.toIso8601String().split('T').first,
        endDate.toIso8601String().split('T').first,
      ],
      orderBy: 'local_date ASC',
    );
    return maps.map((m) => _mapToPrayerTimes(m, fromCache: true)).toList();
  }

  /// Checks whether any cached data exists for the given year.
  Future<bool> hasYearData({
    required String countrySlug,
    required String citySlug,
    required int year,
    required String provider,
    required String method,
  }) async {
    final db = await database;
    final result = await db.rawQuery(
      '''SELECT COUNT(*) as cnt FROM prayer_times_cache
         WHERE country_slug = ? AND city_slug = ? AND provider = ? AND method = ?
         AND local_date >= ? AND local_date <= ?''',
      [
        countrySlug,
        citySlug,
        provider,
        method,
        '$year-01-01',
        '$year-12-31',
      ],
    );
    final count = Sqflite.firstIntValue(result) ?? 0;
    return count > 0;
  }

  /// Checks whether any cached data exists for the given month.
  Future<bool> hasMonthData({
    required String countrySlug,
    required String citySlug,
    required int year,
    required int month,
    required String provider,
    required String method,
  }) async {
    final db = await database;
    final result = await db.rawQuery(
      '''SELECT COUNT(*) as cnt FROM prayer_times_cache
         WHERE country_slug = ? AND city_slug = ? AND provider = ? AND method = ?
         AND local_date >= ? AND local_date <= ?''',
      [
        countrySlug,
        citySlug,
        provider,
        method,
        '$year-${month.toString().padLeft(2, '0')}-01',
        '$year-${month.toString().padLeft(2, '0')}-${DateTime(year, month + 1, 0).day.toString().padLeft(2, '0')}',
      ],
    );
    final count = Sqflite.firstIntValue(result) ?? 0;
    return count > 0;
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

  /// Number of cached prayer-day records for a given month.
  Future<int> countMonthDays({
    required String countrySlug,
    required String citySlug,
    required int year,
    required int month,
    required String provider,
    required String method,
  }) async {
    final db = await database;
    final start = '$year-${month.toString().padLeft(2, '0')}-01';
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final end = '$year-${month.toString().padLeft(2, '0')}-${daysInMonth.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      '''SELECT COUNT(*) as cnt FROM prayer_times_cache
         WHERE country_slug = ? AND city_slug = ? AND provider = ? AND method = ?
         AND local_date >= ? AND local_date <= ?''',
      [countrySlug, citySlug, provider, method, start, end],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Whether every calendar day of the month is present in the cache.
  Future<bool> hasCompleteMonth({
    required String countrySlug,
    required String citySlug,
    required int year,
    required int month,
    required String provider,
    required String method,
  }) async {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final count = await countMonthDays(
      countrySlug: countrySlug,
      citySlug: citySlug,
      year: year,
      month: month,
      provider: provider,
      method: method,
    );
    return count >= daysInMonth;
  }

  /// All cached prayer times for a whole month (one record per day).
  Future<List<PrayerTimes>> getMonthPrayerTimes({
    required String countrySlug,
    required String citySlug,
    required int year,
    required int month,
    required String provider,
    required String method,
  }) async {
    return getCachedMonth(
      countrySlug: countrySlug,
      citySlug: citySlug,
      year: year,
      month: month,
      provider: provider,
      method: method,
    );
  }

  /// Cached prayer times for a single local date.
  Future<PrayerTimes?> getTimesForDate({
    required String countrySlug,
    required String citySlug,
    required DateTime localDate,
    required String provider,
    required String method,
  }) async {
    return getCachedTimesFor(
      countrySlug: countrySlug,
      citySlug: citySlug,
      localDate: localDate,
      provider: provider,
      method: method,
    );
  }

  /// Delete all prayer-time records for a given month (transactional).
  Future<void> deleteMonth({
    required String countrySlug,
    required String citySlug,
    required int year,
    required int month,
    required String provider,
    required String method,
  }) async {
    final db = await database;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final start = '$year-${month.toString().padLeft(2, '0')}-01';
    final end = '$year-${month.toString().padLeft(2, '0')}-${daysInMonth.toString().padLeft(2, '0')}';
    await db.transaction((txn) async {
      await txn.delete(
        'prayer_times_cache',
        where:
            'country_slug = ? AND city_slug = ? AND provider = ? AND method = ? AND local_date >= ? AND local_date <= ?',
        whereArgs: [countrySlug, citySlug, provider, method, start, end],
      );
    });
  }

  /// Atomically store a whole month of prayer times. Aborts (and throws) if
  /// the list is empty so valid local data is never replaced with nothing.
  Future<void> storeMonth(List<PrayerTimes> timesList) async {
    if (timesList.isEmpty) {
      throw StateError('storeMonth called with empty times list');
    }
    final db = await database;
    final batch = db.batch();
    for (final times in timesList) {
      final key = times.cacheKey();
      batch.insert(
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
          'local_date': times.localDate.toIso8601String().split('T').first,
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
    await batch.commit(noResult: true);
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
      hijriDateMonth: map['hijri_month'] as int?,
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
