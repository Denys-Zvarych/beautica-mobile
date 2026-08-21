// Phase 258 — unit tests for the walk-in guest seed additions on the three
// freezed args classes that thread the CLIENT booking chain:
// `BookingSlotPickerArgs` -> `BookingConfirmArgs` -> `BookingSuccessArgs`.
//
// D3 of the phase doc: every new field is nullable-or-`false`, so no
// existing constructor invocation anywhere in `lib/`, `test/` or
// `integration_test/` gains an argument. This file pins the two directly
// testable halves of that promise:
//   1. the DEFAULT is `null`/`false` when the new fields are omitted;
//   2. two instances built the OLD way (new fields omitted on both) stay
//      `==` and share a `hashCode` — guards `slotPickerProvider` /
//      `workingDaysProvider` family keys against a silent cache split.
//
// The forwarding half (`SlotTimeScreen._confirm` carries `guest` /
// `hideMasterIdentity` onto the minted `BookingConfirmArgs`) is covered in
// `slot_picker_test.dart` (`should_forwardGuestAndHideFlag_when_
// slotTimeScreenConfirms` / `should_forwardNulls_when_clientPathConfirms`),
// not here — that needs a pumped widget tree, this file stays pure Dart.
//
// Pure Dart: no ProviderScope, no widget tree.

import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_success_args.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
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

// future-date-ok: fixed args fixture, never compared against isPast/now — only threaded through equality/hashCode/default assertions.
final DateTime _kStartAt = DateTime.utc(2026, 7, 20, 10);

const WalkInGuest _kGuest = WalkInGuest(
  name: 'Іван',
  surname: 'Петренко',
  phone: '+380501234567',
);

void main() {
  group('BookingSlotPickerArgs — walk-in seed defaults', () {
    test('should_defaultGuestToNull_when_slotPickerArgsBuiltWithoutIt', () {
      const BookingSlotPickerArgs args = BookingSlotPickerArgs(
        masterId: 'master-1',
        master: _kMaster,
        services: <MasterService>[_kService],
      );

      expect(args.guest, isNull);
      expect(args.hideMasterIdentity, isFalse);
    });

    test('should_stayValueEqual_when_newFieldsOmitted', () {
      const BookingSlotPickerArgs a = BookingSlotPickerArgs(
        masterId: 'master-1',
        master: _kMaster,
        services: <MasterService>[_kService],
      );
      const BookingSlotPickerArgs b = BookingSlotPickerArgs(
        masterId: 'master-1',
        master: _kMaster,
        services: <MasterService>[_kService],
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('guest is settable and does not disturb other fields', () {
      const BookingSlotPickerArgs args = BookingSlotPickerArgs(
        masterId: 'master-1',
        master: _kMaster,
        services: <MasterService>[_kService],
        guest: _kGuest,
        hideMasterIdentity: true,
      );

      expect(args.guest, _kGuest);
      expect(args.hideMasterIdentity, isTrue);
      expect(args.masterId, 'master-1');
    });
  });

  group('BookingConfirmArgs — walk-in seed defaults', () {
    test('defaults guest to null and hideMasterIdentity to false', () {
      final BookingConfirmArgs args = BookingConfirmArgs(
        masterId: 'master-1',
        master: _kMaster,
        services: const <MasterService>[_kService],
        startAt: _kStartAt,
        idempotencyKey: 'idem-1',
      );

      expect(args.guest, isNull);
      expect(args.hideMasterIdentity, isFalse);
    });

    test('two instances built the old way stay value-equal', () {
      BookingConfirmArgs build() => BookingConfirmArgs(
        masterId: 'master-1',
        master: _kMaster,
        services: const <MasterService>[_kService],
        startAt: _kStartAt,
        idempotencyKey: 'idem-1',
      );

      final BookingConfirmArgs a = build();
      final BookingConfirmArgs b = build();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('BookingSuccessArgs — walk-in seed defaults', () {
    test('should_defaultIsWalkInToFalse_when_successArgsBuiltWithoutIt', () {
      final BookingSuccessArgs args = BookingSuccessArgs(
        master: _kMaster,
        services: const <MasterService>[_kService],
        startAt: _kStartAt,
      );

      expect(args.isWalkIn, isFalse);
    });

    test('two instances built the old way stay value-equal', () {
      BookingSuccessArgs build() => BookingSuccessArgs(
        master: _kMaster,
        services: const <MasterService>[_kService],
        startAt: _kStartAt,
      );

      final BookingSuccessArgs a = build();
      final BookingSuccessArgs b = build();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('isWalkIn is settable independently of isReschedule', () {
      final BookingSuccessArgs args = BookingSuccessArgs(
        master: _kMaster,
        services: const <MasterService>[_kService],
        startAt: _kStartAt,
        isWalkIn: true,
      );

      expect(args.isWalkIn, isTrue);
      expect(args.isReschedule, isFalse);
    });
  });
}
