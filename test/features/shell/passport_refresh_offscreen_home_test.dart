// Phase 349 audit (mobile-perf, cycle 1) — MEDIUM finding.
//
// `passport_screen.dart`'s pull-to-refresh handler invalidates
// `clientProfileProvider`, which is ALSO watched by Home's `_ProfileSection`
// (`home_hub_screen.dart`). Home stays mounted OFFSTAGE while the client shell
// sits on the Passport branch — `StatefulNavigationShell` uses an
// `IndexedStack`, and go_router mutes `TickerMode` on the covered branch. Per
// `project_riverpod_offstage_pause_invalidate`, a covered branch's Riverpod
// `Consumer` PAUSES its subscription (via `TickerMode.of`), so it does not
// rebuild while paused; it resumes and reconciles against the current
// provider state when the branch becomes active again. The finding asked
// whether that resume shows Home the REFRESHED data with no stale/error
// flash, and how many `/users/me`-equivalent fetches happen in total.
//
// THIS FILE PROVES THE ACTUAL BEHAVIOUR ON THE REAL SHELL
// ---------------------------------------------------------------------------
// `passport_screen_test.dart`'s own pull-to-refresh group cannot answer this:
// its header (§7) says outright that `tester.pumpApp` mounts `PassportScreen`
// directly with no `StatefulShellBranch` ancestor, so its one listener is
// never offstage/paused. This file instead mounts the REAL
// `StatefulShellRoute.indexedStack` + `ClientShell`, exactly as
// `home_inpage_branch_hop_test.dart` does, so BOTH `HomeHubScreen` (branch 0)
// and `PassportScreen` (branch 4) are live consumers of the SAME
// `clientProfileProvider` element in the SAME `ProviderContainer`.
//
// SEQUENCE
// --------
//   1. Shell opens on Home (branch 0)   → clientProfileProvider fetch #1.
//   2. Hop to Passport (branch 4)       → Home is now covered/paused; no
//                                          second fetch (same cached value).
//   3. Pull-to-refresh on Passport      → invalidate + await .future; Passport
//                                          is the ACTIVE listener, so this is
//                                          a genuine fetch #2, observed via
//                                          Passport's own profile card.
//   4. Hop back to Home (branch 0)      → Home's paused Consumer resumes.
//
// RESULT ASSERTED: Home's profile card shows the POST-refresh name on the
// very next settle, no skeleton/error flash, and the fetch counter is STILL
// 2 — proving the resume reconciles against the already-fresh cached value
// rather than either (a) showing stale data or (b) firing a second refetch.
// This is the CORRECT, load-bearing behaviour of the invalidate/pause
// mechanism; nothing in `passport_screen.dart` needs to change for it.

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/favorites/presentation/favorites_screen.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
import 'package:beautica_mobile/features/passport/application/passport_notifier.dart';
import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/shell/presentation/branch_placeholders.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fakes/fake_favorite_repository.dart';
import '../../helpers/fakes/fake_wishlist_repository.dart';

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

const ClientProfileSummary _preRefreshProfile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Допрофілю',
  city: 'Київ',
  phone: '+380 67 000 00 00',
  clientRating: null,
  memberSinceYear: 2024,
);

const ClientProfileSummary _postRefreshProfile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Післярефрешу',
  city: 'Львів',
  phone: '+380 67 111 11 11',
  clientRating: null,
  memberSinceYear: 2024,
);

const String _preRefreshName = 'Олена Допрофілю';
const String _postRefreshName = 'Олена Післярефрешу';

/// Builds the REAL CLIENT `StatefulShellRoute` (same branch order as
/// `app_router.dart`) wrapped in the REAL `ClientShell`, mirroring
/// `home_inpage_branch_hop_test.dart`'s harness — no shared helper exists yet
/// for this shape (three files already duplicate it independently); adding a
/// fourth by the same local convention keeps this fix minimally scoped rather
/// than refactoring unrelated shell test files.
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
                builder: (context, state) => const FavoritesScreen(),
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

Future<void> _pumpShell(
  WidgetTester tester,
  GoRouter router,
  List<Object> overrides,
) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: overrides.cast(),
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
  await tester.pump();
  // fixed-wait-ok: drains the StaggeredReveal entrance animation (a fixed-
  // duration AnimationController, not a condition to pump-until) on both
  // Home and Passport so in-page content is laid out and hit-testable.
  await tester.pump(const Duration(milliseconds: 1200));
}

