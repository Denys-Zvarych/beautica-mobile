// Phase 15.1 — Unit tests for [ScheduleRange] family-key normalisation.
//
// Locks the H1 family-key fix: a range built from a DateTime carrying
// wall-clock time-of-day must equal (==/hashCode) the date-only range for the
// same window, so the Riverpod family cache resolves the same instance instead
// of thrashing and firing duplicate fetches.

import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScheduleRange — construction-time date-only normalisation', () {
    test(
      'a DateTime.now()-style value equals the date-only range (==/hashCode)',
      () {
        // Simulates a `DateTime.now()` with wall-clock time (13:47:09.123).
        final withTime = ScheduleRange(
          from: DateTime(2026, 6, 1, 13, 47, 9, 123),
          to: DateTime(2026, 6, 30, 23, 59, 59, 999),
        );
        final dateOnly = ScheduleRange(
          from: DateTime(2026, 6, 1),
          to: DateTime(2026, 6, 30),
        );

        expect(withTime, equals(dateOnly));
        expect(withTime.hashCode, dateOnly.hashCode);
        // The stored bounds are truncated to local midnight.
        expect(withTime.from, DateTime(2026, 6, 1));
        expect(withTime.to, DateTime(2026, 6, 30));
      },
    );

    test(
      'ScheduleRange.month keys identically to the explicit date-only range',
      () {
        final viaMonth = ScheduleRange.month(DateTime(2026, 6, 15, 8, 30));
        final explicit = ScheduleRange(
          from: DateTime(2026, 6, 1),
          to: DateTime(2026, 6, 30),
        );

        expect(viaMonth, equals(explicit));
        expect(viaMonth.hashCode, explicit.hashCode);
      },
    );

    test('different windows are not equal', () {
      final june = ScheduleRange(
        from: DateTime(2026, 6, 1),
        to: DateTime(2026, 6, 30),
      );
      final july = ScheduleRange(
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 31),
      );
      expect(june, isNot(equals(july)));
    });

    test('normalised getter is an identity no-op', () {
      final r = ScheduleRange(
        from: DateTime(2026, 6, 1),
        to: DateTime(2026, 6, 30),
      );
      expect(r.normalised, equals(r));
    });
  });
}
