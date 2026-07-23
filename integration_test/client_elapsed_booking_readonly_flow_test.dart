// Elapsed read-only track — E2E: a CONFIRMED booking whose slot has already
// ELAPSED renders «Деталі запису» READ-ONLY.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// The widget tier proves the elapsed gate in isolation (booking_detail_screen_test
// «CONFIRMED but ELAPSED — read-only») and the getter in isolation
// (booking_display_x_test «isPast»). NEITHER proves the REAL journey wired
// together: the CLIENT opens a CONFIRMED-but-past booking through the live
// shell + router + repository against the FakeBackend, and the detail comes
// back with the reschedule / cancel / add-to-calendar affordances GONE and only
// «Записатись знову» offered.
//
// The sibling `client_my_bookings_cancel_flow` already boots the SAME detail
// screen for a NON-elapsed CONFIRMED booking (reschedule + cancel + calendar
// all present), so this file is the elapsed counterpart on the identical
// harness: the seed booking's window is pushed firmly into the past, which is
// the ONLY difference that drives the read-only branch.
//
// `BookingDisplayX.isPast` compares `endAt` against the REAL device clock
// (`DateTime.now()`), not the harness `clockProvider`, so the seed window is a
// fixed year-2020 instant — elapsed regardless of the runner's wall clock.
//
// KEY POLICY (AppHarness): all TAPS are key-based; Ukrainian text appears in
// CONTENT ASSERTIONS only, and status copy is asserted through l10n.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  AppLocalizations l10nOf(WidgetTester tester, Type screen) =>
      AppLocalizations.of(tester.element(find.byType(screen)));

  testWidgets(
    'CLIENT opens an ELAPSED CONFIRMED booking and its detail is read-only — '
    'reschedule, cancel and add-to-calendar are gone, only «Записатись знову» '
    'is offered',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      // Push the seeded `booking-1` window firmly into the past BEFORE boot, so
      // the detail fetch returns an elapsed CONFIRMED booking. Status is still
      // CONFIRMED (elapsed is a presentation-only signal, not a status change),
      // so it still partitions into Майбутні and stays tappable.
      fb.bookingStartsAt = '2020-01-01T10:00:00Z';
      fb.bookingEndsAt = '2020-01-01T11:30:00Z';

      final GoRouter router = await AppHarness.boot(tester, fb);

      // Cold start → /login.
      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
      await AppHarness.loginAs(tester, fb, UserRole.client);

      // Open the Записи branch (bottom-nav tile 3).
      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientBookings);
      expect(find.byType(MyBookingsScreen), findsOneWidget);

      // The CONFIRMED booking is present in Майбутні (elapsed ≠ a status move).
      expect(find.byType(BookingCard), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('service-booking-1')),
        findsOneWidget,
      );

      // Open «Деталі запису».
      await tester.tap(find.byType(BookingCard));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.bookingDetail('booking-1'));
      expect(find.byType(BookingDetailScreen), findsOneWidget);

      // READ-ONLY: the three CONFIRMED affordances are all suppressed because
      // the slot elapsed against the device clock.
      expect(
        find.byKey(const Key('booking-detail-reschedule')),
        findsNothing,
        reason: 'an elapsed booking cannot be rescheduled',
      );
      expect(
        find.byKey(const Key('booking-detail-cancel')),
        findsNothing,
        reason: 'an elapsed booking cannot be cancelled',
      );
      expect(
        find.byKey(const Key('booking-detail-add-calendar')),
        findsNothing,
        reason: 'adding a past event to the calendar is pointless',
      );

      // Only «Записатись знову» is offered (the terminal/elapsed affordance).
      final AppLocalizations detailL10n = l10nOf(tester, BookingDetailScreen);
      expect(
        find.text(detailL10n.bookingDetailRebookCta),
        findsOneWidget,
        reason:
            'the read-only elapsed booking offers rebooking as its only '
            'forward action',
      );

      // Opening the read-only detail must not have mutated the booking.
      expect(fb.bookingStatus, 'CONFIRMED');
      expect(fb.cancelBookingCalls, 0);
      expect(fb.rescheduleBookingCalls, 0);
    },
  );
}
