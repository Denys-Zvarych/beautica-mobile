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
/// steer the day-number color under test (regression group); [hasOverride]
/// steers the under-number dot regression group (it must NO LONGER drive the
/// dot — only [selected] does). Defaults keep the existing disc-decoration and
/// day-number tests unchanged (in-month, not past, no override).
Future<void> _pumpDay(
  WidgetTester tester, {
  required bool working,
  required bool selected,
  bool inMonth = true,
  bool past = false,
  bool hasOverride = false,
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
            hasOverride: hasOverride,
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

/// Resolves the color of the under-number dot — the small 5×5 plain [Container]
/// (NOT the 38px [AnimatedContainer] disc) whose decoration is a circle. The 5px
/// space is reserved on every day so the number's baseline never shifts; the dot
/// is "shown" only when its color is the saturated [BrandColors.accentDeep] and
/// "hidden" (reserved but invisible) when its color is [Colors.transparent].
///
/// Distinguished from the disc structurally: the disc is an [AnimatedContainer];
/// the dot is a bare [Container] with a 5×5 [BoxConstraints] and a circular
/// [BoxDecoration]. Resolving by these intrinsic properties (not by position)
/// keeps the finder robust against sibling additions.
Color? _dotColor(WidgetTester tester) {
  final Iterable<Container> dots = tester
      .widgetList<Container>(find.byType(Container))
      .where((Container c) {
        final Decoration? d = c.decoration;
        if (d is! BoxDecoration || d.shape != BoxShape.circle) return false;
        final BoxConstraints? cons = c.constraints;
        return cons != null && cons.maxWidth == 5 && cons.maxHeight == 5;
      });
  expect(
    dots,
    hasLength(1),
    reason: 'expected exactly one 5x5 circular under-number dot Container',
  );
  return (dots.first.decoration! as BoxDecoration).color;
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

  // Regression: the under-number dot marks the SELECTED day ONLY. The previous
  // rule painted the dot on a NON-selected day that carried a schedule override
  // (`hasOverride && !selected ? accentDeep : transparent`); the user asked for
  // the dot to mark selection alone, so the new rule is `selected ? accentDeep :
  // transparent` and `hasOverride` no longer drives the dot at all.
  //
  // RED→GREEN proof: case (b) `selected: false, hasOverride: true` was the exact
  // input that lit the dot under the OLD rule (accentDeep) — it now asserts
  // transparent, so it FAILS against `hasOverride && !selected` and PASSES now.
  // The 5px space stays reserved in every case (no baseline shift), so the dot
  // is always present as a widget; only its color changes.
  group('WeekStripDay under-number dot marks the selected day only', () {
    testWidgets('selected day → dot is accentDeep (visible)', (
      WidgetTester tester,
    ) async {
      await _pumpDay(tester, working: true, selected: true);

      expect(_dotColor(tester), BrandColors.accentDeep);
    });

    testWidgets(
      'NOT selected but hasOverride → dot is transparent (override no longer '
      'drives the dot — RED on the old hasOverride && !selected rule)',
      (WidgetTester tester) async {
        await _pumpDay(
          tester,
          working: true,
          selected: false,
          hasOverride: true,
        );

        expect(
          _dotColor(tester),
          Colors.transparent,
          reason: 'an overridden, non-selected day must NOT show the dot',
        );
      },
    );

    testWidgets(
      'NOT selected, no override → dot is transparent (reserved but hidden)',
      (WidgetTester tester) async {
        await _pumpDay(
          tester,
          working: true,
          selected: false,
          hasOverride: false,
        );

        expect(_dotColor(tester), Colors.transparent);
      },
    );

    testWidgets(
      'selected wins even when hasOverride is true → dot is accentDeep',
      (WidgetTester tester) async {
        await _pumpDay(
          tester,
          working: true,
          selected: true,
          hasOverride: true,
        );

        expect(_dotColor(tester), BrandColors.accentDeep);
      },
    );
  });
}
