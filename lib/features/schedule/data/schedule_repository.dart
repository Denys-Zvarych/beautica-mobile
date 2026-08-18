// Phase 15.1 — ScheduleRepository: the schedule feature's data layer over the
// regenerated MasterControllerApi.
//
// Endpoints (verified against the regenerated client 2026-06-05):
//   GET    /api/v1/masters/{id}/weekly-schedules            → getWeeklySchedules
//   POST   /api/v1/masters/{id}/weekly-schedules            → createWeeklySchedule
//   PUT    /api/v1/masters/{id}/weekly-schedules/{schedId}  → updateWeeklySchedule
//   DELETE /api/v1/masters/{id}/weekly-schedules/{schedId}  → deleteWeeklySchedule
//   GET    /api/v1/masters/{id}/overrides?from&to           → getOverrides
//   PUT    /api/v1/masters/{id}/overrides/{date}            → upsertOverride
//   DELETE /api/v1/masters/{id}/overrides/{date}            → clearOverride
//   GET    /api/v1/masters/{id}/effective-schedule?from&to  → getEffectiveSchedule
//
// [_masterId] is the Master-row UUID (from MasterDetailResponse.masterId), NOT
// the User UUID from the auth session — they differ (see the working-hours and
// services features' long-standing note). Resolved from [masterProfileProvider]
// at provider construction time. Empty id → [UnauthorizedFailure], no API call.
//
// BOUNDED-RANGE GUARD: the backend caps effective-schedule / overrides range
// queries (range too large / past windows → 400). [effectiveSchedule] and
// [listOverrides] mirror that guard CLIENT-SIDE with an assert + a thrown
// [ValidationFailure] BEFORE any network call, so an unbounded or >366-day
// window never leaves the device. A backend 400 (e.g. a past-window rule the
// client doesn't replicate) still surfaces as [ValidationFailure] via the
// interceptor.
//
// Every method either resolves successfully or throws a typed [Failure]. Raw
// [DioException]s are caught here and never escape.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../domain/schedule_model.dart';
import '../domain/weekly_schedule.dart';
import 'schedule_mapper.dart';

/// The inclusive maximum span (in days) a single effective-schedule / overrides
/// range query may cover. Mirrors the backend guard. A calendar never needs
/// more than a year in one paint; anything larger is a caller bug.
const int kMaxScheduleRangeDays = 366;

/// Contract for the master-schedule data layer.
///
/// [upsertWeeklySchedule] is create-or-update: pass [scheduleId] to PUT an
/// existing template, omit it to POST a new one. [effectiveSchedule] is the
/// calendar's per-day data source; [listOverrides] feeds the time-off list.
/// Both range queries MUST receive a bounded window (≤ [kMaxScheduleRangeDays]).
abstract interface class ScheduleRepository {
  /// Returns every persisted weekly template for the master (each gap-filled to
  /// a dense 7-entry ISO week).
  Future<List<WeeklySchedule>> listWeeklySchedules();

  /// Creates ([scheduleId] == null) or updates the weekly template and returns
  /// the server-confirmed result (gap-filled to 7 days).
  Future<WeeklySchedule> upsertWeeklySchedule(
    WeeklySchedule schedule, {
    String? scheduleId,
  });

  /// Deletes the weekly template identified by [scheduleId].
  Future<void> deleteWeeklySchedule(String scheduleId);

  /// Lists the per-date overrides in `[from, to]` (inclusive). One returned
  /// [ScheduleOverride] per calendar date (no span grouping — that is a
  /// presentation concern). Range MUST be bounded (≤ [kMaxScheduleRangeDays]).
  Future<List<ScheduleOverride>> listOverrides(DateTime from, DateTime to);

