// Phase 2.16 — Registration progress indicator (4 dots + per-active label).
//
// SOURCE OF TRUTH: docs/signup-designs/sign-up-page.html (and 4 sibling design
// HTMLs — sign-up-step-2-profile, sign-up-step-3-address, verification-page,
// done-page — which all share the IDENTICAL .progress-row block). The
// 2026-05-20 design refresh replaced the per-pill label model with a single
// label rendered ONLY under the currently-active dot:
//
//   <div class="progress-row">
//     <div class="prog-item active">                  ← dot 1 (or done/inactive)
//       <div class="prog-num">1</div>
//       <span class="prog-label-under">Акаунт</span>  ← only on active dot
//     </div>
//     <div class="prog-line"></div>
//     <div class="prog-item inactive"><div class="prog-num">2</div></div>
//     ...
//   </div>
//
// Why pass the active label in via the constructor:
//   Step 2 ("/register/step-2") and Step 3 ("/register/step-3") both collapse
//   to RegistrationStep.details — dot 2 is active for both. The label,
//   however, differs ("Профіль" vs "Локація"). Callers therefore pass the
//   correct localised label via [activeStepLabel] rather than the widget
//   deriving it internally from the step enum (which would force the enum
//   to grow a 5th value just to disambiguate the label).
//
// CSS → Flutter mapping (per HTML source):
//   .prog-item   { width: 22px; padding-bottom: 30px }       → fixed 22 dp column with 30 dp label slot
//   .prog-num    { width: 22px; height: 22px; border-radius: 50% } → SizedBox(22,22) + circle decoration
//   .prog-line   { flex: 1; height: 1px; margin: 0 4px }     → Expanded + 4 dp horizontal padding
//   .prog-label-under { position:absolute; top:30px; left:50%; transform:translateX(-50%); white-space:nowrap }
//                                                            → Positioned label centred on dot via OverflowBox
//   .prog-item.done    .prog-num   { background: rgba(184,154,122,0.22) } + checkmark glyph
//   .prog-item.active  .prog-num   { background: var(--accent) #b89a7a; color: #3a2810; box-shadow: 0 0 0 4px rgba(184,154,122,0.14) }
//   .prog-item.inactive .prog-num  { border: 1.5px solid rgba(255,255,255,0.15); color: rgba(255,255,255,0.28) }
//   .prog-line.done    { background: rgba(184,154,122,0.25) }
//   .prog-line         { background: rgba(255,255,255,0.08) }
//   .prog-label-under  { font: 14px italic 600 Cormorant Garamond; color: var(--accent); letter-spacing: 0.01em; line-height: 1 }
//
// Testability keys:
//   Key('progress-step-1')..Key('progress-step-4')  — one per dot column
//   Key('progress-check-N')                         — present on done dots only
//   Key('progress-active-label')                    — present exactly once when [activeStepLabel] is non-null

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/brand_colors.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Current step in the registration wizard.
///
/// Dot 1 corresponds to [account]; dot 2 corresponds to [details] (Step 2 OR
/// Step 3 — both collapse onto the same dot); dot 3 to [verification]; dot 4
/// to [done]. Dots LEFT of the current step render as `done`, the current
/// step renders as `active`, and dots RIGHT render as `inactive`.
enum RegistrationStep {
  /// `/register` — credentials (email + password + confirm).
  account,

  /// `/register/step-2` (profile) OR `/register/step-3` (address). Both
  /// share the same dot; the label is supplied by the caller.
  details,

  /// `/verification` — OTP entry.
  verification,

  /// `/done` — terminal screen. All preceding dots are `done`; this dot is
  /// rendered `active` (the design has no all-done state — the final screen
  /// is the active step until the user leaves the wizard).
  done,
}

/// Renders the 4-dot progress row used on every registration-flow screen.
///
/// [currentStep] selects which dot is highlighted as the active one.
/// [activeStepLabel] — when non-null — is rendered as italic Cormorant
/// Garamond camel text under the active dot, allowed to overflow the active
/// dot's 22 dp column into neighbouring (empty) label slots. When null no
/// label is rendered (mostly useful for tests / screenshots that want to
/// show the dot row in isolation).
class RegistrationProgress extends StatelessWidget {
  const RegistrationProgress({
    super.key,
    required this.currentStep,
    this.activeStepLabel,
  });

  final RegistrationStep currentStep;
  final String? activeStepLabel;

  static const int _kStepCount = 4;

