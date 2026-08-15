// Phase 15.5 — Structural widget tests for [PeriodRangePicker].
//
// Pins the two behaviours the apply flow depends on:
//   • past days (before `firstSelectableDay`) are non-tappable — tapping one
//     does NOT begin a selection, so the «Зберегти» CTA stays inert;
//   • tapping a start day then an end day, then «Зберегти», pops the expected
//     `DateTimeRange` via the go_router `context.pop` extension.
//
// Finders use `Key`s for the chrome (the save / back buttons) and the day
// `Semantics` label for the calendar cells (the cells carry no per-day Key);
// waits use `pumpAndSettle` (M6). The picker is pumped inside a GoRouter so its
// `context.pop(range)` resolves (M2/M6 compliant, hermetic — no providers).

import 'package:beautica_mobile/shared/widgets/period_range_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Whether the save CTA's CLOSEST `IgnorePointer` ancestor is inert. The picker
/// nests the save button in `Opacity > IgnorePointer > NeumorphicButton`, so the
/// first ancestor match is the gate we care about.
bool _saveCtaIgnoring(WidgetTester tester) {
  final ignore = tester
      .widgetList<IgnorePointer>(
        find.ancestor(
          of: find.byKey(const Key('btn-range-picker-save')),
          matching: find.byType(IgnorePointer),
        ),
      )
      .first;
  return ignore.ignoring;
}

const _strings = PeriodRangePickerStrings(
  title: 'Виберіть період',
  emptyHint: 'Оберіть період',
  saveLabel: 'Зберегти',
  backSemantic: 'Назад',
  weekdayShort: <String>['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'],
  monthNames: <String>[
    'Січень',
    'Лютий',
    'Березень',
    'Квітень',
    'Травень',
    'Червень',
    'Липень',
    'Серпень',
    'Вересень',
    'Жовтень',
    'Листопад',
    'Грудень',
  ],
);

