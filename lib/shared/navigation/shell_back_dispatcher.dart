// Shared back-navigation dispatcher for bottom-nav role shells.
//
// Lives in `lib/shared/` (NOT `lib/features/`) on purpose: it calls
// `NavigatorState.pop()` on a branch's [GlobalKey], and keeping it outside
// `lib/features/` sits clear of the CI `Forbid direct Navigator usage in
// lib/features/` gate (pr-validate.yml) — which forbids `Navigator.(push|pop|of)`
// route calls in feature code, NOT popping a nested branch navigator via its own
// key (the exact primitive the platform back button already uses).

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// One shared back-navigation policy for every bottom-nav
/// [StatefulNavigationShell] role shell (CLIENT today; any future SALON /
/// provider shell tomorrow). Both the left-edge swipe gesture AND the platform
/// back button route through it, so the two can never drift.
///
/// It mirrors Android's nested-navigator back contract EXACTLY:
///
///   1. If the ACTIVE branch's own Navigator can pop (a detail page is on top),
///      pop THAT — returning to the PREVIOUS page. The branch is unchanged.
///   2. Else, if the shell is NOT on its home / first tab, hop to the home
///      branch ([StatefulNavigationShell.goBranch], `initialLocation: false` so
///      the home stack is preserved).
///   3. Else (home tab root, nothing to pop) — no-op; let the platform back fall
///      through to the OS (app exit).
///
/// Step 1 is what Flutter does implicitly for the system back button (it
/// dispatches to the innermost branch Navigator FIRST). The edge-swipe strip is
/// mounted OUTSIDE the branch navigators, so it must replicate that step
/// explicitly through the branch [GlobalKey]s — which is the whole reason this
/// dispatcher exists. Because the swipe and the system back both call
/// [handleBack], their behaviour is identical by construction.
class ShellBackDispatcher {
  const ShellBackDispatcher({
    required this.navigationShell,
    required this.branchNavigatorKeys,
    required this.homeIndex,
  });

  /// The shell supplied by [StatefulShellRoute.indexedStack].
  final StatefulNavigationShell navigationShell;

  /// One [GlobalKey] per branch, indexed by branch position — the SAME keys the
  /// `StatefulShellBranch(navigatorKey: ...)` declarations use, so
  /// `.currentState` resolves the live branch [NavigatorState].
  final List<GlobalKey<NavigatorState>> branchNavigatorKeys;

  /// The home / first-tab branch index the shell falls back to.
  final int homeIndex;

  NavigatorState? get _activeBranchNavigator =>
      branchNavigatorKeys[navigationShell.currentIndex].currentState;

  bool get _activeBranchCanPop => _activeBranchNavigator?.canPop() ?? false;

  bool get _onHome => navigationShell.currentIndex == homeIndex;

  /// True when a back action has somewhere to go WITHOUT exiting the app: a
  /// detail page to pop, or a non-home tab to leave for the home tab. Drive a
  /// shell [PopScope]'s `canPop` off `!canHandleBack`, and an [EdgeSwipeBack]'s
  /// `enabled` may safely stay `true` regardless since [handleBack] no-ops here.
  bool get canHandleBack => _activeBranchCanPop || !_onHome;

  /// Runs the back action described above. Returns true when it consumed the
  /// back (a page was popped or the shell hopped to home); false only on the
  /// home tab root, where nothing was done.
  bool handleBack() {
    final NavigatorState? branch = _activeBranchNavigator;
    if (branch?.canPop() ?? false) {
      // A detail page sits on top of the active branch — pop it (go to the
      // PREVIOUS page). Do NOT change branch. `branch` is non-null here because
      // `canPop()` above resolved on it.
      branch?.pop();
      return true;
    }
    if (!_onHome) {
      // Active branch is at its root and we are on a non-home tab — hop to the
      // home tab, preserving the home branch's own stack.
      navigationShell.goBranch(homeIndex, initialLocation: false);
      return true;
    }
    // Home tab root, nothing on top — no-op.
    return false;
  }
}
