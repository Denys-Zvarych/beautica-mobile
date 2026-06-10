// Phase 15.2 — Widget tests for [WeekStripDay]'s disc decoration.
//
// Guards the THREE camel-disc states the week date-strip now renders, after
// `WeekStripDay` gained a required `working` flag so a non-selected working day
// is drawn in a camel circle matching the top "working week" card's active
// [WeekdayPill] (same accent alphas), while the selected day keeps its stronger
// treatment and a non-working / non-selected day shows no circle at all:
//
//   1. working: true,  selected: false → fill accent α0.32 + non-null Border
//   2. working: false, selected: false → transparent fill, null border (no disc)
//   3. selected: true (any working)    → fill accent α0.35 (selected wins)
//
// The screen-level goldens cover the full strip pixel-for-pixel, but goldens
// alone can't *assert* which decoration branch fired for a given (working,
// selected) pair — these tests pin that mapping explicitly so a future refactor
// of the branch order/alphas fails loudly here, not silently in a regenerated
// golden (memory: "Golden is not acceptance for visual bugs").
//
// [WeekStripDay] is a pure presentational widget (no Riverpod), so it is pumped
// directly inside a bare MaterialApp. The disc is found robustly as the lone
// AnimatedContainer whose BoxDecoration is a circle.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/schedule_widgets.dart';

/// Pumps a single [WeekStripDay] cell with the given branch-selecting flags.
/// All other params are fixed defaults — only [working] and [selected] steer
/// the disc decoration under test.
Future<void> _pumpDay(
  WidgetTester tester, {
  required bool working,
  required bool selected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: WeekStripDay(
            weekdayLabel: 'Пн',
            day: 13,
            selected: selected,
            working: working,
            inMonth: true,
            hasOverride: false,
            onTap: () {},
            pastSemanticLabel: 'Пн 13, минулий день',
            plainSemanticLabel: 'Пн 13',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The disc is the only [AnimatedContainer] in [WeekStripDay] whose decoration
/// is a circle. Resolve it structurally rather than by position so the finder
/// survives sibling additions.
BoxDecoration _discDecoration(WidgetTester tester) {
  final Iterable<AnimatedContainer> circles = tester
      .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
      .where(
        (AnimatedContainer c) =>
            c.decoration is BoxDecoration &&
            (c.decoration! as BoxDecoration).shape == BoxShape.circle,
      );
  expect(circles, hasLength(1), reason: 'expected exactly one circular disc');
  return circles.first.decoration! as BoxDecoration;
}

void main() {
  group('WeekStripDay disc decoration', () {
    testWidgets(
      'working & not selected → camel circle: fill accent α0.32 with a border',
      (WidgetTester tester) async {
        await _pumpDay(tester, working: true, selected: false);

        final BoxDecoration disc = _discDecoration(tester);

        expect(disc.color, BrandColors.accent.withValues(alpha: 0.32));
        expect(disc.border, isNotNull);
      },
    );

    testWidgets(
      'not working & not selected → no circle: transparent fill, null border',
      (WidgetTester tester) async {
        await _pumpDay(tester, working: false, selected: false);

        final BoxDecoration disc = _discDecoration(tester);

        expect(disc.color, Colors.transparent);
        expect(disc.border, isNull);
      },
    );

    testWidgets(
      'selected wins over working → fill accent α0.35 (selected treatment)',
      (WidgetTester tester) async {
        // working is true here too, to prove the selected branch takes
        // precedence over the working branch regardless of the working flag.
        await _pumpDay(tester, working: true, selected: true);

        final BoxDecoration disc = _discDecoration(tester);

        expect(disc.color, BrandColors.accent.withValues(alpha: 0.35));
        expect(disc.border, isNotNull);
      },
    );
  });
}
