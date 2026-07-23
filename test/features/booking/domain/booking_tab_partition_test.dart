// Phase 7.1 — the `BookingTab` → status-set partition, and the one member that
// must never appear in it: [BookingStatus.unknown].
//
// WHY THIS FILE EXISTS
// --------------------
// `BookingStatus.unknown` is a SECURITY fix (finding S1). Its whole contract is
// "keep the row visible, grant nothing", and the phase's own tests pin the
// individual capabilities it must not grant — `canAddToCalendar` is covered in
// `booking_display_x_test.dart`, the decode path in `booking_mapper_test.dart`,
// the wire-strip in `booking_repository_master_query_test.dart`.
//
// The one clause of that contract with NO test was **tab membership**: "never a
// member of any tab's or filter's status set" (`booking_status.dart`). That
// clause is what stops an unrecognised booking from being counted as
// «Майбутні» — i.e. from being presented to the master as an appointment they
// are expected to show up to — and from being serialised into the tab's
// `status=` query param, which the backend 400s on.
//
// It is also the clause most likely to be broken by an innocuous edit, because
// the natural way to widen a tab is `BookingStatus.values.where(...)`, and
// `values` carries `unknown` while `filterable` does not. A `.values`-based
// partition compiles, analyses clean, and puts `status=UNKNOWN` on the wire.
//
// The second group pins the partition's COMPLETENESS, which is the mirror-image
// bug: a real backend status that belongs to no tab is a booking the master can
// never see in «Мої записи» at all. `filterable` and the union of the three
// tabs must be the same set, in both directions.

import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';

void main() {
  Set<BookingStatus> unionOfAllTabs() => <BookingStatus>{
    for (final BookingTab t in BookingTab.values) ...t.statuses,
  };

  group('BookingStatus.unknown is in NO tab (security S1)', () {
    for (final BookingTab tab in BookingTab.values) {
      test('$tab excludes unknown', () {
        expect(
          tab.statuses,
          isNot(contains(BookingStatus.unknown)),
          reason:
              '$tab would present an unrecognised booking as one of its own '
              'and would serialise status=UNKNOWN, which the backend 400s',
        );
      });
    }

    test('the union of every tab excludes unknown', () {
      expect(unionOfAllTabs(), isNot(contains(BookingStatus.unknown)));
    });

    test('no tab is built from BookingStatus.values — every member of every '
        'tab is a real, filterable backend status', () {
      for (final BookingTab tab in BookingTab.values) {
        for (final BookingStatus s in tab.statuses) {
          expect(
            BookingStatus.filterable,
            contains(s),
            reason:
                '$tab carries $s, which is not a filterable backend status; a '
                '`.values`-based partition is the usual cause',
          );
        }
      }
    });

    test('an unknown-status booking is therefore NOT upcoming — it is not an '
        'appointment the master is told to show up to', () {
      expect(
        BookingTab.upcoming.statuses,
        <BookingStatus>{BookingStatus.confirmed},
        reason:
            'Майбутні is CONFIRMED-only since track 24.x auto-confirm; '
            'widening it to a denylist would sweep unknown in',
      );
    });
  });

  group('the partition is COMPLETE and DISJOINT', () {
    test('every filterable status belongs to exactly one tab', () {
      for (final BookingStatus s in BookingStatus.filterable) {
        final List<BookingTab> owners = BookingTab.values
            .where((BookingTab t) => t.statuses.contains(s))
            .toList();

        expect(
          owners,
          hasLength(1),
          reason:
              '$s is owned by $owners — a status in no tab is invisible in '
              '«Мої записи»; a status in two tabs is double-counted',
        );
      }
    });

    test('the tabs cover the whole filterable set and nothing more', () {
      expect(unionOfAllTabs(), BookingStatus.filterable.toSet());
    });

    test('the three tabs together enumerate exactly 5 statuses — the '
        'backend @Size(max = 5) cap', () {
      final int total = BookingTab.values
          .map((BookingTab t) => t.statuses.length)
          .reduce((int a, int b) => a + b);

      expect(
        total,
        5,
        reason:
            'disjoint + complete means the summed size equals filterable.length; '
            'if the backend enum grows, both this and the @Size cap must move',
      );
    });
  });

  group('unknown never reaches the wire from a tab', () {
    test('no tab serialises a status string the backend does not define', () {
      const Set<String> backendStatuses = <String>{
        'CONFIRMED',
        'COMPLETED',
        'DECLINED',
        'CANCELLED',
        'NOT_COMPLETED',
      };

      for (final BookingTab tab in BookingTab.values) {
        for (final BookingStatus s in tab.statuses) {
          expect(
            backendStatuses,
            contains(s.wireValue),
            reason: '$tab would send status=${s.wireValue}, a 400',
          );
        }
      }
    });

    test('`UNKNOWN` is not emitted by any tab', () {
      final Set<String> emitted = <String>{
        for (final BookingTab t in BookingTab.values)
          for (final BookingStatus s in t.statuses) s.wireValue,
      };

      expect(emitted, isNot(contains('UNKNOWN')));
      expect(emitted, hasLength(5));
    });
  });
}
