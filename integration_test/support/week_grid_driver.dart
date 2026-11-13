// Phase 485 — THE one way a test selects a day on a provider «Записи»
// screen, flings its week grid, or switches «День / 3 дні».
//
// It replaces four hand-copied rail-day helpers (and one closure in
// `bookings_discovery_view_reuse_test.dart`) that had drifted apart — two of
// them onto the wrong scrolling primitive. Do not add another copy: extend
// this file.
//
// Two layouts, one entry point:
//   * the WEEK layout (`MasterBookingsScreen`, phase 485) — steps ‹ › until
//     the strip shows the day's week, then taps its strip cell;
//   * the DAY layout (the salon board, `BookingsDiscoveryView` pumped
//     directly) — pages the day rail until the chip is on screen, taps it,
//     and crosses the 220 ms day-selection debounce.
//
// Deliberately free of `app_harness.dart` so a plain widget test under
// `test/` can import it too; integration flows pass `AppHarness.settle` as
// [settle].

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/application/master_bookings_view_mode.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_column_painter.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_nav_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

/// How a driver call waits for the screen to come to rest.
typedef WeekGridSettle = Future<void> Function(WidgetTester tester);

Future<void> _pumpAndSettle(WidgetTester tester) => tester.pumpAndSettle();

/// Week steps / rail pages a driver call may take before failing loudly.
const int _kMaxSteps = 60;

/// The day layout's day-selection debounce plus margin.
const Duration _kDayDebounce = Duration(milliseconds: 300);

/// Selects [day] on whichever layout is mounted — see the file header.
Future<void> selectWeekDay(
  WidgetTester tester,
  DateTime day, {
  WeekGridSettle settle = _pumpAndSettle,
}) async {
  final DateTime target = dateOnly(day);
  if (find.byType(WeekStrip).evaluate().isNotEmpty) {
    await _showWeekOf(tester, target, settle);
    await tester.tap(find.byKey(weekStripDayKey(target)));
    // The grid's animated scroll to the tapped day.
    await tester.pump(WeekStrip.settleDuration);
    await settle(tester);
    return;
  }
  await _tapRailDay(tester, target, settle);
}

/// Steps the week header ‹ › until the strip shows [day]'s week.
Future<void> _showWeekOf(
  WidgetTester tester,
  DateTime day,
  WeekGridSettle settle,
) async {
  final DateTime targetWeek = kyivWeekStart(day);
  for (int i = 0; i < _kMaxSteps; i++) {
    final DateTime shown = tester
        .widget<WeekStrip>(find.byType(WeekStrip))
        .weekStart;
    final int days = kyivDaysBetween(shown, targetWeek);
    if (days == 0) return;
    await tester.tap(
      find.byKey(days > 0 ? WeekStepButton.nextKey : WeekStepButton.prevKey),
    );
    await settle(tester);
  }
  fail('the week header never reached the week of $day in $_kMaxSteps steps');
}

Future<void> _tapRailDay(
  WidgetTester tester,
  DateTime day,
  WeekGridSettle settle,
) async {
  final Finder chip = find.byKey(dayChipKey(day));
  for (int i = 0; i < _kMaxSteps && chip.evaluate().isEmpty; i++) {
    final DateTime selected = tester
        .widget<BookingsDayRail>(find.byType(BookingsDayRail))
        .selectedDay;
    final bool forward = day.isAfter(selected);
    final Finder rail = find.byKey(const Key('master-bookings-day-rail'));
    final double width = tester.getRect(rail).width;
    await tester.fling(rail, Offset(forward ? -width : width, 0), 800);
    await settle(tester);
  }
  expect(chip, findsOneWidget, reason: 'the rail never paged to $day');
  await tester.tap(chip);
  // fixed-wait-ok: crossing the 220 ms day-selection debounce, which
  // pumpAndSettle never fires.
  await tester.pump(_kDayDebounce);
  await settle(tester);
}

