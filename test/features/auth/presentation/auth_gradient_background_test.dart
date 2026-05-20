// Widget tests for AuthGradientBackground — plain Warm-Mocha LinearGradient.
//
// History:
//   Iteration 5: DecoratedBox + LinearGradient (banding regression).
//   Iteration 6: Bayer-4×4 dither CustomPainter (visually perfect, but
//                ~2.5 s GPU raster per frame on Mali-G52 / Impeller-Vulkan —
//                unusable, reverted on 2026-05-20).
//   Iteration 7 (this file): back to LinearGradient, no dither.
//
// Covered scenarios:
//   1. Widget renders without error (smoke test).
//   2. Widget tree contains a DecoratedBox whose decoration carries a
//      LinearGradient with the three approved Warm-Mocha stops (proves the
//      dither painter is gone and we are back on a single GPU draw call).
//   3. Widget is const-constructible (public API unchanged).
//   4. SizedBox.expand child is present so the background fills its parent.

import 'package:beautica_mobile/features/auth/presentation/auth_gradient_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthGradientBackground', () {
    // -------------------------------------------------------------------------
    // Test 1 — smoke test: renders without error
    // -------------------------------------------------------------------------
    testWidgets('1. renders without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Stack(children: [AuthGradientBackground()])),
        ),
      );
      await tester.pump();
      expect(find.byType(AuthGradientBackground), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 2 — DecoratedBox + LinearGradient with the approved Warm-Mocha stops
    // -------------------------------------------------------------------------
    testWidgets('2. uses LinearGradient with Warm-Mocha stops', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Stack(children: [AuthGradientBackground()])),
        ),
      );
      await tester.pump();

      final bgFinder = find.byType(AuthGradientBackground);

      final decoratedBoxes = tester
          .widgetList<DecoratedBox>(
            find.descendant(of: bgFinder, matching: find.byType(DecoratedBox)),
          )
          .toList();
      expect(
        decoratedBoxes,
        isNotEmpty,
        reason:
            'AuthGradientBackground must contain a DecoratedBox carrying the '
            'LinearGradient.',
      );

      final gradients = decoratedBoxes
          .map((db) => db.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.gradient)
          .whereType<LinearGradient>()
          .toList();

      expect(
        gradients,
        isNotEmpty,
        reason:
            'AuthGradientBackground must paint via a BoxDecoration with a '
            'LinearGradient (not a CustomPainter / dither picture).',
      );

      final grad = gradients.first;
      expect(grad.begin, Alignment.topLeft);
      expect(grad.end, Alignment.bottomRight);
      expect(grad.colors, const [
        Color(0xFF3A2615),
        Color(0xFF1E140A),
        Color(0xFF0D0906),
      ]);
      expect(grad.stops, const [0.0, 0.55, 1.0]);
    });

    // -------------------------------------------------------------------------
    // Test 3 — public API is const-constructible (compile-time assertion)
    // -------------------------------------------------------------------------
    testWidgets('3. widget is const-constructible', (tester) async {
      const widget = AuthGradientBackground();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Stack(children: [widget])),
        ),
      );
      expect(find.byType(AuthGradientBackground), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 4 — SizedBox.expand child is present so the background fills space
    // -------------------------------------------------------------------------
    testWidgets('4. contains SizedBox.expand to fill available space', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Stack(children: [AuthGradientBackground()])),
        ),
      );
      await tester.pump();

      final sizedBoxes = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(AuthGradientBackground),
              matching: find.byType(SizedBox),
            ),
          )
          .where(
            (sb) => sb.width == double.infinity && sb.height == double.infinity,
          )
          .toList();

      expect(
        sizedBoxes,
        isNotEmpty,
        reason:
            'Expected a SizedBox.expand() so the gradient fills its parent.',
      );
    });
  });
}
