// Edge swipe-back → Home wiring in the CLIENT shell (client_shell.dart).
//
// THE FEATURE UNDER TEST
// ----------------------
// The shell body is wrapped in an [EdgeSwipeBack] whose `enabled` is `!onHome`
// and whose `onSwipeBack` fires the SAME primitive the bottom-nav tap and the
// PopScope system-back use:
//     navigationShell.goBranch(kClientHomeBranch, initialLocation: false)
// so a committed left-edge rightward swipe on any NON-Home tab hops back to the
// Home branch; on the Home branch the detector is not mounted (enabled:false),
// so a swipe there is inert.
//
// This is the gesture twin of the PopScope guard proven in
// client_shell_back_to_home_test.dart (R1) — it reuses that file's REAL-shell
// harness (the same five branches as app_router.dart, placeholder bodies, no
// provider/network deps) and drives the actual pointer gesture instead of the
// platform back button. The pure EdgeSwipeBack mechanics (strip confinement,
// rightward-only, thresholds) are pinned in
// test/shared/widgets/edge_swipe_back_test.dart; THIS file pins only that the
// shell wires the gesture to a goBranch(0) hop and gates it off Home.

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

/// Performs a committed left-edge rightward swipe starting inside the shell's
/// [EdgeSwipeBack] strip. The strip lives below the top bar (inside an
/// Expanded), so we read its real rect rather than guessing a y offset.
Future<void> _edgeSwipeBack(WidgetTester tester) async {
  final Rect strip = tester.getRect(find.byKey(const Key('edge-swipe-back')));
  // Start 5px in from the true left edge (inside the 20px strip), drag 220px
  // rightward — past the 48px distance threshold.
  await tester.dragFrom(
    strip.centerLeft + const Offset(5, 0),
    const Offset(220, 0),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CLIENT shell edge swipe-back → Home', () {
    testWidgets(
      'a left-edge rightward swipe on a non-Home tab hops back to the Home '
      'branch (goBranch 0)',
      (tester) async {
        final GoRouter router = _buildClientShellRouter();
        addTearDown(router.dispose);
        await _pumpShell(tester, router);

        // Hop to the Bookings tab (branch 3) via the bottom nav.
        await tester.tap(find.byKey(const Key('client-nav-tile-3')));
        await tester.pumpAndSettle();
        expect(_activeIndex(tester), kClientBookingsBranch);
        // On a non-Home tab the edge detector IS mounted.
        expect(
          find.byKey(const Key('edge-swipe-back')),
          findsOneWidget,
          reason: 'the edge strip must be enabled on a non-Home tab',
        );

        // Commit the edge swipe — the shell must hop to the Home branch.
        await _edgeSwipeBack(tester);

        expect(
          _activeIndex(tester),
          kClientHomeBranch,
          reason:
              'a committed edge swipe-back on a non-Home tab must switch the '
              'shell to the Home branch (goBranch(kClientHomeBranch))',
        );
        expect(
          find.byType(ClientShell),
          findsOneWidget,
          reason:
              'the shell must remain mounted — the swipe hops a branch, '
              'it does not push/pop a route',
        );
      },
    );

    testWidgets(
      'on the Home tab the edge detector is NOT mounted, so a swipe is inert',
      (tester) async {
        final GoRouter router = _buildClientShellRouter();
        addTearDown(router.dispose);
        await _pumpShell(tester, router);

        // Start on Home (initial branch).
        expect(_activeIndex(tester), kClientHomeBranch);
        // enabled:false on Home ⇒ the detector is absent.
        expect(
          find.byKey(const Key('edge-swipe-back')),
          findsNothing,
          reason: 'the edge strip must be disabled (unmounted) on the Home tab',
        );

        // A left-edge rightward drag on Home hits only the Home body — no hop.
        await tester.dragFrom(const Offset(5, 400), const Offset(220, 0));
        await tester.pumpAndSettle();

        expect(
          _activeIndex(tester),
          kClientHomeBranch,
          reason: 'a swipe on the Home tab must leave the shell on Home',
        );
      },
    );
  });
}
