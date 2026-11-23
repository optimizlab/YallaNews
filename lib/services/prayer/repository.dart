import 'dart:io';
import 'package:flutter/foundation.dart';
import '../platform_stubs.dart';
import '../connectivity_service.dart';

import '../../models/city_registry.dart';
import '../../models/prayer_times.dart';
import '../prayer/location_manager.dart';
import '../prayer/prayer_database.dart';
import '../prayer/provider.dart';
import '../prayer/manager.dart';

class PrayerFetchResult {
  const PrayerFetchResult({
    required this.times,
    required this.metadata,
    this.error,
  });

  final PrayerTimes times;
  final CalculationMetadata metadata;
  final PrayerProviderException? error;

  bool get succeeded => error == null;
  bool get fromCache => times.fromCache;
}

class PrayerTimesRepository {
  PrayerTimesRepository({
    PrayerTimesManager? manager,
    LocationManager? location,
    PrayerDatabase? database,
  })  : _manager = manager ?? PrayerTimesManager(),
        _location = location ?? LocationManager(),
        _database = database ?? PrayerDatabase.instance;

  final PrayerTimesManager _manager;
  final LocationManager _location;
  final PrayerDatabase _database;

  Future<PrayerFetchResult> getToday({
    bool forceRefresh = false,
    bool allowFallback = true,
    bool forceGps = false,
  }) async {
    final resolved = await _location.detectLocation(forceGps: forceGps);
    return _fetchForCity(
      resolved.city,
      source: resolved.source,
      forceRefresh: forceRefresh,
      allowFallback: allowFallback,
    );
  }

  Future<PrayerFetchResult> forCity(
    CityEntry city, {
    bool forceRefresh = false,
    bool allowFallback = true,
  }) async {
    return _fetchForCity(
      city,
      source: LocationSource.manual,
      forceRefresh: forceRefresh,
      allowFallback: allowFallback,
    );
  }

  Future<PrayerFetchResult> refresh(CityEntry city) async {
    return forCity(city, forceRefresh: true, allowFallback: true);
  }

