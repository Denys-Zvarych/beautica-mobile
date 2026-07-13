// Regression: CLIENT shell edge-swipe / system-back must POP a pushed detail
// page off the ACTIVE branch (→ PREVIOUS page) BEFORE it ever falls back to the
// Home tab — and only hop to Home from a bare tab ROOT.
//
// THE BUG THIS PINS
// -----------------
// The edge swipe-back USED to fire `goBranch(kClientHomeBranch)` UNCONDITIONALLY.
// On a PUSHED DETAIL page (e.g. `/search/results` pushed onto the search branch)
// a swipe therefore JUMPED to Home instead of popping back to the previous page.
// Reported verbatim: "swiping back automatically navigates to home — totally
// wrong; on non-tab-root pages it should go to the PREVIOUS page; only from a
// bottom-nav tab ROOT should it go home."
//
// The fix routes BOTH the edge swipe and the shell PopScope through the shared
// [ShellBackDispatcher.handleBack]:
//   1. active branch canPop → pop it (PREVIOUS page), branch unchanged;
//   2. else non-Home tab root → goBranch(Home);
//   3. else (Home root) → no-op.
//
// WHY THIS ROUTER ATTACHES THE BRANCH NAVIGATOR KEYS (critical harness note)
// -------------------------------------------------------------------------
// [ClientShell] does NOT take the branch keys as a parameter — it reads the
// GLOBAL `clientBranchNavigatorKeys` directly. The dispatcher's `canPop` check
// resolves `clientBranchNavigatorKeys[currentIndex].currentState`. The other
// standalone shell test routers (client_shell_edge_swipe_test.dart,
// client_shell_back_to_home_test.dart) do NOT attach those keys, so
// `.currentState` is null there and `canPop` is INERTLY FALSE — they can never
// exercise (or regress-guard) the detail-pop path. This router attaches the SAME
// global keys app_router.dart wires, so `canPop` is REAL and step 1 is actually
// tested. Every test below both PUSHES a real detail route onto a branch and
// asserts the branch/tab identity, so it fails against the old
// unconditional-`goBranch(Home)` behaviour and passes now.

import 'package:beautica_mobile/features/shell/presentation/branch_placeholders.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A minimal pushed detail page carrying a stable [Key] so its presence/absence
/// on the branch stack is a clean assertion target.
class _DetailPage extends StatelessWidget {
  const _DetailPage({required this.pageKey});

  final Key pageKey;

  @override
  Widget build(BuildContext context) =>
      Scaffold(key: pageKey, body: const SizedBox.shrink());
}

