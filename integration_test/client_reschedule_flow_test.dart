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
// mobile-qa (track 30.x per-item VISIT reschedule cutover) — Test 2 below
// closes a SEPARATE gap: the per-item endpoint
// (`PATCH /appointments/{id}/services/{bookingId}/reschedule`) moves ONE
// service of a multi-service visit and is DELIBERATELY relaxed on contiguity
// (no re-layout, no cascade, no gap-closing — the visit may legally become
// non-contiguous). Nothing at the widget tier can prove this end to end:
// `booking_confirm_test.dart` hand-builds `BookingConfirmArgs` and never goes
// through the real `_onReschedule`/picker chain, and
// `reschedule_navigation_test.dart` / `booking_detail_appointment_child_footer
// _test.dart` mock the repository. Test 2 drives the REAL journey — «Деталі
// запису» → «Перенести» → the REAL slot picker → confirm → submit — against a
// mutating `FakeBackend` seeded with `booking-1` (the moved item) AND
// `booking-2` (its sibling, sharing `bookingAppointmentId` but with its OWN
// independent window — see `FakeBackend.siblingBookingStartsAt`/
// `siblingBookingEndsAt`/`rescheduleChild`, mirroring the per-service DECLINE
// regression `master_appointment_child_booking_actions_flow_test.dart`
// already proves the same way), then re-fetches `booking-2` THROUGH THE
// REPOSITORY LAYER (`bookingDetailProvider('booking-2').future` off the live
// `ProviderContainer` — a genuine `GET /bookings/booking-2` round trip via
// `FakeBackend`'s `DioAdapter`, not a value this fake merely remembers) to
// prove its window is BYTE-FOR-BYTE UNCHANGED — the actual semantic guarantee
// the per-item cutover exists to deliver. NOT a second rendered detail
// screen: a raw `router.push(RouteNames.bookingDetail('booking-2'))` while
// `booking-1`'s own detail page is still on the SAME client-shell bookings
// branch trips a GoRouter/Navigator duplicate-page-key assertion — unrelated
// to this feature, so the round trip is proven one layer down instead.
//
// `AppointmentRepository` is hand-faked for Test 2 (never a real
// `/appointments/.../reschedule` route on `FakeBackend`'s `DioAdapter`) —
// mirrors `master_appointment_child_booking_actions_flow_test.dart` /
// `client_visit_render_flow_test.dart`'s established precedent (avoids the
// generated `AppointmentControllerApi` client's real-Dio timer leak against
// the fake adapter). Test 1's plain single-booking reschedule is UNAFFECTED —
// it never touches `AppointmentRepository` (`Booking.appointmentId` stays
// null), so it keeps using the REAL `BookingRepository` against the fake
// adapter exactly as before.
//
// mobile-qa FIX (both tests) — `pickNewDateAndTime`'s calendar-day tap used
// to read `DateTime.now()`, the HOST clock, to pick which day cell to tap.
// `SlotDateScreen._today` instead derives from `kyivToday(ref.read
// (clockProvider))`, which `AppHarness.boot` pins to `kFixedNow` (2026-06-14)
// — fully decoupled from the real run date. A bare `DateTime.now().day`
// happened to tap an available June cell only when the REAL day-of-month was
// >= 14; on any run before the 14th (as this one was, discovered while
// authoring Test 2) it tapped an ALREADY-PAST June cell — `onTap: null`, a
// silent no-op — so «Далі» never navigated and the flow died with
// "SlotTimeScreen: found 0 widgets", failing Test 1 too even though Test 1
// itself is untouched by track 30.x. Fixed to `kyivToday(() => kFixedNow)`,
// mirroring `master_bookings_flow_test.dart`'s established `_kyivToday`
// pattern (its own doc comment covers the identical reasoning in more
// depth). `independent_multi_service_booking_flow_test.dart` and
// `public_master_profile_flow_test.dart` carried the SAME bare-
// `DateTime.now()` pattern and were flagged here as a latent flake; both have
// since been converted to `kyivToday(() => kFixedNow)` too, so no E2E flow
// still picks a calendar cell off the host clock. In
// `public_master_profile_flow_test.dart` two of those reads were worse than
// flaky — they fed `forceNonWorkingDate` /
// `forceNonWorkingDateWhenServiceScoped` a date the pinned June-2026 calendar
// never renders, making those flows' negative-path assertions VACUOUS (the
// probed cell was untappable because it was PAST, not because the working-days
// endpoint disabled it).
//
// KEY POLICY (AppHarness): all TAPS are key-based; Ukrainian text appears in
// CONTENT ASSERTIONS only, and reschedule copy is asserted through l10n.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

/// Track 30.x per-item VISIT reschedule — hand-faked (see the file header for
/// why no real `/appointments/.../reschedule` adapter route exists). Only
/// [rescheduleAppointmentItem] is exercised by Test 2 below; every other
/// member throws [UnimplementedError], matching this suite's other
/// appointment hand-fakes (`master_appointment_child_booking_actions_flow_test
/// .dart`'s `_FakeAppointmentRepository`).
class _FakeAppointmentRepository implements AppointmentRepository {
  _FakeAppointmentRepository(this._fb);

