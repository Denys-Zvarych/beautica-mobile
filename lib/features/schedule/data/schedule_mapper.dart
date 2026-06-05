// Phase 15.1 — ScheduleMapper: the single translation boundary between the
// generated schedule DTOs (`package:beautica_api`) and the domain schedule
// model.
//
// Generated DTO types (WorkIntervalDto, WeeklyScheduleResponse / -Request,
// ScheduleOverrideResponse / -Request, EffectiveDayResponse, the *_Enum types,
// built_value Date) must never cross this boundary into domain / presentation.
//
// CONTRACTS this mapper owns:
//   • Time wire format — `HH:mm:ss` ↔ TimeOfDay. Seconds are DROPPED on parse
//     and ZEROED on serialise (matches the Phase 6.1 working-hours helpers, so
//     the wire shape is identical to the existing endpoints).
//   • Weekly gap-fill — the backend may omit day-off weekdays, so
//     [weeklyScheduleFromResponse] always materialises all 7 ISO [TemplateDay]s
//     ordered 1..7; a missing weekday (or an explicit empty-intervals row)
//     becomes a day-off (empty intervals). [weeklyScheduleToRequest] is the
//     inverse: an empty-intervals [TemplateDay] is sent as an empty list.
//   • Override 1 row = 1 date — the mapper NEVER groups multi-day spans. The
//     span grouping the screen shows is a presentation concern handled in the
//     notifier/UI, exactly as the preview documents. Each
//     [ScheduleOverrideResponse] maps to a single-day [ScheduleOverride]
//     (start == end), and [overrideToRequestForDate] serialises one date.
//
// WINDOW+BREAKS NOTE: the window+breaks split is NOT part of the wire layer.
// This mapper only ever sees `List<WorkInterval>` — exactly like the backend.
// The editor (Phase 15.3) does the `DayHours.fromIntervals`/`toIntervals` split.
// Do not move break logic here.

import 'package:beautica_api/beautica_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';

import '../domain/schedule_model.dart';
import '../domain/weekly_schedule.dart';

/// Number of ISO days in a week (1 = Monday … 7 = Sunday).
const int _kDaysInWeek = 7;

/// Ukrainian ISO-weekday labels, ordered Monday(1) … Sunday(7). Ported from the
/// approved MasterSchedule preview (`_weekdayFull`). Domain strings (used to
/// label a [TemplateDay]); they are not widget-arg literals.
const List<String> _kWeekdayLabels = <String>[
  'Понеділок',
  'Вівторок',
  'Середа',
  'Четвер',
  'П’ятниця',
  'Субота',
  'Неділя',
];

/// Translates generated schedule DTOs to / from the domain model.
///
/// Pure translation — no network calls, no state. Call only from the schedule
/// repository implementation.
abstract final class ScheduleMapper {
  // ── Time: HH:mm:ss ⇄ TimeOfDay ──────────────────────────────────────────────

