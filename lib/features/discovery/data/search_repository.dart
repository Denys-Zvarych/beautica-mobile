// Phase 13.2 — SearchRepository: interface + HTTP implementation.
//
// Wraps the generated [SearchControllerApi] for the discovery surface:
//   - searchMasters() → GET /api/v1/search/masters  (INDEPENDENT_MASTER-only,
//                        enforced backend-side in Phase 19.7 — no client-side
//                        role filtering here)
//   - searchSalons()  → GET /api/v1/search/salons
//
// Both endpoints bind a single `request` query param carrying the generated
// `MasterSearchRequest` / `SalonSearchRequest` (location nested as a
// `LocationFilter`). [_toMasterRequest] / [_toSalonRequest] translate
// [SearchFilters] → those request DTOs, forwarding the free-text `q` query, the
// allow-listed `sort` ordering, the structured location, the category, and the
// price band (master + salon).
//
// All DioExceptions are mapped to typed [Failure] subclasses via the SAME
// pattern as `service_repository.dart` (400/422 → ValidationFailure, 404 →
// NotFoundFailure, timeouts/connection → NetworkFailure, badCertificate/cancel/
// unknown → ServerFailure; an interceptor-attached Failure is preferred). No raw
// Dio types cross this boundary into the domain or presentation layers.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';

import '../domain/master_search_item.dart';
import '../domain/salon_search_item.dart';
import '../domain/search_filters.dart';
import 'search_mapper.dart';

/// Default page size for discovery search requests.
const int kSearchPageSize = 20;

/// Contract for the discovery search layer.
///
/// Every method either resolves with a [SearchPage] or throws a [Failure]
/// subclass from `core/errors/failures.dart`. Raw [DioException]s are caught
/// inside the implementation and never escape. No generated DTO type is ever
/// returned.
abstract interface class SearchRepository {
  /// Searches INDEPENDENT_MASTERs matching [filters].
  ///
  /// Wraps `GET /api/v1/search/masters`. [page] is zero-based; [size] caps the
  /// page (default [kSearchPageSize]). Returns an empty page (not a throw) when
  /// nothing matches.
  Future<SearchPage<MasterSearchItem>> searchMasters({
    required SearchFilters filters,
    required int page,
    int size = kSearchPageSize,
  });

  /// Searches salons matching [filters].
  ///
  /// Wraps `GET /api/v1/search/salons`. Forwards location, category, the
  /// free-text `q`, the `sort` ordering, and the `minPrice`/`maxPrice` band.
  /// The salon endpoint carries no rating filter, so [SearchFilters.minRating]
  /// is not forwarded here.
  Future<SearchPage<SalonSearchItem>> searchSalons({
    required SearchFilters filters,
    required int page,
    int size = kSearchPageSize,
  });
}

/// HTTP implementation of [SearchRepository].
///
/// Inject via `searchRepositoryProvider` — never construct directly.
final class HttpSearchRepository implements SearchRepository {
  HttpSearchRepository(this._searchApi);

  final SearchControllerApi _searchApi;

  static const _tag = 'feature.discovery.repository';

