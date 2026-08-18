// Phase 6.2 — WorkingHoursRepository: the calendar feature's working-hours
// data layer, backed by the backend weekly-schedule API.
//
// Contract (verified against the generated client 2026-06-10):
//   Read  — getWeeklySchedules(masterId)
//             → GET /api/v1/masters/{masterId}/weekly-schedules
//             → ApiResponseListWeeklyScheduleResponse (a list of schedules).
//           [list] picks the schedule whose [validFrom, validTo] window covers
//           today (Kyiv); if none covers today it falls back to the latest
//           open-ended schedule. The picked schedule is gap-filled to a dense,
//           ordered 7-entry week. (This IS a network read — the old PERF-M1
//           "read from the cached profile, no network call" contract is gone:
//           working hours are no longer bundled on the profile envelope.)
//   Write — there is no single "upsert" call. [replaceAll] first reads the
//           schedules (same selection as [list]); if a covering / latest
//           schedule exists it UPDATEs it in place via
//             updateWeeklySchedule(masterId, scheduleId, body)
//             → PUT /api/v1/masters/{masterId}/weekly-schedules/{scheduleId},
//           preserving that schedule's `validFrom` (the backend's
//           `@FutureOrPresent` rejects a re-stamped past date). If NO schedule
//           exists yet it CREATEs one via
//             createWeeklySchedule(masterId, body)
//             → POST /api/v1/masters/{masterId}/weekly-schedules,
//           stamping `validFrom = today (Kyiv)`, `validTo = null`
//           (open-ended). Both return the saved [WeeklyScheduleResponse], which
//           is mapped back through the gap-filler.
//
// [_masterId] is the Master-row UUID (from MasterDetailResponse.masterId), NOT
// the User UUID from the auth session — they differ (see the services feature's
// long-standing note). It is resolved from [masterProfileProvider] at provider
// construction time (see [workingHoursRepositoryProvider]).
//
// Every method either resolves successfully or throws a typed [Failure] from
// `core/errors/failures.dart`. Raw [DioException]s are caught here and never
// escape. A 400 (server-side time-range / window validation) surfaces as a
// [ValidationFailure] — the [ErrorMapperInterceptor] maps the 400 envelope and
// attaches it to `DioException.error`, which [_mapDioException] re-throws.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../domain/working_hours.dart';
import 'working_hours_mapper.dart';

/// Contract for the master working-hours data layer.
///
/// [replaceAll] is intentionally an atomic "save the whole week" operation
/// rather than a per-day patch — the Phase 6.2 editor commits all seven days in
/// one call so a half-applied state (e.g. Monday saved, Tuesday failed) is
/// impossible.
abstract interface class WorkingHoursRepository {
  /// Returns the authenticated master's week as a dense, ordered 7-entry list
  /// (Monday(1) … Sunday(7)). Missing / closed days are filled by the mapper so
  /// the editor always has all seven days.
  ///
  /// Reads over the network via `getWeeklySchedules`, picking the schedule that
  /// covers today (Kyiv) or, failing that, the latest open-ended schedule.
  Future<List<WorkingHours>> list();

  /// Replaces the entire week with [hours] and returns the saved list (mapped
  /// back through the gap-filler so the result is always 7 ordered entries).
  /// Updates the covering / latest schedule in place when one exists, otherwise
  /// creates a new open-ended schedule. Throws [ValidationFailure] on a backend
  /// 400, or another typed [Failure] on any transport / server error.
  Future<List<WorkingHours>> replaceAll(List<WorkingHours> hours);
}

/// HTTP implementation of [WorkingHoursRepository].
///
/// Inject via `workingHoursRepositoryProvider` — never construct directly.
///
/// [_masterApi] drives both the read (`getWeeklySchedules`) and the write
/// (`createWeeklySchedule` / `updateWeeklySchedule`) through the generated
/// client so built_value handles serialization. [_masterId] is the Master-row
/// UUID resolved at provider construction time.
final class HttpWorkingHoursRepository implements WorkingHoursRepository {
  HttpWorkingHoursRepository({
    required MasterControllerApi masterApi,
    required String masterId,
    // The constructor-level injectable clock seam's own default — mirrors
    // clockProvider's production default; the provider wires clockProvider
    // over this parameter (see working_hours_repository_provider.dart).
    // instant-ok: injectable clock seam default, mirrors clockProvider
    DateTime Function() now = DateTime.now,
  }) : _masterApi = masterApi,
       _masterId = masterId,
       _now = now;

  final MasterControllerApi _masterApi;
  final String _masterId;

  /// Injectable wall-clock seam — defaults to [DateTime.now] in production;
  /// the provider wires [clockProvider] so tests can pin "today".
  final DateTime Function() _now;

  static const _tag = 'feature.calendar.workinghours.repository';

  /// Throws [UnauthorizedFailure] immediately if [_masterId] is empty.
  ///
  /// An empty masterId means [masterProfileProvider] has not resolved an
  /// authenticated master yet. Proceeding would hit
  /// `/api/v1/masters//weekly-schedules` and surface an opaque
  /// [NotFoundFailure]; failing fast surfaces the real cause to callers.
  void _assertAuthenticated() {
    if (_masterId.isEmpty) {
      throw const UnauthorizedFailure();
    }
  }

