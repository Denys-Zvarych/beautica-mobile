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
// WINDOW+BREAKS NOTE: BREAK ranges are NOT part of the wire layer — this mapper
// never sees a `BreakRange`, and the editor (Phase 15.3) alone does the
// `DayHours.fromIntervals`/`toIntervals` split. Do not move break logic here.
//
// The working WINDOW is different, and IS carried across this boundary (added
// 2026-07-27): the backend persists `windowStart`/`windowEnd` on
// `WeeklyScheduleDay{Request,Response}`, `ScheduleOverride{Request,Response}`
// and (response-only) `EffectiveDayResponse` as DISPLAY-ONLY metadata —
// intervals remain the sole canonical availability and no backend availability
// path reads the window. It is a stored field, so mapping it is translation, not
// reconstructed break logic. Contract this mapper honours:
//   • Both-or-neither. Never send one edge alone; never synthesise a window from
//     `min(start)..max(end)` — an absent window is a real, meaningful `null`
//     (the legacy gap-reconstruction regime in `DayHours.fromIntervals`).
//     DELIBERATE EXCEPTION, do not "fix": `DayHoursSheet._save`
//     (`presentation/day_hours_sheet.dart`) always sends `window:
//     _day.window.clone()` on a CUSTOM_HOURS save, INCLUDING when the sheet was
//     seeded from a legacy row with no stored window. That is not synthesis at
//     the mapping boundary — it is the master's actual edited від–до, and it is
//     what lets a legacy override row heal itself on first re-save. The
//     no-synthesis rule above binds THIS file (the read path), not the editor.
//   • `windowEnd > windowStart`, and the window CONTAINS every interval, else
//     the backend 400s. `DayHours.toIntervals()` guarantees containment by
//     construction, so a valid editor state always satisfies it. On the READ
//     path the same containment is re-checked rather than assumed — see
//     [ScheduleMapper._windowFromWire].
//   • Ignored by the backend for day-off and EXPLICIT_TIMES days — this mapper
//     sends `null` there rather than relying on that leniency.

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

  // ── Discrete times: BuiltList<String> ⇄ List<TimeOfDay> (Phase 15.7) ─────────

  /// Reads the wire `times` list (`HH:mm[:ss]` strings) into a sorted, de-duped
  /// [TimeOfDay] list. A null / absent wire list → an empty list. Defensive
  /// sort+dedupe matches the EXPLICIT_TIMES contract (the backend may not
  /// guarantee order, and a duplicate slot start is meaningless).
  static List<TimeOfDay> _timesFromWire(BuiltList<String>? wire) =>
      wire == null || wire.isEmpty
      ? <TimeOfDay>[]
      : sortDedupeTimes(wire.map(parseTime));

  /// Serialises a discrete [TimeOfDay] list to the wire `HH:mm:00` string list,
  /// sorted + de-duped so the request is canonical.
  static BuiltList<String> _timesToWire(List<TimeOfDay> times) =>
      BuiltList<String>(sortDedupeTimes(times).map(formatTimeWire));

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

  // ── Working window: windowStart/windowEnd ⇄ WorkInterval? ────────────────────

  /// Reads the stored display-only working window off a wire pair, validated
  /// against the [intervals] of the SAME row.
  ///
  /// BOTH-OR-NEITHER: a `null`/empty edge on either side — or a degenerate pair
  /// where the end is not strictly after the start — yields `null`, i.e. "this
  /// row has no stored window", which routes the reader to the legacy
  /// gap-reconstruction regime. The window is NEVER synthesised from the
  /// intervals; a missing window must stay missing.
  ///
  /// CONTAINMENT (2026-07-27 audit): the window is additionally rejected unless
  /// it contains EVERY interval of the row. The backend enforces containment on
  /// the write side, but the client must not *rely* on that guarantee — a
  /// backend regression or tampered row could otherwise ship e.g.
  /// `intervals=[08:00–18:00]` with `window=09:00–10:00`, and
  /// `DayHours._breaksFromWindowMinusIntervals` CLAMPS intervals into the
  /// window rather than rejecting them. That silently renders a 09:00–10:00 day
  /// with no warning, and the next save collapses `toIntervals()` to
  /// `[09:00–10:00]` — writing away 8 hours of genuinely bookable time, with the
  /// backend blessing the (now self-consistent) result. Falling back to `null`
  /// keeps the intervals authoritative: the legacy regime derives the window
  /// from them instead.
  ///
  /// An empty [intervals] list satisfies containment vacuously. Such a row is a
  /// day-off, where every reader ignores the window anyway
  /// ([DayHours.fromIntervals] returns a default day, and
  /// [weeklyScheduleToRequest] suppresses the window on the way back out).
  static WorkInterval? _windowFromWire(
    String? start,
    String? end,
    List<WorkInterval> intervals,
  ) {
    if (start == null || start.isEmpty || end == null || end.isEmpty) {
      return null;
    }
    final WorkInterval window = WorkInterval(
      start: parseTime(start),
      end: parseTime(end),
    );
    if (!window.selfValid) return null;
    for (final WorkInterval interval in intervals) {
      if (interval.startMinutes < window.startMinutes ||
          interval.endMinutes > window.endMinutes) {
        return null;
      }
    }
    return window;
  }

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
  ///
  /// The template id comes from the wire (`dto.id`) so reloaded list templates
  /// are self-identifying — that non-null id is what lets the editor's second
  /// save target a PUT (update in place) instead of POSTing a duplicate window.
  /// [id] is an optional override for the create/update re-attach path, where
  /// the caller already knows the targeted id; it falls back to `dto.id`.
  static WeeklySchedule weeklyScheduleFromResponse(
    WeeklyScheduleResponse dto, {
    String? id,
  }) {
    // Seed every ISO day with a day-off (INTERVAL mode, empty intervals).
    final byDay = <int, _DayShape>{
      for (var day = 1; day <= _kDaysInWeek; day++) day: const _DayShape.off(),
    };

    final days = dto.days;
    if (days != null) {
      for (final dayDto in days) {
        final dow = dayDto.dayOfWeek;
        if (dow == null || dow < 1 || dow > _kDaysInWeek) {
          // Broken contract row — cannot be placed in the week; skip it.
          continue;
        }
        if (_weeklyModeIsExplicit(dayDto.mode)) {
          byDay[dow] = _DayShape.explicit(_timesFromWire(dayDto.times));
        } else {
          final List<WorkInterval> intervals = _intervalsFromDtos(
            dayDto.intervals,
          );
          byDay[dow] = _DayShape.interval(
            intervals,
            _windowFromWire(dayDto.windowStart, dayDto.windowEnd, intervals),
          );
        }
      }
    }

    return WeeklySchedule(
      id: id ?? dto.id,
      validFrom: _dateFromWire(dto.validFrom),
      validTo: dto.validTo == null ? null : _dateFromWire(dto.validTo),
      days: [
        for (var day = 1; day <= _kDaysInWeek; day++)
          TemplateDay(
            dayOfWeek: day,
            label: _kWeekdayLabels[day - 1],
            mode: byDay[day]!.mode,
            intervals: byDay[day]!.intervals,
            times: byDay[day]!.times,
            window: byDay[day]!.window,
          ),
      ],
    );
  }

  // ── WeeklySchedule → WeeklyScheduleRequest ───────────────────────────────────

  /// Builds the request payload for create / update. Sends one day per weekday.
  ///
  /// Contract (Phase 15.8, backend `WeeklyScheduleDayRequest.isModeConsistent`):
  ///   • EXPLICIT_TIMES days MUST carry ≥1 discrete time and no intervals.
  ///   • A day-off is the canonical INTERVAL day with an empty `intervals` list
  ///     (NOT omitted — the backend treats an explicit empty list as "off").
  /// An `explicitTimes` [TemplateDay] with zero times is therefore NOT a valid
  /// EXPLICIT_TIMES day (it would 400 on `days[i].modeConsistent`); it is an
  /// empty discrete day == day-off, so we serialise it as INTERVAL-empty.
  /// `validFrom` / `validTo` are date-only.
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
            (d) => WeeklyScheduleDayRequest((db) {
              db.dayOfWeek = d.dayOfWeek;
              if (d.mode == WeekdayMode.explicitTimes && d.times.isNotEmpty) {
                // EXPLICIT_TIMES: a real discrete working day — send the (≥1)
                // discrete times, no intervals.
                db
                  ..mode = WeeklyScheduleDayRequestModeEnum.EXPLICIT_TIMES
                  ..times = _timesToWire(d.times).toBuilder();
              } else {
                // INTERVAL (default) — also the day-off / empty-discrete-day
                // encoding: send intervals (an empty list == this weekday off).
                db
                  ..mode = WeeklyScheduleDayRequestModeEnum.INTERVAL
                  ..intervals = _intervalsToDtos(d.intervals).toBuilder();
                // Display-only working window, both-or-neither. Suppressed for a
                // day-off (empty intervals): the backend ignores it there, and a
                // window with nothing to contain is meaningless.
                final WorkInterval? window = d.window;
                if (window != null && d.intervals.isNotEmpty) {
                  db
                    ..windowStart = formatTimeWire(window.start)
                    ..windowEnd = formatTimeWire(window.end);
                }
              }
            }),
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
      return ScheduleOverride.dayOff(start: date, end: date);
    }
    // CUSTOM_HOURS — either continuous intervals or discrete times.
    if (_overrideModeIsExplicit(dto.mode)) {
      return ScheduleOverride.explicitTimes(
        start: date,
        end: date,
        times: _timesFromWire(dto.times),
      );
    }
    final List<WorkInterval> intervals = _intervalsFromDtos(dto.intervals);
    return ScheduleOverride.custom(
      start: date,
      end: date,
      intervals: intervals,
      window: _windowFromWire(dto.windowStart, dto.windowEnd, intervals),
    );
  }

  /// Resolves the discrete DAY_OFF/CUSTOM_HOURS(INTERVAL|EXPLICIT_TIMES) shape
  /// an [override] serialises to on the wire, shared by
  /// [overrideToRequestForDate] and [conflictQueryRequestForSpan] so the two
  /// request builders can never disagree about what counts as a day-off.
  ///
  /// Contract (Phase 15.9, backend `ScheduleOverrideRequest.isKindConsistent`
  /// — the conflict-preview `OverrideConflictQueryRequest` mirrors the same
  /// rule):
  ///   • DAY_OFF carries neither intervals nor times.
  ///   • CUSTOM_HOURS carries EITHER a non-empty intervals list (INTERVAL) OR
  ///     a non-empty times list (EXPLICIT_TIMES), never both, never empty.
  /// A CUSTOM_HOURS override that resolves to zero working slots (empty times
  /// in EXPLICIT_TIMES mode, or empty intervals in INTERVAL mode) is NOT a
  /// valid CUSTOM_HOURS payload — it would 400 on `kindConsistent`. Such an
  /// override means "no hours that date", which is the DAY_OFF encoding, so it
  /// collapses to DAY_OFF here too.
  static _OverrideWireShape _wireShapeOf(ScheduleOverride override) {
    final isExplicit = override.mode == WeekdayMode.explicitTimes;
    final hasWork = isExplicit
        ? override.times.isNotEmpty
        : override.intervals.isNotEmpty;
    final isDayOff = override.kind == OverrideKind.dayOff || !hasWork;
    return _OverrideWireShape(isDayOff: isDayOff, isExplicit: isExplicit);
  }

  /// Serialises a single-day override into the PUT body for [date]. The caller
  /// (repository) expands a multi-day [ScheduleOverride] span into one PUT per
  /// date and supplies that date here — the mapper never groups spans.
  ///
  /// [cancelOverlapping] forwards the 2026-07-26 booking-conflict design's
  /// consent flag: `false` (default) preserves the pre-existing behaviour
  /// (409 if the write would orphan a CONFIRMED booking); `true` — sent only
  /// after the master confirms [DayOffConflictDialog] — asks the backend to
  /// also decline every conflicting booking atomically with the write.
  static ScheduleOverrideRequest overrideToRequestForDate(
    ScheduleOverride override,
    DateTime date, {
    bool cancelOverlapping = false,
  }) {
    final shape = _wireShapeOf(override);
    return ScheduleOverrideRequest((b) {
      b
        ..date = dateToWire(date)
        ..cancelOverlapping = cancelOverlapping
        ..kind = shape.isDayOff
            ? ScheduleOverrideRequestKindEnum.DAY_OFF
            : ScheduleOverrideRequestKindEnum.CUSTOM_HOURS;
      // DAY_OFF carries only its kind (no intervals/times, no reason/note — the
      // backend dropped those fields). CUSTOM_HOURS carries either the discrete
      // times (EXPLICIT_TIMES) or the intervals (INTERVAL), never both.
      if (shape.isDayOff) return;
      if (shape.isExplicit) {
        b
          ..mode = ScheduleOverrideRequestModeEnum.EXPLICIT_TIMES
          ..times = _timesToWire(override.times).toBuilder();
      } else {
        b
          ..mode = ScheduleOverrideRequestModeEnum.INTERVAL
          ..intervals = _intervalsToDtos(override.intervals).toBuilder();
        // Display-only working window, both-or-neither. Only reachable on the
        // CUSTOM_HOURS INTERVAL branch — [_wireShapeOf] has already collapsed an
        // empty-intervals override to DAY_OFF above, which returns before here.
        final WorkInterval? window = override.window;
        if (window != null) {
          b
            ..windowStart = formatTimeWire(window.start)
            ..windowEnd = formatTimeWire(window.end);
        }
      }
    });
  }

  // ── Booking-conflict preview (2026-07-26 design) ─────────────────────────────

  /// Builds the `POST /overrides/conflicts` body for the WHOLE `[span.start,
  /// span.end]` range in ONE request — never expanded per-date, unlike the PUT
  /// fan-out [overrideToRequestForDate] feeds. The shape (kind/mode/intervals/
  /// times) is held constant across the range, mirroring how
  /// `OverridesNotifier.putSpan` applies one override to every date it expands.
  static OverrideConflictQueryRequest conflictQueryRequestForSpan(
    ScheduleOverride span,
  ) {
    final shape = _wireShapeOf(span);
    return OverrideConflictQueryRequest((b) {
      b
        ..from = dateToWire(span.start)
        ..to = dateToWire(span.end)
        ..kind = shape.isDayOff
            ? OverrideConflictQueryRequestKindEnum.DAY_OFF
            : OverrideConflictQueryRequestKindEnum.CUSTOM_HOURS;
      if (shape.isDayOff) return;
      if (shape.isExplicit) {
        b
          ..mode = OverrideConflictQueryRequestModeEnum.EXPLICIT_TIMES
          ..times = _timesToWire(span.times).toBuilder();
      } else {
        b
          ..mode = OverrideConflictQueryRequestModeEnum.INTERVAL
          ..intervals = _intervalsToDtos(span.intervals).toBuilder();
      }
    });
  }

  /// Maps one `OverrideConflictResponse` row to the domain [OverrideConflict].
  /// Every wire field is nullable (generic `built_value` codegen) even though
  /// the backend always populates them for a real row; defensive fallbacks
  /// (epoch / empty string) keep one malformed row from crashing the whole
  /// preview instead of just rendering blank.
  ///
  /// [OverrideConflict.startsAt] / `.endsAt` are kept as the CANONICAL UTC
  /// instant the generated client deserialises — never `.toLocal()` (the
  /// device-zone convention this app deliberately dropped; see
  /// `shared/time/time_zones.dart`'s header). The presentation layer converts
  /// via `toBeauticaTime` at render time, exactly like every other booking
  /// instant in the app.
  static OverrideConflict overrideConflictFromResponse(
    OverrideConflictResponse dto,
  ) => OverrideConflict(
    bookingId: dto.bookingId ?? '',
    appointmentId: dto.appointmentId,
    date: _dateFromWire(dto.date),
    startsAt: dto.startsAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    endsAt: dto.endsAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    clientDisplayName: dto.clientDisplayName ?? '',
    serviceName: dto.serviceName ?? '',
  );

  /// Maps the full `OverrideConflictPreviewResponse` envelope to the domain
  /// [OverrideConflictCheck].
  static OverrideConflictCheck overrideConflictCheckFromResponse(
    OverrideConflictPreviewResponse dto,
  ) {
    final conflicts = (dto.conflicts ?? const <OverrideConflictResponse>[])
        .map(overrideConflictFromResponse)
        .toList(growable: false);
    return OverrideConflictCheck(
      conflicts: conflicts,
      totalCount: dto.totalCount ?? conflicts.length,
      truncated: dto.truncated ?? false,
      scanTruncated: dto.scanTruncated ?? false,
    );
  }

  // ── EffectiveDayResponse → EffectiveDay ───────────────────────────────────────

  static EffectiveDay effectiveDayFromResponse(EffectiveDayResponse dto) {
    final List<WorkInterval> intervals = _intervalsFromDtos(dto.intervals);
    return EffectiveDay(
      date: _dateFromWire(dto.date),
      source: _sourceFromResponse(dto.source_),
      intervals: intervals,
      // EffectiveDayResponse carries no `mode`; a non-empty `times` list is
      // itself the EXPLICIT_TIMES signal (see [EffectiveDay.isExplicitTimes]).
      times: _timesFromWire(dto.times),
      // Display-only window the backend projects from whichever source resolved
      // the day (TEMPLATE / OVERRIDE_CUSTOM). Null for a day-off, a no-schedule
      // day, an EXPLICIT_TIMES day, any row saved without a stored window, and
      // any row whose window does not contain its own intervals.
      window: _windowFromWire(dto.windowStart, dto.windowEnd, intervals),
    );
  }

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

  /// True when a weekly-day wire `mode` is EXPLICIT_TIMES. A null / unknown mode
  /// falls back to INTERVAL — the legacy shape, safe for any pre-15.7 row.
  static bool _weeklyModeIsExplicit(WeeklyScheduleDayResponseModeEnum? mode) =>
      mode == WeeklyScheduleDayResponseModeEnum.EXPLICIT_TIMES;

  /// True when an override wire `mode` is EXPLICIT_TIMES. Null / unknown →
  /// INTERVAL (legacy custom-hours shape).
  static bool _overrideModeIsExplicit(ScheduleOverrideResponseModeEnum? mode) =>
      mode == ScheduleOverrideResponseModeEnum.EXPLICIT_TIMES;
}

