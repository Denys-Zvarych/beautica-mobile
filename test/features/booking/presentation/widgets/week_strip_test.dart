// Phase 484 — WeekStrip: live counts (cancelled / declined excluded), day-off
// ring, the window (3 vs 1 cells, follows `pageController.page`), strip
// drag scrubs the controller (8-sample recipe), tap → onTapDay, ‹ ›.
import 'dart:async';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart'
    show stableBookingList;
import 'package:beautica_mobile/features/booking/domain/bookings_week_state.dart';
import 'package:beautica_mobile/features/booking/domain/week_day_model.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart'
    show weekdayShortLabels;
import 'package:beautica_mobile/features/booking/presentation/widgets/week_nav_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// future-date-ok: pinned fixture week; `today` is injected, never the host.
final DateTime _monday = DateTime(2026, 11, 16);
final DateTime _today = kyivAddDays(_monday, 3); // Чт

int _seq = 0;

Booking _b(int day, BookingStatus status) {
  // future-date-ok: pinned fixture week (Kyiv 10:00 = 08:00 UTC in November).
  final DateTime start = DateTime.utc(2026, 11, 16 + day, 8);
  _seq++;
  return Booking(
    id: 'b$_seq',
    masterId: 'master-1',
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'INDEPENDENT_MASTER',
    clientFirstName: 'Клієнт',
    clientLastName: 'Коваль',
    serviceId: 'service-$_seq',
    serviceName: 'Манікюр',
    durationMinutes: 60,
    price: 600,
    startAt: start,
    endAt: start.add(const Duration(minutes: 60)),
    status: status,
    canReview: false,
  );
}

List<WeekDayModel> _days(List<Booking> all, {Set<int> off = const {}}) =>
    buildWeekDays(
      BookingsWeekState(
        weekStart: _monday,
        byDay: <DateTime, List<Booking>>{
          for (int i = 0; i < 7; i++)
            kyivAddDays(_monday, i): stableBookingList(<Booking>[
              for (final Booking b in all)
                if (kyivDayOf(b.startAt) == kyivAddDays(_monday, i)) b,
            ]),
        },
      ),
      schedule: <DateTime, EffectiveDay>{
        for (final int i in off)
          kyivAddDays(_monday, i): EffectiveDay(
            date: kyivAddDays(_monday, i),
            source: EffectiveSource.template,
            intervals: const <WorkInterval>[],
          ),
      },
    );

class _Harness extends StatelessWidget {
  const _Harness({
    required this.controller,
    required this.visibleColumns,
    required this.counts,
    required this.dayOff,
    this.onTapDay,
    this.onPrev,
    this.onNext,
  });

  final PageController controller;
  final int visibleColumns;
  final List<int> counts;
  final List<bool> dayOff;
  final ValueChanged<int>? onTapDay;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        WeekStrip(
          weekStart: _monday,
          today: _today,
          counts: counts,
          dayOff: dayOff,
          pageController: controller,
          visibleColumns: visibleColumns,
          onTapDay: onTapDay ?? (int _) {},
          onPrevWeek: onPrev ?? () {},
          onNextWeek: onNext ?? () {},
        ),
        // Stand-in for the week grid: the shared pager the strip follows.
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: controller,
            itemCount: kWeekGridDays,
            itemBuilder: (BuildContext context, int i) =>
                Center(child: Text('$i')),
          ),
        ),
      ],
    );
  }
}

const List<int> _noCounts = <int>[0, 0, 0, 0, 0, 0, 0];
const List<bool> _noOff = <bool>[
  false,
  false,
  false,
  false,
  false,
  false,
  false,
];

