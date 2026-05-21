// TODO(phase-3.2): replace hand-written DTOs with generated LocationApi.
//
// Phase 2.18 — LocationRepository (hand-written Dio).
//
// The OpenAPI codegen for `lib/api/` is deferred to Phase 3.1/3.2, so there is
// no generated `LocationApi` yet. This repository talks to the backend's
// public `/locations/*` read endpoints directly through the singleton
// [dioProvider] Dio — mirroring [HttpAuthRepository]'s envelope handling.
//
// The `/locations/*` endpoints are PUBLIC reads (no auth required), but we
// reuse [dioProvider] anyway for the shared base URL (`…/api/v1`) and the
// ErrorMapper interceptor that converts DioException → typed [Failure]. The
// AuthInterceptor harmlessly skips attaching a token when none is stored.
//
// Backend response envelope for all endpoints:
//   { "success": bool, "data": T, "message": String }
// This class extracts the payload from `response.data['data']`, then maps each
// element through the domain `fromResponse` mapper at the repository boundary.
//
// Live backend contract (verified):
//   GET /locations/oblasts                       -> List<OblastResponse>
//   GET /locations/oblasts/{oblastId}/cities     -> List<CityResponse>   (UUID)
//   GET /locations/cities/{cityId}/districts     -> List<CityDistrictResponse> (UUID)

import 'dart:developer';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/city.dart';
import '../domain/city_district.dart';
import '../domain/oblast.dart';

part 'location_repository.g.dart';

/// Contract for the locality reference-data layer.
///
/// Every method either resolves with the requested list or throws a [Failure]
/// subclass from `core/errors/failures.dart`. Raw [DioException]s are caught
/// inside the implementation and never escape.
abstract interface class LocationRepository {
  /// Fetches all Ukrainian oblasts (first cascade level).
  Future<List<Oblast>> fetchOblasts();

  /// Fetches the cities of the oblast identified by [oblastId] (a UUID).
  Future<List<City>> fetchCities(String oblastId);

  /// Fetches the urban districts of the city identified by [cityId] (a UUID).
  ///
  /// Only called when `City.hasDistricts == true`; for cities without
  /// districts the cascade shows a disabled helper row and never reaches here.
  Future<List<CityDistrict>> fetchDistricts(String cityId);
}

/// HTTP implementation of [LocationRepository].
///
/// Inject via [locationRepositoryProvider] — never construct directly.
final class HttpLocationRepository implements LocationRepository {
  HttpLocationRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<Oblast>> fetchOblasts() => _fetchList(
    path: '/locations/oblasts',
    mapper: Oblast.fromResponse,
    operation: 'fetchOblasts',
  );

  @override
  Future<List<City>> fetchCities(String oblastId) => _fetchList(
    path: '/locations/oblasts/$oblastId/cities',
    mapper: City.fromResponse,
    operation: 'fetchCities',
  );

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) => _fetchList(
    path: '/locations/cities/$cityId/districts',
    mapper: CityDistrict.fromResponse,
    operation: 'fetchDistricts',
  );

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Shared GET → envelope-unwrap → list-map pipeline for all three endpoints.
  ///
  /// [mapper] converts a single raw element map to its domain model. Any
  /// [DioException] is mapped to a typed [Failure]; a malformed envelope
  /// (missing or non-list `data`) surfaces as [UnknownFailure].
  Future<List<T>> _fetchList<T>({
    required String path,
    required T Function(Map<String, dynamic>) mapper,
    required String operation,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(path);
      final data = response.data?['data'];
      if (data is! List) {
        throw const UnknownFailure(
          cause: 'locations response missing a "data" list',
        );
      }
      return data
          .cast<Map<String, dynamic>>()
          .map(mapper)
          .toList(growable: false);
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          '$operation failed: ${e.type} ${e.response?.statusCode}',
          name: 'location.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  /// Maps a [DioException] to a typed [Failure].
  ///
  /// If [ErrorMapperInterceptor] has already attached a [Failure] as
  /// `e.error`, that value is re-thrown directly; otherwise the Dio type is
  /// inspected so connectivity issues surface as [NetworkFailure] and
  /// everything else as [ServerFailure]. Raw [DioException] never escapes.
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

/// Provides the [LocationRepository] singleton used by the locality providers.
///
/// Returns [HttpLocationRepository] backed by the authenticated [dioProvider].
/// Override in tests with a mocktail mock — never construct
/// [HttpLocationRepository] directly in tests.
@Riverpod(keepAlive: true)
LocationRepository locationRepository(Ref ref) =>
    HttpLocationRepository(ref.watch(dioProvider));
