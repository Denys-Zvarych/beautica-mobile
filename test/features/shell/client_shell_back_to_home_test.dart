// R1 — system-back / predictive-back on a non-Home CLIENT tab must return to
// the Home tab, NOT exit the app.
//
// THE BUG
// -------
// The CLIENT StatefulShellRoute.indexedStack had no PopScope. The shell is the
// only route on the root navigator, so a system-back on a non-Home branch root
// had nothing to pop and EXITED the app from Search / Favorites / Bookings /
// Passport instead of returning to Home.
//
// THE FIX UNDER TEST (client_shell.dart)
// --------------------------------------
// The shell's Scaffold is wrapped in a PopScope:
//   • canPop:  true ONLY on the Home branch (back exits — standard home behaviour).
//   • onPopInvokedWithResult: on a blocked pop (any non-Home tab) hop back to the
//     Home branch via navigationShell.goBranch(kClientHomeBranch).
//
// WHY THIS PUMPS THE REAL SHELL
// -----------------------------
// PopScope + StatefulNavigationShell only behave correctly inside a live
// StatefulShellRoute, so the test mounts the REAL ClientShell over the same five
// branches as app_router.dart (placeholder bodies — no provider/network deps) and
// drives the platform back via tester.binding.handlePopRoute().

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

GoRouter _buildClientShellRouter() => GoRouter(
  initialLocation: RouteNames.clientHome,
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          ClientShell(navigationShell: navigationShell),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.clientHome,
              builder: (context, state) => const ClientHomePlaceholderScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.clientFavorites,
              builder: (context, state) =>
                  const ClientFavoritesPlaceholderScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.clientSearch,
              builder: (context, state) =>
                  const ClientSearchPlaceholderScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.clientBookings,
              builder: (context, state) =>
                  const ClientBookingsPlaceholderScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
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
  // fixed-wait-ok: running out a time-driven CurvedAnimation reveal — no condition to pump-until.
  await tester.pump(const Duration(milliseconds: 1200));
}

int _activeIndex(WidgetTester tester) =>
    tester.widget<ClientBottomNav>(find.byType(ClientBottomNav)).activeIndex;

void main() {
  group('CLIENT shell system-back → Home (R1)', () {
    testWidgets(
      'system-back on a non-Home tab returns to Home instead of exiting',
      (tester) async {
        final GoRouter router = _buildClientShellRouter();
        addTearDown(router.dispose);
        await _pumpShell(tester, router);

        // Hop to the Favorites tab (branch 1) via the bottom nav.
        await tester.tap(find.byKey(const Key('client-nav-tile-1')));
        await tester.pumpAndSettle();
        expect(_activeIndex(tester), kClientFavoritesBranch);

        // Dispatch the platform back button.
        final bool handled = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        // The back was HANDLED by the shell (not bubbled to the OS to exit) and
        // the shell hopped back to the Home branch.
        expect(
          handled,
          isTrue,
          reason: 'a non-Home back must be handled by the shell PopScope',
        );
        expect(
          _activeIndex(tester),
          kClientHomeBranch,
          reason: 'system-back on a non-Home tab must return to the Home tab',
        );
        expect(
          find.byType(ClientShell),
          findsOneWidget,
          reason: 'the shell must remain mounted — the app did not exit',
        );
      },
    );

    testWidgets('system-back on the Home tab is NOT intercepted (app exits)', (
      tester,
    ) async {
      final GoRouter router = _buildClientShellRouter();
      addTearDown(router.dispose);
      await _pumpShell(tester, router);

      // Start on Home (initial branch).
      expect(_activeIndex(tester), kClientHomeBranch);

      // On the Home branch canPop is true, so the root navigator has nothing to
      // pop → handlePopRoute returns false (the OS would exit the app). The
      // shell must NOT swallow the back here.
      final bool handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        handled,
        isFalse,
        reason:
            'back on Home must NOT be intercepted — standard exit behaviour',
      );
      expect(_activeIndex(tester), kClientHomeBranch);
    });
  });
}
