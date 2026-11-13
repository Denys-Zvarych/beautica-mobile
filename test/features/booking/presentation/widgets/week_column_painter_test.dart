// Phase 483 — WeekColumnPainter bands + the grid's «Перерва» / «Вихідний»
// labels: band geometry for a 10–19 day in an 08–21 window, a 13–14 break
// with its label (hidden when the band is shorter than the pill), and ONE
// «Вихідний» per day-off column that follows the shared vertical scroll.
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart'
    show stableBookingList;
import 'package:beautica_mobile/features/booking/domain/bookings_week_state.dart';
import 'package:beautica_mobile/features/booking/domain/week_day_model.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_column_painter.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

final DateTime _monday = DateTime(2026, 11, 9);

WorkInterval _w(int sh, int sm, int eh, int em) => WorkInterval(
  start: TimeOfDay(hour: sh, minute: sm),
  end: TimeOfDay(hour: eh, minute: em),
);

EffectiveDay _day(List<WorkInterval> intervals, {List<TimeOfDay>? times}) =>
    EffectiveDay(
      date: _monday,
      source: EffectiveSource.template,
      intervals: intervals,
      times: times ?? const <TimeOfDay>[],
    );

WeekColumnPainter _painter(EffectiveDay? s, {bool isToday = false}) =>
    WeekColumnPainter(
      day: _monday,
      schedule: s,
      firstHour: 8,
      lastHour: 21,
      hourHeight: 72,
      isToday: isToday,
      topPad: 0,
    );

/// Monday [monday], the rest of the week 09:00–20:00 (window 08–21).
List<WeekDayModel> _days(EffectiveDay monday) => buildWeekDays(
  BookingsWeekState(
    weekStart: _monday,
    byDay: <DateTime, List<Booking>>{
      for (int i = 0; i < 7; i++)
        kyivAddDays(_monday, i): stableBookingList(const <Booking>[]),
    },
  ),
  schedule: <DateTime, EffectiveDay>{
    for (int i = 0; i < 7; i++)
      kyivAddDays(_monday, i): i == 0
          ? monday
          : _day(<WorkInterval>[_w(9, 0, 20, 0)]),
  },
);

