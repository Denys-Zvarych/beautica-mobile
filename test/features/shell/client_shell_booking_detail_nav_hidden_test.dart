// Feature B — the CLIENT bottom nav ([ClientBottomNav]) is SUPPRESSED on the
// booking-DETAIL route (`/bookings/:bookingId`) so the detail reads as a
// focused, full-height surface; it stays PRESENT on the `/bookings` list root
// and on every other tab. The [ClientTopBar] is intentionally KEPT on the
// detail page (only the bottom bar hides).
//
// WHY A DEDICATED ROUTER (harness note)
// -------------------------------------
// [ClientShell] detects the detail page by exact-matching the deepest active
// ROUTE PATTERN against `'${RouteNames.clientBookings}/:bookingId'`. So the test
// router must define a real `:bookingId` child under the Записи branch root —
// the standalone shell routers in the sibling shell tests do NOT, so they can
// never exercise this suppression. This router mirrors app_router.dart's five
// branches and attaches the SAME global `clientBranchNavigatorKeys`, so a pushed
// detail page is a live poppable route on the Записи branch and the
// pop-restores-the-bar mechanism is genuinely driven (not inertly false).
//
// WHY WE `context.push` (NOT `router.go`) INTO THE DETAIL — the ab34c0a guard
// --------------------------------------------------------------------------
// The real app reaches the detail via `context.push(RouteNames.bookingDetail…)`
// (my_bookings_screen.dart — a `BookingCard` tap). go_router wraps a PUSHED leaf
// in an `ImperativeRouteMatch`, which it EXCLUDES from
// `currentConfiguration.fullPath` (and the root keeps its base `/bookings` uri) —
// so a naive `fullPath == '/bookings/:bookingId'` check collapses to `/bookings`
// on device and the bar never hides. The ORIGINAL version of this test drove the
// detail with `router.go`, which produces a plain (non-imperative) match whose
// fullPath IS the pattern — it passed while the device was broken (a
// mock-green/real-breakage). These tests therefore navigate into the detail with
// a real `context.push` from the Записи list context, exactly as the app does, so
// they FAIL against the old predicate and only pass with the imperative-aware fix.
//
// KEY-FIRST: taps + presence are asserted by widget TYPE / Key, never by
// localised strings.

import 'dart:async';

import 'package:beautica_mobile/features/shell/presentation/branch_placeholders.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_top_bar.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

/// A minimal pushed booking-detail page carrying a stable [Key] so its
/// presence/absence on the Записи branch stack is a clean assertion target.
class _BookingDetailPage extends StatelessWidget {
  const _BookingDetailPage();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(key: Key('booking-detail-page'), body: SizedBox.shrink());
}

