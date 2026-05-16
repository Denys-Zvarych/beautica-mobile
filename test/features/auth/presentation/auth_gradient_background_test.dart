// Widget tests for AuthGradientBackground — Warm Mocha redesign (Phase 2.x).
//
// AuthGradientBackground was redesigned from a 5-stop navy LinearGradient to
// an espresso (#0D0906) solid fill with two ambient RadialGradient blob
// overlays.  These tests verify the new widget structure.
//
// Covered scenarios:
//   1. Widget renders without error (smoke test).
//   2. Widget tree contains a DecoratedBox with solid espresso fill.
//   3. The solid-fill BoxDecoration uses BrandColors.espresso.
//   4. Widget tree contains at least two ambient blob Containers.
//   5. Blob containers use RadialGradient decorations.
//   6. The gradient blobs contain mocha-toned warm colours.
//   7. The widget contains a SizedBox.expand to fill available space.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
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
    // Test 2 — widget tree contains a DecoratedBox with a solid-colour fill
    // -------------------------------------------------------------------------
    testWidgets(
      '2. widget tree contains a DecoratedBox with a solid espresso fill',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Stack(children: [AuthGradientBackground()])),
          ),
        );

        // Find DecoratedBoxes whose BoxDecoration has a solid colour (no gradient).
        final solidFills = tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .where(
              (db) =>
                  db.decoration is BoxDecoration &&
                  (db.decoration as BoxDecoration).color != null &&
                  (db.decoration as BoxDecoration).gradient == null,
            )
            .toList();

        expect(
          solidFills,
          isNotEmpty,
          reason: 'Expected at least one solid-fill DecoratedBox (espresso bg)',
        );
      },
    );

    // -------------------------------------------------------------------------
    // Test 3 — solid fill uses BrandColors.espresso
    // -------------------------------------------------------------------------
    testWidgets('3. the solid-fill BoxDecoration uses BrandColors.espresso', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Stack(children: [AuthGradientBackground()])),
        ),
      );

      final solidFills = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where(
            (db) =>
                db.decoration is BoxDecoration &&
                (db.decoration as BoxDecoration).color ==
                    BrandColors.espresso &&
                (db.decoration as BoxDecoration).gradient == null,
          )
          .toList();

      expect(
        solidFills,
        isNotEmpty,
        reason: 'Expected a DecoratedBox filled with BrandColors.espresso',
      );
    });

    // -------------------------------------------------------------------------
    // Test 4 — widget tree contains at least two ambient blob Containers
    // -------------------------------------------------------------------------
    testWidgets(
      '4. widget tree contains at least two RadialGradient blob containers',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Stack(children: [AuthGradientBackground()])),
          ),
        );

        // Blob containers are rendered as Containers with a RadialGradient
        // BoxDecoration and explicit width/height.
        final blobs = tester
            .widgetList<Container>(find.byType(Container))
            .where(
              (c) =>
                  c.decoration is BoxDecoration &&
                  (c.decoration as BoxDecoration).gradient is RadialGradient,
            )
            .toList();

        expect(
          blobs.length,
          greaterThanOrEqualTo(2),
          reason:
              'Expected at least two ambient RadialGradient blob containers',
        );
      },
    );

    // -------------------------------------------------------------------------
    // Test 5 — blob containers use RadialGradient decorations
    // -------------------------------------------------------------------------
    testWidgets('5. blob containers use RadialGradient decorations', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Stack(children: [AuthGradientBackground()])),
        ),
      );

      final radialBlobs = tester
          .widgetList<Container>(find.byType(Container))
          .where(
            (c) =>
                c.decoration is BoxDecoration &&
                (c.decoration as BoxDecoration).gradient is RadialGradient,
          )
          .toList();

      expect(radialBlobs, isNotEmpty);

      // Each blob should fade from a semi-transparent warm colour to transparent.
      for (final blob in radialBlobs) {
        final gradient =
            (blob.decoration! as BoxDecoration).gradient! as RadialGradient;
        // Last stop must be fully transparent (a == 0.0).
        expect(
          gradient.colors.last.a,
          equals(0.0),
          reason: 'Blob edge must fade to fully transparent',
        );
      }
    });

    // -------------------------------------------------------------------------
    // Test 6 — gradient blobs contain warm mocha-toned colours
    // -------------------------------------------------------------------------
    testWidgets('6. the gradient blobs contain warm mocha-toned colours', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Stack(children: [AuthGradientBackground()])),
        ),
      );

      final radialBlobs = tester
          .widgetList<Container>(find.byType(Container))
          .where(
            (c) =>
                c.decoration is BoxDecoration &&
                (c.decoration as BoxDecoration).gradient is RadialGradient,
          )
          .toList();

      expect(radialBlobs, isNotEmpty);

      // Centre colour of every blob must be a warm tone:
      //   r channel ≥ g channel (warm, not cool — mocha tone check).
      for (final blob in radialBlobs) {
        final gradient =
            (blob.decoration! as BoxDecoration).gradient! as RadialGradient;
        final centre = gradient.colors.first;
        // Warm colour: r ≥ g (using non-deprecated Color.r / Color.g API).
        expect(
          centre.r,
          greaterThanOrEqualTo(centre.g),
          reason: 'Blob centre colour should have r ≥ g (warm mocha tone)',
        );
      }
    });

    // -------------------------------------------------------------------------
    // Test 7 — SizedBox.expand child ensures the widget fills its parent
    // -------------------------------------------------------------------------
    testWidgets('7. contains SizedBox.expand to fill available space', (
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
