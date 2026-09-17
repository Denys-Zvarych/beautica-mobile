// Phase 21.12 — E2E: the SALON_OWNER's real «Записи» board journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// Phase 21.12 replaced a shell PLACEHOLDER with a real screen that owns a new
// wire scope, a new provider seam and a new drill-in. The widget tier
// (`salon_bookings_screen_test.dart`, `salon_bookings_board_test.dart`,
// `salon_day_narrowing_test.dart`, `salon_bookings_route_shadowing_test.dart`)
// each prove one slice against a bespoke `GoRouter` and a hand-built
// container. NONE of that tier drives:
//   • the REAL post-login landing dispatch putting a SALON_OWNER on their own
//     `/salons/{primary}` shell;
//   • the REAL `SalonBottomNav` tile 1, through a REAL tap, mounting the
//     board in shell slot 1;
//   • the REAL `GET /bookings/salon/{salonId}` + `GET /salons/{id}/masters`
//     chain behind `BookingsDiscoveryView` against a real (fake) HTTP
//     backend — including that NOTHING filter-shaped goes on that wire;
//   • the REAL `auth_redirect.dart` gate deciding where a card tap lands.
//
// THE BUG THIS FLOW WOULD HAVE CAUGHT
// -----------------------------------
// The board shipped pushing `RouteNames.bookingDetail` (`/bookings/:id`).
// `/bookings` is a CLIENT branch prefix, so the REAL redirect bounced the
// owner to `roleHomePath(SALON_OWNER)` — clean out of the salon shell. Every
// widget-tier test passed, because each stubbed `onBookingTap` or registered
// its own router without the gate. Only this tier runs the real one, which is
// exactly why Rule 3b exists.
//
// NO PATROL FLOW: this journey touches no OS permission dialog, no deep link
// / app link, no FCM or local notification, no WebView and no biometric
// prompt. It is a pure screen / route / provider / GET journey, so Step 2.7
// Rule 3b's `integration_test/patrol/` requirement does not apply. Stated
// explicitly (mobile-qa), not omitted.
//
// CLOCK: `AppHarness.boot` pins `clockProvider` to `kFixedNow` for the whole
// tier (`e2e_boot_policy.dart`), and every fixture below is derived from that
// SAME constant. One clock, both halves — the coherence invariant is about
// MIXING a pinned clock with a host-clock fixture, never about pinning.
//
// FINDERS: widget Keys and widget TYPES only — never a Cyrillic UI string
// (`forbid_cyrillic_finder.sh`). The resolved PAGE TYPE is what is asserted
// after the drill-in, not the location string, per this repo's
// literal-before-dynamic go_router shadowing trap.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_column_strip.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_bookings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The owner's OWN primary salon — the id `roleHomePath` lands them on, and
/// therefore the id the board mounts for. NOT `salon-xyz`: pointing the flow
/// at the older fixture salon would have exercised a shell the owner never
/// reaches by logging in.
const String _kSalonId = FakeBackend.kOwnerSalonId;