/// Flings the week grid's pager by [dx] logical px (negative = toward
/// Sunday) with 8 real, 40 ms-spaced pointer samples so the velocity
/// tracker sees a genuine fling, then crosses the grid's day-snap settle
/// delay ([WeekTimeGrid.settleDelay]) — `pumpAndSettle` alone fires no
/// `Timer`.
Future<void> flingWeek(
  WidgetTester tester,
  double dx, {
  WeekGridSettle settle = _pumpAndSettle,
}) async {
  final Finder pager = find.byKey(WeekTimeGrid.pagerKey);
  const int steps = 8;
  final TestGesture gesture = await tester.startGesture(
    tester.getCenter(pager),
  );
  Duration stamp = Duration.zero;
  for (int i = 0; i < steps; i++) {
    stamp += const Duration(milliseconds: 40);
    await gesture.moveBy(Offset(dx / steps, 0), timeStamp: stamp);
    // fixed-wait-ok: advancing the pointer-sample clock in lockstep with the
    // synthetic move timestamps, not waiting on a condition.
    await tester.pump(const Duration(milliseconds: 40));
  }
  await gesture.up();
  await settle(tester);
  await tester.pump(WeekTimeGrid.settleDelay);
  await settle(tester);
}

/// Taps the «День / 3 дні» toggle to [mode] (a no-op tap when already
/// there).
Future<void> switchViewMode(
  WidgetTester tester,
  BookingsWeekViewMode mode, {
  WeekGridSettle settle = _pumpAndSettle,
}) async {
  await tester.tap(
    find.byKey(
      mode == BookingsWeekViewMode.day
          ? ViewModeToggle.dayKey
          : ViewModeToggle.threeDaysKey,
    ),
  );
  await settle(tester);
}

/// The left-most visible day index of the week grid (0 = Monday).
int visibleWeekDay(WidgetTester tester) {
  final PageController c = tester
      .widget<WeekTimeGrid>(find.byType(WeekTimeGrid))
      .pageController;
  return (c.page ?? c.initialPage.toDouble()).round();
}

/// Phase 487 — taps the EMPTY grid of week day [dayIndex] (0 = Monday) at
/// Kyiv wall clock [hour]:[minute]: switches to «День», pages to that day,
/// scrolls the time axis so the minute is on screen, then taps the column's
/// empty-tap layer at the y the column's OWN painter maps that minute to
/// (`topPad` + first hour + hour height) — so the tap lands on that
/// wall-clock minute whatever hour window the grid resolved.
Future<void> tapEmptyGridAt(
  WidgetTester tester, {
  required int dayIndex,
  required int hour,
  required int minute,
  WeekGridSettle settle = _pumpAndSettle,
}) async {
  await switchViewMode(tester, BookingsWeekViewMode.day, settle: settle);
  tester
      .widget<WeekTimeGrid>(find.byType(WeekTimeGrid))
      .pageController
      .jumpToPage(dayIndex);
  await settle(tester);
  // fixed-wait-ok: crossing the grid's day-snap settle delay, which
  // pumpAndSettle never fires (see [flingWeek]).
  await tester.pump(WeekTimeGrid.settleDelay);
  await settle(tester);

  final Finder column = find.byKey(WeekTimeGrid.columnKey(dayIndex));
  final WeekColumnPainter painter =
      tester
              .widgetList<CustomPaint>(
                find.descendant(of: column, matching: find.byType(CustomPaint)),
              )
              .map((CustomPaint p) => p.painter)
              .firstWhere((CustomPainter? p) => p is WeekColumnPainter)
          as WeekColumnPainter;
  final double localY =
      painter.topPad +
      (hour * 60 + minute - painter.firstHour * 60) / 60 * painter.hourHeight;
  final ScrollableState vertical = tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byKey(WeekTimeGrid.verticalScrollKey),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  vertical.position.jumpTo(
    (localY - 120).clamp(0, vertical.position.maxScrollExtent),
  );
  await settle(tester);

  final Rect layer = tester.getRect(
    find.byKey(WeekTimeGrid.emptyTapKey(dayIndex)),
  );
  await tester.tapAt(Offset(layer.center.dx, layer.top + localY));
  await settle(tester);
}
