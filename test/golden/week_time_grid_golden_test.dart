// Phase 483 — WeekTimeGrid «3 дні» at 360 dp, ×1.0 / ×1.3:
//   busy        — preview «Насичений тиждень» (Ср with the 13–14 break +
//                 «Перерва», Чт today with the now-line, Пт EXPLICIT_TIMES
//                 with free markers and the SCH-18-hidden 11:00);
//   day_off     — preview «Вихідний посеред тижня» (Чт today = day off,
//                 ONE pinned «Вихідний»);
//   custom_times — the same week opened on Пн–Ср (Вт EXPLICIT_TIMES: booked,
//                 cancelled-on-a-time, free markers).
// Reviewed against `docs/signup-designs/MasterWeekBookings/` (AC1).
import 'package:beautica_mobile/core/theme/brand_colors.dart';
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

import 'helpers/golden_pump.dart';

const double _kWidth = 360;
const double _kHeight = 640;

final DateTime _monday = DateTime(2026, 11, 9);
const int _kToday = 3; // Чт

/// A Kyiv wall-clock instant (UTC+2 in November).
DateTime _kyiv(int day, int h, [int m = 0]) =>
    // future-date-ok: pinned fixture week; `now` is injected, never the host.
    DateTime.utc(2026, 11, 9 + day, h - 2, m);

int _seq = 0;

Booking _b(
  int day,
  int h,
  int m,
  int minutes,
  String client,
  String service, {
  BookingStatus? status,
}) {
  final DateTime start = _kyiv(day, h, m);
  _seq++;
  return Booking(
    id: 'b$_seq',
    masterId: 'master-1',
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'INDEPENDENT_MASTER',
    clientFirstName: client,
    clientLastName: 'Коваль',
    serviceId: 'service-$_seq',
    serviceName: service,
    durationMinutes: minutes,
    price: 600,
    startAt: start,
    endAt: start.add(Duration(minutes: minutes)),
    status:
        status ??
        (day < _kToday ? BookingStatus.completed : BookingStatus.confirmed),
    canReview: false,
  );
}

EffectiveDay _hours(int day, List<(int, int, int, int)> spans) => EffectiveDay(
  date: kyivAddDays(_monday, day),
  source: EffectiveSource.template,
  intervals: <WorkInterval>[
    for (final (int sh, int sm, int eh, int em) in spans)
      WorkInterval(
        start: TimeOfDay(hour: sh, minute: sm),
        end: TimeOfDay(hour: eh, minute: em),
      ),
  ],
);

EffectiveDay _off(int day) => EffectiveDay(
  date: kyivAddDays(_monday, day),
  source: EffectiveSource.template,
  intervals: const <WorkInterval>[],
);

EffectiveDay _explicit(int day, List<(int, int)> times) => EffectiveDay(
  date: kyivAddDays(_monday, day),
  source: EffectiveSource.template,
  intervals: const <WorkInterval>[],
  times: <TimeOfDay>[
    for (final (int h, int m) in times) TimeOfDay(hour: h, minute: m),
  ],
);

List<WeekDayModel> _week(List<EffectiveDay> schedule, List<Booking> all) =>
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
        for (final EffectiveDay d in schedule) d.date: d,
      },
    );

