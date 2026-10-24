// Phase 417 — pixel lock for the guest-phone ContactTile row on the PROVIDER
// view of «Деталі запису» (guest booking, independent master).
//
// NEW baselines only. `ContactTile` itself is UNCHANGED in this phase (its
// `onTap` was already a constructor parameter), so every existing ContactTile
// golden is re-run untouched as the regression proof.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';

import '../helpers/fakes/fake_notification_repository.dart' show FixedRoleAuth;
import 'helpers/golden_pump.dart';

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

// A far-future, fixed instant: deterministic labels, never `isPast`.
final DateTime _start = DateTime(2099, 3, 14, 10);

final Booking _guest = Booking(
  id: 'b1',
  masterId: 'm1',
  masterFirstName: 'Марія',
  masterLastName: 'Іванюк',
  masterType: 'INDEPENDENT_MASTER',
  clientFirstName: 'Ірина',
  clientLastName: 'Коваль',
  guestPhone: '+380671234567',
  serviceId: 's1',
  serviceName: 'Манікюр з покриттям',
  categoryName: 'NAIL_SERVICE',
  cityLabel: 'Львів',
  durationMinutes: 90,
  price: 650,
  startAt: _start,
  endAt: _start.add(const Duration(minutes: 90)),
  status: BookingStatus.confirmed,
  canReview: false,
);

void main() {
  const double width = 360;

  goldenTest(
    'booking detail — guest phone row (independent master)',
    fileName: 'booking_detail_guest_phone_360_1x',
    constraints: BoxConstraints.tight(const Size(width, 900)),
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        authProvider.overrideWith(
          () => FixedRoleAuth(UserRole.independentMaster),
        ),
        bookingDetailProvider('b1').overrideWith((ref) async => _guest),
      ],
    ),
    builder: () => const BookingDetailScreen(bookingId: 'b1'),
  );
}