  /// Upserts a single-date override (PUT /overrides/{date}). The override's
  /// [ScheduleOverride.start] is used as the target date; a multi-day span must
  /// be expanded to one call per date by the caller.
  ///
  /// [cancelOverlapping] is the 2026-07-26 booking-conflict design's write-time
  /// consent flag (default `false`, preserving the pre-existing "always
  /// allowed" behaviour when there are no conflicts):
  ///   • conflicts + `false` → the server rejects with 409, nothing written.
  ///   • conflicts + `true`  → the override is written AND every conflicting
  ///     CONFIRMED booking is declined, atomically.
  /// Callers should call [previewConflicts] FIRST and only pass `true` after
  /// the master confirms [DayOffConflictDialog] (or the ported equivalent) —
  /// never pass `true` unconditionally, or a conflict the master never saw
  /// would be silently cancelled.
  Future<ScheduleOverride> putOverride(
    ScheduleOverride override, {
    bool cancelOverlapping = false,
  });

  /// Clears (deletes) the override on [date], reverting it to the template.
  Future<void> clearOverride(DateTime date);

  /// Read-only preview (`POST /overrides/conflicts`) of every CONFIRMED
  /// booking that applying [span] (constant kind/mode/intervals/times across
  /// `[span.start, span.end]`) would leave without availability — ONE request
  /// for the whole range, never one per expanded date. No writes, no side
  /// effects. Range MUST be bounded (≤ [kMaxScheduleRangeDays]).
  Future<OverrideConflictCheck> previewConflicts(ScheduleOverride span);

  /// Resolves the effective schedule for each date in `[from, to]` (inclusive)
  /// — the calendar's data source. Range MUST be bounded
  /// (≤ [kMaxScheduleRangeDays]).
  Future<List<EffectiveDay>> effectiveSchedule(DateTime from, DateTime to);
}

/// HTTP implementation of [ScheduleRepository].
///
/// Inject via `scheduleRepositoryProvider` — never construct directly outside
/// that provider and its tests.
final class HttpScheduleRepository implements ScheduleRepository {
  HttpScheduleRepository({
    required MasterControllerApi masterApi,
    required String masterId,
  }) : _masterApi = masterApi,
       _masterId = masterId;

  final MasterControllerApi _masterApi;
  final String _masterId;

  static const _tag = 'feature.schedule.repository';

  /// Throws [UnauthorizedFailure] immediately if [_masterId] is empty — an
  /// unresolved master means [masterProfileProvider] has not produced an
  /// authenticated master yet. Failing fast avoids a malformed
  /// `/api/v1/masters//…` URL surfacing as an opaque [NotFoundFailure].
  void _assertAuthenticated() {
    if (_masterId.isEmpty) {
      throw const UnauthorizedFailure();
    }
  }

  /// Asserts (debug) and enforces (release) a bounded, ordered range before any
  /// network call. An open / inverted / >366-day window is a caller bug — it
  /// throws a [ValidationFailure] so the same typed error path a backend 400
  /// would produce is used in both cases.
  void _assertBoundedRange(DateTime from, DateTime to) {
    final spanDays = to.difference(from).inDays;
    assert(
      !to.isBefore(from) && spanDays <= kMaxScheduleRangeDays,
      'Schedule range must be ordered and ≤ $kMaxScheduleRangeDays days '
      '(got from=$from to=$to, span=$spanDays days).',
    );
    if (to.isBefore(from) || spanDays > kMaxScheduleRangeDays) {
      throw const ValidationFailure(fieldErrors: <String, String>{});
    }
  }

  @override
  Future<List<WeeklySchedule>> listWeeklySchedules() async {
    _assertAuthenticated();
    try {
      final res = await _masterApi.getWeeklySchedules(masterId: _masterId);
      final list = res.data?.data;
      if (list == null) return const <WeeklySchedule>[];
      return list
          .map(ScheduleMapper.weeklyScheduleFromResponse)
          .toList(growable: false);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      throw _logAndMap('listWeeklySchedules', e, st);
    }
  }

  @override
  Future<WeeklySchedule> upsertWeeklySchedule(
    WeeklySchedule schedule, {
    String? scheduleId,
  }) async {
    _assertAuthenticated();
    final request = ScheduleMapper.weeklyScheduleToRequest(schedule);
    try {
      if (scheduleId == null) {
        final res = await _masterApi.createWeeklySchedule(
          masterId: _masterId,
          weeklyScheduleRequest: request,
        );
        return _requireWeeklyData(res.data?.data);
      }
      final res = await _masterApi.updateWeeklySchedule(
        masterId: _masterId,
        scheduleId: scheduleId,
        weeklyScheduleRequest: request,
      );
      // Re-attach the id the caller targeted. The PUT wire response now also
      // carries `id`, but pin it explicitly so the returned template is always
      // tagged with the exact id we updated (defends against any server echo
      // mismatch on the update path).
      return _requireWeeklyData(res.data?.data, id: scheduleId);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      throw _logAndMap('upsertWeeklySchedule', e, st);
    }
  }