/// Builds the CLIENT shell over the SAME five branches as app_router.dart, with
/// a real `:bookingId` child under the Записи (index 3) branch root — the exact
/// `/bookings/:bookingId` pattern [ClientShell] suppresses the bottom nav on.
/// Attaches the global `clientBranchNavigatorKeys` so the pushed detail is a
/// live poppable route.
GoRouter _buildRouter() => GoRouter(
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
              routes: <RouteBase>[
                // The booking-DETAIL child — matched pattern is
                // `/bookings/:bookingId`, the exact one the shell hides the bar on.
                GoRoute(
                  path: ':bookingId',
                  builder: (context, state) => const _BookingDetailPage(),
                ),
              ],
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
      retry: beauticaProviderRetry,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

/// Navigates INTO the booking-detail page exactly as the app does — a real
/// `context.push` from the Записи list root (NOT `router.go`). Lands on the
/// `/bookings` list first (where a `BookingCard` tap starts), then pushes
/// `/bookings/<id>` onto that branch's own navigator, producing the
/// `ImperativeRouteMatch` that the runtime detector must see through.
Future<void> _pushDetail(
  WidgetTester tester,
  GoRouter router,
  String id,
) async {
  router.go(RouteNames.clientBookings);
  await tester.pumpAndSettle();
  unawaited(
    tester
        .element(find.byType(ClientBookingsPlaceholderScreen))
        .push(RouteNames.bookingDetail(id)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CLIENT shell — bottom nav hidden on booking detail', () {
    testWidgets(
      'FEATURE B (1): on a booking-DETAIL location (/bookings/<id>) the bottom '
      'nav is ABSENT while the top bar is KEPT',
      (tester) async {
        final GoRouter router = _buildRouter();
        addTearDown(router.dispose);
        await _pumpShell(tester, router);

        // PUSH into the detail route on the Записи branch, exactly as a
        // `BookingCard` tap does (an imperative push, NOT a `go`).
        await _pushDetail(tester, router, 'booking-1');

        // The detail page is on top of the Записи branch stack …
        expect(
          find.byKey(const Key('booking-detail-page')),
          findsOneWidget,
          reason: 'the booking-detail page must be the deepest active match',
        );
        // … the bottom nav is removed entirely (null slot, not a shrunk one) …
        expect(
          find.byType(ClientBottomNav),
          findsNothing,
          reason:
              'the bottom nav must be suppressed on the /bookings/:bookingId '
              'detail route so it reads as a focused, full-height surface',
        );
        // … but the persistent top bar stays (only the bottom bar hides).
        expect(
          find.byType(ClientTopBar),
          findsOneWidget,
          reason:
              'the top bar is intentionally KEPT on the booking-detail page — '
              'only the bottom nav is hidden',
        );
      },
    );

    testWidgets(
      'FEATURE B (2): on the /bookings LIST root the bottom nav IS present — '
      'the hide is detail-only, not the whole Записи branch',
      (tester) async {
        final GoRouter router = _buildRouter();
        addTearDown(router.dispose);
        await _pumpShell(tester, router);

        router.go(RouteNames.clientBookings);
        await tester.pumpAndSettle();

        expect(
          find.byType(ClientBookingsPlaceholderScreen),
          findsOneWidget,
          reason: 'the Записи list root is shown',
        );
        expect(
          find.byType(ClientBottomNav),
          findsOneWidget,
          reason:
              'the bottom nav must remain on the /bookings LIST root — only '
              'the nested detail hides it',
        );
        expect(
          tester
              .widget<ClientBottomNav>(find.byType(ClientBottomNav))
              .activeIndex,
          kClientBookingsBranch,
          reason: 'the Записи tab is the active one on its list root',
        );
      },
    );

    testWidgets(
      'FEATURE B (2b): on another tab (Пошук) the bottom nav is present too — '
      'suppression is scoped to the booking-detail route only',
      (tester) async {
        final GoRouter router = _buildRouter();
        addTearDown(router.dispose);
        await _pumpShell(tester, router);

        router.go(RouteNames.clientSearch);
        await tester.pumpAndSettle();

        expect(find.byType(ClientBottomNav), findsOneWidget);
        expect(
          tester
              .widget<ClientBottomNav>(find.byType(ClientBottomNav))
              .activeIndex,
          kClientSearchBranch,
        );
      },
    );

    testWidgets(
      'FEATURE B (3): navigating INTO the detail then BACK to the list toggles '
      'the bottom bar off → on (guards the same-branch-push rebuild via the '
      "shell's location listener)",
      (tester) async {
        final GoRouter router = _buildRouter();
        addTearDown(router.dispose);
        await _pumpShell(tester, router);

        // 1) Land on the Записи LIST root first — bar present, index 3. Now a
        //    subsequent hop to the detail keeps `currentIndex` at 3, so ONLY
        //    the shell's own routeInformationProvider listener can rebuild it.
        router.go(RouteNames.clientBookings);
        await tester.pumpAndSettle();
        expect(
          find.byType(ClientBottomNav),
          findsOneWidget,
          reason: 'baseline: the bar is present on the Записи list root',
        );

        // 2) Same-branch PUSH into the detail — currentIndex stays 3, so the
        //    StatefulShellRoute builder alone would NOT re-run this shell's
        //    build. The bar going away here proves the location listener fired
        //    AND that the imperative-aware detector sees the pushed pattern.
        unawaited(
          tester
              .element(find.byType(ClientBookingsPlaceholderScreen))
              .push(RouteNames.bookingDetail('booking-1')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('booking-detail-page')), findsOneWidget);
        expect(
          find.byType(ClientBottomNav),
          findsNothing,
          reason:
              'OFF: a same-branch push to the detail must hide the bar via the '
              'shell location listener (currentIndex is unchanged at 3)',
        );

        // 3) System back pops the detail off the Записи branch → location
        //    returns to /bookings → the listener flips the bar back ON.
        final bool handled = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          handled,
          isTrue,
          reason: 'system-back is consumed by popping the detail page',
        );
        expect(
          find.byKey(const Key('booking-detail-page')),
          findsNothing,
          reason: 'the detail page was popped off the Записи branch',
        );
        expect(
          find.byType(ClientBottomNav),
          findsOneWidget,
          reason:
              'ON: popping back to the /bookings list must restore the bottom '
              'nav — the off → on toggle is driven by the location listener',
        );
        expect(
          tester
              .widget<ClientBottomNav>(find.byType(ClientBottomNav))
              .activeIndex,
          kClientBookingsBranch,
          reason: 'still on the Записи tab after the detail popped',
        );
      },
    );

    testWidgets(
      'FEATURE B (4): back/branch semantics unchanged — popping the detail '
      'keeps the active Записи tab and leaves the shell mounted (top bar '
      'present throughout)',
      (tester) async {
        final GoRouter router = _buildRouter();
        addTearDown(router.dispose);
        await _pumpShell(tester, router);

        await _pushDetail(tester, router, 'booking-1');
        // Top bar stays even on the detail (bottom bar gone).
        expect(find.byType(ClientTopBar), findsOneWidget);
        expect(find.byType(ClientBottomNav), findsNothing);

        final bool handled = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(handled, isTrue);
        // Same ShellBackDispatcher semantics as the sibling detail-pop test:
        // popping a pushed detail keeps the active branch (stays on Записи) and
        // never tears down the shell.
        expect(find.byType(ClientShell), findsOneWidget);
        expect(find.byType(ClientTopBar), findsOneWidget);
        expect(find.byType(ClientBottomNav), findsOneWidget);
        expect(
          tester
              .widget<ClientBottomNav>(find.byType(ClientBottomNav))
              .activeIndex,
          kClientBookingsBranch,
        );
      },
    );
  });
}
