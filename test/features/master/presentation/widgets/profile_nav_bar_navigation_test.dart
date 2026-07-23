// VelvetBottomNavBar tap-to-navigate contract (Phase 6.x — nav bar wired to
// go_router). The bar is self-contained: it takes only `activeIndex` and calls
// `context.go(...)` internally via `_VelvetNavTile._routeFor(index)`.
//
// ## History — DRILL-IN FIX (Step 2.7 Rule 3), now REVERSED
//
// The nav tile onTap started as `context.go(route)`, and that broke: it
// "replaced the navigator stack → no AppBar back button, dead left-edge
// swipe-back — the user was stranded on 'Мої послуги'" (this file's own
// prior header, quoted verbatim). The fix at the time was `context.push
// (route)` (the destination is pushed ON TOP of the origin, so the back
// button and edge-swipe-back both work; `pop()` returns to the origin).
//
// `push` was correct as far as it went, but it has its own cost: every tab
// tap stacks a NEW route on top of the previous one, so hopping
// Профіль → Послуги → Мої записи → Графік pushes 4 deep, and the depth grows
// without bound the longer the master bounces between tabs. mobile-debugger
// traced this back to its root cause: `push` was never really "the fix" for
// stranding — it was a workaround for a DIFFERENT bug (two of the four tab
// screens, Послуги and Графік, rendered no `VelvetBottomNavBar` of their own
// at the time, so `go`-ing to either was a genuine dead end with no way back
// AND no way sideways). That structural bug is fixed now — all four master
// tab screens render this exact bar (`ServicesListScreen`,
// `MasterBookingsScreen`, `MasterScheduleScreen`, `MasterProfileScreen` via
// `ProfileScaffold`), mounted via the identical `Scaffold.bottomNavigationBar`
// convention (see `velvet_bottom_nav_bar_mount_parity_test.dart`). With the
// bar universally present, `go` no longer strands anyone: whichever tab it
// lands on, the SAME bar is right there to leave it again — no back button
// required. So the tile's `onTap` is `context.go(route)` again, this time
// for the stack-growth fix, without reintroducing the original failure. Full
// reasoning lives on the `onTap` call site in `velvet_bottom_nav_bar.dart`.
//
// CONTRACT under go:
//   - Tapping a non-active tile REPLACES the stack with the destination's
//     single route: the origin unmounts entirely (not just covered — gone),
//     and `router.canPop()` is `false` (a stack of depth 1 has nothing to
//     pop to).
//   - Tapping the already-active tile is still a no-op: `onTap` resolves to
//     `null` (the `active` guard in `_routeFor`), so nothing is pushed OR
//     gone-to — the stack is byte-for-byte unchanged.
//   - Repeated tab taps never grow the stack — it stays at depth 1 no matter
//     how many tabs are visited in sequence.
//   - The master is never stranded: every destination the bar can reach
//     renders the SAME bar, so there is always a way out even with no back
//     button — this is the guarantee that replaces "the origin stays
//     poppable" now that `go` no longer keeps the origin around at all.
//
// NOTE on go_router path inspection: after `context.go(...)`,
// `currentConfiguration.uri` DOES update (unlike the old `push` regime, where
// an `ImperativeRouteMatch` was invisible to `.fullPath`/`.uri` — see
// `project_gorouter_imperative_match_fullpath` in the project memory). `go`
// replaces `currentConfiguration` outright, so `_location(router)` is a valid
// ground truth here; the destination marker widget is still asserted
// alongside it as an independent, render-level check.
//
// Keys under test (defined in profile_avatar.dart):
//   master-nav-tile-0 → Послуги    → context.go('/services')
//   master-nav-tile-1 → Мої записи → context.go('/master/bookings')  [7.6]
//   master-nav-tile-2 → Графік     → context.go('/schedule')
//   master-nav-tile-3 → Профіль    → current shell; active tile is always a no-op
//
// pumpAndSettle IS used: the only animation is the 200 ms camel-pill
// AnimatedContainer, which is finite and drains cleanly.

import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Router builder — hosts ALL FOUR master tab destinations, each rendering its
// own correctly-indexed [VelvetBottomNavBar], mirroring the real app now that
// every tab screen carries the bar (Part 1 of the same fix). This lets the
// stack-growth and no-stranding tests chain taps ACROSS destinations, not just
// observe a single hop away from one fixed origin.
// ---------------------------------------------------------------------------

