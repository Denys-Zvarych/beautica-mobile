// Phase 483 — WeekTimeGrid on an EXPLICIT_TIMES day: free declared times are
// `FreeTimeCard(column: true)` markers in «3 дні», booked times are cards,
// SCH-18 consumed declared times are hidden (the shipped
// `consumesDeclaredTimes` via `freeDeclaredTimes`), a booking starting
// exactly on a time takes it whatever its status. «День» = the shipped
// `DeclaredTimeCards` list.
import 'dart:io';

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart'
    show stableBookingList;
import 'package:beautica_mobile/features/booking/domain/bookings_week_state.dart';
import 'package:beautica_mobile/features/booking/domain/week_day_model.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/declared_time_cards.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// Mon 9 – Sun 15 November 2026 (Kyiv UTC+2). Monday declares six times;
// every other day works 09:00–18:00.
final DateTime _monday = DateTime(2026, 11, 9);

const List<int> _kDeclaredHours = <int>[10, 11, 12, 13, 14, 15];

DateTime _kyiv(int dayIndex, int h, [int m = 0]) =>
    // Fixed instants fed to a pure layout; the injected `now` is fixed too.
    // future-date-ok: nothing here compares against the host clock.
    DateTime.utc(2026, 11, 9 + dayIndex, h - 2, m);

Booking _booking(
  String id,
  int h,
  int m, {
  int minutes = 30,
  BookingStatus status = BookingStatus.confirmed,
}) {
  final DateTime start = _kyiv(0, h, m);
  return Booking(
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
    startAt: start,
    endAt: start.add(Duration(minutes: minutes)),
    status: status,
    canReview: false,
  );
}

