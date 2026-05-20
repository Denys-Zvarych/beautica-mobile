// Phase 2.16 — Registration progress indicator (4 pills).
//
// SOURCE OF TRUTH: docs/signup-designs/sign-up-page.html (and the 5 other
// signup-design HTMLs, which share the IDENTICAL .progress-row block). The
// 2026-05-20 redesign tightened the sizing to fit four pills inside the
// 311-dp glass-card content area at 375 dp phone width:
//
//   .prog-item   { gap: 5px; font-size: 9px; letter-spacing: 0.05em }
//   .prog-num    { width: 20px; height: 20px; font-size: 9.5px }
//   .prog-line   { flex: 1; height: 1px; margin: 0 5px; min-width: 6px }
//   .progress-row{ margin-top: 28px }
//
// Pill state (per HTML CSS):
//   .prog-item.done      → label color rgba(255,255,255,0.45);
//                          .prog-num background rgba(184,154,122,0.22);
//                          number is replaced by a camel checkmark glyph.
//   .prog-item.active    → label color rgba(255,255,255,0.85);
//                          .prog-num background --accent #b89a7a;
//                          number font color --prog-color #3a2810.
//   .prog-item.inactive  → label color rgba(255,255,255,0.2);
//                          .prog-num border 1.5px rgba(255,255,255,0.15);
//                          number font color rgba(255,255,255,0.2).
//   .prog-line           → 1px rgba(255,255,255,0.08);
//   .prog-line.done      → 1px rgba(184,154,122,0.25).
//
// Five physical screens consume this widget — Step 1 / Step 2 / Step 3 /
// Verification / Done — and the active pill changes per screen.

import 'package:flutter/material.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Current step in the registration wizard.
///
/// Pills to the LEFT of [currentStep] are rendered as `.done`, the current
/// step as `.active`, and pills to the RIGHT as `.inactive`.
enum RegistrationStep {
  /// `/register` — credentials (email + password + confirm).
  account,

  /// `/register/step-2` — profile (name + phone).
  details,

  /// `/verification` — OTP entry.
  verification,

  /// `/done` — terminal screen. All preceding pills are `.done`, this pill
  /// itself is rendered `.active` (the design has no all-done state — the
  /// final screen is the active step until the user leaves the wizard).
  done,
}

/// Renders the 4-pill progress row used on every registration-flow screen.
class RegistrationProgress extends StatelessWidget {
  const RegistrationProgress({super.key, required this.currentStep});

  final RegistrationStep currentStep;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentIndex = currentStep.index;
    final labels = <String>[
      l10n.progressStepAccount,
      l10n.progressStepDetailsLabel,
      l10n.progressStepVerificationLabel,
      l10n.progressStepDoneLabel,
    ];

    final children = <Widget>[];
    for (var i = 0; i < RegistrationStep.values.length; i++) {
      children.add(
        _ProgItem(
          number: i + 1,
          label: labels[i],
          state: _stateFor(i, currentIndex),
        ),
      );
      if (i < RegistrationStep.values.length - 1) {
        children.add(_ProgLine(done: i < currentIndex));
      }
    }

    return Semantics(
      container: true,
      label:
          '${labels[currentIndex]} '
          '(${currentIndex + 1}/${RegistrationStep.values.length})',
      excludeSemantics: true,
      child: Row(children: children),
    );
  }

  static _PillState _stateFor(int index, int currentIndex) {
    if (index < currentIndex) return _PillState.done;
    if (index == currentIndex) return _PillState.active;
    return _PillState.inactive;
  }
}

// ---------------------------------------------------------------------------
// Internal — pill (number circle + label)
// ---------------------------------------------------------------------------

enum _PillState { done, active, inactive }

class _ProgItem extends StatelessWidget {
  const _ProgItem({
    required this.number,
    required this.label,
    required this.state,
  });

  final int number;
  final String label;
  final _PillState state;

