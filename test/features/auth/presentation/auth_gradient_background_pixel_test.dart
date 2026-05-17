// Pixel-level acceptance gate for AuthGradientBackground — Bayer-4×4 dither.
//
// History:
//   LinearGradient model (iteration 5): L1–L4 proved no ring/disc. However
//   8-bit quantization banding (runs up to 54 px wide) was not tested.
//   Dithered model (iteration 6, this file): same L1–L4 retained with a ±2
//   tolerance for the ±1.77 LSB dither noise. Added:
//     L5 — no banding: longest identical-value run ≤ 4 px per channel.
//     L6 — dither present: ≥ 2 distinct values in every 8-px window.
//
// A golden test is self-referential (regenerating it resets the baseline) and
// cannot prove "smooth gradient, no banding". This file renders the real
// widget, reads raw RGBA bytes, and asserts STRUCTURAL properties that banding
// or a ring/disc would necessarily violate.
//
// All channel assertions use AVERAGED (smoothed) trends for L1–L3, because
// dithering adds ±1.77 LSB noise that can flip a raw adjacent pair — the
// smoothed signal is what matters perceptually.
//
// Scheduling: the widget uses a synchronous PictureRecorder in CustomPainter.
// paint() — captureImage drives paint() directly, no async needed.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:beautica_mobile/features/auth/presentation/auth_gradient_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: avoid_print