void main() {
  group('weekStripCounts / weekStripDayOff', () {
    test('cancelled and declined are not counted', () {
      final List<WeekDayModel> days = _days(<Booking>[
        _b(0, BookingStatus.confirmed),
        _b(0, BookingStatus.cancelled),
        _b(0, BookingStatus.declined),
        _b(1, BookingStatus.completed),
        _b(1, BookingStatus.notCompleted),
        _b(2, BookingStatus.cancelled),
      ]);
      expect(weekStripCounts(days), <int>[1, 2, 0, 0, 0, 0, 0]);
    });

    test('day off = a loaded schedule with no working time', () {
      final List<WeekDayModel> days = _days(const <Booking>[], off: {6});
      expect(weekStripDayOff(days), <bool>[
        false,
        false,
        false,
        false,
        false,
        false,
        true,
      ]);
    });
  });

  testWidgets('renders counts, day-off ring and today mark', (tester) async {
    final List<WeekDayModel> days = _days(
      <Booking>[
        _b(0, BookingStatus.confirmed),
        _b(0, BookingStatus.cancelled),
        _b(2, BookingStatus.declined),
      ],
      off: {6},
    );
    final PageController c = WeekTimeGrid.controllerFor(visibleColumns: 3);
    addTearDown(c.dispose);
    await tester.pumpApp(
      _Harness(
        controller: c,
        visibleColumns: 3,
        counts: weekStripCounts(days),
        dayOff: weekStripDayOff(days),
      ),
      width: 360,
    );

    final Text count = tester.widget<Text>(
      find.byKey(weekStripCountKey(_monday)),
    );
    expect(count.data, '1');
    // Only declined on Wednesday → no count.
    expect(
      find.byKey(weekStripCountKey(kyivAddDays(_monday, 2))),
      findsNothing,
    );
    expect(
      find.byKey(weekStripDayOffKey(kyivAddDays(_monday, 6))),
      findsOneWidget,
    );
    final Text todayNumber = tester.widget<Text>(
      find.descendant(
        of: find.byKey(weekStripDayKey(_today)),
        matching: find.text('${_today.day}'),
      ),
    );
    expect(todayNumber.style?.decoration, TextDecoration.underline);
  });

  double cellW(WidgetTester tester) =>
      tester.getSize(find.byKey(WeekStrip.daysKey)).width / 7;

  for (final int columns in <int>[3, 1]) {
    testWidgets('window is $columns cell(s) wide', (tester) async {
      final PageController c = WeekTimeGrid.controllerFor(
        visibleColumns: columns,
      );
      addTearDown(c.dispose);
      await tester.pumpApp(
        _Harness(
          controller: c,
          visibleColumns: columns,
          counts: _noCounts,
          dayOff: _noOff,
        ),
        width: 360,
      );
      expect(
        tester.getSize(find.byKey(WeekStrip.windowKey)).width,
        closeTo(cellW(tester) * columns - 4, 0.01),
      );
    });
  }

  testWidgets('window follows pageController.page', (tester) async {
    final PageController c = WeekTimeGrid.controllerFor(visibleColumns: 3);
    addTearDown(c.dispose);
    await tester.pumpApp(
      _Harness(
        controller: c,
        visibleColumns: 3,
        counts: _noCounts,
        dayOff: _noOff,
      ),
      width: 360,
    );
    final double origin = tester.getTopLeft(find.byKey(WeekStrip.daysKey)).dx;
    double windowLeft() =>
        tester.getTopLeft(find.byKey(WeekStrip.windowKey)).dx - origin;

    expect(windowLeft(), closeTo(2, 0.01));
    c.jumpToPage(3);
    await tester.pump();
    expect(windowLeft(), closeTo(3 * cellW(tester) + 2, 0.01));
    // A fractional position (mid-scroll) moves the window in step.
    c.jumpTo(c.position.pixels - c.position.viewportDimension / 3 / 2);
    await tester.pump();
    expect(windowLeft(), closeTo(2.5 * cellW(tester) + 2, 0.01));
  });

  testWidgets('drag along the strip scrubs the controller (8 samples)', (
    tester,
  ) async {
    final PageController c = WeekTimeGrid.controllerFor(visibleColumns: 3);
    addTearDown(c.dispose);
    await tester.pumpApp(
      _Harness(
        controller: c,
        visibleColumns: 3,
        counts: _noCounts,
        dayOff: _noOff,
      ),
      width: 360,
    );
    final double w = cellW(tester);
    final Offset start = tester.getCenter(find.byKey(weekStripDayKey(_monday)));
    final TestGesture g = await tester.startGesture(start);
    Duration stamp = Duration.zero;
    // Lead past the touch slop, then 8 samples covering two cells.
    stamp += const Duration(milliseconds: 16);
    await g.moveBy(const Offset(kTouchSlop + 1, 0), timeStamp: stamp);
    for (int i = 0; i < 8; i++) {
      stamp += const Duration(milliseconds: 16);
      await g.moveBy(Offset(2 * w / 8, 0), timeStamp: stamp);
      await tester.pump();
    }
    // Mid-drag the controller already moved with the finger.
    expect(c.page, closeTo(2, 0.05));
    // The finger rests before lifting → zero release velocity, so the
    // pager's own physics settles on the nearest day (a fling is (c)).
    // fixed-wait-ok: a rest longer than the velocity tracker's stop window.
    await tester.pump(const Duration(milliseconds: 100));
    await g.up();
    await tester.pumpAndSettle();
    expect(c.page, 2);
  });

  testWidgets('tap a day → onTapDay; ‹ › step weeks', (tester) async {
    final List<int> taps = <int>[];
    int prev = 0;
    int next = 0;
    final PageController c = WeekTimeGrid.controllerFor(visibleColumns: 3);
    addTearDown(c.dispose);
    await tester.pumpApp(
      _Harness(
        controller: c,
        visibleColumns: 3,
        counts: _noCounts,
        dayOff: _noOff,
        onTapDay: taps.add,
        onPrev: () => prev++,
        onNext: () => next++,
      ),
      width: 360,
    );
    await tester.tap(find.byKey(weekStripDayKey(kyivAddDays(_monday, 5))));
    expect(taps, <int>[5]);
    await tester.tap(find.byKey(WeekStepButton.prevKey));
    await tester.tap(find.byKey(WeekStepButton.nextKey));
    expect((prev, next), (1, 1));
  });

  group('cell marks', () {
    Text number(WidgetTester tester, int i) {
      final DateTime day = kyivAddDays(_monday, i);
      return tester.widget<Text>(
        find.descendant(
          of: find.byKey(weekStripDayKey(day)),
          matching: find.text('${day.day}'),
        ),
      );
    }

    testWidgets('today mark only on today; past dim, future plain; count '
        'colour by past / future; day off shows the ring, never a count', (
      tester,
    ) async {
      final PageController c = WeekTimeGrid.controllerFor(visibleColumns: 3);
      addTearDown(c.dispose);
      await tester.pumpApp(
        _Harness(
          controller: c,
          visibleColumns: 3,
          // Mon (past) 2, Fri (future) 4, Sun (day off) 5.
          counts: const <int>[2, 0, 0, 0, 4, 0, 5],
          dayOff: const <bool>[false, false, false, false, false, false, true],
        ),
        width: 360,
      );
      for (int i = 0; i < 7; i++) {
        final TextStyle style = number(tester, i).style!;
        if (i == 3) {
          expect(style.decoration, TextDecoration.underline);
          expect(style.fontWeight, FontWeight.w800);
          expect(style.color, BrandColors.accentDeep);
        } else {
          expect(style.decoration, TextDecoration.none, reason: 'day $i');
          expect(style.fontWeight, FontWeight.w700, reason: 'day $i');
          expect(
            style.color,
            i < 3 || i == 6 ? BrandColors.weekendMuted : BrandColors.text,
            reason: 'day $i',
          );
        }
      }
      Color? countColor(int i) => tester
          .widget<Text>(find.byKey(weekStripCountKey(kyivAddDays(_monday, i))))
          .style
          ?.color;
      expect(countColor(0), BrandColors.weekendMuted);
      expect(countColor(4), BrandColors.accentDeep);
      expect(
        find.byKey(weekStripCountKey(kyivAddDays(_monday, 6))),
        findsNothing,
      );
      expect(
        find.byKey(weekStripDayOffKey(kyivAddDays(_monday, 6))),
        findsOneWidget,
      );
    });

    testWidgets('today outside the shown week → no cell carries the mark', (
      tester,
    ) async {
      final PageController c = WeekTimeGrid.controllerFor(visibleColumns: 3);
      addTearDown(c.dispose);
      await tester.pumpApp(
        WeekStrip(
          weekStart: _monday,
          today: kyivAddDays(_monday, 7),
          counts: _noCounts,
          dayOff: _noOff,
          pageController: c,
          visibleColumns: 3,
          onTapDay: (_) {},
          onPrevWeek: () {},
          onNextWeek: () {},
        ),
        width: 360,
      );
      for (int i = 0; i < 7; i++) {
        expect(
          number(tester, i).style!.decoration,
          TextDecoration.none,
          reason: 'day $i',
        );
      }
    });

    testWidgets('a11y label: weekday + date, today, count / day off / none', (
      tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final AppLocalizations l10n = lookupAppLocalizations(const Locale('uk'));
      final PageController c = WeekTimeGrid.controllerFor(visibleColumns: 3);
      addTearDown(c.dispose);
      await tester.pumpApp(
        _Harness(
          controller: c,
          visibleColumns: 3,
          counts: const <int>[0, 0, 0, 2, 0, 0, 1],
          dayOff: const <bool>[false, false, false, false, false, false, true],
        ),
        width: 360,
      );
      String label(int i) => tester
          .getSemantics(find.byKey(weekStripDayKey(kyivAddDays(_monday, i))))
          .label;
      final String thu = l10n.masterBookingsDaySemantics(
        weekdayShortLabels(l10n)[3],
        _today.day,
      );
      expect(
        label(3),
        '$thu, ${l10n.masterWeekStripTodaySemantics}, '
        '${l10n.masterBookingsCount(2)}',
      );
      expect(label(0), endsWith(l10n.masterWeekStripNoBookingsSemantics));
      expect(label(6), endsWith(l10n.masterWeekStripDayOffSemantics));
      semantics.dispose();
    });
  });

  testWidgets('window tracks the controller on EVERY frame of an animated '
      'page change (no lag, no jump to the end)', (tester) async {
    final PageController c = WeekTimeGrid.controllerFor(visibleColumns: 3);
    addTearDown(c.dispose);
    await tester.pumpApp(
      _Harness(
        controller: c,
        visibleColumns: 3,
        counts: _noCounts,
        dayOff: _noOff,
      ),
      width: 360,
    );
    final double origin = tester.getTopLeft(find.byKey(WeekStrip.daysKey)).dx;
    final double w = cellW(tester);
    unawaited(
      c.animateToPage(
        4,
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
      ),
    );
    int midFrames = 0;
    for (int f = 0; f < 20; f++) {
      // fixed-wait-ok: stepping an animation frame by frame to sample it.
      await tester.pump(const Duration(milliseconds: 16));
      final double page = c.page!;
      if (page > 0.05 && page < 3.95) midFrames++;
      expect(
        tester.getTopLeft(find.byKey(WeekStrip.windowKey)).dx - origin,
        closeTo(page * w + 2, 0.01),
        reason: 'frame $f at page $page',
      );
    }
    expect(midFrames, greaterThan(5));
    await tester.pumpAndSettle();
    expect(c.page, 4);
  });

  testWidgets('tap on a day under the window reaches onTapDay; a tap never '
      'moves the grid itself (the host scrolls)', (tester) async {
    final List<int> taps = <int>[];
    final PageController c = WeekTimeGrid.controllerFor(
      visibleColumns: 3,
      firstVisibleDay: 4,
    );
    addTearDown(c.dispose);
    await tester.pumpApp(
      _Harness(
        controller: c,
        visibleColumns: 3,
        counts: _noCounts,
        dayOff: _noOff,
        onTapDay: taps.add,
      ),
      width: 360,
    );
    expect(c.page, 4);
    for (final int i in <int>[4, 5, 6, 0]) {
      await tester.tap(find.byKey(weekStripDayKey(kyivAddDays(_monday, i))));
      await tester.pumpAndSettle();
    }
    expect(taps, <int>[4, 5, 6, 0]);
    expect(c.page, 4);
  });

  testWidgets('host wiring onTapDay → animateToPage lands the window on the '
      'tapped day («День»)', (tester) async {
    final PageController c = WeekTimeGrid.controllerFor(visibleColumns: 1);
    addTearDown(c.dispose);
    await tester.pumpApp(
      _Harness(
        controller: c,
        visibleColumns: 1,
        counts: _noCounts,
        dayOff: _noOff,
        onTapDay: (int i) => c.animateToPage(
          i,
          duration: WeekStrip.settleDuration,
          curve: Curves.easeOutCubic,
        ),
      ),
      width: 360,
    );
    final Finder day5 = find.byKey(weekStripDayKey(kyivAddDays(_monday, 5)));
    await tester.tap(day5);
    await tester.pumpAndSettle();
    expect(c.page, 5);
    expect(
      tester.getCenter(find.byKey(WeekStrip.windowKey)).dx,
      closeTo(tester.getCenter(day5).dx, 0.5),
    );
  });

  testWidgets('360 dp ×1.3: no overflow, every weekday / date / count whole '
      'inside its cell', (tester) async {
    final PageController c = WeekTimeGrid.controllerFor(visibleColumns: 3);
    addTearDown(c.dispose);
    await tester.pumpApp(
      _Harness(
        controller: c,
        visibleColumns: 3,
        counts: const <int>[12, 3, 0, 9, 0, 0, 0],
        dayOff: const <bool>[false, false, false, false, false, true, false],
      ),
      width: 360,
      textScaleFactor: 1.3,
    );
    expect(tester.takeException(), isNull);
    for (int i = 0; i < 7; i++) {
      final Finder cell = find.byKey(weekStripDayKey(kyivAddDays(_monday, i)));
      final Rect cellRect = tester.getRect(cell);
      for (final Element e
          in find
              .descendant(of: cell, matching: find.byType(Text))
              .evaluate()) {
        final RenderParagraph p = e.renderObject! as RenderParagraph;
        expect(p.didExceedMaxLines, isFalse);
        expect(p.size.width, greaterThanOrEqualTo(p.getMaxIntrinsicWidth(0)));
        final Rect r = p.localToGlobal(Offset.zero) & p.size;
        expect(r.left, greaterThanOrEqualTo(cellRect.left - 0.5));
        expect(r.right, lessThanOrEqualTo(cellRect.right + 0.5));
        expect(r.bottom, lessThanOrEqualTo(cellRect.bottom + 0.5));
      }
    }
  });

  // ---------------------------------------------------------------------
  // Strip scrub perf (phase 484 audit fixes). (a)–(c) mount the REAL
  // phase-482 WeekTimeGrid on the shared controller, settle timer included.
  // ---------------------------------------------------------------------
  group('strip scrub perf', () {
    Future<PageController> pumpWithGrid(
      WidgetTester tester, {
      required int columns,
    }) async {
      final PageController c = WeekTimeGrid.controllerFor(
        visibleColumns: columns,
      );
      addTearDown(c.dispose);
      final List<WeekDayModel> days = _days(const <Booking>[]);
      await tester.pumpApp(
        Scaffold(
          body: Column(
            children: <Widget>[
              WeekStrip(
                weekStart: _monday,
                today: _today,
                counts: _noCounts,
                dayOff: _noOff,
                pageController: c,
                visibleColumns: columns,
                onTapDay: (_) {},
                onPrevWeek: () {},
                onNextWeek: () {},
              ),
              Expanded(
                child: WeekTimeGrid(
                  weekStart: _monday,
                  days: days,
                  today: _today,
                  // future-date-ok: pinned instant inside the fixture week.
                  now: DateTime.utc(2026, 11, 19, 10),
                  pageController: c,
                  visibleColumns: columns,
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
      return c;
    }

    /// Puts a finger on Monday's cell and scrubs [cells] cells in 8 samples
    /// of [every]; returns the still-down gesture.
    Future<TestGesture> scrub(
      WidgetTester tester,
      double cells, {
      Duration every = const Duration(milliseconds: 16),
      bool pumpFrames = true,
    }) async {
      final double w = cellW(tester);
      final TestGesture g = await tester.startGesture(
        tester.getCenter(find.byKey(weekStripDayKey(_monday))),
      );
      Duration stamp = every;
      await g.moveBy(const Offset(kTouchSlop + 1, 0), timeStamp: stamp);
      for (int i = 0; i < 8; i++) {
        stamp += every;
        await g.moveBy(Offset(cells * w / 8, 0), timeStamp: stamp);
        if (pumpFrames) await tester.pump(every);
      }
      return g;
    }

    testWidgets('(a) a finger held still on the strip > settleDelay does NOT '
        'snap the grid («3 дні», real WeekTimeGrid)', (tester) async {
      final PageController c = await pumpWithGrid(tester, columns: 3);
      final TestGesture g = await scrub(tester, 1.5);
      expect(c.page, closeTo(1.5, 0.05));
      // fixed-wait-ok: holding past WeekTimeGrid.settleDelay (180 ms) is
      // the behaviour under test.
      await tester.pump(const Duration(milliseconds: 300));
      // fixed-wait-ok: let any (wrong) settle animation run to its end.
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        c.page,
        closeTo(1.5, 0.05),
        reason: 'grid snapped under a held finger',
      );
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('(b) «День» (pageSnapping): a held mid-page scrub stays '
        'where the finger is — no spring-back between drag frames', (
      tester,
    ) async {
      final PageController c = await pumpWithGrid(tester, columns: 1);
      final TestGesture g = await scrub(tester, 0.4);
      expect(c.page, closeTo(0.4, 0.05), reason: 'sprang back mid-drag');
      // fixed-wait-ok: a held finger over several frames — a spring-back
      // would move the page here.
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        c.page,
        closeTo(0.4, 0.05),
        reason: 'sprang back under a held finger',
      );
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('(c) a fling off the strip carries momentum and settles via '
        'grid physics on a day boundary', (tester) async {
      final PageController c = await pumpWithGrid(tester, columns: 3);
      // ~1.2 cells in 64 ms: a fast fling forward.
      final TestGesture g = await scrub(
        tester,
        1.2,
        every: const Duration(milliseconds: 8),
        pumpFrames: false,
      );
      await tester.pump();
      final double released = c.page!;
      await g.up();
      await tester.pumpAndSettle();
      // fixed-wait-ok: past WeekTimeGrid.settleDelay so any snap has run.
      await tester.pump(WeekTimeGrid.settleDelay);
      await tester.pumpAndSettle();
      final double page = c.page!;
      expect(
        (page - page.round()).abs(),
        lessThan(0.01),
        reason: 'on a day boundary',
      );
      expect(
        page,
        greaterThan(released.roundToDouble()),
        reason:
            'released at $released; a fling must carry past the nearest '
            'day, not animate to round(page)',
      );
    });

    testWidgets('(d) a RepaintBoundary wraps the strip days (not the window)', (
      tester,
    ) async {
      final PageController c = WeekTimeGrid.controllerFor(visibleColumns: 3);
      addTearDown(c.dispose);
      await tester.pumpApp(
        _Harness(
          controller: c,
          visibleColumns: 3,
          counts: _noCounts,
          dayOff: _noOff,
        ),
        width: 360,
      );
      final Set<Element> inStrip = find
          .descendant(
            of: find.byKey(WeekStrip.daysKey),
            matching: find.byType(RepaintBoundary),
          )
          .evaluate()
          .toSet();
      final Set<Element> overWindow = find
          .ancestor(
            of: find.byKey(WeekStrip.windowKey),
            matching: find.byType(RepaintBoundary),
          )
          .evaluate()
          .toSet();
      for (int i = 0; i < 7; i++) {
        final Set<Element> overDay = find
            .ancestor(
              of: find.byKey(weekStripDayKey(kyivAddDays(_monday, i))),
              matching: find.byType(RepaintBoundary),
            )
            .evaluate()
            .toSet();
        expect(
          overDay.intersection(inStrip).difference(overWindow),
          isNotEmpty,
          reason: 'day $i is not behind its own RepaintBoundary',
        );
      }
    });

    testWidgets(
      '(e) the strip window NeumorphicInset has animatedRing: false',
      (tester) async {
        final PageController c = WeekTimeGrid.controllerFor(visibleColumns: 3);
        addTearDown(c.dispose);
        await tester.pumpApp(
          _Harness(
            controller: c,
            visibleColumns: 3,
            counts: _noCounts,
            dayOff: _noOff,
          ),
          width: 360,
        );
        expect(
          tester
              .widget<NeumorphicInset>(find.byKey(WeekStrip.windowKey))
              .animatedRing,
          isFalse,
        );
      },
    );

    testWidgets(
      '(f) the moving window sits behind its own RepaintBoundary, and the '
      'inset has a RepaintBoundary inside the translation',
      (tester) async {
        final PageController c = WeekTimeGrid.controllerFor(visibleColumns: 3);
        addTearDown(c.dispose);
        await tester.pumpApp(
          _Harness(
            controller: c,
            visibleColumns: 3,
            counts: _noCounts,
            dayOff: _noOff,
          ),
          width: 360,
        );
        final Finder outer = find.byKey(WeekStrip.windowLayerKey);
        final Finder inner = find.byKey(WeekStrip.windowInsetLayerKey);
        expect(tester.widget(outer), isA<RepaintBoundary>());
        expect(tester.widget(inner), isA<RepaintBoundary>());
        // Outer boundary wraps the translation; inner sits below it, directly
        // over the inset — so a scroll frame re-composites a cached layer.
        final Finder translate = find.descendant(
          of: outer,
          matching: find.byType(Transform),
        );
        expect(translate, findsOneWidget);
        expect(find.descendant(of: translate, matching: inner), findsOneWidget);
        expect(
          find.descendant(of: inner, matching: find.byKey(WeekStrip.windowKey)),
          findsOneWidget,
        );
        // Days are not inside the window's layer.
        expect(
          find.descendant(of: outer, matching: find.byKey(WeekStrip.daysKey)),
          findsNothing,
        );
      },
    );
  });

  // ---------------------------------------------------------------------
  // Scrub lifecycle: a scrub in flight drives the OLD controller only until
  // the strip loses it (controller swap) or leaves the tree (dispose) — then
  // the drag is cancelled and that pager settles on its own.
  // ---------------------------------------------------------------------
  group('strip scrub lifecycle', () {
    /// Two pagers (c1, c2) always mounted; the strip follows [strip]'s
    /// controller, or is absent while it holds null.
    Future<(PageController, PageController)> pumpTwoPagers(
      WidgetTester tester,
      ValueNotifier<PageController?> strip,
    ) async {
      final PageController c1 = WeekTimeGrid.controllerFor(visibleColumns: 3);
      final PageController c2 = WeekTimeGrid.controllerFor(visibleColumns: 3);
      addTearDown(c1.dispose);
      addTearDown(c2.dispose);
      strip.value = c1;
      Widget pager(PageController c) => SizedBox(
        height: 120,
        child: PageView.builder(
          controller: c,
          itemCount: kWeekGridDays,
          itemBuilder: (BuildContext context, int i) =>
              Center(child: Text('$i')),
        ),
      );
      await tester.pumpApp(
        Column(
          children: <Widget>[
            SizedBox(
              height: 120,
              child: ValueListenableBuilder<PageController?>(
                valueListenable: strip,
                builder: (BuildContext context, PageController? c, _) =>
                    c == null
                    ? const SizedBox.shrink()
                    : WeekStrip(
                        weekStart: _monday,
                        today: _today,
                        counts: _noCounts,
                        dayOff: _noOff,
                        pageController: c,
                        visibleColumns: 3,
                        onTapDay: (_) {},
                        onPrevWeek: () {},
                        onNextWeek: () {},
                      ),
              ),
            ),
            pager(c1),
            pager(c2),
          ],
        ),
        width: 360,
        height: 800,
      );
      return (c1, c2);
    }

    Future<TestGesture> scrubOneAndAHalf(WidgetTester tester) async {
      final double w = cellW(tester);
      final TestGesture g = await tester.startGesture(
        tester.getCenter(find.byKey(weekStripDayKey(_monday))),
      );
      await g.moveBy(const Offset(kTouchSlop + 1, 0));
      for (int i = 0; i < 6; i++) {
        await g.moveBy(Offset(1.5 * w / 6, 0));
        await tester.pump();
      }
      return g;
    }

    testWidgets('controller swap mid-scrub: the old pager is released and '
        'settles; the drag is not re-routed to the new one', (tester) async {
      final ValueNotifier<PageController?> strip =
          ValueNotifier<PageController?>(null);
      addTearDown(strip.dispose);
      final (PageController c1, PageController c2) = await pumpTwoPagers(
        tester,
        strip,
      );
      final TestGesture g = await scrubOneAndAHalf(tester);
      expect(c1.page, closeTo(1.5, 0.05));

      strip.value = c2;
      await tester.pump();
      await tester.pumpAndSettle();
      final double settled = c1.page!;
      await g.moveBy(Offset(2 * cellW(tester), 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();

      expect(
        (settled - settled.round()).abs(),
        lessThan(0.01),
        reason: 'old pager still held by the swapped-out scrub',
      );
      expect(c1.page, settled, reason: 'old pager moved after the swap');
      expect(c2.page, 0, reason: 'scrub re-routed to the new controller');
    });

    testWidgets('strip disposed mid-scrub: the pager is released and settles '
        'on a day boundary', (tester) async {
      final ValueNotifier<PageController?> strip =
          ValueNotifier<PageController?>(null);
      addTearDown(strip.dispose);
      final (PageController c1, _) = await pumpTwoPagers(tester, strip);
      final TestGesture g = await scrubOneAndAHalf(tester);
      expect(c1.page, closeTo(1.5, 0.05));

      strip.value = null;
      await tester.pump();
      await tester.pumpAndSettle();
      final double page = c1.page!;

      expect(
        (page - page.round()).abs(),
        lessThan(0.01),
        reason: 'pager still held by the disposed strip\'s drag',
      );
      expect(c1.position.isScrollingNotifier.value, isFalse);
      await g.up();
    });
  });
}
