// Widget tests for AuthGradientBackground — drawRect redesign (Phase 2.x).
//
// AuthGradientBackground was rewritten from a Positioned-Container + RadialGradient
// approach to a CustomPainter-based implementation that draws directly on the canvas
// via canvas.drawRect() + RadialGradient.createShader(). The previous drawCircle()
// approach produced a visible circular boundary artifact; drawRect() eliminates it.
//
// Covered scenarios:
//   1. Widget renders without error (smoke test).
//   2. Widget tree contains exactly one CustomPaint.
//   3. The CustomPaint has a non-null painter.
//   4. The painter reports shouldRepaint == false (background is static).
//   5. The CustomPaint child is a SizedBox.expand (fills available space).
//   6. Golden: rendered output matches the approved drawRect baseline.
//      Catches regressions back to drawCircle (circle boundary artifact),
//      wrong gradient anchor positions, and opacity changes.

import 'package:beautica_mobile/features/auth/presentation/auth_gradient_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';

void main() {
  // Golden tests use loadAppFonts() to ensure font rendering is deterministic
  // across machines. For a pure-canvas CustomPainter (no text rendered) this is
  // a no-op but is kept as a convention so the group can grow without surprises.
  setUpAll(() async => loadAppFonts());

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

    // -------------------------------------------------------------------------
    // Test 6 — Golden: rendered pixel output matches the approved drawRect
    // baseline. This is the only layer that can catch a regression back to
    // canvas.drawCircle (which produces a visible circular boundary artifact)
    // or changes to gradient anchor positions, radii, or opacity constants.
    //
    // Baseline: run `flutter test --update-goldens` once after the redesign is
    // approved, commit the generated PNG at:
    //   test/features/auth/presentation/goldens/auth_gradient_background_drawrect.png
    // Subsequent CI runs compare against that baseline automatically.
    //
    // Device size — 390 × 844 pt (logical pixels), 1× device pixel ratio.
    // Using a fixed DPR prevents baseline mismatches across CI runners with
    // different display densities. Physical resolution is therefore 390 × 844 px
    // — large enough to make circular vs. rect boundary artifacts visible.
    // -------------------------------------------------------------------------
    testGoldens('6. rendered output matches approved drawRect baseline', (
      tester,
    ) async {
      await tester.pumpWidgetBuilder(
        const AuthGradientBackground(),
        // Wrap in a zero-MediaQuery context so the widget receives a
        // deterministic constraint. SizedBox.expand() fills the surfaceSize.
        wrapper: materialAppWrapper(theme: ThemeData.dark()),
        surfaceSize: const Size(390, 844),
      );

      await screenMatchesGolden(
        tester,
        'auth_gradient_background_drawrect',
        customPump: (t) async => t.pump(),
      );
    });
  });
}
