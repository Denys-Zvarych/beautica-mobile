// Phase 486 — the week grid's frame budget, as build-identity gates (the
// `bookings_day_rail_rebuild_gate_test.dart` pattern: an element whose
// widget instance is still `identical` after the gesture was not rebuilt by
// its parent).
//
// A horizontal drag / fling of the shared pager must:
//   * rebuild NO booking card and NO day column that stays mounted — the
//     pager only re-lays-out and re-composites them;
//   * leave the strip's day cells alone (its window rides the pager's
//     listenable as a paint-only Transform);
//   * build only the columns in the viewport plus the one sliding in —
//     never all seven.
//
// MUTATIONS, each reddening a case below:
//   * `setState(() {})` in `_WeekTimeGridState._syncHeader` (a per-frame
//     full-tree rebuild) → the card / column identity cases;
//   * the strip's `AnimatedBuilder` moved above the day `Row` (builder
//     rebuilds the cells) → the strip case;
//   * `allowImplicitScrolling: true` on the grid pager → the ±1 case.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart'
    show stableBookingList;
import 'package:beautica_mobile/features/booking/domain/bookings_week_state.dart';
import 'package:beautica_mobile/features/booking/domain/week_day_model.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// Mon 9 – Sun 15 November 2026 (Kyiv UTC+2), 09:00–18:00 every day.
final DateTime _monday = DateTime(2026, 11, 9);

/// A Kyiv wall-clock instant on day [dayIndex] (0 = Monday).
DateTime _kyiv(int dayIndex, int h, [int m = 0]) =>
    // Fixed instants fed to a pure layout; the injected `now` is fixed too.
    // future-date-ok: nothing here compares against the host clock.
    DateTime.utc(2026, 11, 9 + dayIndex, h - 2, m);

Booking _booking(String id, DateTime startAt) => Booking(
  id: id,
  masterId: 'master-1',
  masterFirstName: 'Оля',
  masterLastName: 'Коваль',
  masterType: 'INDEPENDENT_MASTER',
  clientFirstName: 'Олена',
  clientLastName: 'Коваленко',
  serviceId: 'service-1',
  serviceName: 'Манікюр',
  durationMinutes: 60,
  price: 500,
  startAt: startAt,
  endAt: startAt.add(const Duration(minutes: 60)),
  status: BookingStatus.confirmed,
  canReview: false,
);

/// A busy week: four bookings on every day.
List<WeekDayModel> _busyWeek() {
  final BookingsWeekState week = BookingsWeekState(
    weekStart: _monday,
    byDay: <DateTime, List<Booking>>{
      for (int i = 0; i < 7; i++)
        kyivAddDays(_monday, i): stableBookingList(<Booking>[
          for (final int h in <int>[9, 11, 13, 15])
            _booking('d$i-h$h', _kyiv(i, h)),
        ]),
    },
  );
  return buildWeekDays(
    week,
    schedule: <DateTime, EffectiveDay>{
      for (int i = 0; i < 7; i++)
        kyivAddDays(_monday, i): EffectiveDay(
          date: kyivAddDays(_monday, i),
          source: EffectiveSource.template,
          intervals: <WorkInterval>[
            WorkInterval(
              start: const TimeOfDay(hour: 9, minute: 0),
              end: const TimeOfDay(hour: 18, minute: 0),
            ),
          ],
        ),
    },
  );
}

Future<PageController> _pump(WidgetTester tester) async {
  final PageController pager = WeekTimeGrid.controllerFor(
    visibleColumns: 3,
    firstVisibleDay: 2,
  );
  addTearDown(pager.dispose);
  final List<WeekDayModel> days = _busyWeek();
  final List<int> counts = weekStripCounts(days);
  final List<bool> dayOff = weekStripDayOff(days);
  await tester.pumpApp(
    Scaffold(
      body: Column(
        children: <Widget>[
          WeekStrip(
            weekStart: _monday,
            today: kyivAddDays(_monday, 2),
            counts: counts,
            dayOff: dayOff,
            pageController: pager,
            visibleColumns: 3,
            onTapDay: (_) {},
            onPrevWeek: () {},
            onNextWeek: () {},
          ),
          Expanded(
            child: WeekTimeGrid(
              weekStart: _monday,
              days: days,
              today: kyivAddDays(_monday, 2),
              now: _kyiv(2, 8),
              pageController: pager,
              visibleColumns: 3,
              onBookingTap: (_) {},
              onTapHeader: (_) {},
              showsAllOccupancy: true,
            ),
          ),
        ],
      ),
    ),
    width: 360,
    height: 800,
  );
  await tester.pumpAndSettle();
  return pager;
}