  @override
  Future<void> deleteWeeklySchedule(String scheduleId) async {
    _assertAuthenticated();
    try {
      await _masterApi.deleteWeeklySchedule(
        masterId: _masterId,
        scheduleId: scheduleId,
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      throw _logAndMap('deleteWeeklySchedule', e, st);
    }
  }

  @override
  Future<List<ScheduleOverride>> listOverrides(
    DateTime from,
    DateTime to,
  ) async {
    _assertAuthenticated();
    _assertBoundedRange(from, to);
    try {
      final res = await _masterApi.getOverrides(
        masterId: _masterId,
        from: ScheduleMapper.dateToWire(from),
        to: ScheduleMapper.dateToWire(to),
      );
      final list = res.data?.data;
      if (list == null) return const <ScheduleOverride>[];
      return list
          .map(ScheduleMapper.overrideFromResponse)
          .toList(growable: false);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      throw _logAndMap('listOverrides', e, st);
    }
  }

  @override
  Future<ScheduleOverride> putOverride(
    ScheduleOverride override, {
    bool cancelOverlapping = false,
  }) async {
    _assertAuthenticated();
    final date = override.start;
    try {
      final res = await _masterApi.upsertOverride(
        masterId: _masterId,
        date: ScheduleMapper.dateToWire(date),
        scheduleOverrideRequest: ScheduleMapper.overrideToRequestForDate(
          override,
          date,
          cancelOverlapping: cancelOverlapping,
        ),
      );
      final data = res.data?.data;
      if (data == null) {
        throw const ServerFailure();
      }
      return ScheduleMapper.overrideFromResponse(data);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      throw _logAndMapOverrideWrite('putOverride', e, st);
    }
  }

  @override
  Future<OverrideConflictCheck> previewConflicts(ScheduleOverride span) async {
    _assertAuthenticated();
    _assertBoundedRange(span.start, span.end);
    try {
      final res = await _masterApi.previewOverrideConflicts(
        masterId: _masterId,
        overrideConflictQueryRequest:
            ScheduleMapper.conflictQueryRequestForSpan(span),
      );
      final data = res.data?.data;
      if (data == null) {
        throw const ServerFailure();
      }
      return ScheduleMapper.overrideConflictCheckFromResponse(data);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      throw _logAndMap('previewConflicts', e, st);
    }
  }

  @override
  Future<void> clearOverride(DateTime date) async {
    _assertAuthenticated();
    try {
      await _masterApi.clearOverride(
        masterId: _masterId,
        date: ScheduleMapper.dateToWire(date),
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      throw _logAndMap('clearOverride', e, st);
    }
  }

  @override
  Future<List<EffectiveDay>> effectiveSchedule(
    DateTime from,
    DateTime to,
  ) async {
    _assertAuthenticated();
    _assertBoundedRange(from, to);
    try {
      final res = await _masterApi.getEffectiveSchedule(
        masterId: _masterId,
        from: ScheduleMapper.dateToWire(from),
        to: ScheduleMapper.dateToWire(to),
      );
      final list = res.data?.data;
      if (list == null) return const <EffectiveDay>[];
      return list
          .map(ScheduleMapper.effectiveDayFromResponse)
          .toList(growable: false);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      throw _logAndMap('effectiveSchedule', e, st);
    }
  }

  /// Re-runs a create/update response through the gap-filler so callers always
  /// receive a dense 7-entry week, attaching [id] when the caller targeted one.
  WeeklySchedule _requireWeeklyData(
    WeeklyScheduleResponse? data, {
    String? id,
  }) {
    if (data == null) {
      throw const ServerFailure();
    }
    return ScheduleMapper.weeklyScheduleFromResponse(data, id: id);
  }

  /// Logs (debug only) and maps a [DioException] to a typed [Failure].
  Failure _logAndMap(String op, DioException e, StackTrace st) {
    if (kDebugMode) {
      log(
        '$op failed: ${e.type} ${e.response?.statusCode}',
        name: _tag,
        level: 900,
        stackTrace: st,
      );
    }
    return _mapDioException(e);
  }

  /// Logs (debug only) and maps a `putOverride` [DioException] to a typed
  /// [Failure], checking the 2026-07-26 booking-conflict design's two special
  /// statuses BEFORE falling back to [_mapDioException] — mirroring the
  /// `HttpBookingRepository._mapBookingWriteException` precedent (status
  /// checks run before deferring to any [Failure] the [ErrorMapperInterceptor]
  /// may already have attached, since that interceptor has no
  /// schedule-override-specific case for either status).
  ///
  ///   - **409** — the conflict set changed between the caller's
  ///     [previewConflicts] call and this write (a booking was created, or an
  ///     existing one already changed status) — [ConflictFailure]. The caller
  ///     ([OverridesNotifier]) re-runs the preview rather than surfacing this
  ///     as a raw error.
  ///   - **429** — either the flat per-minute write-rate limit (50/60s) or the
  ///     aggregate per-hour decline budget (1500 bookings/hour) —
  ///     [ScheduleOverrideRateLimitedFailure], carrying the `Retry-After`
  ///     header when the server sent one.
  Failure _logAndMapOverrideWrite(String op, DioException e, StackTrace st) {
    if (kDebugMode) {
      log(
        '$op failed: ${e.type} ${e.response?.statusCode}',
        name: _tag,
        level: 900,
        stackTrace: st,
      );
    }
    final statusCode = e.response?.statusCode;
    if (statusCode == 409) return ConflictFailure(cause: e);
    if (statusCode == 429) {
      return ScheduleOverrideRateLimitedFailure(
        retryAfterSeconds: _extractRetryAfterSeconds(e),
        cause: e,
      );
    }
    return _mapDioException(e);
  }

  /// Parses the `Retry-After` response header (RFC 7231 §7.1.3, integer-seconds
  /// form only — the backend always emits an integer, never an HTTP-date).
  /// `null` when the header is absent or unparsable; the UI then shows a
  /// static "try later" message instead of a countdown.
  int? _extractRetryAfterSeconds(DioException e) {
    final raw = e.response?.headers.value('retry-after');
    if (raw == null) return null;
    return int.tryParse(raw.trim());
  }

  /// Maps a [DioException] to a typed [Failure].
  ///
  /// If [ErrorMapperInterceptor] already attached a [Failure] as `e.error`
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
      case DioExceptionType.badCertificate:
        // Own arm (mobile-security LOW, mirrors `HttpBookingRepository` /
        // `HttpSalonRepository`) rather than sharing the
        // `badResponse`/`cancel`/`unknown` catch-all below: a possible MITM on
        // schedule-override traffic (which now carries client names/phone-
        // adjacent identifiers via the conflict preview) gets its own log
        // signal, distinguishable from routine cancellation/server-error
        // noise, instead of blending into the catch-all. The [Failure] handed
        // back is deliberately UNCHANGED ([ServerFailure], still fails
        // closed) — only the log call is split out.
        //
        // NOTE what this actually is: `log(...)` below, gated the same as
        // every other diagnostic in this file — a LOCAL, debug-build-only
        // console line. This app ships no Sentry/Crashlytics/remote-log sink
        // anywhere, so there is no release-build telemetry trail and no
        // alerting on this signal; a real MITM in production leaves no
        // record beyond the fail-closed `ServerFailure` the caller already
        // sees. Do not assume this is monitored.
        if (kDebugMode) {
          log(
            'TLS/certificate validation failed for schedule traffic — '
            'possible MITM',
            name: 'feature.schedule.repository.security',
            level: 1000,
          );
        }
        return ServerFailure(statusCode: e.response?.statusCode, cause: e);
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return ServerFailure(statusCode: e.response?.statusCode, cause: e);
    }
  }
}
