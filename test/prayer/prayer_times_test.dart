import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../lib/models/prayer_times.dart';
import '../../lib/models/city_registry.dart';
import '../../lib/services/prayer/countdown_engine.dart';
import '../../lib/services/prayer/manager.dart';

void main() {
  group('PrayerTimes model', () {
    test('cacheKey includes country, city, date, provider, method', () {
      final times = PrayerTimes(
        countryIso: 'MA',
        countrySlug: 'morocco',
        countryName: 'Morocco',
        cityName: 'Casablanca',
        citySlug: 'casablanca',
        latitude: 33.5731,
        longitude: -7.5898,
        timeZone: 'Africa/Casablanca',
        localDate: DateTime(2026, 11, 16),
        hijriDate: '1448-04-15',
        isRamadan: false,
        times: const <Prayer, PrayerTime>{},
        provider: 'waqtazan',
        method: 'default',
        lastSynced: DateTime.now(),
        fromCache: false,
      );
      final key = times.cacheKey();
      expect(key, contains('morocco'));
      expect(key, contains('casablanca'));
      expect(key, contains('2026-11-16'));
      expect(key, contains('waqtazan'));
      expect(key, contains('default'));
    });

    test('nextPrayer returns tomorrow Fajr when all prayers passed', () {
      final now = DateTime(2026, 11, 16, 20, 0); // After Isha
      final fajrTime = PrayerTime(
        prayer: Prayer.fajr,
        utcTime: DateTime(2026, 11, 16, 5, 0).toUtc(),
        localTime: DateTime(2026, 11, 16, 6, 0),
        formatted: '06:00',
      );
      final ishaTime = PrayerTime(
        prayer: Prayer.isha,
        utcTime: DateTime(2026, 11, 16, 18, 0).toUtc(),
        localTime: DateTime(2026, 11, 16, 19, 0),
        formatted: '19:00',
      );

      final times = PrayerTimes(
        countryIso: 'MA',
        countrySlug: 'morocco',
        countryName: 'Morocco',
        cityName: 'Casablanca',
        citySlug: 'casablanca',
        timeZone: 'Africa/Casablanca',
        localDate: DateTime(2026, 11, 16),
        hijriDate: '',
        isRamadan: false,
        times: <Prayer, PrayerTime>{
          Prayer.fajr: fajrTime,
          Prayer.isha: ishaTime,
        },
        provider: 'waqtazan',
        method: 'default',
        lastSynced: DateTime.now(),
        fromCache: false,
      );

      final next = times.nextPrayer(now);
      expect(next, isNotNull);
      expect(next!.prayer, Prayer.fajr);
      // Should be next day's Fajr
      expect(next.localTime.day, now.day + 1);
    });

    test('sunrise is not obligatory', () {
      expect(kObligatoryPrayers.contains(Prayer.sunrise), isFalse);
      expect(kObligatoryPrayers.contains(Prayer.fajr), isTrue);
      expect(kObligatoryPrayers.contains(Prayer.dhuhr), isTrue);
      expect(kObligatoryPrayers.contains(Prayer.asr), isTrue);
      expect(kObligatoryPrayers.contains(Prayer.maghrib), isTrue);
      expect(kObligatoryPrayers.contains(Prayer.isha), isTrue);
    });

    test('obligatoryTimes excludes sunrise and sorts by time', () {
      final fajr = PrayerTime(
        prayer: Prayer.fajr,
        utcTime: DateTime(2026, 11, 16, 5, 0).toUtc(),
        localTime: DateTime(2026, 11, 16, 6, 0),
        formatted: '06:00',
      );
      final isha = PrayerTime(
        prayer: Prayer.isha,
        utcTime: DateTime(2026, 11, 16, 18, 0).toUtc(),
        localTime: DateTime(2026, 11, 16, 19, 0),
        formatted: '19:00',
      );
      final sunrise = PrayerTime(
        prayer: Prayer.sunrise,
        utcTime: DateTime(2026, 11, 16, 5, 30).toUtc(),
        localTime: DateTime(2026, 11, 16, 6, 30),
        formatted: '06:30',
      );

      final times = PrayerTimes(
        countryIso: 'MA',
        countrySlug: 'morocco',
        countryName: 'Morocco',
        cityName: 'Casablanca',
        citySlug: 'casablanca',
        timeZone: 'Africa/Casablanca',
        localDate: DateTime(2026, 11, 16),
        hijriDate: '',
        isRamadan: false,
        times: <Prayer, PrayerTime>{
          Prayer.fajr: fajr,
          Prayer.isha: isha,
          Prayer.sunrise: sunrise,
        },
        provider: 'waqtazan',
        method: 'default',
        lastSynced: DateTime.now(),
        fromCache: false,
      );

      final obligatory = times.obligatoryTimes;
      expect(obligatory.length, 2);
      expect(obligatory[0].prayer, Prayer.fajr);
      expect(obligatory[1].prayer, Prayer.isha);
    });

    test('serialization roundtrip', () {
      final original = PrayerTimes(
        countryIso: 'MA',
        countrySlug: 'morocco',
        countryName: 'Morocco',
        cityName: 'Casablanca',
        citySlug: 'casablanca',
        latitude: 33.5731,
        longitude: -7.5898,
        timeZone: 'Africa/Casablanca',
        localDate: DateTime(2026, 11, 16),
        hijriDate: '1448-04-15',
        isRamadan: true,
        times: <Prayer, PrayerTime>{
          Prayer.fajr: PrayerTime(
            prayer: Prayer.fajr,
            utcTime: DateTime(2026, 11, 16, 5, 0).toUtc(),
            localTime: DateTime(2026, 11, 16, 6, 0),
            formatted: '06:00',
          ),
        },
        provider: 'waqtazan',
        method: 'default',
        lastSynced: DateTime(2026, 11, 16, 10, 0),
        fromCache: false,
      );

      final json = original.toJson();
      final restored = PrayerTimes.fromJson(json);

      expect(restored.countryIso, original.countryIso);
      expect(restored.citySlug, original.citySlug);
      expect(restored.hijriDate, original.hijriDate);
      expect(restored.isRamadan, original.isRamadan);
      expect(restored.provider, original.provider);
      expect(restored.method, original.method);
      expect(restored.fromCache, original.fromCache);
      expect(restored.times.length, 1);
      expect(restored.times[Prayer.fajr]!.formatted, '06:00');
    });
  });

  group('CityRegistry', () {
    test('finds Casablanca in Morocco', () {
      final city = CityRegistry.instance.bySlug('morocco', 'casablanca');
      expect(city, isNotNull);
      expect(city!.cityName, 'Casablanca');
      expect(city.countryIso, 'MA');
      expect(city.timeZone, 'Africa/Casablanca');
    });

    test('finds nearest city to coordinates', () {
      final city = CityRegistry.instance.nearest(33.5731, -7.5898);
      expect(city, isNotNull);
    });

    test('returns cities for Morocco', () {
      final cities = CityRegistry.instance.citiesForCountry('morocco');
      expect(cities.length, greaterThan(0));
      expect(cities.any((c) => c.cityName == 'Rabat'), isTrue);
      expect(cities.any((c) => c.cityName == 'Marrakech'), isTrue);
    });
  });

  group('CountdownEngine', () {
    test('calculates next prayer', () {
      final fajr = PrayerTime(
        prayer: Prayer.fajr,
        utcTime: DateTime(2026, 11, 16, 5, 0).toUtc(),
        localTime: DateTime(2026, 11, 16, 6, 0),
        formatted: '06:00',
      );
      final dhuhr = PrayerTime(
        prayer: Prayer.dhuhr,
        utcTime: DateTime(2026, 11, 16, 12, 0).toUtc(),
        localTime: DateTime(2026, 11, 16, 13, 0),
        formatted: '13:00',
      );

      final times = PrayerTimes(
        countryIso: 'MA',
        countrySlug: 'morocco',
        countryName: 'Morocco',
        cityName: 'Casablanca',
        citySlug: 'casablanca',
        timeZone: 'Africa/Casablanca',
        localDate: DateTime(2026, 11, 16),
        hijriDate: '',
        isRamadan: false,
        times: <Prayer, PrayerTime>{
          Prayer.fajr: fajr,
          Prayer.dhuhr: dhuhr,
        },
        provider: 'waqtazan',
        method: 'default',
        lastSynced: DateTime.now(),
        fromCache: false,
      );

      final engine = CountdownEngine(prayerTimes: times);
      // At 10:00 UTC, next prayer should be Dhuhr
      final now = DateTime.utc(2026, 11, 16, 10, 0);
      final next = engine.nextPrayerAt(now);
      expect(next.prayer, Prayer.dhuhr);
    });

    test('returns tomorrow Fajr when all prayers passed', () {
      final fajr = PrayerTime(
        prayer: Prayer.fajr,
        utcTime: DateTime(2026, 11, 16, 5, 0).toUtc(),
        localTime: DateTime(2026, 11, 16, 6, 0),
        formatted: '06:00',
      );

      final times = PrayerTimes(
        countryIso: 'MA',
        countrySlug: 'morocco',
        countryName: 'Morocco',
        cityName: 'Casablanca',
        citySlug: 'casablanca',
        timeZone: 'Africa/Casablanca',
        localDate: DateTime(2026, 11, 16),
        hijriDate: '',
        isRamadan: false,
        times: <Prayer, PrayerTime>{
          Prayer.fajr: fajr,
        },
        provider: 'waqtazan',
        method: 'default',
        lastSynced: DateTime.now(),
        fromCache: false,
      );

      final engine = CountdownEngine(prayerTimes: times);
      // At 20:00, all prayers passed, next is tomorrow's Fajr
      final now = DateTime(2026, 11, 16, 20, 0);
      final next = engine.nextPrayerAt(now);
      expect(next.prayer, Prayer.fajr);
      expect(next.time.day, now.day + 1);
    });
  });

  group('PrayerTimesManager', () {
    test('selects provider and method', () {
      final manager = PrayerTimesManager();
      expect(manager.selectedProviderId, 'waqtazan');

      manager.selectProvider('aladhan');
      expect(manager.selectedProviderId, 'aladhan');

      manager.selectMethod('21');
      expect(manager.selectedMethod, '21');
    });

    test('rejects unknown provider', () {
      final manager = PrayerTimesManager();
      expect(() => manager.selectProvider('unknown'),
          throwsA(isArgumentError));
    });

    test('returns available methods', () {
      final manager = PrayerTimesManager();
      final methods = manager.availableMethods();
      expect(methods.length, greaterThan(0));
      expect(methods.any((m) => m.id == '21' && m.providerId == 'aladhan'),
          isTrue);
    });
  });
}
