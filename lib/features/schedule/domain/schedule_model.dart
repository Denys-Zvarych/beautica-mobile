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
// WIRE-LAYER NOTE: the window+breaks split is a PRESENTATION affordance handled
// entirely inside this model (`DayHours.fromIntervals`/`toIntervals`). The data
// layer (`schedule_mapper.dart`) only ever sees `List<WorkInterval>`, exactly
// like the backend. Never move break logic into the wire layer.

import 'package:flutter/material.dart';

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

const List<String> _monthsNominative = <String>[
  'Січень',
  'Лютий',
  'Березень',
  'Квітень',
  'Травень',
  'Червень',
  'Липень',
  'Серпень',
  'Вересень',
  'Жовтень',
  'Листопад',
  'Грудень',
];

String monthShort(int month) => _monthsShort[month - 1];
String monthNominative(int month) => _monthsNominative[month - 1];

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
//   • fromIntervals: the window is [firstStart, lastEnd]; each GAP between two
//     consecutive intervals becomes a break range. This is exactly the inverse,
//     so a load→edit→save cycle is lossless for any template the old multi-
//     interval editor could produce.
//
// So on the backend port nothing changes: the wire shape is still a list of
// {startTime,endTime} working intervals per day. The window+breaks split is a
// pure client-side affordance.
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
  /// Window = [first start, last end]; every gap between consecutive intervals
  /// becomes a break. Empty list → a default day (callers gate on day-off
  /// separately, so this never represents "closed").
  factory DayHours.fromIntervals(List<WorkInterval> intervals) {
    if (intervals.isEmpty) return DayHours.defaultDay();
    final List<WorkInterval> sorted = List<WorkInterval>.of(intervals)
      ..sort(
        (WorkInterval a, WorkInterval b) =>
            a.startMinutes.compareTo(b.startMinutes),
      );
    final WorkInterval window = WorkInterval(
      start: sorted.first.start,
      end: sorted.last.end,
    );
    final List<BreakRange> breaks = <BreakRange>[];
    for (int i = 1; i < sorted.length; i++) {
      final int gapStart = sorted[i - 1].endMinutes;
      final int gapEnd = sorted[i].startMinutes;
      if (gapEnd > gapStart) {
        breaks.add(
          BreakRange(
            start: TimeOfDay(hour: gapStart ~/ 60, minute: gapStart % 60),
            end: TimeOfDay(hour: gapEnd ~/ 60, minute: gapEnd % 60),
          ),
        );
      }
    }
    return DayHours(window: window, breaks: breaks);
  }

  /// Collapse back to the canonical working-interval list (window minus breaks).
  /// This is what the host stores and what the backend port serialises. Assumes
  /// the day is valid (caller gates on [validate]); on a still-invalid state it
  /// degrades gracefully by skipping out-of-window / inverted breaks.
  List<WorkInterval> toIntervals() {
    final List<BreakRange> sorted = List<BreakRange>.of(breaks)
      ..sort(
        (BreakRange a, BreakRange b) =>
            a.startMinutes.compareTo(b.startMinutes),
      );
    final List<WorkInterval> result = <WorkInterval>[];
    int cursor = window.startMinutes;
    for (final BreakRange b in sorted) {
      // Ignore breaks that don't sit cleanly inside the remaining window.
      if (b.startMinutes <= cursor || b.endMinutes >= window.endMinutes) {
        continue;
      }
      if (b.endMinutes <= b.startMinutes) continue;
      if (b.startMinutes > cursor) {
        result.add(
          WorkInterval(
            start: TimeOfDay(hour: cursor ~/ 60, minute: cursor % 60),
            end: b.start,
          ),
        );
      }
      cursor = b.endMinutes;
    }
    if (cursor < window.endMinutes) {
      result.add(
        WorkInterval(
          start: TimeOfDay(hour: cursor ~/ 60, minute: cursor % 60),
          end: window.end,
        ),
      );
    }
    // A window with no valid working time left collapses to the bare window so
    // the day is never silently emptied.
    if (result.isEmpty) {
      result.add(WorkInterval(start: window.start, end: window.end));
    }
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
/// four `validateDayHours` return cases.
enum DayHoursErrorKind {
  /// The working window's end is not strictly after its start.
  windowEndBeforeStart,

  /// A break's end is not strictly after its start.
  breakEndBeforeStart,

  /// A break falls partly or wholly outside the working window.
  breakOutsideWindow,

  /// Two breaks overlap.
  breaksOverlap,

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
      times = const <TimeOfDay>[];

  ScheduleOverride.custom({
    required this.start,
    required this.end,
    required this.intervals,
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
       times = sortDedupeTimes(times);

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
}
