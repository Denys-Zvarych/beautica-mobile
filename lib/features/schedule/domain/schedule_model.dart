// Phase 15.1 — Master Schedule canonical domain model.
//
// Transcribed VERBATIM from the approved preview
// `docs/signup-designs/MasterSchedule/lib/widgets/schedule_model.dart`.
// These are plain Dart (TimeOfDay-based), NOT freezed — keep them as-is so the
// editors' lossless window+breaks ⇄ intervals round-trip is preserved exactly
// as the preview produced it.
//
// The Ukrainian validation messages and the calendar formatting helpers are
// part of the ported contract — do not paraphrase them. They are domain strings
// (returned from pure functions, never passed to a widget arg), so they are
// outside the `no_raw_ui_strings` lint surface.
//
// WIRE-LAYER NOTE (superseded 2026-07-27 for the WINDOW only): break RANGES stay
// a presentation affordance derived here (`DayHours.fromIntervals` /
// `toIntervals`) — never serialise a break list, and never re-derive breaks in
// the wire layer. The working WINDOW, however, is now genuinely persisted: the
// backend stores `windowStart`/`windowEnd` on the weekly-template day, the
// per-date override and the effective day as DISPLAY-ONLY metadata (intervals
// remain the sole canonical availability; no backend availability path reads
// the window). So `schedule_mapper.dart` legitimately carries the window across
// the boundary — it is a stored field, not reconstructed break logic. Breaks are
// still computed here, from `window MINUS intervals`.

import 'package:flutter/material.dart';

// Phase 7.7 — the nominative month table moved to `shared/formatters/` when the
// range calendar was promoted to `shared/widgets/` and gained a second (booking)
// caller. Re-exported so every existing `monthNominative(...)` call site in the
// schedule feature keeps resolving through this file unchanged.
export 'package:beautica_mobile/shared/formatters/month_names.dart'
    show monthNominative;

// ─────────────────────────────────────────────────────────────────────────────
// Calendar / time formatting helpers (Ukrainian).
// Shared verbatim with the TimeOffScreen preview's month tables so the two
// screens speak the same calendar language.
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _monthsShort = <String>[
  'СІЧ',
  'ЛЮТ',
  'БЕР',
  'КВІ',
  'ТРА',
  'ЧЕР',
  'ЛИП',
  'СЕР',
  'ВЕР',
  'ЖОВ',
  'ЛИС',
  'ГРУ',
];

const List<String> _monthsGenitive = <String>[
  'січня',
  'лютого',
  'березня',
  'квітня',
  'травня',
  'червня',
  'липня',
  'серпня',
  'вересня',
  'жовтня',
  'листопада',
  'грудня',
];

String monthShort(int month) => _monthsShort[month - 1];

/// Long human date — e.g. "29 травня".
String formatDay(DateTime d) => '${d.day} ${_monthsGenitive[d.month - 1]}';

/// `HH:MM` with zero padding.
String formatTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

// ─────────────────────────────────────────────────────────────────────────────
// Phase 15.7 — discrete working-times mode.
//
// A working day (weekly template row OR per-date custom override) can be
// expressed in one of two mutually-exclusive shapes:
//   • INTERVAL        — continuous working window(s) (the existing model:
//                       `List<WorkInterval>`, optionally with breaks carved out).
//   • EXPLICIT_TIMES  — a discrete set of start times (`List<TimeOfDay>`), no
//                       intervals and no breaks. Each entry is a bookable slot
//                       start; the display window is derived min–max (Phase 15.9).
//
// This local enum mirrors the generated per-schema `...ModeEnum` values 1:1 but
// is deliberately INDEPENDENT of them — the generated DTO enums never cross the
// mapper boundary into the domain (same rule as [EffectiveSource]). The mapper
// (`schedule_mapper.dart`) owns the translation.
// ─────────────────────────────────────────────────────────────────────────────

/// How a working day's hours are expressed. Mirrors the generated
/// `WeeklyScheduleDay*ModeEnum` / `ScheduleOverride*ModeEnum` wire values
/// (INTERVAL / EXPLICIT_TIMES) without leaking the generated enum into domain.
enum WeekdayMode {
  /// Continuous working window(s) — the canonical [WorkInterval] list.
  interval,

  /// A discrete set of start times — no intervals, no breaks.
  explicitTimes,
}

int _timeMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

