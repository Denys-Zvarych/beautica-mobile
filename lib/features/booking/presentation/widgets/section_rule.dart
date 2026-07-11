// Shared booking-card hairline separator.
//
// Extracted from the private `_SectionRule` in `booking_summary_cards.dart` so
// both flows' recap cards compose the SAME atom. [dense] tightens the vertical
// inset for the compact (success-screen) card rhythm.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';

/// A thin hairline separating two sections of a booking-details card — the
/// only "structure" inside the card.
class SectionRule extends StatelessWidget {
  const SectionRule({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: dense ? VelvetSpacing.sm + 2 : VelvetSpacing.md,
      ),
      child: Container(
        height: 1,
        color: BrandColors.faint.withValues(alpha: 0.5),
      ),
    );
  }
}
