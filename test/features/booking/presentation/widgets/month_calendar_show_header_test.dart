// mobile-qa (2026-08-14) — the `showHeader` opt-in added to the SHARED
// `MonthCalendar` by the «Мої записи» week-pager / headerless-grid rework.
//
// WHY THIS FILE EXISTS
// --------------------
// `MonthCalendar` has four consumers. Exactly ONE of them (the bookings panel)
// wants the new headerless shape; the other three — `SlotDateScreen`,
// `MasterSchedulePage`, `period_range_picker.dart` — navigate months by the
// ‹ › chevrons `_MonthHeader` renders and have NO other affordance at all. A
// default flip on `showHeader`, or an accidental `showHeader: false` on one of
// them, removes their only month navigation and is INVISIBLE to every existing
// test: `slot_picker_test.dart` taps `booking-calendar-next-month`, so it
// would fail with "found 0 widgets", naming the finder rather than the cause,
// and `period_range_picker`'s own suites never touch the chevrons.
//
// Nothing else in the suite pins any of the following, all of which shipped in
// this diff:
//   * that the DEFAULT is still `true` (the pre-existing three callers'
//     entire contract);
//   * that `false` removes BOTH chevrons AND the second month caption — the
//     user-facing reason the flag exists is that the month+year must appear
//     exactly ONCE on the bookings screen;
//   * that the constructor assert rejects an `onPrevMonth`/`onNextMonth`
//     silently dropped by `showHeader: false`;
//   * that `kMonthCalendarExpandedHeight` — hand-reduced by 48dp in this diff
//     — still equals what the panel's exact composition actually LAYS OUT AT.
//     That constant is the panel's expanded resting height and its
//     `ClipRect`'s size: if the header ever comes back, the constant does not
//     grow with it and the last grid row is silently clipped away.
//
// MUTATION-PROBED (2026-08-14) — each assertion was confirmed load-bearing by
// reverting the production change it guards; see the per-test notes.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/month_calendar.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// A July fixture, deliberately mid-month so no six-week-row edge case is in
/// play — this file is about the HEADER, not the grid.
final DateTime _month = DateTime(2026, 7);
final DateTime _today = DateTime(2026, 7, 15);

/// The month+year caption `_MonthHeader` renders, derived through the same
/// production formatter the header itself uses rather than re-spelled — a
/// hardcoded «липень 2026» would drift the moment `monthNominative` changed.
String get _caption => '${monthNominative(_month.month)} ${_month.year}';

const Key _prevChevron = Key('booking-calendar-prev-month');
const Key _nextChevron = Key('booking-calendar-next-month');

/// Pumps a `MonthCalendar` in a vertically UNBOUNDED slot, so the widget
/// reports its own INTRINSIC height rather than whatever the viewport handed
/// it — which is what the [kMonthCalendarExpandedHeight] pin below measures.
Future<void> _pumpCalendar(
  WidgetTester tester,
  MonthCalendar calendar, {
  double width = 360,
}) async {
  await tester.pumpApp(SingleChildScrollView(child: calendar), width: width);
  await tester.pumpAndSettle();
}

