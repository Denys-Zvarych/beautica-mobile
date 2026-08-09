// Phase 13.8 — BEAUTY PASSPORT repository.
//
// Fetches the CLIENT's auto-derived passport aggregate from
// `GET /api/v1/clients/me/passport` (backend 19.5) through the generated
// [ClientControllerApi] and maps it via [PassportMapper.fromDto].
//
// Error policy mirrors [HttpClientProfileRepository] exactly: every method
// either resolves successfully or throws a [Failure] subclass from
// `core/errors/failures.dart`. Raw [DioException]s are caught here and never
// escape, so the screen only ever sees a typed failure. There is no retry loop
// — this is a plain idempotent GET and the screen owns the retry affordance.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/errors/failures.dart';
import '../domain/passport.dart';
import 'passport_mapper.dart';

/// Reads the CLIENT's derived beauty passport.
abstract interface class PassportRepository {
  /// Returns the signed-in client's auto-derived passport.
  ///
  /// Throws a typed [Failure] on any transport or server error; raw
  /// [DioException]s never escape the implementation.
  Future<Passport> getMyPassport();
}

/// HTTP implementation of [PassportRepository] backed by the generated
/// [ClientControllerApi].
///
/// Inject via `passportRepositoryProvider` — never construct directly outside
/// that provider.
final class HttpPassportRepository implements PassportRepository {
  HttpPassportRepository(this._clientApi);

  final ClientControllerApi _clientApi;

  @override
  Future<Passport> getMyPassport() async {
    try {
      final res = await _clientApi.getPassport();
      final PassportResponse? dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'getMyPassport: ApiResponsePassportResponse.data is null',
            name: 'feature.passport.repository',
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return PassportMapper.fromDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMyPassport failed: ${e.type} ${e.response?.statusCode}',
          name: 'feature.passport.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  /// Maps a [DioException] to a typed [Failure]. If `ErrorMapperInterceptor`
  /// already attached a [Failure] as `e.error`, that value is re-thrown
  /// directly; otherwise the Dio type is inspected. Identical policy to
  /// [HttpClientProfileRepository._mapDioException].
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
