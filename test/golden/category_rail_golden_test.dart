// Phase 13.4 — Full-label category-rail golden (FIRST rail golden).
//
// The canonical wrap / no-truncation pixel case for [CategoryRailTile]: a row
// holding a deliberately long label («Перманентний макіяж», which MUST wrap onto
// a 2nd line within the 132dp ceiling, never ellipsis-clip) beside a short one
// («Брови»), one tile selected (pressed-in inset well) and one resting (raised
// pill). A regression that re-introduces single-line truncation, drops the wrap,
// or swaps the selected/resting treatment reads as a pixel diff here.
//
// Each tile sizes to its own intrinsic width (min 72 / max 132dp), so the row is
// laid out at its natural width inside a horizontally-scrolling container — we
// host it in a left-aligned Row on the brand base, matching the rail on screen.
//
// Captured at {360} dp × {1.0, 1.3} scale — the 1.3 cell is the meaningful one:
// it proves the long label still wraps (never clips) under large-text settings.
//
// File names: category_rail_full_labels_360_1x.png
//             category_rail_full_labels_360_1_3x.png

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/category_rail.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

/// A long label that must wrap to two lines, and a short one that stays a pill.
Widget _rail() => Row(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: <Widget>[
    CategoryRailTile(
      key: const Key('rail_tile_short'),
      icon: Icons.face_retouching_natural,
      label: 'Брови',
      selected: true,
      onTap: () {},
    ),
    const SizedBox(width: 12),
    CategoryRailTile(
      key: const Key('rail_tile_long'),
      icon: Icons.brush_outlined,
      label: 'Перманентний макіяж',
      selected: false,
      onTap: () {},
    ),
  ],
);

/// Hosts [child] on the brand base with the rail's vertical breathing room.
Widget _host(double width, Widget child) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Align(alignment: Alignment.centerLeft, child: child),
    ),
  ),
);

void main() {
  const double width = 360;

  for (final double scale in kGoldenTextScales) {
    goldenTest(
      'category rail full labels ${width.toInt()}dp x$scale',
      fileName: 'category_rail_full_labels_${widthScaleSuffix(width, scale)}',
      constraints: BoxConstraints.tight(const Size(width, 160)),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(width: width),
      builder: () => _host(width, _rail()),
    );
  }
}