/// Internal carrier for [ScheduleMapper._wireShapeOf]'s resolved DAY_OFF vs.
/// CUSTOM_HOURS(INTERVAL|EXPLICIT_TIMES) verdict, shared by the PUT and
/// conflict-preview request builders.
class _OverrideWireShape {
  const _OverrideWireShape({required this.isDayOff, required this.isExplicit});

  final bool isDayOff;
  final bool isExplicit;
}

/// Internal carrier for a resolved weekly-day shape during gap-fill so the
/// dense 7-entry build can read mode + the applicable list uniformly.
class _DayShape {
  const _DayShape.off()
    : mode = WeekdayMode.interval,
      intervals = const <WorkInterval>[],
      times = const <TimeOfDay>[],
      window = null;

  const _DayShape.interval(this.intervals, this.window)
    : mode = WeekdayMode.interval,
      times = const <TimeOfDay>[];

  const _DayShape.explicit(this.times)
    : mode = WeekdayMode.explicitTimes,
      intervals = const <WorkInterval>[],
      window = null;

  final WeekdayMode mode;
  final List<WorkInterval> intervals;
  final List<TimeOfDay> times;

  /// The stored display-only working window; `null` for a day-off, an
  /// EXPLICIT_TIMES day, and any legacy row the backend saved without one.
  final WorkInterval? window;
}
