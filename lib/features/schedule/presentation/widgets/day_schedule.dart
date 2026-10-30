// Phase 15.2 — Master Schedule day-grid render projection.
//
// Transcribed from the approved preview
// `docs/signup-designs/MasterSchedule/lib/widgets/day_schedule.dart`, adapted to
// project off the Phase 15.1 [EffectiveDay] (the calendar's real data source)
// instead of the preview's in-memory `DaySchedule` sample.
//
// The 30-min [SlotCell] grid is a PURE RENDER PROJECTION — it is computed from
// the resolved [EffectiveDay] (template- or override-derived) plus the day's
// BOOKINGS on every build and is NEVER stored (cf. Phase 15.1 contract +
// preview README). Each cell carries exactly ONE [SlotState] (solid
// single-colour chip — no proportional / split / banded fills). The state
// assigned to a 30-min cell window `[s, s+30)`:
//   • the cell overlaps a CONFIRMED / COMPLETED      → [SlotState.booked]
//     booking (even by a single minute)                 (wins over every
//                                                       other state)
//   • OVERRIDE_DAY_OFF (whole day off)                → [SlotState.unavailable]
//   • NO_SCHEDULE / no intervals                      → [SlotState.unavailable]
//   • otherwise (working day, intervals present):
//       – the cell overlaps any working interval      → [SlotState.available]
//       – else (leading off, or a BREAK between two   → [SlotState.unavailable]
//         consecutive intervals)
//
// Three-state legend (user decision 2026-10-30): «Вільно» / «Заброньовано» /
// «Неробочий час». Breaks and whole-day OVERRIDE_DAY_OFF are folded into
// «Неробочий час»; they no longer have a legend state of their own. The booked
// visual is the former «Час відпочинку» (`timeOff`) dusty-rose swatch,
// byte-for-byte.
//
// Bookings are optional input (`buildDayCells(day, bookings: ...)`): the screen
// renders the availability grid immediately and repaints once the day's
// bookings land. CANCELLED / DECLINED / NOT_COMPLETED bookings never paint.
// Before 2026-10-30 this surface was availability-only (Phase 15.2 design).

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

import 'slot_colors.dart';

/// One 30-minute cell of the day grid. Purely a *render* projection — computed
/// from the resolved [EffectiveDay], never stored on its own. Each cell carries
/// a single [state] and renders as ONE solid colour (no split fills).
class SlotCell {
  const SlotCell({required this.time, required this.state});

  final TimeOfDay time;
  final SlotState state;
}

/// The localised human label for a single [SlotState] (legend + per-cell label).
///
/// Deviation from the preview, which hard-coded the Ukrainian strings on the
/// enum: production routes them through [AppLocalizations] so they satisfy
/// `no_raw_ui_strings` and stay EN-ready. Wording per the 2026-10-30 user
/// decision: "Вільно" / "Заброньовано" / "Неробочий час".
String slotStateLabel(AppLocalizations l10n, SlotState state) =>
    switch (state) {
      SlotState.available => l10n.scheduleSlotWorking,
      SlotState.booked => l10n.scheduleSlotBooked,
      SlotState.unavailable => l10n.scheduleSlotOff,
    };

/// The localised semantic label for a [cell]: its time + state label (e.g.
/// "09:00 — Вільно"). Used for the chip's a11y label so the state is
/// conveyed without relying on colour.
String slotCellLabel(AppLocalizations l10n, SlotCell cell) {
  final String time =
      '${cell.time.hour.toString().padLeft(2, '0')}:${cell.time.minute.toString().padLeft(2, '0')}';
  return '$time — ${slotStateLabel(l10n, cell.state)}';
}

