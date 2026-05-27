// Phase 1.2 — `AppSpacing` token unit test.
//
// Guard rail against hand-edit typo regressions on the canonical
// seven-token spacing scale. The values are locked by
// `ARCHITECTURE-mobile.md` § 9 and consumed everywhere via
// `lib/core/theme/app_spacing.dart`; nudging any number here will cascade
// to every padding/margin/gap in the app, so we pin them explicitly.
//
// Uses plain `test` (not `testWidgets`) — these are compile-time constants,
// no widget tree, no localisation, no theme involved.

import 'package:beautica_mobile/core/theme/app_spacing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppSpacing exposes the seven-token canonical scale', () {
    expect(AppSpacing.xxs, 4);
    expect(AppSpacing.xs, 8);
    expect(AppSpacing.sm, 12);
    expect(AppSpacing.md, 16);
    expect(AppSpacing.lg, 24);
    expect(AppSpacing.xl, 32);
    expect(AppSpacing.xxl, 48);
  });
}
