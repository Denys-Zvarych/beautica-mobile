// VelvetBottomNavBar tap-to-navigate contract (Phase 6.x — nav bar wired to
// go_router). The bar is self-contained: it takes only `activeIndex` and calls
// `context.go(...)` internally via `_VelvetNavTile._routeFor(index)`.
//
// These tests pump the real production widget inside a real GoRouter with stub
// destination routes (mirroring profile_to_services_navigation_test.dart), tap
// a keyed tile, and assert the router's current location changed (or did not,
// for the no-op cases). No providers are required — the bar reads nothing from
// Riverpod — so no ProviderScope/overrides are needed.
//
// Keys under test (defined in profile_avatar.dart):
//   master-nav-tile-0 → Послуги  → context.go('/services')
//   master-nav-tile-1 → Мої записи → no route yet (onTap == null, no-op)
//   master-nav-tile-2 → Календар  → context.go('/master/working-hours')
//   master-nav-tile-3 → Профіль   → current shell; active tile is always a no-op
//
// pumpAndSettle IS used: the only animation is the 200 ms camel-pill
// AnimatedContainer, which is finite and drains cleanly.

import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Router builder — hosts the nav bar at /master/profile plus stub destination
// routes for /services and /master/working-hours. Each stub renders a keyed
// marker widget so we can ground-truth that the destination actually mounted,
// in addition to asserting the router's reported location.
// ---------------------------------------------------------------------------

const Key _servicesMarker = Key('stub-services-screen');
const Key _workingHoursMarker = Key('stub-working-hours-screen');

GoRouter _buildRouter({required int activeIndex}) => GoRouter(
  initialLocation: RouteNames.masterProfile,
  redirect: (context, state) => null,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterProfile,
      builder: (context, _) => Scaffold(
        // Bar lives at the bottom of the host route; only `activeIndex` varies.
        bottomNavigationBar: VelvetBottomNavBar(activeIndex: activeIndex),
      ),
    ),
    GoRoute(
      path: RouteNames.services,
      builder: (context, _) => const Scaffold(
        body: SizedBox.shrink(key: _servicesMarker),
      ),
    ),
    GoRoute(
      path: RouteNames.workingHours,
      builder: (context, _) => const Scaffold(
        body: SizedBox.shrink(key: _workingHoursMarker),
      ),
    ),
  ],
);

MaterialApp _app(GoRouter router) => MaterialApp.router(routerConfig: router);

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  group('VelvetBottomNavBar tap-to-navigate', () {
    testWidgets(
      'tapping Календар (master-nav-tile-2) navigates to /master/working-hours',
      (tester) async {
        final router = _buildRouter(activeIndex: 3); // Профіль active
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        expect(
          _location(router),
          RouteNames.masterProfile,
          reason: 'precondition: bar hosted on the profile route',
        );

        await tester.tap(find.byKey(const Key('master-nav-tile-2')));
        await tester.pumpAndSettle();

        expect(
          _location(router),
          RouteNames.workingHours,
          reason:
              'tapping the Календар tile must context.go(workingHours) — the '
              'requested behavior',
        );
        expect(
          find.byKey(_workingHoursMarker),
          findsOneWidget,
          reason: 'the working-hours destination route must mount after the tap',
        );
      },
    );

    testWidgets(
      'tapping Послуги (master-nav-tile-0) navigates to /services',
      (tester) async {
        final router = _buildRouter(activeIndex: 3); // Профіль active
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('master-nav-tile-0')));
        await tester.pumpAndSettle();

        expect(
          _location(router),
          RouteNames.services,
          reason: 'tapping the Послуги tile must context.go(services)',
        );
        expect(
          find.byKey(_servicesMarker),
          findsOneWidget,
          reason: 'the services destination route must mount after the tap',
        );
      },
    );

    testWidgets(
      'tapping the active tile (master-nav-tile-3, activeIndex 3) is a no-op',
      (tester) async {
        final router = _buildRouter(activeIndex: 3); // Профіль active
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('master-nav-tile-3')));
        await tester.pumpAndSettle();

        expect(
          _location(router),
          RouteNames.masterProfile,
          reason:
              'the already-active tile resolves to a null route — onTap is '
              'null, so the location must not change',
        );
      },
    );
  });
}