/// Returns [times] start-sorted and de-duplicated (by wall-clock minute).
///
/// Used on the read path (defensive: the wire list may arrive unsorted / with
/// dupes) and on the editor path (keep the discrete list canonical for compare
/// + display). Pure — never mutates the input.
List<TimeOfDay> sortDedupeTimes(Iterable<TimeOfDay> times) {
  final seen = <int>{};
  final result = <TimeOfDay>[];
  final sorted = List<TimeOfDay>.of(times)
    ..sort((a, b) => _timeMinutes(a).compareTo(_timeMinutes(b)));
  for (final t in sorted) {
    if (seen.add(_timeMinutes(t))) result.add(t);
  }
  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// Working intervals — the heart of the model.
//
// A working day is a *list* of intervals. The GAP between two consecutive
// intervals is the lunch / break — there is no separate "break" object. A day
// with zero intervals is a day-off.
// ─────────────────────────────────────────────────────────────────────────────

/// One working interval (start–end). Mutable so the editors can repoint the
/// pickers in place. Maps to a `{startTime,endTime}` wire pair on the port.
class WorkInterval {
  WorkInterval({required this.start, required this.end});

  WorkInterval clone() => WorkInterval(start: start, end: end);

  TimeOfDay start;
  TimeOfDay end;

  int get startMinutes => start.hour * 60 + start.minute;
  int get endMinutes => end.hour * 60 + end.minute;

  /// End must be strictly after start.
  bool get selfValid => endMinutes > startMinutes;
}

/// Validates an ordered list of intervals for one day. Returns the index of the
/// first interval that is invalid (bad self-range OR overlaps the previous one),
/// or `null` if every interval is sound. The list is treated in the order given
/// — the editors keep intervals start-sorted on render so "previous" means
/// "earlier in the day".
int? firstInvalidInterval(List<WorkInterval> intervals) {
  final List<WorkInterval> sorted = List<WorkInterval>.of(intervals)
    ..sort(
      (WorkInterval a, WorkInterval b) =>
          a.startMinutes.compareTo(b.startMinutes),
    );
  for (int i = 0; i < sorted.length; i++) {
    if (!sorted[i].selfValid) {
      return intervals.indexOf(sorted[i]);
    }
    if (i > 0 && sorted[i].startMinutes < sorted[i - 1].endMinutes) {
      return intervals.indexOf(sorted[i]);
    }
  }
  return null;
}

bool intervalsValid(List<WorkInterval> intervals) =>
    firstInvalidInterval(intervals) == null;

// ─────────────────────────────────────────────────────────────────────────────
// Working window + breaks — the editor's mental model.
//
// The UI no longer asks the master to think in abstract "intervals". Instead a
// day is expressed as ONE working window (від–до) with OPTIONAL break ranges
// carved out of it (lunch, rest). This is a *presentation* over the same
// `List<WorkInterval>` the model (and the backend port) already use:
//
//   working intervals  =  working window  MINUS  every break range
//
// Round-trip mapping (see [DayHours.fromIntervals] / [DayHours.toIntervals]):
//   • toIntervals: sort breaks, then walk the window left→right emitting a
//     WorkInterval for each gap between the previous cursor and the next break
//     start, then jump the cursor past the break end; a trailing WorkInterval
//     covers window-end. Zero breaks ⇒ a single [window.start, window.end].
//   • fromIntervals: has TWO regimes, decided by whether a stored window came
//     back from the wire.
//
// REGIME 1 — WINDOW PRESENT (the current backend contract). The stored
// `windowStart`/`windowEnd` IS the outer від–до, and
//
//     breaks  =  window  MINUS  intervals
//
// recovers EVERY break in one pass: interior breaks, a break flush against the
// window start, one flush against the end, or both. The round-trip is then
// GENUINELY LOSSLESS — saving window 09:00–18:00 with a 09:00–10:00 break stores
// intervals `[10:00–18:00]` PLUS window `09:00–18:00`, and reopening shows the
// window 09:00–18:00 with the 09:00–10:00 break still rendered as a break.
//
// REGIME 2 — WINDOW ABSENT (`null`). Every pre-window row hits this legacy path,
// and its behaviour is unchanged: the window is [firstStart, lastEnd] and each
// GAP between two consecutive intervals becomes a break. That regime is lossless
// in AVAILABILITY but NORMALIZING for edge-flush breaks — an edge-flush break
// leaves no gap to reconstruct, so `[10:00–18:00]` reads back as the window
// 10:00–18:00 with zero breaks. The presentation differs; the bookable time does
// not, which is why the legacy encoding was never wrong, only lossy on display.
//
// The wire shape is still the list of {startTime,endTime} working intervals that
// alone determines availability; `windowStart`/`windowEnd` ride alongside as
// display-only metadata the backend stores but never reads for availability.
// ─────────────────────────────────────────────────────────────────────────────

/// A single break range (start–end) carved out of the working window.
/// Off-time, NOT a working interval. Mutable so the editor repoints pickers in
/// place, mirroring [WorkInterval].
class BreakRange {
  BreakRange({required this.start, required this.end});

  BreakRange clone() => BreakRange(start: start, end: end);

  TimeOfDay start;
  TimeOfDay end;

  int get startMinutes => start.hour * 60 + start.minute;
  int get endMinutes => end.hour * 60 + end.minute;
}

/// The editor-facing representation of one day: a working window plus the breaks
/// carved out of it. Built from / collapsed back to the canonical
/// [WorkInterval] list so the underlying model and backend port are untouched.
class DayHours {
  DayHours({required this.window, required this.breaks});

  /// The full working window (the outer від–до the master "works"). A break
  /// can only ever live inside this window.
  WorkInterval window;

  /// The breaks carved out of [window]. May be empty (no break → one solid
  /// working block). Kept start-sorted by the editor on render.
  List<BreakRange> breaks;

  /// Default 09:00–18:00, no breaks.
  factory DayHours.defaultDay() => DayHours(
    window: WorkInterval(
      start: const TimeOfDay(hour: 9, minute: 0),
      end: const TimeOfDay(hour: 18, minute: 0),
    ),
    breaks: <BreakRange>[],
  );

  /// Reconstruct a window+breaks view from the canonical working-interval list.
  ///
  /// [window] is the STORED working window (`windowStart`/`windowEnd` off the
  /// wire), when the backend has one for this day. It selects between the two
  /// regimes documented in this file's header:
  ///
  ///   • [window] NON-NULL — the given window is the outer від–до and the breaks
  ///     are exactly `window MINUS intervals`. This recovers every break shape,
  ///     including one flush against the window start and/or end, which the
  ///     gap-based reconstruction below cannot see. Intervals are clamped to the
  ///     window first, so a malformed row (an interval poking outside a stored
  ///     window) degrades to a sane view instead of an inverted break.
  ///   • [window] NULL — legacy reconstruction, byte-for-byte the pre-window
  ///     behaviour: window = [first start, last end], every gap between two
  ///     consecutive intervals becomes a break. Edge-flush breaks are
  ///     unrecoverable here because they left no gap.
  ///
  /// Empty [intervals] → a default day regardless of [window] (callers gate on
  /// day-off separately, so this never represents "closed" — and the backend
  /// never stores a window for a day with no intervals, so honouring one here
  /// would only ever manufacture a whole-window break that
  /// [validateDayHours] rejects).
  factory DayHours.fromIntervals(
    List<WorkInterval> intervals, {
    WorkInterval? window,
  }) {
    if (intervals.isEmpty) return DayHours.defaultDay();
    final List<WorkInterval> sorted = List<WorkInterval>.of(intervals)
      ..sort(
        (WorkInterval a, WorkInterval b) =>
            a.startMinutes.compareTo(b.startMinutes),
      );
    if (window != null && window.endMinutes > window.startMinutes) {
      return DayHours(
        window: window.clone(),
        breaks: _breaksFromWindowMinusIntervals(window, sorted),
      );
    }
    final WorkInterval derivedWindow = WorkInterval(
      start: sorted.first.start,
      end: sorted.last.end,
    );
    final List<BreakRange> breaks = <BreakRange>[];
    for (int i = 1; i < sorted.length; i++) {
      final int gapStart = sorted[i - 1].endMinutes;
      final int gapEnd = sorted[i].startMinutes;
      if (gapEnd > gapStart) {
        breaks.add(_breakOf(gapStart, gapEnd));
      }
    }
    return DayHours(window: derivedWindow, breaks: breaks);
  }

  static BreakRange _breakOf(int startMinutes, int endMinutes) => BreakRange(
    start: TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60),
    end: TimeOfDay(hour: endMinutes ~/ 60, minute: endMinutes % 60),
  );

  /// The exact inverse of [toIntervals] for a KNOWN window: walk [sorted]
  /// (start-ordered, clamped to [window]) left→right and emit a [BreakRange] for
  /// every stretch of the window no interval covers — leading, interior and
  /// trailing alike.
  static List<BreakRange> _breaksFromWindowMinusIntervals(
    WorkInterval window,
    List<WorkInterval> sorted,
  ) {
    final List<BreakRange> breaks = <BreakRange>[];
    int cursor = window.startMinutes;
    for (final WorkInterval w in sorted) {
      final int end = w.endMinutes.clamp(
        window.startMinutes,
        window.endMinutes,
      );
      // Fully behind the cursor / entirely before the window.
      if (end <= cursor) {
        continue;
      }
      final int start = w.startMinutes.clamp(
        window.startMinutes,
        window.endMinutes,
      );
      if (start > cursor) breaks.add(_breakOf(cursor, start));
      cursor = end;
    }
    if (cursor < window.endMinutes) {
      breaks.add(_breakOf(cursor, window.endMinutes));
    }
    return breaks;
  }

  /// Collapse back to the canonical working-interval list (window minus breaks).
  /// This is what the host stores and what the backend port serialises. Assumes
  /// the day is valid (caller gates on [validateDayHours]); on a still-invalid
  /// state it degrades gracefully by CLAMPING each break to the remaining window
  /// and skipping the ones that fall entirely outside it.
  ///
  /// Clamping (never skipping) is what makes a break flush against the window
  /// edge carve real time off the day: a 09:00–10:00 break in a 09:00–18:00
  /// window emits `[10:00–18:00]`, not the unbroken window. An edge-flush break
  /// therefore yields no leading / trailing block at all — the break survives a
  /// reload because [window] is persisted alongside these intervals and
  /// [DayHours.fromIntervals] re-derives it as `window MINUS intervals` (see the
  /// two regimes in this file's header).
  ///
  /// Every emitted interval is contained in [window] by construction (the walk
  /// starts at `window.startMinutes`, never emits past `window.endMinutes`, and
  /// clamps each break to both edges). That is what lets the mapper send the
  /// window alongside these intervals without tripping the backend's
  /// "window must contain every interval" 400.
  List<WorkInterval> toIntervals() {
    final List<BreakRange> sorted = List<BreakRange>.of(breaks)
      ..sort(
        (BreakRange a, BreakRange b) =>
            a.startMinutes.compareTo(b.startMinutes),
      );
    final List<WorkInterval> result = <WorkInterval>[];
    int cursor = window.startMinutes;
    for (final BreakRange b in sorted) {
      if (b.endMinutes <= b.startMinutes) continue; // inverted / empty
      if (b.endMinutes <= cursor) continue; // fully behind the cursor
      // Fully past the window.
      if (b.startMinutes >= window.endMinutes) continue;
      final int start = b.startMinutes < cursor ? cursor : b.startMinutes;
      final int end = b.endMinutes > window.endMinutes
          ? window.endMinutes
          : b.endMinutes;
      if (start > cursor) {
        result.add(
          WorkInterval(
            start: TimeOfDay(hour: cursor ~/ 60, minute: cursor % 60),
            end: TimeOfDay(hour: start ~/ 60, minute: start % 60),
          ),
        );
      }
      // Always advance — a clamped break still consumes its span.
      cursor = end;
    }
    if (cursor < window.endMinutes) {
      result.add(
        WorkInterval(
          start: TimeOfDay(hour: cursor ~/ 60, minute: cursor % 60),
          end: window.end,
        ),
      );
    }
    // NOTE: no "collapse to the bare window" fallback. A break set that eats the
    // whole window is rejected up-front by [validateDayHours]
    // ([DayHoursErrorKind.breakCoversWholeWindow]), so an empty result can only
    // mean the caller ignored validation — and emitting FULL availability there
    // is the exact inverse of what the master asked for (an overbooking hazard).
    return result;
  }

  DayHours clone() => DayHours(
    window: window.clone(),
    breaks: breaks.map((BreakRange b) => b.clone()).toList(),
  );
}