/// 10:00 and 12:30 Kyiv on the board's own day, as the canonical UTC instants
/// a `BookingResponse` carries. Derived from [kFixedNow] through the SAME
/// `kyivToday` the screen's seed query uses, so the fixtures and the fetched
/// day cannot disagree on ANY host timezone (the dev VM is Europe/Kyiv, which
/// masks exactly this class of bug).
DateTime _atKyivHour(int hour, int minute) {
  final DateTime day = kyivToday(() => kFixedNow);
  // Kyiv is UTC+3 in June.
  return DateTime.utc(day.year, day.month, day.day, hour - 3, minute);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'SALON_OWNER logs in, taps «Записи» in their own salon shell, sees the '
    'salon-wide board with one column per roster master, and drills into a '
    'booking WITHOUT being bounced out of the shell',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()
          ..currentRole = UserRole.salonOwner
          // Phase 320 — this flow drills into `GET /bookings/booking-1` as the
          // OWNER, who is not `booking-1`'s performing master (`master-aaa`).
          // `BookingService#computeProviderCanReviewClient` (backend
          // `a0df4cf`) answers on `isPerformingMasterOfBooking(...)` alone, so
          // the real server returns `false` here; the fake's `true` default
          // models the performing master's view and would misrepresent this
          // session.
          ..bookingProviderCanReviewClient = false;

        final GoRouter router = await AppHarness.boot(tester, fb);

        // Seeded AFTER boot, deliberately: [_atKyivHour] reads
        // `beauticaZone`, which `initBeauticaTimeZones()` only populates as
        // part of app/harness startup. The handler reads this list at REQUEST
        // time (never at registration), and the board does not mount until
        // the tab tap far below, so nothing has been fetched yet.
        //
        // Two DIFFERENT masters on one day — the whole point of a salon-wide
        // board, and the only shape that can tell a real partition apart from
        // a single-column list that happens to render.
        fb.salonBoardBookings = <Map<String, dynamic>>[
          fb.salonBoardBookingRow(
            id: 'booking-1',
            masterId: 'master-aaa',
            masterFirstName: 'Софія',
            masterLastName: 'Бондар',
            startsAt: _atKyivHour(10, 0),
          ),
          fb.salonBoardBookingRow(
            id: 'board-booking-2',
            masterId: 'master-ccc',
            masterFirstName: 'Марія',
            masterLastName: 'Гриценко',
            startsAt: _atKyivHour(12, 30),
          ),
        ];
        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);

        // ── The REAL landing dispatch ──────────────────────────────────────
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonShellScreen),
          timeout: const Duration(seconds: 20),
        );
        AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonId));

        // ── The REAL bottom-nav tap onto slot 1 ────────────────────────────
        final Finder bookingsTab = find.byKey(const Key('salon-nav-tile-1'));
        await AppHarness.pumpUntilFound(
          tester,
          bookingsTab,
          timeout: const Duration(seconds: 20),
        );
        try {
          await tester.ensureVisible(bookingsTab);
        } catch (_) {}
        await AppHarness.pumpUntilFound(
          tester,
          bookingsTab.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(bookingsTab);
        await tester.pump();

        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonBookingsScreen),
          timeout: const Duration(seconds: 20),
        );
        expect(find.byKey(const Key('salon-bookings-screen')), findsOneWidget);

        // ── The REAL fetch chain ───────────────────────────────────────────
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(BookingsTimelineGrid),
          timeout: const Duration(seconds: 20),
        );

        expect(
          fb.getSalonBookingsCalls,
          greaterThan(0),
          reason: 'the board must fetch GET /bookings/salon/{salonId}',
        );
        // The endpoint takes NO status list and NO service predicate — the
        // narrowing is client-side. Asserted at the ONE tier that can see the
        // real query string Dio produced.
        final Map<String, dynamic> query = fb.lastSalonBookingsQuery!;
        expect(
          query.containsKey('status'),
          isFalse,
          reason:
              'sending a single status would make the truncation boundary '
              'depend on which filter the owner picked — the rejected design '
              'named in bookings_day_notifier.dart',
        );
        expect(query.containsKey('serviceId'), isFalse);
        expect(query['size'].toString(), '100');

        // ── The board itself: a COLUMN PER MASTER, not one merged list ─────
        expect(find.byType(MasterColumnStrip), findsOneWidget);
        expect(
          find.byKey(
            const ValueKey<String>('salon-bookings-column-chip-master-aaa'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey<String>('salon-bookings-column-chip-master-ccc'),
          ),
          findsOneWidget,
        );
        // Both masters' cards, by id — data binding, not a smoke check.
        expect(
          find.byKey(const ValueKey<String>('timeline-card-booking-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('timeline-card-board-booking-2')),
          findsOneWidget,
        );

        // ── THE DRILL-IN ───────────────────────────────────────────────────
        final Finder card = find.byKey(
          const ValueKey<String>('timeline-card-booking-1'),
        );
        try {
          await tester.ensureVisible(card);
        } catch (_) {}
        await AppHarness.pumpUntilFound(
          tester,
          card.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(card);
        await tester.pump();

        await AppHarness.pumpUntilFound(
          tester,
          find.byType(BookingDetailScreen),
          timeout: const Duration(seconds: 20),
        );

        // ANTI-VACUITY: "the detail screen rendered" is not enough on its own
        // — the owner must ALSO still be inside their salon shell. The
        // shipped bug rendered no detail screen at all AND left the owner on
        // `roleHomePath`, so both halves are asserted.
        //
        // The board itself stays MOUNTED underneath: the detail is pushed
        // onto the root navigator over the shell, which is the whole point of
        // a pushed leaf (swipe-back returns to the still-scrolled board). So
        // the observable is the LOCATION, not the board's absence.
        expect(find.byType(SalonBookingsScreen), findsOneWidget);
        expect(
          AppHarness.location(router),
          equals(RouteNames.salonStaffBookingDetail('booking-1')),
          reason:
              'RouteNames.bookingDetail (/bookings/:id) is CLIENT-gated — an '
              'owner who lands there is redirected to roleHomePath and leaves '
              'the salon shell entirely',
        );
        expect(
          AppHarness.location(router),
          isNot(equals(RouteNames.bookingDetail('booking-1'))),
        );
      });
    },
  );

  testWidgets(
    'the board renders NO cards and no crash when the salon day is empty — '
    'the roster strip still states WHICH masters are free',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()
          ..currentRole = UserRole.salonOwner
          ..salonBoardBookings = <Map<String, dynamic>>[];

        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonShellScreen),
          timeout: const Duration(seconds: 20),
        );
        AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonId));

        final Finder bookingsTab = find.byKey(const Key('salon-nav-tile-1'));
        await AppHarness.pumpUntilFound(
          tester,
          bookingsTab.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(bookingsTab);
        await tester.pump();

        await AppHarness.pumpUntilFound(
          tester,
          find.byType(MasterColumnStrip),
          timeout: const Duration(seconds: 20),
        );

        // The locked decision: an owner must be able to see WHICH masters are
        // free, so an empty day draws the roster and a ruled, card-less grid
        // rather than an illustration.
        expect(find.byType(MasterBookingCard), findsNothing);
        expect(
          find.byKey(
            const ValueKey<String>('salon-bookings-column-chip-master-aaa'),
          ),
          findsOneWidget,
        );
        expect(find.byType(BookingsTimelineGrid), findsOneWidget);
      });
    },
  );
}