  Future<PrayerFetchResult> _fetchForCity(
    CityEntry city, {
    required LocationSource source,
    required bool forceRefresh,
    required bool allowFallback,
  }) async {
    final now = DateTime.now();

    if (!forceRefresh) {
      final cached = await _database.getCachedTimesFor(
        countrySlug: city.countrySlug,
        citySlug: city.slug,
        localDate: now,
        provider: _manager.selectedProviderId,
        method: _manager.selectedMethod ?? '',
      );
      if (cached != null) {
        return PrayerFetchResult(
          times: cached,
          metadata: CalculationMetadata(
            provider: cached.provider,
            method: cached.method,
            providerAvailable: true,
          ),
        );
      }
    }

    bool hasInternet = true;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final result = await ConnectivityService.isWifi() ||
            await ConnectivityService.hasInternet();
        hasInternet = result;
      } catch (_) {}
    }
    if (!hasInternet) {
      final fallbackCached = await _database.getCachedTimesFor(
        countrySlug: city.countrySlug,
        citySlug: city.slug,
        localDate: now,
        provider: _manager.selectedProviderId,
        method: _manager.selectedMethod ?? '',
      );
      if (fallbackCached != null) {
        return PrayerFetchResult(
          times: fallbackCached,
          metadata: CalculationMetadata(
            provider: fallbackCached.provider,
            method: fallbackCached.method,
            providerAvailable: false,
          ),
        );
      }
      return PrayerFetchResult(
        times: _emptyTimes(city),
        metadata: CalculationMetadata(
          provider: _manager.selectedProviderId,
          method: _manager.selectedMethod ?? '',
          providerAvailable: false,
        ),
        error: const PrayerProviderException('offline', provider: 'unknown'),
      );
    }

    final result = await _manager.fetchTimings(
      city,
      date: now,
      allowFallback: allowFallback,
    );

    if (result.succeeded) {
      await _database.cacheTimes(result.times);
      return PrayerFetchResult(
        times: result.times,
        metadata: result.metadata,
      );
    }

    final cached = await _database.getCachedTimesFor(
      countrySlug: city.countrySlug,
      citySlug: city.slug,
      localDate: now,
      provider: result.times.provider,
      method: result.times.method,
    );
    if (cached != null) {
      return PrayerFetchResult(
        times: cached,
        metadata: CalculationMetadata(
          provider: cached.provider,
          method: cached.method,
          providerAvailable: false,
        ),
        error: result.error,
      );
    }

    return PrayerFetchResult(
      times: result.times,
      metadata: result.metadata,
      error: result.error,
    );
  }

  PrayerTimes _emptyTimes(CityEntry city) {
    return PrayerTimes(
      countryIso: city.countryIso,
      countrySlug: city.countrySlug,
      countryName: city.countryName,
      cityName: city.cityName,
      citySlug: city.slug,
      latitude: city.latitude,
      longitude: city.longitude,
      timeZone: city.timeZone,
      localDate: DateTime.now(),
      hijriDate: '',
      isRamadan: false,
      times: const <Prayer, PrayerTime>{},
      provider: _manager.selectedProviderId,
      method: _manager.selectedMethod ?? '',
      lastSynced: DateTime.now(),
      fromCache: false,
    );
  }

  /// Returns all cached prayer times for a given month (all days).
  Future<List<PrayerTimes>> getAllMonthTimes({
    required String countrySlug,
    required String citySlug,
    required int year,
    required int month,
    required String provider,
    required String method,
  }) async {
    return _database.getCachedMonth(
      countrySlug: countrySlug,
      citySlug: citySlug,
      year: year,
      month: month,
      provider: provider,
      method: method,
    );
  }

  /// Returns all cached prayer times for a given year (all days).
  Future<List<PrayerTimes>> getAllYearTimes({
    required String countrySlug,
    required String citySlug,
    required int year,
    required String provider,
    required String method,
  }) async {
    return _database.getCachedYear(
      countrySlug: countrySlug,
      citySlug: citySlug,
      year: year,
      provider: provider,
      method: method,
    );
  }

  Future<CitySearchResult> resolveNearest(double lat, double lng) {
    return _manager.resolveNearest(lat, lng);
  }

  /// Fetch prayer times for the full [year]/[month] for [city].
  ///
  /// Uses cached data when available (no API call). Falls back to the API
  /// when the month is not fully cached, then persists the result locally
  /// so subsequent calls work offline.
  Future<PrayerFetchResult> getMonth({
    required CityEntry city,
    required int year,
    required int month,
    bool forceRefresh = false,
  }) async {
    final provider = _manager.selectedProviderId;
    final method = _manager.selectedMethod ?? '';

    // Return cached month data if fully present and not forcing refresh.
    if (!forceRefresh) {
      final hasData = await _database.hasMonthData(
        countrySlug: city.countrySlug,
        citySlug: city.slug,
        year: year,
        month: month,
        provider: provider,
        method: method,
      );
      if (hasData) {
        final monthTimes = await _database.getCachedMonth(
          countrySlug: city.countrySlug,
          citySlug: city.slug,
          year: year,
          month: month,
          provider: provider,
          method: method,
        );
        if (monthTimes.isNotEmpty) {
          return PrayerFetchResult(
            times: monthTimes.first,
            metadata: CalculationMetadata(
              provider: provider,
              method: method,
              providerAvailable: false,
            ),
          );
        }
      }
    }

    // No usable cache: fetch from API.
    bool hasInternet = true;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final result = await ConnectivityService.isWifi() ||
            await ConnectivityService.hasInternet();
        hasInternet = result;
      } catch (_) {}
    }

    if (!hasInternet) {
      // Last resort: return whatever partial cache exists.
      final partial = await _database.getCachedMonth(
        countrySlug: city.countrySlug,
        citySlug: city.slug,
        year: year,
        month: month,
        provider: provider,
        method: method,
      );
      if (partial.isNotEmpty) {
        return PrayerFetchResult(
          times: partial.first,
          metadata: CalculationMetadata(
            provider: provider,
            method: method,
            providerAvailable: false,
          ),
        );
      }
      return PrayerFetchResult(
        times: _emptyTimes(city),
        metadata: CalculationMetadata(
          provider: provider,
          method: method,
          providerAvailable: false,
        ),
        error: const PrayerProviderException('offline', provider: 'unknown'),
      );
    }

    final monthTimes = await _manager.fetchMonth(
      city,
      year: year,
      month: month,
    );

    if (monthTimes.isNotEmpty) {
      await _database.cacheMonth(monthTimes);
      return PrayerFetchResult(
        times: monthTimes.first,
        metadata: CalculationMetadata(
          provider: provider,
          method: method,
          providerAvailable: true,
        ),
      );
    }

    // API failed entirely; try partial cache as last resort.
    final partial = await _database.getCachedMonth(
      countrySlug: city.countrySlug,
      citySlug: city.slug,
      year: year,
      month: month,
      provider: provider,
      method: method,
    );
    if (partial.isNotEmpty) {
      return PrayerFetchResult(
        times: partial.first,
        metadata: CalculationMetadata(
          provider: provider,
          method: method,
          providerAvailable: false,
        ),
      );
    }

    return PrayerFetchResult(
      times: _emptyTimes(city),
      metadata: CalculationMetadata(
        provider: provider,
        method: method,
        providerAvailable: false,
      ),
      error: const PrayerProviderException(
        'failed to fetch month',
        provider: 'unknown',
      ),
    );
  }

  /// Fetch prayer times for the full [year]/[month] for [city] from the
  /// provider without persisting to the local database.
  ///
  /// Used by the synchronization manager so it can validate completeness
  /// before storing anything locally. Returns the raw provider result (may be
  /// partial when some days fail); callers must validate before persisting.
  Future<List<PrayerTimes>> fetchMonthRaw({
    required CityEntry city,
    required int year,
    required int month,
  }) async {
    return _manager.fetchMonth(city, year: year, month: month);
  }

  /// Today's prayer times from the local database only. Never calls the API.
  ///
  /// Returns null when today is not cached (e.g. before first-install
  /// synchronization has completed). The UI must handle this gracefully
  /// without triggering a network request.
  Future<PrayerTimes?> todayFromDb(CityEntry city) async {
    final now = DateTime.now();
    return _database.getCachedTimesFor(
      countrySlug: city.countrySlug,
      citySlug: city.slug,
      localDate: now,
      provider: _manager.selectedProviderId,
      method: _manager.selectedMethod ?? '',
    );
  }

  /// Fetch prayer times for the full [year] for [city].
  ///
  /// Uses cached data when available (no API call). Falls back to the API
  /// when the year is not cached, then persists the result locally
  /// so subsequent calls work offline.
  Future<PrayerFetchResult> getYear({
    required CityEntry city,
    required int year,
    bool forceRefresh = false,
  }) async {
    final provider = _manager.selectedProviderId;
    final method = _manager.selectedMethod ?? '';

    // Return cached year data if present and not forcing refresh.
    if (!forceRefresh) {
      final hasData = await _database.hasYearData(
        countrySlug: city.countrySlug,
        citySlug: city.slug,
        year: year,
        provider: provider,
        method: method,
      );
      if (hasData) {
        final yearTimes = await _database.getCachedYear(
          countrySlug: city.countrySlug,
          citySlug: city.slug,
          year: year,
          provider: provider,
          method: method,
        );
        if (yearTimes.isNotEmpty) {
          return PrayerFetchResult(
            times: yearTimes.first,
            metadata: CalculationMetadata(
              provider: provider,
              method: method,
              providerAvailable: false,
            ),
          );
        }
      }
    }

    // No usable cache: fetch from API.
    bool hasInternet = true;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final result = await ConnectivityService.isWifi() ||
            await ConnectivityService.hasInternet();
        hasInternet = result;
      } catch (_) {}
    }

    if (!hasInternet) {
      // Last resort: return whatever partial cache exists.
      final partial = await _database.getCachedYear(
        countrySlug: city.countrySlug,
        citySlug: city.slug,
        year: year,
        provider: provider,
        method: method,
      );
      if (partial.isNotEmpty) {
        return PrayerFetchResult(
          times: partial.first,
          metadata: CalculationMetadata(
            provider: provider,
            method: method,
            providerAvailable: false,
          ),
        );
      }
      return PrayerFetchResult(
        times: _emptyTimes(city),
        metadata: CalculationMetadata(
          provider: provider,
          method: method,
          providerAvailable: false,
        ),
        error: const PrayerProviderException('offline', provider: 'unknown'),
      );
    }

    final yearTimes = await _manager.fetchYear(
      city,
      year: year,
    );

    if (yearTimes.isNotEmpty) {
      await _database.cacheYear(yearTimes);
      return PrayerFetchResult(
        times: yearTimes.first,
        metadata: CalculationMetadata(
          provider: provider,
          method: method,
          providerAvailable: true,
        ),
      );
    }

    // API failed entirely; try partial cache as last resort.
    final partial = await _database.getCachedYear(
      countrySlug: city.countrySlug,
      citySlug: city.slug,
      year: year,
      provider: provider,
      method: method,
    );
    if (partial.isNotEmpty) {
      return PrayerFetchResult(
        times: partial.first,
        metadata: CalculationMetadata(
          provider: provider,
          method: method,
          providerAvailable: false,
        ),
      );
    }

    return PrayerFetchResult(
      times: _emptyTimes(city),
      metadata: CalculationMetadata(
        provider: provider,
        method: method,
        providerAvailable: false,
      ),
      error: const PrayerProviderException(
        'failed to fetch year',
        provider: 'unknown',
      ),
    );
  }

  Future<List<CitySearchResult>> searchCities(String query) {
    return _manager.searchCities(query);
  }

  List<CityEntry> get allCities => _location.allCities;

  Map<String, List<CityEntry>> get citiesByCountry =>
      _location.citiesByCountry;

  void selectProvider(String providerId) {
    _manager.selectProvider(providerId);
  }

  void selectMethod(String? method) {
    _manager.selectMethod(method);
  }

  String get selectedProviderId => _manager.selectedProviderId;
  String? get selectedMethod => _manager.selectedMethod;
  List<CalculationMethod> get availableMethods =>
      _manager.availableMethods();

  Future<void> setManualLocation(CityEntry city) {
    return _location.setManualLocation(city);
  }

  Future<void> clearManualLocation() {
    return _location.clearManualLocation();
  }

  bool get isManualLocation => _location.hasManualLocation;

  CityEntry? get selectedCity => _location.selectedCity;
}
