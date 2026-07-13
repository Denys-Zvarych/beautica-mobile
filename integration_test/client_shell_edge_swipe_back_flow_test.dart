// E2E: CLIENT edge swipe-back → Home (Step 2.7 Rule 3b).
//
// WHY THIS FLOW EXISTS
// --------------------
// The widget tier proves the gesture in isolation:
//   • test/shared/widgets/edge_swipe_back_test.dart — the EdgeSwipeBack strip
//     mechanics (confinement, rightward-only, thresholds, enabled gating).
//   • test/features/shell/client_shell_edge_swipe_test.dart — the shell wires
//     the swipe to goBranch(kClientHomeBranch) and gates it off Home.
// Neither exercises the REAL journey: a CLIENT logging in through the real login
// form against the fake backend, landing on the real StatefulShellRoute,
// navigating to a non-Home tab, and performing the actual pointer swipe to
// return Home — end to end through the live router + shell + branches.
//
// This is the gesture counterpart of the R1 system-back E2E already in
// client_shell_flow_test.dart (Test 7). It boots the REAL app via AppHarness
// (FakeBackend socket, FakeSecureStorage, fixed clock, overflow guard) and:
//   1. CLIENT login → lands on /home (branch 0).
//   2. Tap the Bookings tab (branch 3) → the non-Home branch body mounts.
//   3. Commit a left-edge rightward swipe → the router returns to /home and the
//      Home branch body is the active IndexedStack child.
//
// KEY POLICY: all taps/finders are key-based (client-nav-tile-N,
// edge-swipe-back, client-branch-*). See support/app_harness.dart.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
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

  void expectLocation(GoRouter router, String expected) {
    final String current = router.routerDelegate.currentConfiguration.uri
        .toString();
    expect(
      current,
      startsWith(expected),
      reason: 'Expected router location to start with $expected, got $current',
    );
  }

  // Commit a left-edge rightward swipe starting inside the shell's real
  // EdgeSwipeBack strip (its rect is read live — the strip sits below the top
  // bar inside an Expanded, so a guessed y offset would be brittle).
  Future<void> edgeSwipeBack(WidgetTester tester) async {
    final Rect strip = tester.getRect(find.byKey(const Key('edge-swipe-back')));
    await tester.dragFrom(
      strip.centerLeft + const Offset(5, 0),
      const Offset(220, 0),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  int activeIndex(WidgetTester tester) =>
      tester.widget<ClientBottomNav>(find.byType(ClientBottomNav)).activeIndex;

  testWidgets(
    'CLIENT on a non-Home tab swipes back from the left edge and returns to '
    '/home',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientHome);

      // Hop to the Bookings tab (branch 3) via the bottom nav.
      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientBookings);
      expect(
        find.byKey(const Key('client-branch-bookings')),
        findsOneWidget,
        reason: 'branch 3 (Записи) must be the active body before the swipe',
      );
      // The edge strip is mounted on a non-Home tab.
      expect(
        find.byKey(const Key('edge-swipe-back')),
        findsOneWidget,
        reason: 'the edge swipe-back strip must be enabled on a non-Home tab',
      );

      // Commit the left-edge rightward swipe — must return to Home.
      await edgeSwipeBack(tester);

      expectLocation(router, RouteNames.clientHome);
      expect(
        find.byKey(const Key('client-branch-home')),
        findsOneWidget,
        reason:
            'the edge swipe-back must hop the shell to the Home branch (branch '
            '0, Головна)',
      );
      expect(
        find.byType(ClientShell),
        findsOneWidget,
        reason:
            'the shell must remain mounted — the swipe hops a branch, it does '
            'not push/pop a route',
      );
      expect(
        find.byType(ClientBottomNav),
        findsOneWidget,
        reason: 'the 5-tab bar must persist across the back-to-Home hop',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  // E2E REGRESSION (the reported bug): on a PUSHED DETAIL page a swipe must POP
  // to the PREVIOUS page, NOT jump to Home. Only from a bare tab ROOT does the
  // swipe fall back to Home.
  //
  // Journey: CLIENT login → Пошук tab → push the REAL /search/results detail
  // onto the search branch → edge swipe returns to the PREVIOUS page (the search
  // root), STILL on the Пошук tab (NOT Home) → a second swipe from the tab root
  // then hops to Home. Pushing the detail via `router.go` exercises the real
  // results screen on the real branch navigator; the SWIPE (the thing under
  // test) is the genuine pointer gesture.
  testWidgets(
    'CLIENT swipe on a pushed detail page returns to the PREVIOUS page (not '
    'Home); a second swipe from the tab root then goes Home',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientHome);

      // Land on the Пошук (Search) tab root via the elevated center disc.
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientSearch);
      expect(activeIndex(tester), kClientSearchBranch);

      // Push the REAL results detail onto the SEARCH branch navigator — the
      // stack becomes [search root, results], so the branch canPop.
      router.go(RouteNames.clientSearchResults);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientSearchResults);
      expect(
        find.byKey(const Key('client-search-results')),
        findsOneWidget,
        reason: 'the results detail must be on top of the search branch',
      );
      expect(activeIndex(tester), kClientSearchBranch);

      // ── FIRST swipe — must POP the detail (→ PREVIOUS page), NOT jump Home ──
      await edgeSwipeBack(tester);

      expectLocation(router, RouteNames.clientSearch);
      expect(
        find.byKey(const Key('client-search-results')),
        findsNothing,
        reason:
            'the swipe must POP the results detail and return to the search '
            'root (the PREVIOUS page) — the exact reported regression',
      );
      expect(
        find.byKey(const Key('client-branch-search')),
        findsOneWidget,
        reason: 'the search root (previous page) is shown again',
      );
      expect(
        activeIndex(tester),
        kClientSearchBranch,
        reason: 'popping a detail must NOT change the active tab (stays Пошук)',
      );

      // ── SECOND swipe — now on the Пошук tab ROOT → falls back to Home ──────
      await edgeSwipeBack(tester);

      expectLocation(router, RouteNames.clientHome);
      expect(
        activeIndex(tester),
        kClientHomeBranch,
        reason: 'a swipe from a non-Home tab ROOT falls back to the Home tab',
      );
      expect(
        find.byKey(const Key('client-branch-home')),
        findsOneWidget,
        reason: 'the Home branch body is the active IndexedStack child',
      );
      expect(
        find.byType(ClientShell),
        findsOneWidget,
        reason: 'the shell stays mounted across both swipes',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
