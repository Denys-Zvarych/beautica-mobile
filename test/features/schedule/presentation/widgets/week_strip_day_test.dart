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

/// Fixed day number for the pumped cell; reused by [_numberColor] to locate
/// the day-number [Text] by its `data`.
const int _kDay = 13;

/// Pumps a single [WeekStripDay] cell with the given branch-selecting flags.
/// [working] and [selected] steer the disc decoration; [inMonth] and [past]
/// steer the day-number color under test (regression group). Defaults keep the
/// disc-decoration tests unchanged (in-month, not past).
Future<void> _pumpDay(
  WidgetTester tester, {
  required bool working,
  required bool selected,
  bool inMonth = true,
  bool past = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: WeekStripDay(
            weekdayLabel: 'Пн',
            day: _kDay,
            selected: selected,
            working: working,
            inMonth: inMonth,
            past: past,
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

/// Resolves the rendered color of the day-NUMBER [Text] (the one whose `data`
/// is the day-of-month). Read structurally from the resolved [TextStyle.color]
/// rather than by pixel/golden so the assertion pins the exact `numberColor`
/// branch that fired.
Color? _numberColor(WidgetTester tester) {
  final Text number = tester.widget<Text>(find.text('$_kDay'));
  return number.style?.color;
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

  // Regression: the day-NUMBER color must depend on `selected`/`past` only —
  // NOT on `inMonth`. The old rule greyed any out-of-month cell to
  // BrandColors.faint BEFORE checking `past`, so a future out-of-month
  // spillover working day (e.g. Mon 29 / Tue 30 Jun in a July-anchored strip)
  // rendered greyed, reading as past/disabled. The `!inMonth → faint` branch
  // was removed; these tests pin the corrected mapping. Case (a) is RED against
  // the old rule (faint ≠ text) and GREEN now.
  group('WeekStripDay day-number color', () {
    testWidgets(
      'future out-of-month working day → number in BrandColors.text (not faint)',
      (WidgetTester tester) async {
        // The key regression case: spillover working day from the next month,
        // genuinely in the future. Old rule painted this faint; fix paints text.
        await _pumpDay(
          tester,
          working: true,
          selected: false,
          inMonth: false,
          past: false,
        );

        expect(_numberColor(tester), BrandColors.text);
        expect(
          _numberColor(tester),
          isNot(BrandColors.faint),
          reason: 'out-of-month must NOT grey the day number (the fixed bug)',
        );
      },
    );

    testWidgets('genuinely past day → number in BrandColors.muted', (
      WidgetTester tester,
    ) async {
      await _pumpDay(
        tester,
        working: false,
        selected: false,
        inMonth: true,
        past: true,
      );

      expect(_numberColor(tester), BrandColors.muted);
    });

    testWidgets('selected day → number in BrandColors.accentDeep', (
      WidgetTester tester,
    ) async {
      // selected wins regardless of past/inMonth.
      await _pumpDay(
        tester,
        working: true,
        selected: true,
        inMonth: false,
        past: true,
      );

      expect(_numberColor(tester), BrandColors.accentDeep);
    });
  });
}
