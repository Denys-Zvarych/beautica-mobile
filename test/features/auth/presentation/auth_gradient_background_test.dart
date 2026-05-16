// Widget tests for AuthGradientBackground — CustomPainter rewrite (Phase 2.x).
//
// AuthGradientBackground was rewritten from a Positioned-Container + RadialGradient
// approach to a CustomPainter-based implementation that draws blobs directly on the
// canvas via canvas.drawCircle() + RadialGradient.createShader(). This eliminates
// the hard-edged circle artifacts caused by Impeller compositing layers.
//
// Covered scenarios:
//   1. Widget renders without error (smoke test).
//   2. Widget tree contains exactly one CustomPaint.
//   3. The CustomPaint has a non-null painter.
//   4. The painter reports shouldRepaint == false (background is static).
//   5. The CustomPaint child is a SizedBox.expand (fills available space).

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
      // No exception thrown — rendering succeeded.
      expect(find.byType(AuthGradientBackground), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 2 — widget tree contains at least one CustomPaint descending from
    // AuthGradientBackground (the framework may add its own CustomPaint nodes)
    // -------------------------------------------------------------------------
    testWidgets('2. AuthGradientBackground contains a CustomPaint descendant', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Stack(children: [AuthGradientBackground()])),
        ),
      );

      final bgFinder = find.byType(AuthGradientBackground);
      final painterFinder = find.descendant(
        of: bgFinder,
        matching: find.byType(CustomPaint),
      );

      expect(
        painterFinder,
        findsOneWidget,
        reason:
            'AuthGradientBackground must contain exactly one CustomPaint descendant',
      );
    });

    // -------------------------------------------------------------------------
    // Test 3 — the CustomPaint has a non-null painter
    // -------------------------------------------------------------------------
    testWidgets('3. the CustomPaint has a non-null painter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Stack(children: [AuthGradientBackground()])),
        ),
      );

      final bgFinder = find.byType(AuthGradientBackground);
      final painterFinder = find.descendant(
        of: bgFinder,
        matching: find.byType(CustomPaint),
      );
      final customPaint = tester.widget<CustomPaint>(painterFinder);
      expect(
        customPaint.painter,
        isNotNull,
        reason: 'CustomPaint.painter must not be null',
      );
    });

    // -------------------------------------------------------------------------
    // Test 4 — shouldRepaint returns false (background is static)
    // -------------------------------------------------------------------------
    testWidgets('4. painter.shouldRepaint returns false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Stack(children: [AuthGradientBackground()])),
        ),
      );

      final bgFinder = find.byType(AuthGradientBackground);
      final painterFinder = find.descendant(
        of: bgFinder,
        matching: find.byType(CustomPaint),
      );
      final customPaint = tester.widget<CustomPaint>(painterFinder);
      final painter = customPaint.painter!;

      expect(
        painter.shouldRepaint(painter),
        isFalse,
        reason:
            'The background painter is static and must never request a repaint',
      );
    });

    // -------------------------------------------------------------------------
    // Test 5 — CustomPaint child is SizedBox.expand to fill available space
    // -------------------------------------------------------------------------
    testWidgets('5. contains SizedBox.expand to fill available space', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Stack(children: [AuthGradientBackground()])),
        ),
      );

      // SizedBox.expand() sets width = double.infinity and height = double.infinity.
      final sizedBoxes = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where(
            (sb) => sb.width == double.infinity && sb.height == double.infinity,
          )
          .toList();

      expect(
        sizedBoxes,
        isNotEmpty,
        reason: 'Expected a SizedBox.expand() child to make the widget expand',
      );
    });
  });
}
