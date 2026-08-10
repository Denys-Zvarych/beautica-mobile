// WCAG contrast guard for `HubFilledButton`'s CTA gradient
// (`lib/features/home/presentation/widgets/hub_widgets.dart`).
//
// WHY THIS FILE EXISTS
// ---------------------
// mobile-security finding (LOW, in-diff on the CTA button change): the
// button's label (`VelvetText.cta135` — Comfortaa 11sp/w700, cream
// `#F5EDE0`) is ORDINARY text under WCAG — nowhere near the 14pt-bold "large
// text" floor — so its threshold is 4.5:1, not 3:1. The gradient fill
// (`BrandColors.accentLatte` → `BrandColors.accentDeep`) was diagonal
// (`Alignment.topLeft` → `bottomRight`), which put the lightest (lowest-
// contrast) end of the gradient closest to the label's own leading edge on a
// natural-width button (no slack between text and padding) — measured
// against `accentLatte` alone: 4.37:1, sub-AA.
//
// THE FIX
// -------
// Switched the gradient to VERTICAL (`topCenter` → `bottomCenter`) with
// `stops: [0.0, 0.6]`. Vertical decouples contrast from the label's
// HORIZONTAL position — every label, whatever its width, sees the same
// vertical slice of the gradient, so a single measurement covers every
// caller rather than needing to be re-verified per label length. The stop
// bias then pushes the transition far enough up that the label's own
// bounding box — vertically centred, so it starts at whatever y the font's
// ascent puts it at — never sits closer to `accentLatte` than the gradient's
// OWN unbiased midpoint would.
//
// WHAT THIS FILE PROVES
// ----------------------
// For BOTH of the button's current real callers' labels («Записатись» —
// `wishlistBookCta` — and «Обрати майстра» — `wishlistChooseMasterCta`, see
// `wishlist_entry_labels.dart`), sampling the gradient at the actual
// RENDERED bounding box of the label (not a guessed position — measured via
// `tester.getRect` against the real `Text`) never dips below AA (4.5:1), and
// in fact never dips below the gradient's own midpoint contrast (~5.47:1) —
// which is the exact property the fix was designed to guarantee, restated
// as a test rather than left as a comment's claim.
//
// The gradient sampled is NOT a hand-mirrored copy of the private
// `_HubFilledButtonState._decoration` — it is pulled straight off the
// `Container` the widget actually paints (`tester.widget<Container>(...)`,
// scoped to a descendant of `HubFilledButton`), via `_renderedGradient`.
// That is deliberate: a mirrored `const LinearGradient` in this file would
// only ever prove the INTENDED gradient clears AA, never that the SHIPPED
// one does — a change to `_decoration`'s colours, direction, or stops would
// silently desync from a copy and this test would keep passing regardless.
// Reading the rendered `Container` closes that gap: it verifies what is
// genuinely painted, so a colour or stop change to `_decoration` changes
// what `_renderedGradient` returns and is caught here without a golden
// image diff. The sampling math (`_gradientColorAt`) replicates `dart:ui`'s
// own linear-gradient projection (project the point onto the begin→end
// line, clamp to [0,1], then walk the [stops] piecewise) rather than
// rendering to a real pixel buffer — this is the SAME algorithm the engine
// runs, just evaluated in Dart against that rendered `LinearGradient`.
//
// Layer: Widget + pure-Dart colour math. No providers — `HubFilledButton` is
// a `StatefulWidget` with no Riverpod dependency.

import 'dart:math' as math;

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/hub_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// WCAG 2.x relative luminance + contrast ratio — textbook formula, no
// existing shared helper in this repo (checked: neither
// `test/core/theme/typography_test.dart` nor `lib/core/theme/brand_colors.dart`
// expose one), so it is self-contained here rather than invented a shared
// location for a single consumer.
// ---------------------------------------------------------------------------

