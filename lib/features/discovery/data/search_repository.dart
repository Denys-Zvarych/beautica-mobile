// Phase 13.2 — SearchRepository: interface + HTTP implementation.
//
// Issues the discovery searches against:
//   - searchMasters() → GET /api/v1/search/masters  (INDEPENDENT_MASTER-only,
//                        enforced backend-side in Phase 19.7 — no client-side
//                        role filtering here)
//   - searchSalons()  → GET /api/v1/search/salons
//
// WIRE-FORMAT FIX (bug: city/all filters silently dropped):
//   The backend binds `@ModelAttribute MasterSearchRequest` / `SalonSearchRequest`
//   (SearchController.java:84/113) which expects FLAT dot-notation query params:
//     location.cityId=<uuid>&location.districtId=<uuid>&q=…&category=…
//     &sort=RATING_DESC&minPrice=…&maxPrice=…&minRating=…&page=0&size=20
//   The OpenAPI-generated `SearchControllerApi.searchMasters/searchSalons`
//   serialised the WHOLE request DTO as a single object query param named
//   `request`, which Dio bracket-nests to `request[location][cityId]=…`. Those
//   bracketed keys do NOT bind to the @ModelAttribute record → request arrived
//   all-null → backend ran an unfiltered all-regions search and returned 200.
//   We therefore bypass the generated object-query encoding and issue the GET
//   directly through the shared authenticated [Dio] with an explicit FLAT
//   `Map<String, dynamic>`. The response is still deserialized through the same
//   generated `standardSerializers`, so parsing into the domain models is
//   unchanged. See [_toMasterQuery] / [_toSalonQuery] for the flat mapping.
//
// All DioExceptions are mapped to typed [Failure] subclasses via the SAME
// pattern as `service_repository.dart` (400/422 → ValidationFailure, 404 →
// NotFoundFailure, timeouts/connection → NetworkFailure, badCertificate/cancel/
// unknown → ServerFailure; an interceptor-attached Failure is preferred). No raw
// Dio types cross this boundary into the domain or presentation layers.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:built_value/serializer.dart';
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
  ///
  /// [cancelToken] lets the caller abort a request that has been SUPERSEDED —
  /// live search re-keys the results provider on every settled term, and without
  /// this the obsolete socket runs to completion (see the `cancelToken` note on
  /// [HttpSearchRepository]).
  Future<SearchPage<MasterSearchItem>> searchMasters({
    required SearchFilters filters,
    required int page,
    int size = kSearchPageSize,
    CancelToken? cancelToken,
  });

  /// Searches salons matching [filters].
  ///
  /// Wraps `GET /api/v1/search/salons`. Forwards location, category, the
  /// free-text `q`, the `sort` ordering, and the `minPrice`/`maxPrice` band.
  /// The salon endpoint carries no rating filter, so [SearchFilters.minRating]
  /// is not forwarded here.
  ///
  /// [cancelToken] behaves exactly as on [searchMasters].
  Future<SearchPage<SalonSearchItem>> searchSalons({
    required SearchFilters filters,
    required int page,
    int size = kSearchPageSize,
    CancelToken? cancelToken,
  });
}

/// HTTP implementation of [SearchRepository].
///
/// Inject via `searchRepositoryProvider` — never construct directly.
///
/// Issues the GET directly through the shared authenticated [Dio] with a FLAT
/// dot-notation query map (see the file header for the wire-format fix) rather
/// than the generated `SearchControllerApi`, whose object-query encoding
/// bracket-nests the params and silently drops every filter server-side. The
/// generated `standardSerializers` is still used to deserialize the response
/// envelope, so domain-model parsing is unchanged.
///
/// CANCELLATION (perf/sec MEDIUM-1). Both methods accept an optional
/// [CancelToken] which is forwarded verbatim to Dio. The discovery results
/// notifier creates one per family member and cancels it from `ref.onDispose`,
/// so a search superseded by the next settled keystroke aborts its two in-flight
/// GETs instead of running them to completion and discarding the payload. A
/// cancelled request raises `DioExceptionType.cancel`, which [_mapDioException]
/// maps to a [ServerFailure] like any other transport fault — it never reaches
/// the UI, because Riverpod drops the result of a disposed/recomputed provider's
/// future (see the notifier's cancellation note).
final class HttpSearchRepository implements SearchRepository {
  HttpSearchRepository(this._dio, this._serializers);

  final Dio _dio;
  final Serializers _serializers;

  static const _tag = 'feature.discovery.repository';

  static const _mastersPath = '/api/v1/search/masters';
  static const _salonsPath = '/api/v1/search/salons';

