// Track 7.x Wave B — RatingRepository: the CLIENT's own-rating read path.
//
//   GET /api/v1/users/me/rating
//
// Backs «Мій рейтинг» (`MyRatingScreen`), replacing the Phase 13.7 (revised)
// placeholder that always rendered the empty state pending this endpoint.
// Mirrors `HttpClientProfileRepository` in shape (interface + Http impl +
// provider + DioException → typed Failure mapping), reusing the CORE
// [userApiProvider] singleton `UserControllerApi` rather than constructing a
// second instance — this endpoint lives on the same generated controller as
// `GET /users/me`.
//
// Every method either resolves successfully or throws a [Failure] subclass
// from `core/errors/failures.dart`. Raw [DioException]s are caught here and
// never escape.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/api_client_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/client_rating.dart';

part 'rating_repository.g.dart';

const String _tag = 'rating.repository';

/// Contract for the CLIENT's own aggregate-rating read layer.
abstract interface class RatingRepository {
  /// Fetches the authenticated CLIENT's own aggregate rating via
  /// `GET /api/v1/users/me/rating`.
  ///
  /// The backend resolves the user from the JWT, so no id is passed. A null
  /// `avgRating` on the returned [ClientRating] means no reviews yet — render
  /// the empty state, never a ★0. Throws a typed [Failure] on any transport or
  /// server error.
  Future<ClientRating> getMyRating();
}

/// HTTP implementation of [RatingRepository].
///
/// Inject via [ratingRepositoryProvider] — never construct directly.
final class HttpRatingRepository implements RatingRepository {
  HttpRatingRepository(this._userApi);

  final UserControllerApi _userApi;

  @override
  Future<ClientRating> getMyRating() async {
    try {
      final res = await _userApi.getMyRating();
      final dto = res.data?.data;
      if (dto == null) return const ClientRating();
      return ClientRating(
        avgRating: dto.avgRating?.toDouble(),
        reviewCount: dto.reviewCount ?? 0,
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMyRating failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  /// Maps a [DioException] to a typed [Failure]. If [ErrorMapperInterceptor]
  /// already attached a [Failure] as `e.error`, that value is re-thrown
  /// directly; otherwise the Dio type is inspected. Raw [DioException] never
  /// escapes.
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

/// Provides the [RatingRepository] singleton backed by the CORE
/// [userApiProvider] (`core/network/api_client_provider.dart`) — reused rather
/// than duplicated, since `UserControllerApi` is already a core-level
/// singleton shared by the client-profile feature.
///
/// Override in tests with a mocktail mock — never construct
/// [HttpRatingRepository] directly in production code.
@Riverpod(keepAlive: true)
RatingRepository ratingRepository(Ref ref) =>
    HttpRatingRepository(ref.watch(userApiProvider));
