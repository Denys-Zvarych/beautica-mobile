// CLIENT branch → root-screen → persistent-chrome registry (shared source of
// truth for the cross-branch chrome-stability net).
//
// THE BUG CLASS THIS GUARDS — the "wordmark-jump" family
// ------------------------------------------------------
// The CLIENT shell is a [StatefulShellRoute.indexedStack] of five branches.
// The persistent chrome the user reads as "fixed" while hopping tabs is TWO
// things:
//   • the `beautica` wordmark inside [ClientTopBar] (its global `dy`), and
//   • the [ClientBottomNav] top edge (its global Y).
// Neither bar is hosted by the shell uniformly: the bottom nav IS shell-hosted
// (good), but [ClientTopBar] is mounted PER SCREEN — each branch root builds its
// OWN `SafeArea(bottom:false)` + a `Padding`/`ListView` whose top inset is a
// hand-copied `VelvetSpacing.sm`. That means a single screen re-adding an AppBar,
// nudging its top padding (`sm` → `lg`), or double-wrapping a SafeArea silently
// shifts the wordmark on THAT branch only — and the user sees the wordmark JUMP
// when they switch to it. The old chrome tests pinned only two SYNTHETIC
// [ClientTopBar] configs in isolation (burger vs no-burger); nothing pumped the
// REAL branch screens through the REAL router, so a per-screen wrapper drift was
// invisible.
//
// This registry is the durable generalisation: it lists every real CLIENT branch
// root so the router-driven net (`client_branch_chrome_test.dart`) can boot the
// production [appRouter], hop each branch, and assert the wordmark `dy` + bottom
// nav top-Y are BYTE-IDENTICAL across all branches that carry the chrome.
//
// HOW TO ADD A ROW (do this whenever a new CLIENT branch root ships)
// ------------------------------------------------------------------
// 1. Add one [ClientBranchChrome] to [clientBranchChromeMatrix] below.
// 2. Set [branchIndex] to the StatefulShellBranch index (the kClient*Branch
//    constant from app_router.dart) and [expectedRoute] to its root path.
// 3. Set [expectedRootType] to the branch root's widget Type.
// 4. Set [hasTopBar] = true if the root mounts a [ClientTopBar] (so the
//    cross-branch wordmark `dy` assertion includes it); false otherwise (the
//    placeholder branches render a different "Beautica" appTitle wordmark, NOT
//    the shared [ClientTopBar] — they are excluded from the dy invariant but
//    STILL pinned for route + bottom-nav-Y).
// 5. That single row is consumed by the router-tier net automatically — no
//    per-branch copy-paste.
//
// DEFERRED ROWS (pending, by dependency)
// --------------------------------------
// Rows whose target screen has not shipped yet are added with [pending] = true
// and a [deferredReason], NOT silently omitted. The net SKIP-marks them (visible
// in the run output) so the future work auto-joins the invariant and the gap can
// never be forgotten. Flip [pending] → false + fill the real expectations when
// the screen ships.
//
// Note: `test/` is excluded from the `no_raw_ui_strings` lint. Every assertion
// keys off route constants + widget TYPES / Keys — never raw Ukrainian text — so
// an l10n key move cannot mask a regression (mobile-qa M2).

import 'package:beautica_mobile/features/discovery/presentation/search_filters_screen.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/shell/presentation/branch_placeholders.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';

/// One row of the CLIENT branch → root → persistent-chrome contract.
class ClientBranchChrome {
  const ClientBranchChrome({
    required this.branchIndex,
    required this.branchName,
    required this.expectedRoute,
    required this.expectedRootType,
    required this.hasTopBar,
    this.pending = false,
    this.deferredReason,
  }) : assert(
         !pending || deferredReason != null,
         'a pending (deferred) row must document its deferredReason',
       );

  /// The [StatefulShellBranch] index (kClient*Branch in app_router.dart).
  final int branchIndex;

  /// Human-readable branch name, used in test descriptions + failure messages.
  final String branchName;

  /// The root path the branch resolves to (its [GoRoute] path).
  final String expectedRoute;

