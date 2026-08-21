// Phase 27.2 follow-up — DIRECT unit coverage for `isBookingRescheduleSeed`.
//
// WHY THIS FILE EXISTS
// --------------------
// `isBookingRescheduleSeed` is the single discriminator that decides whether an
// INDEPENDENT_MASTER is admitted onto the four `clientOnlyGuard`-ed booking
// routes the reschedule flow traverses. Until now it was covered only
// TRANSITIVELY, through `booking_route_guard_test.dart`'s mounted-router
// assertions — which prove the two shapes the router happens to navigate with,
// and nothing about the predicate's own boundaries. In particular the
// DELIBERATE ASYMMETRY between the three accepted types is invisible there:
//
//   * `BookingSlotPickerArgs` / `BookingConfirmArgs` key off
//     `rescheduleBookingId != null` — they carry the id of the booking being
//     moved;
//   * `BookingSuccessArgs` keys off its own `isReschedule` BOOLEAN — that class
//     never carries the id, because the recap only needs the copy switch.
//
// Swapping either rule for the other reads as a harmless tidy-up and would keep
// every router test green for one of the two shapes while silently re-breaking
// the other. Pinning it here, table-driven, makes the asymmetry a fact of the
// suite rather than an accident of the router fixtures.
//
// The `_ => false` fallthrough is the SECURITY-relevant branch (see the source
// file's SEC note): `extra` is null for anything arriving from an external deep
// link, so an un-seeded navigation MUST fall through to the unchanged role
// bounce. `null` and a foreign type are both pinned below.
//
// Pure Dart — no widget tree, no Riverpod, no router.

import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_success_args.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/routing/booking_reschedule_seed.dart';
import 'package:flutter_test/flutter_test.dart';

const Master _kMaster = Master(
  id: 'master-1',
  firstName: 'Test',
  lastName: 'Master',
  avgRating: 0,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

const MasterService _kService = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'NAILS',
);

final DateTime _kStartAt = DateTime.utc(2026, 7, 20, 10);

BookingSlotPickerArgs _slotArgs({String? rescheduleBookingId}) =>
    BookingSlotPickerArgs(
      masterId: _kMaster.id,
      master: _kMaster,
      services: const <MasterService>[_kService],
      rescheduleBookingId: rescheduleBookingId,
    );

BookingConfirmArgs _confirmArgs({String? rescheduleBookingId}) =>
    BookingConfirmArgs(
      masterId: _kMaster.id,
      master: _kMaster,
      services: const <MasterService>[_kService],
      startAt: _kStartAt,
      idempotencyKey: 'idem-1',
      rescheduleBookingId: rescheduleBookingId,
    );

BookingSuccessArgs _successArgs({required bool isReschedule}) =>
    BookingSuccessArgs(
      master: _kMaster,
      services: const <MasterService>[_kService],
      startAt: _kStartAt,
      isReschedule: isReschedule,
    );

/// One row of the truth table below.
typedef _Case = ({String name, Object? extra, bool expected});

void main() {
  group('isBookingRescheduleSeed', () {
    final List<_Case> cases = <_Case>[
      // ── BookingSlotPickerArgs — keyed on `rescheduleBookingId`. ────────────
      (
        name:
            'BookingSlotPickerArgs with a non-null rescheduleBookingId is a '
            'reschedule seed',
        extra: _slotArgs(rescheduleBookingId: 'bkg-1'),
        expected: true,
      ),
      (
        name:
            'BookingSlotPickerArgs with a null rescheduleBookingId is a CREATE '
            'seed (step 2 of the client create flow)',
        extra: _slotArgs(),
        expected: false,
      ),
      // A visit-item reschedule seeds BOTH ids; the discriminator is still the
      // booking id, so the per-item shape must not read differently.
      (
        name:
            'BookingSlotPickerArgs for a VISIT-item reschedule (both ids set) '
            'is a reschedule seed',
        extra: BookingSlotPickerArgs(
          masterId: _kMaster.id,
          master: _kMaster,
          services: const <MasterService>[_kService],
          rescheduleBookingId: 'bkg-1',
          rescheduleAppointmentId: 'appt-1',
        ),
        expected: true,
      ),
      // Negative guard for the line above: an appointment id ALONE is not a
      // reschedule — `rescheduleBookingId` is the sole discriminator, and a
      // predicate that also accepted a bare appointment id would admit a shape
      // no caller ever produces.
      (
        name:
            'BookingSlotPickerArgs with ONLY rescheduleAppointmentId set is '
            'NOT a reschedule seed',
        extra: BookingSlotPickerArgs(
          masterId: _kMaster.id,
          master: _kMaster,
          services: const <MasterService>[_kService],
          rescheduleAppointmentId: 'appt-1',
        ),
        expected: false,
      ),

      // ── BookingConfirmArgs — same key, different type. ─────────────────────
      (
        name:
            'BookingConfirmArgs with a non-null rescheduleBookingId is a '
            'reschedule seed',
        extra: _confirmArgs(rescheduleBookingId: 'bkg-1'),
        expected: true,
      ),
      (
        name:
            'BookingConfirmArgs with a null rescheduleBookingId is a CREATE '
            'seed',
        extra: _confirmArgs(),
        expected: false,
      ),

      // ── BookingSuccessArgs — THE ASYMMETRY: a boolean, not an id. ──────────
      (
        name: 'BookingSuccessArgs with isReschedule true is a reschedule seed',
        extra: _successArgs(isReschedule: true),
        expected: true,
      ),
      (
        name:
            'BookingSuccessArgs with isReschedule false is a CREATE seed '
            '(the default)',
        extra: _successArgs(isReschedule: false),
        expected: false,
      ),

      // ── Fallthrough — the SEC-relevant branch. ─────────────────────────────
      (
        name:
            'null extra (an external deep link carries none) is NOT a '
            'reschedule seed',
        extra: null,
        expected: false,
      ),
      (
        name: 'an unrelated type is NOT a reschedule seed',
        extra: 'bkg-1',
        expected: false,
      ),
      (
        name: 'a bare Object is NOT a reschedule seed',
        extra: Object(),
        expected: false,
      ),
    ];

    for (final _Case c in cases) {
      test(c.name, () {
        expect(isBookingRescheduleSeed(c.extra), c.expected);
      });
    }

    // A cardinality ledger over the table itself: the two id-keyed types and
    // the one flag-keyed type must each contribute at least one TRUE and one
    // FALSE row, so a future edit cannot quietly drop half of a pair.
    test('every accepted type is pinned in BOTH directions', () {
      bool has(Type t, bool expected) => cases.any(
        (_Case c) =>
            c.extra.runtimeType.toString().contains('$t') &&
            c.expected == expected,
      );

      for (final Type t in <Type>[
        BookingSlotPickerArgs,
        BookingConfirmArgs,
        BookingSuccessArgs,
      ]) {
        expect(has(t, true), isTrue, reason: '$t has no admitted case');
        expect(has(t, false), isTrue, reason: '$t has no bounced case');
      }
      expect(
        cases.where((_Case c) => c.expected).length,
        4,
        reason:
            'exactly four shapes admit today — slot-picker (plain + visit '
            'item), confirm, success; adding a fifth is a deliberate widening '
            'of the guard and must be justified here',
      );
    });
  });
}