  final FakeBackend _fb;

  int rescheduleItemCalls = 0;
  String? lastAppointmentId;
  String? lastBookingId;
  DateTime? lastNewStartAt;

  @override
  Future<Appointment> rescheduleAppointmentItem(
    String appointmentId,
    String bookingId,
    DateTime newStartAt,
  ) async {
    rescheduleItemCalls++;
    lastAppointmentId = appointmentId;
    lastBookingId = bookingId;
    lastNewStartAt = newStartAt;
    // `booking-1`'s booked service (`pub-assign-1`) is 90 minutes on the
    // public catalogue this suite's `FakeBackend` serves. Moves ONLY
    // [bookingId]'s window via [FakeBackend.rescheduleChild] — `booking-2`
    // (the sibling) keeps its own independent window untouched, exactly the
    // per-item ("no cascade") contract Test 2 pins.
    final DateTime newEnd = newStartAt.add(const Duration(minutes: 90));
    _fb.rescheduleChild(bookingId, newStartAt, newEnd);
    return Appointment(
      id: appointmentId,
      status: BookingStatus.confirmed,
      masterId: 'master-aaa',
      masterFirstName: 'Софія',
      masterLastName: 'Бондар',
      masterType: 'INDEPENDENT_MASTER',
      startAt: newStartAt,
      endAt: newEnd,
      totalDurationMinutes: 90,
      totalPrice: 650,
      items: <AppointmentItem>[
        AppointmentItem(
          bookingId: bookingId,
          masterServiceId: 'pub-assign-1',
          serviceName: 'Манікюр з покриттям',
          startAt: newStartAt,
          endAt: newEnd,
          durationMinutes: 90,
          price: 650,
        ),
      ],
    );
  }

  @override
  Future<Appointment> getAppointment(String id) => throw UnimplementedError();

  @override
  Future<void> cancelAppointment(String id, {String? note}) =>
      throw UnimplementedError();

  @override
  Future<void> completeAppointment(String id) => throw UnimplementedError();

  @override
  Future<void> declineAppointment(String id, {String? comment}) =>
      throw UnimplementedError();

  @override
  Future<void> declineAppointmentService(
    String appointmentId,
    String bookingId, {
    String? comment,
  }) => throw UnimplementedError();

