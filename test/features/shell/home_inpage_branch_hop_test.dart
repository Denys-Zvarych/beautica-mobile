// REGRESSION — in-page Home tiles must hop their shell BRANCH, keeping the
// bottom-nav selection in sync with the page (Rule 3 guard).
//
// THE BUG
// -------
// In-page Home tiles that target a bottom-nav shell branch (the BEAUTY PASSPORT
// preview tile, and the Search / Favorites / Bookings quick-links) used
// `context.push(<branch route>)`. A push stacks the destination ON TOP of the
// HOME branch's navigator — so the destination PAGE appeared, but the
// StatefulNavigationShell's `currentIndex` stayed 0 (Home). The bottom nav
// fills the tile whose `index == currentIndex`, so the Home tile stayed filled
// and the destination tile (e.g. Passport, index 4) never became active. Page
// and nav-bar were out of sync.
//
// The nav-bar TABS themselves were never broken (they call
// `navigationShell.goBranch(index)`); only the IN-PAGE tiles were.
//
// THE FIX UNDER TEST
// ------------------
//   • app_router.dart            — named branch-index constants
//                                  (kClientHomeBranch … kClientPassportBranch).
//   • home_hub_screen.dart       — the Passport stat-pill tile (onPassport) now
//                                  StatefulNavigationShell.of(context)
//                                    .goBranch(kClientPassportBranch).
//   • quick_links_card.dart      — Search/Favorites/Bookings quick-links now
//                                  goBranch(branchIndex) (push only when null).
//   • client_bottom_nav.dart     — tiles fill when index == currentIndex.
//
// WHY THIS PUMPS THE REAL SHELL
// -----------------------------
// `StatefulNavigationShell.of(context)` only resolves inside a live
// StatefulShellRoute. A bare HomeHubScreen would throw, so the prior home-hub
// widget tests could not exercise the page↔navbar sync at all. This file pumps
// a router that mounts the REAL ClientShell + the REAL StatefulShellRoute
// branches (branch 0 = HomeHubScreen, branch 4 = PassportScreen, plus the real
// placeholder branches), so `goBranch` runs through the production wiring and
// the ClientBottomNav reads the real `currentIndex`.
//
// RED-AGAINST-BUG
// ---------------
// With the OLD `context.push`, tapping the in-page Passport tile would push
// PassportScreen over the Home branch: the Passport page would render (so a
// page-only assertion would still pass — which is exactly why the bug shipped),
// but `navigationShell.currentIndex` would stay 0. So the assertions below that
// (a) tile-4 is selected and (b) tile-0 is NOT selected, and that
// ClientBottomNav.activeIndex == 4, would FAIL. This file therefore fails
// against the bug and passes against the fix.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/passport_preview_card.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/shell/presentation/branch_placeholders.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// No-op ScreenProtectionManager — both HomeHubScreen and PassportScreen
// acquire screen protection in initState; the native plugin must not be hit.
// ---------------------------------------------------------------------------
class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void reset() {}
}

const _sampleProfile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Шевченко',
  city: 'Київ',
  phone: '+380 67 000 00 00',
  clientRating: 4.8,
  memberSinceYear: 2026,
);

/// Overrides that keep every Home-Hub / Passport async card off the network and
/// in a deterministic data/empty state so the tree settles synchronously.
List<Object> _overrides() => <Object>[
  screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
  clientProfileProvider.overrideWith((ref) async => _sampleProfile),
  nextAppointmentProvider.overrideWith((ref) async => null),
  favoriteMastersProvider.overrideWith(
    (ref) async => const <FavoriteMasterItem>[],
  ),
  beautyTimelineProvider.overrideWith((ref) async => const <TimelineEntry>[]),
  unlikeFavoriteMasterProvider.overrideWith(() => UnlikeFavoriteMaster()),
];

