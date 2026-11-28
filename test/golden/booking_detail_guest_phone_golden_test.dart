// Pixel lock for the PROVIDER view of «Деталі запису»'s client block.
//
// History: Phase 417 / M519 locked a guest-phone / client-phone ContactTile
// row here. 2026-11-21 (user) the detail shows NO phone for any role (the
// phone lives on the client card), so these baselines now lock the NO-PHONE
// layout. Since the 2026-11-22 audit (CLI-D08) `Booking` cannot carry a
// phone at all, so the fixtures hold none; the render is unchanged. The
// client strip is tappable (→ client card) but pixel-identical at rest: the
// `salon_master` baseline (which never had a row) passed UNCHANGED through
// that change and is the regression proof.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_client_feedback_screen.dart';

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
  // Backend 397: a LINK guest with a verified phone is blockable for an
  // independent master, so the strip carries its «⋯».
  clientBlockable: true,
);

// M519 — a registered client (clientId set). Its phone is not mapped into
// `Booking` at all (CLI-D08), so no fixture can carry one.
final Booking _registered = _guest.copyWith(clientId: 'c1');

// The same registered client on a SALON booking — the owner / admin / salon
// master views.
final Booking _registeredSalon = _registered.copyWith(
  masterType: 'SALON_MASTER',
  salonName: 'Студія Ліра',
  salonId: 'salon-1',
);

// M569 (CLI-101) — a LINK guest with a phone-keyed rating (B546): the strip
// shows its ★ readout like any registered client.
final Booking _ratedGuest = _guest.copyWith(
  clientAvgRating: 4.7,
  clientReviewCount: 3,
);

// M569 (CLI-101 / CLI-D20) — the client-review compose heads with the SAME
// shared strip (visit line as its sub-line); a COMPLETED, reviewable visit.
final Booking _composeBase = _guest.copyWith(
  status: BookingStatus.completed,
  providerCanReviewClient: true,
);

void main() {
  const double width = 360;

  goldenTest(
    'booking detail — LINK guest with a phone-keyed rating shows its ★ (M569)',
    fileName: 'booking_detail_rated_guest_360_1x',
    constraints: BoxConstraints.tight(const Size(width, 900)),
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        authProvider.overrideWith(
          () => FixedRoleAuth(UserRole.independentMaster),
        ),
        bookingDetailProvider('b1').overrideWith((ref) async => _ratedGuest),
      ],
    ),
    builder: () => const BookingDetailScreen(bookingId: 'b1'),
  );

  final List<(String, Booking)> composeCases = <(String, Booking)>[
    (
      'registered_rated',
      _composeBase.copyWith(
        clientId: 'c1',
        clientAvgRating: 4.8,
        clientReviewCount: 5,
      ),
    ),
    (
      'guest_rated',
      _composeBase.copyWith(clientAvgRating: 4.2, clientReviewCount: 3),
    ),
    ('unrated', _composeBase.copyWith(clientId: 'c1')),
  ];
  for (final (String slug, Booking booking) in composeCases) {
    goldenTest(
      'client-review compose — shared client strip header ($slug, M569)',
      fileName: 'client_review_compose_strip_${slug}_360_1x',
      constraints: BoxConstraints.tight(const Size(width, 760)),
      pumpWidget: goldenPumpWidget(
        width: width,
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          authProvider.overrideWith(
            () => FixedRoleAuth(UserRole.independentMaster),
          ),
          bookingDetailProvider('b1').overrideWith((ref) async => booking),
        ],
      ),
      builder: () => const LeaveClientFeedbackScreen(bookingId: 'b1'),
    );
  }

  goldenTest(
    'booking detail — guest, no phone row (independent master)',
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

  final List<(String, UserRole, Booking)> registeredCases =
      <(String, UserRole, Booking)>[
        ('independent_master', UserRole.independentMaster, _registered),
        ('salon_owner', UserRole.salonOwner, _registeredSalon),
        ('salon_admin', UserRole.salonAdmin, _registeredSalon),
        ('salon_master', UserRole.salonMaster, _registeredSalon),
      ];
  for (final (String slug, UserRole role, Booking booking) in registeredCases) {
    goldenTest(
      'booking detail — registered client, no phone row ($slug)',
      fileName: 'booking_detail_client_phone_${slug}_360_1x',
      constraints: BoxConstraints.tight(const Size(width, 1000)),
      pumpWidget: goldenPumpWidget(
        width: width,
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          authProvider.overrideWith(() => FixedRoleAuth(role)),
          bookingDetailProvider('b1').overrideWith((ref) async => booking),
        ],
      ),
      builder: () => const BookingDetailScreen(bookingId: 'b1'),
    );
  }
}
