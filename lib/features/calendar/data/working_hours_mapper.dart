// Phase 6.2 — WorkingHoursMapper: data-layer translation between the generated
// weekly-schedule API types and the single-window domain [WorkingHours] model.
//
// This is the single translation boundary between the generated weekly-schedule
// DTOs (`WeeklyScheduleResponse` / `WeeklyScheduleRequest`, lives in
// `package:beautica_api`) and the domain [WorkingHours] entity. Generated DTO
// types must not cross this boundary into the domain or presentation layers.
//
// Domain vs. wire model (the reason this mapper exists rather than a one-liner):
//   - The backend weekly-schedule model is multi-interval per day (a day can
//     carry several work intervals, e.g. a lunch break splits a day into two).
//     The Phase 6.2 editor is single-window, so the domain [WorkingHours]
//     carries exactly ONE interval per day. On READ we keep the FIRST interval
//     per day (first-interval-wins) and drop the rest — acceptable for a
//     single-window editor. On WRITE we emit one interval per active day.
//   - The backend only persists the days a master actually works (an "off" day
//     is an absent / empty `days` entry). The UI editor always needs all 7 ISO
//     days present and ordered Monday(1) … Sunday(7), so
//     [weeklyScheduleToDomainWeek] gap-fills every missing weekday with an
//     inactive ("closed") default window.
//   - The domain keeps an `isActive` flag; the wire model encodes "off" as
//     "no intervals". The flag is translated at this boundary only: on read
//     `isActive = intervals.isNotEmpty`; on write an inactive day is omitted
//     (no `WeeklyScheduleDayRequest` emitted for it).
//
// Null handling: every field on the response DTOs is nullable in the generated
// code. A day row with a null / out-of-range `dayOfWeek` is a broken contract
// and is dropped (it cannot be slotted into the week); a day with no intervals
// (or null start/end on its first interval) falls back to the default window so
// the editor never crashes on a malformed row.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:built_collection/built_collection.dart';

import '../domain/working_hours.dart';

/// Default window applied to a closed / missing day so the editor always opens
/// on a sensible 09:00–18:00 range when the master enables that day.
const String _kDefaultStart = '09:00:00';
const String _kDefaultEnd = '18:00:00';

/// Number of ISO days in a week (1 = Monday … 7 = Sunday).
const int _kDaysInWeek = 7;

/// Converts the generated weekly-schedule DTOs to / from the domain
/// [WorkingHours].
///
/// Pure translation — no network calls, no state. Call only from
/// [HttpWorkingHoursRepository].
abstract final class WorkingHoursMapper {
  /// Expands a (possibly sparse) [WeeklyScheduleResponse] into a dense, ordered
  /// 7-entry list indexed by ISO [WorkingHours.dayOfWeek] (Monday(1) …
  /// Sunday(7)).
  ///
  /// Any weekday the backend omitted — or any day row with a null /
  /// out-of-range `dayOfWeek`, or with no intervals — is materialised as an
  /// inactive default window so the UI always has exactly 7 days to render.
  /// When a day carries multiple intervals (e.g. a lunch break) only the FIRST
  /// is kept (the editor is single-window). When the backend sends a duplicate
  /// weekday, the last one wins (the loop overwrites earlier entries). A null
  /// [schedule] (no schedule exists yet) yields a fully closed default week.
  static List<WorkingHours> weeklyScheduleToDomainWeek(
    WeeklyScheduleResponse? schedule,
  ) {
    // Seed every ISO day with a closed default window.
    final byDay = <int, WorkingHours>{
      for (var day = 1; day <= _kDaysInWeek; day++)
        day: WorkingHours(
          dayOfWeek: day,
          startTime: _kDefaultStart,
          endTime: _kDefaultEnd,
          isActive: false,
        ),
    };

    // Overlay whatever the backend actually returned.
    final days = schedule?.days;
    if (days != null) {
      for (final dayDto in days) {
        final day = dayDto.dayOfWeek;
        if (day == null || day < 1 || day > _kDaysInWeek) {
          // Broken contract row — cannot be placed in the week; skip it.
          continue;
        }
        final intervals = dayDto.intervals;
        if (intervals == null || intervals.isEmpty) {
          // No intervals = day off; the seeded inactive default already holds.
          continue;
        }
        // First-interval-wins: the domain is single-window, so any break-split
        // day flattens to its first interval.
        final first = intervals.first;
        byDay[day] = WorkingHours(
          dayOfWeek: day,
          startTime: first.startTime,
          endTime: first.endTime,
          isActive: true,
        );
      }
    }

    // Return ordered Monday(1) … Sunday(7).
    return [for (var day = 1; day <= _kDaysInWeek; day++) byDay[day]!];
  }

