// Phase 482 — WeekTimeGrid: 7-column pager (3 or 1 visible), day-snap
// momentum, 180 ms settle snap, header-row drag forwarding, ONE shared
// vertical scroll, card geometry, now-line.
//
// The settle snap is a real Timer (decision D2). `pumpAndSettle` does not
// wait for it (it stops once no frame is scheduled), so every test that ends
// a scroll pumps [WeekTimeGrid.settleDelay] explicitly before asserting the
// rest position — and a pre-snap assertion uses a single-frame `pump()`,
// because any timed pump (pumpAndSettle's 100 ms steps too) can run it.
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart'
    show stableBookingList;
import 'package:beautica_mobile/features/booking/domain/bookings_week_state.dart';
import 'package:beautica_mobile/features/booking/domain/week_day_model.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// Mon 9 – Sun 15 November 2026 (Kyiv UTC+2). Every day works 09:00–18:00,
// so the shared window is 08:00–19:00.
final DateTime _monday = DateTime(2026, 11, 9);
const int _kFirstHour = 8;

/// A Kyiv wall-clock instant on day [dayIndex] (0 = Monday) of the week.
DateTime _kyiv(int dayIndex, int h, [int m = 0]) =>
    // Fixed instants fed to a pure layout; the injected `now` is fixed too.
    // future-date-ok: nothing here compares against the host clock.
    DateTime.utc(2026, 11, 9 + dayIndex, h - 2, m);

Booking _booking(String id, DateTime startAt, {int minutes = 30}) => Booking(
  id: id,
  masterId: 'master-1',
  masterFirstName: 'Оля',
  masterLastName: 'Коваль',
  masterType: 'INDEPENDENT_MASTER',
  clientFirstName: 'Олена',
  clientLastName: 'Коваленко',
  serviceId: 'service-1',
  serviceName: 'Манікюр',
  durationMinutes: minutes,
  price: 500,
  startAt: startAt,
  endAt: startAt.add(Duration(minutes: minutes)),
  status: BookingStatus.confirmed,
  canReview: false,
);

