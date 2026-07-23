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
// ## Phase 7.13 — the "booking caller" group moved out
//
// This file used to also pin `showBookingsDateRangePicker` (the booking
// filter's Дата-row calendar) opening on today via `initialScrollMonth`.
// Phase 7.13 retired that function along with the Дата section it served —
// the rail's single-day jump (`showBookingsDayPicker`,
// `bookings_day_picker.dart`) replaces it, opening on the CURRENT SELECTION
// rather than on today specifically (today and the current selection often
// differ once the master has navigated). That coverage now lives in
// `test/features/booking/presentation/bookings_day_picker_test.dart`, which
// pins the day-picker's own opening behaviour against its own API. What
// remains here is the ONE group that never depended on either booking file
// at all — the schedule caller, pinned directly against `PeriodRangePicker`.
//
// ## Host-zone independence
//
// The remaining case is expressed RELATIVE to `DateTime.now()` rather than
// against a date literal, and asserts only which cell is on screen, not a
// wall-clock value. Identical under TZ=UTC and TZ=Europe/Kyiv.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
