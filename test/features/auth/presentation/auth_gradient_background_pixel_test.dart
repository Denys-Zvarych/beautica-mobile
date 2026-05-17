// Pixel-level acceptance gate for AuthGradientBackground — Phase 2.x geometry fix.
//
// Rationale: a golden test is self-referential (regenerating it resets the
// baseline) and cannot detect the disc-vs-gradient regression on its own.
// This file renders the real widget, reads raw RGBA bytes, and asserts seven
// structural properties that prove the canvas shows a smooth directional
// gradient with no visible disc:
//
//   A1 — top-right corner is warm (blob 1 tail present)
//   A2 — top-left corner is cold (no bleed to the opposite corner)
//   A3 — at y=40, red is monotonically non-decreasing left→right (gradient, not disc)
//   A4 — at y=80, no sample pair 5px apart has a red delta > 4 (no sharp ring edge)
//   A5 — screen centre is near-espresso (no blob dominates the middle)
//   A6 — bottom-left area is warm (blob 2 tail present)
//   A7 — bottom-right corner is cold (no bleed to the opposite corner)

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:beautica_mobile/features/auth/presentation/auth_gradient_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fixed logical-pixel surface that matches the golden test dimensions.
  // 1× device-pixel ratio keeps physical = logical, so byte offsets are simple.
  const testWidth = 390.0;
  const testHeight = 844.0;

  late Uint8List rgba;
  late int w;
  late int h;

  // ---------------------------------------------------------------------------
  // The actual pixel gate — one testWidgets that renders + checks all 7 props.
  // ---------------------------------------------------------------------------
  testWidgets('A1–A7: pixel assertions prove smooth gradient, no disc', (
    tester,
  ) async {
    // Fix the surface to a deterministic size.
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

    // Capture the rendered image from the RepaintBoundary.
    final element = repaintKey.currentContext!;
    final image = await captureImage(element as Element);
    final byteData = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(byteData, isNotNull, reason: 'toByteData must return data');

    final bytes = byteData!.buffer.asUint8List();
    w = image.width;
    h = image.height;
    rgba = bytes;

    // rAt returns the red channel at logical pixel (x, y).
    // Bytes layout: [R, G, B, A] per pixel, row-major.
    int rAt(int x, int y) {
      final idx = (y * w + x) * 4;
      return rgba[idx];
    }

    // -----------------------------------------------------------------------
    // A1 — top-right corner red ≥ 28 (blob 1 tail must be visible).
    // Geometry: blob1 center = (w+30, -30), radius = 420.
    // At (w-5, 5), distance ≈ 49px → well inside the tail → warm red.
    // -----------------------------------------------------------------------
    final a1Red = rAt(w - 5, 5);
    expect(
      a1Red,
      greaterThanOrEqualTo(28),
      reason:
          'A1: top-right corner red=$a1Red must be ≥ 28 (blob1 tail present)',
    );

    // -----------------------------------------------------------------------
    // A2 — top-left corner red ≤ 16 (no bleed to the opposite corner).
    // Blob1 center is at (w+30, -30) — far from (5, 5). Red ≈ espresso (13).
    // -----------------------------------------------------------------------
    final a2Red = rAt(5, 5);
    expect(
      a2Red,
      lessThanOrEqualTo(16),
      reason:
          'A2: top-left corner red=$a2Red must be ≤ 16 (cold, no blob1 bleed)',
    );

    // -----------------------------------------------------------------------
    // A3 — at y=40, red is monotonically non-decreasing sampled at
    //        x = 40%, 55%, 70%, 85%, (w-5).
    // Blob1 distance decreases as x→w+30, so red increases left→right.
    // A disc would peak then drop; a tail-only gradient does not.
    // Tolerance: allow –1 for rounding noise between adjacent samples.
    // -----------------------------------------------------------------------
    final a3Xs = [
      (w * 0.40).round(),
      (w * 0.55).round(),
      (w * 0.70).round(),
      (w * 0.85).round(),
      w - 5,
    ];
    final a3Reds = a3Xs.map((x) => rAt(x, 40)).toList();
    for (var i = 0; i < a3Reds.length - 1; i++) {
      expect(
        a3Reds[i + 1],
        greaterThanOrEqualTo(a3Reds[i] - 1),
        reason:
            'A3: at y=40 red must be non-decreasing left→right; '
            'sample[$i]=${a3Reds[i]} sample[${i + 1}]=${a3Reds[i + 1]} '
            '(xs=${a3Xs[i]},${a3Xs[i + 1]})',
      );
    }

    // -----------------------------------------------------------------------
    // A4 — at y=80, max absolute red delta between any two samples 5px apart
    //        must be ≤ 4. A disc has a sharp ring edge (large delta). A smooth
    //        radial tail does not.
    // Sample a 100px span near the centre of the right half.
    // -----------------------------------------------------------------------
    var a4MaxDelta = 0;
    var a4MaxX = 0;
    for (var x = 100; x < w - 5; x += 5) {
      final delta = (rAt(x + 5, 80) - rAt(x, 80)).abs();
      if (delta > a4MaxDelta) {
        a4MaxDelta = delta;
        a4MaxX = x;
      }
    }
    expect(
      a4MaxDelta,
      lessThanOrEqualTo(4),
      reason:
          'A4: at y=80, max 5px red delta=$a4MaxDelta (at x=$a4MaxX) must be '
          '≤ 4 (no sharp ring edge = not a disc)',
    );

    // -----------------------------------------------------------------------
    // A5 — screen centre red ≤ 18 (near-espresso; no blob dominates middle).
    // Both blob centres are off-screen and their radii do not reach the centre.
    // -----------------------------------------------------------------------
    final a5Red = rAt(w ~/ 2, h ~/ 2);
    expect(
      a5Red,
      lessThanOrEqualTo(18),
      reason: 'A5: centre red=$a5Red must be ≤ 18 (near-espresso, no blob)',
    );

    // -----------------------------------------------------------------------
    // A6 — bottom-left area (x=5, y=h-250) red ≥ 20 (blob 2 tail present).
    // Blob2 center = (-30, h-240). At (5, h-250), distance ≈ 36px → warm.
    // -----------------------------------------------------------------------
    final a6Red = rAt(5, h - 250);
    expect(
      a6Red,
      greaterThanOrEqualTo(20),
      reason:
          'A6: bottom-left (5,h-250) red=$a6Red must be ≥ 20 (blob2 tail present)',
    );

    // -----------------------------------------------------------------------
    // A7 — bottom-right corner red ≤ 16 (cold; no blob reaches here).
    // -----------------------------------------------------------------------
    final a7Red = rAt(w - 5, h - 5);
    expect(
      a7Red,
      lessThanOrEqualTo(16),
      reason: 'A7: bottom-right corner red=$a7Red must be ≤ 16 (cold, no blob)',
    );

    // Report sampled values for diagnosability even on pass.
    // ignore: avoid_print — test-only output, not production code.
    printOnFailure(
      'Pixel sample report:\n'
      '  A1 top-right (${w - 5},5)     R=$a1Red  (≥28)\n'
      '  A2 top-left  (5,5)            R=$a2Red  (≤16)\n'
      '  A3 y=40 reds: $a3Reds         (non-decreasing)\n'
      '  A4 max 5px delta at y=80      Δ=$a4MaxDelta at x=$a4MaxX (≤4)\n'
      '  A5 centre (${w ~/ 2},${h ~/ 2}) R=$a5Red  (≤18)\n'
      '  A6 bot-left (5,${h - 250})   R=$a6Red  (≥20)\n'
      '  A7 bot-right (${w - 5},${h - 5}) R=$a7Red  (≤16)\n',
    );
  });
}
