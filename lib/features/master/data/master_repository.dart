// Phase 4.1 — MasterRepository extended with getMyProfile.
//
// Phase 2.19 introduced [HttpMasterRepository] with a hand-written Dio
// implementation of [updateLocality]. Phase 4.1 adds [getMyProfile], which
// uses the generated [MasterControllerApi] (via [masterApiProvider]) so that
// deserialization of the `MasterDetailResponse` envelope is handled by the
// generated built_value serializers — no manual JSON parsing needed.
//
// The constructor now accepts both [Dio] (for [updateLocality]) and
// [MasterControllerApi] (for [getMyProfile]). Both are injected via
// [masterRepositoryProvider] — never construct directly.
//
// Backend contracts:
//   PATCH /api/v1/independent-masters/me — see Phase 2.19 comment.
//   GET   /api/v1/masters/{masterId}     — returns ApiResponse<MasterDetailResponse>.
//
// The base URL already carries the `/api/v1` prefix (see AppConfig.baseUrl).

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/api_client_provider.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'master_mapper.dart';

part 'master_repository.g.dart';

/// Contract for the independent-master profile layer.
///
/// Every method either resolves successfully or throws a [Failure] subclass
/// from `core/errors/failures.dart`. Raw [DioException]s are caught inside the
/// implementation and never escape.
abstract interface class MasterRepository {
  /// Persists the authenticated master's working address.
  ///
  /// Wraps `PATCH /independent-masters/me`. [districtId] and [locationNote] are
  /// optional — pass `null` for a city without districts / no note. Throws a
  /// typed [Failure] on any transport or server error.
  Future<void> updateLocality({
    required String cityId,
    String? districtId,
    required String street,
    required String buildingNo,
    String? locationNote,
  });

  /// Fetches the master profile for the given [masterId].
  ///
  /// Wraps `GET /masters/{masterId}`. For the authenticated master's own
  /// profile, pass the user's id (available from [AuthSession.user.id]).
  /// Throws a typed [Failure] on any transport or server error.
  Future<Master> getMyProfile(String masterId);
}

/// HTTP implementation of [MasterRepository].
///
/// Inject via [masterRepositoryProvider] — never construct directly.
///
/// [_dio] drives [updateLocality] (hand-written PATCH envelope).
/// [_masterApi] drives [getMyProfile] using the generated [MasterControllerApi]
/// so that built_value deserialization handles the response envelope.
final class HttpMasterRepository implements MasterRepository {
  HttpMasterRepository(this._dio, this._masterApi);

  final Dio _dio;
  final MasterControllerApi _masterApi;

  @override
  Future<void> updateLocality({
    required String cityId,
    String? districtId,
    required String street,
    required String buildingNo,
    String? locationNote,
  }) async {
    // Build the body explicitly so null / empty optionals are omitted rather
    // than sent as `null` strings (backlog pattern 5 — trim once).
    final trimmedNote = locationNote?.trim();
    final body = <String, dynamic>{
      'cityId': cityId,
      'street': street.trim(),
      'buildingNo': buildingNo.trim(),
    };
    if (districtId != null && districtId.isNotEmpty) {
      body['districtId'] = districtId;
    }
    if (trimmedNote != null && trimmedNote.isNotEmpty) {
      body['locationNote'] = trimmedNote;
    }

    try {
      await _dio.patch<Map<String, dynamic>>(
        '/independent-masters/me',
        data: body,
      );
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'updateLocality failed: ${e.type} ${e.response?.statusCode}',
          name: 'master.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<Master> getMyProfile(String masterId) async {
    try {
      final res = await _masterApi.getMasterDetail(masterId: masterId);
      final dto = res.data?.data;
      if (dto == null) {
        // Fix 7 (SEC MEDIUM-2): guard the log call with kDebugMode so the
        // masterId (PII-adjacent) is never emitted in release builds. Matches
        // the existing guard pattern on the other log() calls in this file.
        if (kDebugMode) {
          log(
            'getMyProfile: ApiResponseMasterDetailResponse.data is null '
            'for masterId=$masterId',
            name: 'master.repository',
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return MasterMapper.fromDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMyProfile failed: ${e.type} ${e.response?.statusCode}',
          name: 'master.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  /// Maps a [DioException] to a typed [Failure].
  ///
  /// If [ErrorMapperInterceptor] has already attached a [Failure] as `e.error`,
  /// that value is re-thrown directly; otherwise the Dio type is inspected so
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

/// Provides the [MasterRepository] singleton backed by the authenticated Dio
/// and the generated [MasterControllerApi].
///
/// Override in tests with a mocktail mock — never construct
/// [HttpMasterRepository] directly in tests.
@Riverpod(keepAlive: true)
MasterRepository masterRepository(Ref ref) =>
    HttpMasterRepository(ref.watch(dioProvider), ref.watch(masterApiProvider));