double _linearise(double channel255) {
  final double c = channel255 / 255.0;
  if (c <= 0.03928) return c / 12.92;
  return math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _relativeLuminance(Color c) {
  final double r = _linearise(c.r * 255);
  final double g = _linearise(c.g * 255);
  final double b = _linearise(c.b * 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// WCAG contrast ratio between two colours, always >= 1.0.
double _contrastRatio(Color a, Color b) {
  final double la = _relativeLuminance(a);
  final double lb = _relativeLuminance(b);
  final double lighter = math.max(la, lb);
  final double darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Replicates `dart:ui`'s linear-gradient colour-at-point projection: project
/// [point] (in the gradient's own local coordinate space, i.e. relative to
/// [size]) onto the begin→end line, clamp to [0,1], then resolve through
/// [gradient.stops] exactly as the engine's piecewise-linear stop walk does.
Color _gradientColorAt(LinearGradient gradient, Offset point, Size size) {
  final Rect rect = Rect.fromLTWH(0, 0, size.width, size.height);
  final Offset begin = gradient.begin
      .resolve(TextDirection.ltr)
      .withinRect(rect);
  final Offset end = gradient.end.resolve(TextDirection.ltr).withinRect(rect);
  final Offset dir = end - begin;
  final double lenSq = dir.dx * dir.dx + dir.dy * dir.dy;
  final Offset rel = point - begin;
  double t = (rel.dx * dir.dx + rel.dy * dir.dy) / lenSq;
  t = t.clamp(0.0, 1.0);

  final List<double> stops = gradient.stops ?? <double>[0.0, 1.0];
  final double s0 = stops.first;
  final double s1 = stops.last;
  if (t <= s0) return gradient.colors.first;
  if (t >= s1) return gradient.colors.last;
  final double frac = (t - s0) / (s1 - s0);
  return Color.lerp(gradient.colors[0], gradient.colors[1], frac)!;
}

/// Reads the [LinearGradient] `HubFilledButton` actually paints, straight off
/// the rendered `Container` — NOT a hand-mirrored copy of the private
/// `_HubFilledButtonState._decoration`. `HubFilledButton`'s build method
/// contains exactly one `Container` (the decorated pill itself; the loading
/// spinner is a bare `SizedBox`, the label a bare `FittedBox`+`Text`), so
/// scoping to a descendant of `HubFilledButton` finds it uniquely.
LinearGradient _renderedGradient(WidgetTester tester) {
  final Container container = tester.widget<Container>(
    find.descendant(
      of: find.byType(HubFilledButton),
      matching: find.byType(Container),
    ),
  );
  final BoxDecoration decoration = container.decoration! as BoxDecoration;
  return decoration.gradient! as LinearGradient;
}

/// The gradient's own unbiased midpoint colour (t = 0.5 with NO stop bias),
/// derived from the SAME two colours the rendered gradient actually uses —
/// the floor the fix promises no part of the label ever sits below.
Color _unbiasedMidpoint(LinearGradient gradient) =>
    Color.lerp(gradient.colors.first, gradient.colors.last, 0.5)!;

const double _kWcagAaNormalText = 4.5;

void main() {
  for (final String label in <String>[
    'Записатись', // i18n-const-ok: mirrors wishlistBookCta verbatim (data
    // fixture, not routed through AppLocalizations — see the no_raw_ui_
    // strings lint's own test-file exemption).
    'Обрати майстра', // i18n-const-ok: mirrors wishlistChooseMasterCta.
  ]) {
    group('label «$label»', () {
      testWidgets(
        'the gradient under the label never dips below WCAG AA (4.5:1)',
        (tester) async {
          await tester.pumpApp(
            Center(
              child: IntrinsicWidth(
                child: HubFilledButton(label: label, onTap: () {}),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final LinearGradient renderedGradient = _renderedGradient(tester);
          final Rect buttonRect = tester.getRect(find.byType(HubFilledButton));
          final Rect labelRect = tester.getRect(find.text(label));
          final Rect localLabelRect = labelRect.shift(-buttonRect.topLeft);
          final Size buttonSize = buttonRect.size;

          double worst = double.infinity;
          for (final Offset corner in <Offset>[
            localLabelRect.topLeft,
            localLabelRect.topRight,
            localLabelRect.bottomLeft,
            localLabelRect.bottomRight,
          ]) {
            final Color sampled = _gradientColorAt(
              renderedGradient,
              corner,
              buttonSize,
            );
            final double ratio = _contrastRatio(BrandColors.white, sampled);
            worst = math.min(worst, ratio);
          }

          expect(
            worst,
            greaterThanOrEqualTo(_kWcagAaNormalText),
            reason:
                'the label ($label) is normal-weight-scale text under WCAG '
                '(11sp/w700 clears neither the 18pt nor the 14pt-bold "large '
                'text" floor), so its threshold is 4.5:1 — worst measured '
                'was $worst',
          );
        },
      );

      testWidgets(
        'the gradient under the label never sits closer to accentLatte '
        'than the gradient\'s own unbiased midpoint',
        (tester) async {
          // The exact property the fix set out to guarantee, restated as an
          // assertion: "no part of the label's bounding box sits closer
          // than the midpoint to the latte end." Comfortably true — the
          // measured worst case is ~5.64:1, both above AA (4.5:1) AND above
          // the unbiased midpoint (~5.47:1).
          await tester.pumpApp(
            Center(
              child: IntrinsicWidth(
                child: HubFilledButton(label: label, onTap: () {}),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final LinearGradient renderedGradient = _renderedGradient(tester);
          final Rect buttonRect = tester.getRect(find.byType(HubFilledButton));
          final Rect labelRect = tester.getRect(find.text(label));
          final Rect localLabelRect = labelRect.shift(-buttonRect.topLeft);
          final Size buttonSize = buttonRect.size;

          final double midpointContrast = _contrastRatio(
            BrandColors.white,
            _unbiasedMidpoint(renderedGradient),
          );

          double worst = double.infinity;
          for (final Offset corner in <Offset>[
            localLabelRect.topLeft,
            localLabelRect.topRight,
            localLabelRect.bottomLeft,
            localLabelRect.bottomRight,
          ]) {
            final Color sampled = _gradientColorAt(
              renderedGradient,
              corner,
              buttonSize,
            );
            final double ratio = _contrastRatio(BrandColors.white, sampled);
            worst = math.min(worst, ratio);
          }

          expect(
            worst,
            greaterThanOrEqualTo(midpointContrast),
            reason:
                'unbiased midpoint contrast is $midpointContrast; the '
                'worst point under the label ($label) measured $worst — if '
                'this regresses below the midpoint, the stop bias no '
                'longer covers the label\'s actual rendered position',
          );
        },
      );
    });
  }
}