  @override
  Future<List<WorkingHours>> list() async {
    _assertAuthenticated();
    try {
      final schedules = await _fetchSchedules();
      return WorkingHoursMapper.weeklyScheduleToDomainWeek(
        _pickSchedule(schedules),
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      _logDio('list', e, st);
      throw _mapDioException(e);
    }
  }

  @override
  Future<List<WorkingHours>> replaceAll(List<WorkingHours> hours) async {
    _assertAuthenticated();
    try {
      final existing = _pickSchedule(await _fetchSchedules());
      final WeeklyScheduleResponse? saved;
      if (existing != null && existing.id != null && existing.id!.isNotEmpty) {
        // UPDATE in place — preserve the existing schedule's validFrom (the
        // backend's @FutureOrPresent rejects a re-stamped past date). Fall back
        // to today only if the existing window somehow has no validFrom.
        final validFrom = existing.validFrom?.toDateTime() ?? _todayKyiv();
        final res = await _masterApi.updateWeeklySchedule(
          masterId: _masterId,
          scheduleId: existing.id!,
          weeklyScheduleRequest: WorkingHoursMapper.toWeeklyScheduleRequest(
            hours,
            validFrom: validFrom,
          ),
        );
        saved = res.data?.data;
      } else {
        // CREATE — no schedule exists yet. Stamp validFrom = today (Kyiv),
        // validTo = null (open-ended).
        final res = await _masterApi.createWeeklySchedule(
          masterId: _masterId,
          weeklyScheduleRequest: WorkingHoursMapper.toWeeklyScheduleRequest(
            hours,
            validFrom: _todayKyiv(),
          ),
        );
        saved = res.data?.data;
      }
      // The backend returns the saved schedule; re-run it through the gap-filler
      // so callers always receive a dense, ordered 7-entry week.
      return WorkingHoursMapper.weeklyScheduleToDomainWeek(saved);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      _logDio('replaceAll', e, st);
      throw _mapDioException(e);
    }
  }

  /// Fetches the master's weekly schedules, returning an empty iterable when the
  /// envelope carries none.
  ///
  /// Returns the built_value [BuiltList] (an [Iterable]) directly — [_pickSchedule]
  /// walks it once, so there is no need to copy it into a growable [List].
  Future<Iterable<WeeklyScheduleResponse>> _fetchSchedules() async {
    final res = await _masterApi.getWeeklySchedules(masterId: _masterId);
    return res.data?.data ?? const <WeeklyScheduleResponse>[];
  }

  /// Picks the schedule that governs "today", deterministically.
  ///
  /// Selection (the backend forbids overlapping windows, so at most one
  /// schedule can cover today):
  ///   1. The schedule whose [validFrom, validTo] window covers today (Kyiv) —
  ///      `validFrom <= today` AND (`validTo == null` OR `today <= validTo`).
  ///   2. Otherwise the latest OPEN-ENDED schedule (`validTo == null`, max
  ///      `validFrom`) — the one that will become active.
  ///   3. Otherwise the schedule with the latest `validFrom` (best effort).
  ///   4. `null` when there are no schedules at all (the create path).
  ///
  /// Shared by [list] and [replaceAll] so read and write always agree on which
  /// schedule is "the" schedule.
  WeeklyScheduleResponse? _pickSchedule(
    Iterable<WeeklyScheduleResponse> schedules,
  ) {
    final today = _todayKyiv();

    WeeklyScheduleResponse? covering;
    WeeklyScheduleResponse? latestOpenEnded;
    WeeklyScheduleResponse? latestAny;

    for (final s in schedules) {
      final from = s.validFrom?.toDateTime();
      final to = s.validTo?.toDateTime();

      final coversToday =
          from != null &&
          !today.isBefore(from) &&
          (to == null || !today.isAfter(to));
      if (coversToday) {
        // Deterministic even if (contract-violating) duplicates exist: keep the
        // one with the later validFrom.
        if (covering == null || _validFromAfter(s, covering)) {
          covering = s;
        }
      }

      if (to == null) {
        if (latestOpenEnded == null || _validFromAfter(s, latestOpenEnded)) {
          latestOpenEnded = s;
        }
      }

      if (latestAny == null || _validFromAfter(s, latestAny)) {
        latestAny = s;
      }
    }

    return covering ?? latestOpenEnded ?? latestAny;
  }

  /// True when [a]'s `validFrom` is strictly after [b]'s (nulls sort earliest),
  /// used to break ties deterministically in [_pickSchedule].
  bool _validFromAfter(WeeklyScheduleResponse a, WeeklyScheduleResponse b) {
    final fa = a.validFrom;
    final fb = b.validFrom;
    if (fa == null) return false;
    if (fb == null) return true;
    return fa.compareTo(fb) > 0;
  }

  /// "Today" as a Kyiv-anchored date token (see `shared/time/kyiv_day.dart`),
  /// so the window comparison in [_pickSchedule] agrees with the backend's
  /// own `atStartOfDay(TimeZones.KYIV)` day boundary regardless of the
  /// device's own zone.
  DateTime _todayKyiv() => kyivDayOf(_now());

  void _logDio(String op, DioException e, StackTrace st) {
    if (kDebugMode) {
      log(
        '$op failed: ${e.type} ${e.response?.statusCode}',
        name: _tag,
        level: 900,
        stackTrace: st,
      );
    }
  }

  /// Maps a [DioException] to a typed [Failure].
  ///
  /// If [ErrorMapperInterceptor] has already attached a [Failure] as `e.error`
  /// (e.g. a 400 → [ValidationFailure], a 401 → [UnauthorizedFailure]), that
  /// value is re-thrown directly; otherwise the Dio type is inspected so
  /// connectivity issues surface as [NetworkFailure] and everything else as
  /// [ServerFailure]. Raw [DioException] never escapes.
  Failure _mapDioException(DioException e) {
    if (e.error is Failure) return e.error as Failure;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(cause: e);
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return ServerFailure(statusCode: e.response?.statusCode, cause: e);
    }
  }
}
