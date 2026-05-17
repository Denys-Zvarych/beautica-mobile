// Widget tests for AuthGradientBackground — LinearGradient redesign (Phase 2.x).
//
// History: AuthGradientBackground previously used a CustomPainter that drew an
// espresso rect + two RadialGradient "blob" shaders. On real devices the blobs
// ALWAYS rendered as a visible ring/disc. The radial approach is abandoned.
// The widget is now a DecoratedBox whose BoxDecoration carries a single
// full-bleed LinearGradient (top-left → bottom-right Warm Mocha wash). There is
// no CustomPaint and no RadialGradient anywhere — a ring is impossible.
//
// Covered scenarios:
//   1. Widget renders without error (smoke test).
//   2. Widget tree contains a DecoratedBox descendant.
//   3. The decoration is a BoxDecoration whose gradient is a LinearGradient
//      (never a RadialGradient / SweepGradient).
//   4. The gradient runs topLeft → bottomRight with the exact Warm Mocha stops.
//   5. The DecoratedBox child is a SizedBox.expand (fills available space).
//   6. Golden: rendered output matches the approved LinearGradient baseline.
//      Catches regressions back to any radial/blob model, wrong direction,
//      wrong colors, or wrong stops.

import 'package:beautica_mobile/features/auth/presentation/auth_gradient_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';

void main() {
  // Golden tests use loadAppFonts() to ensure font rendering is deterministic
  // across machines. For a pure-decoration widget (no text rendered) this is a
  // no-op but is kept as a convention so the group can grow without surprises.
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
    // Test 2 — widget tree contains a DecoratedBox descendant
    // -------------------------------------------------------------------------
    testWidgets(
      '2. AuthGradientBackground contains a DecoratedBox descendant',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Stack(children: [AuthGradientBackground()])),
          ),
        );

        final bgFinder = find.byType(AuthGradientBackground);
        final boxFinder = find.descendant(
          of: bgFinder,
          matching: find.byType(DecoratedBox),
        );

        expect(
          boxFinder,
          findsOneWidget,
          reason:
              'AuthGradientBackground must contain exactly one DecoratedBox '
              '(no CustomPaint / radial shader anymore)',
        );
      },
    );

    // -------------------------------------------------------------------------
    // Test 3 — decoration is a BoxDecoration whose gradient is a LinearGradient
    //          (and is provably NOT a RadialGradient / SweepGradient)
    // -------------------------------------------------------------------------
    testWidgets('3. decoration gradient is a LinearGradient', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Stack(children: [AuthGradientBackground()])),
        ),
      );

      final bgFinder = find.byType(AuthGradientBackground);
      final boxFinder = find.descendant(
        of: bgFinder,
        matching: find.byType(DecoratedBox),
      );
      final box = tester.widget<DecoratedBox>(boxFinder);
      final decoration = box.decoration;

      expect(
        decoration,
        isA<BoxDecoration>(),
        reason: 'decoration must be a BoxDecoration',
      );
      final gradient = (decoration as BoxDecoration).gradient;
      expect(
        gradient,
        isA<LinearGradient>(),
        reason: 'gradient must be a LinearGradient',
      );
      expect(
        gradient,
        isNot(isA<RadialGradient>()),
        reason: 'gradient must NEVER be a RadialGradient (no ring/disc)',
      );
      expect(
        gradient,
        isNot(isA<SweepGradient>()),
        reason: 'gradient must NEVER be a SweepGradient',
      );
    });

    // -------------------------------------------------------------------------
    // Test 4 — gradient runs topLeft → bottomRight with the exact Warm Mocha
    //          stops/colors (locks the brand spec)
    // -------------------------------------------------------------------------
    testWidgets(
      '4. gradient direction, colors and stops are the Warm Mocha spec',
      (tester) async {
        const g = AuthGradientBackground.gradient;

        expect(
          g.begin,
          Alignment.topLeft,
          reason: 'gradient must begin at topLeft (warm corner)',
        );
        expect(
          g.end,
          Alignment.bottomRight,
          reason: 'gradient must end at bottomRight (espresso base)',
        );
        expect(
          g.colors,
          const [
            Color(0xFF3A2615),
            Color(0xFF2A1A0E),
            Color(0xFF1C1109),
            Color(0xFF0D0906),
          ],
          reason:
              'colors must be the dark Warm Mocha ramp (no light/cream tones)',
        );
        expect(g.stops, const [
          0.0,
          0.35,
          0.65,
          1.0,
        ], reason: 'stops must be the approved smooth ramp');
      },
    );

    // -------------------------------------------------------------------------
    // Test 5 — DecoratedBox child is SizedBox.expand to fill available space
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
    // Test 6 — Golden: rendered pixel output matches the approved LinearGradient
    // baseline. This is the layer that catches a regression back to any
    // radial/blob model (visible ring), a flipped direction, or changed
    // colors/stops.
    //
    // Baseline: run `flutter test --update-goldens` once after the redesign is
    // approved, commit the generated PNG at:
    //   test/features/auth/presentation/goldens/auth_gradient_background_linear.png
    // Subsequent CI runs compare against that baseline automatically.
    //
    // Device size — 390 × 844 pt (logical pixels), 1× device pixel ratio.
    // Using a fixed DPR prevents baseline mismatches across CI runners with
    // different display densities.
    // -------------------------------------------------------------------------
    testGoldens('6. rendered output matches approved LinearGradient baseline', (
      tester,
    ) async {
      await tester.pumpWidgetBuilder(
        const AuthGradientBackground(),
        // Wrap in a deterministic context so the widget receives a fixed
        // constraint. SizedBox.expand() fills the surfaceSize.
        wrapper: materialAppWrapper(theme: ThemeData.dark()),
        surfaceSize: const Size(390, 844),
      );

      await screenMatchesGolden(
        tester,
        'auth_gradient_background_linear',
        customPump: (t) async => t.pump(),
      );
    });
  });
}