  @override
  Future<Appointment> createAppointment(CreateAppointmentRequest req) =>
      throw UnimplementedError();
}

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

    // mobile-qa fix (was `DateTime.now()`) — Kyiv "today" AS THE APP UNDER
    // TEST COMPUTES IT, derived from the harness's INJECTED clock
    // (`kFixedNow`, 2026-06-14 12:00 UTC), never the host device clock.
    // `SlotDateScreen._today` reads `clockProvider`, which `AppHarness.boot`
    // overrides to `kFixedNow`, so the visible month + "today" cell are
    // always June 2026 no matter what day the suite runs on. The bare
    // `DateTime.now()` this used to read instead passed only by ACCIDENT,
    // whenever the real run date's day-of-month happened to land on/after
    // the 14th — any run on the 1st–13th tapped an ALREADY-PAST June cell
    // (`onTap: null`), which is a silent no-op, so the CTA below never
    // navigated and the flow died with "SlotTimeScreen: found 0 widgets".
    // Mirrors `master_bookings_flow_test.dart`'s `_kyivToday` (same fix, same
    // reasoning, documented there in detail).
    final DateTime today = kyivToday(() => kFixedNow);
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
      // listeners does not re-fetch there and then — the fetch lands on
      // RESUME. "Mounted" is not "subscribed".
      //
      // (Corrected 2026-08-06: this used to say invalidate DISPOSES such a
      // provider. It does not at riverpod 3.1.0 — `_performDispose` skips it
      // because `hasNonWeakListeners` counts PAUSED subscriptions,
      // `scheduler.dart:167` / `element.dart:407`, measured `exists` → true.
      // The deferred-to-resume observable this test relies on is unchanged.)
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
  // Test 2 (was RETIRED — see git history for the earlier Home-Hub entry
  // point this slot used to cover; superseded when the Home Hub's populated
  // card switched to the read-only `BookingCard` widget, which has no
  // «Перенести» trigger of its own). mobile-qa (track 30.x cutover) reclaims
  // this slot for the per-item VISIT reschedule's actual semantic guarantee.
  // ==========================================================================
  testWidgets(
    'CLIENT reschedules ONE service of a multi-service visit end-to-end: '
    'detail «Перенести» → slot picker → new date+time → confirm (per-item '
    'endpoint) → submit calls PATCH /appointments/{id}/services/{bookingId}'
    '/reschedule (never the per-booking PATCH /bookings/{id}/reschedule) → '
    'success, while the visit\'s SIBLING service (booking-2) stays at its '
    'ORIGINAL time across a real re-fetch',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        // `booking-1` becomes one service of a multi-service visit
        // (`appt-1`); `booking-2` is its sibling, sharing the same
        // `appointmentId` but carrying its OWN independent window
        // (`siblingBookingStartsAt`/`siblingBookingEndsAt`) — the window
        // whose survival is the entire point of the per-item fix.
        ..bookingAppointmentId = 'appt-1';
      final fakeAppointments = _FakeAppointmentRepository(fb);
      final DateTime originalSiblingStart = DateTime.parse(
        fb.siblingBookingStartsAt,
      );
      final String originalSiblingEnd = fb.siblingBookingEndsAt;

      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          appointmentRepositoryProvider.overrideWithValue(fakeAppointments),
        ],
      );

      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
      await AppHarness.loginAs(tester, fb, UserRole.client);

      // ── Open «МОЇ ЗАПИСИ» and land on `booking-1`'s detail. The default
      //    `/bookings/me` fixture always hands back exactly ONE row
      //    (`booking-1`) regardless of `bookingAppointmentId` — `booking-2`
      //    is reachable only via its own `GET /bookings/booking-2` detail
      //    route below, never through the list — so this is the SAME
      //    single-`BookingCard` navigation Test 1 uses. ─────────────────────
      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      expect(find.byType(BookingCard), findsOneWidget);
      await tester.tap(find.byType(BookingCard));
      await AppHarness.settle(tester);
      expect(find.byType(BookingDetailScreen), findsOneWidget);

      // ── «Перенести» → the shared `startBookingReschedule` helper forwards
      //    `appointmentId: 'appt-1'`, the per-item routing discriminator
      //    `BookingConfirmScreen._submit` checks FIRST. ─────────────────────
      final Finder reschedule = find.byKey(
        const Key('booking-detail-reschedule'),
      );
      expect(reschedule, findsOneWidget);
      await tester.tap(reschedule);
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.bookingSlots);

      // ── Pick a NEW date + time through the REAL picker. ───────────────────
      await pickNewDateAndTime(tester);

      AppHarness.expectLocation(router, RouteNames.bookingConfirm);
      expect(find.byType(BookingConfirmScreen), findsOneWidget);

      // ── Submit → the PER-ITEM endpoint fires. ─────────────────────────────
      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await AppHarness.settle(tester);

      AppHarness.expectLocation(router, RouteNames.bookingSuccess);
      expect(find.byType(BookingSuccessScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // ── The write went to the PER-ITEM endpoint with THIS child's id,
      //    never the per-booking `PATCH /bookings/{id}/reschedule` — asserted
      //    both positively (the hand-fake's own call) and negatively
      //    (`FakeBackend.rescheduleBookingCalls` stays at 0). ───────────────
      expect(fakeAppointments.rescheduleItemCalls, 1);
      expect(fakeAppointments.lastAppointmentId, 'appt-1');
      expect(fakeAppointments.lastBookingId, 'booking-1');
      expect(
        fb.rescheduleBookingCalls,
        0,
        reason:
            'a per-item VISIT reschedule must never reach the per-booking '
            'PATCH /bookings/{id}/reschedule endpoint',
      );

      // ── `booking-1` genuinely MOVED. ───────────────────────────────────────
      expect(
        DateTime.parse(fb.bookingStartsAt),
        fakeAppointments.lastNewStartAt,
      );

      // ── THE SEMANTIC GUARANTEE — `booking-2` (the sibling) is
      //    BYTE-FOR-BYTE UNCHANGED on the fake backend: no re-layout, no
      //    cascade, no gap-closing (track 30.x's locked "no cascade"
      //    invariant — the retired whole-visit reschedule moved every child
      //    in lockstep). ────────────────────────────────────────────────────
      expect(
        fb.siblingBookingStartsAt,
        originalSiblingStart.toIso8601String(),
        reason:
            'moving booking-1 must NEVER move booking-2 — the per-item '
            'endpoint must leave siblings byte-for-byte unchanged',
      );
      expect(fb.siblingBookingEndsAt, originalSiblingEnd);

      // ── …and this is REFLECTED in a REAL re-fetch through the repository
      //    layer — a genuine `GET /bookings/booking-2` round trip via
      //    `FakeBackend`'s `DioAdapter` — not just a value this fake merely
      //    remembers. (A raw `router.push(RouteNames.bookingDetail(...))`
      //    for a SECOND detail page inside the same client-shell bookings
      //    branch trips a GoRouter/Navigator duplicate-page-key assertion —
      //    unrelated to this feature, and out of scope to chase here — so the
      //    round trip is proven at the provider layer instead, exactly as
      //    real as the HTTP call a rendered screen would have made.) ────────
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(BookingSuccessScreen)),
        listen: false,
      );
      final Booking sibling = await container.read(
        bookingDetailProvider('booking-2').future,
      );
      expect(fb.getSiblingBookingDetailCalls, greaterThanOrEqualTo(1));
      expect(
        sibling.startAt,
        originalSiblingStart,
        reason:
            "the sibling's RE-FETCHED start time must be UNCHANGED after "
            'booking-1 moved',
      );
      expect(sibling.endAt, DateTime.parse(originalSiblingEnd));
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
