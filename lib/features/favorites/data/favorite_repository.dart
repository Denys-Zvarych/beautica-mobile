// Phase 13.4 — FavoriteRepository: interface + HTTP implementation.
//
// Wraps the generated [FavoriteControllerApi] for the favorites surface:
//   - add(target)          → POST   /api/v1/favorites           (idempotent 200)
//   - remove(target)       → DELETE /api/v1/favorites?targetType&targetId (204)
//   - getFavoriteMasters() → GET    /api/v1/favorites/masters   (Phase 111)
//   - getFavoriteSalons()  → GET    /api/v1/favorites/salons    (Phase 111)
//
// The favorite-toggle notifier (13.4) and the Favorites screen (Phase 111) call
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
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';

import '../domain/favorite_item.dart';
import '../domain/favorite_target.dart';
import 'favorite_mapper.dart';

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

  /// The signed-in client's favourited masters, newest-saved first (the
  /// backend orders by `favorites.created_at DESC`).
  ///
  /// Capped at one page — see [HttpFavoriteRepository.pageSize]. Throws a typed
  /// [Failure] on any transport or server error; raw [DioException]s never
  /// escape the implementation.
  Future<List<FavoriteItem>> getFavoriteMasters();

  /// The signed-in client's favourited salons, newest-saved first. Same page
  /// cap and error contract as [getFavoriteMasters].
  Future<List<FavoriteItem>> getFavoriteSalons();
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
      case FavoriteTargetType.salonService:
        return AddFavoriteRequestTargetTypeEnum.SALON_SERVICE;
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

  /// The single page both list calls fetch.
  ///
  /// Matches the endpoints' own `@PageableDefault(size = 20)` so the request
  /// asks for exactly what the backend would have defaulted to — stated
  /// explicitly rather than relied on, so a backend-side default change cannot
  /// silently resize the client's list. Same policy (and same value) as
  /// `HttpWishlistRepository._pageSize`.
  ///
  /// A client with more than 20 saved masters (or salons) sees only the 20 most
  /// recently saved. Pagination is not wired: «Улюблені» is a flat unsectioned
  /// scroll with no page footer in the approved design, and no infinite-scroll
  /// affordance was specified.
  static const int pageSize = 20;

  static final Pageable _firstPage = Pageable(
    (PageableBuilder b) => b
      ..page = 0
      ..size = pageSize,
  );

  @override
  Future<List<FavoriteItem>> getFavoriteMasters() async {
    try {
      final Response<ApiResponsePageResponseFavoriteMasterResponse> res =
          await _api.listMasterFavorites(pageable: _firstPage);
      final PageResponseFavoriteMasterResponse? page = res.data?.data;
      if (page == null) {
        _logMissingEnvelope('getFavoriteMasters');
        throw const ServerFailure(statusCode: null);
      }
      // An ABSENT rows list is an EMPTY favourites list, not an error: the
      // envelope itself arrived, so the server answered. Only a missing
      // envelope (above) is a broken payload.
      final BuiltList<FavoriteMasterResponse>? rows = page.data;
      if (rows == null) return const <FavoriteItem>[];
      return FavoriteMapper.mastersFromDtoList(rows);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      _log('getFavoriteMasters', e, st);
      throw _mapDioException(e);
    }
  }

  @override
  Future<List<FavoriteItem>> getFavoriteSalons() async {
    try {
      final Response<ApiResponsePageResponseFavoriteSalonResponse> res =
          await _api.listSalonFavorites(pageable: _firstPage);
      final PageResponseFavoriteSalonResponse? page = res.data?.data;
      if (page == null) {
        _logMissingEnvelope('getFavoriteSalons');
        throw const ServerFailure(statusCode: null);
      }
      final BuiltList<FavoriteSalonResponse>? rows = page.data;
      if (rows == null) return const <FavoriteItem>[];
      return FavoriteMapper.salonsFromDtoList(rows);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      _log('getFavoriteSalons', e, st);
      throw _mapDioException(e);
    }
  }

  void _logMissingEnvelope(String op) {
    if (kDebugMode) {
      log('$op: response envelope .data is null', name: _tag, level: 1000);
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
      // Backlog fix (Phase 111) — `badCertificate` used to fall into the
      // `ServerFailure` arm below, across 11 repositories. That was wrong (the
      // server never spoke, so there is no server to blame), but so was the
      // first correction, which folded it into `NetworkFailure` above:
      // `dio_provider.dart:216` states that a pin miss must not "blend into
      // generic network failures", and `NetworkFailure`'s copy («перевірте
      // з'єднання») tells the client to retry or switch networks — the exact
      // wrong advice when the cause is an intercepting proxy. This app PINS,
      // so `badCertificate` fires only after the chain failed against the
      // pinned anchors: it is a pin miss, not a captive portal. It gets its
      // own typed failure and its own copy. Only this repository's arm is
      // moved; the other ten are a separate sweep.
      case DioExceptionType.badCertificate:
        return CertificateFailure(cause: e);
      case DioExceptionType.badResponse:
        if (statusCode == 400 || statusCode == 422) {
          return ValidationFailure(fieldErrors: const {}, cause: e);
        }
        if (statusCode == 404) return NotFoundFailure(cause: e);
        return ServerFailure(statusCode: statusCode, cause: e);
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return ServerFailure(statusCode: statusCode, cause: e);
    }
  }
}
