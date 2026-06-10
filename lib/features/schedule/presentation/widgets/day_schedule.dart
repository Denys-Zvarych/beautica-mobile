// Phase 15.2 — Master Schedule day-grid render projection.
//
// Transcribed from the approved preview
// `docs/signup-designs/MasterSchedule/lib/widgets/day_schedule.dart`, adapted to
// project off the Phase 15.1 [EffectiveDay] (the calendar's real data source)
// instead of the preview's in-memory `DaySchedule` sample.
//
// The 30-min [SlotCell] grid is a PURE RENDER PROJECTION — it is computed from
// the resolved [EffectiveDay] (template- or override-derived) on every build and
// is NEVER stored (cf. Phase 15.1 contract + preview README). Each cell carries
// exactly ONE [SlotState] (solid single-colour chip — no proportional / split /
// banded fills). The state assigned to a 30-min cell window `[s, s+30)`:
//   • OVERRIDE_DAY_OFF (whole day off)                → [SlotState.timeOff]
//   • NO_SCHEDULE / no intervals                      → [SlotState.unavailable]
//   • otherwise (working day, intervals present):
//       – the cell overlaps an INTERIOR PAUSE (a gap     → [SlotState.timeOff]
//         between two consecutive working intervals)        (FULLY red — the
//         even by a single minute → WHOLE-CELL RED            round-up rule)
//       – else the cell overlaps any working interval   → [SlotState.available]
//       – else (leading / trailing off)                 → [SlotState.unavailable]
//
// The "round-up" (ceil) pause rule: a 15-min pause paints the ONE 30-min card
// that contains it fully red; a 45-min pause paints TWO cards fully red. A pause
// wins over partial work in the same cell (pause beats work when both touch it).
//
// A "pause" is derived CLIENT-SIDE: the interior non-working span of a working
// day (minutes inside `[firstStart, lastEnd)` that fall in no interval). Leading
// and trailing gaps stay grey "off". No backend change — the wire format is the
// same minute-precise `List<WorkInterval>`.
//
// No client bookings appear on this surface — availability only.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

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
/// `no_raw_ui_strings` and stay EN-ready. The Ukrainian wording is byte-for-byte
/// the approved preview copy ("Робочий час" / "Час відпочинку" / "Неробочий
/// час").
String slotStateLabel(AppLocalizations l10n, SlotState state) =>
    switch (state) {
      SlotState.available => l10n.scheduleSlotWorking,
      SlotState.timeOff => l10n.scheduleSlotTimeOff,
      SlotState.unavailable => l10n.scheduleSlotOff,
    };

/// The localised semantic label for a [cell]: its time + state label (e.g.
/// "09:00 — Робочий час"). Used for the chip's a11y label so the state is
/// conveyed without relying on colour.
String slotCellLabel(AppLocalizations l10n, SlotCell cell) {
  final String time =
      '${cell.time.hour.toString().padLeft(2, '0')}:${cell.time.minute.toString().padLeft(2, '0')}';
  return '$time — ${slotStateLabel(l10n, cell.state)}';
}

/// Builds the ordered list of 30-min [SlotCell]s for [day]. The grid spans a
/// default 09:00 → 19:00 window, expanded only as far as needed to contain any
/// working interval that falls outside it (clamped to `[0, 24]`).
///
/// [day] is the resolved [EffectiveDay] from Phase 15.1. State mapping (which
/// mirrors the four [EffectiveSource] cases the backend can produce):
///   • intervals present (TEMPLATE / OVERRIDE_CUSTOM) → green inside an
///     interval; the interior gap between intervals is a PAUSE rendered RED
///     under the whole-cell round-up rule; the lead-in before the first interval
///     and the run-out after the last are GREY.
///   • OVERRIDE_DAY_OFF (the master deliberately closed the date — vacation /
///     holiday / sick / other) → the whole grid reads pink "Час відпочинку",
///     distinguishing a chosen rest day from a simple gap.
///   • NO_SCHEDULE (no hours published for the date) → all grey "Неробочий час".
List<SlotCell> buildDayCells(EffectiveDay day) {
  final (int gridStartHour, int gridEndHour) = _gridBounds(day.intervals);

  // Perf (HIGH-2): the projection is a pure function of the day's
  // (date, source, intervals) — recomputing + reallocating the list on every
  // build is wasteful, especially since the grid is now isolated and rebuilt
  // independently of day selection. Memoize a single most-recent result keyed
  // by the resolved day + grid bounds: a day-change recomputes once, a pure
  // strip-highlight repaint (no day change) reuses the cached list verbatim.
  if (_cachedKey != null &&
      _cachedKey!.matches(day, gridStartHour, gridEndHour)) {
    return _cachedCells!;
  }
  final List<SlotCell> cells = _computeDayCells(
    day,
    gridStartHour,
    gridEndHour,
  );
  _cachedKey = _DayCellsKey(day, gridStartHour, gridEndHour);
  _cachedCells = cells;
  return cells;
}

