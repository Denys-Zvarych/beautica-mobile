// VelvetBottomNavBar tap-to-navigate contract (Phase 6.x — nav bar wired to
// go_router). The bar is self-contained: it takes only `activeIndex` and calls
// `context.push(...)` internally via `_VelvetNavTile._routeFor(index)`.
//
// DRILL-IN FIX (Step 2.7 Rule 3): the nav tile onTap was changed from
// `context.go(route)` (replaced the navigator stack → no AppBar back button,
// dead left-edge swipe-back — the user was stranded on "Мої послуги") to
// `context.push(route)` (the destination is pushed ON TOP of the origin, so the
// back button and edge-swipe-back both work; `pop()` returns to the origin).
// This is the user-approved drill-in behavior, NOT a StatefulShellRoute refactor.
//
// CONTRACT under push:
//   - Tapping a non-active tile mounts the destination AND leaves the origin on
//     the back stack (router.canPop() == true). Location is NOT replaced.
//   - Popping returns to the originating (profile) screen.
//   - Re-tapping the already-active tile resolves to a null route (onTap == null)
//     → no push, the stack is unchanged.
//
// NOTE on go_router path inspection: `currentConfiguration.uri` reflects the
// initial location and does NOT update after a `context.push(...)`. Asserting on
// `_location(router)` would therefore be wrong here — we ground-truth via the
// destination marker widget + `router.canPop()` instead, mirroring the
// "menu button pushes masterMenu (swipe-back regression guard)" group in
// master_profile_screen_test.dart.
//
// Keys under test (defined in profile_avatar.dart):
//   master-nav-tile-0 → Послуги  → context.push('/services')
//   master-nav-tile-1 → Мої записи → context.push('/master/bookings')  [7.6]
//   master-nav-tile-2 → Календар  → context.push('/schedule')
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
// routes for /services and /schedule. Each route renders a keyed marker widget
// so we can ground-truth which screen is mounted: the origin marker proves we
// returned after a pop, the destination markers prove the push landed.
// ---------------------------------------------------------------------------

const Key _profileMarker = Key('stub-profile-screen');
const Key _servicesMarker = Key('stub-services-screen');
const Key _scheduleMarker = Key('stub-schedule-screen');
const Key _bookingsMarker = Key('stub-master-bookings-screen');

GoRouter _buildRouter({required int activeIndex}) => GoRouter(
  initialLocation: RouteNames.masterProfile,
  redirect: (context, state) => null,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterProfile,
      builder: (context, _) => Scaffold(
        body: const SizedBox.shrink(key: _profileMarker),
        // Bar lives at the bottom of the host route; only `activeIndex` varies.
        bottomNavigationBar: VelvetBottomNavBar(activeIndex: activeIndex),
      ),
    ),
    GoRoute(
      path: RouteNames.services,
      builder: (context, _) =>
          const Scaffold(body: SizedBox.shrink(key: _servicesMarker)),
    ),
    GoRoute(
      path: RouteNames.masterSchedule,
      builder: (context, _) =>
          const Scaffold(body: SizedBox.shrink(key: _scheduleMarker)),
    ),
    // Phase 7.6 — the «Мої записи» destination that tile 1 had no route to
    // until this phase.
    GoRoute(
      path: RouteNames.masterBookings,
      builder: (context, _) =>
          const Scaffold(body: SizedBox.shrink(key: _bookingsMarker)),
    ),
  ],
);