  /// Parses a wire `HH:mm[:ss]` string into a [TimeOfDay], dropping seconds.
  ///
  /// Falls back to midnight on a malformed / null string so a single broken row
  /// can never crash the whole schedule load.
  static TimeOfDay parseTime(String? wire) {
    if (wire == null || wire.isEmpty) {
      return const TimeOfDay(hour: 0, minute: 0);
    }
    final parts = wire.split(':');
    final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  /// Formats a [TimeOfDay] as the wire `HH:mm:00` string (seconds always zero).
  static String formatTimeWire(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:00';

  // ── WorkInterval ⇄ WorkIntervalDto ───────────────────────────────────────────

  static WorkInterval intervalFromDto(WorkIntervalDto dto) => WorkInterval(
    start: parseTime(dto.startTime),
    end: parseTime(dto.endTime),
  );

  static WorkIntervalDto intervalToDto(WorkInterval interval) =>
      WorkIntervalDto(
        (b) => b
          ..startTime = formatTimeWire(interval.start)
          ..endTime = formatTimeWire(interval.end),
      );

  static List<WorkInterval> _intervalsFromDtos(
    BuiltList<WorkIntervalDto>? dtos,
  ) => dtos == null
      ? <WorkInterval>[]
      : dtos.map(intervalFromDto).toList(growable: true);

  static BuiltList<WorkIntervalDto> _intervalsToDtos(
    List<WorkInterval> intervals,
  ) => BuiltList<WorkIntervalDto>(intervals.map(intervalToDto));

  // ── Date ⇄ DateTime (date-only, local midnight) ──────────────────────────────

  static DateTime _dateFromWire(Date? date) => date == null
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : DateTime(date.year, date.month, date.day);

  /// Converts a date-only [DateTime] to the built_value [Date] the client uses
  /// for path / query params (year-month-day only; time-of-day discarded).
  static Date dateToWire(DateTime date) =>
      Date(date.year, date.month, date.day);

  // ── WeeklyScheduleResponse → WeeklySchedule (gap-filled to 7 days) ───────────

  /// Expands a (possibly sparse) [WeeklyScheduleResponse] into a dense,
  /// ordered 7-entry [WeeklySchedule] (Monday(1) … Sunday(7)).
  ///
  /// Any weekday the backend omitted — or any row with a null / out-of-range
  /// `dayOfWeek` — materialises as a day-off (empty intervals). A duplicate
  /// weekday: the last one wins.
  static WeeklySchedule weeklyScheduleFromResponse(
    WeeklyScheduleResponse dto, {
    String? id,
  }) {
    // Seed every ISO day with a day-off (empty intervals).
    final byDay = <int, List<WorkInterval>>{
      for (var day = 1; day <= _kDaysInWeek; day++) day: <WorkInterval>[],
    };

    final days = dto.days;
    if (days != null) {
      for (final dayDto in days) {
        final dow = dayDto.dayOfWeek;
        if (dow == null || dow < 1 || dow > _kDaysInWeek) {
          // Broken contract row — cannot be placed in the week; skip it.
          continue;
        }
        byDay[dow] = _intervalsFromDtos(dayDto.intervals);
      }
    }

    return WeeklySchedule(
      id: id,
      validFrom: _dateFromWire(dto.validFrom),
      validTo: dto.validTo == null ? null : _dateFromWire(dto.validTo),
      days: [
        for (var day = 1; day <= _kDaysInWeek; day++)
          TemplateDay(
            dayOfWeek: day,
            label: _kWeekdayLabels[day - 1],
            intervals: byDay[day]!,
          ),
      ],
    );
  }

  // ── WeeklySchedule → WeeklyScheduleRequest ───────────────────────────────────

  /// Builds the request payload for create / update. Sends one day per weekday;
  /// an empty-intervals [TemplateDay] is a day-off, serialised as an empty
  /// `intervals` list (NOT omitted — the backend treats an explicit empty list
  /// as "this weekday is off"). `validFrom` / `validTo` are date-only.
  static WeeklyScheduleRequest weeklyScheduleToRequest(
    WeeklySchedule schedule,
  ) {
    return WeeklyScheduleRequest(
      (b) => b
        ..validFrom = dateToWire(schedule.validFrom)
        ..validTo = schedule.validTo == null
            ? null
            : dateToWire(schedule.validTo!)
        ..days = ListBuilder<WeeklyScheduleDayRequest>(
          schedule.days.map(
            (d) => WeeklyScheduleDayRequest(
              (db) => db
                ..dayOfWeek = d.dayOfWeek
                ..intervals = _intervalsToDtos(d.intervals).toBuilder(),
            ),
          ),
        ),
    );
  }

  // ── ScheduleOverrideResponse ⇄ ScheduleOverride (1 row = 1 date) ──────────────

  /// Maps one override row to a single-day [ScheduleOverride] (start == end).
  /// Multi-day span grouping is a presentation concern handled above the mapper.
  static ScheduleOverride overrideFromResponse(ScheduleOverrideResponse dto) {
    final date = _dateFromWire(dto.date);
    final isDayOff = dto.kind == ScheduleOverrideResponseKindEnum.DAY_OFF;
    if (isDayOff) {
      return ScheduleOverride.dayOff(
        start: date,
        end: date,
        reason: _reasonFromResponse(dto.reason),
        note: dto.note,
      );
    }
    return ScheduleOverride.custom(
      start: date,
      end: date,
      intervals: _intervalsFromDtos(dto.intervals),
    );
  }

  /// Serialises a single-day override into the PUT body for [date]. The caller
  /// (repository) expands a multi-day [ScheduleOverride] span into one PUT per
  /// date and supplies that date here — the mapper never groups spans.
  static ScheduleOverrideRequest overrideToRequestForDate(
    ScheduleOverride override,
    DateTime date,
  ) {
    final isDayOff = override.kind == OverrideKind.dayOff;
    return ScheduleOverrideRequest((b) {
      b
        ..date = dateToWire(date)
        ..kind = isDayOff
            ? ScheduleOverrideRequestKindEnum.DAY_OFF
            : ScheduleOverrideRequestKindEnum.CUSTOM_HOURS;
      if (isDayOff) {
        b
          ..reason = _reasonToRequest(override.reason)
          ..note = override.note;
      } else {
        b.intervals = _intervalsToDtos(override.intervals).toBuilder();
      }
    });
  }

  // ── EffectiveDayResponse → EffectiveDay ───────────────────────────────────────

  static EffectiveDay effectiveDayFromResponse(EffectiveDayResponse dto) =>
      EffectiveDay(
        date: _dateFromWire(dto.date),
        source: _sourceFromResponse(dto.source_),
        intervals: _intervalsFromDtos(dto.intervals),
        reason: _reasonFromEffective(dto.reason),
      );

  // ── Enum translation (DTO *_Enum ⇄ domain) ────────────────────────────────────

  static EffectiveSource _sourceFromResponse(
    EffectiveDayResponseSource_Enum? src,
  ) {
    if (src == EffectiveDayResponseSource_Enum.TEMPLATE) {
      return EffectiveSource.template;
    }
    if (src == EffectiveDayResponseSource_Enum.OVERRIDE_CUSTOM) {
      return EffectiveSource.overrideCustom;
    }
    if (src == EffectiveDayResponseSource_Enum.OVERRIDE_DAY_OFF) {
      return EffectiveSource.overrideDayOff;
    }
    // NO_SCHEDULE and any unknown future value collapse to noSchedule — the
    // safe "no published hours" reading.
    return EffectiveSource.noSchedule;
  }

  static OverrideReason? _reasonFromResponse(
    ScheduleOverrideResponseReasonEnum? reason,
  ) {
    if (reason == ScheduleOverrideResponseReasonEnum.VACATION) {
      return OverrideReason.vacation;
    }
    if (reason == ScheduleOverrideResponseReasonEnum.HOLIDAY) {
      return OverrideReason.holiday;
    }
    if (reason == ScheduleOverrideResponseReasonEnum.SICK_DAY) {
      return OverrideReason.sickDay;
    }
    if (reason == ScheduleOverrideResponseReasonEnum.OTHER) {
      return OverrideReason.other;
    }
    return null;
  }

  static OverrideReason? _reasonFromEffective(
    EffectiveDayResponseReasonEnum? reason,
  ) {
    if (reason == EffectiveDayResponseReasonEnum.VACATION) {
      return OverrideReason.vacation;
    }
    if (reason == EffectiveDayResponseReasonEnum.HOLIDAY) {
      return OverrideReason.holiday;
    }
    if (reason == EffectiveDayResponseReasonEnum.SICK_DAY) {
      return OverrideReason.sickDay;
    }
    if (reason == EffectiveDayResponseReasonEnum.OTHER) {
      return OverrideReason.other;
    }
    return null;
  }

  static ScheduleOverrideRequestReasonEnum? _reasonToRequest(
    OverrideReason? reason,
  ) {
    switch (reason) {
      case OverrideReason.vacation:
        return ScheduleOverrideRequestReasonEnum.VACATION;
      case OverrideReason.holiday:
        return ScheduleOverrideRequestReasonEnum.HOLIDAY;
      case OverrideReason.sickDay:
        return ScheduleOverrideRequestReasonEnum.SICK_DAY;
      case OverrideReason.other:
        return ScheduleOverrideRequestReasonEnum.OTHER;
      case null:
        return null;
    }
  }
}