/// The grid's `[startHour, endHour]` (both inclusive of the hour's :00 row).
/// Defaults to the reference 9–19 column and only expands when an interval
/// reaches earlier / later, clamped to `[0, 24]`.
(int, int) _gridBounds(List<WorkInterval> intervals) {
  int startHour = 9;
  int endHour = 19;
  if (intervals.isNotEmpty) {
    int firstStart = intervals.first.startMinutes;
    int lastEnd = intervals.first.endMinutes;
    for (final WorkInterval w in intervals) {
      if (w.startMinutes < firstStart) firstStart = w.startMinutes;
      if (w.endMinutes > lastEnd) lastEnd = w.endMinutes;
    }
    final int floorHour = (firstStart ~/ 60).clamp(0, 24);
    final int ceilHour = ((lastEnd + 59) ~/ 60).clamp(0, 24);
    if (floorHour < startHour) startHour = floorHour;
    if (ceilHour > endHour) endHour = ceilHour;
  }
  return (startHour, endHour);
}

// Single-entry memo for [buildDayCells] (the calendar shows one day at a time).
_DayCellsKey? _cachedKey;
List<SlotCell>? _cachedCells;

/// Identity of a [buildDayCells] computation: the resolved day's date + source
/// + interval shape, plus the grid bounds. Two days that resolve to the same
/// key paint an identical grid, so the cached list can be reused.
class _DayCellsKey {
  _DayCellsKey(EffectiveDay day, this.startHour, this.endHour)
    : date = day.date,
      source = day.source,
      intervalSig = _intervalSignature(day.intervals);

  final DateTime date;
  final EffectiveSource source;
  final String intervalSig;
  final int startHour;
  final int endHour;

  bool matches(EffectiveDay day, int startHour, int endHour) =>
      this.startHour == startHour &&
      this.endHour == endHour &&
      date == day.date &&
      source == day.source &&
      intervalSig == _intervalSignature(day.intervals);

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
  int gridStartHour,
  int gridEndHour,
) {
  // A whole-day override or an empty day is one uniform state for every cell —
  // resolve it once and skip the per-cell interval scan.
  final SlotState? uniform = switch (day.source) {
    EffectiveSource.overrideDayOff => SlotState.timeOff,
    _ when day.intervals.isEmpty => SlotState.unavailable,
    _ => null,
  };

  // For a working day, the interior-pause window is `[firstStart, lastEnd)`:
  // any minute inside it that falls in no interval is a pause. Intervals are
  // sorted defensively (the model keeps them ordered, but a malformed payload
  // must not break the first/last derivation).
  final List<WorkInterval> sorted = uniform != null
      ? const <WorkInterval>[]
      : (List<WorkInterval>.of(day.intervals)..sort(
          (WorkInterval a, WorkInterval b) =>
              a.startMinutes.compareTo(b.startMinutes),
        ));
  final int firstStart = sorted.isEmpty ? 0 : sorted.first.startMinutes;
  final int lastEnd = sorted.isEmpty ? 0 : sorted.last.endMinutes;

  final List<SlotCell> cells = <SlotCell>[];
  for (int h = gridStartHour; h <= gridEndHour; h++) {
    for (final int min in const <int>[0, 30]) {
      final TimeOfDay t = TimeOfDay(hour: h, minute: min);
      final SlotState state =
          uniform ?? _cellState(sorted, h * 60 + min, firstStart, lastEnd);
      cells.add(SlotCell(time: t, state: state));
    }
  }
  return cells;
}

/// The single [SlotState] for the 30-min cell window `[cellStartMin,
/// cellStartMin + 30)` of a WORKING day. Applies the whole-cell round-up rule:
///
///   1. if ANY minute of the cell falls in an interior pause → [SlotState.timeOff]
///      (FULLY red — a pause wins over partial work in the same cell);
///   2. else if any minute overlaps a working interval       → [SlotState.available];
///   3. else (leading / trailing off)                        → [SlotState.unavailable].
SlotState _cellState(
  List<WorkInterval> sorted,
  int cellStartMin,
  int firstStart,
  int lastEnd,
) {
  const int cellLen = 30;
  final int cellEndMin = cellStartMin + cellLen;

  bool overlapsWork = false;
  for (int m = cellStartMin; m < cellEndMin; m++) {
    final bool inInterval = _minuteInAnyInterval(sorted, m);
    if (inInterval) {
      overlapsWork = true;
      continue;
    }
    // A pause minute: inside the working span but in no interval. The round-up
    // rule fires on the FIRST such minute — the whole cell is red.
    if (m >= firstStart && m < lastEnd) {
      return SlotState.timeOff;
    }
  }
  return overlapsWork ? SlotState.available : SlotState.unavailable;
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
