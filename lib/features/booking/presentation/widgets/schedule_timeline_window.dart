// Working-hours window for the master's «Мої записи» day timeline
// (`BookingsTimelineGrid`), and the pure predicate that decides which
// bookings fall inside it. Kept OUT of `bookings_timeline_grid.dart` (which
// owns the Kyiv-minute conversion machinery over `Booking.startAt`) because
// this is pure [EffectiveDay] translation with no Flutter/timezone
// dependency of its own — unit-testable without pumping a widget tree.
//
// Product decision (locked, this session — see `bookings_discovery_view
// .dart`'s "working-hours window" section for the full context): the
// master's own booking timeline is bounded by WORKING HOURS, not by
// whichever bookings happen to exist that day:
//   * grid top    = the day's earliest working start;
//   * grid bottom = the day's latest working end — EXCEPT a booking that
//     legitimately STARTS inside the window still renders in full even past
//     that bottom (`BookingsTimelineGrid` performs that one widening itself,
//     once it has been handed [ScheduleTimelineWindow.firstMinute] /
//     [ScheduleTimelineWindow.windowEndMinute]);
//   * a booking that does NOT start inside the window is dropped entirely —
//     never rendered, never widens the grid. mobile-security HIGH fix (this
//     session): the DROPPING itself is now `bookings_discovery_view.dart`'s
//     job, not `BookingsTimelineGrid`'s — `_Loaded` calls
//     `bookingsInsideScheduleWindow` (in `bookings_timeline_grid.dart`,
//     which still owns the Kyiv-minute conversion machinery this predicate
//     needs) exactly ONCE per day and uses its result for BOTH the header
//     count and the grid's `bookings`, so the two can never read different
//     numbers. `BookingsTimelineGrid` itself no longer calls
//     [ScheduleTimelineWindow.includesStart] — it trusts the list it is
//     handed.
// A day with no working hours at all — a settled day off, the unset
// NO_SCHEDULE state, or (defensively) a working [EffectiveSource] whose
// intervals/times still resolved empty — has no window
// ([scheduleWindowFor] returns `null`); the caller
// (`bookings_discovery_view.dart`) replaces the whole timeline with
// `MasterBookingsNoWorkingHoursState` rather than passing a window through.

import '../../../schedule/domain/weekly_schedule.dart';

/// The working-hours window for one resolved [EffectiveDay], expressed in
/// minutes since that day's Kyiv midnight — the same unit
/// `BookingsTimelineGrid` already measures every booking in.
class ScheduleTimelineWindow {
  const ScheduleTimelineWindow({
    required this.firstMinute,
    required this.windowEndMinute,
    required this.isExplicitTimes,
  });

  /// Grid top — the earliest working start.
  final int firstMinute;

  /// INTERVAL day: the latest interval END. A booking cannot legitimately
  /// START at this exact minute (there would be no time left to serve it),
  /// so [includesStart] excludes it — see [isExplicitTimes] `false`.
  ///
  /// EXPLICIT_TIMES day: the latest DECLARED START time itself — there is no
  /// "end" in this mode, and that time IS a legitimate booking start, so
  /// [includesStart] includes it ([isExplicitTimes] `true`).
  final int windowEndMinute;

  /// Selects which boundary rule [includesStart] applies at
  /// [windowEndMinute] — see that field's doc.
  final bool isExplicitTimes;

  /// Whether a booking starting at [startMinute] (minutes since the same
  /// Kyiv midnight [windowEndMinute] is measured against) counts as "inside"
  /// this window.
  bool includesStart(int startMinute) {
    if (startMinute < firstMinute) return false;
    return isExplicitTimes
        ? startMinute <= windowEndMinute
        : startMinute < windowEndMinute;
  }
}

/// Resolves [day]'s working-hours window, or `null` when the day has no
/// working hours at all — see this file's header for the three cases that
/// return `null`.
ScheduleTimelineWindow? scheduleWindowFor(EffectiveDay day) {
  if (day.source == EffectiveSource.overrideDayOff ||
      day.source == EffectiveSource.noSchedule) {
    return null;
  }
  if (day.isExplicitTimes) {
    if (day.times.isEmpty) return null;
    int first = day.times.first.hour * 60 + day.times.first.minute;
    int last = first;
    for (final time in day.times) {
      final int minute = time.hour * 60 + time.minute;
      if (minute < first) first = minute;
      if (minute > last) last = minute;
    }
    return ScheduleTimelineWindow(
      firstMinute: first,
      windowEndMinute: last,
      isExplicitTimes: true,
    );
  }
  if (day.intervals.isEmpty) return null;
  int first = day.intervals.first.startMinutes;
  int lastEnd = day.intervals.first.endMinutes;
  for (final interval in day.intervals) {
    if (interval.startMinutes < first) first = interval.startMinutes;
    if (interval.endMinutes > lastEnd) lastEnd = interval.endMinutes;
  }
  return ScheduleTimelineWindow(
    firstMinute: first,
    windowEndMinute: lastEnd,
    isExplicitTimes: false,
  );
}
