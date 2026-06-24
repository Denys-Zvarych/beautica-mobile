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

import 'widgets/client_bottom_nav.dart';
import 'widgets/client_top_bar.dart';

class ClientShell extends StatelessWidget {
  const ClientShell({super.key, required this.navigationShell});

  /// The shell supplied by [StatefulShellRoute.indexedStack].
  final StatefulNavigationShell navigationShell;

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

    return Scaffold(
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
            Expanded(child: navigationShell),
          ],
        ),
      ),
      bottomNavigationBar: ClientBottomNav(
        activeIndex: navigationShell.currentIndex,
        onTap: _onTap,
        homeLabel: l10n.clientNavHome,
        favoritesLabel: l10n.clientNavFavorites,
        searchLabel: l10n.clientNavSearch,
        bookingsLabel: l10n.clientNavBookings,
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
