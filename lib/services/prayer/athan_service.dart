import 'dart:io' show Platform;

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/city_registry.dart';
import '../prayer/prayer_database.dart';
import '../prayer/repository.dart';
import '../prayer/sync_manager.dart';
import 'scheduler.dart';

/// Top-level coordinator for the offline-first Athan system.
///
/// Responsibilities (kept independent of the UI):
///  * Ensure the local database is initialized on first install (Months N +
///    N+1).
///  * Run automatic monthly synchronization (Month N+1, cleanup N-1) and
///    recovery after missed transitions.
///  * Schedule/restore native Athan alarms from the local database.
///
/// The Athan UI never talks to this service for data; it reads only from
/// [PrayerDatabase]. API synchronization happens here, in the background, and
/// never as a consequence of opening the Athan screen.
class AthanService {
  AthanService._();
  static final AthanService instance = AthanService._();

  late final PrayerTimesRepository _repository;
  late final AthanSyncManager _sync;
  late final AthanScheduler _scheduler;

  bool _initialized = false;

  /// One-time setup: load saved provider/method, run first-install or monthly
  /// sync as needed, then schedule alarms from the local database.
  ///
  /// Safe to call multiple times; subsequent calls are no-ops until
  /// [reset] is invoked.
  Future<void> initialize() async {
    if (_initialized) return;
    _repository = PrayerTimesRepository();
    _sync = AthanSyncManager(repository: _repository);
    _scheduler = AthanScheduler();

    final prefs = await SharedPreferences.getInstance();
    _repository.selectProvider(prefs.getString('prayer_provider') ?? 'waqtazan');
    _repository.selectMethod(prefs.getString('prayer_method'));

    _initialized = true;

    final city = _repository.selectedCity;
    if (city == null) return;

    // First installation: populate the current month and the following month.
    await _sync.ensureFirstInstall(city);

    // Automatic monthly sync (no-op if already synced this month; recovers
    // after missed transitions).
    await _sync.performMonthlySync(city);

    // Schedule all future enabled prayers from the local database.
    await _schedule(city);
  }

  /// Re-schedule native alarms whenever the user changes Athan settings,
  /// location, provider, or calculation method. Reads fresh config from
  /// SharedPreferences.
  ///
  /// Also ensures the two required months are populated, retrying first-install
  /// population if it previously failed (e.g. no internet at install time).
  Future<void> reschedule(CityEntry city) async {
    if (!_initialized) await initialize();
    await _sync.performMonthlySync(city);
    await _schedule(city);
  }

  /// Re-run synchronization and rescheduling after a location/method change.
  Future<void> syncAndReschedule(CityEntry city) async {
    if (!_initialized) await initialize();
    await _sync.performMonthlySync(city);
    await _schedule(city);
  }

  Future<void> _schedule(CityEntry city) async {
    final provider = _repository.selectedProviderId;
    final method = _repository.selectedMethod ?? '';
    await _scheduler.scheduleAllPrayers(
      countrySlug: city.countrySlug,
      citySlug: city.slug,
      provider: provider,
      method: method,
    );
    _scheduler.setTimeZone(city.timeZone);
  }

  /// Whether initialization has completed.
  bool get isInitialized => _initialized;

  /// The prayer times repository (exposed so the UI can read provider/method
  /// without creating a second instance).
  PrayerTimesRepository get repository => _repository;

  /// The scheduler (exposed so settings can trigger a reschedule).
  AthanScheduler get scheduler => _scheduler;

  /// Last successful sync timestamp.
  Future<DateTime?> get lastSuccessfulSync => _sync.lastSuccessfulSync;

  /// Whether the database has been initialized (first install done).
  Future<bool> get isDbInitialized => _sync.isInitialized;

  void reset() {
    _initialized = false;
  }
}
