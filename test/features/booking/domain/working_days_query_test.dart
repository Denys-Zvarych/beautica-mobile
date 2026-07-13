// Phase 14.20 — Unit tests for [WorkingDaysQuery] (the family key backing
// `workingDaysProvider`).
//
// Pure Dart: no ProviderScope, no widget tree. These pin the two properties the
// Phase 14.20 fix leans on:
//   1. `serviceId` participates in `==`/`hashCode`, so the availability-aware
//      calendar query (serviceId present) and the schedule-shape query
//      (serviceId absent) resolve to DISTINCT Riverpod family members and never
//      collide in the provider cache — if they shared a cache entry, the master
//      schedule UI (schedule-shape) and the booking calendar (service-scoped)
//      could serve each other stale `working` verdicts.
//   2. Construction-time date-only normalisation keeps two windows covering the
//      same calendar dates `==`-equal regardless of time-of-day, AND carries the
//      serviceId straight through — the property the family-caching design in
//      the class doc depends on.
// Plus the structural bound behind the backend's 62-day service-scoped cap: a
// `.month` window is at most one calendar month wide, always well under 62 days.

import 'package:beautica_mobile/features/booking/domain/working_days_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const masterId = 'master-1';
  final DateTime jul1 = DateTime(2026, 7, 1);
  final DateTime jul31 = DateTime(2026, 7, 31);

  group('WorkingDaysQuery — serviceId in equality/hashCode', () {
    test('two queries differing ONLY by serviceId are NOT equal (distinct '
        'family members → no cache collision between the two modes)', () {
      final withService = WorkingDaysQuery(
        masterId: masterId,
        from: jul1,
        to: jul31,
        serviceId: 'svc-1',
      );
      final scheduleShape = WorkingDaysQuery(
        masterId: masterId,
        from: jul1,
        to: jul31,
        // serviceId omitted → schedule-shape mode.
      );

      expect(
        withService == scheduleShape,
        isFalse,
        reason:
            'the availability-aware query and the schedule-shape query must be '
            'unequal so they key SEPARATE workingDaysProvider family members',
      );
      expect(withService.hashCode == scheduleShape.hashCode, isFalse);
    });

    test('two queries with DIFFERENT non-null serviceIds are not equal', () {
      final svc1 = WorkingDaysQuery(
        masterId: masterId,
        from: jul1,
        to: jul31,
        serviceId: 'svc-1',
      );
      final svc2 = WorkingDaysQuery(
        masterId: masterId,
        from: jul1,
        to: jul31,
        serviceId: 'svc-2',
      );

      expect(svc1 == svc2, isFalse);
      expect(svc1.hashCode == svc2.hashCode, isFalse);
    });

    test('two queries with the SAME serviceId (and same masterId/range) are '
        'equal with equal hashCode — the family-cache hit path', () {
      final a = WorkingDaysQuery(
        masterId: masterId,
        from: jul1,
        to: jul31,
        serviceId: 'svc-1',
      );
      final b = WorkingDaysQuery(
        masterId: masterId,
        from: jul1,
        to: jul31,
        serviceId: 'svc-1',
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('two schedule-shape queries (both serviceId null) are equal — the '
        'salon step-3 picker still shares one cache entry', () {
      final a = WorkingDaysQuery(masterId: masterId, from: jul1, to: jul31);
      final b = WorkingDaysQuery(masterId: masterId, from: jul1, to: jul31);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('WorkingDaysQuery — construction-time date-only normalisation', () {
    test('the public factory truncates time-of-day on both bounds and carries '
        'serviceId through, so two same-date windows stay ==-equal', () {
      final withTime = WorkingDaysQuery(
        masterId: masterId,
        from: DateTime(2026, 7, 1, 13, 45, 30),
        to: DateTime(2026, 7, 31, 23, 59, 59),
        serviceId: 'svc-1',
      );
      final dateOnly = WorkingDaysQuery(
        masterId: masterId,
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 31),
        serviceId: 'svc-1',
      );

      expect(withTime.from, DateTime(2026, 7, 1));
      expect(withTime.to, DateTime(2026, 7, 31));
      expect(withTime.serviceId, 'svc-1');
      expect(
        withTime,
        dateOnly,
        reason:
            'time-of-day must be discarded so the family key is stable — a '
            'differing HH:mm must not fork the provider cache',
      );
    });
  });

  group('WorkingDaysQuery.month', () {
    test('spans the first → last day of the containing month (date-only) and '
        'propagates serviceId', () {
      final q = WorkingDaysQuery.month(
        masterId: masterId,
        anyDayInMonth: DateTime(2026, 7, 15, 9, 30),
        serviceId: 'svc-9',
      );

      expect(q.from, DateTime(2026, 7, 1));
      expect(q.to, DateTime(2026, 7, 31));
      expect(q.serviceId, 'svc-9');
    });

    test(
      'omitting serviceId yields the schedule-shape window (serviceId null)',
      () {
        final q = WorkingDaysQuery.month(
          masterId: masterId,
          anyDayInMonth: DateTime(2026, 7, 15),
        );

        expect(q.serviceId, isNull);
      },
    );

    test('a service-scoped and schedule-shape month window for the SAME month '
        'are still distinct family members', () {
      final scoped = WorkingDaysQuery.month(
        masterId: masterId,
        anyDayInMonth: DateTime(2026, 7, 10),
        serviceId: 'svc-1',
      );
      final shape = WorkingDaysQuery.month(
        masterId: masterId,
        anyDayInMonth: DateTime(2026, 7, 20),
      );

      expect(scoped == shape, isFalse);
    });

    test('resolves February correctly (leap-year-agnostic last day)', () {
      final q = WorkingDaysQuery.month(
        masterId: masterId,
        anyDayInMonth: DateTime(2026, 2, 10),
      );

      expect(q.from, DateTime(2026, 2, 1));
      // 2026 is not a leap year → Feb has 28 days.
      expect(q.to, DateTime(2026, 2, 28));
    });

    test('any .month window is at most one calendar month wide — structurally '
        'under the backend 62-day service-scoped cap (no mobile-side guard '
        'needed)', () {
      // Sweep every month of a year (the widest is 31 days inclusive).
      for (int month = 1; month <= 12; month++) {
        final q = WorkingDaysQuery.month(
          masterId: masterId,
          anyDayInMonth: DateTime(2026, month, 15),
          serviceId: 'svc-1',
        );
        final int inclusiveDays = q.to.difference(q.from).inDays + 1;
        expect(
          inclusiveDays,
          lessThanOrEqualTo(62),
          reason:
              'month $month spans $inclusiveDays days — the calendar only ever '
              'fetches one visible month at a time, so it can never exceed the '
              'server cap; this is the structural bound the SlotDateScreen '
              'query relies on',
        );
        // Tighter real bound: no calendar month exceeds 31 days.
        expect(inclusiveDays, lessThanOrEqualTo(31));
      }
    });
  });
}
