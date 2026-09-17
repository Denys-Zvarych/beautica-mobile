// Working-hours windows for the day timeline (`BookingsTimelineGrid`), and the
// pure predicate that decides which bookings fall inside one.
//
// TWO windows live here, and everything in THIS header describes only the
// first:
//   * [scheduleWindowFor] — the MASTER board's, one person's hours, with
//     phase 244's "a booking outside the window is dropped" rule;
//   * [salonBoardWindow] — the SALON board's, the UNION of every roster
//     master's hours, deliberately wide enough that the same predicate drops
//     NOTHING. See its own section at the bottom of this file, which carries
//     the vacuity proof. Do not read the rules below as app-wide.
//
// Kept OUT of `bookings_timeline_grid.dart` (which owns the Kyiv-minute
// conversion machinery over `Booking.startAt`) because this is pure
// [EffectiveDay] translation with no Flutter/timezone dependency of its own —
// unit-testable without pumping a widget tree. (The salon window does need a
// booking span in Kyiv minutes, which is why it takes one as two plain `int`s
// the caller derives with that file's `bookingsMinuteSpan`, rather than
// importing the conversion here.)
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

import 'dart:math' as math;

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

// ═══════════════════════════════════════════════════════════════════════════
// PHASE 335 — THE SALON BOARD'S UNION WINDOW
// ═══════════════════════════════════════════════════════════════════════════
// Everything above this line is the MASTER board's window: one person's hours,
// and the "a booking starting outside the window is dropped entirely" rule
// that goes with it. That rule is correct for a master looking at their own
// day and WRONG for a manager looking at a whole salon — a 22:00 walk-in must
// not vanish from the owner's board because the master it belongs to finishes
// at 20:00. On a manager's board, dropping a booking is DATA LOSS.
//
// The fix is not a second filtering rule, a flag, or a branch. It is a WIDER
// WINDOW, chosen so that the existing filter ([bookingsInsideScheduleWindow])
// is provably VACUOUS on this path:
//
//   firstMinute     = min( union of every master's window start , earliest
//                          booking START )
//   windowEndMinute = max( union of every master's window end   , latest
//                          booking END )
//   isExplicitTimes = false
//
// THE PROOF. Take any booking b in the list the span was computed from, with
// Kyiv start s and end e. [ScheduleTimelineWindow.includesStart] with
// `isExplicitTimes == false` admits s iff `firstMinute <= s < windowEndMinute`.
//   * Lower bound: firstMinute <= bookingFirstMinute <= s. ✔
//   * Upper bound: windowEndMinute >= bookingLastEndMinute >= e, and
//     e = s + max(duration, 1) > s (see [bookingsMinuteSpan], which floors the
//     duration at one minute for exactly this step), so
//     windowEndMinute > s. ✔
// Both hold for EVERY b, so the filter excludes nothing and returns its input
// list unchanged — the SAME instance, which is what
// `bookings_discovery_view.dart`'s vacuity assert checks with `identical()`.
// That is why the bottom is folded from the booking END and not its start: an
// end-EXCLUSIVE upper bound tested against a start needs strict room above the
// last start, and only the end provides it.
//
// WHY THE BOTTOM IS NOT SIMPLY "the latest booking end". Because the grid must
// still show a master's full working day even when nobody has booked its tail
// — a 20:00 closing time with a last booking at 15:00 still draws ruler to
// 20:00. The union takes whichever is later; neither term alone is right.

/// The union of every roster master's working-hours window for one day, WIDENED
/// to cover every booking on that day — the salon «Записи» board's timeline
/// bounds. See this section's header for the vacuity proof that makes this safe.
///
/// [rosterDays] is the [EffectiveDay] each active master resolved for the day
/// being rendered. A master who is off (`OVERRIDE_DAY_OFF`), unscheduled
/// (`NO_SCHEDULE`), or whose intervals/times resolved empty contributes
/// NOTHING — [scheduleWindowFor] returns `null` for them and they are skipped.
/// That is how "off today" stays distinguishable from "not loaded": the caller
/// only ever reaches this function with a resolved, roster-complete set.
///
/// [bookingFirstMinute] / [bookingLastEndMinute] are the day's booking span in
/// minutes since the same Kyiv midnight — `null` together when the day has no
/// bookings at all. Produced by `bookingsMinuteSpan` in
/// `bookings_timeline_grid.dart`, which owns the Kyiv-minute conversion.
///
/// Returns `null` when NO master contributed a window (every one off/unloaded).
/// `null` means "no schedule bound to apply", and the caller then renders
/// exactly as it did before this feature existed — the booking-derived window
/// [BookingsTimelineGrid] computes for itself. It deliberately does NOT
/// degenerate into "a window equal to the booking span": handing that back
/// would be the same pixels by a longer route, and it would flip the
/// `window == null` tests elsewhere in `bookings_discovery_view.dart` that
/// several pre-existing behaviours key off.
///
/// [isExplicitTimes] on the result is ALWAYS `false`, even when some master's
/// own day is EXPLICIT_TIMES. A union of many masters has no single declared
/// start list, so the inclusive EXPLICIT_TIMES boundary rule has nothing to
/// mean here; the end-EXCLUSIVE INTERVAL rule is the one the proof above is
/// written against. An explicit-times master's latest declared start still
/// enters the union as a window END — and any booking placed AT that start is
/// still admitted, because its own end pushes [windowEndMinute] strictly past
/// it.
ScheduleTimelineWindow? salonBoardWindow({
  required Iterable<EffectiveDay> rosterDays,
  required int? bookingFirstMinute,
  required int? bookingLastEndMinute,
}) {
  int? first;
  int? end;
  for (final EffectiveDay day in rosterDays) {
    final ScheduleTimelineWindow? window = scheduleWindowFor(day);
    if (window == null) continue;
    first = first == null
        ? window.firstMinute
        : math.min(first, window.firstMinute);
    end = end == null
        ? window.windowEndMinute
        : math.max(end, window.windowEndMinute);
  }
  // Flow-typing pair (repo style forbids `!`): `end` is non-null exactly when
  // `first` is, since both are written together on every loop iteration that
  // writes either.
  if (first == null || end == null) return null;

  return ScheduleTimelineWindow(
    firstMinute: bookingFirstMinute == null
        ? first
        : math.min(first, bookingFirstMinute),
    windowEndMinute: bookingLastEndMinute == null
        ? end
        : math.max(end, bookingLastEndMinute),
    isExplicitTimes: false,
  );
}
