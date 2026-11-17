
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/city_registry.dart';
import '../../services/app_settings.dart';
import '../prayer/provider.dart';

enum LocationSource { gps, deviceCountry, simCountry, manual, none }

class ResolvedLocation {
  const ResolvedLocation({
    required this.city,
    required this.source,
  });

  final CityEntry city;
  final LocationSource source;
}

class LocationManager {
  LocationManager({
    SharedPreferences? prefs,
    PrayerTimesProvider? provider,
  })  : _prefs = prefs,
        _provider = provider ?? WaqtazanProvider();

  static const String _keySelectedCountrySlug = 'prayer_selected_country_slug';
  static const String _keySelectedCitySlug = 'prayer_selected_city_slug';
  static const String _keyManualLocation = 'prayer_manual_location';

  final SharedPreferences? _prefs;
  final PrayerTimesProvider _provider;

  bool get _isManual {
    return _prefs?.getBool(_keyManualLocation) ?? false;
  }

  bool get hasManualLocation {
    return _prefs?.getBool(_keyManualLocation) ?? false;
  }

  /// The manually saved prayer city (from settings), or null when none is set.
  /// This is the source of truth used by [detectLocation], so the settings UI
  /// can reflect the city that will actually be used for real prayer data.
  CityEntry? get selectedCity {
    final settings = AppSettings.instance;
    final country = settings.prayerCountrySlug;
    final city = settings.prayerCitySlug;
    if (country == null || city == null) return null;
    return CityRegistry.instance.bySlug(country, city);
  }

  Future<ResolvedLocation> detectLocation() async {
    final settings = AppSettings.instance;
    final savedCountry = settings.prayerCountrySlug;
    final savedCity = settings.prayerCitySlug;
    if (savedCountry != null && savedCity != null) {
      final city = CityRegistry.instance.bySlug(savedCountry, savedCity);
      if (city != null) {
        return ResolvedLocation(city: city, source: LocationSource.manual);
      }
    }

    final manual = _loadManualSelection();
    if (manual != null) {
      return ResolvedLocation(city: manual, source: LocationSource.manual);
    }

    // GPS (one-shot fix, never continuous tracking).
    if (!_isManual) {
      try {
        final gps = await _detectViaGps();
        if (gps != null) return gps;
      } catch (_) {}
    }

    // Device country from locale settings.
    final device = _detectViaDeviceCountry();
    if (device != null) {
      return ResolvedLocation(city: device.city, source: LocationSource.deviceCountry);
    }

    // SIM/network country.
    final sim = _detectViaSimCountry();
    if (sim != null) {
      return ResolvedLocation(city: sim.city, source: LocationSource.simCountry);
    }

    // Fallback: Casablanca, Morocco (default for the app's primary market).
    return ResolvedLocation(
      city: CityRegistry.instance.bySlug('morocco', 'casablanca')!,
      source: LocationSource.none,
    );
  }

  Future<ResolvedLocation?> _detectViaGps() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
      timeLimit: const Duration(seconds: 10),
    );

    // 1. Try Waqtazan nearest-city endpoint.
    try {
      final nearest = await _provider.nearestCity(
        position.latitude,
        position.longitude,
      );
      final city = CityRegistry.instance.bySlug(
        nearest.countrySlug,
        nearest.citySlug,
      );
      if (city != null) {
        return ResolvedLocation(city: city, source: LocationSource.gps);
      }
      // Waqtazan returned a city not in our registry — use coordinates directly.
      final registryCity = CityRegistry.instance.nearest(
        position.latitude,
        position.longitude,
      );
      if (registryCity != null) {
        return ResolvedLocation(city: registryCity, source: LocationSource.gps);
      }
    } catch (_) {}

    // 2. Fall back to registry-based nearest city by haversine distance.
    final registryCity = CityRegistry.instance.nearest(
      position.latitude,
      position.longitude,
    );
    if (registryCity != null) {
      return ResolvedLocation(city: registryCity, source: LocationSource.gps);
    }
    return null;
  }

  ResolvedLocation? _detectViaDeviceCountry() {
    final locale = Platform.localeName;
    final countryCode = _extractCountryFromLocale(locale);
    if (countryCode == null) return null;
    final city = _cityForCountryCode(countryCode);
    if (city != null) {
      return ResolvedLocation(city: city, source: LocationSource.deviceCountry);
    }
    return null;
  }

  ResolvedLocation? _detectViaSimCountry() {
    final locale = Platform.localeName;
    final countryCode = _extractCountryFromLocale(locale);
    if (countryCode == null) return null;
    final city = _cityForCountryCode(countryCode);
    if (city != null) {
      return ResolvedLocation(city: city, source: LocationSource.simCountry);
    }
    return null;
  }

  String? _extractCountryFromLocale(String localeName) {
    // Platform.localeName looks like "en_US", "fr_FR", "ar_MA".
    final parts = localeName.split('_');
    if (parts.length >= 2) {
      return parts.last.toLowerCase();
    }
    return null;
  }

  CityEntry? _cityForCountryCode(String countryCode) {
    final upper = countryCode.toUpperCase();
    final isoToSlug = <String, String>{
      'MA': 'morocco',
      'FR': 'france',
      'SA': 'saudi-arabia',
      'EG': 'egypt',
      'SN': 'senegal',
      'AE': 'united-arab-emirates',
      'TR': 'turkey',
      'ID': 'indonesia',
      'PK': 'pakistan',
      'MY': 'malaysia',
      'IR': 'iran',
    };
    final countrySlug = isoToSlug[upper];
    if (countrySlug == null) return null;
    final cities = CityRegistry.instance.citiesForCountry(countrySlug);
    if (cities.isEmpty) return null;
    return cities.first;
  }

  CityEntry? _loadManualSelection() {
    if (_prefs == null) return null;
    final countrySlug = _prefs!.getString(_keySelectedCountrySlug);
    final citySlug = _prefs!.getString(_keySelectedCitySlug);
    if (countrySlug == null || citySlug == null) return null;
    return CityRegistry.instance.bySlug(countrySlug, citySlug);
  }

  Future<void> setManualLocation(CityEntry city) async {
    if (_prefs != null) {
      await _prefs!.setString(_keySelectedCountrySlug, city.countrySlug);
      await _prefs!.setString(_keySelectedCitySlug, city.slug);
      await _prefs!.setBool(_keyManualLocation, true);
    }
    await AppSettings.instance.setPrayerLocation(city.countrySlug, city.slug);
  }

  Future<void> clearManualLocation() async {
    if (_prefs != null) {
      await _prefs!.remove(_keySelectedCountrySlug);
      await _prefs!.remove(_keySelectedCitySlug);
      await _prefs!.setBool(_keyManualLocation, false);
    }
    await AppSettings.instance.clearPrayerLocation();
  }

  List<CityEntry> get allCities => CityRegistry.instance.all;

  Map<String, List<CityEntry>> get citiesByCountry {
    final map = <String, List<CityEntry>>{};
    for (final city in CityRegistry.instance.all) {
      map.putIfAbsent(city.countrySlug, () => <CityEntry>[]).add(city);
    }
    return map;
  }
}
