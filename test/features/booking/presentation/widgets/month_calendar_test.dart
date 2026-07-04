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
}