  // ── Pre-allocated style constants (HOIST §1) ───────────────────────────

  /// .prog-item.done .prog-num { background: rgba(184,154,122,0.22) }
  static const _kDoneCircle = BoxDecoration(
    color: Color(0x38B89A7A),
    shape: BoxShape.circle,
  );

  /// .prog-item.active .prog-num { background: var(--accent) }
  static const _kActiveCircle = BoxDecoration(
    color: BrandColors.camel,
    shape: BoxShape.circle,
  );

  /// .prog-item.inactive .prog-num { border: 1.5px solid rgba(255,255,255,0.15) }
  static const _kInactiveCircle = BoxDecoration(
    shape: BoxShape.circle,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x26FFFFFF), width: 1.5),
    ),
  );

  // Per-state label colours.
  // .prog-item { font-size: 9px; font-weight: 700; letter-spacing: 0.05em }.
  static const _kLabelDone = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.45, // 0.05em × 9px
    color: Color(0x73FFFFFF), // rgba(255,255,255,0.45)
  );
  static const _kLabelActive = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.45,
    color: Color(0xD9FFFFFF), // rgba(255,255,255,0.85)
  );
  static const _kLabelInactive = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.45,
    color: Color(0x33FFFFFF), // rgba(255,255,255,0.20)
  );

  // Per-state number colours.
  // .prog-num { font-size: 9.5px; font-weight: 700 }.
  static const _kNumActive = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w700,
    color: Color(0xFF3A2810), // var(--prog-color)
  );
  static const _kNumInactive = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w700,
    color: Color(0x33FFFFFF), // rgba(255,255,255,0.20)
  );

  @override
  Widget build(BuildContext context) {
    final (BoxDecoration decoration, TextStyle labelStyle) = switch (state) {
      _PillState.done => (_kDoneCircle, _kLabelDone),
      _PillState.active => (_kActiveCircle, _kLabelActive),
      _PillState.inactive => (_kInactiveCircle, _kLabelInactive),
    };

    final Widget circleChild = switch (state) {
      // Key is stamped per pill index so tests can assert "pill N is done"
      // positively, without relying on absence of the number digit.
      _PillState.done => _CheckGlyph(key: Key('progress-check-$number')),
      _PillState.active => Text('$number', style: _kNumActive),
      _PillState.inactive => Text('$number', style: _kNumInactive),
    };

    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // .prog-num { width: 20px; height: 20px; border-radius: 50% }
          SizedBox(
            width: 20,
            height: 20,
            child: DecoratedBox(
              decoration: decoration,
              child: Center(child: circleChild),
            ),
          ),
          // .prog-item { gap: 5px }
          const SizedBox(width: 5),
          // .prog-item { white-space: nowrap; text-transform: uppercase }.
          // Flexible + overflow.fade lets the row degrade gracefully when
          // the Roboto fallback (test-time) renders Cyrillic glyphs wider
          // than the Manrope-on-device design measurements.
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: labelStyle,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal — connector line between pills
// ---------------------------------------------------------------------------

class _ProgLine extends StatelessWidget {
  const _ProgLine({required this.done});

  final bool done;

  /// .prog-line.done { background: rgba(184,154,122,0.25) }
  static const _kDoneColor = Color(0x40B89A7A);

  /// .prog-line { background: rgba(255,255,255,0.08) }
  static const _kInactiveColor = Color(0x14FFFFFF);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ConstrainedBox(
        // .prog-line { min-width: 6px }
        constraints: const BoxConstraints(minWidth: 6, minHeight: 1),
        child: Padding(
          // .prog-line { margin: 0 5px }
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: ColoredBox(
            color: done ? _kDoneColor : _kInactiveColor,
            child: const SizedBox(height: 1, width: double.infinity),
          ),
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
/// var(--accent), fill none. Identical to the verification-page.html design.
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
      ..color = BrandColors.camel
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