  /// The branch-root widget Type the router must build at [expectedRoute].
  final Type expectedRootType;

  /// Whether this branch root mounts a [ClientTopBar] (and therefore the
  /// `beautica` wordmark). When `true`, the cross-branch wordmark-`dy` invariant
  /// includes this branch. When `false`, the branch is still pinned for route +
  /// root-type + bottom-nav-Y, but excluded from the wordmark invariant because
  /// it renders a DIFFERENT wordmark (the placeholder's "Beautica" appTitle).
  final bool hasTopBar;

  /// True if the branch's target screen has not shipped yet, or the chrome it
  /// renders depends on a not-yet-available backend/fixture. The net SKIP-marks
  /// it (visible-but-deferred). Flip to `false` when the dependency lands.
  final bool pending;

  /// Why this row is deferred. Non-null iff [pending] is true.
  final String? deferredReason;
}

/// THE matrix — single source of truth for the CLIENT shell's five branches.
/// Verified against app_router.dart (`StatefulShellRoute.indexedStack` branch
/// order) and each branch root's `build()`:
///
/// ┌───┬──────────────┬───────────┬────────────────────────────────┬─────────┐
/// │ # │ Branch       │ Route     │ Root widget                    │ TopBar? │
/// ├───┼──────────────┼───────────┼────────────────────────────────┼─────────┤
/// │ 0 │ Головна      │ /home     │ HomeHubScreen                  │  YES    │
/// │ 1 │ Улюблені     │ /favorites│ ClientFavoritesPlaceholder…    │  no*    │
/// │ 2 │ Пошук        │ /search   │ ClientSearchScreen             │  YES    │
/// │ 3 │ Записи       │ /bookings │ ClientBookingsPlaceholder…     │  no*    │
/// │ 4 │ BEAUTY PASS… │ /passport │ PassportScreen                 │  YES    │
/// └───┴──────────────┴───────────┴────────────────────────────────┴─────────┘
/// * Favorites + Bookings are still placeholder screens (Phase 13.11 / 14.3).
///   They render the `appTitle` ("Beautica") wordmark via
///   [ClientBranchPlaceholder], NOT the shared [ClientTopBar]. They are pinned
///   for route/root/bottom-nav-Y but excluded from the [ClientTopBar] wordmark
///   `dy` invariant until their real screens ship and adopt the shared bar.
final List<ClientBranchChrome> clientBranchChromeMatrix = <ClientBranchChrome>[
  const ClientBranchChrome(
    branchIndex: kClientHomeBranch, // 0
    branchName: 'Головна (home)',
    expectedRoute: RouteNames.clientHome, // '/home'
    expectedRootType: HomeHubScreen,
    hasTopBar: true,
  ),
  const ClientBranchChrome(
    branchIndex: kClientFavoritesBranch, // 1
    branchName: 'Улюблені (favorites)',
    expectedRoute: RouteNames.clientFavorites, // '/favorites'
    expectedRootType: ClientFavoritesPlaceholderScreen,
    // Placeholder renders appTitle wordmark, not ClientTopBar (see note).
    hasTopBar: false,
  ),
  const ClientBranchChrome(
    branchIndex: kClientSearchBranch, // 2
    branchName: 'Пошук (search)',
    expectedRoute: RouteNames.clientSearch, // '/search'
    expectedRootType: ClientSearchScreen,
    hasTopBar: true,
  ),
  const ClientBranchChrome(
    branchIndex: kClientBookingsBranch, // 3
    branchName: 'Записи (bookings)',
    expectedRoute: RouteNames.clientBookings, // '/bookings'
    expectedRootType: ClientBookingsPlaceholderScreen,
    // Placeholder renders appTitle wordmark, not ClientTopBar (see note).
    hasTopBar: false,
  ),
  const ClientBranchChrome(
    branchIndex: kClientPassportBranch, // 4
    branchName: 'BEAUTY PASSPORT (passport)',
    expectedRoute: RouteNames.clientPassport, // '/passport'
    expectedRootType: PassportScreen,
    hasTopBar: true,
  ),

  // ── Deferred-by-dependency rows (pending, visible-but-skipped) ────────────
  // These pin the SCOPE of the future net so the chrome invariant auto-extends
  // when the screen / fixtures land. The net SKIP-marks each (so it shows in the
  // run output) — they are NOT silently omitted. Flip `pending` → false and fill
  // real expectations when the dependency ships.
  const ClientBranchChrome(
    branchIndex: -1, // not a shell branch — a pushed detail route
    branchName: 'public master profile (/masters/{id})',
    expectedRoute: '/masters/{id}',
    expectedRootType: Object, // unknown until the screen ships
    hasTopBar: false,
    pending: true,
    deferredReason:
        'Public master profile screen ships in Phase 13.5 (route '
        'RouteNames.masterPublicProfile). Once it lands, pin its top-chrome '
        'offset against the branch roots so a back-nav from a detail page does '
        'not re-introduce a wordmark/header jump.',
  ),
  const ClientBranchChrome(
    branchIndex: -1, // not a shell branch — a pushed detail route
    branchName: 'public salon profile (/salons/{id})',
    expectedRoute: '/salons/{id}',
    expectedRootType: Object, // unknown until the screen ships
    hasTopBar: false,
    pending: true,
    deferredReason:
        'Public salon profile screen ships in Phase 13.6 (route '
        'RouteNames.salonPublicProfile). Pin its top-chrome offset alongside '
        'the master profile once it lands.',
  ),
  const ClientBranchChrome(
    branchIndex: kClientPassportBranch, // 4 (populated variant)
    branchName: 'passport/favorites/bookings POPULATED render',
    expectedRoute: RouteNames.clientPassport,
    expectedRootType: PassportScreen,
    hasTopBar: true,
    pending: true,
    deferredReason:
        'The chrome is asserted today against the EMPTY/AsyncError data state '
        '(the no-network test harness). Pinning chrome stability for the '
        'POPULATED render (real passport timeline, favorites grid, bookings '
        'list) needs backend 19.x fakes (passport aggregations + favorites + '
        'bookings). Add a settled-fakes variant of the cross-branch dy test '
        'when those fakes exist, so a data-driven layout that pushes the top '
        'bar down on one branch is also caught.',
  ),
];

