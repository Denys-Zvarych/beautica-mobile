// M544 — pixel lock for the promoted [SwipeActionBackground].
//
// `swipe_action_background_salon_default` was SEEDED from a verbatim copy of
// the original private `_DeleteSalonSwipeBackground` (my_salons_screen.dart)
// BEFORE the promotion, then re-run unchanged against the promoted widget's
// defaults: the «Мої салони» swipe reveal is pixel-identical.
// `swipe_action_background_client_remove` is the «Клієнти» row reveal
// (person-remove glyph + «Прибрати»).

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/shared/widgets/swipe_action_background.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

Widget _frame(Widget child) => Padding(
  padding: const EdgeInsets.all(VelvetSpacing.md),
  child: SizedBox(height: 64, child: child),
);

void main() {
  goldenTest(
    'SwipeActionBackground salon default',
    fileName: 'swipe_action_background_salon_default',
    constraints: BoxConstraints.tight(const Size(360, 96)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: 360),
    builder: () => _frame(const SwipeActionBackground()),
  );

  goldenTest(
    'SwipeActionBackground client remove',
    fileName: 'swipe_action_background_client_remove',
    constraints: BoxConstraints.tight(const Size(360, 96)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: 360),
    builder: () => _frame(
      const SwipeActionBackground(
        icon: Icons.person_remove_outlined,
        label: 'Прибрати',
      ),
    ),
  );
}