/// The distinct validation problems a [DayHours] can carry. Lets the editor
/// localise the message via `AppLocalizations` instead of string-matching the
/// (domain-string) [DayHoursError.message]. Each value maps 1:1 to one of the
/// `validateDayHours` return cases.
enum DayHoursErrorKind {
  /// The working window's end is not strictly after its start.
  windowEndBeforeStart,

  /// A break's end is not strictly after its start.
  breakEndBeforeStart,

  /// A break falls partly or wholly outside the working window.
  breakOutsideWindow,

  /// Two breaks overlap.
  breaksOverlap,

  /// The breaks consume the ENTIRE working window, leaving zero bookable time.
  /// Saving such a day would either publish full availability (the exact
  /// inverse of the intent) or an empty interval list indistinguishable from a
  /// day off — the master must shorten a break or close the day instead.
  breakCoversWholeWindow,

  /// A time edge (window or break start/end) is not a multiple of 15 minutes.
  /// The editor snaps new picks to 15-min steps, but a legacy / loaded schedule
  /// may carry a misaligned edge — flag it so the master must re-align before
  /// re-saving.
  notAligned,
}

/// Validation problem for a [DayHours], with a Ukrainian message + which field
/// the editor should ring red. `null` index means the working window itself.
///
/// [kind] is the typed discriminator the UI uses to look up a localised message
/// (the [message] is kept as the canonical domain string / debug fallback).
class DayHoursError {
  const DayHoursError(
    this.message,
    this.kind, {
    this.windowInvalid = false,
    this.breakIndex,
  });

