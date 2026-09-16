// SALON_MASTER bottom-nav-bar tap-through redirect gate (item 5, mobile-qa
// 2026-09-01, Rule 3b negative matrix).
//
// WHY THIS FILE EXISTS
// ---------------------
// `SalonMasterProfileScreen` gained `bottomNavigationBar: const
// VelvetBottomNavBar(activeIndex: 3)` on `ProfileScaffold` (item B). That
// bar's tiles were ROLE-AGNOSTIC — `_VelvetNavTile._routeFor` hardcoded
// `RouteNames.services` / `.masterBookings` / `.masterSchedule` regardless of
// who is looking at it — because it was built for INDEPENDENT_MASTER and
// reused verbatim for SALON_MASTER. All three destinations were gated to
// INDEPENDENT_MASTER only in `auth_redirect.dart` (the `/services`,
// `/master/*` and `/schedule` role gates).
//
// Phase 309/310 CLOSED this gap for tile 2 (Графік) specifically: it now
// targets `RouteNames.salonMasterSchedule` (`/staff/schedule`, an additive
// `scheduleRoute` override — see `velvet_bottom_nav_bar.dart` D1/D2), which
// renders the SAME `MasterScheduleScreen` read-only and does NOT bounce.
// Phase 321 CLOSED it for tile 0 (Послуги) too: it now targets
// `RouteNames.salonMasterServices` (`/staff/services`, an additive
// `servicesRoute` override), which renders the SAME `ServicesListScreen`
// read-only (`writable: false`) and does NOT bounce. Phase 330 CLOSED THE
// LAST ONE: tile 1 (Мої записи) now targets
// `RouteNames.salonMasterBookings` (`/staff/bookings`, an additive
// `bookingsRoute` override), which renders the SAME `MasterBookingsScreen`
// read-only and does NOT bounce either. All four tiles now land.
//
// What did NOT change, and is pinned below: `/master/bookings` and every
// leaf under it still bounce a SALON_MASTER. The `/master/*` gate in
// `auth_redirect.dart` is byte-unchanged by all three phases — each tile got
// its own `/staff/*` counterpart instead of a widened fence.
//
// `role_landing_chrome_matrix.dart` proves the bar RENDERS; `auth_redirect
// _test.dart` proves the pure redirect FUNCTION bounces SALON_MASTER off
// `/schedule` and its subtree (`/schedule/weekly`, `/schedule/day`,
// `/schedule/copy`) back to `/staff/profile`, and admits SALON_MASTER at
// `/staff/schedule` with no redirect. Neither proves the two are wired
// together — that tapping a tile does what `_routeFor` claims. This file
// closes that gap for all four tiles.
//
// Real `authRedirectForLocation` is wired into the router's `redirect:`
// callback (mirrors `navigation_links_test.dart`'s NL-22 harness) — only the
// destination SCREENS are stubbed, so this stays a widget-tier test, not an
// integration one.
//
// Layer: Widget (router + real authRedirect, stub destinations).

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/routing/auth_redirect.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _salonMasterUser = User(
  id: 'u-sm-nav',
  email: 'salonmaster-nav@example.com',
  role: UserRole.salonMaster,
  firstName: 'Salon',
  lastName: 'Master',
);

const _salonMasterSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _salonMasterUser, accessToken: 'token'),
);

const Key _staffProfileMarker = Key('stub-staff-profile-screen');
const Key _servicesMarker = Key('stub-services-screen');
const Key _serviceSetupMarker = Key('stub-service-setup-screen');
const Key _serviceEditMarker = Key('stub-service-edit-screen');
const Key _bookingsMarker = Key('stub-master-bookings-screen');
const Key _bookingsArchiveMarker = Key('stub-master-bookings-archive-screen');
const Key _bookingDetailMarker = Key('stub-master-booking-detail-screen');
const Key _staffBookingsMarker = Key('stub-staff-bookings-screen');
const Key _staffScheduleMarker = Key('stub-staff-schedule-screen');
const Key _staffServicesMarker = Key('stub-staff-services-screen');

