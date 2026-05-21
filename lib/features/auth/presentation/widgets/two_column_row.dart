// Phase 2.17 — Two-column row layout helper.
//
// SOURCE OF TRUTH: sign-up-step-2-profile.html .row-2
//   .row-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
//
// Wraps two equal-width widgets in a single Row with a configurable gap.
// Used by RegisterStep2Screen to place Ім'я and Прізвище side-by-side.
// Reused by RegisterStep3Screen (Phase 2.19) for Street + Building fields.

import 'package:flutter/material.dart';

/// Places [left] and [right] in equal-width columns separated by [gap] px.
///
/// Both children are wrapped in [Expanded] so they share the available width
/// equally regardless of their intrinsic sizes. The [gap] defaults to 12 dp
/// (the project's AppSpacing.sm token), matching the 10 px HTML gap rounded
/// up to the nearest 4 dp grid step; callers may override to pass the exact
/// CSS value (10 dp) if pixel-fidelity is required.
class TwoColumnRow extends StatelessWidget {
  const TwoColumnRow({
    super.key,
    required this.left,
    required this.right,
    this.gap = 12,
  });

  /// Left column widget — receives 50 % of available width.
  final Widget left;

  /// Right column widget — receives 50 % of available width.
  final Widget right;

  /// Horizontal gap between the two columns. Defaults to 12 dp (AppSpacing.sm).
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        SizedBox(width: gap),
        Expanded(child: right),
      ],
    );
  }
}
