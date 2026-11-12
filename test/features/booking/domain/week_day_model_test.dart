// Phase 482 — WeekDayModel: Kyiv-day columns built from phase 480's
// BookingsWeekState, and the week's shared hour window.
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart'
    show stableBookingList;
import 'package:beautica_mobile/features/booking/domain/bookings_week_state.dart';
import 'package:beautica_mobile/features/booking/domain/week_day_model.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

Booking _booking(String id, DateTime startAt, {int minutes = 60}) => Booking(
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

/// A UTC instant. Fixed on purpose: the model is pure over its inputs and
/// never reads the clock.
DateTime _utc(int y, int mo, int d, int h, [int mi = 0]) =>
    // future-date-ok: pure-function fixture; nothing compares it to the clock.
    DateTime.utc(y, mo, d, h, mi);

BookingsWeekState _week(DateTime monday, Map<int, List<Booking>> byIndex) =>
    BookingsWeekState(
      weekStart: monday,
      byDay: <DateTime, List<Booking>>{
        for (int i = 0; i < 7; i++)
          kyivAddDays(monday, i): stableBookingList(
            byIndex[i] ?? const <Booking>[],
          ),
      },
    );

EffectiveDay _hours(DateTime day, int fromH, int toH) => EffectiveDay(
  date: day,
  source: EffectiveSource.template,
  intervals: <WorkInterval>[
    WorkInterval(
      start: TimeOfDay(hour: fromH, minute: 0),
      end: TimeOfDay(hour: toH, minute: 0),
    ),
  ],
);

void main() {
  // Mon 9 – Sun 15 November 2026 (Kyiv winter, UTC+2).
  final DateTime monday = DateTime(2026, 11, 9);

  group('buildWeekDays — Kyiv-day columns', () {
    test('seven columns, Monday first, one calendar day apart', () {
      final List<WeekDayModel> days = buildWeekDays(_week(monday, const {}));
      expect(days.map((WeekDayModel d) => d.day).toList(), <DateTime>[
        for (int i = 9; i <= 15; i++) DateTime(2026, 11, i),
      ]);
    });

    test(
      'minutes are Kyiv wall-clock, a 23:30 Kyiv start stays on its day',
      () {
        // 07:00 UTC = 09:00 Kyiv; 21:30 UTC = 23:30 Kyiv (UTC next-day-safe).
        final Booking morning = _booking('m', _utc(2026, 11, 10, 7));
        final Booking late = _booking('l', _utc(2026, 11, 10, 21, 30));
        final BookingsWeekState week = _week(monday, <int, List<Booking>>{
          1: <Booking>[morning, late],
        });
        final WeekDayModel tue = buildWeekDays(week)[1];
        expect(tue.day, DateTime(2026, 11, 10));
        expect(tue.startMinutes, <int>[9 * 60, 23 * 60 + 30]);
        expect(
          tue.endMinuteOf(1),
          24 * 60 + 30,
          reason: 'past midnight runs on, never wraps',
        );
        expect(
          identical(tue.bookings, week.bookingsOn(DateTime(2026, 11, 10))),
          isTrue,
          reason: 'the state\'s own list instance (memo gates)',
        );
      },
    );

    test('DST week: calendar-stepped days, minutes off the Kyiv midnight', () {
      // Mon 23 – Sun 29 March 2026; Kyiv springs forward Sun 29 at 03:00.
      final DateTime dstMonday = DateTime(2026, 3, 23);
      // Sat 28 10:00 Kyiv (UTC+2) = 08:00 UTC.
      final Booking sat = _booking('s', _utc(2026, 3, 28, 8));
      // Sun 29 02:00 Kyiv, still UTC+2, before the jump = 00:00 UTC.
      final Booking sunEarly = _booking('e', _utc(2026, 3, 29, 0));
      final List<WeekDayModel> days = buildWeekDays(
        _week(dstMonday, <int, List<Booking>>{
          5: <Booking>[sat],
          6: <Booking>[sunEarly],
        }),
      );
      expect(
        days.map((WeekDayModel d) => d.day).toList(),
        <DateTime>[for (int i = 23; i <= 29; i++) DateTime(2026, 3, i)],
        reason: 'no Duration(hours: 24) drift across the 23 h day',
      );
      expect(days[5].startMinutes, <int>[10 * 60]);
      expect(days[6].startMinutes, <int>[2 * 60]);
    });

    test('schedule is attached by Kyiv day token; missing = null', () {
      final DateTime tue = DateTime(2026, 11, 10);
      final List<WeekDayModel> days = buildWeekDays(
        _week(monday, const {}),
        schedule: <DateTime, EffectiveDay>{tue: _hours(tue, 9, 18)},
      );
      expect(days[1].schedule?.intervals.single.startMinutes, 9 * 60);
      expect(days[0].schedule, isNull);
    });
  });

  group('weekGridWindow — union of hours and bookings, ±1 h', () {
    test('empty week → the 8–20 default', () {
      expect(
        weekGridWindow(buildWeekDays(_week(monday, const {}))),
        kEmptyWeekGridWindow,
      );
    });

    test('earliest start − 1 h … latest end + 1 h across all days', () {
      final DateTime mon = monday;
      final DateTime tue = DateTime(2026, 11, 10);
      // Wed 20:00–21:15 Kyiv = 18:00 UTC, past every working end.
      final Booking evening = _booking(
        'w',
        _utc(2026, 11, 11, 18),
        minutes: 75,
      );
      final WeekGridWindow w = weekGridWindow(
        buildWeekDays(
          _week(monday, <int, List<Booking>>{
            2: <Booking>[evening],
          }),
          schedule: <DateTime, EffectiveDay>{
            mon: _hours(mon, 10, 19),
            tue: _hours(tue, 9, 18),
          },
        ),
      );
      // first: 09:00 → 8. last: 21:15 → ceil 22 → 23.
      expect(w, (firstHour: 8, lastHour: 23));
    });

    test('declared EXPLICIT_TIMES count as 30-minute slots', () {
      final DateTime fri = DateTime(2026, 11, 13);
      final WeekGridWindow w = weekGridWindow(
        buildWeekDays(
          _week(monday, const {}),
          schedule: <DateTime, EffectiveDay>{
            fri: EffectiveDay(
              date: fri,
              source: EffectiveSource.template,
              intervals: const <WorkInterval>[],
              times: const <TimeOfDay>[
                TimeOfDay(hour: 7, minute: 30),
                TimeOfDay(hour: 17, minute: 45),
              ],
            ),
          },
        ),
      );
      // 07:30 → floor 7 → 6; 18:15 → ceil 19 → 20.
      expect(w, (firstHour: 6, lastHour: 20));
    });

    test('a 00:xx start clamps the top at hour 0', () {
      final Booking midnight = _booking('z', _utc(2026, 11, 9, 22, 30));
      final WeekGridWindow w = weekGridWindow(
        buildWeekDays(
          _week(monday, <int, List<Booking>>{
            1: <Booking>[midnight],
          }),
        ),
      );
      expect(w.firstHour, 0);
    });
  });
}