void main() {
  testWidgets(
    'REGRESSION: Passport pull-to-refresh leaves the offstage Home profile '
    'card correctly refreshed on resume, with no stale/error flash and no '
    'extra fetch',
    (tester) async {
      int profileCalls = 0;
      final FakeWishlistRepository fakeWishlist = FakeWishlistRepository();

      final GoRouter router = _buildClientShellRouter();
      addTearDown(router.dispose);

      await _pumpShell(tester, router, <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        clientProfileProvider.overrideWith((ref) async {
          profileCalls++;
          return profileCalls == 1 ? _preRefreshProfile : _postRefreshProfile;
        }),
        // Home-only providers.
        nextAppointmentProvider.overrideWith((ref) async => null),
        favoriteMastersProvider.overrideWith(
          (ref) async => const <FavoriteMasterItem>[],
        ),
        beautyTimelineProvider.overrideWith(
          (ref) async => const <TimelineEntry>[],
        ),
        unlikeFavoriteMasterProvider.overrideWith(() => UnlikeFavoriteMaster()),
        favoriteRepositoryProvider.overrideWithValue(FakeFavoriteRepository()),
        // Passport-only providers.
        passportProvider.overrideWith(
          (ref) async => Passport.empty(memberSinceYear: 2024),
        ),
        wishlistRepositoryProvider.overrideWithValue(fakeWishlist),
      ]);

      // 1. Home is the starting branch — the first (and, until the pull,
      //    only) fetch, showing the PRE-refresh name.
      expect(find.byType(HomeHubScreen), findsOneWidget);
      expect(profileCalls, 1, reason: 'exactly one fetch on cold start');
      expect(find.text(_preRefreshName), findsOneWidget);

      // 2. Hop to Passport (branch 4). Home is now covered/paused; Passport
      //    mounts its OWN `_ProfileSection` consumer of the same provider.
      await tester.tap(find.byKey(const Key('client-nav-tile-4')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('client-branch-passport')), findsOneWidget);
      expect(find.byType(HomeHubScreen), findsNothing);
      expect(
        profileCalls,
        1,
        reason:
            'a NEW listener on an already-resolved provider must not '
            'trigger a second fetch',
      );
      expect(
        find.text(_preRefreshName),
        findsOneWidget,
        reason: "Passport's own profile block renders the same cached value",
      );

      // 3. Pull-to-refresh on Passport. Recipe matches
      //    `passport_screen_test.dart`'s own M6 drag sequence: the 200ms
      //    drag-reveal pump is what actually invokes `onRefresh`.
      final Finder scrollableFinder = find
          .descendant(
            of: find.byType(PassportScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      final ScrollableState scrollableState = tester.state<ScrollableState>(
        scrollableFinder,
      );
      scrollableState.position.jumpTo(0);
      await tester.pump();

      await tester.fling(scrollableFinder, const Offset(0, 400), 800);
      // Pump 1: RefreshIndicator intercepts the gesture, starts the pull
      // animation.
      await tester.pump();
      // Pump 2: past the indicator's 200ms drag-reveal animation — this is
      // the pump that actually invokes `onRefresh`.
      // fixed-wait-ok: Material's RefreshIndicator drag-reveal is a fixed
      // 200ms animation length (M6 exception), not a condition to pump-until.
      await tester.pump(const Duration(milliseconds: 200));
      // Pump 3: onRefresh runs (invalidate + await the three provider
      // futures).
      await tester.pump();
      // Pump 4: Riverpod notifier state transitions settle.
      // fixed-wait-ok: draining the notifier state-transition queue after
      // invalidate; nothing to pump-until against directly.
      await tester.pump(const Duration(milliseconds: 50));
      // Pump 5: Material RefreshIndicator's built-in 250ms dismiss animation.
      // fixed-wait-ok: fixed Material dismiss-animation duration (M6
      // exception), not application state to pump-until.
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        profileCalls,
        2,
        reason:
            'the pull, issued while Passport is the ACTIVE listener, must '
            're-fetch clientProfileProvider exactly once',
      );
      expect(
        find.text(_postRefreshName),
        findsOneWidget,
        reason:
            "Passport's own profile block must show the POST-refresh name "
            'immediately — proves the refetch actually landed, not just '
            'that the counter incremented',
      );

      // 4. Hop back to Home. Its paused Consumer resumes and must reconcile
      //    against the ALREADY-fresh cached value on the very next settle —
      //    no stale name, no skeleton, no error card, and NO third fetch.
      await tester.tap(find.byKey(const Key('client-nav-tile-0')));
      await tester.pumpAndSettle();

      expect(find.byType(HomeHubScreen), findsOneWidget);
      expect(find.byKey(const Key('client-branch-passport')), findsNothing);
      expect(
        find.text(_postRefreshName),
        findsOneWidget,
        reason:
            'resuming Home after the Passport-driven refresh must show the '
            'REFRESHED profile — a paused-then-resumed consumer reconciling '
            'against a stale cached AsyncValue is exactly the defect this '
            'test exists to catch',
      );
      expect(
        find.text(_preRefreshName),
        findsNothing,
        reason: 'Home must not flash or retain the pre-refresh name',
      );
      expect(find.byKey(const Key('home_profile_name')), findsOneWidget);
      expect(
        profileCalls,
        2,
        reason:
            'resuming a paused consumer must NOT trigger a redundant third '
            'fetch — it reconciles against the value Passport already '
            'refetched while active',
      );
    },
  );
}