  @override
  Widget build(BuildContext context) {
    final currentIndex = currentStep.index;
    final stepKeys = <Key>[
      const Key('progress-step-1'),
      const Key('progress-step-2'),
      const Key('progress-step-3'),
      const Key('progress-step-4'),
    ];

    final children = <Widget>[];
    for (var i = 0; i < _kStepCount; i++) {
      children.add(
        _ProgItem(
          key: stepKeys[i],
          number: i + 1,
          state: _stateFor(i, currentIndex),
          activeLabel: i == currentIndex ? activeStepLabel : null,
        ),
      );
      if (i < _kStepCount - 1) {
        children.add(_ProgLine(done: i < currentIndex));
      }
    }

    return Semantics(
      container: true,
      label: activeStepLabel == null
          ? '${currentIndex + 1}/$_kStepCount'
          : '$activeStepLabel (${currentIndex + 1}/$_kStepCount)',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  static _DotState _stateFor(int index, int currentIndex) {
    if (index < currentIndex) return _DotState.done;
    if (index == currentIndex) return _DotState.active;
    return _DotState.inactive;
  }
}

// ---------------------------------------------------------------------------
// Internal — dot column (fixed 22 dp width + 30 dp label slot)
// ---------------------------------------------------------------------------

enum _DotState { done, active, inactive }

class _ProgItem extends StatelessWidget {
  const _ProgItem({
    super.key,
    required this.number,
    required this.state,
    required this.activeLabel,
  });

  final int number;
  final _DotState state;

  /// Non-null only when this column is the active dot AND the caller passed
  /// a label to [RegistrationProgress.activeStepLabel].
  final String? activeLabel;

  // ── Layout tokens ──────────────────────────────────────────────────────

  /// .prog-item { width: 22px } — fixed dot column width.
  static const double _kDotSize = 22;

  /// .prog-item { padding-bottom: 30px } — reserved vertical slot under the
  /// dot for the active label (kept constant so the dot row stays aligned
  /// across active/done/inactive columns).
  static const double _kLabelSlotHeight = 30;

  /// Negative left/right anchor applied to the `Positioned` active-label
  /// band so the label can overflow the 22 dp dot column symmetrically into
  /// neighbouring (empty) label slots. 110 dp per side → 242 dp wide band
  /// for the label text, which comfortably fits the widest Cyrillic label
  /// ("Верифікація", ~120 dp at 14 px Cormorant Garamond) and re-centres on
  /// the dot midline via the inner `Center`.
  static const double _kLabelOverflow = 110;

  // ── Pre-allocated decoration constants (HOIST §1) ──────────────────────

  /// .prog-item.done .prog-num { background: rgba(184,154,122,0.22) }.
  static const _kDoneCircle = BoxDecoration(
    color: Color(0x38B89A7A),
    shape: BoxShape.circle,
  );

  /// .prog-item.active .prog-num { background: var(--accent);
  ///                               box-shadow: 0 0 0 4px rgba(184,154,122,0.14) }.
  static const _kActiveCircle = BoxDecoration(
    color: BrandColors.accent,
    shape: BoxShape.circle,
    boxShadow: [
      BoxShadow(
        color: Color(0x24B89A7A), // rgba(184,154,122,0.14)
        spreadRadius: 4,
        blurRadius: 0,
      ),
    ],
  );

  /// .prog-item.inactive .prog-num { border: 1.5px solid rgba(255,255,255,0.15) }.
  static const _kInactiveCircle = BoxDecoration(
    shape: BoxShape.circle,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x26FFFFFF), width: 1.5),
    ),
  );

  /// .prog-item.active .prog-num { color: var(--prog-color) #3a2810 }.
  static const _kNumActive = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: Color(0xFF3A2810),
    height: 1,
  );

  /// .prog-item.inactive .prog-num { color: rgba(255,255,255,0.28) }.
  static const _kNumInactive = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: Color(0x47FFFFFF),
    height: 1,
  );

  @override
  Widget build(BuildContext context) {
    final decoration = switch (state) {
      _DotState.done => _kDoneCircle,
      _DotState.active => _kActiveCircle,
      _DotState.inactive => _kInactiveCircle,
    };

    final Widget circleChild = switch (state) {
      // Key is stamped per dot index so tests can positively assert
      // "dot N is in done state" without relying on absence of the digit.
      _DotState.done => _CheckGlyph(key: Key('progress-check-$number')),
      _DotState.active => Text('$number', style: _kNumActive),
      _DotState.inactive => Text('$number', style: _kNumInactive),
    };

    return SizedBox(
      // Fixed-width column — never flexes. Connectors take up the slack.
      width: _kDotSize,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Dot circle (also hosts the absolute label via Stack) ────────
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: _kDotSize,
                height: _kDotSize,
                child: DecoratedBox(
                  decoration: decoration,
                  child: Center(child: circleChild),
                ),
              ),
              if (activeLabel != null)
                // .prog-label-under: position:absolute; top:30px; left:50%;
                // transform:translateX(-50%); white-space:nowrap; overflow
                // allowed to extend into neighbouring (empty) label slots.
                //
                // Flutter implementation: a `Positioned` with negative `left`
                // and `right` anchors widens the label-bearing band to
                // [-_kLabelOverflow, _kDotSize + _kLabelOverflow] dp around
                // the 22 dp dot column — so the band is ~220 dp wide and the
                // Centered label inside it sits exactly over the dot mid-line
                // regardless of label length. The Stack uses
                // `clipBehavior: Clip.none` (above) so the overflow paints
                // visibly into neighbouring columns.
                Positioned(
                  top: _kDotSize + 8,
                  left: -_kLabelOverflow,
                  right: -_kLabelOverflow,
                  child: Center(child: _ActiveLabel(activeLabel!)),
                ),
            ],
          ),
          // Reserves the 30 dp vertical slot below the dot so every column
          // (done/active/inactive) has identical height — keeps the dot row
          // perfectly horizontal regardless of which column owns the label.
          const SizedBox(height: _kLabelSlotHeight),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal — active label (Cormorant Garamond italic, camel)
