// Phase 1.2 — Manrope typography wiring tests.
//
// Verifies that [lightTheme] exposes the locked Beautica type scale via the
// `_textTheme` helper in `app_theme.dart`. All six roles the design system
// exercises are parametrised below so a regression in any single size or
// weight surfaces as a named expectation failure instead of an opaque
// "fontSize wrong" crash. A separate dark-theme spot check guards the
// `_textTheme(Brightness)` helper's parity contract — the body text scale
// must look identical regardless of brightness.
//
// Font-family is intentionally NOT asserted here: `GoogleFonts.manrope*`
// returns a synthesized family name (e.g. `Manrope_regular`) and the cached
// asset name can change between `google_fonts` minor versions. Visual
// confirmation that text renders in Manrope (not system Roboto) is part of
// the manual emulator check in the phase doc acceptance criteria.

import 'package:beautica_mobile/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One row of the canonical Beautica type scale.
///
/// `height` and `letterSpacing` are nullable because not every role pins
/// them — only the ones the design system explicitly locks. A `null` here
/// means "do not assert" (the value falls through to Material 3 defaults).
class _TypeRoleSpec {
  const _TypeRoleSpec({
    required this.name,
    required this.style,
    required this.fontSize,
    required this.fontWeight,
    this.height,
    this.letterSpacing,
  });
  final String name;
  final TextStyle Function(TextTheme) style;
  final double fontSize;
  final FontWeight fontWeight;
  final double? height;
  final double? letterSpacing;
}

final List<_TypeRoleSpec> _roles = <_TypeRoleSpec>[
  _TypeRoleSpec(
    name: 'displayLarge',
    style: (t) => t.displayLarge!,
    fontSize: 57,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.25,
  ),
  _TypeRoleSpec(
    name: 'headlineLarge',
    style: (t) => t.headlineLarge!,
    fontSize: 32,
    fontWeight: FontWeight.w600,
  ),
  _TypeRoleSpec(
    name: 'titleLarge',
    style: (t) => t.titleLarge!,
    fontSize: 22,
    fontWeight: FontWeight.w600,
  ),
  _TypeRoleSpec(
    name: 'bodyLarge',
    style: (t) => t.bodyLarge!,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  ),
  _TypeRoleSpec(
    name: 'bodyMedium',
    style: (t) => t.bodyMedium!,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
  ),
  _TypeRoleSpec(
    name: 'labelLarge',
    style: (t) => t.labelLarge!,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  ),
];

void main() {
  testWidgets('lightTheme covers all six brand text roles', (
    WidgetTester tester,
  ) async {
    late TextTheme textTheme;

    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme(),
        home: Builder(
          builder: (BuildContext ctx) {
            textTheme = Theme.of(ctx).textTheme;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    for (final _TypeRoleSpec spec in _roles) {
      final TextStyle s = spec.style(textTheme);
      expect(s.fontSize, spec.fontSize, reason: '${spec.name}.fontSize');
      expect(s.fontWeight, spec.fontWeight, reason: '${spec.name}.fontWeight');
      if (spec.height != null) {
        expect(s.height, spec.height, reason: '${spec.name}.height');
      }
      if (spec.letterSpacing != null) {
        expect(
          s.letterSpacing,
          spec.letterSpacing,
          reason: '${spec.name}.letterSpacing',
        );
      }
    }
  });

  testWidgets('darkTheme bodyLarge uses Manrope 16/1.5', (
    WidgetTester tester,
  ) async {
    // Sanity check for the shared `_textTheme(Brightness)` helper — body
    // text dimensions must be brightness-agnostic. We only assert one role
    // because the helper applies the same `copyWith` block to both
    // brightnesses, so light-theme coverage transitively proves dark
    // parity for the remaining roles.
    late TextStyle style;

    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme(),
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
}