/// Builds the CLIENT shell over the SAME five branches as app_router.dart AND —
/// unlike the other standalone shell routers — attaches the global
/// `clientBranchNavigatorKeys` to each branch, so [ShellBackDispatcher]'s
/// `canPop` resolves a live [NavigatorState]. A pushable `detail` sub-route sits
/// under BOTH the Home (index 0) and Search (index 2) branch roots so the
/// detail-pop path can be exercised on a Home AND a non-Home branch.
GoRouter _buildKeyedClientShellRouter() => GoRouter(
  initialLocation: RouteNames.clientHome,
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          ClientShell(navigationShell: navigationShell),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          navigatorKey: clientBranchNavigatorKeys[kClientHomeBranch],
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.clientHome,
              builder: (context, state) => const ClientHomePlaceholderScreen(),
              routes: <RouteBase>[
                GoRoute(
                  path: 'detail',
                  builder: (context, state) =>
                      const _DetailPage(pageKey: Key('home-detail-page')),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: clientBranchNavigatorKeys[kClientFavoritesBranch],
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.clientFavorites,
              builder: (context, state) =>
                  const ClientFavoritesPlaceholderScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: clientBranchNavigatorKeys[kClientSearchBranch],
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.clientSearch,
              builder: (context, state) =>
                  const ClientSearchPlaceholderScreen(),
              routes: <RouteBase>[
                GoRoute(
                  path: 'detail',
                  builder: (context, state) =>
                      const _DetailPage(pageKey: Key('search-detail-page')),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: clientBranchNavigatorKeys[kClientBookingsBranch],
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.clientBookings,
              builder: (context, state) =>
                  const ClientBookingsPlaceholderScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: clientBranchNavigatorKeys[kClientPassportBranch],
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.clientPassport,
              builder: (context, state) =>
                  const ClientPassportPlaceholderScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

Future<void> _pumpShell(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
  await tester.pump();
  // Run out the one-shot staggered-reveal CurvedAnimation on the visible
  // branch. It is finite (a single `controller.forward()`, never `.repeat()`),
  // so pumpAndSettle terminates the instant the reveal completes — waiting
  // exactly as long as the animation takes rather than a hard-coded guess.
  await tester.pumpAndSettle();
}

int _activeIndex(WidgetTester tester) =>
    tester.widget<ClientBottomNav>(find.byType(ClientBottomNav)).activeIndex;

/// Commits a left-edge rightward swipe inside the shell's real [EdgeSwipeBack]
/// strip (its rect is read live — the strip sits below the top bar inside an
/// Expanded, so a guessed y offset would be brittle).
Future<void> _edgeSwipeBack(WidgetTester tester) async {
  final Rect strip = tester.getRect(find.byKey(const Key('edge-swipe-back')));
  await tester.dragFrom(
    strip.centerLeft + const Offset(5, 0),
    const Offset(220, 0),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CLIENT shell detail-pop back policy (edge swipe)', () {
    testWidgets(
      'REGRESSION: on a non-Home branch with a detail page pushed, an edge '
      'swipe POPS the detail (→ previous page) and does NOT change the tab',
      (tester) async {
        final GoRouter router = _buildKeyedClientShellRouter();
        addTearDown(router.dispose);
        await _pumpShell(tester, router);

        // Push a detail page onto the SEARCH branch (index 2, non-Home). Going
        // to the nested location selects branch 2 and builds its stack as
        // [search root, detail] — canPop is now true on that branch.
        router.go('${RouteNames.clientSearch}/detail');
        await tester.pumpAndSettle();

        expect(_activeIndex(tester), kClientSearchBranch);
        expect(
          find.byKey(const Key('search-detail-page')),
          findsOneWidget,
          reason: 'the detail page must be on top of the search branch',
        );

        // Commit the edge swipe — it must POP the detail, NOT jump to Home.
        await _edgeSwipeBack(tester);

        // 1) The detail page is gone (popped & disposed) — the PREVIOUS page
        //    (the search root) is shown again.
        expect(
          find.byKey(const Key('search-detail-page')),
          findsNothing,
          reason:
              'the swipe must POP the detail page (return to the previous '
              'page), not jump to Home — the exact regression',
        );
        expect(
          find.byKey(const Key('client-branch-search')),
          findsOneWidget,
          reason: 'the search branch root (the previous page) is shown again',
        );
        // 2) The active tab is UNCHANGED — still Search. Under the OLD
        //    unconditional goBranch(Home) this would flip to 0 (and the detail
        //    would survive offstage on the search branch) — both assertions
        //    fail on the buggy code and pass now.
        expect(
          _activeIndex(tester),
          kClientSearchBranch,
          reason:
              'popping a detail must NOT change the active branch/tab (stays '
              'on Search)',
        );
      },
    );

    testWidgets(
      'on a non-Home tab ROOT (nothing pushed) an edge swipe hops to the Home '
      'branch',
      (tester) async {
        final GoRouter router = _buildKeyedClientShellRouter();
        addTearDown(router.dispose);
        await _pumpShell(tester, router);

        // Bookings tab root — nothing pushed, so the branch cannot pop.
        await tester.tap(find.byKey(const Key('client-nav-tile-3')));
        await tester.pumpAndSettle();
        expect(_activeIndex(tester), kClientBookingsBranch);

        await _edgeSwipeBack(tester);

        expect(
          _activeIndex(tester),
          kClientHomeBranch,
          reason:
              'a swipe on a non-Home tab ROOT must fall back to the Home '
              'branch (goBranch(Home))',
        );
      },
    );

    testWidgets(
      'on the Home tab ROOT an edge swipe is a no-op (stays Home, no crash)',
      (tester) async {
        final GoRouter router = _buildKeyedClientShellRouter();
        addTearDown(router.dispose);
        await _pumpShell(tester, router);

        expect(_activeIndex(tester), kClientHomeBranch);

        await _edgeSwipeBack(tester);

        expect(
          _activeIndex(tester),
          kClientHomeBranch,
          reason: 'a swipe on the Home tab root leaves the shell on Home',
        );
        expect(
          find.byType(ClientShell),
          findsOneWidget,
          reason: 'the no-op swipe must not tear down the shell',
        );
      },
    );

    testWidgets('a detail page pushed onto the HOME branch is swipe-poppable '
        '(guards the old !onHomeBranch enabled-gate regression)', (
      tester,
    ) async {
      final GoRouter router = _buildKeyedClientShellRouter();
      addTearDown(router.dispose);
      await _pumpShell(tester, router);

      // Push a detail page onto the HOME branch (index 0). Under the OLD
      // `enabled: !onHomeBranch` gate the swipe strip was omitted here, so the
      // detail was NOT swipe-poppable — this pins `enabled: true`.
      router.go('${RouteNames.clientHome}/detail');
      await tester.pumpAndSettle();

      expect(_activeIndex(tester), kClientHomeBranch);
      expect(
        find.byKey(const Key('home-detail-page')),
        findsOneWidget,
        reason: 'the detail page must be on top of the Home branch',
      );
      // The strip is mounted on the Home branch too (always enabled).
      expect(
        find.byKey(const Key('edge-swipe-back')),
        findsOneWidget,
        reason: 'the edge strip stays mounted on the Home branch',
      );

      await _edgeSwipeBack(tester);

      expect(
        find.byKey(const Key('home-detail-page')),
        findsNothing,
        reason:
            'a detail on the Home branch MUST be swipe-poppable — the old '
            '!onHomeBranch gate wrongly disarmed the swipe here',
      );
      expect(_activeIndex(tester), kClientHomeBranch);
    });
  });

  group('CLIENT shell detail-pop back policy (system-back parity)', () {
    // The shell PopScope (system back) and the edge swipe both route through the
    // SAME [ShellBackDispatcher], so the two can never drift. These pin the
    // system-back OUTCOMES for cases 1-3 as identical to the swipe outcomes
    // above (pop detail; else Home; else exit).

    testWidgets(
      'system-back on a non-Home branch with a detail pushed POPS the detail '
      '(same outcome as the swipe) and keeps the tab',
      (tester) async {
        final GoRouter router = _buildKeyedClientShellRouter();
        addTearDown(router.dispose);
        await _pumpShell(tester, router);

        router.go('${RouteNames.clientSearch}/detail');
        await tester.pumpAndSettle();
        expect(_activeIndex(tester), kClientSearchBranch);
        expect(find.byKey(const Key('search-detail-page')), findsOneWidget);

        // Flutter dispatches the platform back to the innermost (active branch)
        // navigator first — popping the detail, exactly like the swipe.
        final bool handled = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(
          handled,
          isTrue,
          reason: 'system-back must be consumed by popping the detail page',
        );
        expect(
          find.byKey(const Key('search-detail-page')),
          findsNothing,
          reason: 'system-back pops the detail — same outcome as the swipe',
        );
        expect(
          _activeIndex(tester),
          kClientSearchBranch,
          reason: 'system-back popping a detail keeps the active tab',
        );
      },
    );

    testWidgets(
      'system-back on a non-Home tab ROOT hops to Home (same outcome as the '
      'swipe)',
      (tester) async {
        final GoRouter router = _buildKeyedClientShellRouter();
        addTearDown(router.dispose);
        await _pumpShell(tester, router);

        await tester.tap(find.byKey(const Key('client-nav-tile-3')));
        await tester.pumpAndSettle();
        expect(_activeIndex(tester), kClientBookingsBranch);

        final bool handled = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(
          handled,
          isTrue,
          reason: 'a non-Home tab-root back is handled by the shell PopScope',
        );
        expect(
          _activeIndex(tester),
          kClientHomeBranch,
          reason: 'system-back on a non-Home tab root hops to Home',
        );
      },
    );

    testWidgets(
      'system-back on the Home tab ROOT is NOT intercepted (app exits) — same '
      'no-op outcome as the swipe',
      (tester) async {
        final GoRouter router = _buildKeyedClientShellRouter();
        addTearDown(router.dispose);
        await _pumpShell(tester, router);

        expect(_activeIndex(tester), kClientHomeBranch);

        final bool handled = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(
          handled,
          isFalse,
          reason:
              'back on the Home root must NOT be intercepted — standard app '
              'exit, mirroring the swipe no-op',
        );
        expect(_activeIndex(tester), kClientHomeBranch);
      },
    );
  });
}
