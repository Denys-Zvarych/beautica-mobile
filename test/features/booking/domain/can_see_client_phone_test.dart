// M510 — `canSeeClientPhone(role)`: the ONE role gate for a client's phone,
// extracted from `BookingDisplayX.guestPhoneFor` (parity: booking detail keeps
// calling it). It takes NO client kind, so a guest-vs-registered check cannot
// hide in it; the card widget test pins that both kinds render the chip.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('true for independent master, salon owner, salon admin', () {
    expect(canSeeClientPhone(UserRole.independentMaster), isTrue);
    expect(canSeeClientPhone(UserRole.salonOwner), isTrue);
    expect(canSeeClientPhone(UserRole.salonAdmin), isTrue);
  });

  test('false for salon master, client and an unresolved session', () {
    expect(canSeeClientPhone(UserRole.salonMaster), isFalse);
    expect(canSeeClientPhone(UserRole.client), isFalse);
    expect(canSeeClientPhone(null), isFalse);
  });

  test('every role is classified (a new role must be decided here)', () {
    for (final UserRole r in UserRole.values) {
      expect(
        canSeeClientPhone(r),
        <UserRole>{
          UserRole.independentMaster,
          UserRole.salonOwner,
          UserRole.salonAdmin,
        }.contains(r),
        reason: '$r',
      );
    }
  });
}
