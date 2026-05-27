// Phase 1.1 — VelvetTouch theme wiring tests.
//
// Verifies that [velvetTheme] exposes the correct VelvetTouch tokens via the
// Material 3 [ColorScheme] — specifically that [BrandColors.base] is the
// surface color and that brightness is light-only.
//
// Also pins every [BrandColors] constant to its locked hex value so a
// future accidental edit to the palette is caught immediately.

import 'package:beautica_mobile/core/theme/app_theme.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Theme structure
  // ---------------------------------------------------------------------------

  testWidgets('velvetTheme surface is BrandColors.base', (tester) async {
    late ColorScheme scheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: velvetTheme(),
        home: Builder(
          builder: (BuildContext ctx) {
            scheme = Theme.of(ctx).colorScheme;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(scheme.surface, BrandColors.base);
    expect(scheme.brightness, Brightness.light);
  });

  testWidgets('velvetTheme scaffoldBackgroundColor is BrandColors.base', (
    tester,
  ) async {
    late ThemeData theme;
    await tester.pumpWidget(
      MaterialApp(
        theme: velvetTheme(),
        home: Builder(
          builder: (BuildContext ctx) {
            theme = Theme.of(ctx);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(theme.scaffoldBackgroundColor, BrandColors.base);
  });

  testWidgets('velvetTheme useMaterial3 is true', (tester) async {
    late ThemeData theme;
    await tester.pumpWidget(
      MaterialApp(
        theme: velvetTheme(),
        home: Builder(
          builder: (BuildContext ctx) {
            theme = Theme.of(ctx);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(theme.useMaterial3, isTrue);
  });

  // ---------------------------------------------------------------------------
  // BrandColors value-pinning — hex assertions for every constant.
  // If any token drifts from the VelvetTouch locked palette, a named
  // failure surfaces here before it reaches production.
  // ---------------------------------------------------------------------------

  group('BrandColors hex value pins', () {
    test('base is #E6DDD0', () {
      expect(BrandColors.base, const Color(0xFFE6DDD0));
    });

    test('accent is #B89A7A', () {
      expect(BrandColors.accent, const Color(0xFFB89A7A));
    });

    test('accentDeep is #6A4A28', () {
      expect(BrandColors.accentDeep, const Color(0xFF6A4A28));
    });

    test('accentLatte is #8A6840', () {
      expect(BrandColors.accentLatte, const Color(0xFF8A6840));
    });

    test('accentLogo is #C4A988', () {
      expect(BrandColors.accentLogo, const Color(0xFFC4A988));
    });

    test('text is #4A3322', () {
      expect(BrandColors.text, const Color(0xFF4A3322));
    });

    test('textSecondary is #6E5743', () {
      expect(BrandColors.textSecondary, const Color(0xFF6E5743));
    });

    test('muted is #9A8367', () {
      expect(BrandColors.muted, const Color(0xFF9A8367));
    });

    test('placeholder is #AD9A82', () {
      expect(BrandColors.placeholder, const Color(0xFFAD9A82));
    });

    test('faint is #BCAB95', () {
      expect(BrandColors.faint, const Color(0xFFBCAB95));
    });

    test('white is #F5EDE0', () {
      expect(BrandColors.white, const Color(0xFFF5EDE0));
    });

    test('shadowLightStrong is #FFFBF4', () {
      expect(BrandColors.shadowLightStrong, const Color(0xFFFFFBF4));
    });

    test('shadowDarkCard is #C4B49E', () {
      expect(BrandColors.shadowDarkCard, const Color(0xFFC4B49E));
    });

    test('shadowDarkButton is #C0AF98', () {
      expect(BrandColors.shadowDarkButton, const Color(0xFFC0AF98));
    });

    test('error is #B0452F', () {
      expect(BrandColors.error, const Color(0xFFB0452F));
    });

    test('success is #5C7A4A', () {
      expect(BrandColors.success, const Color(0xFF5C7A4A));
    });

    test('seed equals accentDeep', () {
      expect(BrandColors.seed, BrandColors.accentDeep);
    });
  });
}
