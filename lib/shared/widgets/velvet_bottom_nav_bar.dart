// Phase 4.2 — VelvetBottomNavBar (originally authored alongside ProfileAvatar
// in `features/master/presentation/widgets/profile_avatar.dart`).
//
// Moved here (Phase 7.14) so it can be reused across features — the master
// profile screen AND the master «Мої записи» screen both render this exact
// bar — without a cross-feature `presentation/`-to-`presentation/` import,
// which the architecture's layering rule forbids (booking/presentation may
// import shared/, never master/presentation/ directly). Mirrors the Phase
// 13.6 move of `ContactTile` to this same directory for the identical
// reason. `features/master/presentation/widgets/profile_avatar.dart` now
// re-exports this file so its existing import sites (master_profile_screen
// .dart, the nav-bar navigation/routing tests) keep working unchanged.
//
// Ported verbatim from
// `docs/signup-designs/MasterProfileScreen/lib/widgets/profile_widgets.dart`.
// `VelvetColors.*` → `BrandColors.*`.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/routing/route_names.dart';

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Full left→right layout: [Послуги(0)] [Мої записи(1)] [Графік(2)] [Профіль(3)].
const List<_NavItem> _navItems = <_NavItem>[
  _NavItem(
    icon: Icons.design_services_outlined,
    activeIcon: Icons.design_services_rounded,
    label: 'Послуги',
  ),
  _NavItem(
    icon: Icons.event_note_outlined,
    activeIcon: Icons.event_note_rounded,
    label: 'Мої записи',
  ),
  _NavItem(
    icon: Icons.calendar_month_outlined,
    activeIcon: Icons.calendar_month_rounded,
    label: 'Графік',
  ),
  _NavItem(
    icon: Icons.person_outline,
    activeIcon: Icons.person_rounded,
    label: 'Профіль',
  ),
];

/// Neumorphic bottom navigation bar for the master surface. The bar is
/// extruded from the surface — a top-facing light highlight raises it above the
/// content, the dark shadow anchors it to the page floor.
///
/// [activeIndex] selects the highlighted item (0 = Послуги, 1 = Мої записи,
/// 2 = Графік, 3 = Профіль). A camel accent pill floats above the active icon.
///
/// Every master "tab" screen renders its OWN instance of this bar (the master
/// surface has no `StatefulShellRoute` — see `app_router.dart`'s
/// `RouteNames.masterBookings` registration comment) with `activeIndex` set to
/// that screen's own tile: `MasterProfileScreen` (through `ProfileScaffold`),
/// `MasterBookingsScreen` (wrapping `BookingsDiscoveryView`),
/// `ServicesListScreen`, and `MasterScheduleScreen` all pass this bar to their
/// own `Scaffold.bottomNavigationBar` — one convention, applied identically on
/// all four, never inlined into a scrollable body or nested inside the body's
/// own `SafeArea` (either breaks the inset accounting this bar's internal
/// `SafeArea(top: false)` relies on — see `ProfileScaffold.bottomNavBar`'s doc
/// comment for the concrete failure mode this shipped as).
///
/// Ported verbatim from
/// `docs/signup-designs/MasterProfileScreen/lib/widgets/profile_widgets.dart`.
/// `VelvetColors.*` → `BrandColors.*`.
class VelvetBottomNavBar extends StatelessWidget {
  const VelvetBottomNavBar({super.key, required this.activeIndex});

  final int activeIndex;

