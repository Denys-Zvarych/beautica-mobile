// 2026-10-30 — master-nav setup-hint dots on `VelvetBottomNavBar`.
//
// One bar with BOTH dots on and tile 0 («Послуги») active, so a single cell
// pins the dot on an ACTIVE tile (0, accentDeep icon) and on an INACTIVE tile
// (2 «Графік», muted icon). The hint answer is overridden directly
// (`masterNavSetupHintsProvider`) — which hints show is proven by
// `test/shared/widgets/velvet_bottom_nav_bar_setup_hints_test.dart`; this file
// pins only the look (8 dp mocha dot, base ring, -1 dp corner inset).
//
// The dot-less bar stays pinned, byte-identical, by
// `bottom_nav_inset_golden_test.dart` (`showSetupHints` defaults off).
//
// Matrix: {360, 414} dp x {1.0} scale — same widths as the nav-bar goldens.
// File names: velvet_bottom_nav_bar_setup_dots_<width>_1x.png

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_link_setup_hints_provider.dart';
import 'package:beautica_mobile/features/booking_links/presentation/master_nav_setup_hints_provider.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const List<double> _widths = <double>[360, 414];

void main() {
  for (final double width in _widths) {
    final int w = width.toInt();
    goldenTest(
      'VelvetBottomNavBar with both setup dots (active tile 0, inactive tile '
      '2) at $w dp',
      fileName: 'velvet_bottom_nav_bar_setup_dots_${w}_1x',
      constraints: BoxConstraints.tight(Size(width, 140)),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(
        width: width,
        overrides: <Object>[
          masterNavSetupHintsProvider.overrideWithValue(
            const BookingLinkSetupHints(schedule: true, services: true),
          ),
        ],
      ),
      builder: () => const ColoredBox(
        color: BrandColors.base,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: VelvetBottomNavBar(activeIndex: 0, showSetupHints: true),
        ),
      ),
    );
  }
}
