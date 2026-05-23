// Phase 1.1 — VelvetTouch typography wiring tests.
//
// Verifies that [velvetTheme] exposes a non-null Nunito text theme and that
// core roles have the expected font-family prefix. The VelvetTouch design
// system uses Nunito for body/label copy (via GoogleFonts.nunitoTextTheme).
//
// Font-family is asserted as startsWith('Nunito') — GoogleFonts synthesizes
// variant family names (e.g. 'Nunito_regular') so exact matching is brittle.

import 'package:beautica_mobile/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [velvetTheme] and returns the resolved [TextTheme].
Future<TextTheme> _pumpVelvetTheme(WidgetTester tester) async {
  late TextTheme textTheme;
  await tester.pumpWidget(
    MaterialApp(
      theme: velvetTheme(),
      home: Builder(
        builder: (BuildContext ctx) {
          textTheme = Theme.of(ctx).textTheme;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return textTheme;
}

void main() {
  // ---------------------------------------------------------------------------
  // Per-role fontFamily assertions — Nunito via GoogleFonts.nunitoTextTheme.
  // ---------------------------------------------------------------------------

  group('velvetTheme — per-role Nunito fontFamily', () {
    testWidgets('bodySmall fontFamily starts with Nunito', (tester) async {
      final theme = await _pumpVelvetTheme(tester);
      expect(theme.bodySmall!.fontFamily, startsWith('Nunito'));
    });

    testWidgets('bodyMedium fontFamily starts with Nunito', (tester) async {
      final theme = await _pumpVelvetTheme(tester);
      expect(theme.bodyMedium!.fontFamily, startsWith('Nunito'));
    });

    testWidgets('bodyLarge fontFamily starts with Nunito', (tester) async {
      final theme = await _pumpVelvetTheme(tester);
      expect(theme.bodyLarge!.fontFamily, startsWith('Nunito'));
    });

    testWidgets('labelMedium fontFamily starts with Nunito', (tester) async {
      final theme = await _pumpVelvetTheme(tester);
      expect(theme.labelMedium!.fontFamily, startsWith('Nunito'));
    });

    testWidgets('titleMedium fontFamily starts with Nunito', (tester) async {
      final theme = await _pumpVelvetTheme(tester);
      expect(theme.titleMedium!.fontFamily, startsWith('Nunito'));
    });

    testWidgets('titleSmall fontFamily starts with Nunito', (tester) async {
      final theme = await _pumpVelvetTheme(tester);
      expect(theme.titleSmall!.fontFamily, startsWith('Nunito'));
    });
  });

  // ---------------------------------------------------------------------------
  // Sanity check — textTheme is non-null for all standard roles.
  // ---------------------------------------------------------------------------

  testWidgets('velvetTheme textTheme roles are non-null', (tester) async {
    final theme = await _pumpVelvetTheme(tester);
    expect(theme.bodyLarge, isNotNull);
    expect(theme.bodyMedium, isNotNull);
    expect(theme.bodySmall, isNotNull);
    expect(theme.labelLarge, isNotNull);
    expect(theme.labelMedium, isNotNull);
    expect(theme.titleLarge, isNotNull);
    expect(theme.titleMedium, isNotNull);
    expect(theme.headlineLarge, isNotNull);
    expect(theme.displayLarge, isNotNull);
  });
}
