// Chrome golden — [ClientBottomNav] (the shell-hosted 5-tab CLIENT bar).
//
// Pins the active/inactive appearance of every tab — the indicator pill, the
// outline→filled icon swap, the muted→accentDeep tint, and the elevated center
// search disc's elevated (inactive) vs depressed (active) face. A regression in
// any of those reads as a pixel diff. One golden per active index (0..4) so each
// tab's selected state AND the other four tabs' inactive state are captured in
// the same frame.
//
// Matrix kept tight (chrome): {360} dp × {1.0} scale. The bar sits on the brand
// base color and is bottom-aligned in a tall box because its center disc
// overflows the bar's top edge (clipBehavior: Clip.none).
//
// File names: client_bottom_nav_active_<index>_360_1x.png  (index 0..4)

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

/// Hosts the bar bottom-aligned on the brand base background. The tall box gives
/// the center disc (which floats above the bar) room so it is not clipped.
Widget _host(double width, int activeIndex) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: ClientBottomNav(
        activeIndex: activeIndex,
        onTap: (_) {},
        // Labels supplied directly (the widget takes no l10n itself). The brand
        // "BEAUTY PASSPORT" tab caption is a const inside the widget.
        homeLabel: 'Головна',
        favoritesLabel: 'Улюблені',
        searchLabel: 'Пошук',
        bookingsLabel: 'Записи',
      ),
    ),
  ),
);

void main() {
  const double width = 360;

  // 0=Головна, 1=Улюблені, 2=Пошук (center disc), 3=Записи, 4=BEAUTY PASSPORT.
  for (final int activeIndex in <int>[0, 1, 2, 3, 4]) {
    goldenTest(
      'client_bottom_nav active tab $activeIndex',
      fileName: 'client_bottom_nav_active_${activeIndex}_360_1x',
      constraints: BoxConstraints.tight(const Size(width, 140)),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(width: width),
      builder: () => _host(width, activeIndex),
    );
  }
}
