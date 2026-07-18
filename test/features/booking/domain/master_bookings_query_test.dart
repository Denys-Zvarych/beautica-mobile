// Phase 7.1 — MasterBookingsQuery: the provider-family-key contract.
//
// Two properties are load-bearing and each guards a distinct bug:
//
//   1. STRUCTURAL EQUALITY — two independently-built identical queries must be
//      `==` (and share a hashCode), or `masterBookingsProvider` mints a fresh
//      family member (and a fresh network fetch, and a fresh cached page) on
//      every rebuild that reconstructs the query.
//   2. DATE NORMALISATION — the practical leak vector. A date picker hands
//      back time-bearing `DateTime`s, so two taps on the SAME calendar day at
//      different clock times would otherwise be two different keys.
//
// Plus canonical ordering, which is what makes the repository's emitted URL a
// pure function of the query's value (asserted in `booking_repository_test`).

import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/master_bookings_query.dart';

void main() {
  group('MasterBookingsQuery — structural equality (family-key contract)', () {
    test('two independently-built identical queries are == and share a '
        'hashCode', () {
      final a = MasterBookingsQuery.of(
        statuses: <BookingStatus>{
          BookingStatus.confirmed,
          BookingStatus.completed,
        },
        serviceIds: <String>{'svc-a', 'svc-b'},
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 31),
        sort: BookingSort.priceDesc,
      );
      final b = MasterBookingsQuery.of(
        statuses: <BookingStatus>{
          BookingStatus.confirmed,
          BookingStatus.completed,
        },
        serviceIds: <String>{'svc-a', 'svc-b'},
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 31),
        sort: BookingSort.priceDesc,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('the default query (no args) is == to another default query', () {
      expect(MasterBookingsQuery.of(), equals(MasterBookingsQuery.of()));
    });

    test('a different sort is a DIFFERENT key (sort is server-side, so it '
        'must refetch)', () {
      expect(
        MasterBookingsQuery.of(sort: BookingSort.newest),
        isNot(equals(MasterBookingsQuery.of(sort: BookingSort.priceAsc))),
      );
    });

    test('a different status set is a different key', () {
      expect(
        MasterBookingsQuery.of(
          statuses: <BookingStatus>{BookingStatus.confirmed},
        ),
        isNot(
          equals(
            MasterBookingsQuery.of(
              statuses: <BookingStatus>{BookingStatus.completed},
            ),
          ),
        ),
      );
    });

    test('a different date range is a different key', () {
      expect(
        MasterBookingsQuery.of(from: DateTime(2026, 7, 1)),
        isNot(equals(MasterBookingsQuery.of(from: DateTime(2026, 7, 2)))),
      );
    });
  });

  group('MasterBookingsQuery — DateTime normalisation (the leak guard)', () {
    test('same calendar day at different clock times yields EQUAL queries — '
        'one family member, not two', () {
      final morning = MasterBookingsQuery.of(
        from: DateTime(2026, 7, 18, 9, 14, 3, 221),
        to: DateTime(2026, 7, 25, 23, 59, 59, 999),
      );
      final afternoon = MasterBookingsQuery.of(
        from: DateTime(2026, 7, 18, 16, 42, 58, 7),
        to: DateTime(2026, 7, 25, 0, 0, 1),
      );

      expect(morning, equals(afternoon));
      expect(morning.hashCode, equals(afternoon.hashCode));
    });

    test('bounds are truncated to local midnight', () {
      final q = MasterBookingsQuery.of(
        from: DateTime(2026, 7, 18, 23, 59),
        to: DateTime(2026, 7, 25, 0, 30),
      );

      expect(q.from, DateTime(2026, 7, 18));
      expect(q.to, DateTime(2026, 7, 25));
    });

    test('a one-second-before-midnight `from` keeps its OWN day — it is not '
        'rounded up to the next one', () {
      final q = MasterBookingsQuery.of(from: DateTime(2026, 7, 18, 23, 59, 59));

      expect(q.from?.day, 18);
    });

    test('null bounds stay null (no filter)', () {
      final q = MasterBookingsQuery.of();

      expect(q.from, isNull);
      expect(q.to, isNull);
    });
  });

  group('MasterBookingsQuery — canonical ordering', () {
    test('statuses are sorted by enum index regardless of insertion order', () {
      final a = MasterBookingsQuery.of(
        statuses: <BookingStatus>{
          BookingStatus.notCompleted,
          BookingStatus.confirmed,
          BookingStatus.declined,
        },
      );
      final b = MasterBookingsQuery.of(
        statuses: <BookingStatus>{
          BookingStatus.declined,
          BookingStatus.notCompleted,
          BookingStatus.confirmed,
        },
      );

      expect(a.statuses, <BookingStatus>[
        BookingStatus.confirmed,
        BookingStatus.declined,
        BookingStatus.notCompleted,
      ]);
      expect(a.statuses, equals(b.statuses));
      expect(a, equals(b));
    });

    test('serviceIds are sorted lexicographically regardless of insertion '
        'order', () {
      final a = MasterBookingsQuery.of(
        serviceIds: <String>{'zebra', 'alpha', 'middle'},
      );
      final b = MasterBookingsQuery.of(
        serviceIds: <String>{'middle', 'zebra', 'alpha'},
      );

      expect(a.serviceIds, <String>['alpha', 'middle', 'zebra']);
      expect(a, equals(b));
    });

    test('the canonicalised lists are unmodifiable — a caller cannot mutate a '
        'live family key out from under Riverpod', () {
      final q = MasterBookingsQuery.of(
        statuses: <BookingStatus>{BookingStatus.confirmed},
        serviceIds: <String>{'svc-a'},
      );

      expect(
        () => q.statuses.add(BookingStatus.declined),
        throwsUnsupportedError,
      );
      expect(() => q.serviceIds.add('svc-b'), throwsUnsupportedError);
    });

    test('mutating the caller\'s source sets afterwards does not rewrite the '
        'query', () {
      final Set<String> src = <String>{'svc-a'};
      final q = MasterBookingsQuery.of(serviceIds: src);

      src.add('svc-b');

      expect(q.serviceIds, <String>['svc-a']);
    });
  });

  group('MasterBookingsQuery.hasFilters', () {
    test('a default query has no filters', () {
      expect(MasterBookingsQuery.of().hasFilters, isFalse);
    });

    test('sort alone is NOT a filter — it reorders, it never hides a row', () {
      expect(
        MasterBookingsQuery.of(sort: BookingSort.priceAsc).hasFilters,
        isFalse,
      );
    });

    test('each of statuses / serviceIds / from / to counts as a filter', () {
      expect(
        MasterBookingsQuery.of(
          statuses: <BookingStatus>{BookingStatus.confirmed},
        ).hasFilters,
        isTrue,
      );
      expect(
        MasterBookingsQuery.of(serviceIds: <String>{'svc-a'}).hasFilters,
        isTrue,
      );
      expect(
        MasterBookingsQuery.of(from: DateTime(2026, 7, 1)).hasFilters,
        isTrue,
      );
      expect(
        MasterBookingsQuery.of(to: DateTime(2026, 7, 1)).hasFilters,
        isTrue,
      );
    });
  });
}
