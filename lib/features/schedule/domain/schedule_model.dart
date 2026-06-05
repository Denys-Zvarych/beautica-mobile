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

/// Validation problem for a [DayHours], with a Ukrainian message + which field
/// the editor should ring red. `null` index means the working window itself.
class DayHoursError {
  const DayHoursError(
    this.message, {
    this.windowInvalid = false,
    this.breakIndex,
  });

  final String message;
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
        breakIndex: originalIndex,
      );
    }
    if (b.startMinutes < day.window.startMinutes ||
        b.endMinutes > day.window.endMinutes) {
      return DayHoursError(
        'Перерва має бути в межах робочих годин',
        breakIndex: originalIndex,
      );
    }
    if (i > 0 && b.startMinutes < indexed[i - 1].value.endMinutes) {
      return DayHoursError(
        'Перерви не можуть перетинатися',
        breakIndex: originalIndex,
      );
    }
  }
  return null;
}

bool dayHoursValid(DayHours day) => validateDayHours(day) == null;

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
  });

  final int dayOfWeek; // 1=Mon … 7=Sun (ISO)
  final String label; // Ukrainian day name
  List<WorkInterval> intervals;

  bool get isDayOff => intervals.isEmpty;
  bool get hasError => intervals.isNotEmpty && !intervalsValid(intervals);

  List<WorkInterval> cloneIntervals() =>
      intervals.map((WorkInterval w) => w.clone()).toList();
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

/// The fixed reasons a *day-off* override can carry. Mirrors the backend enum
/// `ScheduleExceptionReason` (VACATION / HOLIDAY / SICK_DAY / OTHER) 1:1.
enum OverrideReason {
  vacation('VACATION', 'Відпустка', Icons.beach_access_rounded),
  holiday('HOLIDAY', 'Святковий день', Icons.celebration_rounded),
  sickDay('SICK_DAY', 'Лікарняний', Icons.healing_rounded),
  other('OTHER', 'Інше', Icons.event_busy_rounded);

  const OverrideReason(this.wire, this.label, this.icon);

  final String wire;
  final String label;
  final IconData icon;
}

/// One per-date override as the *screen* models it: a contiguous span of dates
/// sharing one kind (+ reason/note for day-offs, or intervals for custom-hours).
/// A single date has `start == end`.
///
/// Wire note: the backend stores **one row per calendar date**. A multi-day
/// span here maps to N rows on save / re-grouped rows on load — the grouping is
/// a presentation convenience for identical overrides on consecutive dates.
class ScheduleOverride {
  ScheduleOverride.dayOff({
    required this.start,
    required this.end,
    required this.reason,
    this.note,
  }) : kind = OverrideKind.dayOff,
       intervals = const <WorkInterval>[];

  ScheduleOverride.custom({
    required this.start,
    required this.end,
    required this.intervals,
  }) : kind = OverrideKind.custom,
       reason = null,
       note = null;

  final OverrideKind kind;
  final DateTime start;
  final DateTime end;

  /// Day-off only.
  final OverrideReason? reason;
  final String? note;

  /// Custom-hours only.
  final List<WorkInterval> intervals;

  bool get isSingleDay =>
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;

  /// Inclusive day count of the span.
  int get dayCount => end.difference(start).inDays + 1;

  DateTime get sortKey => start;

  /// Stable-ish key for list widgets / Dismissible.
  String get key =>
      '${start.toIso8601String()}_${kind.name}_${reason?.wire ?? summariseIntervals(intervals)}';
}