// ---------------------------------------------------------------------------

/// Active-step label rendered absolutely under the active dot.
///
/// Carries `Key('progress-active-label')` — tests assert this key resolves
/// exactly once on screens that pass a non-null [activeStepLabel] to
/// [RegistrationProgress].
class _ActiveLabel extends StatelessWidget {
  const _ActiveLabel(this.text);

  final String text;

  /// .prog-label-under {
  ///   font-family: 'Cormorant Garamond';
  ///   font-style: italic;
  ///   font-weight: 600;
  ///   font-size: 14px;
  ///   line-height: 1;
  ///   color: var(--accent) #b89a7a;
  ///   letter-spacing: 0.01em;
  /// }
  static final _kLabelStyle = GoogleFonts.cormorantGaramond(
    textStyle: const TextStyle(
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w600,
      fontSize: 14,
      color: BrandColors.accent,
      height: 1,
      letterSpacing: 0.14, // 0.01em × 14px
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      key: const Key('progress-active-label'),
      style: _kLabelStyle,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      textAlign: TextAlign.center,
    );
  }
}

// ---------------------------------------------------------------------------
// Internal — connector line between dots (1 px hairline)
// ---------------------------------------------------------------------------

class _ProgLine extends StatelessWidget {
  const _ProgLine({required this.done});

  final bool done;

  /// .prog-line.done { background: rgba(184,154,122,0.25) }.
  static const _kDoneColor = Color(0x40B89A7A);

  /// .prog-line { background: rgba(255,255,255,0.08) }.
  static const _kInactiveColor = Color(0x14FFFFFF);

  /// .prog-line { margin: 11px 4px 0 } — 11 dp top aligns the line on the
  /// vertical centre of the 22 dp dot; 4 dp horizontal margin between line
  /// and dot edge gives each connector room without crowding the dots.
  static const double _kVerticalOffset = 11;
  static const double _kSideMargin = 4;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kSideMargin),
        child: Column(
          children: [
            const SizedBox(height: _kVerticalOffset),
            ColoredBox(
              color: done ? _kDoneColor : _kInactiveColor,
              child: const SizedBox(height: 1, width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal — done-state checkmark glyph
// ---------------------------------------------------------------------------

/// Camel-tinted checkmark glyph rendered inside `.prog-item.done .prog-num`.
///
/// Path: M2 5.5 l2.5 2.5 4.5-4.5  (viewBox 11×11). Stroke-width 2, stroke
/// var(--accent) #b89a7a, fill none. Identical to the verification-page.html
/// design.
class _CheckGlyph extends StatelessWidget {
  const _CheckGlyph({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 10,
      height: 10,
      child: CustomPaint(painter: _CheckmarkPainter()),
    );
  }
}

class _CheckmarkPainter extends CustomPainter {
  const _CheckmarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BrandColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final sx = size.width / 11;
    final sy = size.height / 11;

    final path = Path()
      ..moveTo(2 * sx, 5.5 * sy)
      ..lineTo(4.5 * sx, 8 * sy)
      ..lineTo(9 * sx, 3.5 * sy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckmarkPainter oldDelegate) => false;
}
