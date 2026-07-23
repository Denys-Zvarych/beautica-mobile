// Phase 13.1 — CLIENT 5-tab navigation scaffold.
//
// Wraps a [StatefulNavigationShell] (the body of the CLIENT
// StatefulShellRoute.indexedStack) and renders the active branch + the
// persistent chrome — the [ClientTopBar] (wordmark · bell · burger) AND the
// [ClientBottomNav] — BOTH mounted ONCE here. Tapping a tab hops the branch via
// `goBranch` — it does NOT grow the nav stack (the prior `context.push`-retains-
// shell note from profile_avatar.dart:555 is exactly what StatefulShellRoute
// fixes).
//
// WHY THE TOP BAR LIVES HERE (the wordmark-jump fix — 2026-06-24)
// --------------------------------------------------------------
// The [ClientTopBar] used to be mounted PER SCREEN inside each branch root
// (home / search / passport), each with its OWN `SafeArea(bottom:false)` +
// `VelvetSpacing.sm` top inset — and on home it lived INSIDE the scrolling
// ListView. The byte-identical wordmark `dy` across branches was therefore an
// EMERGENT ACCIDENT of three independently-maintained wrappers: a future
// per-screen Padding / AppBar / double-SafeArea drift would silently re-jump
// the wordmark on one branch. Hoisting the bar into the shell makes a single
// shell-owned bar the ONLY source of the top chrome — byte-identical across
// every branch BY CONSTRUCTION, not by coincidence. The bottom nav was already
// shell-owned; now the top bar matches.
//
// The per-branch differences (which Key the burger carries, whether the burger
// shows at all, the bell/burger semantic labels, the navigation each fires) are
// driven off `navigationShell.currentIndex` via the [_TopBarConfig] table below
// — keeping a single readable mapping close to the branch-index matrix idiom.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/navigation/shell_back_dispatcher.dart';
import 'package:beautica_mobile/shared/widgets/edge_swipe_back.dart';

import 'widgets/client_bottom_nav.dart';
import 'widgets/client_top_bar.dart';

class ClientShell extends StatefulWidget {
  const ClientShell({super.key, required this.navigationShell});

  /// The shell supplied by [StatefulShellRoute.indexedStack].
  final StatefulNavigationShell navigationShell;

  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  /// The booking-DETAIL route pattern (`/bookings/:bookingId`) — the ONE route
  /// on which the bottom nav is suppressed. Composed from the Записи branch
  /// list path + the child param segment so it stays in lockstep with the
  /// go_router branch definition in app_router.dart (which is NOT edited here);
  /// it matches the detail page only, never the `/bookings` list root or any
  /// other tab.
  static const String _bookingDetailPattern =
      '${RouteNames.clientBookings}/:bookingId';

  /// The router whose location changes we listen for. `navigationShell.currentIndex`
  /// does NOT change on a same-branch nested push (tapping a `BookingCard` pushes
  /// `/bookings/:id` onto the Записи branch while the index stays 3), so the
  /// StatefulShellRoute builder alone never re-runs this shell's `build` on that
  /// push/pop. Listening to the router's location provider gives us the rebuild
  /// that toggles the bar as the detail page is pushed on / popped off.
  GoRouter? _router;