/// A minimal router hosting the real INDEPENDENT_MASTER-only destinations
/// PLUS `/staff/profile` and `/staff/schedule`, all wired through the real
/// `authRedirect` guard for a FIXED SALON_MASTER session (the session never
/// changes mid-test, so no `refreshListenable` container plumbing is needed
/// — mirrors `auth_redirect_test.dart`'s pure-function fixtures, just driven
/// through a live router instead of called directly).
///
/// [redirectLog] (Phase 310 D2 proof), when given, records every
/// `state.matchedLocation` the `redirect:` callback was asked to resolve —
/// used to assert tile 3's landing from `/staff/schedule` is a SINGLE
/// navigation (no intermediate `/master/profile` hop that the gate then
/// has to correct).
GoRouter _buildRouter({List<String>? redirectLog}) => GoRouter(
  initialLocation: RouteNames.salonMasterProfile,
  redirect: (context, state) {
    redirectLog?.add(state.matchedLocation);
    return authRedirectForLocation(_salonMasterSession, state.matchedLocation);
  },
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.salonMasterProfile,
      // Mirrors `salon_master_profile_screen.dart:232` production wiring:
      // `scheduleRoute` and `servicesRoute` are the overrides this call site
      // passes (tile 3 is active here, so `profileRoute` is never read —
      // Phase 310 D2 / Phase 321 D1).
      builder: (context, _) => const Scaffold(
        body: SizedBox.shrink(key: _staffProfileMarker),
        bottomNavigationBar: VelvetBottomNavBar(
          activeIndex: 3,
          scheduleRoute: RouteNames.salonMasterSchedule,
          servicesRoute: RouteNames.salonMasterServices,
          bookingsRoute: RouteNames.salonMasterBookings,
        ),
      ),
    ),
    GoRoute(
      path: RouteNames.services,
      builder: (context, _) => const Scaffold(
        body: SizedBox.shrink(key: _servicesMarker),
        bottomNavigationBar: VelvetBottomNavBar(activeIndex: 0),
      ),
    ),
    // Registered so the "still bounced off /services*" matrix exercises the
    // WIRED redirect (a live router evaluating a real destination), not just
    // the pure `authRedirectForLocation` function `auth_redirect_test.dart`
    // already covers for these two leaves.
    GoRoute(
      path: RouteNames.serviceSetup,
      builder: (context, _) =>
          const Scaffold(body: SizedBox.shrink(key: _serviceSetupMarker)),
    ),
    GoRoute(
      path: '/services/:id/edit',
      builder: (context, _) =>
          const Scaffold(body: SizedBox.shrink(key: _serviceEditMarker)),
    ),
    GoRoute(
      path: RouteNames.masterBookings,
      builder: (context, _) => const Scaffold(
        body: SizedBox.shrink(key: _bookingsMarker),
        bottomNavigationBar: VelvetBottomNavBar(activeIndex: 1),
      ),
    ),
    // Registered so the "still bounced off /master/bookings*" matrix below
    // exercises the WIRED redirect against real destinations, exactly as the
    // `/services` write leaves above do.
    GoRoute(
      path: RouteNames.masterBookingsArchive,
      builder: (context, _) =>
          const Scaffold(body: SizedBox.shrink(key: _bookingsArchiveMarker)),
    ),
    GoRoute(
      path: '/master/bookings/:bookingId',
      builder: (context, _) =>
          const Scaffold(body: SizedBox.shrink(key: _bookingDetailMarker)),
    ),
    // Phase 330 — «Мої записи» LANDS here now. Mirrors the production
    // `/staff/bookings` registration's own bar wiring: tile 1 is active, so
    // the other three carry `/staff/*` overrides.
    GoRoute(
      path: RouteNames.salonMasterBookings,
      builder: (context, _) => const Scaffold(
        body: SizedBox.shrink(key: _staffBookingsMarker),
        bottomNavigationBar: VelvetBottomNavBar(
          activeIndex: 1,
          scheduleRoute: RouteNames.salonMasterSchedule,
          servicesRoute: RouteNames.salonMasterServices,
          profileRoute: RouteNames.salonMasterProfile,
        ),
      ),
    ),
    GoRoute(
      path: RouteNames.salonMasterSchedule,
      // Mirrors `master_schedule_screen.dart:461` production wiring: all
      // three overrides passed, resolved off the role (here always
      // SALON_MASTER) — `profileRoute` is what makes tile 3's landing a
      // single hop, `servicesRoute` the same for tile 0.
      builder: (context, _) => const Scaffold(
        body: SizedBox.shrink(key: _staffScheduleMarker),
        bottomNavigationBar: VelvetBottomNavBar(
          activeIndex: 2,
          scheduleRoute: RouteNames.salonMasterSchedule,
          profileRoute: RouteNames.salonMasterProfile,
          servicesRoute: RouteNames.salonMasterServices,
        ),
      ),
    ),
    // Phase 321 — «Послуги» LANDS here now (D2). Mirrors
    // `salon_master_profile_screen.dart:232` / `master_schedule_screen.dart
    // :461` production wiring for the destination itself: both overrides
    // resolved off the (always SALON_MASTER) role.
    GoRoute(
      path: RouteNames.salonMasterServices,
      builder: (context, _) => const Scaffold(
        body: SizedBox.shrink(key: _staffServicesMarker),
        bottomNavigationBar: VelvetBottomNavBar(
          activeIndex: 0,
          scheduleRoute: RouteNames.salonMasterSchedule,
          servicesRoute: RouteNames.salonMasterServices,
        ),
      ),
    ),
  ],
);

