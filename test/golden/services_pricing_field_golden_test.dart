// Phase 17.4 — Visual regression goldens for PricingField widget.
//
// PricingField is the highest-risk visual component in the services feature:
// it switches between FIXED (one amount well) and RANGE (duration/min/max row)
// modes and has a tight layout at 320 dp that was previously an overflow
// source. Two rows are goldenned:
//   • FIXED mode  — single amount field
//   • RANGE mode  — three-column duration/min/max row
//
// Matrix: {320, 360, 414} dp × {textScale 1.0, 1.3} = 12 golden PNGs.
// PricingField is a pure StatelessWidget receiving controllers — no providers
// needed. Clock: no date-bearing UI.
//
// File names: pricing_fixed_<width>_<scale>.png
//             pricing_range_<width>_<scale>.png

import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Helper — wraps PricingField in a constrained Container so it renders as it
// would inside a Scaffold body (horizontal padding of 16 dp on each side,
// no vertical constraints).
// ---------------------------------------------------------------------------

Widget _fixedRow(double width) {
  final fixedCtrl = TextEditingController(text: '500');
  final minCtrl = TextEditingController();
  final maxCtrl = TextEditingController();
  final durationCtrl = TextEditingController(text: '60');
  addTearDown(fixedCtrl.dispose);
  addTearDown(minCtrl.dispose);
  addTearDown(maxCtrl.dispose);
  addTearDown(durationCtrl.dispose);

  return SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: PricingField(
        mode: ServicePriceType.fixed,
        onModeChanged: (_) {},
        fixedController: fixedCtrl,
        minController: minCtrl,
        maxController: maxCtrl,
        durationController: durationCtrl,
        durationLabel: 'Тривалість (хв)',
      ),
    ),
  );
}

Widget _rangeRow(double width) {
  final fixedCtrl = TextEditingController();
  final minCtrl = TextEditingController(text: '300');
  final maxCtrl = TextEditingController(text: '700');
  final durationCtrl = TextEditingController(text: '90');
  addTearDown(fixedCtrl.dispose);
  addTearDown(minCtrl.dispose);
  addTearDown(maxCtrl.dispose);
  addTearDown(durationCtrl.dispose);

  return SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: PricingField(
        mode: ServicePriceType.range,
        onModeChanged: (_) {},
        fixedController: fixedCtrl,
        minController: minCtrl,
        maxController: maxCtrl,
        durationController: durationCtrl,
        durationLabel: 'Тривалість (хв)',
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Goldens
// ---------------------------------------------------------------------------

void main() {
  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final suffix = widthScaleSuffix(width, scale);

      // FIXED mode
      goldenTest(
        'pricing_field FIXED ${width.toInt()}dp text-${scale}x',
        fileName: 'pricing_fixed_$suffix',
        constraints: BoxConstraints.tight(Size(width, 240)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(width: width),
        builder: () => _fixedRow(width),
      );

      // RANGE mode
      goldenTest(
        'pricing_field RANGE ${width.toInt()}dp text-${scale}x',
        fileName: 'pricing_range_$suffix',
        constraints: BoxConstraints.tight(Size(width, 280)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(width: width),
        builder: () => _rangeRow(width),
      );
    }
  }
}
