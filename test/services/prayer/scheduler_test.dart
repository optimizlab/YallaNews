import 'package:flutter_test/flutter_test.dart';

import '../../../lib/services/prayer/scheduler.dart';
import '../../../lib/models/prayer_times.dart';

void main() {
  group('AthanScheduler notificationId', () {
    test('is unique per prayer on the same day', () {
      final ids = <int>{};
      for (final prayer in kObligatoryPrayers) {
        ids.add(AthanScheduler.notificationId(
            DateTime(2026, 11, 15), prayer));
      }
      expect(ids.length, kObligatoryPrayers.length);
    });

    test('is unique across different days', () {
      final a = AthanScheduler.notificationId(
          DateTime(2026, 11, 15), Prayer.fajr);
      final b = AthanScheduler.notificationId(
          DateTime(2026, 11, 16), Prayer.fajr);
      expect(a, isNot(b));
    });

    test('is stable for the same date and prayer', () {
      final a = AthanScheduler.notificationId(
          DateTime(2026, 11, 15), Prayer.fajr);
      final b = AthanScheduler.notificationId(
          DateTime(2026, 11, 15), Prayer.fajr);
      expect(a, b);
    });

    test('starts in the 2000+ range', () {
      final id = AthanScheduler.notificationId(
          DateTime(2026, 11, 1), Prayer.fajr);
      expect(id, greaterThanOrEqualTo(2000));
    });
  });

  group('AthanScheduler alarmRequestCode', () {
    test('is unique per date and prayer', () {
      final codes = <int>{};
      for (final prayer in kObligatoryPrayers) {
        codes.add(AthanScheduler.alarmRequestCode(
            DateTime(2026, 11, 15), prayer));
      }
      expect(codes.length, kObligatoryPrayers.length);
    });

    test('differs across days for the same prayer', () {
      final a = AthanScheduler.alarmRequestCode(
          DateTime(2026, 11, 15), Prayer.fajr);
      final b = AthanScheduler.alarmRequestCode(
          DateTime(2026, 11, 16), Prayer.fajr);
      expect(a, isNot(b));
    });

    test('fits in a 32-bit signed int for far-future dates', () {
      final code = AthanScheduler.alarmRequestCode(
          DateTime(2035, 12, 31), Prayer.isha);
      expect(code, greaterThanOrEqualTo(0));
      expect(code, lessThan(1 << 31));
    });
  });

  group('AthanScheduler dayOfYearOf', () {
    test('returns 1 for January 1', () {
      expect(AthanScheduler.dayOfYearOf(DateTime(2026, 1, 1)), 1);
    });

    test('returns 365 for December 31 in a non-leap year', () {
      expect(AthanScheduler.dayOfYearOf(DateTime(2026, 12, 31)), 365);
    });

    test('returns 366 for December 31 in a leap year', () {
      expect(AthanScheduler.dayOfYearOf(DateTime(2024, 12, 31)), 366);
    });
  });
}