// `localizationsDelegates` is REQUIRED since the 2026-09-13 audit (M18):
// `VelvetBottomNavBar`'s four tile labels moved out of hardcoded literals
// into ARB, so the bar now reads `AppLocalizations.of(context)`.
MaterialApp _app(GoRouter router) => MaterialApp.router(
  routerConfig: router,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
);

// Every navigation in this file is `context.go` (the nav-bar tile's own
// onTap) or a redirect — never `context.push` — so the `ImperativeRouteMatch`
// exclusion this raw read would otherwise be fragile to never bites here
// (mirrors `profile_nav_bar_navigation_test.dart`'s identical `_location`
// helper, grandfathered for the same reason).
String _location(GoRouter router) =>
    // router-location-ok: go-only navigation, no push, so the raw read is safe.
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  group('SALON_MASTER tapping VelvetBottomNavBar tile 1 (Мої записи) LANDS '
      '— Phase 330', () {
    testWidgets('precondition: SALON_MASTER lands on /staff/profile with '
        'the bar at activeIndex 3', (tester) async {
      final router = _buildRouter();
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      expect(find.byKey(_staffProfileMarker), findsOneWidget);
      expect(_location(router), RouteNames.salonMasterProfile);
    });

    testWidgets(
      'tapping tile 1 renders the /staff/bookings destination — pinned by a '
      'marker key that is only present on THAT stub screen (not the route '
      'string alone), guarding against go_router literal-vs-dynamic '
      'shadowing; the real router type-level proof (both routes build '
      'MasterBookingsScreen) lives in '
      'salon_master_bookings_route_shadowing_test.dart',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('master-nav-tile-1')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(_staffBookingsMarker),
          findsOneWidget,
          reason:
              'Phase 330 registered /staff/bookings as a tab root reusing '
              'MasterBookingsScreen and retargeted this tile onto it. No '
              'redirect should fire.',
        );
        expect(find.byKey(_bookingsMarker), findsNothing);
        expect(find.byKey(_staffProfileMarker), findsNothing);
        expect(_location(router), RouteNames.salonMasterBookings);
      },
    );

    testWidgets('tapping tile 1 lands in ONE navigation — the tap never '
        'passes through the INDEPENDENT_MASTER-only /master/bookings '
        'literal and gets corrected by the gate', (tester) async {
      final redirectLog = <String>[];
      final router = _buildRouter(redirectLog: redirectLog);
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();
      redirectLog.clear();

      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await tester.pumpAndSettle();

      expect(
        redirectLog,
        <String>[RouteNames.salonMasterBookings],
        reason:
            'if bookingsRoute were NOT wired, the tap would go to '
            '/master/bookings and the log would show BOTH that (rejected) '
            'AND /staff/profile (the correction) — two matched locations '
            'for one tap.',
      );
    });

    testWidgets(
      'from /staff/bookings the bar is present — no dead end even though '
      'go leaves no back button',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('master-nav-tile-1')));
        await tester.pumpAndSettle();

        expect(find.byType(VelvetBottomNavBar), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------
  // Phase 330 D-list — the structural claim: gaining `/staff/bookings` does
  // NOT widen `/master/*`. Each leaf named individually so a single carve-out
  // cannot hide behind a sibling. Mutation: delete the `/master/` gate's
  // non-INDEPENDENT_MASTER bounce and all three must go RED.
  // ---------------------------------------------------------------------
  group('SALON_MASTER still bounced off /master/bookings and its leaves — '
      'Phase 330', () {
    testWidgets('/master/bookings still bounces to /staff/profile', (
      tester,
    ) async {
      final router = _buildRouter();
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      router.go(RouteNames.masterBookings);
      await tester.pumpAndSettle();

      expect(find.byKey(_bookingsMarker), findsNothing);
      expect(find.byKey(_staffProfileMarker), findsOneWidget);
      expect(_location(router), RouteNames.salonMasterProfile);
    });

    testWidgets('/master/bookings/archive still bounces to /staff/profile', (
      tester,
    ) async {
      final router = _buildRouter();
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      router.go(RouteNames.masterBookingsArchive);
      await tester.pumpAndSettle();

      expect(find.byKey(_bookingsArchiveMarker), findsNothing);
      expect(find.byKey(_staffProfileMarker), findsOneWidget);
      expect(_location(router), RouteNames.salonMasterProfile);
    });

    testWidgets('/master/bookings/:id still bounces to /staff/profile', (
      tester,
    ) async {
      final router = _buildRouter();
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      router.go(RouteNames.masterBookingDetail('b-001'));
      await tester.pumpAndSettle();

      expect(find.byKey(_bookingDetailMarker), findsNothing);
      expect(find.byKey(_staffProfileMarker), findsOneWidget);
      expect(_location(router), RouteNames.salonMasterProfile);
    });
  });

  // ---------------------------------------------------------------------
  // Phase 321 D2 — the structural claim: /services and its two write leaves
  // stay INDEPENDENT_MASTER-only for a SALON_MASTER even after tile 0 gains
  // its own `/staff/services` counterpart. Each of the three is named
  // individually — mutation check #5 deletes the `/services` gate's
  // SALON_MASTER bounce and requires all three to go RED.
  // ---------------------------------------------------------------------
  group('SALON_MASTER still bounced off /services and its write leaves — '
      'Phase 321 D2', () {
    testWidgets('/services still bounces to /staff/profile', (tester) async {
      final router = _buildRouter();
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      router.go(RouteNames.services);
      await tester.pumpAndSettle();

      expect(find.byKey(_servicesMarker), findsNothing);
      expect(find.byKey(_staffProfileMarker), findsOneWidget);
      expect(_location(router), RouteNames.salonMasterProfile);
    });

    testWidgets('/services/setup still bounces to /staff/profile', (
      tester,
    ) async {
      final router = _buildRouter();
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      router.go(RouteNames.serviceSetup);
      await tester.pumpAndSettle();

      expect(find.byKey(_serviceSetupMarker), findsNothing);
      expect(find.byKey(_staffProfileMarker), findsOneWidget);
      expect(_location(router), RouteNames.salonMasterProfile);
    });

    testWidgets('/services/:id/edit still bounces to /staff/profile', (
      tester,
    ) async {
      final router = _buildRouter();
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      router.go(RouteNames.serviceEdit('svc-1'));
      await tester.pumpAndSettle();

      expect(find.byKey(_serviceEditMarker), findsNothing);
      expect(find.byKey(_staffProfileMarker), findsOneWidget);
      expect(_location(router), RouteNames.salonMasterProfile);
    });
  });

  group('SALON_MASTER tapping tile 0 (Послуги) LANDS — Phase 321', () {
    testWidgets(
      'tapping tile 0 renders the /staff/services destination — pinned by '
      'a marker key that is only present on THAT stub screen (not the '
      'route string alone), guarding against go_router literal-vs-dynamic '
      'shadowing; the real router\'s type-level proof (both routes build '
      'ServicesListScreen) lives in app_router/auth_redirect coverage',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('master-nav-tile-0')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(_staffServicesMarker),
          findsOneWidget,
          reason:
              'Phase 321 registered /staff/services as its own top-level '
              'route reusing ServicesListScreen(writable: false); this '
              'tile now targets it. No redirect should fire.',
        );
        expect(find.byKey(_staffProfileMarker), findsNothing);
        expect(_location(router), RouteNames.salonMasterServices);
      },
    );

    testWidgets(
      'from /staff/services, the bar is present — no dead end even though '
      'go leaves no back button',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('master-nav-tile-0')));
        await tester.pumpAndSettle();

        expect(find.byType(VelvetBottomNavBar), findsOneWidget);
      },
    );
  });

  group('SALON_MASTER tapping tile 2 (Графік) LANDS — Phase 310', () {
    testWidgets(
      'tapping tile 2 renders the /staff/schedule destination — pinned by '
      'a marker key that is only present on THAT stub screen (not the '
      'route string alone), guarding against go_router literal-vs-dynamic '
      'shadowing; the real router\'s type-level proof (both routes build '
      'MasterScheduleScreen) lives in app_router/auth_redirect coverage',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('master-nav-tile-2')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(_staffScheduleMarker),
          findsOneWidget,
          reason:
              'Phase 309 registered /staff/schedule as its own top-level '
              'route reusing MasterScheduleScreen; Phase 310 retargeted '
              'this tile onto it. No redirect should fire.',
        );
        expect(find.byKey(_staffProfileMarker), findsNothing);
        expect(_location(router), RouteNames.salonMasterSchedule);
      },
    );

    testWidgets('from /staff/schedule, tapping tile 3 (Профіль) lands on '
        '/staff/profile in ONE navigation — no intermediate /master/profile '
        'hop (Phase 310 D2)', (tester) async {
      final redirectLog = <String>[];
      final router = _buildRouter(redirectLog: redirectLog);
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('master-nav-tile-2')));
      await tester.pumpAndSettle();
      expect(_location(router), RouteNames.salonMasterSchedule);
      redirectLog.clear();

      await tester.tap(find.byKey(const Key('master-nav-tile-3')));
      await tester.pumpAndSettle();

      expect(find.byKey(_staffProfileMarker), findsOneWidget);
      expect(_location(router), RouteNames.salonMasterProfile);
      expect(
        redirectLog,
        <String>[RouteNames.salonMasterProfile],
        reason:
            'if profileRoute were NOT wired, the tap would `go` to the '
            'INDEPENDENT_MASTER-only /master/profile literal, and the '
            'redirect log would show BOTH /master/profile (rejected) '
            'AND /staff/profile (the correction) — two matched '
            'locations for one tap. Exactly one proves the single-hop '
            'landing.',
      );
    });
  });
}
