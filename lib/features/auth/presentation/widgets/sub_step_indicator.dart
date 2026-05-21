// Phase 2.17 — Sub-step indicator (two pill dots).
//
// SOURCE OF TRUTH: sign-up-step-2-profile.html .substep-row / .substep-dots
//
// CSS reference:
//   .substep-row    { display:flex; align-items:center; margin-bottom:14px }
//   .substep-dots   { display:flex; gap:6px }
//   .substep-dot    { width:18px; height:3px; border-radius:2px; background:rgba(255,255,255,0.1) }
//   .substep-dot.active { background: var(--accent) #b89a7a }
//
// The HTML variant mockups show dots only — no visible text label.
// The [label] param is retained for screen-reader context only (attached via
// [Semantics]); it does NOT render as a visible widget.
//
// Reused by RegisterStep3Screen (Phase 2.19) — pass a different [activeIndex]
// to represent the address sub-step.

import 'package:flutter/material.dart';

import '../../../../core/theme/brand_colors.dart';

// ---------------------------------------------------------------------------
// Pre-allocated decoration constants (PERF — no per-build allocation)
// ---------------------------------------------------------------------------

/// .substep-dot.active { background: var(--accent) #b89a7a }.
const _kActiveDot = BoxDecoration(
  color: BrandColors.camel,
  borderRadius: BorderRadius.all(Radius.circular(2)),
);

/// .substep-dot { background: rgba(255,255,255,0.1) }.
const _kInactiveDot = BoxDecoration(
  color: Color(0x1AFFFFFF), // rgba(255,255,255,0.1)
  borderRadius: BorderRadius.all(Radius.circular(2)),
);

/// .substep-dot { width: 18px; height: 3px }
const double _kDotWidth = 18;
const double _kDotHeight = 3;

/// .substep-dots { gap: 6px }
const double _kDotGap = 6;

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Two-dot sub-progress indicator rendered at the top of the wizard glass card.
///
/// [totalSteps] — total number of pill dots (default 2).
/// [activeIndex] — 0-based index of the active (camel-coloured) dot. All
///   other dots are rendered inactive (white 10%).
/// [label] — optional description attached as a [Semantics] label on the dots
///   row for screen-reader context. No visible text is rendered.
///
/// Keys:
///   Key('substep-dot-0') .. Key('substep-dot-N')  — one per dot
class SubStepIndicator extends StatelessWidget {
  const SubStepIndicator({
    super.key,
    this.totalSteps = 2,
    this.activeIndex = 0,
    this.label,
  });

  /// Total number of pill dots.
  final int totalSteps;

  /// Zero-based index of the active (highlighted) dot.
  final int activeIndex;

  /// Optional description exposed to screen readers. Not rendered as visible text.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final dotsRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < totalSteps; i++) ...[
          if (i > 0) const SizedBox(width: _kDotGap),
          SizedBox(
            key: Key('substep-dot-$i'),
            width: _kDotWidth,
            height: _kDotHeight,
            child: DecoratedBox(
              decoration: i == activeIndex ? _kActiveDot : _kInactiveDot,
            ),
          ),
        ],
      ],
    );

    if (label == null) {
      return Align(alignment: Alignment.centerLeft, child: dotsRow);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(label: label, child: dotsRow),
    );
  }
}