  @override
  Future<SearchPage<MasterSearchItem>> searchMasters({
    required SearchFilters filters,
    required int page,
    int size = kSearchPageSize,
  }) async {
    try {
      final res = await _searchApi.searchMasters(
        request: _toMasterRequest(filters, page: page, size: size),
      );
      final body = res.data?.data;
      final items =
          body?.data?.map(MasterSearchMapper.fromDto).toList(growable: false) ??
          const [];
      return SearchPage<MasterSearchItem>(
        items: items,
        page: body?.page ?? page,
        totalPages: body?.totalPages ?? 0,
        // Backend PageResponse always sends totalElements; the fallback is
        // defensive. Use 0 (honest "unknown/empty") rather than items.length,
        // which would understate a multi-page result as a single page's count.
        totalElements: body?.totalElements ?? 0,
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'searchMasters failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<SearchPage<SalonSearchItem>> searchSalons({
    required SearchFilters filters,
    required int page,
    int size = kSearchPageSize,
  }) async {
    try {
      final res = await _searchApi.searchSalons(
        request: _toSalonRequest(filters, page: page, size: size),
      );
      final body = res.data?.data;
      final items =
          body?.data?.map(SalonSearchMapper.fromDto).toList(growable: false) ??
          const [];
      return SearchPage<SalonSearchItem>(
        items: items,
        page: body?.page ?? page,
        totalPages: body?.totalPages ?? 0,
        // Backend PageResponse always sends totalElements; the fallback is
        // defensive. Use 0 (honest "unknown/empty") rather than items.length,
        // which would understate a multi-page result as a single page's count.
        totalElements: body?.totalElements ?? 0,
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'searchSalons failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  /// Builds the nested [LocationFilter], or null when neither id is present.
  ///
  /// The generated serializer omits a null builder field, so a request with no
  /// location simply carries no `location` key.
  static LocationFilter? _toLocation(SearchFilters f) {
    final cityId = f.cityId;
    final districtId = f.districtId;
    if ((cityId == null || cityId.isEmpty) &&
        (districtId == null || districtId.isEmpty)) {
      return null;
    }
    return LocationFilter(
      (b) => b
        ..cityId = (cityId == null || cityId.isEmpty) ? null : cityId
        ..districtId = (districtId == null || districtId.isEmpty)
            ? null
            : districtId,
    );
  }

  /// Normalises the free-text query for the `q` wire param: trims surrounding
  /// whitespace and collapses an empty/blank value to null (so the serializer
  /// omits the key entirely). The backend further normalises a `q` shorter than
  /// 3 chars to null server-side; the client forwards a non-empty term as-is.
  static String? _normalizeQuery(String? raw) {
    final String? trimmed = raw?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Translates [SearchFilters] → [MasterSearchRequest].
  ///
  /// Forwards the free-text `q`, the `sort` ordering, location, category, the
  /// price band, and the rating floor. Null filter fields are left unset on the
  /// builder so the serializer omits them.
  static MasterSearchRequest _toMasterRequest(
    SearchFilters f, {
    required int page,
    required int size,
  }) {
    final location = _toLocation(f);
    final category = f.categoryKey;
    final query = _normalizeQuery(f.query);
    return MasterSearchRequest((b) {
      b
        ..page = page
        ..size = size
        ..sort = MasterSearchRequestSortEnum.valueOf(f.sort.wireValue);
      if (query != null) b.q = query;
      if (location != null) b.location.replace(location);
      if (category != null && category.isNotEmpty) b.category = category;
      if (f.minPrice != null) b.minPrice = f.minPrice;
      if (f.maxPrice != null) b.maxPrice = f.maxPrice;
      if (f.minRating != null) b.minRating = f.minRating;
    });
  }

  /// Translates [SearchFilters] → [SalonSearchRequest].
  ///
  /// Forwards the free-text `q`, the `sort` ordering, location, category, and
  /// the `minPrice`/`maxPrice` band. The salon endpoint has no rating filter, so
  /// [SearchFilters.minRating] is intentionally not forwarded.
  static SalonSearchRequest _toSalonRequest(
    SearchFilters f, {
    required int page,
    required int size,
  }) {
    final location = _toLocation(f);
    final category = f.categoryKey;
    final query = _normalizeQuery(f.query);
    return SalonSearchRequest((b) {
      b
        ..page = page
        ..size = size
        ..sort = SalonSearchRequestSortEnum.valueOf(f.sort.wireValue);
      if (query != null) b.q = query;
      if (location != null) b.location.replace(location);
      if (category != null && category.isNotEmpty) b.category = category;
      if (f.minPrice != null) b.minPrice = f.minPrice;
      if (f.maxPrice != null) b.maxPrice = f.maxPrice;
    });
  }

  /// Maps a [DioException] to a typed [Failure].
  ///
  /// Mirrors `HttpServiceRepository._mapDioException`: an interceptor-attached
  /// [Failure] is preferred; otherwise the Dio type + HTTP status select the
  /// subtype. `badCertificate` is handled deliberately (not collapsed silently)
  /// as a [ServerFailure], same as the other repositories.
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
