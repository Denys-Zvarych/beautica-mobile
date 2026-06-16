// TODO(phase-3.2): replace hand-written payloads with generated UserApi DTOs.
//
// Post-registration hot-fix — UserRepository (hand-written Dio).
//
// Created to fix a CLIENT-registration locality persistence regression: the
// register endpoint silently drops locality fields (RegisterRequest DTO does
// not declare them), so locality must be PATCHed onto the user record after
// email verification — the FIRST point a Bearer token exists.
//
// This repository talks to the authenticated [dioProvider] Dio singleton —
// mirroring [HttpMasterRepository] / [HttpSalonRepository] / [HttpAuthRepository]
// in style. CLIENT does not have a provider profile (no PATCH
// /independent-masters/me), so locality lives directly on the user row.
//
// Backend contract (locked — backend PR #58):
//   PATCH /api/v1/users/me
//     Body: { cityId? (UUID|null), districtId? (UUID|null), street?,
//             buildingNo?, locationNote? }
//     Returns: ApiResponse<UserResponse> — the mobile layer does not need the
//              body here, so the method resolves with void.
//
// AppConfig.baseUrl does NOT carry the `/api/v1` prefix (see app_config.dart).
// The path below must include the full `/api/v1/` segment explicitly.

import 'dart:developer';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'user_repository.g.dart';

/// Contract for the authenticated user's profile write layer.
///
/// Every method either resolves successfully or throws a [Failure] subclass
/// from `core/errors/failures.dart`. Raw [DioException]s are caught inside the
/// implementation and never escape.
abstract interface class UserRepository {
  /// Persists the authenticated user's locality + working address.
  ///
  /// Wraps `PATCH /users/me`. All fields are optional — pass only the slice
  /// the caller has captured (e.g. CLIENT Step 3 captures all five). Throws a
  /// typed [Failure] on any transport or server error.
  Future<void> updateLocality({
    required String cityId,
    String? districtId,
    String? street,
    String? buildingNo,
    String? locationNote,
  });
}

/// HTTP implementation of [UserRepository].
///
/// Inject via [userRepositoryProvider] — never construct directly.
final class HttpUserRepository implements UserRepository {
  HttpUserRepository(this._dio);

  final Dio _dio;

  @override
  Future<void> updateLocality({
    required String cityId,
    String? districtId,
    String? street,
    String? buildingNo,
    String? locationNote,
  }) async {
    // Build the body explicitly so null / empty optionals are omitted rather
    // than sent as `null` strings (backlog pattern 5 — trim once).
    final trimmedStreet = street?.trim();
    final trimmedBuildingNo = buildingNo?.trim();
    final trimmedNote = locationNote?.trim();
    final body = <String, dynamic>{'cityId': cityId};
    if (districtId != null && districtId.isNotEmpty) {
      body['districtId'] = districtId;
    }
    if (trimmedStreet != null && trimmedStreet.isNotEmpty) {
      body['street'] = trimmedStreet;
    }
    if (trimmedBuildingNo != null && trimmedBuildingNo.isNotEmpty) {
      body['buildingNo'] = trimmedBuildingNo;
    }
    if (trimmedNote != null && trimmedNote.isNotEmpty) {
      body['locationNote'] = trimmedNote;
    }

    try {
      await _dio.patch<Map<String, dynamic>>('/api/v1/users/me', data: body);
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'updateLocality failed: ${e.type} ${e.response?.statusCode}',
          name: 'user.repository',
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

/// Provides the [UserRepository] singleton backed by the authenticated Dio.
///
/// Override in tests with a mocktail mock — never construct
/// [HttpUserRepository] directly in tests.
@Riverpod(keepAlive: true)
UserRepository userRepository(Ref ref) =>
    HttpUserRepository(ref.watch(dioProvider));
