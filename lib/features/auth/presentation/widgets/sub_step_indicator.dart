// Phase 2.17 — Sub-step indicator (two pill dots + optional label).
//
// SOURCE OF TRUTH: sign-up-step-2-profile.html .substep-row / .substep-dots
//
// CSS reference:
//   .substep-row    { display:flex; align-items:center; justify-content:space-between; margin-bottom:14px }
//   .substep-text   { font-size:10px; font-weight:600; color:rgba(255,255,255,0.45); letter-spacing:0.1em; text-transform:uppercase }
//   .substep-dots   { display:flex; gap:6px }
//   .substep-dot    { width:18px; height:3px; border-radius:2px; background:rgba(255,255,255,0.1) }
//   .substep-dot.active { background: var(--accent) #b89a7a }
//
// The HTML variant mockups show the dots only (no text in .substep-text). The
// phase doc specifies a text label ("Крок 2.1 — Профіль") alongside the dots.
// Both are rendered: dots on the right, label on the left — matching the
// `.substep-row { justify-content: space-between }` layout. When [label] is
// null, only the dots row is rendered (centred-left).
//
// Reused by RegisterStep3Screen (Phase 2.19) — pass a different [activeIndex]
// and [label] to represent "Крок 2.2 — Адреса".

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

/// .substep-text style (uppercase, w600, white 45%)
const TextStyle _kLabelStyle = TextStyle(
  color: Color(0x73FFFFFF), // rgba(255,255,255,0.45)
  fontSize: 10,
  fontWeight: FontWeight.w600,
  letterSpacing: 1.0, // 0.1em × 10px
  height: 1,
);

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Two-dot sub-progress indicator rendered at the top of the wizard glass card.
///
/// [totalSteps] — total number of pill dots (default 2).
/// [activeIndex] — 0-based index of the active (camel-coloured) dot. All
///   other dots are rendered inactive (white 10%).
/// [label] — optional uppercase label shown to the left of the dots. When
///   null, only the dots cluster is rendered.
///
/// Keys:
///   Key('substep-dot-0') .. Key('substep-dot-N')  — one per dot
///   Key('substep-label')                           — present when label != null
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

  /// Optional uppercase label rendered to the left of the dots cluster.
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label!.toUpperCase(),
          key: const Key('substep-label'),
          style: _kLabelStyle,
        ),
        dotsRow,
      ],
    );
  }
}
