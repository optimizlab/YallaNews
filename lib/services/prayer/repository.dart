import 'package:connectivity_plus/connectivity_plus.dart';

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
  }) async {
    final resolved = await _location.detectLocation();
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

    bool hasInternet = false;
    try {
      final result = await Connectivity().checkConnectivity();
      hasInternet = result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.mobile) ||
          result.contains(ConnectivityResult.ethernet);
    } catch (_) {}
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

  Future<CitySearchResult> resolveNearest(double lat, double lng) {
    return _manager.resolveNearest(lat, lng);
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
}
