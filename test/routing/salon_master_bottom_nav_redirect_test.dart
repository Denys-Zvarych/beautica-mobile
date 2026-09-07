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
// Tiles 0 (Послуги) and 1 (Мої записи) still have no `/staff/*` counterpart
// and keep bouncing — see `salon_master_profile_screen.dart`'s header
// (narrowed by Phase 310 D3).
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
const Key _bookingsMarker = Key('stub-master-bookings-screen');
const Key _staffScheduleMarker = Key('stub-staff-schedule-screen');

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
      // `scheduleRoute` is the ONLY override this call site passes (tile 3
      // is active here, so `profileRoute` is never read — Phase 310 D2).
      builder: (context, _) => const Scaffold(
        body: SizedBox.shrink(key: _staffProfileMarker),
        bottomNavigationBar: VelvetBottomNavBar(
          activeIndex: 3,
          scheduleRoute: RouteNames.salonMasterSchedule,
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
    GoRoute(
      path: RouteNames.masterBookings,
      builder: (context, _) => const Scaffold(
        body: SizedBox.shrink(key: _bookingsMarker),
        bottomNavigationBar: VelvetBottomNavBar(activeIndex: 1),
      ),
    ),
    GoRoute(
      path: RouteNames.salonMasterSchedule,
      // Mirrors `master_schedule_screen.dart:461` production wiring: BOTH
      // overrides passed, resolved off the role (here always SALON_MASTER)
      // — `profileRoute` is what makes tile 3's landing a single hop.
      builder: (context, _) => const Scaffold(
        body: SizedBox.shrink(key: _staffScheduleMarker),
        bottomNavigationBar: VelvetBottomNavBar(
          activeIndex: 2,
          scheduleRoute: RouteNames.salonMasterSchedule,
          profileRoute: RouteNames.salonMasterProfile,
        ),
      ),
    ),
  ],
);

MaterialApp _app(GoRouter router) => MaterialApp.router(routerConfig: router);

// Every navigation in this file is `context.go` (the nav-bar tile's own
// onTap) or a redirect — never `context.push` — so the `ImperativeRouteMatch`
// exclusion this raw read would otherwise be fragile to never bites here
// (mirrors `profile_nav_bar_navigation_test.dart`'s identical `_location`
// helper, grandfathered for the same reason).
String _location(GoRouter router) =>
    // router-location-ok: go-only navigation, no push, so the raw read is safe.
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  group('SALON_MASTER tapping VelvetBottomNavBar tiles 0/1 still bounces '
      'back to /staff/profile with no intermediate frame', () {
    testWidgets('precondition: SALON_MASTER lands on /staff/profile with '
        'the bar at activeIndex 3', (tester) async {
      final router = _buildRouter();
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      expect(find.byKey(_staffProfileMarker), findsOneWidget);
      expect(_location(router), RouteNames.salonMasterProfile);
    });

    testWidgets(
      'tapping tile 0 (Послуги, /services) never renders the services '
      'screen — the redirect fires before the destination page builds',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('master-nav-tile-0')));
        // A SINGLE frame — if the redirect did not fire synchronously
        // before the page builds, the services screen would be visible
        // right here, even if it is later replaced.
        await tester.pump();

        expect(
          find.byKey(_servicesMarker),
          findsNothing,
          reason:
              'go_router evaluates `redirect:` before building the '
              'destination page — a SALON_MASTER must never see so much '
              'as one frame of the INDEPENDENT_MASTER-only /services '
              'screen',
        );
        expect(
          find.byKey(_staffProfileMarker),
          findsOneWidget,
          reason:
              'the origin must still be mounted — the bounce is a '
              'same-location no-op, not a round trip through another '
              'screen',
        );

        await tester.pumpAndSettle();
        expect(_location(router), RouteNames.salonMasterProfile);
      },
    );

    testWidgets(
      'tapping tile 1 (Мої записи, /master/bookings) never renders the '
      'master-bookings screen',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('master-nav-tile-1')));
        await tester.pump();

        expect(find.byKey(_bookingsMarker), findsNothing);
        expect(find.byKey(_staffProfileMarker), findsOneWidget);

        await tester.pumpAndSettle();
        expect(_location(router), RouteNames.salonMasterProfile);
      },
    );

    testWidgets(
      'the bar itself is still present after the bounce — the master is '
      'never left on a screen with no way to navigate',
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