/// Builds the ordered list of 30-min [SlotCell]s for [day]. On a real working
/// day the grid is CLAMPED to the actual working span — it starts at the first
/// interval start (floored to the enclosing 30-min cell) and ends EXACTLY at the
/// last interval end, so no trailing "off" cards render past the working day.
/// The reference 09:00 → 19:00 window is used only for the empty / uniform case
/// (day-off / no schedule). All bounds clamped to `[0, 1440]` minutes (single
/// day; no cross-midnight handling).
///
/// [day] is the resolved [EffectiveDay] from Phase 15.1. State mapping (which
/// mirrors the four [EffectiveSource] cases the backend can produce):
///   • intervals present (TEMPLATE / OVERRIDE_CUSTOM) → green inside an
///     interval; the lead-in before the first interval and any BREAK between
///     intervals is GREY "Неробочий час"; the run-out after the last interval
///     is clamped away (no trailing cells).
///   • OVERRIDE_DAY_OFF / NO_SCHEDULE → all grey "Неробочий час".
///
/// [bookings] (default empty — every pre-2026-10-30 caller renders exactly the
/// availability grid it always did, minus the retired pause/day-off pink): any
/// cell overlapping a [BookingStatus.confirmed] or [BookingStatus.completed]
/// booking's Kyiv `[startAt, endAt)` span on [day]'s date is
/// [SlotState.booked], winning over every other state. Other statuses are
/// ignored.
List<SlotCell> buildDayCells(
  EffectiveDay day, {
  List<Booking> bookings = const <Booking>[],
}) {
  final (int gridStartMin, int gridEndMin) = _gridBounds(day.intervals);
  final List<(int, int)> bookedSpans = _bookedSpans(day.date, bookings);

  // Perf (HIGH-2): the projection is a pure function of the day's
  // (date, source, intervals) — recomputing + reallocating the list on every
  // build is wasteful, especially since the grid is now isolated and rebuilt
  // independently of day selection. Memoize a single most-recent result keyed
  // by the resolved day + grid bounds: a day-change recomputes once, a pure
  // strip-highlight repaint (no day change) reuses the cached list verbatim.
  final _DayCellsKey? cachedKey = _cachedKey;
  final List<SlotCell>? cachedCells = _cachedCells;
  if (cachedKey != null &&
      cachedCells != null &&
      cachedKey.matches(day, gridStartMin, gridEndMin, bookedSpans)) {
    return cachedCells;
  }
  final List<SlotCell> cells = _computeDayCells(
    day,
    gridStartMin,
    gridEndMin,
    bookedSpans,
  );
  _cachedKey = _DayCellsKey(day, gridStartMin, gridEndMin, bookedSpans);
  _cachedCells = cells;
  return cells;
}

/// The Kyiv-minute `[start, end)` spans (minutes since [date]'s Kyiv midnight,
/// clamped to `[0, 1440]`) of every CONFIRMED / COMPLETED booking in
/// [bookings] that touches [date]. Empty input short-circuits before any
/// timezone read, so a bookings-less caller never depends on tz init.
List<(int, int)> _bookedSpans(DateTime date, List<Booking> bookings) {
  if (bookings.isEmpty) return const <(int, int)>[];
  final tz.TZDateTime midnight = tz.TZDateTime(
    beauticaZone,
    date.year,
    date.month,
    date.day,
  );
  final List<(int, int)> spans = <(int, int)>[];
  for (final Booking b in bookings) {
    if (b.status != BookingStatus.confirmed &&
        b.status != BookingStatus.completed) {
      continue;
    }
    final int start = toBeauticaTime(
      b.startAt,
    ).difference(midnight).inMinutes.clamp(0, 1440);
    final int end = toBeauticaTime(
      b.endAt,
    ).difference(midnight).inMinutes.clamp(0, 1440);
    if (end > start) spans.add((start, end));
  }
  return spans;
}

/// The grid's `[gridStartMin, gridEndMin)` cell-start window, in minutes from
/// midnight. On a real working day (intervals present) the grid is CLAMPED to
/// the actual span: it starts at the first interval start (floored to the
/// enclosing 30-min cell boundary so cells stay aligned) and ENDS EXACTLY at
/// the last interval end — every cell whose start is at or after that end is
/// dropped, so no trailing "off" cards render past the working day. The
/// reference 09:00–19:00 window is used ONLY for the empty / uniform case
/// (day-off / no schedule / no intervals). All values clamped to `[0, 1440]`
/// (single-day; no cross-midnight handling).
(int, int) _gridBounds(List<WorkInterval> intervals) {
  // Reference window for the empty / uniform-day case: 09:00–19:00.
  const int referenceStartMin = 9 * 60;
  const int referenceEndMin = 19 * 60;
  if (intervals.isEmpty) {
    return (referenceStartMin, referenceEndMin);
  }

  int firstStart = intervals.first.startMinutes;
  int lastEnd = intervals.first.endMinutes;
  for (final WorkInterval w in intervals) {
    if (w.startMinutes < firstStart) firstStart = w.startMinutes;
    if (w.endMinutes > lastEnd) lastEnd = w.endMinutes;
  }
  // Floor the start to its enclosing 30-min cell so cells stay grid-aligned
  // (a 09:15 start still opens the grid at 09:00); the end stays exact so the
  // `cellStartMin < gridEndMin` loop drops any cell starting at/after lastEnd.
  const int cellLen = 30;
  final int startMin = ((firstStart ~/ cellLen) * cellLen).clamp(0, 1440);
  final int endMin = lastEnd.clamp(0, 1440);
  return (startMin, endMin);
}

// Single-entry memo for [buildDayCells] (the calendar shows one day at a time).
_DayCellsKey? _cachedKey;
List<SlotCell>? _cachedCells;

/// Identity of a [buildDayCells] computation: the resolved day's date + source
/// + interval shape, the grid bounds (minute-based, matching [_gridBounds]),
/// and the booked-span signature (value-based, so a refetch that returns an
/// equal day reuses the cache even though the list instance is new).
/// Two days that resolve to the same key paint an identical grid, so the cached
/// list can be reused.
class _DayCellsKey {
  _DayCellsKey(
    EffectiveDay day,
    this.startMin,
    this.endMin,
    List<(int, int)> bookedSpans,
  ) : date = day.date,
      source = day.source,
      intervalSig = _intervalSignature(day.intervals),
      bookedSig = _spanSignature(bookedSpans);

