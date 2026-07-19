// Phase 7.2 + 7.6 — E2E: the INDEPENDENT MASTER's «Мої записи» → day rail →
// «Деталі запису» (PROVIDER view) → back journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// The widget/unit tier proves each surface in isolation:
// `master_bookings_screen_test` (four async states, two empties, rail dots,
// debounce, server order), `master_bookings_notifier_test` (query → wire,
// paging, no re-sort), `booking_detail_provider_view_test` (role branching of
// the header + footer), `master_bookings_route_guard_test` (the two-way role
// fence), `booking_viewer_role_test` (fail-closed derivation). NONE of them
// proves the journey wired together against a real HTTP boundary:
//
//   1. A master logs in and lands on the master shell.
//   2. Tapping «Мої записи» (nav tile 1) PUSHES `/master/bookings` — not the
//      CLIENT `/bookings`, which the role gate would bounce them off.
//   3. The list is served by `GET /bookings/me` and the rail's dots by the
//      SEPARATE, filter-independent `GET /bookings/me/booked-days`. Two
//      distinct endpoints — a regression that fed the rail from the list would
//      be invisible to a widget test that stubs the repository.
//   4. Selecting a rail day re-queries with `from == to` ON THE WIRE.
//   5. Tapping the card pushes `/master/bookings/:id` and the SAME
//      `BookingDetailScreen` renders its PROVIDER branch: the CLIENT as
//      counterparty, and no client action footer.
//   6. Back returns to the still-mounted list.
//
// The provider-vs-client branch is the load-bearing part. It is derived from
// the SESSION (`bookingViewerRoleProvider`), and the only way to exercise that
// derivation end-to-end is to drive a REAL master login through a real router
// — which is exactly what a widget test cannot do.
//
// ⚠ EXECUTION STATUS: this flow has NOT been run on a device. The dev VM has no
// attached emulator (the known host-only-adapter limitation, backlog #179/#191),
// so it is verified here as analyze-clean and correctly wired into BOTH
// aggregators; its first real execution is the CI emulator job. This is stated
// rather than implied — it has not passed, it has been authored.
//
// KEY POLICY (AppHarness): all TAPS are key-based; Ukrainian text appears in
// CONTENT ASSERTIONS only.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
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

  String locationOf(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.toString();

  testWidgets(
    'INDEPENDENT_MASTER opens «Мої записи», narrows by a rail day, and opens '
    'the booking in the PROVIDER view',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);

      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // ── 1. The master lands on their own shell, NOT the client one. ───────
      expect(locationOf(router), startsWith(RouteNames.masterProfile));

      // ── 2. «Мої записи» (nav tile 1) pushes the MASTER route. ─────────────
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);

      expect(
        locationOf(router),
        startsWith(RouteNames.masterBookings),
        reason:
            'tile 1 must reach /master/bookings; /bookings is the CLIENT '
            'branch and the role gate would bounce a master straight off it',
      );
      expect(
        locationOf(router),
        isNot(startsWith('${RouteNames.clientBookings}/')),
      );
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(
        router.canPop(),
        isTrue,
        reason: 'push, not go — the profile origin stays on the back stack',
      );

      // ── 3. The list rendered from GET /bookings/me. ───────────────────────
      expect(
        fb.getMyBookingsCalls,
        greaterThan(0),
        reason: 'the list must be served by the real endpoint',
      );
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
      );
      // The PROVIDER-side identity fields the mapper gained in Phase 7.2 must
      // survive the whole wire → DTO → domain → widget path.
      expect(
        find.text('${fb.clientFirstName} ${fb.clientLastName}'),
        findsWidgets,
        reason:
            'the master\'s card must name the CLIENT — clientFirstName/'
            'clientLastName decoded off the wire, not the master\'s own name',
      );

      // ── 3b. Phases 7.9–7.11: the TIMELINE body, and the day-scoped wire
      //        shape — this is the part this flow did NOT prove before the
      //        rework (it predates it and never asserted anything specific to
      //        it; the widget/unit tier covers this shape against a MOCKED
      //        repository — `bookings_day_notifier_test.dart`,
      //        `master_bookings_screen_test.dart` — this is the same
      //        invariant proven against a REAL HTTP round trip instead). ────
      expect(
        find.byType(BookingsTimelineGrid),
        findsOneWidget,
        reason: 'the body must be the day-scoped timeline, not a vertical list',
      );
      expect(
        find.byKey(const Key('master-bookings-list')),
        findsNothing,
        reason: 'the retired paginated vertical list must not resurface',
      );
      final Map<String, dynamic>? landingQuery = fb.lastMyBookingsQuery;
      expect(
        landingQuery,
        isNotNull,
        reason: 'the landing fetch must have reached the fake backend',
      );
      expect(
        landingQuery!['from'],
        landingQuery['to'],
        reason:
            'the day-scoped landing fetch is from == to — Phase 7.9 fetches '
            'exactly one Kyiv calendar day, never a range',
      );
      expect(
        landingQuery['size'],
        100,
        reason:
            'Phase 7.9\'s single-fetch contract: size=100 in one request, no '
            'page-1 loop, so a whole day is provably covered',
      );
      expect(
        landingQuery['sort'],
        'startsAt,asc',
        reason:
            'ascending order is load-bearing for Phase 7.10\'s lane '
            'assignment — the notifier must not have re-sorted or requested '
            'descending',
      );

      // ── 4. The rail dots come from the SEPARATE booked-days endpoint. ─────
      expect(
        fb.bookedDaysCalls,
        greaterThan(0),
        reason:
            'the rail must be fed by GET /bookings/me/booked-days — a rail '
            'derived from the (filtered) list would hide the very days the '
            'master needs to un-narrow to reach',
      );
      final DateTime bookedDay = parseApiDate(
        fb.bookingStartsAt.substring(0, 10),
      );
      expect(find.byType(BookingsDayRail), findsOneWidget);
      expect(
        find.byKey(dayDotKey(bookedDay)),
        findsOneWidget,
        reason: 'the seeded booking\'s day must carry a dot',
      );

      // ── 5. Selecting that rail day re-queries with from == to ON THE WIRE. ─
      final int callsBeforeNarrow = fb.getMyBookingsCalls;
      await tester.tap(find.byKey(dayChipKey(bookedDay)));
      // The screen debounces day-chip taps by 220 ms; the filtered request
      // does not leave until it elapses, so there is no earlier state to
      // pump-until.
      // fixed-wait-ok: advancing past the 220 ms day-tap debounce.
      await tester.pump(const Duration(milliseconds: 300));
      await AppHarness.settle(tester);

      expect(
        fb.getMyBookingsCalls,
        greaterThan(callsBeforeNarrow),
        reason: 'the day selection must have issued a NEW list request',
      );
      final Map<String, dynamic> q = fb.lastMyBookingsQuery!;
      final String expectedDay = toApiDate(bookedDay);
      expect(
        q['from'],
        expectedDay,
        reason: 'a single-day rail selection is from == to on the wire',
      );
      expect(q['to'], expectedDay);
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
        reason: 'the narrowed day still contains the seeded booking',
      );

      // ── 6. Open the detail — the PROVIDER view. ───────────────────────────
      await tester.tap(find.byType(MasterBookingCard));
      await AppHarness.settle(tester);

      expect(
        locationOf(router),
        RouteNames.masterBookingDetail('booking-1'),
        reason:
            'the card must push the MASTER detail route, not the client one',
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);

      // The counterparty is the CLIENT — this is the whole role branch, and it
      // is derived from the SESSION, which only a real login can exercise.
      expect(
        find.byKey(const Key('booking-detail-client-strip')),
        findsOneWidget,
        reason:
            'the PROVIDER view must show the CLIENT strip; the master seeing '
            'their own name here is the exact bug booking_viewer_role.dart '
            'exists to prevent',
      );
      expect(
        find.text('${fb.clientFirstName} ${fb.clientLastName}'),
        findsWidgets,
      );

      // …and NONE of the client action footer. These are the client's own
      // affordances over their own booking; a master must never be offered
      // them (7.3 fills the provider footer separately).
      for (final String clientOnly in <String>[
        'booking-detail-cancel',
        'booking-detail-reschedule',
        'booking-detail-add-calendar',
        'booking-detail-leave-review',
      ]) {
        expect(
          find.byKey(Key(clientOnly)),
          findsNothing,
          reason:
              '«$clientOnly» is a CLIENT affordance and must not render for a '
              'provider viewer',
        );
      }

      // ── 7. Back returns to the list, still narrowed. ──────────────────────
      await tester.tap(find.byKey(const Key('booking-detail-back')));
      await AppHarness.settle(tester);

      expect(locationOf(router), startsWith(RouteNames.masterBookings));
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(find.byType(BookingDetailScreen), findsNothing);
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
      );
    },
  );
}