Future<void> _pump(
  WidgetTester tester,
  EffectiveDay monday, {
  double? hourHeight,
  double scale = 1.0,
}) async {
  final PageController controller = WeekTimeGrid.controllerFor(
    visibleColumns: 3,
  );
  addTearDown(controller.dispose);
  await tester.pumpApp(
    Scaffold(
      body: WeekTimeGrid(
        weekStart: _monday,
        days: _days(monday),
        today: kyivAddDays(_monday, 14),
        // future-date-ok: fixed instant for a pure layout.
        now: DateTime.utc(2026, 11, 23, 7),
        pageController: controller,
        visibleColumns: 3,
        hourHeight: hourHeight,
        onBookingTap: (_) {},
        onTapHeader: (_) {},
        showsAllOccupancy: true,
      ),
    ),
    width: 360,
    height: 600,
    textScaleFactor: scale,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('bands', () {
    test('a 10–19 day in an 08–21 window: before-start and after-end', () {
      final EffectiveDay s = _day(<WorkInterval>[_w(10, 0, 19, 0)]);
      expect(weekOffBands(s, 8 * 60, 21 * 60), <MinuteRange>[
        (start: 480, end: 600),
        (start: 1140, end: 1260),
      ]);
      expect(_painter(s).offBandRects(const Size(100, 1000)), <Rect>[
        const Rect.fromLTRB(0, 0, 100, 144),
        const Rect.fromLTRB(0, 792, 100, 936),
      ]);
    });

    test('a 13–14 break is its own band, and a break', () {
      final EffectiveDay s = _day(<WorkInterval>[
        _w(14, 0, 19, 0),
        _w(10, 0, 13, 0), // unsorted on purpose
      ]);
      expect(weekBreaks(s), <MinuteRange>[(start: 780, end: 840)]);
      expect(weekOffBands(s, 480, 1260), <MinuteRange>[
        (start: 480, end: 600),
        (start: 780, end: 840),
        (start: 1140, end: 1260),
      ]);
    });

    test('day off and EXPLICIT_TIMES: one band over the window', () {
      const List<MinuteRange> whole = <MinuteRange>[(start: 480, end: 1260)];
      expect(weekOffBands(_day(const <WorkInterval>[]), 480, 1260), whole);
      expect(
        weekOffBands(
          _day(
            const <WorkInterval>[],
            times: const <TimeOfDay>[TimeOfDay(hour: 11, minute: 0)],
          ),
          480,
          1260,
        ),
        whole,
      );
    });

    test('schedule not loaded: no bands (no claim)', () {
      expect(weekOffBands(null, 480, 1260), isEmpty);
    });

    test('hatch segments are clipped to the band analytically: every '
        'endpoint inside, 45°, on the column-wide x − y = k·step lattice', () {
      const Rect band = Rect.fromLTRB(0, 144, 100, 230);
      final List<double> pts = WeekColumnPainter.hatchSegments(band);
      expect(pts, isNotEmpty);
      expect(pts.length % 4, 0);
      for (int i = 0; i < pts.length; i += 4) {
        final (double x0, double y0, double x1, double y1) = (
          pts[i],
          pts[i + 1],
          pts[i + 2],
          pts[i + 3],
        );
        for (final Offset p in <Offset>[Offset(x0, y0), Offset(x1, y1)]) {
          expect(p.dx, inInclusiveRange(band.left - 1e-3, band.right + 1e-3));
          expect(p.dy, inInclusiveRange(band.top - 1e-3, band.bottom + 1e-3));
        }
        expect(x1 - x0, moreOrLessEquals(y1 - y0, epsilon: 1e-3));
        expect(y1, greaterThan(y0));
        final double k = (x0 - y0) / WeekColumnPainter.hatchStep;
        expect(k, moreOrLessEquals(k.roundToDouble(), epsilon: 1e-3));
      }
    });

    test('shouldRepaint: same day/window/today → false; changes → true', () {
      final EffectiveDay s = _day(<WorkInterval>[_w(10, 0, 19, 0)]);
      expect(_painter(s).shouldRepaint(_painter(s)), isFalse);
      expect(
        _painter(
          s,
        ).shouldRepaint(_painter(_day(<WorkInterval>[_w(10, 0, 19, 0)]))),
        isTrue,
      );
      expect(_painter(s, isToday: true).shouldRepaint(_painter(s)), isTrue);
    });
  });

  group('labels', () {
    testWidgets('break 13–14 shows «Перерва»', (WidgetTester tester) async {
      await _pump(
        tester,
        _day(<WorkInterval>[_w(10, 0, 13, 0), _w(14, 0, 19, 0)]),
      );
      final Finder label = find.byKey(WeekTimeGrid.breakLabelKey(0, 780));
      expect(label, findsOneWidget);
      final AppLocalizations l10n = AppLocalizations.of(tester.element(label));
      expect(
        find.descendant(
          of: label,
          matching: find.text(l10n.masterWeekBreakLabel),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a break band shorter than the pill has no label', (
      WidgetTester tester,
    ) async {
      // 13:00–13:15 at 72 dp/h = 18 dp < pill (16.5) + clearance (6).
      await _pump(
        tester,
        _day(<WorkInterval>[_w(10, 0, 13, 0), _w(13, 15, 19, 0)]),
      );
      expect(find.byKey(WeekTimeGrid.breakLabelKey(0, 780)), findsNothing);
    });

    // mobile-qa — the pill's height (and so the threshold) scales with text.
    testWidgets('textScaler 1.3: a 15-min break has no «Перерва», an 18-min '
        'break does', (WidgetTester tester) async {
      // 3 дні at 1.3: 93.6 dp/h; pill 20.25 + clearance 6 = 26.25 dp.
      // 15 min = 23.4 dp (hidden), 18 min = 28.08 dp (shown — and hidden at
      // 1.0, where 21.6 dp < 22.5, so this pins the SCALED threshold).
      await _pump(
        tester,
        _day(<WorkInterval>[
          _w(10, 0, 13, 0),
          _w(13, 15, 15, 0),
          _w(15, 18, 19, 0),
        ]),
        scale: 1.3,
      );
      expect(find.byKey(WeekTimeGrid.breakLabelKey(0, 780)), findsNothing);
      expect(find.byKey(WeekTimeGrid.breakLabelKey(0, 900)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('day off: exactly one «Вихідний», still visible after a '
        'vertical scroll to the bottom', (WidgetTester tester) async {
      await _pump(tester, _day(const <WorkInterval>[]));
      final Finder label = find.byKey(WeekTimeGrid.dayOffLabelKey(0));
      expect(label, findsOneWidget);
      final AppLocalizations l10n = AppLocalizations.of(tester.element(label));
      // One in the column (the header's hours line is the other text).
      expect(
        find.descendant(
          of: find.byKey(WeekTimeGrid.columnKey(0)),
          matching: find.text(l10n.salonBookingsColumnDayOff),
        ),
        findsOneWidget,
      );

      final Rect viewport = tester.getRect(
        find.byKey(WeekTimeGrid.verticalScrollKey),
      );
      final Finder pill = find.descendant(
        of: label,
        matching: find.text(l10n.salonBookingsColumnDayOff),
      );
      final double before = tester.getCenter(pill).dy;
      expect(viewport.contains(tester.getCenter(pill)), isTrue);

      final ScrollableState v = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(WeekTimeGrid.verticalScrollKey),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      v.position.jumpTo(v.position.maxScrollExtent);
      await tester.pump();

      final Offset after = tester.getCenter(pill);
      expect(viewport.contains(after), isTrue);
      // Pinned to the viewport's vertical centre, not to the content.
      expect(after.dy, moreOrLessEquals(viewport.center.dy, epsilon: 1));
      expect(before, moreOrLessEquals(viewport.center.dy, epsilon: 1));
    });

    testWidgets('a working day has no «Вихідний» label', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _day(<WorkInterval>[_w(10, 0, 19, 0)]));
      expect(find.byKey(WeekTimeGrid.dayOffLabelKey(0)), findsNothing);
    });

    // mobile-qa — pinned «Вихідний» at top / middle / bottom scroll.
    testWidgets('day off: «Вихідний» stays centred in the visible viewport at '
        'top, middle and bottom scroll', (WidgetTester tester) async {
      await _pump(tester, _day(const <WorkInterval>[]));
      final Finder label = find.byKey(WeekTimeGrid.dayOffLabelKey(0));
      final AppLocalizations l10n = AppLocalizations.of(tester.element(label));
      final Finder pill = find.descendant(
        of: label,
        matching: find.text(l10n.salonBookingsColumnDayOff),
      );
      final Rect viewport = tester.getRect(
        find.byKey(WeekTimeGrid.verticalScrollKey),
      );
      final ScrollPosition v = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(WeekTimeGrid.verticalScrollKey),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      // The grid must actually scroll, or "middle"/"bottom" pin nothing.
      expect(v.maxScrollExtent, greaterThan(200));

      for (final double fraction in <double>[0, 0.5, 1]) {
        v.jumpTo(v.maxScrollExtent * fraction);
        await tester.pump();
        expect(
          tester.getCenter(pill).dy,
          moreOrLessEquals(viewport.center.dy, epsilon: 1),
          reason: 'scroll fraction $fraction',
        );
      }
      expect(label, findsOneWidget);
    });

    // Phase 492 fix — the opening jumpTo(0) on a non-today week is a no-op
    // (no scroll notification), and a viewport resize never moves the offset
    // either: the pill must re-pin from the scroll METRICS, not only from
    // the controller.
    testWidgets('day off, non-today week: «Вихідний» is viewport-centred on '
        'open with no scroll, and again after a viewport resize', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _day(const <WorkInterval>[]));
      final Finder label = find.byKey(WeekTimeGrid.dayOffLabelKey(0));
      final AppLocalizations l10n = AppLocalizations.of(tester.element(label));
      final Finder pill = find.descendant(
        of: label,
        matching: find.text(l10n.salonBookingsColumnDayOff),
      );
      final Finder scroll = find.byKey(WeekTimeGrid.verticalScrollKey);

      final Rect before = tester.getRect(scroll);
      expect(
        tester.getCenter(pill).dy,
        moreOrLessEquals(before.center.dy, epsilon: 1),
        reason: 'open, no scroll',
      );

      tester.view.physicalSize = Size(
        tester.view.physicalSize.width,
        700 * tester.view.devicePixelRatio,
      );
      await tester.pump();
      await tester.pump();

      final Rect after = tester.getRect(scroll);
      // The resize must really change the viewport, or this pins nothing.
      expect(after.height, greaterThan(before.height + 50));
      expect(
        tester.getCenter(pill).dy,
        moreOrLessEquals(after.center.dy, epsilon: 1),
        reason: 'after 600 → 700 resize',
      );
    });
  });

  group('window (mobile-qa)', () {
    // mobile-qa — the column painter receives the earliest start .. the
    // latest end, floored / ceiled to whole hours, with no margin (phase 492).
    testWidgets('window = earliest start .. latest end, no margin', (
      WidgetTester tester,
    ) async {
      // Monday 07:30–22:15 widens the 09–20 rest of the week → 07..23.
      await _pump(tester, _day(<WorkInterval>[_w(7, 30, 22, 15)]));
      final WeekColumnPainter p =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byKey(WeekTimeGrid.columnKey(1)),
                      matching: find.byWidgetPredicate(
                        (Widget w) =>
                            w is CustomPaint && w.painter is WeekColumnPainter,
                      ),
                    ),
                  )
                  .painter!
              as WeekColumnPainter;
      expect((p.firstHour, p.lastHour), (7, 23));
    });
  });

  group('repaint isolation', () {
    // mobile-qa — the column painter is wrapped in its own RepaintBoundary
    // inside the column, so a card press (ink splash) does not repaint the
    // hatch.
    testWidgets('the column painter sits under its own '
        'RepaintBoundary inside the column', (WidgetTester tester) async {
      await _pump(tester, _day(<WorkInterval>[_w(10, 0, 19, 0)]));
      final Finder column = find.byKey(WeekTimeGrid.columnKey(0));
      final Finder painter = find.descendant(
        of: column,
        matching: find.byWidgetPredicate(
          (Widget w) => w is CustomPaint && w.painter is WeekColumnPainter,
        ),
      );
      expect(painter, findsOneWidget);
      expect(
        find.descendant(
          of: column,
          matching: find.ancestor(
            of: painter,
            matching: find.byType(RepaintBoundary),
          ),
        ),
        findsWidgets,
      );
    });
  });
}
