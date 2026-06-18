// Phase 13.1 — CLIENT 5-tab navigation scaffold.
//
// Wraps a [StatefulNavigationShell] (the body of the CLIENT
// StatefulShellRoute.indexedStack) and renders the active branch + the
// [ClientBottomNav]. Tapping a tab hops the branch via `goBranch` — it does NOT
// grow the nav stack (the prior `context.push`-retains-shell note from
// profile_avatar.dart:555 is exactly what StatefulShellRoute fixes).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import 'widgets/client_bottom_nav.dart';

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(bottom: false, child: navigationShell),
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