/// The subset of [clientBranchChromeMatrix] that is live (not deferred). The
/// router-driven net iterates these for the byte-identical chrome assertions.
List<ClientBranchChrome> get liveClientBranches =>
    clientBranchChromeMatrix.where((b) => !b.pending).toList();

/// The live branches whose root mounts a [ClientTopBar] — the set over which the
/// wordmark-`dy` invariant must hold byte-identical.
List<ClientBranchChrome> get topBarBranches =>
    liveClientBranches.where((b) => b.hasTopBar).toList();

/// Sanity check consumed by the net: the live matrix must cover EVERY CLIENT
/// shell branch index (0..4) exactly once. If a new branch is added to the
/// shell, this fails until a row is added — the matrix can never silently miss a
/// branch.
void assertMatrixCoversAllClientBranches() {
  const expected = <int>{
    kClientHomeBranch,
    kClientFavoritesBranch,
    kClientSearchBranch,
    kClientBookingsBranch,
    kClientPassportBranch,
  };
  final liveIndices = liveClientBranches
      .where((b) => b.branchIndex >= 0)
      .map((b) => b.branchIndex)
      .toList();
  final covered = liveIndices.toSet();
  if (covered.length != liveIndices.length) {
    throw StateError(
      'clientBranchChromeMatrix has a duplicate live branch index. Each of '
      'the five CLIENT shell branches must appear exactly once.',
    );
  }
  final bool sameContent =
      covered.length == expected.length && covered.containsAll(expected);
  if (!sameContent) {
    throw StateError(
      'clientBranchChromeMatrix must have exactly one live row per CLIENT '
      'shell branch (0..4). Missing: ${expected.difference(covered)}; '
      'unexpected: ${covered.difference(expected)}. Add/fix a row in '
      'test/routing/client_branch_chrome_matrix.dart (see "HOW TO ADD A ROW").',
    );
  }
}
