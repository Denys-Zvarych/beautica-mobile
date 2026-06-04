// Phase 6.1 — WorkingHoursRepository: the calendar feature's working-hours
// data layer.
//
// Contract (verified against the generated client 2026-06-04):
//   Read  — there is NO standalone GET working-hours endpoint. Working hours
//           come bundled in MasterDetailResponse.workingHours. Rather than
//           re-fetch that envelope (PERF M1), [list] returns the working week
//           already carried on the cached [Master] profile — the provider wires
//           in the dense, gap-filled week from [masterProfileProvider] at
//           construction time, so [list] performs NO network call.
//   Write — MasterControllerApi.upsertWorkingHours(masterId, BuiltList<
//           WorkingHoursRequest>) → PATCH /api/v1/masters/{masterId}/working-hours,
//           returning ApiResponseListWorkingHoursResponse (the saved list).
//           The endpoint requires the real Master-row UUID in the path and is
//           authorised by @authz.canManageMasterSchedule.
//
// [_masterId] is the Master-row UUID (from MasterDetailResponse.masterId), NOT
// the User UUID from the auth session — they differ (see the services feature's
// long-standing note). It is resolved from [masterProfileProvider] at provider
// construction time (see [workingHoursRepositoryProvider]).
//
// Every method either resolves successfully or throws a typed [Failure] from
// `core/errors/failures.dart`. Raw [DioException]s are caught here and never
// escape. A 400 (server-side time-range / @Size validation) surfaces as a
// [ValidationFailure] — the [ErrorMapperInterceptor] maps the 400 envelope and
// attaches it to `DioException.error`, which [_mapDioException] re-throws.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../domain/working_hours.dart';
import 'working_hours_mapper.dart';

/// Contract for the master working-hours data layer.
///
/// [replaceAll] is intentionally an atomic "save the whole week" operation
/// rather than a per-day patch — the Phase 6.2 editor commits all seven days in
/// one PATCH so a half-applied state (e.g. Monday saved, Tuesday failed) is
/// impossible.
abstract interface class WorkingHoursRepository {
  /// Returns the authenticated master's week as a dense, ordered 7-entry list
  /// (Monday(1) … Sunday(7)). Missing / closed days are already filled by the
  /// mapper (at profile-mapping time) so the editor always has all seven days.
  ///
  /// PERF M1: this reads from the already-cached [masterProfileProvider] value's
  /// working hours (injected at construction) and performs NO network call —
  /// the profile fetch the app already made carries the bundled week.
  Future<List<WorkingHours>> list();

  /// Replaces the entire week with [hours] and returns the saved list (mapped
  /// back through the gap-filler so the result is always 7 ordered entries).
  /// Throws [ValidationFailure] on a backend 400, or another typed [Failure]
  /// on any transport / server error.
  Future<List<WorkingHours>> replaceAll(List<WorkingHours> hours);
}

/// HTTP implementation of [WorkingHoursRepository].
///
/// Inject via `workingHoursRepositoryProvider` — never construct directly.
///
/// [_masterApi] drives the write ([MasterControllerApi.upsertWorkingHours])
/// path through the generated client so built_value handles serialization.
/// [_masterId] is the Master-row UUID resolved at provider construction time.
/// [_cachedWeek] is the dense, gap-filled working week already carried on the
/// cached [Master] profile — [list] returns it directly with NO network call
/// (PERF M1).
final class HttpWorkingHoursRepository implements WorkingHoursRepository {
  HttpWorkingHoursRepository({
    required MasterControllerApi masterApi,
    required String masterId,
    required List<WorkingHours> cachedWeek,
  }) : _masterApi = masterApi,
       _masterId = masterId,
       _cachedWeek = cachedWeek;

  final MasterControllerApi _masterApi;
  final String _masterId;
  final List<WorkingHours> _cachedWeek;

  static const _tag = 'feature.calendar.workinghours.repository';

  /// Throws [UnauthorizedFailure] immediately if [_masterId] is empty.
  ///
  /// An empty masterId means [masterProfileProvider] has not resolved an
  /// authenticated master yet. Proceeding would PATCH `/api/v1/masters//working-hours`
  /// and surface an opaque [NotFoundFailure]; failing fast surfaces the real
  /// cause to callers. Only the write path guards this — the read path resolves
  /// the master from the JWT and needs no path id.
  void _assertAuthenticated() {
    if (_masterId.isEmpty) {
      throw const UnauthorizedFailure();
    }
  }

  @override
  Future<List<WorkingHours>> list() async {
    // PERF M1: no network call. The week is already on the cached [Master]
    // profile (fetched once via masterProfileProvider) and gap-filled to 7
    // entries at profile-mapping time; the provider injects it here. Returning a
    // Future keeps the [WorkingHoursRepository] contract unchanged.
    return _cachedWeek;
  }

  @override
  Future<List<WorkingHours>> replaceAll(List<WorkingHours> hours) async {
    _assertAuthenticated();
    try {
      final res = await _masterApi.upsertWorkingHours(
        masterId: _masterId,
        workingHoursRequest: WorkingHoursMapper.toRequestList(hours),
      );
      // The backend returns the saved list; re-run it through the gap-filler so
      // callers always receive a dense, ordered 7-entry week.
      return WorkingHoursMapper.toDomainWeek(res.data?.data);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'replaceAll failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
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
