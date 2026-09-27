// Phase 330 / 332 — E2E: the SALON_MASTER's real «Записи» journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// This track makes a user journey reachable for a NEW ROLE. The dense
// unit/widget coverage (`bookings_capability_test.dart`,
// `bookings_read_only_salon_master_test.dart`,
// `master_archive_screen_test.dart`'s phase-332 group,
// `salon_master_bookings_route_shadowing_test.dart`,
// `salon_master_bottom_nav_redirect_test.dart`,
// `auth_redirect_test.dart`'s `/staff/*` matrix) each prove one slice against
// a bespoke `GoRouter` and a hand-built container. None of that tier drives:
//   • the REAL post-login landing dispatch (`roleHomePath`) putting a
//     SALON_MASTER on `/staff/profile`;
//   • the REAL `VelvetBottomNavBar` tile 1, built with its phase-330
//     `bookingsRoute` override, through a REAL tap;
//   • the REAL `auth_redirect.dart` gate admitting `/staff/bookings` while
//     leaving `/master/bookings` closed, resolved by the ACTUAL redirect
//     callback wired into `appRouter`;
//   • the REAL `GET /bookings/me` chain behind `BookingsDiscoveryView`
//     against a real (fake) HTTP backend;
//   • that the read-only and the writable renderings are the SAME widget
//     tree reached through the SAME real navigation stack.
//
// Mirrors `salon_master_schedule_nav_flow_test.dart` (phase 309/310), the
// sibling journey for tile 2 — same harness, same two-arm shape
// (SALON_MASTER + INDEPENDENT_MASTER control), same finder discipline.
//
// ANTI-VACUITY: the add (+) button's absence is asserted on the SALON_MASTER
// arm and its PRESENCE on the INDEPENDENT_MASTER arm, on the same fixture and
// the same screen. Without that control an absence would also pass if the
// header never rendered at all (M14).
//
// NO PATROL FLOW: nothing in this journey touches an OS permission dialog, a
// deep link / app link, FCM or a local notification, a WebView, or a
// biometric prompt. It is a pure screen / route / provider / GET journey, so
// Step 2.7 Rule 3b's `integration_test/patrol/` requirement does not apply.
// Stated explicitly (mobile-qa), not omitted.
//
// FINDERS: widget Keys and widget TYPES only — never a Cyrillic UI string
// (`forbid_cyrillic_finder.sh`). `find.byType(MasterBookingsScreen)` (not a
// route-string assertion alone) pins the resolved page, per the go_router
// literal-before-dynamic-shadowing trap this repo has been bitten by before.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/master_archive_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/salon_master_profile_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'SALON_MASTER taps «Записи» from /staff/profile, lands on the REAL '
    'read-only bookings screen at /staff/bookings with NO add button, and '
    'can open the archive from there',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend();
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.salonMaster);
        await AppHarness.settle(tester);

        // ── Landing ──────────────────────────────────────────────────────
        expect(find.byType(SalonMasterProfileScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.salonMasterProfile);

        // ── Tap the REAL «Записи» nav tile ──────────────────────────────
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('master-nav-tile-1')),
        );
        await AppHarness.settle(tester);

        // Pin the resolved page TYPE, not the route string — a string
        // assertion alone passes under go_router's literal-before-dynamic
        // shadowing even if a different page happened to build.
        expect(find.byType(MasterBookingsScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.salonMasterBookings);

        // The tile did NOT bounce: before phase 330 this tap landed the user
        // straight back on the screen they were standing on.
        expect(find.byType(SalonMasterProfileScreen), findsNothing);

        // ── The screen's own chrome renders ─────────────────────────────
        expect(
          find.byKey(const Key('master-bookings-screen')),
          findsOneWidget,
          reason:
              'ANTI-VACUITY — the discovery header/body must actually be on '
              'screen, otherwise the missing-(+) assertion below would pass '
              'on a blank page.',
        );

        // ── The write affordance is ABSENT, not disabled ────────────────
        expect(
          find.byKey(const Key('master-bookings-add')),
          findsNothing,
          reason:
              'bookingCreationEnabledProvider resolves false for '
              'SALON_MASTER, so the manual add-booking entry point must not '
              'be drawn at all.',
        );

        // ── Phase 332: the archive is reachable from here ───────────────
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('master-bookings-open-archive')),
        );
        await AppHarness.settle(tester);

        expect(
          find.byType(MasterArchiveScreen),
          findsOneWidget,
          reason:
              'the archive is where a salon master\'s COMPLETED bookings — '
              'and therefore the only reachable review capability — live; '
              'if :bookingId ever shadows the archive literal this goes red.',
        );
        AppHarness.expectLocation(
          router,
          RouteNames.salonMasterBookingsArchive,
        );
      });
    },
  );

  testWidgets(
    'CONTROL — INDEPENDENT_MASTER\'s identical journey still lands on '
    '/master/bookings with the add (+) button PRESENT',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend();
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
        await AppHarness.settle(tester);

        expect(find.byType(MasterProfileScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.masterProfile);

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('master-nav-tile-1')),
        );
        await AppHarness.settle(tester);

        expect(find.byType(MasterBookingsScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.masterBookings);

        expect(
          find.byKey(const Key('master-bookings-add')),
          findsOneWidget,
          reason:
              'the SAME screen, the SAME harness — only the session differs. '
              'Without this arm the absence above would also pass if the '
              'header stopped rendering entirely.',
        );

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('master-bookings-open-archive')),
        );
        await AppHarness.settle(tester);

        expect(find.byType(MasterArchiveScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.masterBookingsArchive);
      });
    },
  );
}
