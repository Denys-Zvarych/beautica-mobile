// Phase 482 — WeekDayModel: one Kyiv day of the master's week, as the week
// time grid (`presentation/widgets/week_time_grid.dart`) lays it out.
//
// Pure: built from phase 480's [BookingsWeekState] (already bucketed by Kyiv
// day) plus the optional resolved schedule. Every minute is measured against
// the day's own Kyiv midnight via the shared [minutesSinceDayStart] — never
// the device time zone, never `Duration(hours: 24)` stepping (a DST week has
// a 23 h and a 25 h day; [kyivAddDays] is calendar arithmetic).

import 'dart:math' as math;

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart'
    show WorkInterval;
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

import 'booking.dart';
import 'bookings_day_state.dart' show stableBookingList;
import 'bookings_week_state.dart';

part 'week_day_model.freezed.dart';

/// Days in the grid's week — Monday … Sunday.
const int kWeekGridDays = 7;

/// One Kyiv day column of the week grid.
@freezed
abstract class WeekDayModel with _$WeekDayModel {
  const factory WeekDayModel({
    /// The Kyiv date token of this column.
    required DateTime day,

    /// The resolved schedule for [day]; `null` when none was loaded (the
    /// grid then draws no working-hours information for the column).
    EffectiveDay? schedule,

    /// The day's bookings in server order (`startAt` ASC) — the SAME list
    /// instance phase 480's state holds, so identity memo gates hit.
    required List<Booking> bookings,

    /// `bookings[i]`'s start, in minutes since [day]'s Kyiv midnight
    /// (index-aligned with [bookings]).
    required List<int> startMinutes,
  }) = _WeekDayModel;

  const WeekDayModel._();

  /// `bookings[i]`'s end minute — start + its duration. May exceed 1440 for
  /// a booking running past midnight.
  int endMinuteOf(int i) => startMinutes[i] + bookings[i].durationMinutes;
}

/// The hour window every column of one week shares — [firstHour] /
/// [lastHour] are hours since the Kyiv midnight of each column's own day.
typedef WeekGridWindow = ({int firstHour, int lastHour});

/// Default window when the week holds neither hours nor bookings.
const WeekGridWindow kEmptyWeekGridWindow = (firstHour: 8, lastHour: 20);

/// The seven [WeekDayModel]s of [week], Monday first. [schedule] maps a Kyiv
/// date token to its resolved day; a missing key means "not loaded".
List<WeekDayModel> buildWeekDays(
  BookingsWeekState week, {
  Map<DateTime, EffectiveDay> schedule = const <DateTime, EffectiveDay>{},
}) {
  return List<WeekDayModel>.unmodifiable(<WeekDayModel>[
    for (int i = 0; i < kWeekGridDays; i++)
      _dayModel(kyivAddDays(week.weekStart, i), week, schedule),
  ]);
}

WeekDayModel _dayModel(
  DateTime day,
  BookingsWeekState week,
  Map<DateTime, EffectiveDay> schedule,
) {
  final tz.TZDateTime midnight = kyivMidnight(day);
  final List<Booking> bookings = week.bookingsOn(day);
  return WeekDayModel(
    day: day,
    schedule: schedule[day],
    bookings: stableBookingList(bookings),
    startMinutes: <int>[
      for (final Booking b in bookings)
        minutesSinceDayStart(b.startAt, midnight),
    ],
  );
}

/// The UNION of the week's working hours, declared times and bookings, the
/// start floored and the end ceiled to whole hours, with NO margin (phase
/// 492, SCH-39): the edges are the real working edges, since a booking
/// cannot sit outside working hours. A declared (EXPLICIT_TIMES) time counts
/// as 30 minutes. One axis for the whole loaded week (all seven days, not
/// only the columns on screen), so the ruler never jumps while swiping and
/// «День» / «3 дні» share it. A booking outside the hours still widens the
/// window to its own floor / ceil, so it is never cropped. Nothing covered
/// → [kEmptyWeekGridWindow].
///
/// Bounded to `[0, 48]` hours: the bottom may run into the next day for a
/// booking past midnight (the ruler labels such hours `00:00`, `01:00`, …),
/// exactly as the single-day grid's R1 fix allows.
WeekGridWindow weekGridWindow(List<WeekDayModel> days) {
  const int none = -1;
  int lo = none;
  int hi = none;
  void cover(int start, int end) {
    lo = lo == none ? start : math.min(lo, start);
    hi = hi == none ? end : math.max(hi, end);
  }

  for (final WeekDayModel d in days) {
    final EffectiveDay? s = d.schedule;
    if (s != null) {
      for (final WorkInterval w in s.intervals) {
        cover(w.startMinutes, w.endMinutes);
      }
      for (final TimeOfDay t in s.times) {
        final int m = t.hour * 60 + t.minute;
        cover(m, m + 30);
      }
    }
    for (int i = 0; i < d.bookings.length; i++) {
      cover(d.startMinutes[i], d.endMinuteOf(i));
    }
  }
  if (lo == none || hi == none) return kEmptyWeekGridWindow;
  final int firstHour = lo.clamp(0, 48 * 60) ~/ 60;
  final int lastHour = math.min(48, (hi / 60).ceil());
  return (firstHour: firstHour, lastHour: math.max(lastHour, firstHour + 1));
}