  /// Convenience accessor so the (verbatim) build body + handlers below keep
  /// reading `navigationShell` unqualified.
  StatefulNavigationShell get navigationShell => widget.navigationShell;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final GoRouter router = GoRouter.of(context);
    if (!identical(router, _router)) {
      _router?.routeInformationProvider.removeListener(_onLocationChanged);
      _router = router;
      router.routeInformationProvider.addListener(_onLocationChanged);
    }
  }

  @override
  void dispose() {
    _router?.routeInformationProvider.removeListener(_onLocationChanged);
    super.dispose();
  }

  /// Rebuilds the shell whenever the active location changes — the trigger that
  /// flips the bottom bar off/on as the booking-detail page enters/leaves the
  /// Записи branch stack (a same-branch push that leaves `currentIndex` at 3).
  void _onLocationChanged() {
    if (mounted) setState(() {});
  }

  void _onTap(int index) {
    // `initialLocation: true` re-pops a branch to its root when its current tab
    // is re-tapped (standard go_router idiom); a no-op for a fresh hop.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  /// Opens the CLIENT settings hub (/client/menu) — the burger-menu mirror of
  /// the master settings hub. Role-gated to CLIENT in auth_redirect.dart. The
  /// hub's Account row routes onward to the shared SettingsScreen (/settings).
  void _onBurger(BuildContext context) => context.push(RouteNames.clientMenu);

  void _onBell(BuildContext context) {
    // Phase 14.9 not yet shipped — notification center is a placeholder. The
    // bell is intentionally inert here (no route yet). When 14.9 ships, push
    // RouteNames.notifications and bind ClientTopBar.hasUnread from the unread
    // provider (single call site now — see the [ClientTopBar] below).
    //
    // TODO(14.9): context.push(RouteNames.notifications).
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final _TopBarConfig config = _configFor(navigationShell.currentIndex, l10n);

    // Booking-DETAIL detection — the deepest active ROUTE PATTERN compared to
    // `/bookings/:bookingId`, exact-matching the detail page only (NOT the
    // `/bookings` list root, NOT any other tab). The `didChangeDependencies`
    // listener above re-evaluates this on the same-branch push/pop.
    //
    // WHY NOT `currentConfiguration.fullPath` DIRECTLY (the ab34c0a bug)
    // -----------------------------------------------------------------
    // The detail page is reached by an imperative `context.push`
    // (my_bookings_screen.dart) — a `BookingCard` tap PUSHES `/bookings/:id`
    // onto the Записи branch, it does NOT `go`. go_router wraps a pushed leaf in
    // an `ImperativeRouteMatch`, which `RouteMatchList._generateFullPath`
    // EXPLICITLY SKIPS ("they don't contribute to the path"), and the root
    // match list keeps its BASE uri via `copyWith`. So on the pushed detail the
    // ROOT `currentConfiguration.fullPath` (and `.uri`) collapse to `/bookings`
    // — the `== '/bookings/:bookingId'` check is NEVER true and the bar never
    // hides on a real device. (It only worked in the old widget test because a
    // `router.go` produces a plain, non-imperative match whose fullPath IS the
    // pattern — the classic mock-green/real-breakage.) The pushed leaf's OWN
    // inner match list DOES carry the real deepest pattern, so read it there;
    // for a non-imperative (go) match the root fullPath is already correct.
    final RouteMatchList routeConfig = GoRouter.of(
      context,
    ).routerDelegate.currentConfiguration;
    final RouteMatch? leaf = routeConfig.lastOrNull;
    final String currentPath = leaf is ImperativeRouteMatch
        ? leaf.matches.fullPath
        : routeConfig.fullPath;
    final bool onBookingDetail = currentPath == _bookingDetailPattern;

    // ONE back-navigation policy for BOTH the platform back button (the
    // [PopScope] below) and the left-edge swipe (the [EdgeSwipeBack] further
    // down) — so the gesture and the button can never diverge. It pops a pushed
    // detail page off the ACTIVE branch's own stack first (→ PREVIOUS page), and
    // only when that branch is at its root hops to the Home tab; on the Home tab
    // root it no-ops. See [ShellBackDispatcher] for the full contract.
    final ShellBackDispatcher backDispatcher = ShellBackDispatcher(
      navigationShell: navigationShell,
      branchNavigatorKeys: clientBranchNavigatorKeys,
      homeIndex: kClientHomeBranch,
    );
    final bool onHomeBranch = navigationShell.currentIndex == kClientHomeBranch;

    // System-back / predictive-back handling.
    //
    // Flutter dispatches the back button to the innermost (active branch)
    // Navigator FIRST, so a detail page pushed onto a branch is popped before
    // this shell-level PopScope is ever consulted. The PopScope therefore only
    // fires when the active branch is AT ITS ROOT: on the Home branch root back
    // exits the app (canPop:true — standard home behaviour); on any other tab
    // root the blocked back hops to Home via the shared dispatcher (the SAME
    // `goBranch` the bottom nav and the edge swipe use — no Navigator route call).
    return PopScope(
      canPop: onHomeBranch,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        // Pop already happened (Home branch root → app exit) — nothing to do.
        if (didPop) return;
        // Blocked pop on a non-Home tab root → hop to Home (dispatcher no-ops
        // the branch-pop branch here since the branch is already at its root).
        backDispatcher.handleBack();
      },
      child: Scaffold(
        backgroundColor: BrandColors.base,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              // Persistent top chrome — mounted ONCE, byte-identical across every
              // branch by construction. The single `VelvetSpacing.sm` top inset
              // the per-screen bars used to carry now lives here, so the wordmark
              // sits at the SAME dy on every branch.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  VelvetSpacing.lg,
                  VelvetSpacing.sm,
                  VelvetSpacing.lg,
                  0,
                ),
                child: ClientTopBar(
                  // Single STABLE identity across every branch hop — the element
                  // subtree is reused (updated in place) instead of torn down and
                  // rebuilt on each `goBranch`. The only per-branch differences
                  // (showBurger + the bell/burger test keys) flow through props
                  // below via `_configFor`, none of which need a new bar IDENTITY.
                  key: const Key('client-top-bar'),
                  onBell: () => _onBell(context),
                  onBurger: config.showBurger ? () => _onBurger(context) : null,
                  bellSemanticLabel: l10n.homeHubNotificationsLabel,
                  burgerSemanticLabel: l10n.settingsHubMenuButton,
                  bellKey: config.bellKey,
                  burgerKey: config.burgerKey,
                  // hasUnread is pinned false until the Phase 14.9 notification
                  // provider ships (single call site now).
                ),
              ),
              // Left-edge swipe-back — the gesture twin of the [PopScope]
              // system-back above, routed through the SAME [ShellBackDispatcher]
              // so the two can never drift. A committed rightward edge drag:
              //   • pops a pushed detail page off the active branch (e.g.
              //     `/search/results` → back to the filters) — the PREVIOUS page;
              //   • or, on a non-Home tab ROOT, hops to the Home branch;
              //   • or, on the Home tab root, no-ops.
              // The strip is ALWAYS mounted (`enabled: true`) rather than gated on
              // `!onHomeBranch`: a detail page can be pushed onto the HOME branch
              // too, and it MUST stay swipe-poppable — the previous `!onHomeBranch`
              // gate wrongly disarmed the swipe there (and on every branch it fired
              // `goBranch(Home)` UNCONDITIONALLY, jumping Home instead of popping
              // the detail — the regression this fixes). The handler no-ops on the
              // Home tab root, so an always-mounted strip is harmless there. The
              // 20px edge strip keeps the gesture off the tabs' own horizontal
              // scrollers (search filter rail, calendars) — see [EdgeSwipeBack].
              Expanded(
                child: EdgeSwipeBack(
                  enabled: true,
                  onSwipeBack: backDispatcher.handleBack,
                  child: navigationShell,
                ),
              ),
            ],
          ),
        ),
        // Suppressed on the booking-detail page (`/bookings/:bookingId`) so the
        // detail reads as a focused, full-height surface. `null` (not a shrunk
        // placeholder) removes the slot entirely, letting the body's Expanded
        // extend to the screen bottom; the detail screen's own Scaffold+SafeArea
        // (BookingSuccessScaffold) handles the bottom system inset, so the outer
        // `SafeArea(bottom:false)` stays as-is — no gap, no double-inset.
        bottomNavigationBar: onBookingDetail
            ? null
            : ClientBottomNav(
                activeIndex: navigationShell.currentIndex,
                onTap: _onTap,
                homeLabel: l10n.clientNavHome,
                favoritesLabel: l10n.clientNavFavorites,
                searchLabel: l10n.clientNavSearch,
                bookingsLabel: l10n.clientNavBookings,
              ),
      ),
    );
  }
}