MaterialApp _app(GoRouter router) => MaterialApp.router(routerConfig: router);

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  group('VelvetBottomNavBar tap-to-navigate (push drill-in)', () {
    testWidgets(
      'tapping Мої записи (master-nav-tile-1) pushes /master/bookings and '
      'leaves the origin poppable — the tab that went nowhere until Phase 7.6',
      (tester) async {
        final router = _buildRouter(activeIndex: 3); // Профіль active
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        expect(find.byKey(_profileMarker), findsOneWidget);
        expect(router.canPop(), isFalse);

        await tester.tap(find.byKey(const Key('master-nav-tile-1')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(_bookingsMarker),
          findsOneWidget,
          reason:
              'tile 1 must now resolve to RouteNames.masterBookings — it was '
              'a documented no-op ("no route yet") before Phase 7.6.',
        );
        expect(
          router.canPop(),
          isTrue,
          reason:
              'push (not go) — the profile origin must stay on the back stack '
              'so the back button and edge-swipe work.',
        );

        // Deliberately NOT the client «Мої записи»: /bookings lives under the
        // client shell branch and its CLIENT-only guard.
        expect(_location(router), isNot(contains(RouteNames.clientBookings)));

        router.pop();
        await tester.pumpAndSettle();
        expect(find.byKey(_bookingsMarker), findsNothing);
        expect(find.byKey(_profileMarker), findsOneWidget);
      },
    );

    testWidgets(
      'tapping Календар (master-nav-tile-2) pushes /schedule and leaves the '
      'origin poppable (canPop true)',
      (tester) async {
        final router = _buildRouter(activeIndex: 3); // Профіль active
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        // Precondition: origin mounted, nothing to pop yet.
        expect(
          find.byKey(_profileMarker),
          findsOneWidget,
          reason: 'precondition: bar hosted on the profile route',
        );
        expect(
          router.canPop(),
          isFalse,
          reason: 'precondition: nothing pushed yet → back stack is empty',
        );

        await tester.tap(find.byKey(const Key('master-nav-tile-2')));
        await tester.pumpAndSettle();

        // (a) Destination mounted.
        expect(
          find.byKey(_scheduleMarker),
          findsOneWidget,
          reason: 'the schedule destination must mount after the tap',
        );
        // (b) canPop() proves push (not go) — the origin stayed on the stack so
        //     AppBar back button + left-edge swipe-back work. With go() the
        //     stack would be replaced and canPop() would be false.
        expect(
          router.canPop(),
          isTrue,
          reason:
              'tapping the Календар tile must context.push(masterSchedule) — '
              'the origin must remain on the back stack so swipe-back works. '
              'If this fails, the call reverted to context.go() which replaces '
              'the stack and strands the user on the destination.',
        );
      },
    );

    testWidgets(
      'tapping Послуги (master-nav-tile-0) pushes /services, back affordance '
      'exists, and pop returns to origin (Step 2.7 Rule 3 regression guard)',
      (tester) async {
        final router = _buildRouter(activeIndex: 3); // Профіль active
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('master-nav-tile-0')));
        await tester.pumpAndSettle();

        // (a) ServicesListScreen destination mounted.
        expect(
          find.byKey(_servicesMarker),
          findsOneWidget,
          reason: 'the services destination must mount after the tap',
        );
        // (b) Back affordance: a poppable stack is exactly what powers the
        //     AppBar BackButton and the left-edge swipe-back gesture.
        expect(
          router.canPop(),
          isTrue,
          reason:
              'tapping the Послуги tile must context.push(services) — the '
              'origin must stay on the back stack (canPop true) so the user is '
              'not stranded on "Мої послуги" (the bug Step 2.7 Rule 3 fixes).',
        );

        // (c) Pop returns to the originating profile screen.
        router.pop();
        await tester.pumpAndSettle();
        expect(
          find.byKey(_servicesMarker),
          findsNothing,
          reason: 'services destination must be gone after pop',
        );
        expect(
          find.byKey(_profileMarker),
          findsOneWidget,
          reason:
              'popping must return to the master profile origin — confirms a '
              'true back stack existed after the push',
        );
      },
    );

    testWidgets(
      'tapping the active tile (master-nav-tile-3, activeIndex 3) is a no-op — '
      'no push, stack unchanged',
      (tester) async {
        final router = _buildRouter(activeIndex: 3); // Профіль active
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('master-nav-tile-3')));
        await tester.pumpAndSettle();

        // The already-active tile resolves to a null route (onTap == null), so
        // nothing is pushed: still on the origin, nothing to pop, location
        // unchanged. Locks the null-for-active contract in _routeFor.
        expect(
          find.byKey(_profileMarker),
          findsOneWidget,
          reason: 'the active tile must not navigate away from the origin',
        );
        expect(
          router.canPop(),
          isFalse,
          reason:
              'the already-active tile resolves to a null route — onTap is '
              'null, so nothing is pushed and the back stack stays empty',
        );
        expect(
          _location(router),
          RouteNames.masterProfile,
          reason: 'location must remain on the profile route after a no-op tap',
        );
      },
    );
  });
}
