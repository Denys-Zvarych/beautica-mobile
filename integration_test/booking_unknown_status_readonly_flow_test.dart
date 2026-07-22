// Phase 7.1 / security S1 — E2E: a booking whose wire status this build does
// NOT recognise stays VISIBLE but grants NOTHING.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// Phase 7.1 is mostly a master-side QUERY layer with no screen of its own until
// Phase 7.6, so most of it genuinely cannot be driven end-to-end yet. One part
// of it can, and it is the part with the highest cost of being wrong: the
// `BookingStatus.unknown` decode contract, which this phase both introduced and
// then re-pointed on a security finding.
//
// That contract crosses every layer of the app, and each layer is currently
// pinned only in ISOLATION:
//
//   * `booking_status_test` / `booking_mapper_test` — the decode keeps the row
//     as `unknown` rather than throwing (which used to DROP it) and rather than
//     falling back to `confirmed` (which used to over-grant).
//   * `booking_display_x_test` — `canAddToCalendar` is false for `unknown`.
//   * `booking_detail_screen_test` — the `unknown` branch renders rebook-only
//     actions.
//
// None of them proves the JOURNEY: that a real `GET /bookings/{id}` carrying a
// status string this build has never seen travels through the real Dio, the
// real mapper, the real notifier and the real router, and arrives at a «Деталі
// запису» that renders at all — and that renders WITHOUT reschedule, WITHOUT
// cancel and WITHOUT add-to-calendar.
//
// Both historical failure modes are silent and neither is a crash:
//
//   * The pre-7.1 behaviour threw, and `BookingMapper.fromDtoList`'s
//     `on Failure { continue; }` swallowed the throw and DROPPED the row. The
//     booking simply vanished from «Мої записи» — invisible, unrecoverable, and
//     the provider could no-show a client over it.
//   * The first 7.1 cut kept the row by relabelling it CONFIRMED, which is the
//     single most privileged member of the enum. `canAddToCalendar` has NO
//     server round-trip to catch that: the appointment would be written into the
//     device calendar, world-readable to any app holding `READ_CALENDAR`.
//
// A widget test with a hand-built `Booking(status: unknown)` cannot see either
// one, because both live in the DECODE, upstream of where such a test starts.
// This flow starts from the wire.
//
// THE SEEDED SCENARIO
// -------------------
// `FakeBackend.bookingStatus` is flipped to `'RESCHEDULED'` — a plausible
// future backend state this build has no member for — AFTER the list renders
// and BEFORE the detail is opened. That ordering is the realistic one: the
// client's list request asks for `status=CONFIRMED` and can only ever come back
// with statuses it named, whereas the DETAIL request names no status at all and
// returns whatever the record currently holds. A booking transitioning to a
// newly-deployed backend state between the two is exactly how an unknown status
// reaches a shipped client.
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
    'a booking that moves to an UNRECOGNISED backend status opens a detail '
    'that is rendered but powerless — no reschedule, no cancel, no '
    'add-to-calendar, and the row was never dropped',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;

      final GoRouter router = await AppHarness.boot(tester, fb);

      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
      await AppHarness.loginAs(tester, fb, UserRole.client);

      // Записи tab (bottom-nav tile 3).
      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientBookings);
      expect(find.byType(MyBookingsScreen), findsOneWidget);

      // The booking is still CONFIRMED here, so it partitions into Майбутні
      // and is tappable — the ordinary starting point.
      expect(find.byType(BookingCard), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('service-booking-1')),
        findsOneWidget,
      );

      // ─── The backend gains a state this build does not know ───────────────
      // Flipped BEFORE the detail request is issued, so `GET /bookings/booking-1`
      // returns a status string with no `BookingStatus` member.
      fb.bookingStatus = 'RESCHEDULED';

      await tester.tap(find.byType(BookingCard));
      await AppHarness.settle(tester);

      // ─── 1. The row SURVIVED the decode ───────────────────────────────────
      // The pre-7.1 throw was swallowed by the mapper's `on Failure { continue; }`
      // and the booking disappeared. Reaching a rendered detail screen at all is
      // the assertion.
      AppHarness.expectLocation(router, RouteNames.bookingDetail('booking-1'));
      expect(
        find.byType(BookingDetailScreen),
        findsOneWidget,
        reason:
            'an unrecognised status must not drop the booking or fail the '
            'screen — the master has to be able to see that it exists',
      );

      // ─── 2. It GRANTS NOTHING ─────────────────────────────────────────────
      // The three capabilities a CONFIRMED booking would carry. Had the decode
      // fallen back to `confirmed`, all three would be present here.
      expect(
        find.byKey(const Key('booking-detail-reschedule')),
        findsNothing,
        reason:
            'a status this build cannot identify must not offer to move the '
            'appointment',
      );
      expect(
        find.byKey(const Key('booking-detail-cancel')),
        findsNothing,
        reason: 'nor to cancel it',
      );
      expect(
        find.byKey(const Key('booking-detail-add-calendar')),
        findsNothing,
        reason:
            'the S1 finding itself — add-to-calendar has NO server round-trip '
            'to re-validate it, so a wrong decode writes an unidentified '
            'appointment into a calendar readable by any app with '
            'READ_CALENDAR',
      );

      // ─── 3. The one SAFE affordance is offered ────────────────────────────
      // «Записатись знову» starts a brand-new booking flow and touches this
      // record not at all, so it is safe regardless of what the status means.
      final AppLocalizations detailL10n = l10nOf(tester, BookingDetailScreen);
      expect(
        find.text(detailL10n.bookingDetailRebookCta),
        findsOneWidget,
        reason:
            'the screen is read-only, not empty — rebooking is the one action '
            'that cannot be wrong here',
      );

      // ─── 4. Nothing was mutated ───────────────────────────────────────────
      // No write endpoint was reached, and the record still holds the status
      // the backend gave it — the client neither acted on nor laundered it.
      expect(fb.cancelBookingCalls, 0);
      expect(fb.rescheduleBookingCalls, 0);
      expect(fb.bookingStatus, 'RESCHEDULED');
    },
  );
}
