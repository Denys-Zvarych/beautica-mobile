// Phase 15.2 — Master Schedule day-grid render projection.
//
// Transcribed from the approved preview
// `docs/signup-designs/MasterSchedule/lib/widgets/day_schedule.dart`, adapted to
// project off the Phase 15.1 [EffectiveDay] (the calendar's real data source)
// instead of the preview's in-memory `DaySchedule` sample.
//
// The 30-min [SlotCell] grid is a PURE RENDER PROJECTION — it is computed from
// the resolved [EffectiveDay] (template- or override-derived) on every build and
// is NEVER stored (cf. Phase 15.1 contract + preview README). The projection:
//   • inside a working interval                       → [SlotState.available]
//   • inside an OVERRIDE_DAY_OFF span (whole day off) → [SlotState.timeOff]
//   • outside every interval (incl. NO_SCHEDULE gap)  → [SlotState.unavailable]
//
// No client bookings appear on this surface — availability only.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import 'slot_colors.dart';

/// One 30-minute cell of the day grid. Purely a *render* projection — computed
/// from the resolved [EffectiveDay], never stored on its own.
class SlotCell {
  const SlotCell({required this.time, required this.state});

  final TimeOfDay time;
  final SlotState state;
}

/// The localised human label for a [SlotState] (legend + per-cell semantics).
///
/// Deviation from the preview, which hard-coded the Ukrainian strings on the
/// enum: production routes them through [AppLocalizations] so they satisfy
/// `no_raw_ui_strings` and stay EN-ready. The Ukrainian wording is byte-for-byte
/// the approved preview copy ("Робочий час" / "Час відпочинку" / "Неробочий час").
String slotStateLabel(AppLocalizations l10n, SlotState state) =>
    switch (state) {
      SlotState.available => l10n.scheduleSlotWorking,
      SlotState.timeOff => l10n.scheduleSlotTimeOff,
      SlotState.unavailable => l10n.scheduleSlotOff,
    };

/// Builds the ordered list of 30-min [SlotCell]s for [day], spanning
/// [gridStartHour] until [gridEndHour] (inclusive of the trailing hour's :00
/// row, like the reference's 09:00 → 19:00 column).
///
/// [day] is the resolved [EffectiveDay] from Phase 15.1. State mapping (which
/// mirrors the four [EffectiveSource] cases the backend can produce):
///   • intervals present (TEMPLATE / OVERRIDE_CUSTOM) → green inside the
///     interval, grey outside.
///   • OVERRIDE_DAY_OFF (the master deliberately closed the date — vacation /
///     holiday / sick / other) → the whole grid reads pink "Час відпочинку",
///     distinguishing a chosen rest day from a simple gap.
///   • NO_SCHEDULE (no hours published for the date) → all grey
///     "Неробочий час".
///
/// Note: 15.1's [EffectiveDay] models a day-off as a WHOLE-DAY override with
/// empty intervals (there is no partial time-off span carrying intervals — a
/// rest block inside a working day is expressed as a gap between two working
/// intervals, which simply renders grey). So OVERRIDE_DAY_OFF is the only
/// source that paints the time-off tint, and it paints the entire grid.
List<SlotCell> buildDayCells(
  EffectiveDay day, {
  int gridStartHour = 9,
  int gridEndHour = 19,
}) {
  // Perf (HIGH-2): the 42-cell projection is a pure function of the day's
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
  final bool dayOff = day.source == EffectiveSource.overrideDayOff;
  final List<SlotCell> cells = <SlotCell>[];
  for (int h = gridStartHour; h <= gridEndHour; h++) {
    for (final int min in const <int>[0, 30]) {
      final TimeOfDay t = TimeOfDay(hour: h, minute: min);
      final SlotState state;
      if (_inAnyInterval(day.intervals, t)) {
        state = SlotState.available;
      } else if (dayOff) {
        // Explicit rest/time-off override (OVERRIDE_DAY_OFF) → pink. The day
        // carries no working intervals, so every cell takes the time-off tint.
        state = SlotState.timeOff;
      } else {
        // Outside every interval — or a NO_SCHEDULE gap → grey.
        state = SlotState.unavailable;
      }
      cells.add(SlotCell(time: t, state: state));
    }
  }
  return cells;
}

/// True when [t] falls inside any working [intervals] (half-open `[start,end)`).
bool _inAnyInterval(List<WorkInterval> intervals, TimeOfDay t) {
  final int m = t.hour * 60 + t.minute;
  for (final WorkInterval w in intervals) {
    if (m >= w.startMinutes && m < w.endMinutes) return true;
  }
  return false;
}
