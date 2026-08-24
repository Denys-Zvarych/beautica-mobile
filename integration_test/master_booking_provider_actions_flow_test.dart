// Track 27.x Wave A — E2E: the PROVIDER footer's decline/complete round trip.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// `booking_detail_provider_footer_test.dart` (widget tier) proves the footer
// content per status/`hasStarted`, that the decline/complete dialogs wire to
// `BookingRepository.declineBooking`/`completeBooking`, that a 409 surfaces
// the friendly message, and that a successful write invalidates an
// actively-watched `bookingsDayProvider` family member — but it does all of
// that against a MOCKED `BookingRepository`. Two links of the real chain sit
// entirely outside a mocked-repository test's reach:
//
//   * `HttpBookingRepository.declineBooking` builds a real
//     `StatusUpdateRequest` (`cancellationReason` enum + optional `comment`)
//     and serialises it through the generated `built_value` client before it
//     ever reaches the mock boundary. A mocked repository proves the DART
//     call site is right; it cannot prove the WIRE body is — a wrong wire
//     name or enum value would still satisfy every widget-tier `verify(...)`
//     while breaking against the real backend.
//   * The status change has to actually PERSIST server-side and be visible on
//     a subsequent real `GET` — not merely update an in-memory `Booking` the
//     mock happened to be told to return.
//
// This flow drives both PROVIDER write paths — decline and complete — through
// a real login, a real `BookingDetailScreen` reached via `router.push` (the
// established idiom for reaching a child route whose OWN navigation is
// already proven elsewhere — see `master_bookings_flow_test.dart`'s rail →
// card → detail journey; re-deriving that lazy-rail scroll here would just
// re-prove navigation this file is not about), a real `PATCH
// /bookings/{id}/decline|complete` against `FakeBackend`, and a real
// subsequent `GET` that must reflect the new terminal status. It also
// establishes a REAL (unmocked) subscription to `bookingsDayProvider` for the
// booking's own day BEFORE acting — mirroring the widget test's own
// container-subscription technique, but here proving the invalidation reaches
// the real `HttpBookingRepository` → real `Dio` → `FakeBackend` chain, not a
// mock that was simply told to return a value.
//
// Decline is proven on BOTH a not-yet-started AND an underway/elapsed
// CONFIRMED booking — the backend allows a provider decline at any time, so a
// client no-show is recorded as a decline with a free-text reason rather than
// a separate no-show action.
//
// KEY POLICY (AppHarness): all TAPS are key-based; Ukrainian text appears
// nowhere in this file — every assertion is by key or call count.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
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
import 'support/reschedule_assertions.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Pushes the PROVIDER detail route for the seeded `booking-1` and
  /// establishes an ACTIVE watcher on `bookingsDayProvider` for the booking's
  /// own day — the real (unmocked) counterpart of what
  /// `bookings_discovery_view.dart` watches underneath the pushed detail
  /// screen in the real app, and what `booking_detail_provider_footer_test`
  /// proves against a mock. Returns the day's initial `getMyBookingsCalls`
  /// count so a test can assert a NEW fetch fired after its write.
  Future<int> openDetailWithActiveDayWatch(
    WidgetTester tester,
    GoRouter router,
    FakeBackend fb,
  ) async {
    unawaited(router.push(RouteNames.masterBookingDetail('booking-1')));
    await AppHarness.settle(tester);
    expect(find.byType(BookingDetailScreen), findsOneWidget);

    final BookingsDayQuery dayQuery = BookingsDayQuery.of(
      day: DateTime.parse(fb.bookingStartsAt),
    );
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(BookingDetailScreen)),
    );
    final ProviderSubscription<AsyncValue<BookingsDayState>> sub = container
        .listen(bookingsDayProvider(dayQuery), (_, _) {});
    addTearDown(sub.close);
    await container.read(bookingsDayProvider(dayQuery).future);

    return fb.getMyBookingsCalls;
  }

  testWidgets(
    'PROVIDER declines a CONFIRMED, not-yet-started booking → the real '
    'StatusUpdateRequest reaches FakeBackend, the status persists across a '
    'real re-fetch (footer goes terminal), and the actively-watched day-list '
    'refetches for real',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      // Default seed is CONFIRMED, ~7 real days out — `hasStarted` is false,
      // so the footer must offer reschedule + decline, never complete.
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      final int callsBeforeAct = await openDetailWithActiveDayWatch(
        tester,
        router,
        fb,
      );

      expect(
        find.byKey(const Key('booking-detail-decline')),
        findsOneWidget,
        reason: 'CONFIRMED + not started must offer decline',
      );
      expect(find.byKey(const Key('booking-detail-complete')), findsNothing);

      await tester.tap(find.byKey(const Key('booking-detail-decline')));
      await AppHarness.settle(tester);
      expect(find.byKey(const Key('decline-booking-dialog')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'Client rescheduled elsewhere.',
      );
      await tester.tap(find.byKey(const Key('decline-booking-confirm')));
      await AppHarness.settle(tester);

      // [AppHarness.settle] can return in the lull between the PATCH
      // resolving and the follow-up GET landing (see [pumpUntilGone]'s doc) —
      // wait for the pre-write decline button to genuinely leave the tree
      // before asserting the terminal state below.
      await AppHarness.pumpUntilGone(
        tester,
        find.byKey(const Key('booking-detail-decline')),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('decline-booking-dialog')), findsNothing);

      // ── The REAL wire body — not a Dart-level mock argument. ──────────────
      expect(
        fb.declineBookingCalls,
        1,
        reason:
            'exactly one PATCH /bookings/booking-1/decline must reach '
            'the fake',
      );
      expect(fb.lastDeclineComment, 'Client rescheduled elsewhere.');
      expect(fb.lastDeclineCancellationReason, 'PROVIDER_UNAVAILABLE');

      // ── The status PERSISTS across a real re-fetch: the footer, driven by
      //      `bookingDetailProvider`'s invalidation, goes fully terminal. ────
      expect(
        find.byKey(const Key('booking-detail-decline')),
        findsNothing,
        reason: 'a DECLINED booking must not still offer decline',
      );
      expect(
        find.byKey(const Key('booking-detail-provider-reschedule')),
        findsNothing,
      );
      expect(find.byKey(const Key('booking-detail-complete')), findsNothing);

      // ── The actively-watched day-list refetched for real, through the
      //      REAL repository → REAL Dio → FakeBackend — not a mock told to
      //      report an invocation. ─────────────────────────────────────────
      expect(
        fb.getMyBookingsCalls,
        greaterThan(callsBeforeAct),
        reason:
            'a successful decline must invalidate the booking day\'s '
            'actively-watched bookingsDayProvider member, issuing a new real '
            'GET /bookings/me',
      );
    },
  );

  testWidgets(
    'PROVIDER completes an underway CONFIRMED booking → the real PATCH '
    '/complete reaches FakeBackend, the status persists across a real '
    're-fetch (footer goes terminal), and the actively-watched day-list '
    'refetches for real',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      // Wide, wall-clock-safe "underway" window — started well in the past,
      // ends well in the future, so `hasStarted` is deterministically true and
      // `isPast` deterministically false regardless of how long this test
      // takes to run on a real device.
      // The window is anchored to the HARNESS'S INJECTED CLOCK ([kFixedNow] —
      // the same instant `AppHarness` overrides `clockProvider` to), NOT the
      // device clock it used to track. Since the 2026-08-17 CRITICAL fix the
      // provider footer's start-time gate reads
      // `Booking.hasStartedAt(ref.watch(clockProvider)())` instead of the
      // device-clock `Booking.hasStarted` getter, so the FIXTURE clock and the
      // APP clock must be the SAME clock (test-clock coherence invariant). A
      // `DateTime.now()`-anchored window — what this used to be, correctly, on
      // the old gate — sits far AFTER `kFixedNow` and would read as
      // not-yet-started, hiding «Завершити» entirely. Both-pinned is now the
      // only coherent form, and it removes the last wall-clock race here:
      // started an hour before the app's "now", ending three hours after it.
      // `isPast` (still device-clock, still `instant-ok`) does not gate the
      // PROVIDER footer at all — `_providerActions` returns before every
      // `isPast` branch — so leaving it out of this pinning changes nothing.
      final DateTime start = kFixedNow.subtract(const Duration(hours: 1));
      final DateTime end = start.add(const Duration(hours: 4));
      fb.bookingStartsAt = start.toIso8601String();
      fb.bookingEndsAt = end.toIso8601String();

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      final int callsBeforeAct = await openDetailWithActiveDayWatch(
        tester,
        router,
        fb,
      );

      expect(
        find.byKey(const Key('booking-detail-complete')),
        findsOneWidget,
        reason: 'an underway CONFIRMED booking must offer complete',
      );
      expect(
        find.byKey(const Key('booking-detail-decline')),
        findsOneWidget,
        reason:
            'decline stays offered on an underway booking too — the backend '
            'allows a provider decline at any time',
      );
      expectRescheduleAbsent(tester);

      await tester.tap(find.byKey(const Key('booking-detail-complete')));
      await AppHarness.settle(tester);
      expect(find.byKey(const Key('complete-booking-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('complete-booking-confirm')));
      await AppHarness.settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('complete-booking-dialog')), findsNothing);

      // ── The REAL wire round trip — no body expected, just the PATCH. ──────
      expect(
        fb.completeBookingCalls,
        1,
        reason:
            'exactly one PATCH /bookings/booking-1/complete must reach '
            'the fake',
      );

      // ── The status PERSISTS across a real re-fetch: terminal footer. ──────
      expect(find.byKey(const Key('booking-detail-complete')), findsNothing);

      // ── The actively-watched day-list refetched for real. ─────────────────
      expect(
        fb.getMyBookingsCalls,
        greaterThan(callsBeforeAct),
        reason:
            'a successful complete must invalidate the booking day\'s '
            'actively-watched bookingsDayProvider member, issuing a new real '
            'GET /bookings/me',
      );
    },
  );

  testWidgets('PROVIDER declines an elapsed CONFIRMED booking → the real '
      'StatusUpdateRequest still reaches FakeBackend (the backend allows a '
      'provider decline at any time), the status persists across a real '
      're-fetch (footer goes terminal), and the actively-watched day-list '
      'refetches for real', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.independentMaster;
    // Same wide, wall-clock-safe "underway/elapsed" window as the complete
    // test above — `hasStarted` deterministically true.
    // The window is anchored to the HARNESS'S INJECTED CLOCK ([kFixedNow] —
    // the same instant `AppHarness` overrides `clockProvider` to), NOT the
    // device clock it used to track. Since the 2026-08-17 CRITICAL fix the
    // provider footer's start-time gate reads
    // `Booking.hasStartedAt(ref.watch(clockProvider)())` instead of the
    // device-clock `Booking.hasStarted` getter, so the FIXTURE clock and the
    // APP clock must be the SAME clock (test-clock coherence invariant). A
    // `DateTime.now()`-anchored window — what this used to be, correctly, on
    // the old gate — sits far AFTER `kFixedNow` and would read as
    // not-yet-started, hiding «Завершити» entirely. Both-pinned is now the
    // only coherent form, and it removes the last wall-clock race here:
    // started an hour before the app's "now", ending three hours after it.
    // `isPast` (still device-clock, still `instant-ok`) does not gate the
    // PROVIDER footer at all — `_providerActions` returns before every
    // `isPast` branch — so leaving it out of this pinning changes nothing.
    final DateTime start = kFixedNow.subtract(const Duration(hours: 1));
    final DateTime end = start.add(const Duration(hours: 4));
    fb.bookingStartsAt = start.toIso8601String();
    fb.bookingEndsAt = end.toIso8601String();

    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

    final int callsBeforeAct = await openDetailWithActiveDayWatch(
      tester,
      router,
      fb,
    );

    expect(
      find.byKey(const Key('booking-detail-complete')),
      findsOneWidget,
      reason: 'an elapsed CONFIRMED booking must offer complete',
    );
    expect(
      find.byKey(const Key('booking-detail-decline')),
      findsOneWidget,
      reason:
          'decline must ALSO be offered on an elapsed booking — the '
          'backend allows a provider decline at any time; a client no-show '
          'is recorded as a decline with a free-text reason',
    );
    expectRescheduleAbsent(tester);

    await tester.tap(find.byKey(const Key('booking-detail-decline')));
    await AppHarness.settle(tester);
    expect(find.byKey(const Key('decline-booking-dialog')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('cancel-booking-note-field')),
      'Client never arrived, could not reach them.',
    );
    await tester.tap(find.byKey(const Key('decline-booking-confirm')));
    await AppHarness.settle(tester);

    // [AppHarness.settle] can return in the lull between the PATCH
    // resolving and the follow-up GET landing (see [pumpUntilGone]'s doc) —
    // wait for the pre-write decline button to genuinely leave the tree
    // before asserting the terminal state below.
    await AppHarness.pumpUntilGone(
      tester,
      find.byKey(const Key('booking-detail-decline')),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('decline-booking-dialog')), findsNothing);

    // ── The REAL wire body — not a Dart-level mock argument. ──────────────
    expect(
      fb.declineBookingCalls,
      1,
      reason:
          'exactly one PATCH /bookings/booking-1/decline must reach '
          'the fake',
    );
    expect(
      fb.lastDeclineComment,
      'Client never arrived, could not reach them.',
    );
    expect(fb.lastDeclineCancellationReason, 'PROVIDER_UNAVAILABLE');

    // ── The status PERSISTS across a real re-fetch: the footer, driven by
    //      `bookingDetailProvider`'s invalidation, goes fully terminal. ────
    expect(
      find.byKey(const Key('booking-detail-decline')),
      findsNothing,
      reason: 'a DECLINED booking must not still offer decline',
    );
    expect(find.byKey(const Key('booking-detail-complete')), findsNothing);

    // ── The actively-watched day-list refetched for real, through the
    //      REAL repository → REAL Dio → FakeBackend — not a mock told to
    //      report an invocation. ─────────────────────────────────────────
    expect(
      fb.getMyBookingsCalls,
      greaterThan(callsBeforeAct),
      reason:
          'a successful decline must invalidate the booking day\'s '
          'actively-watched bookingsDayProvider member, issuing a new real '
          'GET /bookings/me',
    );
  });

  // ==========================================================================
  // Phase 27.2 follow-up — the PROVIDER RESCHEDULE journey.
  //
  // WHY THESE TWO TESTS EXIST
  // -------------------------
  // Provider-side reschedule shipped BROKEN and every tier stayed green.
  // `clientOnlyGuard` bounced an INDEPENDENT_MASTER off all four routes the
  // reschedule flow traverses (`/booking/slots`, `/booking/slots/time`,
  // `/booking/confirm`, `/booking/success`), so tapping «Перенести» landed the
  // master back on `/master/profile` and the slot picker was unreachable — the
  // feature had never worked once. It went unnoticed because:
  //
  //   * `test/routing/booking_route_guard_test.dart` PINNED the bounce as
  //     intended behaviour;
  //   * `booking_detail_provider_footer_test.dart`,
  //     `reschedule_navigation_test.dart` and `reschedule_in_flight_test.dart`
  //     all build a synthetic 2-route `GoRouter` with NO `clientOnlyGuard` and
  //     no session, so the tap "navigates" perfectly;
  //   * this very file, and
  //     `master_appointment_child_booking_actions_flow_test.dart`, asserted the
  //     button `findsOneWidget` and NEVER TAPPED IT.
  //
  // The transferable lesson: a test that never taps the CTA, or that taps it
  // against a stubbed router, cannot catch a route-guard regression. Test 4
  // below is the only tier in the repo that taps «Перенести» as a real
  // INDEPENDENT_MASTER against the REAL `appRouterProvider` (`AppHarness.boot`
  // reads the production router out of the live container) and follows the
  // journey to its end. Test 5 is its mandatory NEGATIVE sibling: a
  // CREATE-shaped seed must STILL bounce, so the narrowed guard cannot later
  // be deleted outright and stay green.
  //
  // Assertions are on the resolved PAGE TYPE (`SlotDateScreen`,
  // `BookingConfirmScreen`, `BookingSuccessScreen`, `MasterProfileScreen`),
  // never on the router location alone — literal-vs-dynamic route shadowing
  // keeps a path assertion green while the WRONG page resolves. The
  // navigations are all `push`-shaped (`startBookingReschedule` calls
  // `context.push`; Test 5 uses `router.push`) because a pushed leaf collapses
  // to its PARENT path in `RouteMatchList.uri` — a `router.go` reproduction
  // false-passes, which is why `AppHarness.location` exists at all.
  // ==========================================================================

  /// Drives the REAL slot picker (SlotDateScreen → SlotTimeScreen): taps the
  /// pinned-clock "today" cell, advances to the time step, picks the first
  /// available chip and confirms. Mirrors `client_reschedule_flow_test.dart`'s
  /// `pickNewDateAndTime` — including its `kyivToday(() => kFixedNow)` fix:
  /// the fixture clock and the app clock MUST be the same clock, or the tap
  /// lands on a PAST cell that renders with no `GestureDetector` at all and
  /// silently no-ops.
  Future<void> pickNewDateAndTime(WidgetTester tester) async {
    expect(find.byType(SlotDateScreen), findsOneWidget);
    await AppHarness.settle(tester);

    final DateTime today = kyivToday(() => kFixedNow);
    await tester.tapCalendarDay(today.day);
    await AppHarness.settle(tester);

    await tester.tap(find.byKey(const Key('booking-summary-cta')));
    await AppHarness.settle(tester);
    expect(find.byType(SlotTimeScreen), findsOneWidget);

    final Finder availableChip = find.byWidgetPredicate(
      (Widget w) => w is SlotChip && w.available,
    );
    expect(availableChip, findsWidgets);
    await tester.tap(availableChip.first);
    await AppHarness.settle(tester);

    await tester.tap(find.byKey(const Key('booking-summary-cta')));
    await AppHarness.settle(tester);
  }

  testWidgets(
    'INDEPENDENT_MASTER TAPS «Перенести» on its own CONFIRMED booking and '
    'reaches the REAL slot picker (never bounced to /master/profile), then '
    'walks the whole reschedule journey — date → time → confirm → submit → '
    'success — across all four clientOnlyGuard-ed routes, and «На головну» '
    'lands on the MASTER home, not the CLIENT shell. mobile-qa '
    '(client-identity parity, 2026-08-22) additionally asserts the '
    'registered-client identity card (`booking-confirm-client-card` / '
    '`booking-success-client-card`) renders with the REAL seeded client '
    'name (`booking-1`\'s FakeBackend fixture — clientId `client-1`, '
    'firstName «Дмитро», lastName «Клієнт») on BOTH the confirm and done '
    'steps — the end-to-end proof that `reschedule_navigation.dart` seeds '
    'the field off a REAL `GET /bookings/booking-1` response, not merely a '
    'synthetic widget-tier fixture (`reschedule_navigation_test.dart` and '
    '`booking_confirm_test.dart`/`booking_success_walkin_test.dart` already '
    'prove the wiring against hand-built fixtures; this is the one place '
    'that proves it survives a real GET + real JSON deserialization).',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      // Default seed: CONFIRMED, ~7 days out, so `hasStartedAt(kFixedNow)` is
      // false and the footer offers the LIVE (tappable) «Перенести».
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // The master's own landing is on screen before anything is pushed.
      expect(find.byType(MasterProfileScreen), findsOneWidget);

      unawaited(router.push(RouteNames.masterBookingDetail('booking-1')));
      await AppHarness.settle(tester);
      expect(find.byType(BookingDetailScreen), findsOneWidget);

      final Finder reschedule = find.byKey(
        const Key('booking-detail-provider-reschedule'),
      );
      expect(
        reschedule,
        findsOneWidget,
        reason:
            'a not-yet-started CONFIRMED provider booking must offer the LIVE '
            '«Перенести» CTA',
      );

      // ── THE TAP THE OLD COVERAGE NEVER MADE. ──────────────────────────────
      await tester.tap(reschedule);
      await AppHarness.settle(tester);

      // ── /booking/slots — guard route 1 of 4. ──────────────────────────────
      expect(
        find.byType(SlotDateScreen),
        findsOneWidget,
        reason:
            'the reschedule-shaped seed must be ADMITTED past clientOnlyGuard '
            '— this is the assertion the shipped bug failed',
      );
      expect(
        find.byType(MasterProfileScreen),
        findsNothing,
        reason:
            'the master must NOT have been bounced back to /master/profile; a '
            'bounce pushes a second MasterProfileScreen ONSTAGE, while a '
            'successful push leaves the original OFFSTAGE (and therefore '
            'invisible to the default finder)',
      );
      AppHarness.expectLocation(router, RouteNames.bookingSlots);

      // ── /booking/slots/time + /booking/confirm — guard routes 2 and 3. ────
      await pickNewDateAndTime(tester);
      expect(
        find.byType(BookingConfirmScreen),
        findsOneWidget,
        reason:
            'the nested time step AND the confirm step carry the same guard — '
            'either one still bouncing would strand the flow here',
      );
      expect(find.byType(MasterProfileScreen), findsNothing);
      AppHarness.expectLocation(router, RouteNames.bookingConfirm);

      // ── Client identity card (client-identity parity, 2026-08-22). ────────
      // A PROVIDER rescheduling a REAL client's booking (`booking-1`'s
      // FakeBackend fixture is seeded with clientId `client-1`, never a
      // guest) must see the client's name in the same visual slot the
      // walk-in guest card occupies on the CREATE path.
      expect(
        find.byKey(const Key('booking-confirm-client-card')),
        findsOneWidget,
        reason:
            'a PROVIDER rescheduling a REAL client\'s booking must see the '
            'registered client\'s identity card on the confirm step',
      );
      // i18n-finder-ok: client name is FakeBackend fixture data
      // (`clientFirstName`/`clientLastName`), not localized UI copy.
      expect(find.text('Дмитро Клієнт'), findsOneWidget);
      // Mutually exclusive with the walk-in guest card on THIS screen.
      expect(find.byKey(const Key('booking-confirm-guest-card')), findsNothing);

      // ── Submit → the REAL PATCH /bookings/{id}/reschedule, as a PROVIDER. ─
      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await AppHarness.settle(tester);

      // ── /booking/success — guard route 4 of 4. ────────────────────────────
      expect(
        find.byType(BookingSuccessScreen),
        findsOneWidget,
        reason: 'the success step carries the same guard',
      );
      expect(find.byType(MasterProfileScreen), findsNothing);
      AppHarness.expectLocation(router, RouteNames.bookingSuccess);
      expect(tester.takeException(), isNull);

      expect(
        fb.rescheduleBookingCalls,
        1,
        reason:
            'a PROVIDER reschedule must reach the SAME per-booking endpoint '
            'the client uses — track 27.2 widened it, it was never forked',
      );
      expect(fb.lastRescheduleNewStartsAt, isNotNull);

      // ── Client identity card carries through onto the DONE screen too. ────
      expect(
        find.byKey(const Key('booking-success-client-card')),
        findsOneWidget,
        reason:
            'BookingConfirmScreen._submit forwards rescheduleClientName/'
            '-Phone unchanged onto BookingSuccessArgs — the done screen '
            'renders its own copy of the card',
      );
      // i18n-finder-ok: client name is FakeBackend fixture data, not
      // localized UI copy.
      expect(find.text('Дмитро Клієнт'), findsOneWidget);

      // ── The journey ENDS with the master back on its own home. ────────────
      //
      // MUTATION-PROBED, AND HONEST ABOUT WHAT IT PROVES (M14). Reverting
      // `booking_success_screen.dart` to its old hard-coded
      // `context.go(RouteNames.clientHome)` leaves THIS assertion GREEN: the
      // global `authRedirect` prefix gate bounces an INDEPENDENT_MASTER off
      // `/home` to `/master/profile` anyway, so the two implementations are
      // indistinguishable from the end of the journey. So this pins the
      // user-visible outcome — a provider is never left stranded in the CLIENT
      // shell — but it is NOT the discriminating test for the `roleHomePath`
      // change itself. That one lives at the widget tier
      // (`booking_confirm_test.dart` → «На головну» navigates an
      // INDEPENDENT_MASTER session to /master/profile), where the synthetic
      // router has no `authRedirect` to mask the difference; it was verified
      // to go RED against the reverted CTA. Do not delete that test on the
      // grounds that "the E2E covers it" — it does not.
      await tester.tap(find.byKey(const Key('booking-success-home-cta')));
      await AppHarness.settle(tester);
      expect(
        find.byType(MasterProfileScreen),
        findsOneWidget,
        reason:
            'the provider must end the journey on its OWN home, never parked '
            'inside the CLIENT shell',
      );
      AppHarness.expectLocation(router, RouteNames.masterProfile);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  testWidgets(
    'NEGATIVE SIBLING — the same INDEPENDENT_MASTER pushing /booking/slots '
    'with a CREATE-shaped seed (no rescheduleBookingId) is STILL bounced to '
    '/master/profile: the guard was NARROWED, not deleted',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      expect(find.byType(MasterProfileScreen), findsOneWidget);

      // Byte-for-byte the seed Test 4's tap produces, MINUS
      // `rescheduleBookingId` — i.e. exactly what step 2 of the CLIENT CREATE
      // flow hands the picker. Nothing else about the navigation differs, so
      // this pins the discriminator itself and not some incidental difference.
      unawaited(
        router.push(
          RouteNames.bookingSlots,
          extra: const BookingSlotPickerArgs(
            masterId: 'master-aaa',
            master: Master(
              id: 'master-aaa',
              firstName: 'Софія',
              lastName: 'Бондар',
              avgRating: 0,
              reviewCount: 0,
              type: MasterType.independentMaster,
            ),
            services: <MasterService>[
              MasterService(
                id: 'pub-assign-1',
                serviceDefId: 'def-1',
                name: 'Манікюр з покриттям',
                durationMinutes: 90,
                priceMin: 650,
                priceDisplay: '650 ₴',
                category: 'NAILS',
              ),
            ],
          ),
        ),
      );
      await AppHarness.settle(tester);

      expect(
        find.byType(SlotDateScreen),
        findsNothing,
        reason:
            'a CREATE-shaped seed must never admit a provider into the CLIENT '
            'booking flow',
      );
      expect(
        find.byType(MasterProfileScreen),
        findsOneWidget,
        reason: 'clientOnlyGuard → roleHomePath still bounces the master home',
      );
      AppHarness.expectLocation(router, RouteNames.masterProfile);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
