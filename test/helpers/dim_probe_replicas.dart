// If the real disabled face was restyled, update the replica here (a probe failing with only "ratio off" may be replica drift, not a dim regression).
// UNDIMMED replicas of private faces, for the pixel dim probe (Phase 301).
//
// `_MonthChevron` (month_calendar.dart) and `_PagerArrow` (salon_time_screen
// .dart) render their DISABLED state as `Opacity(0.55, child: face)`, where
// `face` is a 40dp `base` tile carrying a `faint` 24dp glyph and NO shadow. The
// enabled state is a different picture (accentDeep glyph, extruded shadow), so
// the probe cannot compare disabled-vs-enabled: the content differs, not only
// the dim. The honest "full" control is the SAME disabled face without the
// `Opacity` — which only a replica can supply, because the originals are
// private. The ratio  real-disabled : replica  is then the dim and nothing
// else (the same device `slot_picker_test.dart` uses for the unavailable
// SlotChip).
//
// If the real face is ever restyled, this replica drifts and the probe reads
// off-value (RED, loudly) — update both together.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:flutter/material.dart';

/// The disabled ‹ / › arrow face, UNDIMMED. 40x40, `base` fill, no shadow,
/// `faint` 24dp [icon].
class UndimmedDisabledArrowFace extends StatelessWidget {
  const UndimmedDisabledArrowFace({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      width: 40,
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.field),
      ),
      child: Icon(icon, color: BrandColors.faint, size: 24),
    );
  }
}
