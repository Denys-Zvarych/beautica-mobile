// Phase 1.1 — Material 3 theme wiring tests.
//
// Verifies that both light and dark theme factories expose the locked brand
// colour role overrides via `ColorScheme.copyWith` — specifically `bliss` as
// `secondary` and `cherry` as `error`. These two roles are the most visible
// brand surfaces (CTA buttons, validation/destructive states), so a
// regression here means the brand identity is drifting.

import 'package:beautica_mobile/core/theme/app_theme.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lightTheme exposes bliss as secondary and cherry as error', (
    WidgetTester tester,
  ) async {
    late ColorScheme scheme;

    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme(),
        home: Builder(
          builder: (BuildContext ctx) {
            scheme = Theme.of(ctx).colorScheme;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(scheme.brightness, Brightness.light);
    expect(scheme.secondary, BrandColors.bliss);
    expect(scheme.secondaryContainer, BrandColors.sunshine);
    expect(scheme.tertiary, BrandColors.sand);
    expect(scheme.error, BrandColors.cherry);
  });

  testWidgets('darkTheme exposes bliss as secondary and cherry as error', (
    WidgetTester tester,
  ) async {
    late ColorScheme scheme;

    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme(),
        home: Builder(
          builder: (BuildContext ctx) {
            scheme = Theme.of(ctx).colorScheme;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(scheme.brightness, Brightness.dark);
    expect(scheme.secondary, BrandColors.bliss);
    // Dark theme intentionally lets the seed derive `secondaryContainer`
    // (sunshine is too pale to read against a dark surface) — assert the
    // override was NOT applied so the omission stays load-bearing.
    expect(scheme.secondaryContainer, isNot(BrandColors.sunshine));
    expect(scheme.tertiary, BrandColors.sand);
    expect(scheme.error, BrandColors.cherry);
  });
}
