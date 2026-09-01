// SALON_MASTER bottom-nav-bar tap-through redirect gate (item 5, mobile-qa
// 2026-09-01, Rule 3b negative matrix).
//
// WHY THIS FILE EXISTS
// ---------------------
// `SalonMasterProfileScreen` gained `bottomNavigationBar: const
// VelvetBottomNavBar(activeIndex: 3)` on `ProfileScaffold` (item B). That
// bar's tiles are ROLE-AGNOSTIC — `_VelvetNavTile._routeFor` hardcodes
// `RouteNames.services` / `.masterBookings` / `.masterSchedule` regardless of
// who is looking at it (`velvet_bottom_nav_bar.dart:174-181`) — because it
// was built for INDEPENDENT_MASTER and is now reused verbatim for
// SALON_MASTER. Those three destinations are gated to INDEPENDENT_MASTER
// only in `auth_redirect.dart` (the `/services`, `/master/*` and `/schedule`
// role gates). `role_landing_chrome_matrix.dart`'s flipped SALON_MASTER row
// (this same QA pass) proves the bar RENDERS; `auth_redirect_test.dart`
// proves the pure redirect FUNCTION bounces SALON_MASTER off each of those
// three prefixes back to `/staff/profile`. Neither proves the two are wired
// together — that tapping tile 0/1/2 as SALON_MASTER never lands on so much
// as one frame of the guarded destination before the router bounces back.
// This file closes that gap.
//
// Real `authRedirectForLocation` is wired into the router's `redirect:`
// callback (mirrors `navigation_links_test.dart`'s NL-22 harness, named
// explicitly in this pass's own brief as the established pattern for
// exercising the real router + real guard together) — only the three
// destination SCREENS are stubbed, so this stays a widget-tier test, not an
// integration one (see this pass's Rule 3b note for why that split is
// deliberate).
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
const Key _scheduleMarker = Key('stub-schedule-screen');

/// A minimal router hosting the real INDEPENDENT_MASTER-only destinations
/// PLUS `/staff/profile`, all wired through the real `authRedirect` guard for
/// a FIXED SALON_MASTER session (the session never changes mid-test, so no
/// `refreshListenable` container plumbing is needed — mirrors
/// `auth_redirect_test.dart`'s pure-function fixtures, just driven through a
/// live router instead of called directly).
GoRouter _buildRouter() => GoRouter(
  initialLocation: RouteNames.salonMasterProfile,
  redirect: (context, state) =>
      authRedirectForLocation(_salonMasterSession, state.matchedLocation),
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.salonMasterProfile,
      builder: (context, _) => const Scaffold(
        body: SizedBox.shrink(key: _staffProfileMarker),
        bottomNavigationBar: VelvetBottomNavBar(activeIndex: 3),
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
      path: RouteNames.masterSchedule,
      builder: (context, _) => const Scaffold(
        body: SizedBox.shrink(key: _scheduleMarker),
        bottomNavigationBar: VelvetBottomNavBar(activeIndex: 2),
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
  group('SALON_MASTER tapping VelvetBottomNavBar tiles 0-2 bounces back to '
      '/staff/profile with no intermediate frame', () {
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

    testWidgets('tapping tile 2 (Графік, /schedule) never renders the schedule '
        'screen', (tester) async {
      final router = _buildRouter();
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('master-nav-tile-2')));
      await tester.pump();

      expect(find.byKey(_scheduleMarker), findsNothing);
      expect(find.byKey(_staffProfileMarker), findsOneWidget);

      await tester.pumpAndSettle();
      expect(_location(router), RouteNames.salonMasterProfile);
    });

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
}