List<WeekDayModel> _busy() => _week(
  <EffectiveDay>[
    _hours(0, <(int, int, int, int)>[(10, 0, 19, 0)]),
    _hours(1, <(int, int, int, int)>[(9, 0, 18, 0)]),
    _hours(2, <(int, int, int, int)>[(9, 0, 13, 0), (14, 0, 20, 0)]),
    _hours(3, <(int, int, int, int)>[(9, 0, 19, 0)]),
    _explicit(4, <(int, int)>[
      (10, 0),
      (11, 0), // swallowed by 10:00–11:30 → hidden (SCH-18)
      (11, 30),
      (13, 0),
      (14, 30),
      (16, 0),
    ]),
    _hours(5, <(int, int, int, int)>[(10, 0, 15, 0)]),
    _off(6),
  ],
  <Booking>[
    _b(2, 9, 0, 30, 'Наталія', 'Корекція брів'),
    _b(2, 9, 30, 90, 'Тетяна', 'Манікюр з покриттям'),
    _b(2, 11, 0, 60, 'Валерія', 'Ламінування брів, дизайн'),
    _b(2, 12, 0, 60, 'Людмила', 'Манікюр'),
    _b(2, 14, 0, 90, 'Єва', 'Педикюр'),
    _b(2, 15, 30, 60, 'Поліна', 'Манікюр'),
    _b(2, 16, 30, 30, 'Ганна', 'Корекція брів'),
    _b(2, 17, 0, 60, 'Злата', 'Манікюр'),
    _b(
      3,
      9,
      0,
      90,
      'Олександра',
      'Манікюр з покриттям',
      status: BookingStatus.completed,
    ),
    _b(3, 10, 30, 30, 'Інна', 'Зняття покриття'),
    _b(3, 11, 0, 120, 'Діана', 'Чистка обличчя'),
    _b(3, 14, 0, 60, 'Вероніка', 'Манікюр'),
    _b(3, 15, 0, 30, 'Маргарита', 'Корекція брів'),
    _b(3, 15, 30, 90, 'Лілія', 'Педикюр', status: BookingStatus.declined),
    _b(3, 17, 0, 90, 'Світлана', 'Манікюр з покриттям'),
    _b(3, 18, 30, 30, 'Каріна', 'Корекція брів'),
    _b(4, 10, 0, 90, 'Еліна', 'Манікюр з покриттям'),
    _b(4, 13, 0, 90, 'Богдана', 'Педикюр'),
    _b(4, 16, 0, 30, 'Мілана', 'Корекція брів'),
  ],
);

List<WeekDayModel> _dayOffWeek() => _week(
  <EffectiveDay>[
    _hours(0, <(int, int, int, int)>[(10, 0, 19, 0)]),
    _explicit(1, <(int, int)>[
      (9, 0),
      (10, 0),
      (11, 30),
      (13, 0),
      (15, 0),
      (16, 30),
    ]),
    _hours(2, <(int, int, int, int)>[(9, 0, 13, 0), (14, 0, 20, 0)]),
    _off(3),
    _hours(4, <(int, int, int, int)>[(11, 0, 20, 0)]),
    _hours(5, <(int, int, int, int)>[(10, 0, 15, 0)]),
    _off(6),
  ],
  <Booking>[
    _b(1, 9, 0, 60, 'Олена', 'Манікюр'),
    _b(1, 11, 30, 90, 'Софія', 'Манікюр з покриттям'),
    _b(1, 15, 0, 30, 'Аліна', 'Корекція брів', status: BookingStatus.cancelled),
    _b(2, 9, 30, 90, 'Наталія', 'Манікюр з покриттям'),
    _b(2, 11, 0, 30, 'Тетяна', 'Корекція брів'),
    _b(2, 15, 0, 90, 'Єва', 'Педикюр'),
    _b(4, 11, 0, 150, 'Еліна', 'Нарощування вій'),
    _b(4, 14, 0, 60, 'Мілана', 'Манікюр'),
    _b(4, 16, 30, 30, 'Богдана', 'Корекція брів'),
  ],
);

Widget _scene(List<WeekDayModel> days, int firstVisibleDay) => SizedBox(
  width: _kWidth,
  height: _kHeight,
  child: ColoredBox(
    color: BrandColors.base,
    child: WeekTimeGrid(
      weekStart: _monday,
      days: days,
      today: kyivAddDays(_monday, _kToday),
      now: _kyiv(_kToday, 13, 40),
      pageController: WeekTimeGrid.controllerFor(
        visibleColumns: 3,
        firstVisibleDay: firstVisibleDay,
      ),
      visibleColumns: 3,
      onBookingTap: (_) {},
      onTapHeader: (_) {},
      showsAllOccupancy: true,
    ),
  ),
);

void main() {
  final Map<String, Widget Function()> scenes = <String, Widget Function()>{
    'busy': () => _scene(_busy(), 2),
    'day_off': () => _scene(_dayOffWeek(), 2),
    'custom_times': () => _scene(_dayOffWeek(), 0),
  };
  for (final double scale in kGoldenTextScales) {
    final String suffix = widthScaleSuffix(_kWidth, scale);
    for (final MapEntry<String, Widget Function()> scene in scenes.entries) {
      goldenTest(
        'week time grid ${scene.key} $suffix',
        fileName: 'week_time_grid_${scene.key}_$suffix',
        constraints: BoxConstraints.tight(const Size(_kWidth, _kHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(width: _kWidth),
        builder: scene.value,
      );
    }
  }
}