const Key _profileMarker = Key('stub-profile-screen');
const Key _servicesMarker = Key('stub-services-screen');
const Key _scheduleMarker = Key('stub-schedule-screen');
const Key _bookingsMarker = Key('stub-master-bookings-screen');

GoRouter _buildRouter() => GoRouter(
  initialLocation: RouteNames.masterProfile,
  redirect: (context, state) => null,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterProfile,
      builder: (context, _) => const Scaffold(
        body: SizedBox.shrink(key: _profileMarker),
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
      path: RouteNames.masterSchedule,
      builder: (context, _) => const Scaffold(
        body: SizedBox.shrink(key: _scheduleMarker),
        bottomNavigationBar: VelvetBottomNavBar(activeIndex: 2),
      ),
    ),
    // Phase 7.6 — the «Мої записи» destination that tile 1 had no route to
    // until this phase.
    GoRoute(
      path: RouteNames.masterBookings,
      builder: (context, _) => const Scaffold(
        body: SizedBox.shrink(key: _bookingsMarker),
        bottomNavigationBar: VelvetBottomNavBar(activeIndex: 1),
      ),
    ),
  ],
);

MaterialApp _app(GoRouter router) => MaterialApp.router(routerConfig: router);

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

/// Number of matches in the CURRENT route stack — `1` whenever `go` has fully
/// replaced the configuration (the state every tab tap must leave the router
/// in), growing only if something pushed on top instead.
int _stackDepth(GoRouter router) =>
    router.routerDelegate.currentConfiguration.matches.length;

