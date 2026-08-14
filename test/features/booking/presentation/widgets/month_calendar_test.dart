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

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/month_calendar.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
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

      // `tapCalendarDay` rather than a blind `tap(cell)`: this fixture mounts
      // MonthCalendar in a bare Scaffold (no scroll view), so `ensureVisible`
      // is a no-op here — but the helper is the single uniform entry point for
      // every enabled-cell tap (scripts/forbid_blind_calendar_tap.sh), so the
      // day this fixture grows a scroll ancestor it does not silently rot.
      await tester.tapCalendarDay(15);
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
              // `CalendarWeekdayBar` renders no horizontal padding of its own
              // (mobile-backlog D4/D5) — every caller wraps it in the same
              // inset its sibling grid uses, mirroring
              // `slot_picker_screen.dart`'s real (production) composition.
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
                child: CalendarWeekdayBar(),
              ),
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

      // `CalendarWeekdayBar` renders `weekdayAbbrev` verbatim (a hardcoded
      // Monday-first lookup, not an `AppLocalizations` lookup — see
      // `shared/formatters/uk_calendar.dart`), so locating by that same
      // accessor (rather than a duplicated Cyrillic literal) tracks the
      // widget's real source of truth instead of coupling the test to a copy
      // of it.
      final double mondayHeaderX = tester
          .getCenter(find.text(weekdayAbbrev(1)))
          .dx;
      final double sundayHeaderX = tester
          .getCenter(find.text(weekdayAbbrev(7)))
          .dx;
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

    // mobile-backlog D4 regression: the COMPOSED configuration
    // (`composeWeekdayBar: true`, `showHeader: false`) is exactly what
    // `BookingsMonthCalendarPanel` uses for the expanded «Мої записи»
    // calendar — the surface the user reported «пн» rendering between the
    // 3rd and 4th of серпня on. Before the fix, `CalendarWeekdayBar` self-
    // padded by `VelvetSpacing.lg` AND was composed inside `MonthCalendar`'s
    // own `VelvetSpacing.lg` outer `Padding`, doubling the inset to 48dp/side
    // against the grid's single 24dp/side — this test pumps that exact
    // composition and would have failed before the fix.
    testWidgets(
      'composed weekday bar (composeWeekdayBar: true) aligns with the grid',
      (tester) async {
        final DateTime visibleMonth = DateTime(2026, 7);
        final int leadingBlanks =
            DateTime(visibleMonth.year, visibleMonth.month, 1).weekday - 1;
        final int mondayDay = 8 - leadingBlanks;
        final int sundayDay = 14 - leadingBlanks;

        await tester.pumpApp(
          Scaffold(
            body: MonthCalendar(
              visibleMonth: visibleMonth,
              today: visibleMonth,
              selected: null,
              isAvailable: (_) => true,
              onSelectDay: (_) {},
              composeWeekdayBar: true,
              showHeader: false,
            ),
          ),
          width: 360,
        );
        await tester.pumpAndSettle();

        final double mondayHeaderX = tester
            .getCenter(find.text(weekdayAbbrev(1)))
            .dx;
        final double sundayHeaderX = tester
            .getCenter(find.text(weekdayAbbrev(7)))
            .dx;
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
              'composed «пн» must sit directly above the Monday day-number '
              'column — a double-padded bar drifts it a half column right',
        );
        expect(sundayHeaderX, closeTo(sundayGridX, 1.5));
      },
    );
  });

  // mobile-backlog D1 regression: a day with fewer than the max 3 density
  // dots must still render its LIT dot(s) centered under the day number —
  // not left-aligned inside a fixed 3-slot row. Ground truth is
  // `tester.getCenter`, per the task brief: a golden cannot prove this.
  group('density-dot centering (D1)', () {
    Future<double> pumpAndGetLitDotCentroidX(
      WidgetTester tester, {
      required int bookingsOnDay15,
    }) async {
      final DateTime visibleMonth = DateTime(2026, 7);
      await tester.pumpApp(
        Scaffold(
          body: MonthCalendar(
            visibleMonth: visibleMonth,
            today: DateTime(2026, 7, 1),
            selected: null,
            isAvailable: (_) => true,
            onSelectDay: (_) {},
            onPrevMonth: null,
            onNextMonth: null,
            bookingCount: (DateTime d) => d.day == 15 ? bookingsOnDay15 : 0,
          ),
        ),
        width: 360,
      );
      await tester.pumpAndSettle();

      final Finder cell = find.byKey(const Key('booking-calendar-day-15'));
      final Finder dots = find.descendant(
        of: cell,
        matching: find.byWidgetPredicate((Widget w) {
          if (w is! Container) return false;
          final BoxDecoration? d = w.decoration as BoxDecoration?;
          return d?.shape == BoxShape.circle;
        }),
      );
      final int n = dots.evaluate().length;
      expect(n, bookingsOnDay15, reason: 'exactly the lit dots are laid out');
      double minX = double.infinity, maxX = -double.infinity;
      for (int i = 0; i < n; i++) {
        final Rect r = tester.getRect(dots.at(i));
        minX = minX < r.left ? minX : r.left;
        maxX = maxX > r.right ? maxX : r.right;
      }
      return (minX + maxX) / 2;
    }

    testWidgets('a single lit dot centers under the day number', (
      tester,
    ) async {
      // The tree must be pumped (inside `pumpAndGetLitDotCentroidX`) BEFORE
      // either finder resolves — both address the same already-mounted
      // widget.
      final double dotX = await pumpAndGetLitDotCentroidX(
        tester,
        bookingsOnDay15: 1,
      );
      final double numberX = tester
          .getCenter(
            find.descendant(
              of: find.byKey(const Key('booking-calendar-day-15')),
              matching: find.text('15'),
            ),
          )
          .dx;
      expect(
        dotX,
        closeTo(numberX, 0.5),
        reason:
            'a single booking must render its dot centered under the day '
            'number, not left-aligned inside a reserved 3-slot row',
      );
    });

    testWidgets('two lit dots center as a group under the day number', (
      tester,
    ) async {
      final double dotsX = await pumpAndGetLitDotCentroidX(
        tester,
        bookingsOnDay15: 2,
      );
      final double numberX = tester
          .getCenter(
            find.descendant(
              of: find.byKey(const Key('booking-calendar-day-15')),
              matching: find.text('15'),
            ),
          )
          .dx;
      expect(dotsX, closeTo(numberX, 0.5));
    });
  });

  // mobile-backlog D2 regression: a day that is BOTH "today" and selected
  // must not paint the today ring on top of the selected trough — selected
  // wins, the ring stands down.
  group('today ring vs. selection precedence (D2)', () {
    Finder badgeContainer(Finder cell) => find.descendant(
      of: cell,
      matching: find.byWidgetPredicate(
        (Widget w) =>
            w is Container &&
            w.constraints ==
                const BoxConstraints.tightFor(width: 38, height: 38),
      ),
    );

    testWidgets('today ring renders when today is NOT selected', (
      tester,
    ) async {
      final DateTime today = DateTime(2026, 7, 15);
      await tester.pumpApp(
        Scaffold(
          body: MonthCalendar(
            visibleMonth: today,
            today: today,
            selected: null,
            isAvailable: (_) => true,
            onSelectDay: (_) {},
            onPrevMonth: null,
            onNextMonth: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder cell = find.byKey(const Key('booking-calendar-day-15'));
      final Container badge = tester.widget<Container>(badgeContainer(cell));
      final BoxDecoration? deco = badge.decoration as BoxDecoration?;
      expect(deco?.shape, BoxShape.circle, reason: 'unselected today rings');
    });

    testWidgets(
      'today ring is SUPPRESSED when today is also selected (no double '
      'disc)',
      (tester) async {
        final DateTime today = DateTime(2026, 7, 15);
        await tester.pumpApp(
          Scaffold(
            body: MonthCalendar(
              visibleMonth: today,
              today: today,
              selected: today,
              isAvailable: (_) => true,
              onSelectDay: (_) {},
              onPrevMonth: null,
              onNextMonth: null,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final Finder cell = find.byKey(const Key('booking-calendar-day-15'));
        final Container badge = tester.widget<Container>(badgeContainer(cell));
        expect(
          badge.decoration,
          isNull,
          reason:
              'a selected today must not ALSO paint the ring — the trough '
              '+ bold number already carry the "picked" signal',
        );
      },
    );
  });

  // mobile-backlog D3 regression: Saturday/Sunday day numbers read muted,
  // and a SELECTED weekend day is never left illegible (muted).
  //
  // mobile-security MEDIUM (calendar-consolidation audit): the muted tone is
  // `BrandColors.weekendMuted`, not `BrandColors.muted` — `muted` measures
  // 2.69:1 on `BrandColors.base` (sub-AA) and this day number is ACTIVE,
  // tappable text (`isAvailable: (_) => true` below), so WCAG 1.4.3's
  // inactive-component exemption does not cover it; `weekendMuted` clears AA
  // (5.07:1).
  group('weekend day-number muting (D3)', () {
    testWidgets('an available, unselected Sunday number renders weekendMuted', (
      tester,
    ) async {
      // 2026-07-05 is a Sunday.
      final DateTime visibleMonth = DateTime(2026, 7);
      await tester.pumpApp(
        Scaffold(
          body: MonthCalendar(
            visibleMonth: visibleMonth,
            today: DateTime(2026, 7, 1),
            selected: null,
            isAvailable: (_) => true,
            onSelectDay: (_) {},
            onPrevMonth: null,
            onNextMonth: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Text number = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('booking-calendar-day-5')),
          matching: find.text('5'),
        ),
      );
      expect(number.style?.color, BrandColors.weekendMuted);
    });

    testWidgets('a SELECTED Sunday number stays legible (never muted)', (
      tester,
    ) async {
      final DateTime visibleMonth = DateTime(2026, 7);
      final DateTime sunday = DateTime(2026, 7, 5);
      await tester.pumpApp(
        Scaffold(
          body: MonthCalendar(
            visibleMonth: visibleMonth,
            today: DateTime(2026, 7, 1),
            selected: sunday,
            isAvailable: (_) => true,
            onSelectDay: (_) {},
            onPrevMonth: null,
            onNextMonth: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Text number = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('booking-calendar-day-5')),
          matching: find.text('5'),
        ),
      );
      expect(
        number.style?.color,
        BrandColors.accentDeep,
        reason: 'selected always outranks the weekend-muted cue',
      );
    });
  });
}