/// Every mounted card, by key → its widget instance.
Map<Key?, Widget> _cards(WidgetTester tester) => <Key?, Widget>{
  for (final Element e
      in find.byType(MasterBookingCard, skipOffstage: false).evaluate())
    e.widget.key: e.widget,
};

/// The mounted day columns, by index → widget instance.
Map<int, Widget> _columns(WidgetTester tester) => <int, Widget>{
  for (int i = 0; i < 7; i++)
    if (find
        .byKey(WeekTimeGrid.columnKey(i), skipOffstage: false)
        .evaluate()
        .isNotEmpty)
      i: tester.widget(
        find.byKey(WeekTimeGrid.columnKey(i), skipOffstage: false),
      ),
};

/// Moves the pager by [dx] in [steps] pointer moves, pumping ONE frame per
/// move — every frame of the gesture is observed.
Future<void> _dragFrames(
  WidgetTester tester, {
  required double dx,
  int steps = 8,
}) async {
  final TestGesture g = await tester.startGesture(
    tester.getCenter(find.byKey(WeekTimeGrid.pagerKey)),
  );
  for (int i = 0; i < steps; i++) {
    await g.moveBy(Offset(dx / steps, 0));
    await tester.pump();
  }
  await g.up();
  await tester.pump();
}

void main() {
  testWidgets('dragging the pager rebuilds no card that stays mounted', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final Map<Key?, Widget> before = _cards(tester);
    expect(before.length, greaterThanOrEqualTo(12), reason: 'three days × 4');

    // Less than one column: every card on screen stays mounted.
    await _dragFrames(tester, dx: -60);

    final Map<Key?, Widget> after = _cards(tester);
    int kept = 0;
    for (final MapEntry<Key?, Widget> e in before.entries) {
      final Widget? now = after[e.key];
      if (now == null) continue;
      kept++;
      expect(identical(now, e.value), isTrue, reason: '${e.key} rebuilt');
    }
    expect(kept, greaterThanOrEqualTo(12));
  });

  testWidgets('a fling across the week rebuilds no column that stays mounted '
      'and builds only the visible columns ±1', (WidgetTester tester) async {
    final PageController pager = await _pump(tester);
    Map<int, Widget> prev = _columns(tester);
    final Set<int> everBuilt = <int>{...prev.keys};

    final TestGesture g = await tester.startGesture(
      tester.getCenter(find.byKey(WeekTimeGrid.pagerKey)),
    );
    for (int i = 0; i < 8; i++) {
      await g.moveBy(const Offset(-30, 0));
      await tester.pump();
      final int left = (pager.page ?? 0).floor();
      final Map<int, Widget> now = _columns(tester);
      for (final MapEntry<int, Widget> e in now.entries) {
        expect(
          e.key,
          inInclusiveRange(left - 1, left + 3),
          reason: 'column ${e.key} built at page $left — outside visible ±1',
        );
        // Mounted on the previous frame AND this one → the same element, so
        // the same widget instance unless something rebuilt it.
        final Widget? was = prev[e.key];
        if (was != null) {
          expect(identical(e.value, was), isTrue, reason: 'column ${e.key}');
        }
      }
      everBuilt.addAll(now.keys);
      prev = now;
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(everBuilt.length, lessThan(7), reason: 'never all seven built');
  });

  testWidgets('the strip cells are not rebuilt while the pager moves — only '
      'the window translates', (WidgetTester tester) async {
    await _pump(tester);
    Widget cells() => tester.widget(
      find
          .descendant(
            of: find.byKey(WeekStrip.daysKey),
            matching: find.byType(Row),
          )
          .first,
    );
    final Widget before = cells();
    final double windowBefore = tester
        .getTopLeft(find.byKey(WeekStrip.windowKey))
        .dx;

    await _dragFrames(tester, dx: -90);

    expect(identical(cells(), before), isTrue);
    expect(
      tester.getTopLeft(find.byKey(WeekStrip.windowKey)).dx,
      isNot(closeTo(windowBefore, 0.5)),
      reason: 'positive control: the window followed the pager',
    );
  });
}
