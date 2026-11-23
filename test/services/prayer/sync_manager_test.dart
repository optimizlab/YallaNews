import 'package:flutter_test/flutter_test.dart';

import '../../../lib/services/prayer/sync_manager.dart';

void main() {
  group('AthanSyncManager month rollover', () {
    test('nextMonthOf advances within a year', () {
      final (int year, int month) = AthanSyncManager.nextMonthOf(
          DateTime(2026, 11, 15));
      expect(year, 2026);
      expect(month, 12);
    });

    test('nextMonthOf rolls over from December to January', () {
      final (int year, int month) = AthanSyncManager.nextMonthOf(
          DateTime(2026, 12, 25));
      expect(year, 2027);
      expect(month, 1);
    });

    test('previousMonthOf retreats within a year', () {
      final (int year, int month) = AthanSyncManager.previousMonthOf(
          DateTime(2026, 12, 15));
      expect(year, 2026);
      expect(month, 11);
    });

    test('previousMonthOf rolls over from January to December', () {
      final (int year, int month) = AthanSyncManager.previousMonthOf(
          DateTime(2027, 1, 5));
      expect(year, 2026);
      expect(month, 12);
    });

    test('next and previous are inverses', () {
      final now = DateTime(2026, 11, 22);
      final next = AthanSyncManager.nextMonthOf(now);
      final prev = AthanSyncManager.previousMonthOf(
          DateTime(next.$1, next.$2, 1));
      expect(prev.$1, now.year);
      expect(prev.$2, now.month);
    });
  });
}