  @override
  Future<SearchPage<MasterSearchItem>> searchMasters({
    required SearchFilters filters,
    required int page,
    int size = kSearchPageSize,
    CancelToken? cancelToken,
  }) async {
    try {
      final res = await _dio.get<Object>(
        _mastersPath,
        queryParameters: _toMasterQuery(filters, page: page, size: size),
        cancelToken: cancelToken,
      );
      final envelope = _deserialize<ApiResponsePageResponseMasterSearchResult>(
        res.data,
        const FullType(ApiResponsePageResponseMasterSearchResult),
        res,
      );
      final body = envelope?.data;
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
    CancelToken? cancelToken,
  }) async {
    try {
      final res = await _dio.get<Object>(
        _salonsPath,
        queryParameters: _toSalonQuery(filters, page: page, size: size),
        cancelToken: cancelToken,
      );
      final envelope = _deserialize<ApiResponsePageResponseSalonSearchResult>(
        res.data,
        const FullType(ApiResponsePageResponseSalonSearchResult),
        res,
      );
      final body = envelope?.data;
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

  /// Deserializes a Dio response body into the generated envelope [T] using the
  /// same `standardSerializers` the generated client uses. Mirrors the
  /// generated client's failure path: a deserialization error is rethrown as a
  /// [DioException] so it maps to a [ServerFailure] like any other parse fault.
  T? _deserialize<T>(Object? raw, FullType type, Response<Object> res) {
    if (raw == null) return null;
    try {
      return _serializers.deserialize(raw, specifiedType: type) as T;
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Normalises the free-text query for the `q` wire param: trims surrounding
  /// whitespace and collapses an empty/blank value to null (so the key is
  /// omitted).
  ///
  /// A below-minimum term never gets this far: [SearchFilters.query] only ever
  /// holds null or a term of at least [kSearchMinQueryLength] characters (the
  /// presentation controller holds anything shorter — see
  /// `SearchFiltersController.setQuery`). Should one arrive anyway (a stale
  /// `extra`, a deep link), it is forwarded as-is and the backend answers with
  /// an empty page plus a "type at least 3 characters" envelope message; that
  /// degrades cleanly into the existing `ResultsEmpty` state, so no extra
  /// handling is needed here.
  static String? _normalizeQuery(String? raw) {
    final String? trimmed = raw?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Adds the structured location keys (`location.cityId` / `location.districtId`)
  /// to [q] when present. Empty/blank ids are skipped so the key is omitted,
  /// matching the backend's "null id = no filter" semantics.
  static void _addLocation(Map<String, dynamic> q, SearchFilters f) {
    final cityId = f.cityId;
    final districtId = f.districtId;
    if (cityId != null && cityId.isNotEmpty) {
      q['location.cityId'] = cityId;
    }
    if (districtId != null && districtId.isNotEmpty) {
      q['location.districtId'] = districtId;
    }
  }

  /// Adds the per-service `serviceTypeSlugs` constraint to [q] when present.
  ///
  /// Emits the slug set as a SORTED `List<String>` value: Dio's default
  /// `ListFormat.multi` renders it as repeated bare params
  /// (`serviceTypeSlugs=a&serviceTypeSlugs=b`), which the backend
  /// `@ModelAttribute List<String> serviceTypeSlugs` binds (OR / union
  /// semantics — the provider must offer ANY of the slugs). Sorting makes the
  /// assembled URI
  /// deterministic (stable transport tests); order is irrelevant to the
  /// backend. Omitted entirely when the set is empty (no constraint).
  static void _addServiceTypeSlugs(Map<String, dynamic> q, SearchFilters f) {
    final Set<String> slugs = f.serviceTypeSlugs;
    if (slugs.isEmpty) return;
    q['serviceTypeSlugs'] = slugs.toList(growable: false)..sort();
  }

  /// Builds the FLAT `@ModelAttribute`-bindable query map for the masters
  /// endpoint. Keys mirror the backend `MasterSearchRequest` record field names
  /// (`q`, `category`, `location.cityId`, `location.districtId`, `sort`,
  /// `minPrice`, `maxPrice`, `minRating`, `page`, `size`). Null/blank filter
  /// fields are omitted entirely so the backend treats them as "no constraint".
  static Map<String, dynamic> _toMasterQuery(
    SearchFilters f, {
    required int page,
    required int size,
  }) {
    final category = f.categoryKey;
    final query = _normalizeQuery(f.query);
    final q = <String, dynamic>{
      'page': page,
      'size': size,
      // sort is never null (SearchFilters defaults to ratingDesc); the enum
      // wireValue is the exact backend SearchSort constant name.
      'sort': f.sort.wireValue,
    };
    _addLocation(q, f);
    _addServiceTypeSlugs(q, f);
    if (query != null) q['q'] = query;
    if (category != null && category.isNotEmpty) q['category'] = category;
    if (f.minPrice != null) q['minPrice'] = f.minPrice.toString();
    if (f.maxPrice != null) q['maxPrice'] = f.maxPrice.toString();
    if (f.minRating != null) q['minRating'] = f.minRating.toString();
    return q;
  }

  /// Builds the FLAT `@ModelAttribute`-bindable query map for the salons
  /// endpoint. Mirrors [_toMasterQuery] minus `minRating` — the backend
  /// `SalonSearchRequest` record has no rating filter, so
  /// [SearchFilters.minRating] is intentionally not forwarded.
  static Map<String, dynamic> _toSalonQuery(
    SearchFilters f, {
    required int page,
    required int size,
  }) {
    final category = f.categoryKey;
    final query = _normalizeQuery(f.query);
    final q = <String, dynamic>{
      'page': page,
      'size': size,
      'sort': f.sort.wireValue,
    };
    _addLocation(q, f);
    _addServiceTypeSlugs(q, f);
    if (query != null) q['q'] = query;
    if (category != null && category.isNotEmpty) q['category'] = category;
    if (f.minPrice != null) q['minPrice'] = f.minPrice.toString();
    if (f.maxPrice != null) q['maxPrice'] = f.maxPrice.toString();
    return q;
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
