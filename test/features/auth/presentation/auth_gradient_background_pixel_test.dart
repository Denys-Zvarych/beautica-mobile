// Pixel-level acceptance gate for AuthGradientBackground — LinearGradient model.
//
// History: the widget previously drew two RadialGradient "blob" shaders. On
// real devices those ALWAYS rendered as a visible ring/disc. The radial model
// is abandoned. The widget is now ONE full-bleed LinearGradient running the
// top-left → bottom-right diagonal (Warm Mocha: #3A2615 → #2A1A0E → #1C1109 →
// espresso #0D0906).
//
// A golden test is self-referential (regenerating it resets the baseline) and
// cannot, on its own, prove "smooth linear gradient, no ring/disc". This file
// renders the real widget, reads raw RGBA bytes, and asserts STRUCTURAL
// properties that a ring/disc would necessarily violate:
//
//   L1 — Along the gradient axis (TL→BR diagonal) the red channel is
//        MONOTONICALLY NON-INCREASING end to end (warm corner → espresso).
//   L2 — NO interior local maximum on that axis. A ring/disc brightens then
//        darkens somewhere; a linear ramp never does. No sampled interior
//        point may be a strict peak vs BOTH neighbours beyond tolerance.
//   L3 — Perpendicular to the gradient axis (the anti-diagonal, constant
//        x+y), red is approximately CONSTANT — proving a directional wash,
//        not a localized blob.
//   L4 — Warm but dark: the warm corner's red is meaningfully above espresso
//        red, AND no pixel anywhere approaches a bright/cream level.
//
// All assertions use a ±1 rounding tolerance for byte quantisation. Values are
// reported on failure for diagnosability. Assertions are NOT weakened to pass.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:beautica_mobile/features/auth/presentation/auth_gradient_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fixed logical-pixel surface that matches the golden test dimensions.
  // 1× device-pixel ratio keeps physical = logical, so byte offsets are simple.
  const testWidth = 390.0;
  const testHeight = 844.0;

  // Espresso (#0D0906) red channel = 0x0D = 13 — the gradient's darkest stop.
  const espressoRed = 13;
  // Restrained mocha (#3A2615) red channel = 0x3A = 58 — the warm stop.
  const warmRed = 58;
  // Byte-quantisation tolerance for "monotonic / constant" comparisons.
  const tol = 1;

  testWidgets('L1–L4: linear gradient is a smooth warm-dark wash, no ring', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(testWidth, testHeight));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repaintKey = GlobalKey();

    await tester.pumpWidget(
      RepaintBoundary(
        key: repaintKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(),
          home: const Scaffold(body: AuthGradientBackground()),
        ),
      ),
    );

    await tester.pump(); // ensure first frame is flushed

    final element = repaintKey.currentContext!;
    final image = await captureImage(element as Element);
    final byteData = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(byteData, isNotNull, reason: 'toByteData must return data');

    final rgba = byteData!.buffer.asUint8List();
    final w = image.width;
    final h = image.height;

    // Red / green / blue channel accessors. Bytes are [R,G,B,A] row-major.
    int rAt(int x, int y) => rgba[(y * w + x) * 4];
    int gAt(int x, int y) => rgba[(y * w + x) * 4 + 1];
    int bAt(int x, int y) => rgba[(y * w + x) * 4 + 2];

    // The gradient axis is the TL→BR diagonal. Sample N points evenly along
    // the main diagonal from (0,0) → (w-1, h-1).
    const n = 7; // 7 points → 5 interior points for the peak test
    int diagX(int i) => ((w - 1) * i / (n - 1)).round();
    int diagY(int i) => ((h - 1) * i / (n - 1)).round();
    final axisReds = [for (var i = 0; i < n; i++) rAt(diagX(i), diagY(i))];

    // -----------------------------------------------------------------------
    // L1 — red is monotonically NON-INCREASING along TL→BR (warm → espresso).
    // -----------------------------------------------------------------------
    for (var i = 0; i < axisReds.length - 1; i++) {
      expect(
        axisReds[i + 1],
        lessThanOrEqualTo(axisReds[i] + tol),
        reason:
            'L1: along TL→BR diagonal red must be non-increasing; '
            'sample[$i]=${axisReds[i]} sample[${i + 1}]=${axisReds[i + 1]} '
            '(full axis = $axisReds). A rise here means a ring/disc.',
      );
    }

    // -----------------------------------------------------------------------
    // L2 — no interior local MAXIMUM on the axis. A ring/disc creates a
    //      brighten-then-darken bump; a linear ramp cannot. An interior point
    //      that is strictly greater than BOTH neighbours (beyond tol) fails.
    // -----------------------------------------------------------------------
    for (var i = 1; i < axisReds.length - 1; i++) {
      final isStrictPeak =
          axisReds[i] > axisReds[i - 1] + tol &&
          axisReds[i] > axisReds[i + 1] + tol;
      expect(
        isStrictPeak,
        isFalse,
        reason:
            'L2: interior axis point $i (=${axisReds[i]}) is a strict peak vs '
            'neighbours (${axisReds[i - 1]}, ${axisReds[i + 1]}) — that is the '
            'signature of a ring/disc. Full axis = $axisReds.',
      );
    }

    // -----------------------------------------------------------------------
    // L3 — perpendicular to the gradient axis, red is approximately CONSTANT.
    //
    // For a LinearGradient(begin=topLeft, end=bottomRight) on a W×H rect,
    // Flutter projects every pixel onto the begin→end vector (W, H). The
    // colour parameter is t ∝ (x·W + y·H), so the TRUE iso-colour lines are
    // NOT the geometric 45° anti-diagonal (that only holds on a square) — they
    // are the lines where (x·W + y·H) is constant, i.e. the direction
    // (−H, W) (because (−H)·W + W·H = 0 keeps the projection fixed).
    //
    // We walk a centred segment along that exact iso-colour direction. On it a
    // directional wash is flat; a localized blob would still vary sharply.
    // -----------------------------------------------------------------------
    final cx = w / 2.0;
    final cy = h / 2.0;
    // Unit vector along the iso-colour line: (−H, W) normalised.
    final len = math.sqrt(w * w + h * h);
    final ux = -h / len;
    final uy = w / len;
    // Longest centred segment that stays on-canvas in BOTH directions.
    var maxS = double.infinity;
    for (final s in [
      ux > 0 ? (w - 1 - cx) / ux : (ux < 0 ? -cx / ux : double.infinity),
      uy > 0 ? (h - 1 - cy) / uy : (uy < 0 ? -cy / uy : double.infinity),
    ]) {
      if (s.abs() < maxS) maxS = s.abs();
    }
    final perpReds = <int>[];
    for (var k = -3; k <= 3; k++) {
      final s = maxS * k / 3.0;
      final x = (cx + ux * s).round().clamp(0, w - 1);
      final y = (cy + uy * s).round().clamp(0, h - 1);
      perpReds.add(rAt(x, y));
    }
    final perpMin = perpReds.reduce((a, b) => a < b ? a : b);
    final perpMax = perpReds.reduce((a, b) => a > b ? a : b);
    expect(
      perpMax - perpMin,
      lessThanOrEqualTo(2 * tol),
      reason:
          'L3: red must be ~constant along the gradient iso-colour line '
          '(perpendicular to the projected begin→end axis); '
          'spread=${perpMax - perpMin} reds=$perpReds. A spread here means '
          'the wash is localized (blob), not directional.',
    );

    // -----------------------------------------------------------------------
    // L4 — visibly warm but dark.
    //   (a) The warm (top-left) corner red is meaningfully above espresso red.
    //   (b) Every sampled pixel stays dark — red well below any cream/bright
    //       level (cream #F5EDE0 red = 245; cap generously at 90).
    //   (c) The far (bottom-right) corner has settled to ~espresso.
    // -----------------------------------------------------------------------
    final warmCornerRed = rAt(2, 2);
    final darkCornerRed = rAt(w - 3, h - 3);

    expect(
      warmCornerRed,
      greaterThan(espressoRed + 10),
      reason:
          'L4a: warm corner red=$warmCornerRed must be clearly above espresso '
          '($espressoRed) — the wash must read warm (target ≈ $warmRed).',
    );
    expect(
      warmCornerRed,
      lessThan(90),
      reason:
          'L4b: warm corner red=$warmCornerRed must stay dark (< 90, far below '
          'cream 245) — never a bright field.',
    );
    // Whole-image dark cap: scan a coarse grid, assert no pixel is bright and
    // every pixel is warm-or-neutral (R ≥ G ≥ B holds for the Warm Mocha ramp).
    var globalMaxRed = 0;
    for (var y = 0; y < h; y += 37) {
      for (var x = 0; x < w; x += 37) {
        final r = rAt(x, y);
        final g = gAt(x, y);
        final b = bAt(x, y);
        if (r > globalMaxRed) globalMaxRed = r;
        expect(
          r,
          lessThan(90),
          reason: 'L4b: pixel ($x,$y) red=$r must stay dark (< 90).',
        );
        expect(
          r >= g - tol && g >= b - tol,
          isTrue,
          reason:
              'L4b: pixel ($x,$y) must be warm-toned (R≥G≥B); got '
              'R=$r G=$g B=$b.',
        );
      }
    }
    expect(
      darkCornerRed,
      lessThanOrEqualTo(espressoRed + tol),
      reason:
          'L4c: bottom-right corner red=$darkCornerRed must settle to espresso '
          '(≈ $espressoRed) — the cool end of the wash.',
    );

    // Report sampled values for diagnosability even on pass.
    printOnFailure(
      'Linear gradient pixel report (image ${w}x$h):\n'
      '  L1/L2 axis reds (TL→BR)      = $axisReds  (non-increasing, no peak)\n'
      '  L3 anti-diagonal reds        = $perpReds  (spread ≤ ${2 * tol})\n'
      '  L4a warm corner (2,2) R      = $warmCornerRed  (> ${espressoRed + 10})\n'
      '  L4c dark corner  (w-3,h-3) R = $darkCornerRed  (≤ ${espressoRed + tol})\n'
      '  L4b global max sampled R     = $globalMaxRed  (< 90)\n',
    );
  });
}
