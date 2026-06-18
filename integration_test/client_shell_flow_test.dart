// Phase 13.1 — E2E: CLIENT 5-tab shell flow (StatefulShellRoute.indexedStack).
//
// WHY THIS FILE EXISTS
// --------------------
// The widget tier (test/features/shell/client_shell_test.dart) proves the
// ClientBottomNav surface in isolation, and the pure-fn tier
// (test/routing/auth_redirect_test.dart) proves the role-gate matrix. Neither
// exercises the REAL journey: a CLIENT logging in through the real login form
// against the fake backend, landing on the real StatefulShellRoute, hopping
// every branch via the real goBranch wiring, and being fenced off the MASTER
// shell (and vice-versa) by the live GoRouter redirect.
//
// This flow boots the REAL app via AppHarness (FakeBackend socket,
// FakeSecureStorage, fixed clock, overflow guard) and drives:
//
//   1. CLIENT login → lands on /home (Головна, branch index 0, the real
//      ClientHomePlaceholderScreen body).
//   2. Tapping each of the 5 tabs switches the active IndexedStack branch
//      WITHOUT growing the parent nav stack (goBranch, not push) — asserted by
//      reading the live router location AND confirming the shell + bottom-nav
//      survive every hop (a push would have stacked a new route over the shell).
//   3. Role gate (the live redirect, not the pure fn):
//        • a CLIENT cannot reach /master/profile → bounced to /home;
//        • an INDEPENDENT_MASTER cannot reach a client branch → bounced to
//          /master/profile;
//        • an unauthenticated cold start sits on /login.
//
// KEY POLICY: all taps are key-based (client-nav-tile-N / client-nav-search-
// center). Raw find.text(...) is used for content assertions only. See
// integration_test/support/app_harness.dart for the rationale.
//
// FAKE-BACKEND NOTE (backlog item): POST /auth/verify-email always returns
// INDEPENDENT_MASTER tokens, so a CLIENT session is established via the
// SUPPORTED path — AppHarness.loginAs(tester, fb, UserRole.client) drives the
// real /auth/login form, and FakeBackend.currentRole = client makes /auth/login
// + /users/me return the CLIENT persona. We never touch /auth/verify-email here.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
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

  // ── Helper: assert the router landed on [expected] ───────────────────────
  void expectLocation(GoRouter router, String expected) {
    final String current = router.routerDelegate.currentConfiguration.uri
        .toString();
    expect(
      current,
      startsWith(expected),
      reason: 'Expected router location to start with $expected, got $current',
    );
  }

  // The 5 branches keyed by their index → (route, branch-body key). Index 2 is
  // the elevated center «Пошук» disc (tapped via client-nav-search-center, not a
  // flanking tile). The branch bodies are the real placeholder screens.
  const branchRoute = <int, String>{
    0: RouteNames.clientHome,
    1: RouteNames.clientFavorites,
    2: RouteNames.clientSearch,
    3: RouteNames.clientBookings,
    4: RouteNames.clientPassport,
  };
  const branchBodyKey = <int, String>{
    0: 'client-branch-home',
    1: 'client-branch-favorites',
    2: 'client-branch-search',
    3: 'client-branch-bookings',
    4: 'client-branch-passport',
  };

  // Tap the affordance for branch [index]: flanking tile for 0/1/3/4, the
  // elevated center disc for 2. Key-based per policy.
  Future<void> tapBranch(WidgetTester tester, int index) async {
    final Finder target = index == 2
        ? find.byKey(const Key('client-nav-search-center'))
        : find.byKey(Key('client-nav-tile-$index'));
    await tester.tap(target);
    // Hop + drain the placeholder's 1s staggered reveal so the body settles.
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  // ── Test 1 — CLIENT login lands on the real /home shell ──────────────────

  testWidgets(
    'CLIENT login lands on /home — the client shell, branch index 0',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      // Cold start with no stored token → /login.
      expect(
        find.byKey(const ValueKey<String>('login_email')),
        findsOneWidget,
        reason: 'cold start (no token) must show /login',
      );

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Landed on the CLIENT shell at /home (branch 0).
      expectLocation(router, RouteNames.clientHome);
      expect(
        find.byType(ClientShell),
        findsOneWidget,
        reason: 'CLIENT must land inside the StatefulShellRoute shell',
      );
      expect(
        find.byType(ClientBottomNav),
        findsOneWidget,
        reason: 'the 5-tab bottom nav must be present on the client shell',
      );
      expect(
        find.byKey(const Key('client-branch-home')),
        findsOneWidget,
        reason: 'branch index 0 (Головна) must be the active body on landing',
      );
      expect(fb.loginCalls, equals(1));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── Test 2 — tapping each tab hops the branch (goBranch, not push) ───────

  testWidgets('tapping each of the 5 tabs switches the IndexedStack branch '
      'without growing the nav stack (goBranch)', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expectLocation(router, RouteNames.clientHome);

    // Visit every branch in a non-trivial order (incl. the center disc), then
    // back to home. After EACH hop:
    //   • the router location is the branch route (goBranch changed the active
    //     branch's location);
    //   • the active branch body is mounted;
    //   • the single ClientShell + ClientBottomNav are STILL present — a
    //     context.push would have stacked a new route OVER the shell, so the
    //     shell-still-present assertion is the stack-did-not-grow proof.
    for (final int index in <int>[1, 2, 3, 4, 0]) {
      await tapBranch(tester, index);

      expectLocation(router, branchRoute[index]!);
      expect(
        find.byType(ClientShell),
        findsOneWidget,
        reason:
            'exactly one ClientShell must remain after hopping to branch '
            '$index — a second one means a route was PUSHED over the shell '
            '(goBranch must not grow the parent stack)',
      );
      expect(
        find.byType(ClientBottomNav),
        findsOneWidget,
        reason: 'the bottom nav must persist across branch $index',
      );
      expect(
        find.byKey(Key(branchBodyKey[index]!)),
        findsOneWidget,
        reason: 'branch $index body must be the active IndexedStack child',
      );
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  // ── Test 3 — role gate: CLIENT cannot reach /master/* ────────────────────

  testWidgets('role gate: a CLIENT navigating to /master/profile is bounced '
      'to /home (the client shell)', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expectLocation(router, RouteNames.clientHome);

    // Attempt to deep-link into the MASTER shell. The live redirect must bounce
    // the CLIENT straight back to /home — they never see the master profile.
    router.go(RouteNames.masterProfile);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expectLocation(router, RouteNames.clientHome);
    expect(
      find.byType(ClientShell),
      findsOneWidget,
      reason: 'a CLIENT bounced off /master/* must be back on the client shell',
    );
    // The bottom bar is the visible proof of the fix: pre-fix the bounce
    // target was '/' (RouteNames.home — the no-bottom-bar "Скоро…"
    // placeholder), so ClientBottomNav was absent. Landing on /home
    // (RouteNames.clientHome) must mount the 5-tab bar.
    expect(
      find.byType(ClientBottomNav),
      findsOneWidget,
      reason:
          'a CLIENT bounced off /master/profile must land on /home WITH the '
          '5-tab bottom nav — the no-bar / placeholder was the routing bug',
    );
    expect(
      find.byKey(const Key('master-profile-name')),
      findsNothing,
      reason: 'the master profile must never render for a CLIENT',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ── Test 4 — role gate: INDEPENDENT_MASTER cannot reach a client branch ──

  testWidgets('role gate: an INDEPENDENT_MASTER navigating to a client branch '
      'is bounced to /master/profile', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.independentMaster;
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // The master lands on /master/profile after login.
    expectLocation(router, RouteNames.masterProfile);

    // Attempt to deep-link into each CLIENT branch — the inverse gate must
    // bounce the master back to its own profile every time, and the client
    // shell must never mount.
    for (final String clientRoute in <String>[
      RouteNames.clientHome,
      RouteNames.clientFavorites,
      RouteNames.clientSearch,
      RouteNames.clientBookings,
      RouteNames.clientPassport,
    ]) {
      router.go(clientRoute);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expectLocation(router, RouteNames.masterProfile);
      expect(
        find.byType(ClientShell),
        findsNothing,
        reason:
            'an INDEPENDENT_MASTER must never mount the client shell '
            '(attempted $clientRoute)',
      );
    }
  }, timeout: const Timeout(Duration(seconds: 45)));

  // ── Test 5 — unauthenticated cold start sits on /login ───────────────────

  testWidgets('unauthenticated cold start sits on /login — no client shell, '
      'no master profile', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    // No stored token → settled Unauthenticated → /login.
    expectLocation(router, RouteNames.login);
    expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
    expect(
      find.byType(ClientShell),
      findsNothing,
      reason: 'an unauthenticated user must never reach the client shell',
    );
    expect(fb.loginCalls, equals(0));
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ── Test 6 — the OTHER fixed dispatch site: done-screen → /home → bar ────
  //
  // f929caf fixed TWO dispatch sites that hardcoded RouteNames.home for a
  // CLIENT: the auth_redirect role-gate bounce (Test 3 above) AND the
  // registration DoneScreen's "to app" CTA (done_to_app → roleHomePath). Test 3
  // covers the bounce; this covers the done-screen CTA end-to-end through the
  // REAL DoneScreen + the real router redirect. A CLIENT tapping "to the app"
  // must land on /home (ClientShell) WITH the 5-tab bar — pre-fix it landed on
  // "/" (the no-bar "Скоро…" placeholder).
  //
  // /done is a post-register route the redirect deliberately does NOT bounce an
  // authenticated user off (auth_redirect excludes /verification + /done), so we
  // can drive an already-authenticated CLIENT session there via the real router
  // and tap the real CTA — the dispatch path under test is the screen's
  // onPressed (roleHomePath), exactly the f929caf fix.
  testWidgets('registration done-screen CTA sends a CLIENT to /home with the '
      'bottom bar (the second fixed dispatch site)', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expectLocation(router, RouteNames.clientHome);

    // Drive the real DoneScreen (the post-registration celebration surface).
    // The authenticated CLIENT is NOT bounced off /done.
    router.go(RouteNames.done);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expectLocation(router, RouteNames.done);

    // Tap the real "to the app" CTA — its onPressed resolves the destination
    // through roleHomePath(role), the single source of truth f929caf restored.
    await tester.tap(find.byKey(const ValueKey<String>('done_to_app')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Must land on /home (the client shell), NOT "/" (the no-bar placeholder).
    expectLocation(router, RouteNames.clientHome);
    expect(
      find.byType(ClientShell),
      findsOneWidget,
      reason: 'the done CTA must deliver a CLIENT to the client shell',
    );
    expect(
      find.byType(ClientBottomNav),
      findsOneWidget,
      reason:
          'a CLIENT finishing registration must land on /home WITH the 5-tab '
          'bar — the done-screen hardcoding RouteNames.home ("/", no bar) was '
          'the second half of the f929caf dispatch bug',
    );
  }, timeout: const Timeout(Duration(seconds: 45)));
}
