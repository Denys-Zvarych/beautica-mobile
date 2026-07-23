// Phase 7.8 — the `BookingSort` SURVIVAL guard.
//
// Phase 7.8 retired sorting as a user-facing feature: no sheet, no button, no
// screen state, and no `sort` on `MasterBookingsQuery`. What it did NOT do is
// delete the enum, because the shipped CLIENT «Мої записи» tabs order
// themselves with it (`MyBookingsNotifier`) and that ordering has NO UI.
//
// That combination is the hazard this file exists for. To a later reader,
// `BookingSort` looks like leftover scaffolding from a feature that was
// removed — the natural next cleanup is "the sort UI is gone, so this enum is
// dead too". It is not dead, and nothing on screen would reveal the mistake.
//
// Two directions are pinned here, and they fail differently:
//
//   • REMOVING a member — caught by the compiler at `MyBookingsNotifier`'s
//     ternary, so this guard is belt-and-braces for that direction. Kept
//     anyway: it names the invariant at the enum, where a would-be deleter is
//     actually looking, instead of leaving them to infer it from a compile
//     error two layers away.
//
//   • ADDING a member — NOT caught anywhere else. It compiles cleanly, and
//     `booking_repository_master_query_test.dart:405` iterates
//     `BookingSort.values` but asserts `anyOf('startsAt', 'priceAtBooking')`,
//     so a re-added `priceAtBooking,*` member passes there too. Re-adding a
//     price member is precisely what Phase 7.8 removed and what backend Phase
//     26.8's narrowed whitelist will answer with an HTTP 400. This file is the
//     only thing standing between that and production.
//
// Pure Dart: no Flutter imports, no widgets, no providers.

import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';

void main() {
  group('BookingSort survives Phase 7.8 with exactly two members', () {
    test('the enum is exactly {newest, oldest} — no more, no fewer', () {
      expect(
        BookingSort.values,
        <BookingSort>[BookingSort.newest, BookingSort.oldest],
        reason:
            'Phase 7.8 pruned the price members and kept these two because '
            'MyBookingsNotifier orders the shipped client tabs with them. '
            'A member ADDED here compiles silently and, once backend Phase '
            '26.8 narrows the sort whitelist to startsAt, 400s in production.',
      );
    });

    test('every member orders by startsAt — the one whitelisted property', () {
      for (final BookingSort s in BookingSort.values) {
        expect(
          s.wireValue.split(',').first,
          'startsAt',
          reason:
              '$s targets "${s.wireValue.split(',').first}". Backend Phase '
              '26.8 narrows the whitelist to startsAt alone, so anything '
              'else is an HTTP 400, not a silently-ignored param.',
        );
      }
    });

    // The wire values themselves, pinned at the enum rather than only at the
    // call sites. `MyBookingsNotifier`'s tabs have no UI, so a swapped
    // direction here ships a backwards list with nothing on screen to betray
    // it — see the wireValue assertions in `my_bookings_notifier_test.dart`.
    test('newest is descending and oldest is ascending — not swapped', () {
      expect(BookingSort.newest.wireValue, 'startsAt,desc');
      expect(BookingSort.oldest.wireValue, 'startsAt,asc');
    });
  });
}
