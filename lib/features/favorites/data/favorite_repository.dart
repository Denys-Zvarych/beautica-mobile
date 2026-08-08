// Phase 13.4 — FavoriteRepository: interface + HTTP implementation.
//
// Wraps the generated [FavoriteControllerApi] for the favorites surface:
//   - add(target)    → POST   /api/v1/favorites           (idempotent 200)
//   - remove(target) → DELETE /api/v1/favorites?targetType&targetId (204)
//
// The favorite-toggle notifier (13.4) and the Favorites screen (13.10) call
// THIS — never the generated API directly. [FavoriteTargetType] is translated
// to the generated `AddFavoriteRequestTargetTypeEnum` here so the generated enum
// never leaks past the data layer.
//
// All DioExceptions are mapped to typed [Failure] subclasses via the same
// pattern as `search_repository.dart` (400/422 → ValidationFailure, 404 →
// NotFoundFailure, timeouts/connection → NetworkFailure, others → ServerFailure;
// an interceptor-attached Failure is preferred). No raw Dio type crosses this
// boundary into the application or presentation layers.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';

import '../domain/favorite_target.dart';

/// Contract for the favorites mutation layer.
///
/// Both methods resolve to `void` on success or throw a [Failure] subclass.
/// The backend treats add as idempotent (re-adding an existing favorite returns
/// 200, not an error) and remove as idempotent (removing an absent favorite
/// returns 204), so the optimistic toggle never has to special-case a
/// "duplicate".
abstract interface class FavoriteRepository {
  /// Adds [target] to the signed-in client's favorites. Idempotent.
  Future<void> add(FavoriteTarget target);

  /// Removes [target] from the signed-in client's favorites. Idempotent.
  Future<void> remove(FavoriteTarget target);
}

/// HTTP implementation of [FavoriteRepository].
///
/// Inject via `favoriteRepositoryProvider` — never construct directly.
final class HttpFavoriteRepository implements FavoriteRepository {
  HttpFavoriteRepository(this._api);

  final FavoriteControllerApi _api;

  static const _tag = 'feature.favorites.repository';

  /// Wire value for the `targetType` query/body param.
  static AddFavoriteRequestTargetTypeEnum _wireType(FavoriteTargetType type) {
    switch (type) {
      case FavoriteTargetType.master:
        return AddFavoriteRequestTargetTypeEnum.MASTER;
      case FavoriteTargetType.salon:
        return AddFavoriteRequestTargetTypeEnum.SALON;
      case FavoriteTargetType.service:
        return AddFavoriteRequestTargetTypeEnum.SERVICE;
    }
  }

  @override
  Future<void> add(FavoriteTarget target) async {
    try {
      await _api.addFavorite(
        addFavoriteRequest: AddFavoriteRequest(
          (b) => b
            ..targetType = _wireType(target.type)
            ..targetId = target.id,
        ),
      );
    } on DioException catch (e, st) {
      _log('add', e, st);
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> remove(FavoriteTarget target) async {
    try {
      await _api.removeFavorite(
        targetType: _wireType(target.type).name,
        targetId: target.id,
      );
    } on DioException catch (e, st) {
      _log('remove', e, st);
      throw _mapDioException(e);
    }
  }

  void _log(String op, DioException e, StackTrace st) {
    if (kDebugMode) {
      log(
        'favorite $op failed: ${e.type} ${e.response?.statusCode}',
        name: _tag,
        level: 900,
        stackTrace: st,
      );
    }
  }

  /// Maps a [DioException] to a typed [Failure]. Mirrors
  /// `HttpSearchRepository._mapDioException`.
  Failure _mapDioException(DioException e) {
    if (e.error is Failure) return e.error as Failure;
    final statusCode = e.response?.statusCode;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(cause: e);
      case DioExceptionType.badResponse:
        if (statusCode == 400 || statusCode == 422) {
          return ValidationFailure(fieldErrors: const {}, cause: e);
        }
        if (statusCode == 404) return NotFoundFailure(cause: e);
        return ServerFailure(statusCode: statusCode, cause: e);
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return ServerFailure(statusCode: statusCode, cause: e);
    }
  }
}
