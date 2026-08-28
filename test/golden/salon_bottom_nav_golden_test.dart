// Phase 21.8 QA follow-up — golden coverage for [SalonBottomNav] (the new
// SALON_OWNER/SALON_ADMIN shell bar, `lib/shared/widgets/salon_bottom_nav.dart`).
//
// Structurally the SAME chrome family as `client_bottom_nav_golden_test.dart`
// (this file mirrors its shape) minus the client bar's elevated center disc:
// a floating rounded pill, dual-direction neumorphic shadow, and a thin
// gradient indicator bar that grows in above the active icon. Pins the
// active/inactive appearance of every one of the 4 `ownerAdminItems` tabs —
// the indicator, the outline->filled icon swap, and the muted->accentDeep
// tint. A regression in any of those reads as a pixel diff.
//
// `SalonNavItem` needs no [AppLocalizations] here — unlike
// [SalonBottomNav.ownerAdminItems] (which sources labels from l10n), the
// widget itself is purely presentational and takes a caller-supplied
// `List<SalonNavItem>`, so the fixture below constructs items directly with
// fixed UK labels — same approach `client_bottom_nav_golden_test.dart` uses
// for `ClientBottomNav`'s own label params.
//
// Matrix kept tight (chrome): {360} dp x {1.0} scale, one golden per active
// index (0..3) so each tab's selected state AND the other three tabs'
// inactive state are captured in the same frame.
//
// File names: salon_bottom_nav_active_<index>_360_1x.png (index 0..3)

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const List<SalonNavItem> _items = <SalonNavItem>[
  SalonNavItem(
    label: 'Салон',
    icon: Icons.storefront_outlined,
    activeIcon: Icons.storefront_rounded,
  ),
  SalonNavItem(
    label: 'Записи',
    icon: Icons.calendar_month_outlined,
    activeIcon: Icons.calendar_month_rounded,
  ),
  SalonNavItem(
    label: 'Команда',
    icon: Icons.groups_outlined,
    activeIcon: Icons.groups_rounded,
  ),
  SalonNavItem(
    label: 'Профіль',
    icon: Icons.person_outline_rounded,
    activeIcon: Icons.person_rounded,
  ),
];

/// Hosts the bar bottom-aligned on the brand base background, mirroring
/// `client_bottom_nav_golden_test.dart`'s `_host`.
Widget _host(double width, int activeIndex) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: SalonBottomNav(
        currentIndex: activeIndex,
        onSelect: (_) {},
        items: _items,
      ),
    ),
  ),
);

void main() {
  const double width = 360;

  // 0=Салон, 1=Записи, 2=Команда, 3=Профіль.
  for (final int activeIndex in <int>[0, 1, 2, 3]) {
    goldenTest(
      'salon_bottom_nav active tab $activeIndex',
      fileName: 'salon_bottom_nav_active_${activeIndex}_360_1x',
      constraints: BoxConstraints.tight(const Size(width, 100)),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(width: width),
      builder: () => _host(width, activeIndex),
    );
  }
}