  final String message;
  final DayHoursErrorKind kind;
  final bool windowInvalid;
  final int? breakIndex;
}

/// Validates a window+breaks day. Returns the first problem found, or `null` if
/// the day is sound: window end > start, every break inside the window, every
/// break end > start, and no two breaks overlapping. Breaks are validated in
/// start-sorted order so "previous" means "earlier in the day".
DayHoursError? validateDayHours(DayHours day) {
  if (day.window.endMinutes <= day.window.startMinutes) {
    return const DayHoursError(
      'Час завершення робочого дня має бути пізніше початку',
      DayHoursErrorKind.windowEndBeforeStart,
      windowInvalid: true,
    );
  }
  // 15-minute alignment of the working window. New picks are snapped to a
  // 15-min step in the editor; this guards a legacy / loaded misaligned edge so
  // the master is forced to re-align before re-saving.
  if (day.window.startMinutes % 15 != 0 || day.window.endMinutes % 15 != 0) {
    return const DayHoursError(
      'Час має бути кратним 15 хвилинам',
      DayHoursErrorKind.notAligned,
      windowInvalid: true,
    );
  }
  // Pair each break with its ORIGINAL index so the error rings the right row.
  final List<MapEntry<int, BreakRange>> indexed =
      <MapEntry<int, BreakRange>>[
        for (int i = 0; i < day.breaks.length; i++)
          MapEntry<int, BreakRange>(i, day.breaks[i]),
      ]..sort(
        (MapEntry<int, BreakRange> a, MapEntry<int, BreakRange> b) =>
            a.value.startMinutes.compareTo(b.value.startMinutes),
      );

  for (int i = 0; i < indexed.length; i++) {
    final int originalIndex = indexed[i].key;
    final BreakRange b = indexed[i].value;
    if (b.endMinutes <= b.startMinutes) {
      return DayHoursError(
        'Час завершення перерви має бути пізніше початку',
        DayHoursErrorKind.breakEndBeforeStart,
        breakIndex: originalIndex,
      );
    }
    if (b.startMinutes % 15 != 0 || b.endMinutes % 15 != 0) {
      return DayHoursError(
        'Час має бути кратним 15 хвилинам',
        DayHoursErrorKind.notAligned,
        breakIndex: originalIndex,
      );
    }
    if (b.startMinutes < day.window.startMinutes ||
        b.endMinutes > day.window.endMinutes) {
      return DayHoursError(
        'Перерва має бути в межах робочих годин',
        DayHoursErrorKind.breakOutsideWindow,
        breakIndex: originalIndex,
      );
    }
    if (i > 0 && b.startMinutes < indexed[i - 1].value.endMinutes) {
      return DayHoursError(
        'Перерви не можуть перетинатися',
        DayHoursErrorKind.breaksOverlap,
        breakIndex: originalIndex,
      );
    }
  }

  // Every break is individually sound by now (inside the window, non-inverted,
  // non-overlapping), so their union covers the window iff walking them in
  // start order never leaves a gap. Zero working time left is rejected here so
  // [DayHours.toIntervals] may assume at least one working block survives —
  // without this gate a whole-window break would save FULL availability.
  if (indexed.isNotEmpty) {
    int cursor = day.window.startMinutes;
    for (final MapEntry<int, BreakRange> entry in indexed) {
      if (entry.value.startMinutes > cursor) break; // a working block survives
      cursor = entry.value.endMinutes;
    }
    if (cursor >= day.window.endMinutes) {
      return DayHoursError(
        'Перерва не може займати весь робочий день',
        DayHoursErrorKind.breakCoversWholeWindow,
        breakIndex: indexed.last.key,
      );
    }
  }
  return null;
}

