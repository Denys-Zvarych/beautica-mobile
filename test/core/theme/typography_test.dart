// Phase 1.2 — VelvetTouch typography tests.
//
// Verifies:
//   1. [VelvetText] style accessors return the correct font properties and
//      [BrandColors] color references.
//   2. [velvetTheme] text-theme roles carry the Nunito font family.
//
// Why testWidgets for VelvetText assertions?
// google_fonts fires an async loadFontIfNecessary side-effect on every
// GoogleFonts.* call.  A plain test() body completes synchronously and the
// test harness then reports the still-pending async work as a post-test
// failure.  Using testWidgets (even without pumping a widget tree) lets the
// harness drain the font-load queue via the implicit pump, eliminating the
// spurious async failure.  The style metadata assertions (fontSize, weight,
// color) are still purely synchronous — they pass on the first microtask.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:beautica_mobile/core/theme/app_theme.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

void main() {
  // ── VelvetText unit tests ────────────────────────────────────────────────
  group('VelvetText', () {
    testWidgets('heading uses Comfortaa 21/700 with BrandColors.text', (
      tester,
    ) async {
      final s = VelvetText.heading();
      expect(s.fontSize, 21.0);
      expect(s.fontWeight, FontWeight.w700);
      expect(s.height, 1.25);
      expect(s.color, BrandColors.text);
    });

    testWidgets('subheading uses Comfortaa 14/600', (tester) async {
      final s = VelvetText.subheading();
      expect(s.fontSize, 14.0);
      expect(s.fontWeight, FontWeight.w600);
      expect(s.color, BrandColors.text);
    });

    testWidgets('cta uses Comfortaa 13/700 with BrandColors.white', (
      tester,
    ) async {
      final s = VelvetText.cta();
      expect(s.fontSize, 13.0);
      expect(s.fontWeight, FontWeight.w700);
      expect(s.letterSpacing, 0.3);
      expect(s.color, BrandColors.white);
    });

    testWidgets(
      'wordmark uses Comfortaa 19/700 with BrandColors.text (WCAG AA+)',
      (tester) async {
        final s = VelvetText.wordmark();
        expect(s.fontSize, 19.0);
        expect(s.fontWeight, FontWeight.w700);
        // Changed from textSecondary (#6E5743, ~3.2:1) to text (#4A3322, ~7:1)
        // for WCAG AA compliance on the warm-taupe base (#E6DDD0) background.
        expect(s.color, BrandColors.text);
      },
    );

    testWidgets('body uses Nunito 12/600 height 1.5 with textSecondary', (
      tester,
    ) async {
      final s = VelvetText.body();
      expect(s.fontSize, 12.0);
      expect(s.fontWeight, FontWeight.w600);
      expect(s.height, 1.5);
      expect(s.color, BrandColors.textSecondary);
    });

    testWidgets('bodyStrong uses Nunito 12/700 with BrandColors.text', (
      tester,
    ) async {
      final s = VelvetText.bodyStrong();
      expect(s.fontSize, 12.0);
      expect(s.fontWeight, FontWeight.w700);
      expect(s.color, BrandColors.text);
    });

    testWidgets('input uses Nunito 13/600 with BrandColors.text', (
      tester,
    ) async {
      final s = VelvetText.input();
      expect(s.fontSize, 13.0);
      expect(s.fontWeight, FontWeight.w600);
      expect(s.color, BrandColors.text);
    });

    testWidgets(
      'label uses Nunito 11/700 letterSpacing 0.6 with BrandColors.muted',
      (tester) async {
        final s = VelvetText.label();
        expect(s.fontSize, 11.0);
        expect(s.fontWeight, FontWeight.w700);
        expect(s.letterSpacing, 0.6);
        expect(s.color, BrandColors.muted);
      },
    );

    testWidgets('link uses Nunito 11/700 with BrandColors.accentDeep', (
      tester,
    ) async {
      final s = VelvetText.link();
      expect(s.fontSize, 11.0);
      expect(s.fontWeight, FontWeight.w700);
      expect(s.color, BrandColors.accentDeep);
    });

    testWidgets(
      'feedback uses Nunito 11/700 height 1.4 with caller-supplied color',
      (tester) async {
        final s = VelvetText.feedback(BrandColors.error);
        expect(s.fontSize, 11.0);
        expect(s.fontWeight, FontWeight.w700);
        expect(s.height, 1.4);
        expect(s.color, BrandColors.error);
      },
    );

    testWidgets(
      'feedbackAccentXs has fontSize 11, fontWeight w700, color accentDeep',
      (tester) async {
        final s = VelvetText.feedbackAccentXs;
        expect(s.fontSize, 11.0);
        expect(s.fontWeight, FontWeight.w700);
        expect(s.color, BrandColors.accentDeep);
      },
    );

    testWidgets(
      'feedbackMutedXs has fontSize 11, fontWeight w700, color muted',
      (tester) async {
        final s = VelvetText.feedbackMutedXs;
        expect(s.fontSize, 11.0);
        expect(s.fontWeight, FontWeight.w700);
        expect(s.color, BrandColors.muted);
      },
    );

    testWidgets('feedbackMutedNote overrides base to 11 sp / muted, '
        'inheriting w700 and height 1.4 from the feedback base', (
      tester,
    ) async {
      // Pre-cached variant for the locationNote sub-row on the identity
      // card. Verifies the copyWith composition: size + color are overridden
      // while the base weight (w700) and line-height (1.4) carry through.
      final s = VelvetText.feedbackMutedNote;
      expect(s.fontSize, 11.0);
      expect(s.color, BrandColors.muted);
      expect(s.fontWeight, FontWeight.w700);
      expect(s.height, 1.4);
    });
  });

  // ── velvetTheme textTheme fontFamily assertions ──────────────────────────
  //
  // Uses the same pump-through-MaterialApp pattern as app_theme_test.dart
  // (Phase 1.1) to drain the async font load before assertions run.
  group('velvetTheme textTheme fontFamily', () {
    Future<TextTheme> pumpTheme(WidgetTester tester) async {
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

    testWidgets('bodyLarge starts with Nunito', (tester) async {
      final theme = await pumpTheme(tester);
      expect(theme.bodyLarge!.fontFamily, startsWith('Nunito'));
    });

    testWidgets('bodyMedium starts with Nunito', (tester) async {
      final theme = await pumpTheme(tester);
      expect(theme.bodyMedium!.fontFamily, startsWith('Nunito'));
    });

    testWidgets('labelMedium starts with Nunito', (tester) async {
      final theme = await pumpTheme(tester);
      expect(theme.labelMedium!.fontFamily, startsWith('Nunito'));
    });
  });
}
