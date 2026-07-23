// Phase 15.1 — Wire-facing freezed value objects for the persisted schedule
// shape (weekly template + effective day).
//
// These are the durable, equatable representations the data layer maps to/from
// the generated DTOs. The mutable, editor-facing model (`WorkInterval`,
// `TemplateDay`, `DayHours`, `ScheduleOverride`) lives in `schedule_model.dart`
// — it stays plain Dart so the editors' lossless window+breaks round-trip is
// preserved. Here we capture the immutable persisted snapshots:
//
//   • [WeeklySchedule]  — one active-window weekly template (validFrom/validTo
//     plus the seven ISO [TemplateDay]s).
//   • [EffectiveDay]    — the resolved schedule for one calendar date (the
//     calendar's data source), tagged with the [EffectiveSource] that produced
//     it.
//
// Dates are date-only `DateTime` at local midnight; times ride on
// [WorkInterval] (TimeOfDay). [TemplateDay]/[WorkInterval] are intentionally
// mutable plain-Dart classes referenced by these freezed records — freezed only
// guarantees the container's value identity, not deep immutability of the
// mutable members, which is acceptable here because these snapshots are rebuilt
// (never mutated in place) on every load.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:freezed_annotation/freezed_annotation.dart';

import 'schedule_model.dart';

part 'weekly_schedule.freezed.dart';

/// What produced an [EffectiveDay] for a given date. Maps 1:1 to the backend
/// `EffectiveDayResponse.source` wire enum (TEMPLATE / OVERRIDE_CUSTOM /
/// OVERRIDE_DAY_OFF / NO_SCHEDULE) — see [ScheduleMapper] for the translation.
enum EffectiveSource {
  /// The day is governed by the recurring weekly template.
  template,

  /// A per-date override replaced the template hours with custom intervals.
  overrideCustom,

  /// A per-date override closed the day entirely (a plain full day-off).
  overrideDayOff,

  /// No weekly template covers this date and no override exists — the master
  /// has not published hours for it.
  noSchedule,
}

/// One persisted active-window weekly template.
///
/// [validFrom] / [validTo] are date-only (local midnight); a null [validTo]
/// means the template is open-ended (still the active one). [days] is always
/// the dense, ordered seven-entry ISO week (Monday(1) … Sunday(7)) — the mapper
/// gap-fills any weekday the backend omitted with an empty-intervals day-off.
///
/// [id] is the backend schedule-row UUID when this template was loaded from the
/// server; it is `null` for a not-yet-persisted draft. The PUT path
/// (`updateWeeklySchedule`) needs the id, but the wire response does NOT carry
/// it — callers pass `scheduleId` explicitly to the repository's upsert.
@freezed
abstract class WeeklySchedule with _$WeeklySchedule {
  const factory WeeklySchedule({
    required DateTime validFrom,
    required DateTime? validTo,
    required List<TemplateDay> days,
    String? id,
  }) = _WeeklySchedule;
}

/// The resolved schedule for one calendar date — the calendar's per-day data
/// source.
///
/// [intervals] are the working intervals in effect for [date] (empty for a
/// day-off, a no-schedule day, OR an EXPLICIT_TIMES day). [times] (Phase 15.7)
/// are the resolved discrete start times — non-empty ONLY for an EXPLICIT_TIMES
/// day. The wire `EffectiveDayResponse` carries no `mode`, so [isExplicitTimes]
/// is derived from a non-empty [times] list. [source] tags how the day was
/// resolved.
@freezed
abstract class EffectiveDay with _$EffectiveDay {
  const factory EffectiveDay({
    required DateTime date,
    required EffectiveSource source,
    required List<WorkInterval> intervals,
    @Default(<TimeOfDay>[]) List<TimeOfDay> times,
  }) = _EffectiveDay;

  const EffectiveDay._();

  /// True when this resolved day is expressed as discrete start times rather
  /// than continuous intervals — i.e. the wire response returned a non-empty
  /// `times` list (the response has no `mode` field to read directly).
  bool get isExplicitTimes => times.isNotEmpty;
}