bool dayHoursValid(DayHours day) => validateDayHours(day) == null;

// ─────────────────────────────────────────────────────────────────────────────
// Phase 15.7 — EXPLICIT_TIMES (discrete) validation.
//
// A working EXPLICIT_TIMES day/override is valid when it has ≥1 start time and
// no NaN edges — there are no intervals and no breaks to validate. An empty
// discrete list is a day-off in EXPLICIT_TIMES mode (the caller gates on
// "working vs off" separately, exactly like an empty interval list). 15-minute
// alignment is enforced so a loaded/legacy entry must be re-aligned before save,
// mirroring the INTERVAL window/break alignment guard.
// ─────────────────────────────────────────────────────────────────────────────

/// The validation problems a discrete (EXPLICIT_TIMES) working day can carry.
enum DiscreteTimesErrorKind {
  /// A working EXPLICIT_TIMES day has zero start times.
  empty,

  /// A start time is not a multiple of 15 minutes.
  notAligned,
}

/// Validates a non-empty list of discrete start times for ONE working
/// EXPLICIT_TIMES day/override. Returns the first problem found, or `null` if
/// the list is sound (≥1 time, every edge 15-min aligned). Dupes are tolerated
/// here (the mapper / [sortDedupeTimes] collapse them); only emptiness and
/// alignment are hard errors.
DiscreteTimesErrorKind? validateDiscreteTimes(List<TimeOfDay> times) {
  if (times.isEmpty) return DiscreteTimesErrorKind.empty;
  for (final t in times) {
    if (_timeMinutes(t) % 15 != 0) return DiscreteTimesErrorKind.notAligned;
  }
  return null;
}

