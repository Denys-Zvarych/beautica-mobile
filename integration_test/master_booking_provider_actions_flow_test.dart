// Track 27.x Wave A — E2E: the PROVIDER footer's decline/complete/not-complete
// round trip.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// `booking_detail_provider_footer_test.dart` (widget tier) proves the footer
// content per status/`hasStarted`, that the decline/complete/not-complete
// dialogs wire to
// `BookingRepository.declineBooking`/`completeBooking`/`notCompleteBooking`,
// that a 409 surfaces the friendly message, and that a successful write
// invalidates an actively-watched `bookingsDayProvider` family member — but it
// does all of that against a MOCKED `BookingRepository`. Two links of the
// real chain sit entirely outside a mocked-repository test's reach:
//
//   * `HttpBookingRepository.declineBooking`/`notCompleteBooking` build a
//     real `StatusUpdateRequest` (`cancellationReason` enum + optional
//     `comment`) and serialise it through the generated `built_value` client
//     before it ever reaches the mock boundary. A mocked repository proves the
//     DART call site is right; it cannot prove the WIRE body is — a wrong
//     wire name or enum value would still satisfy every widget-tier
//     `verify(...)` while breaking against the real backend.
//   * The status change has to actually PERSIST server-side and be visible on
//     a subsequent real `GET` — not merely update an in-memory `Booking` the
//     mock happened to be told to return.
//
// This flow drives all three PROVIDER write paths — decline, complete, and
// not-complete (client no-show) — through a real login, a real
// `BookingDetailScreen` reached via `router.push` (the established idiom for
// reaching a child route whose OWN navigation is already proven elsewhere —
// see `master_bookings_flow_test.dart`'s rail → card → detail journey;
// re-deriving that lazy-rail scroll here would just re-prove navigation this
// file is not about), a real `PATCH /bookings/{id}/decline|complete|not-
// complete` against `FakeBackend`, and a real subsequent `GET` that must
// reflect the new terminal status. It also establishes a REAL (unmocked)
// subscription to `bookingsDayProvider` for the booking's own day BEFORE
// acting — mirroring the widget test's own container-subscription technique,
// but here proving the invalidation reaches the real `HttpBookingRepository`
// → real `Dio` → `FakeBackend` chain, not a mock that was simply told to
// return a value.
//
// KEY POLICY (AppHarness): all TAPS are key-based; Ukrainian text appears
// nowhere in this file — every assertion is by key or call count.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

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
      final DateTime start = DateTime.now().toUtc().subtract(
        const Duration(hours: 1),
      );
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
        reason: 'an underway CONFIRMED booking must offer complete only',
      );
      expect(find.byKey(const Key('booking-detail-decline')), findsNothing);
      expect(
        find.byKey(const Key('booking-detail-provider-reschedule')),
        findsNothing,
      );

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

  testWidgets(
    'PROVIDER marks an elapsed CONFIRMED booking as a no-show → the real '
    'StatusUpdateRequest (CLIENT_NO_SHOW) reaches FakeBackend, the status '
    'persists across a real re-fetch (footer goes terminal), and the '
    'actively-watched day-list refetches for real',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      // Same wide, wall-clock-safe "underway/elapsed" window as the complete
      // test above — `hasStarted` deterministically true.
      final DateTime start = DateTime.now().toUtc().subtract(
        const Duration(hours: 1),
      );
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
        find.byKey(const Key('booking-detail-not-complete')),
        findsOneWidget,
        reason: 'an elapsed CONFIRMED booking must ALSO offer no-show',
      );
      expect(find.byKey(const Key('booking-detail-decline')), findsNothing);
      expect(
        find.byKey(const Key('booking-detail-provider-reschedule')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('booking-detail-not-complete')));
      await AppHarness.settle(tester);
      expect(
        find.byKey(const Key('not-complete-booking-dialog')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'Client never arrived, could not reach them.',
      );
      await tester.tap(find.byKey(const Key('not-complete-booking-confirm')));
      await AppHarness.settle(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('not-complete-booking-dialog')),
        findsNothing,
      );

      // ── The REAL wire body — not a Dart-level mock argument. ──────────────
      expect(
        fb.notCompleteBookingCalls,
        1,
        reason:
            'exactly one PATCH /bookings/booking-1/not-complete must reach '
            'the fake',
      );
      expect(
        fb.lastNotCompleteComment,
        'Client never arrived, could not reach them.',
      );
      expect(fb.lastNotCompleteCancellationReason, 'CLIENT_NO_SHOW');

      // ── The status PERSISTS across a real re-fetch: the footer, driven by
      //      `bookingDetailProvider`'s invalidation, goes fully terminal. ────
      expect(
        find.byKey(const Key('booking-detail-not-complete')),
        findsNothing,
        reason: 'a NOT_COMPLETED booking must not still offer no-show',
      );
      expect(find.byKey(const Key('booking-detail-complete')), findsNothing);

      // ── The actively-watched day-list refetched for real, through the
      //      REAL repository → REAL Dio → FakeBackend — not a mock told to
      //      report an invocation. ─────────────────────────────────────────
      expect(
        fb.getMyBookingsCalls,
        greaterThan(callsBeforeAct),
        reason:
            'a successful not-complete must invalidate the booking day\'s '
            'actively-watched bookingsDayProvider member, issuing a new real '
            'GET /bookings/me',
      );
    },
  );
}
