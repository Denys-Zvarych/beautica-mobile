// Phase 14.14 — Widget tests for MonthCalendar's generic day-availability
// gating.
//
// [MonthCalendar] itself stays generic (its `isAvailable` callback can
// express any policy) — see the widget's file header. These tests exercise
// that contract directly, independent of the real working-days data source
// wired up in `SlotDateScreen` (covered separately in `slot_picker_test.dart`
// and `working_days_notifier_test.dart`):
//   1. A day the caller marks available renders tappable and invokes
//      `onSelectDay` with the exact date.
//   2. A day the caller marks unavailable renders WITHOUT a tap handler
//      (no `GestureDetector`) and never invokes `onSelectDay`.

import 'package:beautica_mobile/features/booking/presentation/widgets/month_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  final DateTime visibleMonth = DateTime(2026, 7);
  final DateTime today = DateTime(2026, 7, 1);

  testWidgets(
    'a day with isAvailable=true is tappable and reports the exact date',
    (tester) async {
      DateTime? selected;

      await tester.pumpApp(
        Scaffold(
          body: MonthCalendar(
            visibleMonth: visibleMonth,
            today: today,
            selected: null,
            isAvailable: (DateTime day) => day.day == 15,
            onSelectDay: (DateTime day) => selected = day,
            onPrevMonth: null,
            onNextMonth: null,
          ),
        ),
      );

      final Finder cell = find.byKey(const Key('booking-calendar-day-15'));
      expect(cell, findsOneWidget);
      expect(
        find.descendant(of: cell, matching: find.byType(GestureDetector)),
        findsOneWidget,
      );

      await tester.tap(cell);
      await tester.pumpAndSettle();

      expect(selected, DateTime(2026, 7, 15));
    },
  );

  testWidgets(
    'a day with isAvailable=false renders without a tap handler and never '
    'invokes onSelectDay',
    (tester) async {
      bool tapped = false;

      await tester.pumpApp(
        Scaffold(
          body: MonthCalendar(
            visibleMonth: visibleMonth,
            today: today,
            selected: null,
            // Day 10 is the sole unavailable day (e.g. a non-working day
            // under the Phase 14.14 gate) — every other day in the month
            // stays available so the finder below is unambiguous.
            isAvailable: (DateTime day) => day.day != 10,
            onSelectDay: (_) => tapped = true,
            onPrevMonth: null,
            onNextMonth: null,
          ),
        ),
      );

      final Finder cell = find.byKey(const Key('booking-calendar-day-10'));
      expect(cell, findsOneWidget);

      // The disabled `_DayCell` branch renders a bare `Semantics` with no
      // `GestureDetector` child — mirrors the `info.onTap == null` path.
      expect(
        find.descendant(of: cell, matching: find.byType(GestureDetector)),
        findsNothing,
      );

      await tester.tap(cell, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tapped, isFalse);
    },
  );

  group('CalendarWeekdayBar / day-grid column alignment (regression)', () {
    // BUG: `CalendarWeekdayBar` used to self-pad at `VelvetSpacing.md + 2`
    // (18dp/side, copied from `period_range_picker.dart`'s
    // `_weekdayHeaderBar()`) while `MonthCalendar.build()`'s own outer
    // `Padding` — the effective inset for `_MonthGrid` beneath it — uses
    // `VelvetSpacing.lg` (24dp/side). A 6dp/side mismatch doesn't move the
    // MIDDLE weekday column at all (its center sits on the shared midline
    // regardless of inset), but drifts the two EDGE columns (Monday/Sunday)
    // increasingly as width grows — a golden test of the widget alone would
    // just re-bless whatever the current render is, so this asserts the
    // actual geometric invariant: each header label's horizontal center must
    // coincide with its day-grid column's horizontal center.
    //
    // Pumps `CalendarWeekdayBar` directly above `MonthCalendar` in a bare
    // `Column`, mirroring `slot_picker_screen.dart`'s real (unwrapped)
    // composition of the two widgets — see that file's `build()` comment at
    // its `CalendarWeekdayBar` usage.
    Future<void> expectHeaderAlignsWithGrid(
      WidgetTester tester, {
      required double width,
    }) async {
      final DateTime visibleMonth = DateTime(2026, 7);
      final int leadingBlanks =
          DateTime(visibleMonth.year, visibleMonth.month, 1).weekday - 1;
      // Grid-cell index 7 starts the SECOND week row, which is guaranteed to
      // be fully populated (no blank leading cells) no matter which weekday
      // the 1st falls on (`leadingBlanks` is at most 6) — so column 0
      // (Monday) and column 6 (Sunday) of this row always resolve to real,
      // in-month day numbers. See `_MonthGrid.build()`'s `cellDays` list.
      final int mondayDay = 8 - leadingBlanks;
      final int sundayDay = 14 - leadingBlanks;

      await tester.pumpApp(
        Scaffold(
          body: Column(
            children: <Widget>[
              const CalendarWeekdayBar(),
              MonthCalendar(
                visibleMonth: visibleMonth,
                today: visibleMonth,
                selected: null,
                isAvailable: (_) => true,
                onSelectDay: (_) {},
                onPrevMonth: null,
                onNextMonth: null,
              ),
            ],
          ),
        ),
        width: width,
      );
      await tester.pumpAndSettle();

      final double mondayHeaderX = tester.getCenter(find.text('пн')).dx;
      final double sundayHeaderX = tester.getCenter(find.text('нд')).dx;
      final double mondayGridX = tester
          .getCenter(find.byKey(Key('booking-calendar-day-$mondayDay')))
          .dx;
      final double sundayGridX = tester
          .getCenter(find.byKey(Key('booking-calendar-day-$sundayDay')))
          .dx;

      expect(
        mondayHeaderX,
        closeTo(mondayGridX, 1.5),
        reason:
            'Monday ("пн") weekday label must sit directly above the '
            'Monday day-number column at width=$width — a header/grid '
            'inset mismatch drifts the label off the column, worst at the '
            'edge columns',
      );
      expect(
        sundayHeaderX,
        closeTo(sundayGridX, 1.5),
        reason:
            'Sunday ("нд") weekday label must sit directly above the '
            'Sunday day-number column at width=$width',
      );
    }

    testWidgets(
      'weekday header aligns with day-grid edge columns at width=360',
      (tester) async {
        await expectHeaderAlignsWithGrid(tester, width: 360);
      },
    );

    testWidgets(
      'weekday header aligns with day-grid edge columns at width=414',
      (tester) async {
        await expectHeaderAlignsWithGrid(tester, width: 414);
      },
    );
  });
}
