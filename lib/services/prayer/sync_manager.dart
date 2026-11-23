import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/city_registry.dart';
import '../../models/prayer_times.dart';
import '../connectivity_service.dart';
import '../prayer/prayer_database.dart';
import '../prayer/repository.dart';

/// Result of a synchronization attempt.
class AthanSyncResult {
  const AthanSyncResult({
    required this.succeeded,
    this.error,
    this.monthsSynced = 0,
  });

  final bool succeeded;
  final String? error;
  final int monthsSynced;
}

/// Downloads missing prayer-time months, handles monthly transitions, and
/// manages retry/backoff and sync status. All persistence goes through
/// [PrayerDatabase]; valid local data is never overwritten with incomplete
/// API responses.
class AthanSyncManager {
  AthanSyncManager({
    required PrayerTimesRepository repository,
    PrayerDatabase? database,
  })  : _repository = repository,
        _database = database ?? PrayerDatabase.instance;

  final PrayerTimesRepository _repository;
  final PrayerDatabase _database;

  static const int _maxRetries = 6;
  static const Duration _baseBackoff = Duration(seconds: 5);

  /// First installation: populate Month N (current) and Month N+1 (following).
  /// Marks initialization complete only after both months are persisted.
  /// Returns false if the API is unavailable, leaving the app functional and
  /// the sync unmarked for a later retry.
  Future<bool> ensureFirstInstall(CityEntry city) async {
    if (await _database.isInitialized()) {
      return true;
    }

    final now = DateTime.now();
    final months = <(int year, int month)>[
      (now.year, now.month),
      nextMonthOf(now),
    ];

    var synced = 0;
    for (final (year, month) in months) {
      final ok = await _fetchAndStoreMonthWithRetry(city, year, month);
      if (!ok) {
        debugPrint(
            '[AthanSyncManager] First-install failed for $year-$month; not marking initialized');
        return false;
      }
      synced++;
    }

    await _markSynced(now);
    debugPrint(
        '[AthanSyncManager] First-install complete: $synced months persisted');
    return true;
  }

  /// Automatic monthly synchronization. Call on every app start (and after
  /// boot) so missed transitions are recovered.
  ///
  /// Ensures the database holds Month N and Month N+1, deletes Month N-1 once
  /// N and N+1 are verified valid, and updates the last-successful-sync state.
  Future<bool> performMonthlySync(CityEntry city) async {
    final now = DateTime.now();
    final currentMonthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';

    final provider = _repository.selectedProviderId;
    final method = _repository.selectedMethod ?? '';

    // 1. Ensure the active month (N) is present and complete.
    if (!(await _database.hasCompleteMonth(
          countrySlug: city.countrySlug,
          citySlug: city.slug,
          year: now.year,
          month: now.month,
          provider: provider,
          method: method,
        ))) {
      final ok = await _fetchAndStoreMonthWithRetry(city, now.year, now.month);
      if (!ok) {
        debugPrint('[AthanSyncManager] Monthly sync: could not complete month N');
        return false;
      }
    }

    // 2. Retrieve Month N+1 from the API (skip if already present/complete).
    final next = nextMonthOf(now);
    if (!(await _database.hasCompleteMonth(
          countrySlug: city.countrySlug,
          citySlug: city.slug,
        year: next.$1,
        month: next.$2,
          provider: provider,
          method: method,
        ))) {
      final ok = await _fetchAndStoreMonthWithRetry(city, next.$1, next.$2);
      if (!ok) {
        debugPrint('[AthanSyncManager] Monthly sync: could not fetch month N+1');
        return false;
      }
    }

    // 3. Verify N and N+1 are both available and valid before cleanup.
    final nOk = await _database.hasCompleteMonth(
      countrySlug: city.countrySlug,
      citySlug: city.slug,
      year: now.year,
      month: now.month,
      provider: provider,
      method: method,
    );
    final n1Ok = await _database.hasCompleteMonth(
      countrySlug: city.countrySlug,
      citySlug: city.slug,
      year: next.$1,
      month: next.$2,
      provider: provider,
      method: method,
    );
    if (!nOk || !n1Ok) {
      debugPrint('[AthanSyncManager] Monthly sync: N/N+1 incomplete; aborting cleanup');
      return false;
    }

    // 4. Delete Month N-1 (transactionally). Never delete future schedules.
    final prev = previousMonthOf(now);
    await _database.deleteMonth(
      countrySlug: city.countrySlug,
      citySlug: city.slug,
      year: prev.$1,
      month: prev.$2,
      provider: provider,
      method: method,
    );

    await _markSynced(now);
    debugPrint(
        '[AthanSyncManager] Monthly sync complete: keeping $currentMonthKey and ${next.$1}-${next.$2}, deleted ${prev.$1}-${prev.$2}');
    return true;
  }

