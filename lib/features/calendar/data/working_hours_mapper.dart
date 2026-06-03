// Phase 6.1 — WorkingHoursMapper: data-layer translation between the generated
// API types and the domain [WorkingHours] model.
//
// This is the single translation boundary between the generated
// `WorkingHoursResponse` / `WorkingHoursRequest` (lives in `package:beautica_api`)
// and the domain [WorkingHours] entity. Generated DTO types must not cross this
// boundary into the domain or presentation layers.
//
// Gap-filling contract (the reason this mapper exists rather than a one-liner):
//   The backend only persists the days a master actually works, so the read
//   path may return fewer than 7 entries (often only the active ones). The UI
//   editor (Phase 6.2) and the calendar (Phase 6.3/6.4) always need all 7 ISO
//   days present and ordered Monday(1) … Sunday(7). [toDomainWeek] therefore
//   expands whatever the server returns into a dense 7-entry list, inserting a
//   default inactive ("closed") window for every missing day.
//
// Null handling: every field on `WorkingHoursResponse` is nullable in the
// generated code. A row with a null/out-of-range [dayOfWeek] is a broken
// contract and is dropped (it cannot be slotted into the week); null times fall
// back to the default window so the editor never crashes on a malformed row.

import 'package:beautica_api/beautica_api.dart';
import 'package:built_collection/built_collection.dart';

import '../domain/working_hours.dart';

/// Default window applied to a closed / missing day so the editor always opens
/// on a sensible 09:00–18:00 range when the master enables that day.
const String _kDefaultStart = '09:00:00';
const String _kDefaultEnd = '18:00:00';

/// Number of ISO days in a week (1 = Monday … 7 = Sunday).
const int _kDaysInWeek = 7;

/// Converts generated working-hours DTOs to / from the domain [WorkingHours].
///
/// Pure translation — no network calls, no state. Call only from
/// [HttpWorkingHoursRepository].
abstract final class WorkingHoursMapper {
  /// Expands a (possibly sparse) list of [WorkingHoursResponse] into a dense,
  /// ordered 7-entry list indexed by ISO [WorkingHours.dayOfWeek] (Monday(1) …
  /// Sunday(7)).
  ///
  /// Any day the backend omitted — or any malformed row with a null /
  /// out-of-range `dayOfWeek` — is materialised as an inactive default window
  /// so the UI always has exactly 7 days to render. When the backend sends a
  /// duplicate day, the last one wins (the loop overwrites earlier entries).
  static List<WorkingHours> toDomainWeek(Iterable<WorkingHoursResponse>? dtos) {
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
    if (dtos != null) {
      for (final dto in dtos) {
        final day = dto.dayOfWeek;
        if (day == null || day < 1 || day > _kDaysInWeek) {
          // Broken contract row — cannot be placed in the week; skip it.
          continue;
        }
        byDay[day] = WorkingHours(
          dayOfWeek: day,
          startTime: dto.startTime ?? _kDefaultStart,
          endTime: dto.endTime ?? _kDefaultEnd,
          isActive: dto.isActive ?? false,
        );
      }
    }

    // Return ordered Monday(1) … Sunday(7).
    return [for (var day = 1; day <= _kDaysInWeek; day++) byDay[day]!];
  }

  /// Builds the request payload for `upsertWorkingHours`.
  ///
  /// The backend caps the list at 7 (`@Size(max = 7)`) and the editor saves the
  /// whole week atomically, so the full ordered week is sent every time. Each
  /// domain entry maps 1:1 to a [WorkingHoursRequest]; `timeRangeValid` is left
  /// unset (the backend derives / validates it server-side).
  static BuiltList<WorkingHoursRequest> toRequestList(
    Iterable<WorkingHours> hours,
  ) {
    return BuiltList<WorkingHoursRequest>(
      hours.map(
        (h) => WorkingHoursRequest(
          (b) => b
            ..dayOfWeek = h.dayOfWeek
            ..startTime = h.startTime
            ..endTime = h.endTime
            ..isActive = h.isActive,
        ),
      ),
    );
  }
}