void main() {
  // ── The DEFAULT — what SlotDateScreen / MasterSchedulePage /
  //    period_range_picker rely on, and the only month navigation they have ──
  //
  // MUTATION-PROBED: flipping the `showHeader` field default to `false`
  // turns this red on all three expectations at once.
  testWidgets(
    'showHeader DEFAULTS to true — the header, both ‹ › chevrons and the '
    'month caption all render for a caller that never mentions the flag',
    (tester) async {
      await _pumpCalendar(
        tester,
        MonthCalendar(
          visibleMonth: _month,
          today: _today,
          selected: _today,
          isAvailable: (DateTime _) => true,
          onSelectDay: (DateTime _) {},
          onPrevMonth: () {},
          onNextMonth: () {},
        ),
      );

      expect(
        find.byKey(_prevChevron),
        findsOneWidget,
        reason:
            'the ‹ chevron is gone from the DEFAULT configuration — '
            'SlotDateScreen and MasterSchedulePage have no other way to '
            'reach the previous month',
      );
      expect(find.byKey(_nextChevron), findsOneWidget);
      expect(
        find.text(_caption),
        findsOneWidget,
        reason: 'the default configuration lost its month+year caption',
      );
    },
  );

  testWidgets(
    'the default header\'s chevrons are genuinely WIRED — tapping each one '
    'invokes its callback',
    (tester) async {
      // Presence alone is not the contract: a header that rendered two inert
      // chevrons would satisfy the test above while leaving the slot picker
      // unable to change month. The two counters below separate them.
      int prev = 0;
      int next = 0;
      await _pumpCalendar(
        tester,
        MonthCalendar(
          visibleMonth: _month,
          today: _today,
          selected: _today,
          isAvailable: (DateTime _) => true,
          onSelectDay: (DateTime _) {},
          onPrevMonth: () => prev++,
          onNextMonth: () => next++,
        ),
      );

      await tester.tap(find.byKey(_nextChevron));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_prevChevron));
      await tester.pumpAndSettle();

      expect(next, 1, reason: 'the › chevron did not invoke onNextMonth');
      expect(prev, 1, reason: 'the ‹ chevron did not invoke onPrevMonth');
    },
  );

  // ── showHeader: false — the bookings panel's shape ───────────────────────
  //
  // MUTATION-PROBED: dropping the `if (showHeader)` guard in
  // `month_calendar.dart`'s build (i.e. rendering `_MonthHeader`
  // unconditionally, as before this diff) turns every expectation below red.
  testWidgets(
    'showHeader: false removes BOTH chevrons and the month caption — the '
    'month+year exists exactly ONCE on the bookings screen',
    (tester) async {
      await _pumpCalendar(
        tester,
        MonthCalendar(
          visibleMonth: _month,
          today: _today,
          selected: _today,
          isAvailable: (DateTime _) => true,
          onSelectDay: (DateTime _) {},
          composeWeekdayBar: true,
          sixWeekRows: true,
          showHeader: false,
        ),
      );

      expect(
        find.byKey(_prevChevron),
        findsNothing,
        reason:
            'a ‹ chevron survived showHeader: false — the locked requirement '
            'is that the rework adds NO month-navigation buttons at all',
      );
      expect(find.byKey(_nextChevron), findsNothing);
      expect(
        find.text(_caption),
        findsNothing,
        reason:
            'the grid still renders its own month caption — the panel\'s '
            'permanent _TopRow label would then be the SECOND copy of the '
            'same month on screen, which is what showHeader: false exists to '
            'prevent',
      );

      // …while the parts that must SURVIVE the flag genuinely do. Without
      // this half, deleting the whole calendar body would pass the three
      // negative assertions above.
      expect(
        find.byType(CalendarWeekdayBar),
        findsOneWidget,
        reason:
            'the weekday bar went with the header — the composed grid must '
            'keep its пн…нд captions',
      );
      expect(
        find.byKey(Key('booking-calendar-day-${_today.day}')),
        findsOneWidget,
        reason: 'the day grid itself vanished with the header',
      );
    },
  );

  test('passing onPrevMonth/onNextMonth alongside showHeader: false is a '
      'constructor assert, not a silent no-op', () {
    // The chevrons are the ONLY thing those two callbacks feed. Dropping
    // them silently is always a wiring mistake — a caller that believes it
    // wired month navigation and got none.
    expect(
      () => MonthCalendar(
        visibleMonth: _month,
        today: _today,
        selected: _today,
        isAvailable: (DateTime _) => true,
        onSelectDay: (DateTime _) {},
        showHeader: false,
        onNextMonth: () {},
      ),
      throwsA(isA<AssertionError>()),
      reason: 'onNextMonth with showHeader: false was accepted silently',
    );
    expect(
      () => MonthCalendar(
        visibleMonth: _month,
        today: _today,
        selected: _today,
        isAvailable: (DateTime _) => true,
        onSelectDay: (DateTime _) {},
        showHeader: false,
        onPrevMonth: () {},
      ),
      throwsA(isA<AssertionError>()),
      reason: 'onPrevMonth with showHeader: false was accepted silently',
    );
    // The legitimate combination must NOT throw, or the assert is simply a
    // ban on `showHeader: false`.
    expect(
      () => MonthCalendar(
        visibleMonth: _month,
        today: _today,
        selected: _today,
        isAvailable: (DateTime _) => true,
        onSelectDay: (DateTime _) {},
        showHeader: false,
      ),
      returnsNormally,
    );
  });

  // ── The 48dp reclaim, MEASURED ──────────────────────────────────────────
  //
  // `kMonthCalendarExpandedHeight` was hand-edited in this diff: the
  // `kMonthCalendarHeaderHeight + VelvetSpacing.sm` terms were deleted, taking
  // it from 380dp to 332dp. It is `BookingsMonthCalendarPanel`'s expanded
  // resting height AND the height of the `Positioned` box its grid pager is
  // laid out in — so if the real laid-out height and the constant ever
  // disagree, the panel either clips the last week row away or leaves a dead
  // band under the grid, at every expand fraction, with no error.
  //
  // Asserted against the RENDERED height, not re-derived from the same
  // addends the constant is made of — a test that re-adds the constants would
  // stay green through exactly the change it exists to catch.
  //
  // MUTATION-PROBED: restoring `showHeader: true` on the composition below
  // makes the measured height 380dp against a 332dp constant → red.
  testWidgets(
    'kMonthCalendarExpandedHeight equals the height the panel\'s exact '
    'composition actually lays out at',
    (tester) async {
      await _pumpCalendar(
        tester,
        MonthCalendar(
          visibleMonth: _month,
          today: _today,
          selected: _today,
          isAvailable: (DateTime _) => true,
          onSelectDay: (DateTime _) {},
          composeWeekdayBar: true,
          sixWeekRows: true,
          showHeader: false,
        ),
      );

      expect(
        tester.getSize(find.byType(MonthCalendar)).height,
        closeTo(kMonthCalendarExpandedHeight, 0.5),
        reason:
            'the panel\'s expanded height constant no longer matches what the '
            'grid renders at — the expanded calendar will clip its last week '
            'row or leave a dead band above the timeline',
      );
    },
  );

  testWidgets(
    'the DEFAULT (headered) composition is exactly kMonthCalendarHeaderHeight '
    '+ VelvetSpacing.sm taller — the 48dp this rework reclaimed',
    (tester) async {
      // Pins the DELTA rather than either absolute, so this stays meaningful
      // if the grid's own row metrics are ever retuned: what must hold is
      // that `showHeader` costs exactly the header band and its gap, and
      // nothing else moved when the `if` was introduced.
      await _pumpCalendar(
        tester,
        MonthCalendar(
          visibleMonth: _month,
          today: _today,
          selected: _today,
          isAvailable: (DateTime _) => true,
          onSelectDay: (DateTime _) {},
          composeWeekdayBar: true,
          sixWeekRows: true,
        ),
      );
      final double headered = tester.getSize(find.byType(MonthCalendar)).height;

      expect(
        headered - kMonthCalendarExpandedHeight,
        closeTo(kMonthCalendarHeaderHeight + VelvetSpacing.sm, 0.5),
        reason:
            'showHeader: true no longer costs exactly the header band plus '
            'its gap — either the header changed size without '
            'kMonthCalendarHeaderHeight following it, or the headerless '
            'branch dropped something more than the header',
      );
    },
  );
}