List<WeekDayModel> _days({Map<int, List<Booking>> bookings = const {}}) {
  final BookingsWeekState week = BookingsWeekState(
    weekStart: _monday,
    byDay: <DateTime, List<Booking>>{
      for (int i = 0; i < 7; i++)
        kyivAddDays(_monday, i): stableBookingList(
          bookings[i] ?? const <Booking>[],
        ),
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

Future<PageController> _pump(
  WidgetTester tester, {
  int visibleColumns = 3,
  double width = 360,
  double scale = 1.0,
  int todayIndex = 2,
  Map<int, List<Booking>> bookings = const {},
  DateTime? now,
  double? hourHeight,
  ValueChanged<int>? onTapHeader,
  ValueChanged<Booking>? onBookingTap,
}) async {
  final PageController controller = WeekTimeGrid.controllerFor(
    visibleColumns: visibleColumns,
  );
  addTearDown(controller.dispose);
  final DateTime today = kyivAddDays(_monday, todayIndex);
  await tester.pumpApp(
    Scaffold(
      body: WeekTimeGrid(
        weekStart: _monday,
        days: _days(bookings: bookings),
        today: today,
        now: now ?? _kyiv(todayIndex, 13, 40),
        pageController: controller,
        visibleColumns: visibleColumns,
        hourHeight: hourHeight,
        onBookingTap: onBookingTap ?? (_) {},
        onTapHeader: onTapHeader ?? (_) {},
        showsAllOccupancy: true,
      ),
    ),
    width: width,
    height: 800,
    textScaleFactor: scale,
  );
  await tester.pumpAndSettle();
  return controller;
}

final Finder _pager = find.byKey(WeekTimeGrid.pagerKey);

double _columnExtent(PageController c) => c.position.viewportDimension / 3;

void _expectOnDayBoundary(PageController c) {
  final double days = c.position.pixels / _columnExtent(c);
  expect(
    (days - days.round()).abs(),
    lessThan(0.01),
    reason: 'rests on a day boundary, got $days days',
  );
}

/// The `integration_test/support/pager_drag.dart` recipe: EIGHT pointer
/// samples on synthetic timestamps so the velocity tracker sees a real
/// fling. [dx] per sample, [every] between samples.
Future<void> _drag(
  WidgetTester tester,
  Finder target, {
  required Offset step,
  Duration every = const Duration(milliseconds: 8),
  bool stopBeforeUp = false,
  double leadIn = 0,
}) async {
  final TestGesture g = await tester.startGesture(tester.getCenter(target));
  Duration stamp = Duration.zero;
  if (leadIn != 0) {
    // Crosses the touch slop in one sample so the slow samples after it
    // carry the drag (the recipe's `slopLeadIn`).
    stamp += every;
    await g.moveBy(Offset(leadIn, 0), timeStamp: stamp);
    await tester.pump(every);
  }
  for (int i = 0; i < 8; i++) {
    stamp += every;
    await g.moveBy(step, timeStamp: stamp);
    await tester.pump(every);
  }
  if (stopBeforeUp) {
    // fixed-wait-ok: holding the pointer still past the velocity tracker's
    // 40 ms "stopped" horizon so the release carries ZERO velocity.
    await tester.pump(const Duration(milliseconds: 100));
  }
  await g.up();
}

/// Lets a fling finish, then explicitly runs out the settle Timer and the snap
/// animation it starts.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(WeekTimeGrid.settleDelay);
  await tester.pumpAndSettle();
}

void main() {
  group('visible columns', () {
    for (final double width in <double>[360, 412]) {
      testWidgets('3 дні: three columns fill the pager at $width dp', (
        WidgetTester tester,
      ) async {
        await _pump(tester, width: width);
        final Rect pager = tester.getRect(_pager);
        for (int i = 0; i < 3; i++) {
          final Rect col = tester.getRect(
            find.byKey(WeekTimeGrid.columnKey(i)),
          );
          expect(col.width, closeTo(pager.width / 3, 0.01));
          expect(col.left, closeTo(pager.left + i * pager.width / 3, 0.01));
          // The pinned header sits above its own column.
          final Rect head = tester.getRect(
            find.byKey(WeekTimeGrid.headerKey(i)),
          );
          expect(head.left, closeTo(col.left, 0.01));
        }
        final Finder fourth = find.byKey(WeekTimeGrid.columnKey(3));
        if (fourth.evaluate().isNotEmpty) {
          expect(
            tester.getRect(fourth).left,
            greaterThanOrEqualTo(pager.right - 0.01),
          );
        }
      });
    }

    testWidgets('День: one column fills the pager', (
      WidgetTester tester,
    ) async {
      await _pump(tester, visibleColumns: 1);
      final Rect pager = tester.getRect(_pager);
      final Rect col = tester.getRect(find.byKey(WeekTimeGrid.columnKey(0)));
      expect(col.width, closeTo(pager.width, 0.01));
      expect(tester.widget<PageView>(_pager).pageSnapping, isTrue);
    });
  });

  group('3 дні horizontal scrolling', () {
    testWidgets('custom physics survive: pageSnapping is false', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      expect(tester.widget<PageView>(_pager).pageSnapping, isFalse);
    });

    testWidgets('a hard fling travels ≥ 3 days and lands on a whole column', (
      WidgetTester tester,
    ) async {
      final PageController c = await _pump(tester);
      await _drag(tester, _pager, step: const Offset(-40, 0));
      await _settle(tester);
      expect((c.page ?? -1).round(), greaterThanOrEqualTo(3));
      _expectOnDayBoundary(c);
    });

    testWidgets('slow drag + release is not snapped until 180 ms, then is', (
      WidgetTester tester,
    ) async {
      final PageController c = await _pump(tester);
      await _drag(
        tester,
        _pager,
        // 1 dp per 40 ms = 25 dp/s, under the 50 dp/s fling threshold:
        // the release is a ZERO-velocity end.
        step: const Offset(-1, 0),
        every: const Duration(milliseconds: 40),
        leadIn: -40,
        stopBeforeUp: true,
      );
      // One frame only: a timed pump (pumpAndSettle's 100 ms steps included)
      // would already run the settle Timer.
      await tester.pump();
      final double released = c.position.pixels;
      expect(released, greaterThan(0));
      final double days = released / _columnExtent(c);
      expect(
        (days - days.round()).abs(),
        greaterThan(0.05),
        reason: 'zero-velocity release stays where the finger left it',
      );
      // fixed-wait-ok: asserting the settle window has NOT yet elapsed.
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.position.pixels, released);
      await tester.pump(
        // fixed-wait-ok: crossing the remaining settle window exactly.
        const Duration(milliseconds: 80),
      );
      await tester.pumpAndSettle();
      _expectOnDayBoundary(c);
    });

    testWidgets('a finger resting in the settle window is never snapped '
        'under; the release re-arms the snap', (WidgetTester tester) async {
      final PageController c = await _pump(tester);
      await _drag(
        tester,
        _pager,
        step: const Offset(-1, 0),
        every: const Duration(milliseconds: 40),
        leadIn: -40,
        stopBeforeUp: true,
      );
      await tester.pump();
      final double released = c.position.pixels;
      expect(
        (released / _columnExtent(c) - (released / _columnExtent(c)).round())
            .abs(),
        greaterThan(0.05),
        reason: 'positive control: the release is off a day boundary',
      );

      // fixed-wait-ok: touching down INSIDE the 180 ms settle window.
      await tester.pump(const Duration(milliseconds: 60));
      final TestGesture hold = await tester.startGesture(
        tester.getCenter(_pager),
      );
      // fixed-wait-ok: resting well past the settle window, no movement.
      await tester.pump(const Duration(milliseconds: 800));
      expect(c.position.pixels, released, reason: 'not yanked under the hold');

      await hold.up();
      await _settle(tester);
      _expectOnDayBoundary(c);
    });

    testWidgets('a header-row drag moves the grid (same fling + snap)', (
      WidgetTester tester,
    ) async {
      final PageController c = await _pump(tester);
      await _drag(
        tester,
        find.byKey(WeekTimeGrid.headerRowKey),
        step: const Offset(-40, 0),
      );
      await _settle(tester);
      expect(c.position.pixels, greaterThan(0));
      _expectOnDayBoundary(c);
      // The header row followed: header 0 left == column 0 left.
      final Finder col = find.byKey(
        WeekTimeGrid.columnKey((c.page ?? -1).round()),
      );
      final Finder head = find.byKey(
        WeekTimeGrid.headerKey((c.page ?? -1).round()),
      );
      expect(tester.getRect(head).left, closeTo(tester.getRect(col).left, 0.5));
    });

    testWidgets('День pages one day per swipe', (WidgetTester tester) async {
      final PageController c = await _pump(tester, visibleColumns: 1);
      await _drag(tester, _pager, step: const Offset(-40, 0));
      await _settle(tester);
      expect(c.page, 1);
    });
  });

  testWidgets('vertical scroll of one column moves the ruler + every column', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      bookings: <int, List<Booking>>{
        0: <Booking>[_booking('a', _kyiv(0, 15))],
        1: <Booking>[_booking('b', _kyiv(1, 15))],
      },
    );
    final Finder ruler = find.text('15:00');
    final Finder cardA = find.byKey(WeekTimeGrid.cardKey('a'));
    final Finder cardB = find.byKey(WeekTimeGrid.cardKey('b'));
    final double rulerY = tester.getTopLeft(ruler).dy;
    final double aY = tester.getTopLeft(cardA).dy;
    final double bY = tester.getTopLeft(cardB).dy;

    // The vertical scroll view's centre is on column 1 (360 dp: ruler 42,
    // columns 106 wide) — a column's own centre is below the fold.
    final Offset onColumn1 = tester.getCenter(
      find.byKey(WeekTimeGrid.verticalScrollKey),
    );
    expect(
      tester.getRect(find.byKey(WeekTimeGrid.columnKey(1))).contains(onColumn1),
      isTrue,
    );
    // The grid opens an hour into the window, so dragging DOWN (toward
    // the earlier hours) always has room to scroll.
    await tester.dragFrom(onColumn1, const Offset(0, 100));
    await _settle(tester);

    final double moved = tester.getTopLeft(ruler).dy - rulerY;
    expect(moved, greaterThan(50));
    expect(tester.getTopLeft(cardA).dy - aY, closeTo(moved, 0.01));
    expect(tester.getTopLeft(cardB).dy - bY, closeTo(moved, 0.01));
  });

  group('card geometry', () {
    for (final double scale in <double>[1.0, 1.3]) {
      testWidgets('09:00–09:30 at 72 dp/h × $scale', (
        WidgetTester tester,
      ) async {
        await _pump(
          tester,
          scale: scale,
          bookings: <int, List<Booking>>{
            0: <Booking>[_booking('nine', _kyiv(0, 9))],
          },
        );
        final double hour = 72 * scale;
        final Rect col = tester.getRect(find.byKey(WeekTimeGrid.columnKey(0)));
        final Rect card = tester.getRect(
          find.byKey(WeekTimeGrid.cardKey('nine')),
        );
        // top = nudge 7 + (09:00 − 08:00) × band + half the 2 dp gap.
        expect(
          card.top - col.top,
          closeTo(WeekTimeGrid.topPad + (9 - _kFirstHour) * hour + 1, 0.01),
        );
        expect(card.height, closeTo(hour / 2 - 2, 0.01));
        expect(card.width, closeTo(col.width - 4, 0.01), reason: 'no lanes');
      });
    }
  });

  group('now-line', () {
    testWidgets('only on today\'s column', (WidgetTester tester) async {
      await _pump(tester, todayIndex: 1);
      final Finder line = find.byKey(WeekTimeGrid.nowLineKey);
      expect(line, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(WeekTimeGrid.columnKey(1)),
          matching: line,
        ),
        findsOneWidget,
      );
      expect(find.byKey(WeekTimeGrid.nowPillKey), findsOneWidget);
      expect(find.text('13:40'), findsOneWidget);
    });

    testWidgets('absent when today is outside the week', (
      WidgetTester tester,
    ) async {
      await _pump(tester, todayIndex: 9);
      expect(find.byKey(WeekTimeGrid.nowLineKey), findsNothing);
      expect(find.byKey(WeekTimeGrid.nowPillKey), findsNothing);
    });
  });

  testWidgets('reduced motion: no entrance animation', (
    WidgetTester tester,
  ) async {
    final AnimationController entrance = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 600),
    );
    addTearDown(entrance.dispose);
    final PageController controller = WeekTimeGrid.controllerFor(
      visibleColumns: 3,
    );
    addTearDown(controller.dispose);
    await tester.pumpApp(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: WeekTimeGrid(
            weekStart: _monday,
            days: _days(),
            today: _monday,
            now: _kyiv(0, 13, 40),
            pageController: controller,
            visibleColumns: 3,
            onBookingTap: (_) {},
            onTapHeader: (_) {},
            showsAllOccupancy: true,
            entrance: entrance,
          ),
        ),
      ),
      width: 360,
      height: 800,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(WeekTimeGrid.columnKey(0)),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byKey(WeekTimeGrid.columnKey(0)),
        matching: find.byType(Opacity),
      ),
      findsNothing,
      reason: 'entrance at 0 would hide the column if it were applied',
    );
  });

  group('3 дні fling bounds + boundary (mobile-qa)', () {
    testWidgets('a hard fling from Monday reaches Sunday as the last column', (
      WidgetTester tester,
    ) async {
      final PageController c = await _pump(tester);
      await _drag(tester, _pager, step: const Offset(-60, 0));
      await _settle(tester);

      expect(c.position.pixels, closeTo(c.position.maxScrollExtent, 0.5));
      expect((c.page ?? -1).round(), 4, reason: 'Thu..Sun: Sunday last');
      final Rect pager = tester.getRect(_pager);
      expect(
        tester.getRect(find.byKey(WeekTimeGrid.columnKey(6))).right,
        closeTo(pager.right, 0.5),
      );
    });

    testWidgets(
      'a mid-week fling rests on a boundary BEFORE the settle Timer',
      (WidgetTester tester) async {
        final PageController c = await _pump(tester);
        await _drag(tester, _pager, step: const Offset(-8, 0));
        // Frame by frame until the ballistic ends; the settle Timer needs a
        // further 180 ms, so whatever rests here is the PHYSICS' landing.
        int frames = 0;
        while (c.position.isScrollingNotifier.value && frames < 200) {
          // fixed-wait-ok: one 16 ms frame per step, stops at ballistic end.
          await tester.pump(const Duration(milliseconds: 16));
          frames++;
        }
        expect(c.position.isScrollingNotifier.value, isFalse);
        expect(c.position.pixels, greaterThan(0));
        expect(c.position.pixels, lessThan(c.position.maxScrollExtent));
        _expectOnDayBoundary(c);
      },
    );

    testWidgets(
      'a new drag inside the settle window cancels the pending snap',
      (WidgetTester tester) async {
        final PageController c = await _pump(tester);
        await _drag(
          tester,
          _pager,
          step: const Offset(-1, 0),
          every: const Duration(milliseconds: 40),
          leadIn: -40,
          stopBeforeUp: true,
        );
        await tester.pump();
        // fixed-wait-ok: inside the 180 ms settle window.
        await tester.pump(const Duration(milliseconds: 100));

        final double released = c.position.pixels;
        final TestGesture g = await tester.startGesture(
          tester.getCenter(_pager),
        );
        for (int i = 0; i < 3; i++) {
          await g.moveBy(const Offset(-15, 0));
          await tester.pump();
        }
        final double held = c.position.pixels;
        expect(held, isNot(released), reason: 'the new drag is live');
        final double heldDays = held / _columnExtent(c);
        expect((heldDays - heldDays.round()).abs(), greaterThan(0.05));
        // fixed-wait-ok: well past the first release's settle deadline; the
        // pumpAndSettle after it runs any snap animation that timer started.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(c.position.pixels, held, reason: 'no snap under a held finger');
        await g.up();
        await _settle(tester);
        _expectOnDayBoundary(c);
      },
    );

    testWidgets('a slow header-row drag also settles on a day after 180 ms', (
      WidgetTester tester,
    ) async {
      final PageController c = await _pump(tester);
      await _drag(
        tester,
        find.byKey(WeekTimeGrid.headerRowKey),
        step: const Offset(-1, 0),
        every: const Duration(milliseconds: 40),
        leadIn: -40,
        stopBeforeUp: true,
      );
      await tester.pump();
      final double days = c.position.pixels / _columnExtent(c);
      expect((days - days.round()).abs(), greaterThan(0.05));

      await tester.pump(WeekTimeGrid.settleDelay);
      await tester.pumpAndSettle();

      _expectOnDayBoundary(c);
    });
  });

  group('hour band (mobile-qa)', () {
    testWidgets(
      '3 дні at ×1.3: ruler labels share the columns\' 93.6 dp band',
      (WidgetTester tester) async {
        await _pump(
          tester,
          scale: 1.3,
          bookings: <int, List<Booking>>{
            0: <Booking>[_booking('ten', _kyiv(0, 10))],
          },
        );
        const double hour = 72 * 1.3;
        // i18n-finder-ok: wall-clock digits, not localised copy.
        final double l10 = tester.getTopLeft(find.text('10:00')).dy;
        // i18n-finder-ok: wall-clock digits, not localised copy.
        final double l11 = tester.getTopLeft(find.text('11:00')).dy;
        expect(l11 - l10, closeTo(hour, 0.01));

        final Rect col = tester.getRect(find.byKey(WeekTimeGrid.columnKey(0)));
        final Rect card = tester.getRect(
          find.byKey(WeekTimeGrid.cardKey('ten')),
        );
        expect(
          card.top - col.top,
          closeTo(WeekTimeGrid.topPad + (10 - _kFirstHour) * hour + 1, 0.01),
        );
      },
    );

    testWidgets('День keeps the shipped 120 dp band at ×1.3', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        visibleColumns: 1,
        scale: 1.3,
        bookings: <int, List<Booking>>{
          0: <Booking>[_booking('nine', _kyiv(0, 9))],
        },
      );
      final Rect col = tester.getRect(find.byKey(WeekTimeGrid.columnKey(0)));
      final Rect card = tester.getRect(
        find.byKey(WeekTimeGrid.cardKey('nine')),
      );
      expect(
        card.top - col.top,
        closeTo(WeekTimeGrid.topPad + (9 - _kFirstHour) * 120 + 1, 0.01),
      );
    });

    testWidgets('an explicit hourHeight overrides the mode default', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        hourHeight: 100,
        bookings: <int, List<Booking>>{
          0: <Booking>[_booking('nine', _kyiv(0, 9))],
        },
      );
      final Rect card = tester.getRect(
        find.byKey(WeekTimeGrid.cardKey('nine')),
      );
      expect(card.height, closeTo(100 / 2 - 2, 0.01));
    });
  });

  group('card placement (mobile-qa)', () {
    for (final int visible in <int>[3, 1]) {
      testWidgets(
        'visibleColumns $visible: Positioned, never IntrinsicHeight',
        (WidgetTester tester) async {
          await _pump(
            tester,
            visibleColumns: visible,
            bookings: <int, List<Booking>>{
              0: <Booking>[_booking('p', _kyiv(0, 11), minutes: 90)],
            },
          );
          final Finder card = find.byKey(WeekTimeGrid.cardKey('p'));
          expect(
            find.ancestor(of: card, matching: find.byType(Positioned)),
            findsWidgets,
          );
          expect(
            find.ancestor(of: card, matching: find.byType(IntrinsicHeight)),
            findsNothing,
          );
          expect(
            find.descendant(of: card, matching: find.byType(IntrinsicHeight)),
            findsNothing,
          );
          final double hour = visible == 3 ? 72 : 120;
          // 90 min: «3 дні» exact slot; «День» the slot is a floor.
          final double h = tester.getSize(card).height;
          if (visible == 3) {
            expect(h, closeTo(1.5 * hour - 2, 0.01));
          } else {
            expect(h, greaterThanOrEqualTo(1.5 * hour - 0.01));
          }
        },
      );
    }

    testWidgets('tapping a card reports that booking', (
      WidgetTester tester,
    ) async {
      final List<String> tapped = <String>[];
      await _pump(
        tester,
        onBookingTap: (Booking b) => tapped.add(b.id),
        bookings: <int, List<Booking>>{
          1: <Booking>[_booking('tap-me', _kyiv(1, 13), minutes: 60)],
        },
      );
      await tester.tap(find.byKey(WeekTimeGrid.cardKey('tap-me')));
      await tester.pump();
      expect(tapped, <String>['tap-me']);
    });

    testWidgets('tapping a column header reports its day index', (
      WidgetTester tester,
    ) async {
      final List<int> tapped = <int>[];
      await _pump(tester, onTapHeader: tapped.add);
      await tester.tap(find.byKey(WeekTimeGrid.headerKey(2)));
      await tester.pump();
      expect(tapped, <int>[2]);
    });
  });

  group('now-line position (mobile-qa)', () {
    testWidgets('sits at 13:40 on the 72 dp band', (WidgetTester tester) async {
      await _pump(tester, todayIndex: 1);
      final Rect col = tester.getRect(find.byKey(WeekTimeGrid.columnKey(1)));
      final Rect line = tester.getRect(find.byKey(WeekTimeGrid.nowLineKey));
      const double y =
          WeekTimeGrid.topPad + ((13 * 60 + 40) - _kFirstHour * 60) / 60 * 72;
      // The 2 dp line is centred on y: Positioned top = y − 1.
      expect(line.top - col.top, closeTo(y - 1, 0.01));
    });

    testWidgets('hidden when now is outside the hour window, even today', (
      WidgetTester tester,
    ) async {
      await _pump(tester, todayIndex: 1, now: _kyiv(1, 22, 10));
      expect(find.byKey(WeekTimeGrid.nowLineKey), findsNothing);
      expect(find.byKey(WeekTimeGrid.nowPillKey), findsNothing);
    });
  });

  group('entrance (mobile-qa)', () {
    testWidgets('animations on: entrance drives the column opacity 0 → 1', (
      WidgetTester tester,
    ) async {
      final AnimationController entrance = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 600),
      );
      addTearDown(entrance.dispose);
      await _pumpHarness(tester, entrance: entrance);

      double opacityOf() => tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: find.byKey(WeekTimeGrid.columnKey(0)),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;
      expect(opacityOf(), 0, reason: 'positive control for reduced motion');

      entrance.value = 1;
      await tester.pump();
      expect(opacityOf(), 1);
    });

    // Pins the perf fix: one `CurvedAnimation` per column, disposed on
    // unmount — rebuilds must not add listeners to the entrance controller.
    testWidgets('rebuilds do not grow entrance listeners; unmount frees all', (
      WidgetTester tester,
    ) async {
      final AnimationController parent = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 600),
        value: 1,
      );
      addTearDown(parent.dispose);
      final _CountingAnimation entrance = _CountingAnimation(parent);
      final ValueNotifier<int> tick = ValueNotifier<int>(0);
      addTearDown(tick.dispose);
      await _pumpHarness(tester, entrance: entrance, tick: tick);
      final int baseListeners = entrance.listeners;
      final int baseStatus = entrance.statusListeners;

      for (int i = 1; i <= 10; i++) {
        tick.value = i;
        await tester.pump();
      }

      expect(entrance.statusListeners, lessThanOrEqualTo(baseStatus));
      expect(entrance.listeners, lessThanOrEqualTo(baseListeners));
      await tester.pumpWidget(const SizedBox());
      expect(entrance.statusListeners, 0);
      expect(entrance.listeners, 0);
    });
  });

  group('mode switch (mobile-qa)', () {
    testWidgets('D1: switching 3 дні → День keeps the left-most visible day', (
      WidgetTester tester,
    ) async {
      final ValueNotifier<int> mode = ValueNotifier<int>(3);
      addTearDown(mode.dispose);
      final PageController three = WeekTimeGrid.controllerFor(
        visibleColumns: 3,
      );
      addTearDown(three.dispose);
      await _pumpHarness(tester, mode: mode, three: three);
      three.jumpToPage(2);
      await tester.pump();
      final PageController one = WeekTimeGrid.controllerFor(
        visibleColumns: 1,
        firstVisibleDay: 2,
      );
      addTearDown(one.dispose);

      await _pumpHarness(tester, mode: mode, three: three, one: one);
      mode.value = 1;
      await tester.pumpAndSettle();

      expect(one.page, 2, reason: 'Wednesday stays the shown day');
      final Rect pager = tester.getRect(_pager);
      expect(
        tester.getRect(find.byKey(WeekTimeGrid.columnKey(2))).left,
        closeTo(pager.left, 0.5),
      );
    });
  });

  group('header pager containment (mobile-qa)', () {
    // Pins the perf fix: the header PageView's per-frame `jumpTo` sync
    // notifications are contained inside the grid.
    testWidgets('header sync notifications do not bubble above the grid', (
      WidgetTester tester,
    ) async {
      final List<ScrollNotification> fromHeader = <ScrollNotification>[];
      final List<ScrollNotification> fromPager = <ScrollNotification>[];
      final PageController c = await _pumpHarness(
        tester,
        onNotification: (ScrollNotification n) {
          if (_under(n.context, WeekTimeGrid.headerRowKey)) {
            fromHeader.add(n);
          } else if (_under(n.context, WeekTimeGrid.pagerKey)) {
            fromPager.add(n);
          }
        },
      );
      await _drag(tester, _pager, step: const Offset(-40, 0));
      await _settle(tester);

      expect(c.position.pixels, greaterThan(0));
      expect(fromPager, isNotEmpty, reason: 'listener is wired');
      expect(fromHeader, isEmpty);
    });

    // Pins the fix: `didUpdateWidget` cancels a header drag in flight rather
    // than leave it driving the OLD position.
    testWidgets('a mode switch mid header-drag cancels the drag cleanly', (
      WidgetTester tester,
    ) async {
      final ValueNotifier<int> mode = ValueNotifier<int>(3);
      addTearDown(mode.dispose);
      final PageController three = WeekTimeGrid.controllerFor(
        visibleColumns: 3,
      );
      final PageController one = WeekTimeGrid.controllerFor(visibleColumns: 1);
      addTearDown(three.dispose);
      addTearDown(one.dispose);
      await _pumpHarness(tester, mode: mode, three: three, one: one);

      final TestGesture g = await tester.startGesture(
        tester.getCenter(find.byKey(WeekTimeGrid.headerRowKey)),
      );
      for (int i = 0; i < 3; i++) {
        await g.moveBy(const Offset(-30, 0));
        await tester.pump();
      }
      expect(three.position.pixels, greaterThan(0), reason: 'drag is live');

      mode.value = 1;
      await tester.pump();
      final double before = one.position.pixels;
      for (int i = 0; i < 3; i++) {
        await g.moveBy(const Offset(-30, 0));
        await tester.pump();
      }

      expect(one.position.pixels, before, reason: 'cancelled, not re-routed');
      await g.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

/// Whether [context] sits under the widget keyed [key].
bool _under(BuildContext? context, Key key) {
  bool found = false;
  context?.visitAncestorElements((Element e) {
    if (e.widget.key == key) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// A rebuildable harness: [tick] rebuilds the grid with a new `now`, [mode]
/// swaps between [three] / [one] controllers, [onNotification] observes
/// every scroll notification bubbling out of the grid.
Future<PageController> _pumpHarness(
  WidgetTester tester, {
  Animation<double>? entrance,
  ValueNotifier<int>? tick,
  ValueNotifier<int>? mode,
  PageController? three,
  PageController? one,
  void Function(ScrollNotification)? onNotification,
}) async {
  final PageController c3 =
      three ?? WeekTimeGrid.controllerFor(visibleColumns: 3);
  if (three == null) addTearDown(c3.dispose);
  final ValueNotifier<int> t = tick ?? ValueNotifier<int>(0);
  final ValueNotifier<int> m = mode ?? ValueNotifier<int>(3);
  if (tick == null) addTearDown(t.dispose);
  if (mode == null) addTearDown(m.dispose);
  final List<WeekDayModel> days = _days();
  await tester.pumpApp(
    Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification n) {
          onNotification?.call(n);
          return false;
        },
        child: ValueListenableBuilder<int>(
          valueListenable: m,
          builder: (BuildContext context, int visible, Widget? _) =>
              ValueListenableBuilder<int>(
                valueListenable: t,
                builder: (BuildContext context, int i, Widget? _) =>
                    WeekTimeGrid(
                      weekStart: _monday,
                      days: days,
                      today: kyivAddDays(_monday, 2),
                      now: _kyiv(2, 13, 40 + i % 10),
                      pageController: visible == 3 ? c3 : (one ?? c3),
                      visibleColumns: visible,
                      onBookingTap: (_) {},
                      onTapHeader: (_) {},
                      showsAllOccupancy: true,
                      entrance: entrance,
                    ),
              ),
        ),
      ),
    ),
    width: 360,
    height: 800,
  );
  await tester.pump();
  return c3;
}

/// Delegates to [parent] and counts live (status) listeners.
class _CountingAnimation extends Animation<double>
    with AnimationWithParentMixin<double> {
  _CountingAnimation(this.parent);

  @override
  final Animation<double> parent;

  int listeners = 0;
  int statusListeners = 0;

  @override
  double get value => parent.value;

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }

  @override
  void addStatusListener(AnimationStatusListener listener) {
    statusListeners++;
    super.addStatusListener(listener);
  }

  @override
  void removeStatusListener(AnimationStatusListener listener) {
    statusListeners--;
    super.removeStatusListener(listener);
  }
}
