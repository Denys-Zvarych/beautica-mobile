// Widget tests for AuthGradientBackground.
//
// AuthGradientBackground is a new shared StatelessWidget introduced in the
// auth-screen redesign (Phase 3.x visual). It is used by all three auth
// screens (SplashScreen, LoginScreen, RegisterScreen) as the bottom layer of
// their Stack. Zero test coverage existed before this file.
//
// Covered scenarios:
//   1. Widget renders without error (smoke test).
//   2. Widget contains a DecoratedBox (the gradient carrier).
//   3. The decoration is a LinearGradient.
//   4. The gradient begin/end alignment is topCenter → bottomCenter.
//   5. The first gradient colour equals BrandColors.midnight (#0D3B66).
//   6. The second gradient colour equals the deep-navy value (#061E35).
//   7. The widget is wrapped in SizedBox.expand() — expands to fill the Stack.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_gradient_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Convenience: returns the first [DecoratedBox] in the tree whose decoration
// is a [BoxDecoration] with a [LinearGradient]. Throws if not found.
DecoratedBox _findDecoratedBox(WidgetTester tester) {
  final candidates = tester
      .widgetList<DecoratedBox>(find.byType(DecoratedBox))
      .where(
        (db) =>
            db.decoration is BoxDecoration &&
            (db.decoration as BoxDecoration).gradient is LinearGradient,
      )
      .toList();

  expect(
    candidates,
    isNotEmpty,
    reason: 'Expected at least one DecoratedBox with a LinearGradient',
  );
  return candidates.first;
}

void main() {
  group('AuthGradientBackground', () {
    // -------------------------------------------------------------------------
    // Test 1 — smoke test: renders without error
    // -------------------------------------------------------------------------
    testWidgets('1. renders without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(children: [AuthGradientBackground()]),
          ),
        ),
      );
      // No exception thrown — rendering succeeded.
      expect(find.byType(AuthGradientBackground), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 2 — widget tree contains a DecoratedBox with a LinearGradient
    // -------------------------------------------------------------------------
    testWidgets('2. widget tree contains a DecoratedBox with a LinearGradient', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(children: [AuthGradientBackground()]),
          ),
        ),
      );

      // _findDecoratedBox asserts the structure internally; no further assertion
      // is needed here — the call throws if the widget is missing.
      _findDecoratedBox(tester);
    });

    // -------------------------------------------------------------------------
    // Test 3 — gradient direction is topCenter → bottomCenter
    // -------------------------------------------------------------------------
    testWidgets('3. gradient runs from Alignment.topCenter to Alignment.bottomCenter', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(children: [AuthGradientBackground()]),
          ),
        ),
      );

      final gradient = (_findDecoratedBox(tester).decoration as BoxDecoration)
          .gradient! as LinearGradient;

      expect(gradient.begin, equals(Alignment.topCenter));
      expect(gradient.end, equals(Alignment.bottomCenter));
    });

    // -------------------------------------------------------------------------
    // Test 4 — first gradient stop is BrandColors.midnight (#0D3B66)
    // -------------------------------------------------------------------------
    testWidgets('4. first gradient colour is BrandColors.midnight', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(children: [AuthGradientBackground()]),
          ),
        ),
      );

      final gradient = (_findDecoratedBox(tester).decoration as BoxDecoration)
          .gradient! as LinearGradient;

      expect(gradient.colors.first, equals(BrandColors.midnight));
    });

    // -------------------------------------------------------------------------
    // Test 5 — second gradient stop is deep-navy (#061E35)
    // -------------------------------------------------------------------------
    testWidgets('5. second gradient colour is deep-navy #061E35', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(children: [AuthGradientBackground()]),
          ),
        ),
      );

      final gradient = (_findDecoratedBox(tester).decoration as BoxDecoration)
          .gradient! as LinearGradient;

      expect(gradient.colors.last, equals(const Color(0xFF061E35)));
    });

    // -------------------------------------------------------------------------
    // Test 6 — exactly two gradient stops are defined
    // -------------------------------------------------------------------------
    testWidgets('6. gradient has exactly two colour stops', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(children: [AuthGradientBackground()]),
          ),
        ),
      );

      final gradient = (_findDecoratedBox(tester).decoration as BoxDecoration)
          .gradient! as LinearGradient;

      expect(gradient.colors, hasLength(2));
    });

    // -------------------------------------------------------------------------
    // Test 7 — SizedBox.expand child ensures the widget fills its parent
    // -------------------------------------------------------------------------
    testWidgets('7. contains SizedBox.expand to fill available space', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(children: [AuthGradientBackground()]),
          ),
        ),
      );

      // SizedBox.expand() sets width = double.infinity and height = double.infinity.
      final sizedBoxes = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where(
            (sb) =>
                sb.width == double.infinity && sb.height == double.infinity,
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
