// Phase 237 — BEAUTY WISH LIST repository.
//
// Reads the CLIENT's saved services from `GET /api/v1/favorites/services`
// (backend 247) through the generated [FavoriteControllerApi] and maps them via
// [WishlistMapper].
//
// Error policy mirrors [HttpPassportRepository] exactly: every method either
// resolves successfully or throws a [Failure] subclass from
// `core/errors/failures.dart`. Raw [DioException]s are caught here and never
// escape, so the notifier and the screens only ever see a typed failure. There
// is no retry loop — this is a plain idempotent GET and the screen owns the
// retry affordance.
//
// ## PAGE 0 ONLY — A DELIBERATE CAP, NOT AN OVERSIGHT
//
// The endpoint is `@PageableDefault(size = 20)`. Both approved surfaces render
// a single page: the passport page shows `take(2)`, and the full-list page's
// design carries no paging affordance at all — no "load more", no infinite
// scroll, no page indicator. Fetching one page is therefore the whole contract
// those designs describe, and shipping a pager nothing can drive would be dead
// weight. A client with more than [_pageSize] saved services sees the first
// [_pageSize]; the counter beside the section title counts what was fetched, so
// it stays truthful rather than claiming a total the list does not show.
//
// FOLLOW-UP, recorded rather than silently deferred: if the product ever wants
// an unbounded wish list, this is the seam — [WishlistRepository.getMyWishlist]
// grows a page argument and the notifier grows an append path. Do not bolt
// paging onto the SCREEN instead.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/errors/failures.dart';
import '../domain/wishlist_service.dart';
import 'wishlist_mapper.dart';

/// Reads the CLIENT's beauty wish list.
abstract interface class WishlistRepository {
  /// Returns the signed-in client's saved services, newest-first per the
  /// backend's own ordering. Capped at one page — see the file header.
  ///
  /// Throws a typed [Failure] on any transport or server error; raw
  /// [DioException]s never escape the implementation.
  Future<List<WishlistService>> getMyWishlist();
}

/// HTTP implementation of [WishlistRepository] backed by the generated
/// [FavoriteControllerApi].
///
/// Inject via `wishlistRepositoryProvider` — never construct directly outside
/// that provider.
final class HttpWishlistRepository implements WishlistRepository {
  HttpWishlistRepository(this._api);

  final FavoriteControllerApi _api;

  static const String _tag = 'feature.wishlist.repository';

  /// The single page this repository fetches. Matches the endpoint's own
  /// `@PageableDefault(size = 20)` so the request asks for exactly what the
  /// backend would have defaulted to — stated explicitly rather than relied on,
  /// so a backend-side default change cannot silently resize the client's list.
  static const int _pageSize = 20;

  static final Pageable _firstPage = Pageable(
    (PageableBuilder b) => b
      ..page = 0
      ..size = _pageSize,
  );

  @override
  Future<List<WishlistService>> getMyWishlist() async {
    try {
      final Response<ApiResponsePageResponseFavoriteServiceResponse> res =
          await _api.listServiceFavorites(pageable: _firstPage);
      final PageResponseFavoriteServiceResponse? page = res.data?.data;
      if (page == null) {
        if (kDebugMode) {
          log(
            'getMyWishlist: ApiResponsePageResponseFavoriteServiceResponse'
            '.data is null',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      // An ABSENT rows list is an empty wish list, not an error: the envelope
      // itself arrived, so the server answered. Only a missing envelope (above)
      // is a broken payload.
      final BuiltList<FavoriteServiceResponse>? rows = page.data;
      if (rows == null) return const <WishlistService>[];
      return WishlistMapper.fromDtoList(rows);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMyWishlist failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
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
  /// [HttpPassportRepository]'s.
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
