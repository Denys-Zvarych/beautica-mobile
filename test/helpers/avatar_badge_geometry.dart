// Phase 367 (layout fix) — geometry guard for the own-avatar camera badge vs
// the header text column beside it.
//
// The 367 port dropped the header's spacer on the assumption that the
// editor's 18 dp badge overhang "already" separated ring and text. It did not:
// the badge sits flush with the editor's box, so wherever the text column grew
// down to the badge (320–360 dp, text ×1.3) the badge and its 12 dp-blur
// shadow ran into the pin / salon rows. Goldens caught it once; this guards it
// numerically, independent of any baseline.

import 'dart:math' as math;

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The minimum clear gap (dp) between the badge's box and the text column.
const double kMinBadgeTextGap = 12;

/// The badge's shadow reach: the largest blur of its resting shadow pair.
final double kBadgeShadowBlur = VelvetShadows.extrudedSmall
    .map((BoxShadow s) => s.blurRadius)
    .reduce(math.max);

/// Asserts that the camera badge inside the editor keyed [editorKey] —
/// inflated by its shadow blur — does not intersect the header text column
/// (the [Expanded] that holds the widget keyed [nameKey]), and that the two
/// are at least [kMinBadgeTextGap] apart horizontally.
///
/// [badgeKey] (Phase 369, additive) names the badge for an editor that keys
/// its own (the salon logo's `salon-logo-edit-badge`); the default is the
/// avatar editor's.
void expectBadgeClearsTextColumn(
  WidgetTester tester, {
  required Key editorKey,
  required Key nameKey,
  Key badgeKey = const Key('avatar-edit-badge'),
}) {
  final Finder badge = find.descendant(
    of: find.byKey(editorKey),
    matching: find.byKey(badgeKey),
  );
  expect(badge, findsOneWidget);
  final Finder column = find
      .ancestor(of: find.byKey(nameKey), matching: find.byType(Expanded))
      .first;

  final Rect badgeRect = tester.getRect(badge);
  final Rect columnRect = tester.getRect(column);
  final Rect shadowRect = badgeRect.inflate(kBadgeShadowBlur);

  expect(
    shadowRect.overlaps(columnRect),
    isFalse,
    reason:
        'badge $badgeRect inflated by its ${kBadgeShadowBlur}dp shadow blur '
        '($shadowRect) must not intersect the text column $columnRect',
  );
  expect(
    columnRect.left - badgeRect.right,
    greaterThanOrEqualTo(kMinBadgeTextGap),
    reason:
        'badge→text gap must be ≥ ${kMinBadgeTextGap}dp '
        '(badge right ${badgeRect.right}, column left ${columnRect.left})',
  );
}
