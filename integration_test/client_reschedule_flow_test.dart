// Track 24.x (booking auto-confirm) — E2E: the CLIENT reschedule journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// The widget/unit tier proves the reschedule pieces in isolation:
//   • booking_detail_interactions_test.dart — «Перенести» seeds the slot
//     picker with `rescheduleBookingId`;
//   • reschedule_navigation_test.dart — the helper's UNAVAILABLE guards;
//   • independent_booking_submit_reschedule_test.dart — the notifier swaps
//     `createBooking` → `rescheduleBooking` and fires the two invalidations.
// NONE proves the REAL journey wired together against a mutating backend: a
// CLIENT opening «Деталі запису», tapping «Перенести», picking a NEW date+time
// through the REAL slot picker, confirming on a screen whose CTA reads
// «Перенести запис» and hides the comment field, submitting so the fake backend
// receives `PATCH /bookings/{id}/reschedule` (NOT a new `POST /bookings`),
// landing on the reschedule success screen, and — the load-bearing part — the
// moved booking's detail AND the upcoming My-Bookings list both re-fetching
// (proving both provider invalidations took effect).
//
// The FakeBackend seeds ONE booking (`booking-1`, CONFIRMED, booked service
// `pub-assign-1` = one of `master-aaa`'s public catalogue services) and mutates
// its start/end on the reschedule PATCH, keeping it CONFIRMED.
//
// KEY POLICY (AppHarness): all TAPS are key-based; Ukrainian text appears in
// CONTENT ASSERTIONS only, and reschedule copy is asserted through l10n.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  AppLocalizations l10nOf(WidgetTester tester, Type screen) =>
      AppLocalizations.of(tester.element(find.byType(screen)));

  // Drives the slot picker (SlotDateScreen → SlotTimeScreen): picks "today"
  // (admissible per the fixture's wide always-working window), advances to the
  // time step, and taps the first available chip → «Підтвердити». Mirrors the
  // create-booking picker drive in public_master_profile_flow_test.dart.
  Future<void> pickNewDateAndTime(WidgetTester tester) async {
    expect(find.byType(SlotDateScreen), findsOneWidget);
    await AppHarness.settle(tester);

    final DateTime today = DateTime.now();
    final Finder todayCell = find.byKey(
      Key('booking-calendar-day-${today.day}'),
    );
    expect(todayCell, findsOneWidget);
    // `tapCalendarDay` scrolls the cell into view first — a blind tap on a
    // below-the-fold row lands on the summary bar instead (see the extension's
    // doc comment in test/helpers/pump_app.dart).
    await tester.tapCalendarDay(today.day);
    await AppHarness.settle(tester);

    // «Далі» → SlotTimeScreen.
    await tester.tap(find.byKey(const Key('booking-summary-cta')));
    await AppHarness.settle(tester);
    expect(find.byType(SlotTimeScreen), findsOneWidget);

    final Finder availableChip = find.byWidgetPredicate(
      (Widget w) => w is SlotChip && w.available,
    );
    expect(availableChip, findsWidgets);
    await tester.tap(availableChip.first);
    await AppHarness.settle(tester);

    // «Підтвердити» → BookingConfirmScreen.
    await tester.tap(find.byKey(const Key('booking-summary-cta')));
    await AppHarness.settle(tester);
  }

  // ==========================================================================
  // Test 1 — the full reschedule journey from «МОЇ ЗАПИСИ».
  // ==========================================================================
  testWidgets(
    'CLIENT reschedules a CONFIRMED booking end-to-end: detail «Перенести» → '
    'slot picker → new date+time → confirm shows «Перенести запис» with NO '
    'comment field → submit calls PATCH /reschedule (never POST /bookings) → '
    'reschedule success → detail + upcoming list both re-fetch',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
      await AppHarness.loginAs(tester, fb, UserRole.client);

      // ── Open «МОЇ ЗАПИСИ» (bottom-nav tile 3) and land on the detail. ──────
      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientBookings);
      expect(find.byType(MyBookingsScreen), findsOneWidget);
      expect(find.byType(BookingCard), findsOneWidget);

      await tester.tap(find.byType(BookingCard));
      await AppHarness.settle(tester);
      // `/bookings/:bookingId` is a child GoRoute INSIDE the client shell's
      // bookings branch, reached via `context.push` — so `matches.last` stays a
      // ShellRouteMatch and plain `expectLocation` reads the stale branch root
      // `/bookings`. Only the drill-down resolver sees the pushed leaf. (The
      // `bookingSlots`/`bookingConfirm`/`bookingSuccess` assertions below stay
      // on plain `expectLocation` — those routes live OUTSIDE the shell.)
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.bookingDetail('booking-1'),
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);

      // ── «Перенести» → the shared reschedule helper seeds + pushes the slot
      // picker (loads master-aaa's public profile to recover the booked
      // service). ──────────────────────────────────────────────────────────
      final Finder reschedule = find.byKey(
        const Key('booking-detail-reschedule'),
      );
      expect(
        reschedule,
        findsOneWidget,
        reason: 'a CONFIRMED booking must offer «Перенести»',
      );
      await tester.tap(reschedule);
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.bookingSlots);

      // ── Pick a NEW date + time through the real picker. ───────────────────
      await pickNewDateAndTime(tester);

      // ── The confirm screen is in RESCHEDULE mode. ─────────────────────────
      AppHarness.expectLocation(router, RouteNames.bookingConfirm);
      expect(find.byType(BookingConfirmScreen), findsOneWidget);
      final AppLocalizations confirmL10n = l10nOf(tester, BookingConfirmScreen);
      // CTA reads «Перенести запис» (never «Записатись»).
      expect(find.text(confirmL10n.bookingRescheduleSubmitCta), findsOneWidget);
      expect(find.text(confirmL10n.bookingSubmitCta), findsNothing);
      // The «Коментар для майстра» field is HIDDEN on the reschedule path (the
      // reschedule endpoint has no comment channel).
      expect(
        find.byKey(const Key('booking-confirm-comment-field')),
        findsNothing,
        reason: 'the comment field must be hidden when rescheduling',
      );
      // The ONE visit recap card lists the booked service.
      //
      // This used to assert a per-service `booking-confirm-appt-<id>` card key.
      // MO-3 (`442f5528`) replaced the per-service appointment cards with a
      // SINGLE `BookingSummaryCards` visit recap, deleting that key from
      // `lib/` entirely — so the assertion had become unfalsifiable-in-reverse
      // (it could only ever fail). It never surfaced because the blind
      // calendar tap above (finding #2) killed this flow before line 162 was
      // reached. Re-pointed at what the screen actually renders today.
      expect(
        find.byKey(const Key('booking-confirm-visit-card')),
        findsOneWidget,
        reason: 'the reschedule confirm screen shows one visit recap card',
      );
      expect(
        // FakeBackend fixture DATA (the seeded serviceName for pub-assign-1),
        // not UI copy — echoed back from the wire verbatim, never translated.
        // i18n-finder-ok: seeded serviceName, locale-invariant wire data
        find.text('Манікюр з покриттям'),
        findsWidgets,
        reason: 'the recap must name the booked service (pub-assign-1)',
      );

      // ── Submit → PATCH /reschedule fires; NO POST /bookings. ──────────────
      final int detailFetchesBefore = fb.getBookingDetailCalls;
      final int listFetchesBefore = fb.getMyBookingsCalls;

      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await AppHarness.settle(tester);

      // Landed on the RESCHEDULE success screen.
      AppHarness.expectLocation(router, RouteNames.bookingSuccess);
      expect(find.byType(BookingSuccessScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      final AppLocalizations successL10n = l10nOf(tester, BookingSuccessScreen);
      expect(
        find.text(successL10n.bookingRescheduleSuccessTitle),
        findsOneWidget,
        reason: 'the success screen must show the reschedule title',
      );

      // Exactly one reschedule PATCH, carrying a real new start — and no
      // create ever happened (FakeBackend wires no POST /bookings, so a
      // createBooking would have thrown and failed the flow before here).
      expect(
        fb.rescheduleBookingCalls,
        1,
        reason: 'submit must call PATCH /bookings/{id}/reschedule exactly once',
      );
      expect(fb.lastRescheduleNewStartsAt, isNotNull);

      // ── BOTH invalidations took effect — asserted on the RETURN JOURNEY. ──
      //
      // Do NOT assert an IMMEDIATE re-fetch here. While the app is parked on
      // `BookingSuccessScreen` (a top-level route that COVERS both consumers),
      // `BookingDetailScreen` and `_BookingsTabView` are mounted but NOT
      // subscribed: `Consumer` stops listening whenever its widget stops being
      // visible — it reads `TickerMode.of` and calls `ProviderSubscription
      // .pause` (flutter_riverpod-3.3.1 `src/core/consumer.dart:73-76`,
      // `:405-417`), and Navigator disables `TickerMode` for covered routes.
      // Both providers are `autoDispose` (`booking_detail_notifier.dart:22`,
      // `my_bookings_notifier.dart:95`), so `ref.invalidate` with only PAUSED
      // listeners DISPOSES them instead of re-fetching. The fetch lands on
      // RESUME. "Mounted" is not "subscribed".
      //
      // So walk the user's actual return path and assert the fetch where it
      // really happens. This is strictly STRONGER than an offstage-count
      // check: it proves the client SEES the moved booking, which an offstage
      // re-fetch alone would never establish. Counterfactual (confirmed):
      // comment out `booking_confirm_screen.dart:199-200`'s invalidations and
      // both counters stay at 1 through the whole return journey — i.e. the
      // user is shown the STALE pre-reschedule time. Those two `ref.invalidate`
      // calls are load-bearing.

      // «На головну» → /home, then «МОЇ ЗАПИСИ» → the bookings branch, whose
      // navigator still has the pushed detail on top. The detail RESUMES, its
      // disposed provider rebuilds, and the moved booking is re-fetched.
      await tester.tap(find.byKey(const Key('booking-success-home-cta')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientHome);

      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(
        fb.getBookingDetailCalls,
        greaterThan(detailFetchesBefore),
        reason:
            'bookingDetailProvider(id) was invalidated while paused, so the '
            'detail must RE-FETCH the moved booking when it resumes',
      );

      // Pop the detail → the upcoming My-Bookings list resumes and re-fetches.
      await tester.tap(find.byKey(const Key('booking-detail-back')));
      await AppHarness.settle(tester);
      expect(find.byType(MyBookingsScreen), findsOneWidget);
      expect(
        fb.getMyBookingsCalls,
        greaterThan(listFetchesBefore),
        reason:
            'myBookingsProvider(upcoming) was invalidated while paused, so the '
            'upcoming list must RE-FETCH when it resumes',
      );
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ==========================================================================
  // Test 2 — HOME-HUB entry: the «Найближчий запис» Reschedule button drives
  // the SAME helper from just `appt.id`. `nextAppointmentProvider` is overridden
  // directly (this flow is about the reschedule affordance, not re-proving the
  // provider's own live wiring — that's `next_appointment_provider_test.dart`),
  // seeded with the SAME `booking-1` the FakeBackend serves, so the helper's
  // GET /bookings/booking-1 + GET /masters/master-aaa resolve and the picker is
  // seeded to reschedule THIS booking.
  // ==========================================================================
  testWidgets(
    'CLIENT taps «Перенести» on the Home Hub next-appointment card → the shared '
    'reschedule helper drives the slot picker from just the appointment id',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      // `startsAt` is derived from the SAME booking the FakeBackend serves
      // (`booking-1`) rather than hand-typed, so the Home Hub card and the
      // booking behind it can never disagree. It used to read
      // `DateTime.utc(2026, 7, 20, 15)` — a copy of what was then
      // `bookingStartsAt`'s hardcoded value — and silently expired with it:
      // `CountdownChip` (hub_widgets.dart) diffs the target against the REAL
      // `DateTime.now()`, so the "next appointment" card was rendering «Зараз»
      // instead of «Через N дн» while still passing, because this flow asserts
      // only the reschedule affordance. `dateLabel`/`timeLabel` are the card's
      // pre-formatted display strings and are decorative here — nothing derives
      // or asserts them.
      final DateTime seededStart = DateTime.parse(fb.bookingStartsAt);
      final DateTime seededEnd = DateTime.parse(fb.bookingEndsAt);
      final NextAppointment seededAppt = NextAppointment(
        id: 'booking-1',
        masterName: 'Софія Бондар',
        service: 'Манікюр з покриттям',
        dateLabel: '20 липня',
        timeLabel: '15:00',
        location: 'Київ',
        startsAt: seededStart,
        endsAt: seededEnd,
        masterInitials: 'СБ',
      );
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          nextAppointmentProvider.overrideWith((ref) async => seededAppt),
        ],
      );

      await AppHarness.loginAs(tester, fb, UserRole.client);

      // The Home Hub next-appointment card is populated (override).
      final Finder rescheduleButton = find.byKey(
        const Key('next_appt_reschedule_button'),
      );
      await tester.ensureVisible(rescheduleButton);
      await AppHarness.settle(tester);
      expect(rescheduleButton, findsOneWidget);

      await tester.tap(rescheduleButton);
      await AppHarness.settle(tester);

      // The shared helper loaded the booking (GET /bookings/booking-1) + the
      // master profile and pushed the slot picker — seeded to reschedule.
      AppHarness.expectLocation(router, RouteNames.bookingSlots);
      expect(find.byType(SlotDateScreen), findsOneWidget);
      expect(
        fb.getBookingDetailCalls,
        greaterThanOrEqualTo(1),
        reason:
            'the Home Hub card carries only appt.id — the helper must fetch '
            'the booking detail before seeding the picker',
      );
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
