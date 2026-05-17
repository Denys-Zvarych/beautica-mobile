// Widget tests for AuthGradientBackground — Bayer-4×4 dithered gradient.
//
// History:
//   LinearGradient (iteration 5): tested DecoratedBox + LinearGradient tree.
//   Dithered (iteration 6, this file): widget now uses CustomPaint + a
//   ui.PictureRecorder that records 1×1 drawRect calls per pixel. The
//   DecoratedBox / LinearGradient structural assertions are replaced.
//
// Covered scenarios:
//   1. Widget renders without error (smoke test).
//   2. Widget tree contains a CustomPaint descendant (never a DecoratedBox with
//      a gradient — proves the linear-gradient code path is gone).
//   3. ColoredBox espresso fallback is shown when constraints are empty.
//   4. Widget is const-constructible (public API unchanged).
//   5. SizedBox.expand child is present inside the CustomPaint tree.
//   6. Golden: rendered output matches the approved dithered baseline.
//      Catches regressions back to any radial/blob/linear model, wrong colors,
//      or banding.

import 'package:beautica_mobile/features/auth/presentation/auth_gradient_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';

void main() {
  setUpAll(() async => loadAppFonts());

  // Clear the static picture cache before each test so tests are isolated.
  setUp(() => ditherPictureCache.clear());

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
      await tester.pump(); // LayoutBuilder resolves constraints
      expect(find.byType(AuthGradientBackground), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 2 — widget tree contains a CustomPaint descendant (not DecoratedBox)
    // -------------------------------------------------------------------------
    testWidgets(
      '2. contains a CustomPaint descendant (no DecoratedBox/LinearGradient)',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Stack(children: [AuthGradientBackground()])),
          ),
        );
        await tester.pump();

        final bgFinder = find.byType(AuthGradientBackground);

        expect(
          find.descendant(of: bgFinder, matching: find.byType(DecoratedBox)),
          findsNothing,
          reason:
              'AuthGradientBackground must NOT contain a DecoratedBox — '
              'the LinearGradient implementation is replaced by dithering.',
        );

        expect(
          find.descendant(of: bgFinder, matching: find.byType(CustomPaint)),
          findsWidgets,
          reason:
              'AuthGradientBackground must contain a CustomPaint for the '
              'dithered pixel buffer.',
        );
      },
    );

    // -------------------------------------------------------------------------
    // Test 3 — ColoredBox espresso fallback is the correct color
    // -------------------------------------------------------------------------
    testWidgets('3. ColoredBox fallback color is espresso #0D0906', (
      tester,
    ) async {
      // Pump with tight zero constraints to force the ColoredBox branch.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.shrink(child: AuthGradientBackground()),
          ),
        ),
      );
      await tester.pump();

      final coloredBoxes = tester.widgetList<ColoredBox>(
        find.byType(ColoredBox),
      );

      // There may be multiple ColoredBox widgets (MaterialApp etc.); find ours.
      final espresso = coloredBoxes.where(
        (cb) => cb.color == const Color(0xFF0D0906),
      );
      expect(
        espresso,
        isNotEmpty,
        reason:
            'ColoredBox fallback must use espresso #0D0906 to avoid a '
            'white flash when layout constraints are empty.',
      );
    });

    // -------------------------------------------------------------------------
    // Test 4 — public API is const-constructible (compile-time assertion)
    // -------------------------------------------------------------------------
    testWidgets('4. widget is const-constructible', (tester) async {
      const widget = AuthGradientBackground();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Stack(children: [widget])),
        ),
      );
      expect(find.byType(AuthGradientBackground), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 5 — SizedBox.expand child is present inside the CustomPaint tree
    // -------------------------------------------------------------------------
    testWidgets('5. contains SizedBox.expand to fill available space', (
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
            'Expected a SizedBox.expand() child so the painter fills space.',
      );
    });

    // -------------------------------------------------------------------------
    // Test 6 — Golden: rendered output matches the approved dithered baseline.
    //
    // Baseline filename: auth_gradient_background_dithered.png
    // (old auth_gradient_background_linear.png deleted)
    //
    // Regenerate: flutter test --update-goldens
    //   test/features/auth/presentation/auth_gradient_background_test.dart
    // -------------------------------------------------------------------------
    testGoldens('6. rendered output matches approved dithered baseline', (
      tester,
    ) async {
      await tester.pumpWidgetBuilder(
        const AuthGradientBackground(),
        wrapper: materialAppWrapper(theme: ThemeData.dark()),
        surfaceSize: const Size(390, 844),
      );
      await tester.pump(); // LayoutBuilder resolves constraints

      await screenMatchesGolden(
        tester,
        'auth_gradient_background_dithered',
        customPump: (t) async => t.pump(),
      );
    });
  });
}