void main() {
  // Fixed logical-pixel surface matching the golden dimensions.
  // 1× DPR → physical = logical (simple byte offsets, no upscale).
  const testWidth = 390.0;
  const testHeight = 844.0;

  // Espresso (#0D0906) red = 0x0D = 13.
  const espressoRed = 13;
  // Dither tolerance: ±1.77 LSB noise → use ±2 for smoothed comparisons.
  const tol = 2;

  /// Render [AuthGradientBackground] at [testWidth]×[testHeight] and capture
  /// raw RGBA bytes. The widget uses a synchronous [CustomPainter] backed by
  /// [ui.PictureRecorder], so [captureImage] drives [paint()] directly —
  /// no [tester.runAsync] needed.
  Future<({Uint8List rgba, int w, int h})> captureBytes(
    WidgetTester tester,
  ) async {
    ditherPictureCache.clear();

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

    // Pump: LayoutBuilder resolves constraints → CustomPainter.paint() is
    // called synchronously, building and caching the dithered Picture.
    await tester.pump();

    expect(
      find.byType(CustomPaint),
      findsWidgets,
      reason:
          'CustomPaint must be in the widget tree after layout resolves '
          '(AuthGradientBackground should not be stuck in the ColoredBox fallback).',
    );

    final image = await captureImage(repaintKey.currentContext! as Element);
    final byteData = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(byteData, isNotNull, reason: 'toByteData must return data');

    return (
      rgba: byteData!.buffer.asUint8List(),
      w: image.width,
      h: image.height,
    );
  }

  testWidgets('L1–L6: dithered gradient is smooth, warm-dark, no banding', (
    tester,
  ) async {
    final (:rgba, :w, :h) = await captureBytes(tester);

    // Channel accessors (RGBA row-major).
    int rAt(int x, int y) => rgba[(y * w + x) * 4];
    int gAt(int x, int y) => rgba[(y * w + x) * 4 + 1];
    int bAt(int x, int y) => rgba[(y * w + x) * 4 + 2];

    // -----------------------------------------------------------------------
    // Smoothed-axis helper.
    // Averages a 5×5 neighbourhood to suppress ±1.77 LSB dither noise before
    // testing the monotone trend.
    // -----------------------------------------------------------------------
    double smoothedR(int x, int y) {
      var sum = 0;
      var count = 0;
      for (final dx in [-2, -1, 0, 1, 2]) {
        for (final dy in [-2, -1, 0, 1, 2]) {
          final nx = (x + dx).clamp(0, w - 1);
          final ny = (y + dy).clamp(0, h - 1);
          sum += rAt(nx, ny);
          count++;
        }
      }
      return sum / count;
    }

    // -----------------------------------------------------------------------
    // L1 — smoothed red is MONOTONICALLY NON-INCREASING along TL→BR diagonal
    //      (warm #3A2615 corner → espresso #0D0906 corner).
    // -----------------------------------------------------------------------
    const n = 9; // 9 samples → 7 interior points
    int diagX(int i) => ((w - 1) * i / (n - 1)).round();
    int diagY(int i) => ((h - 1) * i / (n - 1)).round();
    final axisSmoothed = [
      for (var i = 0; i < n; i++) smoothedR(diagX(i), diagY(i)),
    ];

    for (var i = 0; i < axisSmoothed.length - 1; i++) {
      expect(
        axisSmoothed[i + 1],
        lessThanOrEqualTo(axisSmoothed[i] + tol),
        reason:
            'L1: smoothed red along TL→BR diagonal must be non-increasing; '
            'sample[$i]=${axisSmoothed[i].toStringAsFixed(1)} '
            'sample[${i + 1}]=${axisSmoothed[i + 1].toStringAsFixed(1)} '
            '(full smoothed axis = '
            '${axisSmoothed.map((v) => v.toStringAsFixed(1)).toList()}). '
            'A rise indicates a ring/disc or wrong gradient direction.',
      );
    }

    // -----------------------------------------------------------------------
    // L2 — no interior local MAXIMUM on the smoothed axis.
    // -----------------------------------------------------------------------
    for (var i = 1; i < axisSmoothed.length - 1; i++) {
      final isStrictPeak =
          axisSmoothed[i] > axisSmoothed[i - 1] + tol &&
          axisSmoothed[i] > axisSmoothed[i + 1] + tol;
      expect(
        isStrictPeak,
        isFalse,
        reason:
            'L2: interior axis point $i '
            '(=${axisSmoothed[i].toStringAsFixed(1)}) is a strict peak vs '
            'neighbours (${axisSmoothed[i - 1].toStringAsFixed(1)}, '
            '${axisSmoothed[i + 1].toStringAsFixed(1)}) — signature of a '
            'ring/disc. Full axis = '
            '${axisSmoothed.map((v) => v.toStringAsFixed(1)).toList()}.',
      );
    }

    // -----------------------------------------------------------------------
    // L3 — perpendicular to the gradient axis, smoothed red is ~CONSTANT.
    //
    // Gradient direction for t = (x/W + y/H)*0.5 is proportional to (H, W).
    // The iso-colour direction (perpendicular to gradient) is (−W, H)/norm.
    // -----------------------------------------------------------------------
    final cx = w / 2.0;
    final cy = h / 2.0;
    final len = math.sqrt(w * w + h * h);
    final ux = -w / len;
    final uy = h / len;

    var maxS = double.infinity;
    for (final s in [
      ux > 0 ? (w - 1 - cx) / ux : (ux < 0 ? -cx / ux : double.infinity),
      uy > 0 ? (h - 1 - cy) / uy : (uy < 0 ? -cy / uy : double.infinity),
    ]) {
      if (s.abs() < maxS) maxS = s.abs();
    }

    final perpSmoothed = <double>[];
    for (var k = -3; k <= 3; k++) {
      final s = maxS * k / 3.0;
      final x = (cx + ux * s).round().clamp(0, w - 1);
      final y = (cy + uy * s).round().clamp(0, h - 1);
      perpSmoothed.add(smoothedR(x, y));
    }
    final perpMin = perpSmoothed.reduce((a, b) => a < b ? a : b);
    final perpMax = perpSmoothed.reduce((a, b) => a > b ? a : b);
    expect(
      perpMax - perpMin,
      lessThanOrEqualTo(2 * tol),
      reason:
          'L3: smoothed red must be ~constant along the iso-colour line '
          '(perpendicular to TL→BR); '
          'spread=${(perpMax - perpMin).toStringAsFixed(1)} '
          'smoothed=${perpSmoothed.map((v) => v.toStringAsFixed(1)).toList()}. '
          'A large spread indicates a blob/disc.',
    );

    // -----------------------------------------------------------------------
    // L4 — visibly warm but dark.
    //   (a) Warm corner red > espresso red + 10.
    //   (b) All sampled pixels stay dark (R < 90) and warm-toned (R≥G≥B).
    //   (c) Bottom-right corner red ≈ espresso.
    // -----------------------------------------------------------------------
    final warmCornerR = rAt(2, 2);
    final darkCornerR = rAt(w - 3, h - 3);

    expect(
      warmCornerR,
      greaterThan(espressoRed + 10),
      reason:
          'L4a: warm corner red=$warmCornerR must be clearly above espresso '
          '($espressoRed) — the wash must read warm.',
    );
    expect(
      warmCornerR,
      lessThan(90),
      reason:
          'L4b: warm corner red=$warmCornerR must stay dark (< 90, far below '
          'cream 245).',
    );

    var globalMaxR = 0;
    for (var y = 0; y < h; y += 37) {
      for (var x = 0; x < w; x += 37) {
        final r = rAt(x, y);
        final g = gAt(x, y);
        final b = bAt(x, y);
        if (r > globalMaxR) globalMaxR = r;
        expect(
          r,
          lessThan(90),
          reason: 'L4b: pixel ($x,$y) red=$r must stay dark (< 90).',
        );
        expect(
          r >= g - tol && g >= b - tol,
          isTrue,
          reason:
              'L4b: pixel ($x,$y) must be warm-toned (R≥G≥B); '
              'got R=$r G=$g B=$b.',
        );
      }
    }
    expect(
      darkCornerR,
      lessThanOrEqualTo(espressoRed + tol),
      reason:
          'L4c: bottom-right corner red=$darkCornerR must settle to espresso '
          '(≈ $espressoRed).',
    );

    // -----------------------------------------------------------------------
    // L5 — NO BANDING: longest run of an identical channel value along the
    //      centre column must be ≤ 4 px.
    //
    // With Bayer-4×4 dither at ±1.77 LSB (divisor 72), the longest identical
    // run across all column alignments is ≤ 3 px (verified analytically).
    // -----------------------------------------------------------------------
    final centerX = w ~/ 2;
    int longestRunR = 1, curRunR = 1;
    int longestRunG = 1, curRunG = 1;
    int longestRunB = 1, curRunB = 1;

    for (var y = 1; y < h; y++) {
      if (rAt(centerX, y) == rAt(centerX, y - 1)) {
        curRunR++;
        if (curRunR > longestRunR) longestRunR = curRunR;
      } else {
        curRunR = 1;
      }
      if (gAt(centerX, y) == gAt(centerX, y - 1)) {
        curRunG++;
        if (curRunG > longestRunG) longestRunG = curRunG;
      } else {
        curRunG = 1;
      }
      if (bAt(centerX, y) == bAt(centerX, y - 1)) {
        curRunB++;
        if (curRunB > longestRunB) longestRunB = curRunB;
      } else {
        curRunB = 1;
      }
    }

    expect(
      longestRunR,
      lessThanOrEqualTo(4),
      reason:
          'L5 red: longest identical-value run along center column '
          '= $longestRunR px (must be ≤ 4). '
          'A run > 4 means visible banding.',
    );
    expect(
      longestRunG,
      lessThanOrEqualTo(4),
      reason:
          'L5 green: longest identical-value run = $longestRunG px '
          '(must be ≤ 4).',
    );
    expect(
      longestRunB,
      lessThanOrEqualTo(4),
      reason:
          'L5 blue: longest identical-value run = $longestRunB px '
          '(must be ≤ 4).',
    );

    // -----------------------------------------------------------------------
    // L6 — DITHER PRESENT: in every non-overlapping 8-px window down the
    //      centre column, ≥ 2 distinct red values appear.
    //
    // With ±1.77 LSB dither, every 8-row window on the centre column spans
    // 2 full Bayer periods (period = 4 rows) → always ≥ 2 distinct levels.
    // Allow < 10% of windows to have only 1 level (gradient endpoints).
    // -----------------------------------------------------------------------
    const windowSize = 8;
    final numWindows = h ~/ windowSize;
    var windowsWithSingleValue = 0;

    for (var w8 = 0; w8 < numWindows; w8++) {
      final startY = w8 * windowSize;
      final distinctReds = <int>{};
      for (var dy = 0; dy < windowSize; dy++) {
        distinctReds.add(rAt(centerX, startY + dy));
      }
      if (distinctReds.length < 2) windowsWithSingleValue++;
    }

    final failRate = windowsWithSingleValue / numWindows;
    expect(
      failRate,
      lessThan(0.10),
      reason:
          'L6: $windowsWithSingleValue/$numWindows 8-px windows on the '
          'center column had only 1 distinct red value '
          '(fail rate ${(failRate * 100).toStringAsFixed(1)}% ≥ 10%). '
          'Dithering must produce ≥ 2 distinct values per 8-px window in '
          'at least 90% of windows.',
    );

    // -----------------------------------------------------------------------
    // Always-print pass report (per task requirement).
    // -----------------------------------------------------------------------
    print(
      '\nDithered gradient PASS report (image ${w}x$h):\n'
      '  L5 longest run  R=$longestRunR  G=$longestRunG  B=$longestRunB  '
      '(all ≤ 4)\n'
      '  L6 single-value windows = $windowsWithSingleValue/$numWindows '
      '(${(failRate * 100).toStringAsFixed(1)}% < 10%)\n'
      '  L1 smoothed axis = '
      '${axisSmoothed.map((v) => v.toStringAsFixed(1)).toList()}\n'
      '  L4a warmCornerR=$warmCornerR  L4c darkCornerR=$darkCornerR\n',
    );

    // -----------------------------------------------------------------------
    // Diagnostic report (on failure only).
    // -----------------------------------------------------------------------
    printOnFailure(
      'Dithered gradient pixel report (image ${w}x$h):\n'
      '  L1/L2 smoothed axis reds (TL→BR)  = '
      '${axisSmoothed.map((v) => v.toStringAsFixed(1)).toList()}\n'
      '  L3 iso-colour smoothed reds        = '
      '${perpSmoothed.map((v) => v.toStringAsFixed(1)).toList()} '
      '(spread ${(perpMax - perpMin).toStringAsFixed(1)} ≤ ${2 * tol})\n'
      '  L4a warm corner (2,2) R            = $warmCornerR  '
      '(> ${espressoRed + 10})\n'
      '  L4c dark corner (w-3,h-3) R        = $darkCornerR  '
      '(≤ ${espressoRed + tol})\n'
      '  L4b global max sampled R           = $globalMaxR  (< 90)\n'
      '  L5 longest identical run R/G/B     = '
      '$longestRunR / $longestRunG / $longestRunB  (≤ 4)\n'
      '  L6 windows with 1 distinct red     = '
      '$windowsWithSingleValue/$numWindows  (< 10%)\n',
    );
  });
}
