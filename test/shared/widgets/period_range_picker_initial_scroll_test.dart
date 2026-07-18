// Phase 7.7 audit remediation (P3) — WHICH MONTH the picker opens on.
//
// `firstMonth` is where the reachable window BEGINS; `initialScrollMonth` is
// where the user's attention should LAND. They coincide for a forward-only
// picker, which is why the picker had only the one value until Phase 7.7
// pointed a caller's window backwards.
//
// For the booking filter `firstMonth` is `today − 180 days`, so scrolling to it
// opened the calendar roughly SIX MONTHS IN THE PAST — the master had to scroll
// a quarter of a year (~250 day cells) to reach today before they could pick
// anything. Same bug class the day rail had at its own `today − 180` origin,
// fixed for the rail in Phase 7.6.
//
// ## Both directions are asserted, and that is the point
//
// The fix is only correct if it is INERT for the schedule caller, whose
// `firstMonth` already IS the current month and which passes no
// `initialScrollMonth` at all. So this file pins the new behaviour AND the
// unchanged one; a fix that scrolled every caller to today would pass the first
// group and fail the second.
//
// ## Host-zone independence
//
// Both cases are expressed RELATIVE to `DateTime.now()` rather than against
// date literals, and neither asserts a wall-clock value — only which cell is
// on screen. Identical under TZ=UTC and TZ=Europe/Kyiv. (A literal here would
// be actively wrong: the booking window is anchored on the real clock.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/features/booking/presentation/widgets/date_range_calendar.dart';
import 'package:beautica_mobile/shared/widgets/period_range_picker.dart';

import '../../helpers/pump_app.dart';

const PeriodRangePickerStrings _strings = PeriodRangePickerStrings(
  title: 'Оберіть дату або період',
  emptyHint: 'Оберіть день',
  saveLabel: 'Готово',
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
  /// Whether [cell] is actually WITHIN the month list's viewport.
  ///
  /// Not `findsOneWidget`: a `ListView` builds a cache extent beyond the
  /// viewport on both sides, so a cell can be found while sitting off-screen —
  /// which is precisely the state the bug produced (today's cell existed in the
  /// tree, six months of scroll away). Compared against the scroll view's own
  /// rect rather than the window's, because the picker is a sheet that does not
  /// fill the screen.
  bool isInViewport(WidgetTester tester, Finder cell) {
    final Finder list = find.byType(Scrollable).last;
    final Rect viewport = tester.getRect(list);
    final Rect r = tester.getRect(cell);
    return r.top >= viewport.top && r.bottom <= viewport.bottom;
  }

  group('the booking caller opens on TODAY', () {
    // MUTATION: reverted the picker's post-frame target to
    // `_start ?? _firstDay` (the pre-fix expression) → this test FAILED:
    // today's cell was outside the viewport and the scroll offset was 0.
    // Restored.
    //
    // MUTATION: dropped `initialScrollMonth:` from
    // `showBookingsDateRangePicker` → same failure. Restored. (Both halves of
    // the fix are load-bearing and each is pinned.)
    testWidgets('with no initial range, today\'s cell is on screen at open', (
      WidgetTester tester,
    ) async {
      await tester.pumpRoutedApp(
        GoRouter(
          initialLocation: '/',
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (BuildContext context, GoRouterState state) => Scaffold(
                body: Builder(
                  builder: (BuildContext inner) => TextButton(
                    key: const Key('open'),
                    onPressed: () => showBookingsDateRangePicker(
                      inner,
                      today: DateTime.now(),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);
      final Finder todayCell = find.byKey(periodDayCellKey(today));

      expect(
        todayCell,
        findsOneWidget,
        reason: 'today is inside the ±180-day window by construction',
      );
      expect(
        isInViewport(tester, todayCell),
        isTrue,
        reason:
            'the calendar must open ON today, not six months behind it — the '
            'window starts at today − 180 days and scrolling to that origin is '
            'a quarter of a year of day cells before the master can pick '
            'anything',
      );

      // And the offset really moved: an assertion that only checked the cell
      // could in principle pass on a picker that rendered no past months at
      // all, which would be a different (and wrong) fix.
      final ScrollableState list = tester.state(find.byType(Scrollable).last);
      expect(
        list.position.pixels,
        greaterThan(0),
        reason: 'the past months are still rendered and still reachable',
      );
    });
  });

  group('the schedule caller is unchanged', () {
    // MUTATION: made `_initialScrollMonth` default to the CURRENT month rather
    // than to `firstMonth` when the parameter is omitted → this test FAILED
    // (the offset was non-zero for a picker whose first month is 6 months
    // ahead). Restored.
    //
    // `apply_schedule_sheet.dart` passes none of the optional parameters and
    // must keep landing on `firstMonth`. Expressed here as a picker whose
    // `firstMonth` is deliberately NOT the current month, so "scrolled to
    // firstMonth" and "scrolled to today" are distinguishable — with the
    // schedule's real forward-only anchoring the two coincide and the
    // assertion would be vacuous.
    //
    // `firstMonth` is six months in the PAST specifically, not the future. With
    // a future `firstMonth` the today-index is NEGATIVE and `_indexForMonth`
    // clamps it to 0 — so a picker wrongly scrolling to today would still land
    // at offset 0 and the mutation would pass unseen. That was observed, not
    // reasoned about: the first version of this test used `now.month + 6` and
    // stayed green through the mutation below.
    testWidgets('with no initialScrollMonth, the list opens at firstMonth', (
      WidgetTester tester,
    ) async {
      final DateTime now = DateTime.now();
      final DateTime firstMonth = DateTime(now.year, now.month - 6);

      await tester.pumpApp(
        Scaffold(
          body: SizedBox(
            height: 1200,
            child: PeriodRangePicker(
              firstMonth: firstMonth,
              firstSelectableDay: firstMonth,
              strings: _strings,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ScrollableState list = tester.state(find.byType(Scrollable).last);
      expect(
        list.position.pixels,
        0,
        reason:
            'the schedule caller must stay byte-identical: no window cap, no '
            'span cap, 24 months, scrolled to firstMonth',
      );
      expect(
        isInViewport(tester, find.byKey(periodDayCellKey(firstMonth))),
        isTrue,
      );
    });
  });
}
