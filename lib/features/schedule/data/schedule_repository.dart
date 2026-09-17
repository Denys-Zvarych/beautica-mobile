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
// Phase 335 — this file ALSO hosts a SECOND, deliberately separate repository,
// [SalonRosterScheduleRepository]:
//   GET /api/v1/salons/{salonId}/masters/effective-schedule?from&to
//       → SalonControllerApi.getSalonMastersEffectiveSchedule
// It is NOT a method on [ScheduleRepository] and it is NOT keyed on
// [ScheduleScope]. See that interface's own doc for why both of those are
// load-bearing rather than stylistic.
//
// [_masterId] is the Master-row UUID (from MasterDetailResponse.masterId), NOT
// the User UUID from the auth session — they differ (see the working-hours and
// services features' long-standing note). Resolved from [ScheduleScope
// .masterId] at provider construction time (Phase 312 — was
// [masterProfileProvider] directly; see `schedule_repository_provider.dart`'s
// header for why that watch moved out). Empty id → [UnauthorizedFailure], no
// API call.
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

  /// Aliases the library-level [_kScheduleRepoTag] so this class and the
  /// salon-roster repository below log under ONE name rather than two
  /// strings that can drift.
  static const _tag = _kScheduleRepoTag;

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
  void _assertBoundedRange(DateTime from, DateTime to) =>
      _assertBoundedScheduleRange(from, to, kMaxScheduleRangeDays);

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
  ///
  /// Phase 335 — body moved to the library-private [_logAndMapScheduleDio]
  /// so [HttpSalonRosterScheduleRepository] reuses the identical log line +
  /// mapping rather than growing a second copy. Behaviour unchanged.
  Failure _logAndMap(String op, DioException e, StackTrace st) =>
      _logAndMapScheduleDio(op, e, st);

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
  /// Phase 335 — body moved to the library-private
  /// [_mapScheduleDioException]; see that function's doc, which carries the
  /// full per-arm reasoning (including the badCertificate MITM note).
  /// Behaviour unchanged.
  Failure _mapDioException(DioException e) => _mapScheduleDioException(e);
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED, LIBRARY-PRIVATE HELPERS (Phase 335)
// ═══════════════════════════════════════════════════════════════════════════
// Extracted verbatim from [HttpScheduleRepository] so the salon-roster
// repository below reuses the SAME range guard, the SAME log line and the
// SAME `DioException` → [Failure] mapping instead of growing a second,
// drifting copy of each. Every one of these bodies is byte-for-byte what the
// method it came from ran; the methods are now one-line delegators.

/// The log `name:` every schedule-feature repository diagnostic carries.
const String _kScheduleRepoTag = 'feature.schedule.repository';

/// Asserts (debug) and enforces (release) a bounded, ordered range before any
/// network call. An open / inverted / over-[maxDays] window is a caller bug —
/// it throws a [ValidationFailure] so the same typed error path a backend 400
/// would produce is used in both cases.
///
/// [maxDays] is a PARAMETER because the two endpoints this library calls cap
/// differently: the per-master routes at [kMaxScheduleRangeDays] (366), the
/// salon-roster batch route at [kMaxSalonRosterScheduleRangeDays] (62).
/// Mirroring each backend cap exactly is the whole point of the client-side
/// guard — a single shared number would either reject a legal 366-day master
/// window or let an illegal 63-day salon window reach the wire.
void _assertBoundedScheduleRange(DateTime from, DateTime to, int maxDays) {
  final spanDays = to.difference(from).inDays;
  assert(
    !to.isBefore(from) && spanDays <= maxDays,
    'Schedule range must be ordered and ≤ $maxDays days '
    '(got from=$from to=$to, span=$spanDays days).',
  );
  if (to.isBefore(from) || spanDays > maxDays) {
    throw const ValidationFailure(fieldErrors: <String, String>{});
  }
}

/// Logs (debug only) and maps a [DioException] to a typed [Failure].
Failure _logAndMapScheduleDio(String op, DioException e, StackTrace st) {
  if (kDebugMode) {
    log(
      '$op failed: ${e.type} ${e.response?.statusCode}',
      name: _kScheduleRepoTag,
      level: 900,
      stackTrace: st,
    );
  }
  return _mapScheduleDioException(e);
}