  static const BorderRadius _pillRadius = BorderRadius.all(Radius.circular(28));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.md,
        0,
        VelvetSpacing.md,
        VelvetSpacing.md,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: BrandColors.base,
          borderRadius: _pillRadius,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: BrandColors.shadowLightStrong,
              offset: Offset(-6, -6),
              blurRadius: 16,
            ),
            BoxShadow(
              color: BrandColors.shadowDarkCard,
              offset: Offset(6, 6),
              blurRadius: 16,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: _pillRadius,
          child: SafeArea(
            top: false,
            // ConstrainedBox (minHeight, not a fixed SizedBox height) so the bar
            // grows with the tile's intrinsic content at large text scales
            // (textScale 1.3 pushed the icon + pill + label past a fixed 62 dp
            // and overflowed the nav tile column by 5 px). IntrinsicHeight keeps
            // all four tiles the same height as the tallest one.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 62),
              child: IntrinsicHeight(
                child: Row(
                  children: <Widget>[
                    for (int i = 0; i < _navItems.length; i++)
                      Expanded(
                        child: _VelvetNavTile(
                          key: Key('master-nav-tile-$i'),
                          item: _navItems[i],
                          index: i,
                          active: i == activeIndex,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VelvetNavTile extends StatelessWidget {
  const _VelvetNavTile({
    super.key,
    required this.item,
    required this.index,
    required this.active,
  });

  final _NavItem item;
  final int index;
  final bool active;

  /// Resolves the go_router path for a nav-bar [index]. Every index maps to
  /// its real destination; tapping the already-active tile resolves to
  /// `null` via the guard above so we never issue a redundant navigation to
  /// the current location. Do not special-case any index to `null` here —
  /// the `active` guard is the single source of "no-op because we're
  /// already here".
  ///
  /// Every branch below is a TOP-LEVEL tab root (registered as a flat
  /// `GoRoute` in `app_router.dart`, never nested under another tab) — that
  /// is what makes `context.go` in [build] safe here specifically: see that
  /// call site's comment for why.
  String? _routeFor(int index) {
    if (active) return null;
    return switch (index) {
      0 => RouteNames.services, // Послуги
      1 => RouteNames.masterBookings, // Мої записи → Phase 7.6
      2 => RouteNames.masterSchedule, // Графік → Phase 15.2 schedule screen
      _ => RouteNames.masterProfile, // Профіль
    };
  }

  @override
  Widget build(BuildContext context) {
    final Color color = active ? BrandColors.accentDeep : BrandColors.muted;
    final String? route = _routeFor(index);

    return Semantics(
      label: item.label,
      selected: active,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // `context.go`, NOT `context.push` — a DELIBERATE reversal of the
        // earlier push decision (see `profile_nav_bar_navigation_test.dart`'s
        // header for that decision's own history). `push` stacked a new tab
        // route on top of the previous one on every tab tap, so hopping
        // between the four tabs grew the back stack unboundedly (4 tabs
        // visited → 4 deep). `go` replaces the whole stack with the tapped
        // tab's single route instead, so tab-switching never grows the stack.
        //
        // This is SAFE here specifically because every `_routeFor` target is
        // a top-level tab root (see that method's doc comment), and because
        // the original `go`-strands-the-user failure this reverses required
        // BOTH (a) `go` wiping the back button/swipe-back AND (b) the
        // destination screen rendering no other way to navigate — condition
        // (b) doesn't hold anywhere any more now that every one of the four
        // tab screens renders this exact bar (Part 1 of the same fix this
        // comment describes): whichever tab `go` lands on, this bar is right
        // there to leave it again. The two screens that still show a back
        // affordance after a stack-replacing `go` degrade gracefully instead
        // of dead-ending: `ServicesListScreen`'s plain `AppBar` back button is
        // `canPop`-gated (hides itself, exactly like `MasterProfileScreen`'s
        // `showBack: false` tab-root already does) and
        // `MasterScheduleScreen`'s `VelvetTopBar.onBack` already falls back to
        // `context.go(RouteNames.masterProfile)` when nothing is left to pop
        // — a pattern `app_router.dart`'s `RouteNames.masterSchedule`
        // registration comment confirms is already used elsewhere in this
        // router (the weekly editor's save/cancel return) for the exact same
        // reason. `MasterBookingsScreen` never shows a back affordance at all
        // (`onBack: null`) regardless of push or go. Nested drill-in routes
        // pushed from WITHIN a tab (service create/edit, booking detail,
        // schedule day editors, the settings hub) are untouched by this
        // change — they call `context.push` at their own call sites, not
        // through this bar, and keep their own back stack exactly as before.
        onTap: route == null ? null : () => context.go(route),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // Camel pill indicator above the active icon.
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: active ? 26 : 0,
              height: 3,
              margin: const EdgeInsets.only(bottom: VelvetSpacing.xs),
              decoration: BoxDecoration(
                gradient: active
                    ? const LinearGradient(
                        colors: <Color>[
                          BrandColors.accentDeep,
                          BrandColors.accent,
                        ],
                      )
                    : null,
                color: active ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(active ? item.activeIcon : item.icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              item.label,
              // M-1 fix: pre-composed base; one copyWith for the dynamic color
              // instead of two allocations (feedback() + copyWith) per frame.
              style: VelvetText.navTabLabel.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