/// Builds a GoRouter that mounts the REAL CLIENT StatefulShellRoute (the same
/// branch order as app_router.dart) wrapped in the REAL ClientShell, so
/// `StatefulNavigationShell.of(context).goBranch(...)` runs the production path.
/// No auth redirect / splash — the route table is exactly the 5 client branches
/// so the test is deterministic and isolated from the auth flow.
GoRouter _buildClientShellRouter() {
  return GoRouter(
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
                builder: (context, state) => const HomeHubScreen(),
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
                builder: (context, state) => const PassportScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Future<void> _pumpShell(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: _overrides().cast(),
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
  // Resolve the provider futures + play the staggered reveal so the in-page
  // tiles are laid out and hit-testable.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
}

/// Reads the live selected flag off a nav item via its merged Semantics node.
///
/// Index 2 is the elevated center search DISC (key `client-nav-search-center`),
/// not a flanking tile — the other four (0,1,3,4) are `client-nav-tile-$index`.
bool _navTileSelected(WidgetTester tester, int index) {
  final Key key = index == kClientSearchBranch
      ? const Key('client-nav-search-center')
      : Key('client-nav-tile-$index');
  final SemanticsData data = tester
      .getSemantics(find.byKey(key))
      .getSemanticsData();
  // `isSelected` is a tri-state flag; the tiles set it explicitly via
  // Semantics(selected: active), so it is never the unset null here.
  return data.flagsCollection.isSelected.toBoolOrNull() ?? false;
}

/// Reads the production-source-of-truth: ClientBottomNav.activeIndex, which the
/// shell feeds from `navigationShell.currentIndex`.
int _activeIndex(WidgetTester tester) =>
    tester.widget<ClientBottomNav>(find.byType(ClientBottomNav)).activeIndex;

void main() {
  group('In-page Home tile → shell branch hop keeps nav-bar in sync', () {
    testWidgets(
      'tapping the in-page BEAUTY PASSPORT tile shows the Passport page AND '
      'activates nav tile-4 (Home tile-0 deactivates)',
      (tester) async {
        final handle = tester.ensureSemantics();
        final GoRouter router = _buildClientShellRouter();
        addTearDown(router.dispose);

        await _pumpShell(tester, router);

        // Pre-condition: we start on Home (branch 0). The Home tile is selected;
        // the Passport tile is not.
        expect(
          find.byType(HomeHubScreen),
          findsOneWidget,
          reason: 'shell must start on the Home branch',
        );
        expect(_activeIndex(tester), 0, reason: 'starts on Home (index 0)');
        expect(
          _navTileSelected(tester, 0),
          isTrue,
          reason: 'Home tile (0) is selected on the Home branch',
        );
        expect(
          _navTileSelected(tester, 4),
          isFalse,
          reason: 'Passport tile (4) is NOT selected before the tap',
        );

        // The in-page Passport tile (the stat-pills PassportPreviewCard, wired
        // to onPassport). Found by widget type — it is unique in the tree and
        // carries no localised string, so this is a robust finder.
        final Finder passportTile = find.byType(PassportPreviewCard);
        expect(
          passportTile,
          findsOneWidget,
          reason: 'the in-page BEAUTY PASSPORT preview tile must render',
        );
        await tester.ensureVisible(passportTile);
        await tester.tap(passportTile);
        await tester.pumpAndSettle();

        // 1) The Passport PAGE is now shown.
        expect(
          find.byKey(const Key('client-branch-passport')),
          findsOneWidget,
          reason:
              'tapping the in-page Passport tile must show the Passport page '
              '(its branch body)',
        );
        expect(
          find.byType(HomeHubScreen),
          findsNothing,
          reason:
              'the Home branch body must no longer be the active IndexedStack '
              'child after hopping to the Passport branch',
        );

        // 2) The bottom-nav selection followed the page — the exact sync the
        //    bug broke. With the old context.push, currentIndex would stay 0,
        //    so tile-0 would stay selected and these assertions would FAIL.
        expect(
          _activeIndex(tester),
          4,
          reason:
              'ClientBottomNav.activeIndex must be 4 (Passport) — fed from '
              'navigationShell.currentIndex after goBranch. A context.push '
              'would leave it at 0.',
        );
        expect(
          _navTileSelected(tester, 4),
          isTrue,
          reason:
              'the Passport nav tile (4) must be the ACTIVE/selected tile after '
              'the in-page tap (page↔navbar sync)',
        );
        expect(
          _navTileSelected(tester, 0),
          isFalse,
          reason:
              'the Home nav tile (0) must NO LONGER be selected — the bug left '
              'it filled because currentIndex never changed',
        );

        // Exactly one ClientShell — goBranch must NOT have stacked a route over
        // the shell (a push would have grown the stack / duplicated the shell).
        expect(
          find.byType(ClientShell),
          findsOneWidget,
          reason:
              'goBranch must not grow the parent nav stack — exactly one '
              'ClientShell may remain (a push would duplicate it)',
        );
        handle.dispose();
      },
    );

    // ── Quick-links (Search / Favorites / Bookings) — same page↔navbar sync ──
    //
    // Parallel cases proving every in-page quick-link that targets a shell
    // branch activates the MATCHING nav tile (not just changes the page). Same
    // red-against-bug logic: a push would keep tile-0 selected.
    final quickLinks = <({String key, int branch, String bodyKey})>[
      (
        key: 'quick_link_search',
        branch: kClientSearchBranch,
        bodyKey: 'client-branch-search',
      ),
      (
        key: 'quick_link_favorites',
        branch: kClientFavoritesBranch,
        bodyKey: 'client-branch-favorites',
      ),
      (
        key: 'quick_link_bookings',
        branch: kClientBookingsBranch,
        bodyKey: 'client-branch-bookings',
      ),
    ];

    for (final link in quickLinks) {
      testWidgets(
        'tapping the "${link.key}" quick-link hops branch ${link.branch} and '
        'activates the matching nav tile (Home tile-0 deactivates)',
        (tester) async {
          final handle = tester.ensureSemantics();
          final GoRouter router = _buildClientShellRouter();
          addTearDown(router.dispose);

          await _pumpShell(tester, router);

          // Pre-condition: on Home.
          expect(_activeIndex(tester), 0);
          expect(_navTileSelected(tester, 0), isTrue);
          expect(_navTileSelected(tester, link.branch), isFalse);

          final Finder tile = find.byKey(Key(link.key));
          expect(
            tile,
            findsOneWidget,
            reason: '${link.key} quick-link must render on the Home hub',
          );
          await tester.ensureVisible(tile);
          await tester.tap(tile);
          await tester.pumpAndSettle();

          // The destination branch page is shown.
          expect(
            find.byKey(Key(link.bodyKey)),
            findsOneWidget,
            reason:
                'tapping ${link.key} must show branch ${link.branch} '
                '(${link.bodyKey})',
          );

          // The nav-bar selection followed the page.
          expect(
            _activeIndex(tester),
            link.branch,
            reason:
                'ClientBottomNav.activeIndex must be ${link.branch} after the '
                '${link.key} hop — a context.push would leave it at 0',
          );
          expect(
            _navTileSelected(tester, link.branch),
            isTrue,
            reason:
                'nav tile-${link.branch} must be selected after tapping '
                '${link.key}',
          );
          expect(
            _navTileSelected(tester, 0),
            isFalse,
            reason:
                'the Home nav tile (0) must deactivate after the ${link.key} '
                'branch hop',
          );
          handle.dispose();
        },
      );
    }
  });
}
