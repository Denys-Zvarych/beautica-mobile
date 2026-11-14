// mobile-qa (2026-11-12, phase 485) — pins `MonthCalendar.compactRows`'s
// DEFAULT for the callers that never pass it.
//
// Phase 485 added `compactRows` to the SHARED `MonthCalendar`; only the
// bookings panel's week-header path sets it. `MasterSchedulePage` (used by
// `SalonTimeScreen`) composes the calendar with every row-shape flag at its
// default and has no golden, so a flipped default would silently shave 6dp
// off each of its week rows. This file proves the default renders exactly as
// an explicit `compactRows: false` and differs from `true` by the 3dp + 3dp
// row padding per week row.
//
// Load-bearing by construction: a default of `true` makes `byDefault ==
// compact`, so the height-delta expectation fails (lib/ was not mutated — the
// QA pass was barred from editing it).

import 'package:beautica_mobile/features/booking/presentation/widgets/month_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const Key _calendarKey = Key('booking-month-calendar');

/// July 2026 starts on a Wednesday → 5 week rows without `sixWeekRows`.
final DateTime _month = DateTime(2026, 7);
final DateTime _today = DateTime(2026, 7, 15);
const int _julyWeekRows = 5;

/// The `MasterSchedulePage` composition: only the required args + chevrons,
/// every row-shape flag left at its default unless [compactRows] is given.
MonthCalendar _calendar({bool? compactRows}) => compactRows == null
    ? MonthCalendar(
        key: _calendarKey,
        visibleMonth: _month,
        today: _today,
        selected: null,
        isAvailable: (_) => true,
        onSelectDay: (_) {},
        onPrevMonth: () {},
        onNextMonth: () {},
      )
    : MonthCalendar(
        key: _calendarKey,
        visibleMonth: _month,
        today: _today,
        selected: null,
        isAvailable: (_) => true,
        onSelectDay: (_) {},
        onPrevMonth: () {},
        onNextMonth: () {},
        compactRows: compactRows,
      );

Future<double> _heightOf(WidgetTester tester, MonthCalendar calendar) async {
  await tester.pumpApp(SingleChildScrollView(child: calendar), width: 360);
  await tester.pumpAndSettle();
  return tester.getSize(find.byKey(_calendarKey)).height;
}

void main() {
  testWidgets('compactRows defaults to false — the MasterSchedulePage '
      'composition lays out at the full 50dp row height', (tester) async {
    final double byDefault = await _heightOf(tester, _calendar());
    final double explicitFalse = await _heightOf(
      tester,
      _calendar(compactRows: false),
    );
    final double compact = await _heightOf(
      tester,
      _calendar(compactRows: true),
    );

    expect(byDefault, explicitFalse);
    expect(
      byDefault - compact,
      _julyWeekRows *
          (kMonthCalendarRowHeight - kMonthCalendarCompactRowHeight),
      reason: 'each default week row keeps its 3dp top + bottom padding',
    );
  });
}
