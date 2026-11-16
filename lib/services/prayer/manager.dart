
import 'provider.dart';
import '../../models/city_registry.dart';
import '../../models/prayer_times.dart';

/// Result of a prayer times fetch, including which provider/method was used.
class PrayerTimesResult {
  const PrayerTimesResult({
    required this.times,
    required this.metadata,
    this.error,
  });

  final PrayerTimes times;
  final CalculationMetadata metadata;
  final PrayerProviderException? error;

  bool get succeeded => error == null;
}

/// Manages provider selection with Waqtazan as primary and AlAdhan as fallback.
/// Records the provider and method used; never silently switches methods.
class PrayerTimesManager {
  PrayerTimesManager({
    PrayerTimesProvider? primary,
    PrayerTimesProvider? fallback,
  })  : _primary = primary ?? WaqtazanProvider(),
        _fallback = fallback ?? AlAdhanProvider();

  final PrayerTimesProvider _primary;
  final PrayerTimesProvider _fallback;

  /// Currently selected provider id. Defaults to primary.
  String _selectedProviderId = 'waqtazan';

  /// Currently selected calculation method. Defaults to null (provider default).
  String? _selectedMethod;

  String get selectedProviderId => _selectedProviderId;
  String? get selectedMethod => _selectedMethod;

  List<PrayerTimesProvider> get _providers =>
      <PrayerTimesProvider>[_primary, _fallback];

  /// Set the user's preferred provider. Throws [ArgumentError] if unknown.
  void selectProvider(String providerId) {
    if (!_providers.any((p) => p.id == providerId)) {
      throw ArgumentError('Unknown provider: $providerId');
    }
    _selectedProviderId = providerId;
  }

  /// Set the user's preferred calculation method (provider-specific).
  void selectMethod(String? method) {
    _selectedMethod = method;
  }

  /// All available calculation methods across providers.
  List<CalculationMethod> availableMethods() {
    final methods = <CalculationMethod>[
      // Waqtazan default per-country method.
      const CalculationMethod(
        id: 'default',
        label: 'Default (provider)',
        providerId: 'waqtazan',
      ),
      // AlAdhan common methods.
      const CalculationMethod(
        id: '2',
        label: 'Islamic Society of North America',
        providerId: 'aladhan',
      ),
      const CalculationMethod(
        id: '21',
        label: 'Morocco (AlAdhan method 21)',
        providerId: 'aladhan',
      ),
      const CalculationMethod(
        id: '8',
        label: 'University of Islamic Sciences, Karachi',
        providerId: 'aladhan',
      ),
      const CalculationMethod(
        id: '4',
        label: 'Egyptian General Authority',
        providerId: 'aladhan',
      ),
      const CalculationMethod(
        id: '1',
        label: 'University of Islamic Sciences, Karachi (Shia Ithna-Ashari)',
        providerId: 'aladhan',
      ),
      const CalculationMethod(
        id: '5',
        label: 'Dubai',
        providerId: 'aladhan',
      ),
      const CalculationMethod(
        id: '7',
        label: 'Kuwait',
        providerId: 'aladhan',
      ),
      const CalculationMethod(
        id: '3',
        label: 'Muslim World League',
        providerId: 'aladhan',
      ),
      const CalculationMethod(
        id: '6',
        label: 'Umm al-Qura (Makkah)',
        providerId: 'aladhan',
      ),
      const CalculationMethod(
        id: '10',
        label: 'Tehran',
        providerId: 'aladhan',
      ),
    ];
    return methods;
  }

  /// Fetch prayer times for [city] on [date] (defaults to today).
  ///
  /// Uses the user-selected provider when set; otherwise the primary provider.
  /// Falls back to the secondary provider when the primary fails, recording the
  /// provider and method used. Never switches calculation method silently.
  Future<PrayerTimesResult> fetchTimings(
    CityEntry city, {
    DateTime? date,
    bool allowFallback = true,
  }) async {
    final providers = _orderedProviders();
    PrayerProviderException? lastError;

    for (final provider in providers) {
      // Skip a provider that is not the user's selection unless we are
      // falling back and the selected one already failed.
      if (_selectedProviderId != provider.id && !allowFallback) continue;

      try {
        final times = await provider.fetchTimings(city, date: date);
        // Apply user-selected method override when supported.
        final finalTimes = _applyMethodOverride(times, provider);
        return PrayerTimesResult(
          times: finalTimes,
          metadata: CalculationMetadata(
            provider: provider.id,
            method: finalTimes.method,
            providerAvailable: true,
          ),
        );
      } on PrayerProviderException catch (e) {
        lastError = e;
        continue;
      } catch (e) {
        lastError = PrayerProviderException(
          e.toString(),
          provider: provider.id,
        );
        continue;
      }
    }

    return PrayerTimesResult(
      times: _emptyTimes(city),
      metadata: CalculationMetadata(
        provider: _selectedProviderId,
        method: _selectedMethod ?? '',
        providerAvailable: false,
      ),
      error: lastError,
    );
  }

  /// Ordered list: user-selected provider first, then the other as fallback.
  List<PrayerTimesProvider> _orderedProviders() {
    final selected = _providers.firstWhere(
      (p) => p.id == _selectedProviderId,
      orElse: () => _primary,
    );
    final other = _providers.firstWhere(
      (p) => p.id != _selectedProviderId,
      orElse: () => _fallback,
    );
    return <PrayerTimesProvider>[selected, other];
  }

  PrayerTimes _applyMethodOverride(PrayerTimes times, PrayerTimesProvider provider) {
    if (_selectedMethod == null || _selectedMethod!.isEmpty) return times;
    // Only AlAdhan accepts an explicit method parameter; Waqtazan uses its own
    // per-country default and does not accept method overrides.
    if (provider.id == 'aladhan') {
      return times.copyWith(method: _selectedMethod!);
    }
    return times;
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
      provider: _selectedProviderId,
      method: _selectedMethod ?? '',
      lastSynced: DateTime.now(),
      fromCache: false,
    );
  }

  /// Resolve the nearest city to a coordinate using the primary provider.
  Future<CitySearchResult> resolveNearest(double latitude, double longitude) {
    return _primary.nearestCity(latitude, longitude);
  }

  /// Search cities using the primary provider.
  Future<List<CitySearchResult>> searchCities(String query) {
    return _primary.searchCities(query);
  }

  /// Check availability of each provider.
  Future<Map<String, bool>> providerAvailability() async {
    final result = <String, bool>{};
    for (final p in _providers) {
      try {
        result[p.id] = await p.isAvailable();
      } catch (_) {
        result[p.id] = false;
      }
    }
    return result;
  }
}