/// A working EXPLICIT_TIMES day/override is valid iff it has ≥1 aligned time.
bool discreteTimesValid(List<TimeOfDay> times) =>
    validateDiscreteTimes(times) == null;

/// A compact one-line summary of a day's intervals, lunch gap shown as " · ":
/// e.g. "09:00–13:00 · 14:00–18:00". Empty list → "Вихідний".
String summariseIntervals(List<WorkInterval> intervals) {
  if (intervals.isEmpty) return 'Вихідний';
  final List<WorkInterval> sorted = List<WorkInterval>.of(intervals)
    ..sort(
      (WorkInterval a, WorkInterval b) =>
          a.startMinutes.compareTo(b.startMinutes),
    );
  return sorted
      .map((WorkInterval w) => '${formatTime(w.start)}–${formatTime(w.end)}')
      .join('  ·  ');
}

/// The overall work-day span — first interval start to last interval end —
/// collapsing any pauses: e.g. "09:00–18:00" for a day with a lunch break.
/// Empty list → "Вихідний". Scans for min start / max end defensively rather
/// than assuming the list is sorted (single-day contract: no cross-midnight).
///
/// NOTE: kept separate from [summariseIntervals], which is part of a cache /
/// identity key (`ScheduleOverride.key`) and must not change shape.
String summariseSpan(List<WorkInterval> intervals) {
  if (intervals.isEmpty) return 'Вихідний';
  WorkInterval first = intervals.first;
  WorkInterval last = intervals.first;
  for (final WorkInterval w in intervals) {
    if (w.startMinutes < first.startMinutes) first = w;
    if (w.endMinutes > last.endMinutes) last = w;
  }
  return '${formatTime(first.start)}–${formatTime(last.end)}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Weekly template day.
// ─────────────────────────────────────────────────────────────────────────────

/// Editable model for one ISO day of the recurring weekly template. Maps to the
/// backend's weekly working-hours rows (one per `dayOfWeek`, now carrying a
/// *list* of intervals rather than a single start/end pair).
class TemplateDay {
  TemplateDay({
    required this.dayOfWeek,
    required this.label,
    required this.intervals,
    this.mode = WeekdayMode.interval,
    this.times = const <TimeOfDay>[],
    this.window,
  });

  final int dayOfWeek; // 1=Mon … 7=Sun (ISO)
  final String label; // Ukrainian day name

  /// Continuous working interval(s). Populated for [WeekdayMode.interval];
  /// empty for [WeekdayMode.explicitTimes] (the [times] list is authoritative
  /// there) and for a day-off.
  List<WorkInterval> intervals;

  /// How this day's hours are expressed (Phase 15.7). Defaults to
  /// [WeekdayMode.interval] so every pre-15.7 caller keeps its meaning.
  WeekdayMode mode;

  /// Discrete start times. Authoritative for [WeekdayMode.explicitTimes];
  /// empty for [WeekdayMode.interval]. The opposite-shape field must stay
  /// cleared (see [setMode]).
  List<TimeOfDay> times;

  /// The stored working window (`windowStart`/`windowEnd`) for an INTERVAL day —
  /// DISPLAY-ONLY metadata that lets [DayHours.fromIntervals] recover a break
  /// flush against a window edge. `null` means "no stored window": a day-off, an
  /// [WeekdayMode.explicitTimes] day, or any legacy row saved before the backend
  /// persisted the field — all of which take the gap-reconstruction regime.
  /// [intervals] stays the sole source of availability either way.
  WorkInterval? window;

  /// A day-off is empty in whichever shape the [mode] selects.
  bool get isDayOff =>
      mode == WeekdayMode.explicitTimes ? times.isEmpty : intervals.isEmpty;

  bool get hasError => mode == WeekdayMode.explicitTimes
      ? false
      : intervals.isNotEmpty && !intervalsValid(intervals);

  List<WorkInterval> cloneIntervals() =>
      intervals.map((WorkInterval w) => w.clone()).toList();

  /// Flips this day to [next], clearing the now-inapplicable shape so the two
  /// representations never coexist. INTERVAL → drop [times]; EXPLICIT_TIMES →
  /// drop [intervals]. No-op when already in [next].
  void setMode(WeekdayMode next) {
    if (mode == next) return;
    mode = next;
    if (next == WeekdayMode.explicitTimes) {
      intervals = <WorkInterval>[];
      // The stored window describes an INTERVAL day's від–до; it is meaningless
      // (and rejected by the backend) for EXPLICIT_TIMES.
      window = null;
    } else {
      times = const <TimeOfDay>[];
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-date overrides — the exceptions that layer on top of the template.
//
// Two kinds:
//   • dayOff   — the date is fully closed (vacation / holiday / sick / other).
//   • custom   — the date works DIFFERENT intervals than the template.
// An override only exists where a date differs from the template.
// ─────────────────────────────────────────────────────────────────────────────

enum OverrideKind { dayOff, custom }

/// One per-date override as the *screen* models it: a contiguous span of dates
/// sharing one kind (a plain day-off, or custom-hours intervals).
/// A single date has `start == end`.
///
/// Wire note: the backend stores **one row per calendar date**. A multi-day
/// span here maps to N rows on save / re-grouped rows on load — the grouping is
/// a presentation convenience for identical overrides on consecutive dates.
class ScheduleOverride {
  ScheduleOverride.dayOff({required this.start, required this.end})
    : kind = OverrideKind.dayOff,
      mode = WeekdayMode.interval,
      intervals = const <WorkInterval>[],
      times = const <TimeOfDay>[],
      window = null;

  ScheduleOverride.custom({
    required this.start,
    required this.end,
    required this.intervals,
    this.window,
  }) : kind = OverrideKind.custom,
       mode = WeekdayMode.interval,
       times = const <TimeOfDay>[];

  /// A CUSTOM_HOURS override expressed as discrete start times (Phase 15.7).
  /// Carries no intervals — the [times] list is authoritative.
  ScheduleOverride.explicitTimes({
    required this.start,
    required this.end,
    required List<TimeOfDay> times,
  }) : kind = OverrideKind.custom,
       mode = WeekdayMode.explicitTimes,
       intervals = const <WorkInterval>[],
       times = sortDedupeTimes(times),
       window = null;

  final OverrideKind kind;
  final DateTime start;
  final DateTime end;

  /// How a CUSTOM_HOURS override is expressed. Always [WeekdayMode.interval]
  /// for a day-off (it carries neither intervals nor times).
  final WeekdayMode mode;

  /// Custom-hours INTERVAL shape only.
  final List<WorkInterval> intervals;

  /// Custom-hours EXPLICIT_TIMES shape only — discrete start times.
  final List<TimeOfDay> times;

  /// The stored working window (`windowStart`/`windowEnd`) of a CUSTOM_HOURS
  /// INTERVAL override — DISPLAY-ONLY metadata, exactly like [TemplateDay.window]
  /// (see that field for the null semantics). Always `null` for a day-off and for
  /// an EXPLICIT_TIMES override. Deliberately NOT part of [key]: two overrides on
  /// the same date can never coexist, so the window would only churn list
  /// identity without disambiguating anything.
  final WorkInterval? window;

  bool get isSingleDay =>
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;

  /// Inclusive day count of the span.
  int get dayCount => end.difference(start).inDays + 1;

  DateTime get sortKey => start;

  /// Stable-ish key for list widgets / Dismissible. An EXPLICIT_TIMES override
  /// keys off its discrete times (not [intervals], which are empty there) so it
  /// never collides with an interval custom override on the same date.
  String get key {
    if (kind == OverrideKind.dayOff) {
      return '${start.toIso8601String()}_${kind.name}';
    }
    if (mode == WeekdayMode.explicitTimes) {
      final summary = times.map(formatTime).join(',');
      return '${start.toIso8601String()}_${kind.name}_times_$summary';
    }
    return '${start.toIso8601String()}_${kind.name}_'
        '${summariseIntervals(intervals)}';
  }

  /// The new working window this override would leave in place, formatted
  /// `HH:mm–HH:mm` (e.g. `10:00–15:00`) — the day-off-conflict dialog's
  /// `narrowedHours` subline detail. `null` for a day-off (no window) or a
  /// custom override with no working time at all.
  ///
  /// INTERVAL mode: the earliest interval start to the latest interval end.
  /// EXPLICIT_TIMES mode: the earliest to the latest discrete start time —
  /// there is no "end" for a discrete slot, so the span is start-to-start,
  /// which is still a useful "these are the new hours" summary.
  String? get narrowedHoursLabel {
    if (kind == OverrideKind.dayOff) return null;
    if (mode == WeekdayMode.explicitTimes) {
      if (times.isEmpty) return null;
      final sorted = sortDedupeTimes(times);
      return '${formatTime(sorted.first)}–${formatTime(sorted.last)}';
    }
    if (intervals.isEmpty) return null;
    final sorted = List<WorkInterval>.of(intervals)
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    final latestEnd = sorted.fold<TimeOfDay>(
      sorted.first.end,
      (acc, i) => i.endMinutes > (acc.hour * 60 + acc.minute) ? i.end : acc,
    );
    return '${formatTime(sorted.first.start)}–${formatTime(latestEnd)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2026-07-26 design — schedule override booking-conflict check.
//
// `POST /masters/{id}/overrides/conflicts` (read-only preview) and the
// `cancelOverlapping` flag on `PUT /overrides/{date}` (write). See
// `ScheduleRepository.previewConflicts` / `.putOverride` for the wire layer,
// `OverridesNotifier.checkConflicts` for the orchestration, and
// `DayOffConflictDialog` (presentation/widgets) for the confirmation UI these
// feed. Ported from the approved preview at
// `docs/signup-designs/DayOffConflictDialog/lib/screens/day_off_conflict_data.dart`
// — the dialog's copy is NOT baked into these domain types (unlike the
// preview, which returns literal Ukrainian strings from `title`/`subline`
// getters): every user-facing string route through `AppLocalizations` per
// the `no_raw_ui_strings` CI gate, so this app's `DayOffConflictDialog` reads
// this DATA and composes the copy itself via l10n ICU plurals.
// ─────────────────────────────────────────────────────────────────────────────

/// What kind of schedule change produced a conflict list — decides which
/// dialog copy the presentation layer selects.
enum DayOffChangeKind {
  /// One calendar date turned into a full day off.
  singleDay,

  /// A span of dates turned into days off (vacation, sick leave).
  dateRange,

  /// The date(s) stay a working day, but the hours were narrowed and some
  /// bookings now fall outside them.
  narrowedHours,
}

/// One CONFIRMED booking that a pending override would leave without
/// availability. Carries no price — the dialog is about people and times,
/// not revenue (locked 2026-07-26 design decision).
class OverrideConflict {
  const OverrideConflict({
    required this.bookingId,
    required this.appointmentId,
    required this.date,
    required this.startsAt,
    required this.endsAt,
    required this.clientDisplayName,
    required this.serviceName,
  });

  final String bookingId;

  /// Non-null when this conflict is one item of a multi-service visit.
  final String? appointmentId;

  /// Calendar date (Kyiv-local) the booking falls on — the backend's own
  /// timezone-resolved value, never re-derived client-side from [startsAt].
  final DateTime date;

  final DateTime startsAt;
  final DateTime endsAt;
  final String clientDisplayName;
  final String serviceName;

  int get durationMinutes => endsAt.difference(startsAt).inMinutes;
}

/// The full result of `POST /overrides/conflicts` — [OverridesNotifier
/// .checkConflicts]'s return value and the day-off-conflict dialog's single
/// input (together with [start] / [end] / the change [DayOffChangeKind]).
class OverrideConflictCheck {
  const OverrideConflictCheck({
    required this.conflicts,
    required this.totalCount,
    required this.truncated,
    required this.scanTruncated,
  });

  /// Sorted chronologically by the backend. Capped at the server's
  /// `MAX_PREVIEW_RESULTS` (500) — see [truncated].
  final List<OverrideConflict> conflicts;

  /// The server-computed conflict count. Equal to `conflicts.length` unless
  /// [truncated] is true, in which case this is the true count (still exact,
  /// since only the RESULT LIST was trimmed) — unless [scanTruncated] is
  /// ALSO true, in which case this is only a lower bound (the candidate scan
  /// itself was capped before counting). See [isCountExact].
  final int totalCount;

  /// True when [conflicts] was trimmed to fewer rows than [totalCount].
  final bool truncated;

  /// True when the server's underlying candidate scan itself was capped —
  /// [totalCount] is then only a LOWER BOUND on the true conflict count, not
  /// an exact figure. Independent of [truncated] (see that field's doc and
  /// `ScheduleOverrideConflictService.MAX_CANDIDATES_SCANNED`'s javadoc on the
  /// backend).
  final bool scanTruncated;

  bool get isEmpty => conflicts.isEmpty;
  bool get isNotEmpty => conflicts.isNotEmpty;

  /// False the moment [totalCount] cannot be trusted as the true conflict
  /// count — the dialog must then render "at least N" copy instead of "N".
  bool get isCountExact => !scanTruncated;

  /// True when [conflicts] spans more than one calendar date — the dialog
  /// then groups rows under date headers instead of relying on its own
  /// subline to establish the day.
  bool get spansMultipleDates {
    if (conflicts.length < 2) return false;
    final DateTime first = conflicts.first.date;
    return conflicts.any((OverrideConflict c) => c.date != first);
  }
}
