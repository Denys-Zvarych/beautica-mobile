// Phase 350 — [BookingEntryArgs.autoAdvance] additive-field pin.
//
// `booking_entry_args.dart` had no unit test file before this phase (it was
// only ever exercised indirectly through `service_selector_sheet_test.dart`
// / `wishlist_rebook_test.dart`). This file pins the freezed contract
// directly: the new field defaults to `true` (so the pre-existing wish-list
// caller, which never sets it, keeps skipping Step 1 byte-for-byte) and an
// explicit `false` round-trips through the value + `copyWith` + equality.

import 'package:beautica_mobile/features/booking/domain/booking_entry_args.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BookingEntryArgs.autoAdvance', () {
    test('defaults to true when not passed — the wish-list rebook shape', () {
      const args = BookingEntryArgs(masterId: 'm1', preselectedServiceId: 's1');

      expect(args.autoAdvance, isTrue);
    });

    test('an explicit false round-trips — the past-booking rebook shape', () {
      const args = BookingEntryArgs(
        masterId: 'm1',
        preselectedServiceId: 's1',
        autoAdvance: false,
      );

      expect(args.autoAdvance, isFalse);
      expect(args.masterId, 'm1');
      expect(args.preselectedServiceId, 's1');
    });

    test('copyWith preserves autoAdvance when not touched', () {
      const args = BookingEntryArgs(
        masterId: 'm1',
        preselectedServiceId: 's1',
        autoAdvance: false,
      );

      final BookingEntryArgs copy = args.copyWith(preselectedServiceId: 's2');

      expect(copy.autoAdvance, isFalse);
      expect(copy.preselectedServiceId, 's2');
    });

    test('two instances with the same fields (including the default) are '
        'equal — freezed value equality', () {
      const BookingEntryArgs a = BookingEntryArgs(
        masterId: 'm1',
        preselectedServiceId: 's1',
      );
      const BookingEntryArgs b = BookingEntryArgs(
        masterId: 'm1',
        preselectedServiceId: 's1',
        autoAdvance: true,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
