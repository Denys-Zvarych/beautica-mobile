// Phase 7.2 — `BookingDetailScreen` must acquire/release the app-wide
// `ScreenProtectionManager` (mobile-qa audit finding, Phase 7.2/7.6).
//
// WHY THIS FILE EXISTS
// --------------------
// `master_bookings_screen.dart` has this pinned
// (`master_bookings_screen_test.dart` → "acquires on mount and releases on
// dispose"). Its sibling — the detail screen the master pushes FROM it — did
// not. Every existing detail test overrides `screenProtectionProvider` with a
// NO-OP (`_NoOpScreenProtection`, in three separate files), which is correct
// for those tests and means precisely nothing was left asserting that the real
// manager is ever touched.
//
// Deleting `ref.read(screenProtectionProvider)..acquire()` from
// `BookingDetailScreen.initState` therefore fails NOTHING today, while the
// detail screen is the HEAVIER PII surface of the pair: the list shows a client
// name and a service, the detail adds the free-text notes — `clientComment`,
// `clientCancellationNote`, `providerComment` — which are mutually visible by
// locked product decision and are exactly what a screenshot in a task
// switcher, or a screen recorder, should not capture.
//
// The RELEASE half matters as much as the acquire: a leaked acquire leaves
// FLAG_SECURE on for the rest of the session, which is not a security failure
// but is a user-visible one (screenshots silently stop working app-wide).
//
// Asserted for BOTH viewer roles — the protection is a property of the SCREEN,
// not of the branch it renders, and a future refactor that moved the acquire
// inside a role branch would be caught here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

class _CountingScreenProtection extends ScreenProtectionManager {
  int acquires = 0;
  int releases = 0;

  @override
  void acquire() => acquires++;

  @override
  void release() => releases++;
}

class _StubAuth extends AuthNotifier {
  _StubAuth(this._session);

  final AuthSession _session;

  @override
  Future<AuthSession> build() async => _session;
}

Booking _booking() {
  // Now-relative, never an absolute literal — see
  // `test/helpers/booking_fixture_dates.dart` for the time bomb this avoids.
  // This suite pumps «Деталі запису», whose affordances are gated on
  // `BookingDisplayX.isPast`, so an expired literal here is precisely the
  // 2026-07-20 incident's shape.
  final DateTime start = futureBookingStart();
  return Booking(
    id: 'b1',
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    clientId: 'c1',
    clientFirstName: 'Олена',
    clientLastName: 'Ковальчук',
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: BookingStatus.confirmed,
    canReview: false,
    // The free-text surface this protection exists for.
    clientComment: 'Алергія на гель-лак певної марки',
  );
}

void main() {
  for (final UserRole role in <UserRole>[
    UserRole.client,
    UserRole.independentMaster,
  ]) {
    testWidgets('«Деталі запису» acquires screen protection on mount and '
        'releases it on dispose (${role.name} viewer)', (tester) async {
      final _CountingScreenProtection protection = _CountingScreenProtection();
      final Booking booking = _booking();

      await tester.pumpApp(
        BookingDetailScreen(bookingId: booking.id),
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(protection),
          bookingDetailProvider(
            booking.id,
          ).overrideWith((ref) async => booking),
          authProvider.overrideWith(
            () => _StubAuth(
              AuthSession.authenticated(
                user: User(id: 'u1', email: 'u@e.com', role: role),
                accessToken: 't',
              ),
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        protection.acquires,
        1,
        reason:
            'the booking detail renders free-text notes and a counterparty '
            'name — it must hold FLAG_SECURE for its lifetime, exactly as the '
            'list screen that pushes it does',
      );
      expect(protection.releases, 0, reason: 'nothing has been disposed yet');

      // Tear the screen down the way a pop does.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(
        protection.releases,
        1,
        reason:
            'a leaked acquire leaves screenshot blocking on for the rest of '
            'the session — app-wide, long after the PII surface is gone',
      );
    });
  }
}