  /// Ensure Month N+1 exists without triggering a full transition (used when
  /// the current month is already synced).
  Future<bool> ensureNextMonth(CityEntry city) async {
    final now = DateTime.now();
    final next = nextMonthOf(now);
    final provider = _repository.selectedProviderId;
    final method = _repository.selectedMethod ?? '';

    if (await _database.hasCompleteMonth(
          countrySlug: city.countrySlug,
          citySlug: city.slug,
        year: next.$1,
        month: next.$2,
          provider: provider,
          method: method,
        )) {
      return true;
    }
    return _fetchAndStoreMonthWithRetry(city, next.$1, next.$2);
  }

  /// Recover after missed transitions (e.g. device off for weeks). Re-runs the
  /// monthly sync logic which back-fills missing months and cleans up stale
  /// N-1 data.
  Future<bool> recover(CityEntry city) async {
    return performMonthlySync(city);
  }

  /// Last successful synchronization timestamp, if any.
  Future<DateTime?> get lastSuccessfulSync => _database.getLastSuccessfulSync();

  /// Whether the database has been initialized (first-install done).
  Future<bool> get isInitialized => _database.isInitialized();

  // ────────────────────────────────────────────────────────────
  // Internal: fetch + validate + store one month with exponential backoff
  // ────────────────────────────────────────────────────────────

  Future<bool> _fetchAndStoreMonthWithRetry(
      CityEntry city, int year, int month) async {
    // Avoid unnecessary API calls when the month is already complete.
    final provider = _repository.selectedProviderId;
    final method = _repository.selectedMethod ?? '';
    if (await _database.hasCompleteMonth(
          countrySlug: city.countrySlug,
          citySlug: city.slug,
          year: year,
          month: month,
          provider: provider,
          method: method,
        )) {
      return true;
    }

    bool hasInternet = true;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        hasInternet = await ConnectivityService.isWifi() ||
            await ConnectivityService.hasInternet();
      } catch (_) {
        hasInternet = false;
      }
    }
    if (!hasInternet) {
      debugPrint('[AthanSyncManager] No internet; skipping $year-$month');
      return false;
    }

    var delay = _baseBackoff;
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final ok = await _fetchAndStoreMonth(city, year, month);
        if (ok) return true;
      } catch (e) {
        debugPrint(
            '[AthanSyncManager] Attempt $attempt failed for $year-$month: $e');
      }
      await Future.delayed(delay);
      delay = _exponentialBackoff(delay, attempt);
    }
    debugPrint('[AthanSyncManager] Giving up on $year-$month after $_maxRetries attempts');
    return false;
  }

  /// Fetch a single month from the provider, validate completeness, and store
  /// transactionally. Never stores partial/invalid data.
  Future<bool> _fetchAndStoreMonth(
      CityEntry city, int year, int month) async {
    final daysInMonth = DateTime(year, month + 1, 0).day;

    final monthTimes = await _repository.fetchMonthRaw(
      city: city,
      year: year,
      month: month,
    );

    if (monthTimes.length < daysInMonth) {
      debugPrint(
          '[AthanSyncManager] Incomplete month $year-$month: ${monthTimes.length}/$daysInMonth days');
      return false;
    }

    // Validate every day carries all obligatory prayers.
    for (final times in monthTimes) {
      if (!_hasAllObligatory(times)) {
        debugPrint(
            '[AthanSyncManager] Invalid day ${times.localDate} in $year-$month: missing prayers');
        return false;
      }
    }

    await _database.storeMonth(monthTimes);
    return true;
  }

  bool _hasAllObligatory(PrayerTimes times) {
    for (final prayer in kObligatoryPrayers) {
      final t = times.times[prayer];
      if (t == null) {
        return false;
      }
    }
    return true;
  }

  Future<void> _markSynced(DateTime now) async {
    final nowUtc = DateTime.utc(now.year, now.month, now.day,
        now.hour, now.minute, now.second);
    await _database.setLastSuccessfulSync(nowUtc);
    await _database.setLastSyncMonth(
        '${now.year}-${now.month.toString().padLeft(2, '0')}');
  }

  /// The month following [d] as a (year, month) pair.
  static (int year, int month) nextMonthOf(DateTime d) {
    if (d.month == 12) return (d.year + 1, 1);
    return (d.year, d.month + 1);
  }

  /// The month preceding [d] as a (year, month) pair.
  static (int year, int month) previousMonthOf(DateTime d) {
    if (d.month == 1) return (d.year - 1, 12);
    return (d.year, d.month - 1);
  }

  Duration _exponentialBackoff(Duration current, int attempt) {
    // cap at ~5 minutes
    final next = current.inMilliseconds * 2;
    return Duration(milliseconds: next.clamp(0, 300_000));
  }
}