void main() {
  group('VelvetBottomNavBar tap-to-navigate (go, stack-replacing)', () {
    testWidgets(
      'tapping Мої записи (master-nav-tile-1) REPLACES the stack with '
      '/master/bookings — the origin unmounts, canPop is false',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        expect(find.byKey(_profileMarker), findsOneWidget);
        expect(router.canPop(), isFalse);
        expect(_stackDepth(router), 1);

        await tester.tap(find.byKey(const Key('master-nav-tile-1')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(_bookingsMarker),
          findsOneWidget,
          reason:
              'tile 1 must resolve to RouteNames.masterBookings — it was a '
              'documented no-op ("no route yet") before Phase 7.6.',
        );
        expect(
          find.byKey(_profileMarker),
          findsNothing,
          reason:
              'go replaces the stack — the profile origin must be gone, not '
              'merely covered.',
        );
        expect(
          router.canPop(),
          isFalse,
          reason:
              'go (not push) — the stack was replaced wholesale, so there is '
              'nothing left to pop.',
        );
        expect(
          _stackDepth(router),
          1,
          reason: 'a single tab tap must leave the stack at depth 1.',
        );
        // Deliberately NOT the client «Мої записи»: `/bookings` lives under
        // the client shell branch and its CLIENT-only guard. Exact equality
        // (not `contains`) — `masterBookings` (`/master/bookings`) contains
        // `clientBookings` (`/bookings`) as a trailing substring, so a
        // `contains` check would pass for either route.
        expect(_location(router), isNot(RouteNames.clientBookings));
        expect(_location(router), RouteNames.masterBookings);
      },
    );

    testWidgets(
      'tapping Графік (master-nav-tile-2) REPLACES the stack with /schedule',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        expect(
          find.byKey(_profileMarker),
          findsOneWidget,
          reason: 'precondition: bar hosted on the profile route',
        );
        expect(
          router.canPop(),
          isFalse,
          reason: 'precondition: single-route stack from initialLocation',
        );

        await tester.tap(find.byKey(const Key('master-nav-tile-2')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(_scheduleMarker),
          findsOneWidget,
          reason: 'the schedule destination must mount after the tap',
        );
        expect(
          find.byKey(_profileMarker),
          findsNothing,
          reason: 'go replaces the stack — the origin must be gone',
        );
        expect(
          router.canPop(),
          isFalse,
          reason:
              'tapping the Графік tile must context.go(masterSchedule) — a '
              'true `push` would leave canPop() true. If this fails, the call '
              'reverted to context.push(), reintroducing the stack-growth bug '
              'this change fixes.',
        );
      },
    );

    testWidgets(
      'tapping Послуги (master-nav-tile-0) REPLACES the stack with /services '
      '(Step 2.7 Rule 3 regression guard, now under go semantics)',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('master-nav-tile-0')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(_servicesMarker),
          findsOneWidget,
          reason: 'the services destination must mount after the tap',
        );
        expect(router.canPop(), isFalse);

        // The no-stranding guarantee: even with no back button, the bar
        // itself is the escape hatch. This is what makes `go` safe where it
        // used to strand the user (see the file header) — Послуги is
        // specifically the screen named in that original incident.
        expect(
          find.byType(VelvetBottomNavBar),
          findsOneWidget,
          reason:
              'the master must never land on Послуги with no way out — the '
              'exact failure mode `go` caused before every tab screen '
              'rendered this bar.',
        );
      },
    );

    testWidgets(
      'tapping the active tile (master-nav-tile-3, activeIndex 3) is a no-op — '
      'no go, no push, stack byte-for-byte unchanged',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        final int depthBefore = _stackDepth(router);

        await tester.tap(find.byKey(const Key('master-nav-tile-3')));
        await tester.pumpAndSettle();

        // The already-active tile resolves to a null route (onTap == null),
        // so nothing navigates: still on the origin, nothing to pop, location
        // unchanged. Locks the null-for-active contract in _routeFor.
        expect(
          find.byKey(_profileMarker),
          findsOneWidget,
          reason: 'the active tile must not navigate away from the origin',
        );
        expect(router.canPop(), isFalse);
        expect(
          _stackDepth(router),
          depthBefore,
          reason: 'a no-op tap must not touch the stack at all',
        );
        expect(
          _location(router),
          RouteNames.masterProfile,
          reason: 'location must remain on the profile route after a no-op tap',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Back-stack growth — the whole point of the go() switch.
  // ---------------------------------------------------------------------------

  group('back-stack growth', () {
    testWidgets(
      'hopping through all four tabs in sequence never grows the stack past '
      'depth 1 — the bug `push` shipped with (4 tabs visited → 4 deep)',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        // Профіль(3, active) → Мої записи(1) → Графік(2) → Послуги(0) →
        // Профіль(3) — every tile visited at least once, plus a return trip.
        const List<(String tileKey, Key marker)> hops = <(String, Key)>[
          ('master-nav-tile-1', _bookingsMarker),
          ('master-nav-tile-2', _scheduleMarker),
          ('master-nav-tile-0', _servicesMarker),
          ('master-nav-tile-3', _profileMarker),
        ];

        for (final (String tileKey, Key marker) in hops) {
          await tester.tap(find.byKey(Key(tileKey)));
          await tester.pumpAndSettle();

          expect(
            find.byKey(marker),
            findsOneWidget,
            reason: 'tapping $tileKey must land on its destination',
          );
          expect(
            _stackDepth(router),
            1,
            reason:
                'after tapping $tileKey the stack must still be depth 1 — a '
                'growing depth here is exactly the `push` regression this '
                'test guards against.',
          );
          expect(router.canPop(), isFalse);
        }
      },
    );

    testWidgets(
      'the flow the original push decision protected still works: the '
      'master reaches Послуги from Профіль and can leave it again — no '
      'stranding, even though go leaves no back button',
      (tester) async {
        final router = _buildRouter();
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        // Reproduce the exact incident the file header quotes: navigate to
        // Послуги (Мої послуги) from Профіль.
        await tester.tap(find.byKey(const Key('master-nav-tile-0')));
        await tester.pumpAndSettle();
        expect(find.byKey(_servicesMarker), findsOneWidget);
        expect(
          router.canPop(),
          isFalse,
          reason:
              'go leaves no back button — this is the condition that '
              'used to strand the user',
        );

        // The master is NOT stuck: tapping any other tile from here still
        // navigates, because the bar (not a back button) is the escape hatch.
        await tester.tap(find.byKey(const Key('master-nav-tile-3')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(_profileMarker),
          findsOneWidget,
          reason:
              'from Послуги, tapping Профіль must land back there — proving '
              'the master was never actually stranded on Послуги.',
        );
        expect(find.byKey(_servicesMarker), findsNothing);
      },
    );
  });
}