void main() {
  // Anchor the picker on June 2024; first selectable day = 10 Jun 2024, so
  // 1–9 Jun are past (frozen) and 10 Jun onward is tappable.
  final firstMonth = DateTime(2024, 6);
  final firstSelectable = DateTime(2024, 6, 10);

  /// Pumps the picker; the popped range is captured into [popped]. [clock]
  /// overrides the "today" ring's anchor (defaults to production's
  /// `DateTime.now`, Kyiv-anchored via [PeriodRangePicker.clock]) — needed by
  /// the D2 parity group below, which must pin a specific day as "today".
  Future<void> pumpPicker(
    WidgetTester tester, {
    required void Function(DateTimeRange?) onPopped,
    DateTime Function()? clock,
  }) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('open-picker'),
                  onPressed: () async {
                    final range = await showModalBottomSheet<DateTimeRange>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => SizedBox(
                        height: 700,
                        child: PeriodRangePicker(
                          firstMonth: firstMonth,
                          firstSelectableDay: firstSelectable,
                          strings: _strings,
                          clock: clock,
                        ),
                      ),
                    );
                    onPopped(range);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-picker')));
    await tester.pumpAndSettle();
  }

  /// Finds the tappable day cell for [day] in the FIRST rendered month (the
  /// anchor month) by matching the day-number `Text` — scoped to the first
  /// match so later months' identical numbers don't collide. The `Text` sits
  /// inside the cell's `GestureDetector`, so tapping its centre hits the
  /// tap target.
  Finder dayCell(int day) => find
      .descendant(
        of: find.byType(PeriodRangePicker),
        matching: find.text('$day'),
      )
      .first;

  testWidgets('a past day is non-tappable — tapping it does not start a '
      'selection and the save CTA stays inert', (tester) async {
    DateTimeRange? popped;
    var popInvoked = false;
    await pumpPicker(
      tester,
      onPopped: (r) {
        popped = r;
        popInvoked = true;
      },
    );

    // 5 Jun 2024 is before the first selectable day (10 Jun) → frozen.
    await tester.tap(dayCell(5), warnIfMissed: false);
    await tester.pumpAndSettle();

    // No selection began → the save CTA is wrapped in an inert IgnorePointer.
    expect(_saveCtaIgnoring(tester), isTrue);

    // Tapping the inert save CTA does nothing — the sheet has not popped.
    await tester.tap(
      find.byKey(const Key('btn-range-picker-save')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(popInvoked, isFalse);
    expect(popped, isNull);
  });

  testWidgets('tapping a start then an end day, then Зберегти, pops the '
      'expected DateTimeRange', (tester) async {
    DateTimeRange? popped;
    await pumpPicker(tester, onPopped: (r) => popped = r);

    // Start 12 Jun, end 20 Jun (both within the anchor month, both selectable).
    await tester.tap(dayCell(12));
    await tester.pumpAndSettle();
    await tester.tap(dayCell(20));
    await tester.pumpAndSettle();

    // The CTA is now active.
    expect(_saveCtaIgnoring(tester), isFalse);

    await tester.tap(find.byKey(const Key('btn-range-picker-save')));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.start, DateTime(2024, 6, 12));
    expect(popped!.end, DateTime(2024, 6, 20));
  });

  // mobile-qa (calendar-consolidation cross-surface parity audit) —
  // [PeriodRangePicker] forked ~250 lines of `month_calendar.dart` before
  // this consolidation, so it is the highest-risk surface for D1–D4 having
  // been fixed in the shared primitive but never actually reaching this
  // caller. `month_calendar_test.dart` already pins D1–D4 against
  // `MonthCalendar`; these two groups pin the two of D1–D4 that apply here
  // (D2 — this picker renders no density dots, so D1 does not apply) against
  // THIS widget specifically, by the same ground-truth measurement technique
  // (`tester.getCenter`/decoration inspection) — a regenerated golden proves
  // nothing here either (`feedback_golden_not_acceptance`).
  group('cross-surface parity — today ring vs. selection precedence (D2)', () {
    // The shared `CalendarDayCell` badge is a `Container(height: 38, width:
    // 38, decoration: ring)` — `decoration == null` iff the ring is
    // suppressed. `dayCell(day)` (this file's own helper, above) resolves the
    // day-NUMBER `Text` itself, and that `Text` is the badge `Container`'s
    // CHILD — so the badge is an ANCESTOR of `dayCell(day)`, not a
    // descendant (unlike `month_calendar_test.dart`'s identically-named
    // helper, whose `cell` is the outer keyed Semantics/GestureDetector
    // wrapping the whole cell, making the badge a genuine descendant there).
    // `.first` because `find.ancestor` also matches the `SizedBox`-wrapped
    // `centered` ancestor chain's own intermediate boxes before reaching the
    // one 38x38-constrained `Container` — the innermost/closest match.
    Finder badgeContainer(Finder cell) => find
        .ancestor(
          of: cell,
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is Container &&
                w.constraints ==
                    const BoxConstraints.tightFor(width: 38, height: 38),
          ),
        )
        .first;

    testWidgets('today ring renders when today is NOT selected', (
      tester,
    ) async {
      // "Today" = 15 Jun 2024 (selectable — after firstSelectable 10 Jun);
      // the picker's own selection (12→13 Jun) never touches it.
      await pumpPicker(
        tester,
        onPopped: (_) {},
        clock: () => DateTime.utc(2024, 6, 15, 12),
      );
      await tester.tap(dayCell(12));
      await tester.pumpAndSettle();
      await tester.tap(dayCell(13));
      await tester.pumpAndSettle();

      final Container badge = tester.widget<Container>(
        badgeContainer(dayCell(15)),
      );
      expect(
        badge.decoration,
        isNotNull,
        reason:
            'today (15 Jun), unselected, must render the camel ring — same '
            'contract as MonthCalendar',
      );
    });

    testWidgets('today ring is SUPPRESSED when today is ALSO the picked start '
        'endpoint (no double disc)', (tester) async {
      // "Today" IS the day about to be tapped as the range start.
      await pumpPicker(
        tester,
        onPopped: (_) {},
        clock: () => DateTime.utc(2024, 6, 15, 12),
      );
      await tester.tap(dayCell(15));
      await tester.pumpAndSettle();

      final Container badge = tester.widget<Container>(
        badgeContainer(dayCell(15)),
      );
      expect(
        badge.decoration,
        isNull,
        reason:
            'a selected (start-endpoint) today must not ALSO paint the '
            'ring — the recessed trough + bold camel number already carry '
            'the "picked" signal; this is the exact mud the D2 fix in '
            'calendar_grid.dart exists to prevent, proven here against '
            'PeriodRangePicker specifically, not just MonthCalendar',
      );
    });
  });

  // D4 — the weekday header/day-grid column-alignment invariant, pinned
  // against PeriodRangePicker's OWN `_weekdayHeaderBar()` composition (a
  // `Padding(horizontal: VelvetSpacing.md)` wrapping the shared, self-
  // padding-free `CalendarWeekdayBar` — see that file's comment). Before the
  // consolidation this picker's header used a DIFFERENT inset
  // (`VelvetSpacing.md + 2`) than its own grid, an 18dp-vs-16dp mismatch a
  // golden would not have caught either (both were "the current render").
  group('cross-surface parity — weekday header/grid column alignment (D4)', () {
    testWidgets(
      'the composed weekday header aligns with the day-grid edge columns',
      (tester) async {
        await pumpPicker(tester, onPopped: (_) {});

        // June 2024: the 1st is a Saturday, so `leadingBlanks = 5` and the
        // grid's SECOND week row (guaranteed fully populated, mirroring
        // `month_calendar_test.dart`'s identical derivation) starts at
        // Monday-the-3rd.
        const int mondayDay = 3;
        const int sundayDay = 9;

        // Located via `_strings.weekdayShort` — the SAME source the widget
        // itself renders (`_weekdayHeaderBar()` passes `widget.strings
        // .weekdayShort` straight to `CalendarWeekdayBar`) — never a fresh
        // Cyrillic literal (M2/`forbid_cyrillic_finder.sh`): a hardcoded copy
        // here would duplicate `_strings` and drift the moment either one
        // changes, defeating the point of sourcing both from one constant.
        final double mondayHeaderX = tester
            .getCenter(find.text(_strings.weekdayShort[0]))
            .dx;
        final double sundayHeaderX = tester
            .getCenter(find.text(_strings.weekdayShort[6]))
            .dx;
        final double mondayGridX = tester.getCenter(dayCell(mondayDay)).dx;
        final double sundayGridX = tester.getCenter(dayCell(sundayDay)).dx;

        expect(
          mondayHeaderX,
          closeTo(mondayGridX, 1.5),
          reason:
              'Monday ("Пн") weekday label must sit directly above the '
              'Monday day-number column — a header/grid inset mismatch '
              'drifts the label off the column, worst at the edge columns '
              '(the pre-consolidation bug: VelvetSpacing.md + 2 header vs. '
              'VelvetSpacing.md grid)',
        );
        expect(sundayHeaderX, closeTo(sundayGridX, 1.5));
      },
    );
  });
}