  /// Builds the [WeeklyScheduleRequest] body for a create / update call.
  ///
  /// Only ACTIVE days are emitted; an inactive day is omitted entirely (the
  /// backend encodes "off" as an absent day rather than an empty-interval day).
  /// Each active day maps to one [WeeklyScheduleDayRequest] carrying a single
  /// [WorkIntervalDto] — the single-window editor never produces breaks.
  ///
  /// [validFrom] is supplied by the caller: today (Kyiv) on CREATE, or the
  /// existing schedule's `validFrom` on UPDATE (which must be preserved — the
  /// backend's `@FutureOrPresent` rejects a re-stamped past date). [validTo] is
  /// always left open-ended (`null`).
  ///
  /// Guards the interval ordering: the wire contract requires `endTime`
  /// STRICTLY after `startTime` (cross-midnight forbidden). A violating window
  /// throws a [ValidationFailure] here rather than emitting a 400-bound
  /// interval, so the editor surfaces the same typed failure it would for a
  /// server-side rejection.
  static WeeklyScheduleRequest toWeeklyScheduleRequest(
    Iterable<WorkingHours> hours, {
    required DateTime validFrom,
  }) {
    final dayRequests = <WeeklyScheduleDayRequest>[];
    for (final h in hours) {
      if (!h.isActive) {
        // Inactive day → omit (no day request emitted).
        continue;
      }
      final start = _toWireTime(h.startTime);
      final end = _toWireTime(h.endTime);
      if (!_strictlyBefore(start, end)) {
        throw ValidationFailure(
          fieldErrors: const {},
          serverMessage:
              'End time must be strictly after start time '
              '(day ${h.dayOfWeek}: $start–$end).',
        );
      }
      dayRequests.add(
        WeeklyScheduleDayRequest(
          (b) => b
            ..dayOfWeek = h.dayOfWeek
            ..intervals = ListBuilder<WorkIntervalDto>([
              WorkIntervalDto(
                (i) => i
                  ..startTime = start
                  ..endTime = end,
              ),
            ]),
        ),
      );
    }

    return WeeklyScheduleRequest(
      (b) => b
        ..validFrom = Date(validFrom.year, validFrom.month, validFrom.day)
        ..validTo = null
        ..days = ListBuilder<WeeklyScheduleDayRequest>(dayRequests),
    );
  }

  /// Normalises a domain time string to the `HH:mm:ss` wire format.
  ///
  /// The domain stores `HH:mm:ss` (see [WorkingHours.fromTimeOfDay]) but may
  /// also carry a bare `HH:mm`; this appends `:00` seconds when absent so the
  /// emitted [WorkIntervalDto] always satisfies the wire contract.
  static String _toWireTime(String hhmmss) {
    final parts = hhmmss.split(':');
    final hh = parts[0].padLeft(2, '0');
    final mm = parts.length > 1 ? parts[1].padLeft(2, '0') : '00';
    final ss = parts.length > 2 ? parts[2].padLeft(2, '0') : '00';
    return '$hh:$mm:$ss';
  }

  /// True when [start] is strictly before [end] (both `HH:mm:ss`). Cross-midnight
  /// (`end <= start`) is forbidden by the wire contract.
  static bool _strictlyBefore(String start, String end) =>
      start.compareTo(end) < 0;
}
