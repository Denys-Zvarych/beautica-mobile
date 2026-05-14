// Phase 1.2 — Manrope typography wiring tests.
//
// Verifies that [lightTheme] exposes the locked Beautica type scale via the
// `_textTheme` helper in `app_theme.dart`. The two body styles are the
// highest-traffic roles on every screen (forms, lists, descriptions), so a
// regression in either size or line-height is the fastest way to spot the
// theme silently falling back to the Material 3 defaults.
//
// Font-family is intentionally NOT asserted here: `GoogleFonts.manrope*`
// returns a synthesized family name (e.g. `Manrope_regular`) and the cached
// asset name can change between `google_fonts` minor versions. Visual
// confirmation that text renders in Manrope (not system Roboto) is part of
// the manual emulator check in the phase doc acceptance criteria.

import 'package:beautica_mobile/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bodyLarge uses Manrope 16/1.5', (WidgetTester tester) async {
    late TextStyle style;

    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme(),
        home: Builder(
          builder: (BuildContext ctx) {
            style = Theme.of(ctx).textTheme.bodyLarge!;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(style.fontSize, 16);
    expect(style.height, 1.5);
    expect(style.fontWeight, FontWeight.w400);
  });

  testWidgets('bodyMedium uses Manrope 14/1.4', (WidgetTester tester) async {
    late TextStyle style;

    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme(),
        home: Builder(
          builder: (BuildContext ctx) {
            style = Theme.of(ctx).textTheme.bodyMedium!;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(style.fontSize, 14);
    expect(style.height, 1.4);
    expect(style.fontWeight, FontWeight.w400);
  });
}