  final DateTime date;
  final EffectiveSource source;
  final String intervalSig;
  final String bookedSig;
  final int startMin;
  final int endMin;

  bool matches(
    EffectiveDay day,
    int startMin,
    int endMin,
    List<(int, int)> bookedSpans,
  ) =>
      this.startMin == startMin &&
      this.endMin == endMin &&
      date == day.date &&
      source == day.source &&
      intervalSig == _intervalSignature(day.intervals) &&
      bookedSig == _spanSignature(bookedSpans);

  static String _spanSignature(List<(int, int)> spans) {
    if (spans.isEmpty) return '';
    final StringBuffer b = StringBuffer();
    for (final (int start, int end) in spans) {
      b
        ..write(start)
        ..write('-')
        ..write(end)
        ..write(';');
    }
    return b.toString();
  }

  static String _intervalSignature(List<WorkInterval> intervals) {
    if (intervals.isEmpty) return '';
    final StringBuffer b = StringBuffer();
    for (final WorkInterval w in intervals) {
      b
        ..write(w.startMinutes)
        ..write('-')
        ..write(w.endMinutes)
        ..write(';');
    }
    return b.toString();
  }
}

List<SlotCell> _computeDayCells(
  EffectiveDay day,
  int gridStartMin,
  int gridEndMin,
  List<(int, int)> bookedSpans,
) {
  // A whole-day override or an empty day is one uniform availability state for
  // every cell — resolve it once and skip the per-cell interval scan. (Since
  // 2026-10-30 a whole-day OVERRIDE_DAY_OFF reads «Неробочий час», not pink.)
  final SlotState? uniform = switch (day.source) {
    EffectiveSource.overrideDayOff => SlotState.unavailable,
    _ when day.intervals.isEmpty => SlotState.unavailable,
    _ => null,
  };

  // Intervals are sorted defensively (the model keeps them ordered, but a
  // malformed payload must not break the early-exit interval scan).
  final List<WorkInterval> sorted = uniform != null
      ? const <WorkInterval>[]
      : (List<WorkInterval>.of(day.intervals)..sort(
          (WorkInterval a, WorkInterval b) =>
              a.startMinutes.compareTo(b.startMinutes),
        ));

  // Iterate cell-start minutes in 30-min steps, emitting a cell while its
  // START is before [gridEndMin]. On a working day [gridEndMin] == lastEnd, so
  // any cell starting at or after lastEnd is dropped — no trailing "off" cards
  // past the working span. Interior break cells sit before lastEnd and survive,
  // their state resolved by [_cellState].
  const int cellLen = 30;
  final List<SlotCell> cells = <SlotCell>[];
  for (
    int cellStartMin = gridStartMin;
    cellStartMin < gridEndMin;
    cellStartMin += cellLen
  ) {
    final TimeOfDay t = TimeOfDay(
      hour: cellStartMin ~/ 60,
      minute: cellStartMin % 60,
    );
    final SlotState state = _overlapsBooking(bookedSpans, cellStartMin)
        ? SlotState.booked
        : uniform ?? _cellState(sorted, cellStartMin);
    cells.add(SlotCell(time: t, state: state));
  }
  return cells;
}

/// Whether the 30-min cell `[cellStartMin, cellStartMin + 30)` overlaps any
/// booked span by at least one minute (half-open on both sides).
bool _overlapsBooking(List<(int, int)> bookedSpans, int cellStartMin) {
  const int cellLen = 30;
  final int cellEndMin = cellStartMin + cellLen;
  for (final (int start, int end) in bookedSpans) {
    if (start < cellEndMin && end > cellStartMin) return true;
  }
  return false;
}

/// The availability [SlotState] for the 30-min cell window `[cellStartMin,
/// cellStartMin + 30)` of a WORKING day (bookings are applied by the caller):
///
///   1. if any minute overlaps a working interval → [SlotState.available];
///   2. else (leading off, or a break between intervals) → [SlotState.unavailable].
SlotState _cellState(List<WorkInterval> sorted, int cellStartMin) {
  const int cellLen = 30;
  final int cellEndMin = cellStartMin + cellLen;
  for (int m = cellStartMin; m < cellEndMin; m++) {
    if (_minuteInAnyInterval(sorted, m)) return SlotState.available;
  }
  return SlotState.unavailable;
}

/// Whether minute [m] falls inside any working interval (half-open `[start,
/// end)`). [sorted] is start-ordered so the scan can stop early.
bool _minuteInAnyInterval(List<WorkInterval> sorted, int m) {
  for (final WorkInterval w in sorted) {
    if (m < w.startMinutes) break; // sorted: no later interval can contain m.
    if (m < w.endMinutes) return true;
  }
  return false;
}
