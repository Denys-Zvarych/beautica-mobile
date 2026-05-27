// TODO(phase-3.2): replace hand-written payloads with generated MasterApi DTOs.
//
// Phase 2.19 — MasterRepository (hand-written Dio).
//
// The OpenAPI codegen for `lib/api/` is deferred (see ARCHITECTURE-mobile.md
// § 2), so this repository talks to the backend directly through the singleton
// authenticated [dioProvider] Dio — mirroring [HttpLocationRepository] and
// [HttpAuthRepository]'s envelope handling.
//
// For now the only method is [updateLocality], called immediately after a
// successful INDEPENDENT_MASTER registration to persist the provider's working
// address (locality + street + building + optional note) onto their profile,
// per backend Phase 10.6.
//
// Backend contract (locked):
//   PATCH /api/v1/independent-masters/me
//     Body: { cityId (UUID), districtId? (UUID|null), street, buildingNo,
//             locationNote? }
//     Returns: ApiResponse<IndependentMasterResponse> — the mobile layer does
//              not need the body here, so the method resolves with void.
//
// The base URL already carries the `/api/v1` prefix (see AppConfig.baseUrl), so
// the path below is the suffix only.

import 'dart:developer';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'master_repository.g.dart';

/// Contract for the independent-master profile write layer.
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
}

/// HTTP implementation of [MasterRepository].
///
/// Inject via [masterRepositoryProvider] — never construct directly.
final class HttpMasterRepository implements MasterRepository {
  HttpMasterRepository(this._dio);

  final Dio _dio;

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

/// Provides the [MasterRepository] singleton backed by the authenticated Dio.
///
/// Override in tests with a mocktail mock — never construct
/// [HttpMasterRepository] directly in tests.
@Riverpod(keepAlive: true)
MasterRepository masterRepository(Ref ref) =>
    HttpMasterRepository(ref.watch(dioProvider));
