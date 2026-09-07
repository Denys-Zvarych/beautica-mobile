// Phase 312 — a compact one-line summary of a master's CURRENT weekly working
// hours, e.g. "Пн–Пт · 09:00–18:00" or "Пн, Ср, Пт · 10:00–19:00" for a
// non-contiguous pattern. Feeds the D3 «Графік роботи» `SettingsRow`'s
// trailing value on `salon_staff_profile_screen.dart`.
//
// Grepped first (REUSE-FIRST, plan file 15) — no existing weekly-summary
// formatter was found anywhere under `lib/`; `summariseSpan`
// (`schedule/domain/schedule_model.dart`) formats a single day's interval
// span ("09:00–18:00") but has no notion of a WEEK, so it is reused here for
// the hours half rather than re-derived.

import 'package:flutter/material.dart' show TimeOfDay;

import '../../features/schedule/domain/schedule_model.dart';
import '../../features/schedule/domain/weekly_schedule.dart';
import 'uk_calendar.dart';

/// Summarises [schedules] — every persisted weekly template — as it stands on
/// [today]. Returns [notSetLabel] when no template covers [today] (or the
/// resolved template has no working day at all).
String weeklyScheduleSummary(
  List<WeeklySchedule> schedules,
  DateTime today,
  String notSetLabel,
) {
  final WeeklySchedule? active = _activeTemplate(schedules, today);
  if (active == null) return notSetLabel;

  final List<TemplateDay> working = active.days
      .where((TemplateDay d) => !d.isDayOff)
      .toList(growable: false);
  if (working.isEmpty) return notSetLabel;

  return '${_dayRangeLabel(working)} · ${_hoursLabel(working)}';
}

/// The template whose `[validFrom, validTo]` window covers [today], or —
/// defensively, should none match (a gap between windows) — the first
/// template in [schedules]. `schedules` is small (a master rarely has more
/// than a couple of windows), so a linear scan is fine.
WeeklySchedule? _activeTemplate(
  List<WeeklySchedule> schedules,
  DateTime today,
) {
  if (schedules.isEmpty) return null;
  final DateTime day = DateTime(today.year, today.month, today.day);
  for (final WeeklySchedule s in schedules) {
    final DateTime from = DateTime(
      s.validFrom.year,
      s.validFrom.month,
      s.validFrom.day,
    );
    final DateTime? to = s.validTo;
    final bool afterFrom = !day.isBefore(from);
    final bool beforeTo =
        to == null || !day.isAfter(DateTime(to.year, to.month, to.day));
    if (afterFrom && beforeTo) return s;
  }
  return schedules.first;
}

/// «Пн–Пт» for a contiguous run of working ISO weekdays, «Пн» for a single
/// day, or a comma-joined list for a non-contiguous pattern (e.g. «Пн, Ср,
/// Пт»).
String _dayRangeLabel(List<TemplateDay> working) {
  final List<int> weekdays =
      working.map((TemplateDay d) => d.dayOfWeek).toList()..sort();
  if (weekdays.length == 1) {
    return ukCapitalize(weekdayAbbrev(weekdays.first));
  }
  final bool contiguous = weekdays.last - weekdays.first + 1 == weekdays.length;
  if (contiguous) {
    return '${ukCapitalize(weekdayAbbrev(weekdays.first))}–'
        '${ukCapitalize(weekdayAbbrev(weekdays.last))}';
  }
  return weekdays.map((int w) => ukCapitalize(weekdayAbbrev(w))).join(', ');
}

/// The working-hours half of the summary. Prefers the min–max span across
/// every working INTERVAL day (reusing [summariseSpan] — REUSE-FIRST); falls
/// back to the min–max of every working EXPLICIT_TIMES day's discrete start
/// times when no day carries intervals.
String _hoursLabel(List<TemplateDay> working) {
  final List<WorkInterval> allIntervals = <WorkInterval>[
    for (final TemplateDay d in working) ...d.intervals,
  ];
  if (allIntervals.isNotEmpty) return summariseSpan(allIntervals);

  final List<TimeOfDay> allTimes = <TimeOfDay>[
    for (final TemplateDay d in working) ...d.times,
  ];
  if (allTimes.isEmpty) return '';
  TimeOfDay min = allTimes.first;
  TimeOfDay max = allTimes.first;
  for (final TimeOfDay t in allTimes) {
    if (_minutes(t) < _minutes(min)) min = t;
    if (_minutes(t) > _minutes(max)) max = t;
  }
  return '${formatTime(min)}–${formatTime(max)}';
}

int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;