/// Per-branch top-bar configuration, keyed by the [StatefulShellBranch] index.
///
/// Only the per-branch DIFFERENCES live here: whether the burger renders, and
/// the stable test Keys each branch's bell/burger carry. The bar's own identity
/// is a single stable `Key('client-top-bar')` set at the mount site (so its
/// element is reused across hops, not torn down). The bell/burger semantic
/// labels and the navigation actions are identical across branches and live on
/// [ClientShell] directly (single source).
class _TopBarConfig {
  const _TopBarConfig({required this.showBurger, this.bellKey, this.burgerKey});

  /// Whether the burger renders. The settings hub it opens is reachable from
  /// every branch, so the only branch that omits it is Пошук (where it reads as
  /// redundant on a filter surface).
  final bool showBurger;

  /// Stable per-branch Key for the bell (test target).
  final Key? bellKey;

  /// Stable per-branch Key for the burger (test target). Ignored when
  /// [showBurger] is false.
  final Key? burgerKey;
}

/// Resolves the [_TopBarConfig] for [branchIndex].
///
/// Burger SHOWN on Головна(0), Улюблені(1), Записи(3), BEAUTY PASSPORT(4);
/// OMITTED on Пошук(2). Decision (favorites/bookings): the burger is SHOWN
/// there too — the CLIENT settings hub is a useful escape hatch from those
/// branches and showing it keeps the chrome uniform on four of the five tabs.
///
/// The home + passport burger Keys are preserved verbatim (`btn-menu-client` /
/// `btn-menu-passport`) so existing widget/integration finders still resolve.
_TopBarConfig _configFor(int branchIndex, AppLocalizations l10n) {
  switch (branchIndex) {
    case kClientHomeBranch: // 0
      return const _TopBarConfig(
        showBurger: true,
        bellKey: Key('home_hub_bell_button'),
        burgerKey: Key('btn-menu-client'),
      );
    case kClientFavoritesBranch: // 1
      return const _TopBarConfig(
        showBurger: true,
        bellKey: Key('favorites_bell_button'),
        burgerKey: Key('btn-menu-favorites'),
      );
    case kClientSearchBranch: // 2 — Пошук omits the burger.
      return const _TopBarConfig(
        showBurger: false,
        bellKey: Key('search_bell_button'),
      );
    case kClientBookingsBranch: // 3
      return const _TopBarConfig(
        showBurger: true,
        bellKey: Key('bookings_bell_button'),
        burgerKey: Key('btn-menu-bookings'),
      );
    case kClientPassportBranch: // 4
      return const _TopBarConfig(
        showBurger: true,
        bellKey: Key('passport_bell_button'),
        burgerKey: Key('btn-menu-passport'),
      );
    default:
      // Defensive: an unknown index still renders a stable bar (burger shown).
      return const _TopBarConfig(showBurger: true);
  }
}