/// Maps a [DioException] to a typed [Failure].
///
/// If [ErrorMapperInterceptor] already attached a [Failure] as `e.error`
/// (e.g. a 400 → [ValidationFailure], a 401 → [UnauthorizedFailure]), that
/// value is re-thrown directly; otherwise the Dio type is inspected so
/// connectivity issues surface as [NetworkFailure] and everything else as
/// [ServerFailure]. Raw [DioException] never escapes.
Failure _mapScheduleDioException(DioException e) {
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
      // schedule traffic (which carries client names/phone-adjacent
      // identifiers via the conflict preview) gets its own log signal,
      // distinguishable from routine cancellation/server-error noise, instead
      // of blending into the catch-all. The [Failure] handed back is
      // deliberately UNCHANGED ([ServerFailure], still fails closed) — only
      // the log call is split out.
      //
      // NOTE what this actually is: `log(...)` below, gated the same as every
      // other diagnostic in this file — a LOCAL, debug-build-only console
      // line. This app ships no Sentry/Crashlytics/remote-log sink anywhere,
      // so there is no release-build telemetry trail and no alerting on this
      // signal; a real MITM in production leaves no record beyond the
      // fail-closed `ServerFailure` the caller already sees. Do not assume
      // this is monitored.
      if (kDebugMode) {
        log(
          'TLS/certificate validation failed for schedule traffic — '
          'possible MITM',
          name: '$_kScheduleRepoTag.security',
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

// ═══════════════════════════════════════════════════════════════════════════
// PHASE 335 — THE SALON-ROSTER EFFECTIVE SCHEDULE
// ═══════════════════════════════════════════════════════════════════════════

/// The inclusive maximum span (in days) the SALON-ROSTER batch route accepts.
/// Tighter than [kMaxScheduleRangeDays] because the batch fans out across
/// every active master on the roster — mirrors the backend's own 62-day cap
/// (phase 321). One calendar month (the only window the board ever asks for)
/// is at most 31 days, so this is never close to binding in practice; it
/// exists so an over-wide window never leaves the device.
const int kMaxSalonRosterScheduleRangeDays = 62;

/// Contract for the SALON-WIDE roster schedule read.
///
/// ## Why this is NOT a method on [ScheduleRepository]
///
/// [ScheduleRepository] is masterId-keyed BY CONTRACT — its provider is a
/// family over [ScheduleScope] (`schedule_repository_provider.dart`), every
/// method funnels through `_assertAuthenticated`'s empty-masterId guard, and
/// a salon-wide read has no masterId to key on. Bending [ScheduleScope] to
/// carry a salon-only shape would hand every one of those per-master methods
/// a scope they cannot serve. It would also break, at compile time, the seven
/// hand-written `implements ScheduleRepository` fakes under `test/` — for a
/// method not one of them has any business answering.
///
/// So: a second, single-method interface with its own provider. The salonId
/// is a PARAMETER, not a family key, because this repository is stateless
/// with respect to it (contrast [HttpScheduleRepository], which closes over
/// the master id its scope resolved).
abstract interface class SalonRosterScheduleRepository {
  /// Resolves the effective schedule of EVERY active master on [salonId]'s
  /// roster across `[from, to]` (inclusive), keyed by master id.
  ///
  /// **The result is ROSTER-COMPLETE**: the backend emits an entry for every
  /// active master, including one with no schedule rows at all (whose days
  /// then resolve to [EffectiveSource.noSchedule]). That is deliberate and
  /// load-bearing — it is the ONLY thing that lets a caller distinguish "this
  /// master is off today" from "this master's schedule has not loaded".
  ///
  /// Every [EffectiveDay] on this path carries `window == null`: the batch
  /// endpoint never projects the per-master display window (pinned by a
  /// backend test). Callers compute their own bounds from
  /// [EffectiveDay.intervals] / [EffectiveDay.times].
  ///
  /// Range MUST be bounded (≤ [kMaxSalonRosterScheduleRangeDays]).
  Future<Map<String, List<EffectiveDay>>> salonRosterEffectiveSchedule(
    String salonId,
    DateTime from,
    DateTime to,
  );
}

/// HTTP implementation of [SalonRosterScheduleRepository].
///
/// Inject via `salonRosterScheduleRepositoryProvider` — never construct
/// directly outside that provider and its tests.
final class HttpSalonRosterScheduleRepository
    implements SalonRosterScheduleRepository {
  HttpSalonRosterScheduleRepository({required SalonControllerApi salonApi})
    : _salonApi = salonApi;

  final SalonControllerApi _salonApi;

  @override
  Future<Map<String, List<EffectiveDay>>> salonRosterEffectiveSchedule(
    String salonId,
    DateTime from,
    DateTime to,
  ) async {
    if (salonId.isEmpty) {
      // Fail fast rather than issuing `/api/v1/salons//masters/…`, which
      // would surface as an opaque [NotFoundFailure]. Mirrors
      // [HttpScheduleRepository._assertAuthenticated]'s reasoning.
      throw const UnauthorizedFailure();
    }
    _assertBoundedScheduleRange(from, to, kMaxSalonRosterScheduleRangeDays);
    try {
      final res = await _salonApi.getSalonMastersEffectiveSchedule(
        salonId: salonId,
        from: ScheduleMapper.dateToWire(from),
        to: ScheduleMapper.dateToWire(to),
      );
      final list = res.data?.data;
      if (list == null) return const <String, List<EffectiveDay>>{};
      final Map<String, List<EffectiveDay>> byMaster =
          <String, List<EffectiveDay>>{};
      for (final entry in list) {
        final String? masterId = entry.masterId;
        // A roster entry with no id is unusable to every caller (they all
        // look a master up by id) — dropped rather than keyed on `''`, which
        // would silently merge two such entries into one.
        if (masterId == null || masterId.isEmpty) continue;
        byMaster[masterId] =
            entry.days
                ?.map(ScheduleMapper.effectiveDayFromResponse)
                .toList(growable: false) ??
            const <EffectiveDay>[];
      }
      return byMaster;
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      throw _logAndMapScheduleDio('salonRosterEffectiveSchedule', e, st);
    }
  }
}