List<WeekDayModel> _days(List<Booking> monday) {
  final BookingsWeekState week = BookingsWeekState(
    weekStart: _monday,
    byDay: <DateTime, List<Booking>>{
      for (int i = 0; i < 7; i++)
        kyivAddDays(_monday, i): stableBookingList(
          i == 0 ? monday : const <Booking>[],
        ),
    },
  );
  return buildWeekDays(
    week,
    schedule: <DateTime, EffectiveDay>{
      for (int i = 0; i < 7; i++)
        kyivAddDays(_monday, i): i == 0
            ? EffectiveDay(
                date: _monday,
                source: EffectiveSource.template,
                intervals: const <WorkInterval>[],
                times: <TimeOfDay>[
                  for (final int h in _kDeclaredHours)
                    TimeOfDay(hour: h, minute: 0),
                ],
              )
            : EffectiveDay(
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

Future<void> _pump(
  WidgetTester tester,
  List<Booking> monday, {
  int visibleColumns = 3,
  double scale = 1.0,
  bool showsAllOccupancy = true,
}) async {
  final PageController controller = WeekTimeGrid.controllerFor(
    visibleColumns: visibleColumns,
  );
  addTearDown(controller.dispose);
  await tester.pumpApp(
    Scaffold(
      body: WeekTimeGrid(
        weekStart: _monday,
        days: _days(monday),
        // Today outside the week: the grid opens at the window's first hour.
        today: kyivAddDays(_monday, 14),
        now: _kyiv(14, 9),
        pageController: controller,
        visibleColumns: visibleColumns,
        onBookingTap: (_) {},
        onTapHeader: (_) {},
        showsAllOccupancy: showsAllOccupancy,
      ),
    ),
    width: 360,
    height: 800,
    textScaleFactor: scale,
  );
  await tester.pumpAndSettle();
}

/// Free-marker hours rendered in Monday's column.
List<int> _freeHours() => <int>[
  for (final int h in _kDeclaredHours)
    if (find.byKey(WeekTimeGrid.freeMarkerKey(0, h * 60)).evaluate().isNotEmpty)
      h,
];

final List<Booking> _busy = <Booking>[
  _booking('c-10', 10, 0),
  _booking('c-12', 12, 0),
  _booking('x-14', 14, 0, status: BookingStatus.cancelled),
];

void main() {
  group('3 дні', () {
    testWidgets('2 CONFIRMED + 1 CANCELLED on a time → 3 free markers; the '
        'cancelled booking takes its time', (WidgetTester tester) async {
      await _pump(tester, _busy);
      expect(_freeHours(), <int>[11, 13, 15]);
      expect(find.byType(FreeTimeCard), findsNWidgets(3));
      for (final String id in <String>['c-10', 'c-12', 'x-14']) {
        expect(find.byKey(WeekTimeGrid.cardKey(id)), findsOneWidget);
      }
    });

    testWidgets('SCH-18: a time inside a COMPLETED booking is hidden; one '
        'inside a CANCELLED booking stays free', (WidgetTester tester) async {
      await _pump(tester, <Booking>[
        // 10:30–11:30 swallows 11:00 (half-open, start before it).
        _booking('done', 10, 30, minutes: 60, status: BookingStatus.completed),
        // 12:30–13:30 spans 13:00 but frees the clock.
        _booking('gone', 12, 30, minutes: 60, status: BookingStatus.cancelled),
      ]);
      expect(_freeHours(), <int>[10, 12, 13, 14, 15]);
    });

    testWidgets('a booking ENDING on a time leaves it free (half-open)', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <Booking>[
        _booking('to-11', 10, 0, minutes: 60, status: BookingStatus.completed),
      ]);
      expect(_freeHours(), <int>[11, 12, 13, 14, 15]);
    });

    testWidgets('a filtered query (showsAllOccupancy false) claims no free '
        'time', (WidgetTester tester) async {
      await _pump(tester, _busy, showsAllOccupancy: false);
      expect(find.byType(FreeTimeCard), findsNothing);
      expect(find.byKey(WeekTimeGrid.cardKey('c-10')), findsOneWidget);
    });

    testWidgets('a free marker sits at its start, 30 minutes tall', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _busy);
      final Rect col = tester.getRect(find.byKey(WeekTimeGrid.columnKey(0)));
      final Rect marker = tester.getRect(
        find.byKey(WeekTimeGrid.freeMarkerKey(0, 11 * 60)),
      );
      // Window opens at 09:00 — exactly the earliest start (phase 492).
      const double hourH = WeekTimeGrid.threeDayHourHeight;
      final double expectedTop =
          col.top +
          WeekTimeGrid.topPad +
          (11 - 9) * hourH +
          WeekTimeGrid.cardGap / 2;
      expect(marker.top, moreOrLessEquals(expectedTop, epsilon: 0.5));
      expect(
        marker.height,
        moreOrLessEquals(hourH / 2 - WeekTimeGrid.cardGap, epsilon: 0.5),
      );
    });

    testWidgets('textScaler 1.3: markers, cards and labels do not overflow', (
      WidgetTester tester,
    ) async {
      // The suite-wide overflow guard fails the test on any RenderFlex
      // overflow; reaching the expectations means none happened.
      await _pump(tester, _busy, scale: 1.3);
      expect(_freeHours(), <int>[11, 13, 15]);
      expect(tester.takeException(), isNull);
    });
  });

  group('День', () {
    testWidgets('an EXPLICIT_TIMES day renders the shipped DeclaredTimeCards '
        'list, not hour-mapped cards', (WidgetTester tester) async {
      await _pump(tester, _busy, visibleColumns: 1);
      final Finder list = find.byKey(WeekTimeGrid.declaredListKey(0));
      expect(list, findsOneWidget);
      expect(tester.widget(list), isA<DeclaredTimeCards>());
      // Same merge: 3 free cards (list density) + 3 booked cards.
      expect(
        find.descendant(of: list, matching: find.byType(FreeTimeCard)),
        findsNWidgets(3),
      );
      expect(find.byKey(WeekTimeGrid.cardKey('c-10')), findsNothing);
      expect(find.byKey(WeekTimeGrid.freeMarkerKey(0, 11 * 60)), findsNothing);
    });

    testWidgets('textScaler 1.3: the list does not overflow', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _busy, visibleColumns: 1, scale: 1.3);
      expect(find.byKey(WeekTimeGrid.declaredListKey(0)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // mobile-qa — the «День» list honours the filter flag too.
    testWidgets('a filtered query (showsAllOccupancy false) shows no free '
        'card in the declared list', (WidgetTester tester) async {
      await _pump(tester, _busy, visibleColumns: 1, showsAllOccupancy: false);
      final Finder list = find.byKey(WeekTimeGrid.declaredListKey(0));
      expect(list, findsOneWidget);
      expect(
        find.descendant(of: list, matching: find.byType(FreeTimeCard)),
        findsNothing,
      );
    });
  });

  group('header hours inside the grid (mobile-qa)', () {
    // mobile-qa — each column header carries its own day's hours line.
    testWidgets('EXPLICIT_TIMES Monday reads «Свій час · 6», Tuesday '
        '«9:00–18:00»', (WidgetTester tester) async {
      await _pump(tester, _busy);
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byKey(WeekTimeGrid.hoursKey(0))),
      );
      expect(
        tester.widget<Text>(find.byKey(WeekTimeGrid.hoursKey(0))).data,
        l10n.masterWeekCustomTimes(6),
      );
      expect(
        tester.widget<Text>(find.byKey(WeekTimeGrid.hoursKey(1))).data,
        l10n.masterWeekHours('9:00', '18:00'),
      );
    });
  });

  group('truncated week', () {
    // mobile-qa — the grid contract documents that the caller passes
    // `showsAllOccupancy && !isTruncated` (a truncated week cannot back a
    // «Вільно» claim). The widget behaviour itself is pinned by the
    // showsAllOccupancy:false tests above.
    test('showsAllOccupancy doc states the isTruncated contract', () {
      final String src = File(
        'lib/features/booking/presentation/widgets/week_time_grid.dart',
      ).readAsStringSync();
      final int at = src.indexOf('final bool showsAllOccupancy;');
      expect(at, greaterThan(0));
      final String doc = src.substring(
        src.lastIndexOf('/// Whether the week', at),
        at,
      );
      expect(doc, contains('isTruncated'));
    });
  });
}
