// Phase 13.x (Variant A «Рейка + послуги») — CategoryServiceRepository.
//
// Wraps the generated [ServiceCatalogControllerApi] for the second level of the
// search rail: given a platform-category slug, returns the bookable SERVICE
// TYPES inside it as [CategoryServiceOption]s for the «Послуги · {category}»
// chip drawer.
//
//   - fetchServices(categoryName) → GET /api/v1/service-types?categoryName=…
//     (public; items ordered nameUk ASC backend-side)
//
// All DioExceptions are mapped to typed [Failure] subclasses via the SAME
// pattern as `search_repository.dart` / `service_repository.dart` (400/422 →
// ValidationFailure, 404 → NotFoundFailure, timeouts/connection →
// NetworkFailure, badCertificate/cancel/unknown → ServerFailure; an
// interceptor-attached Failure is preferred). No raw Dio types and no generated
// DTO types cross this boundary into the domain or presentation layers.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';

import '../domain/category_service_option.dart';

/// Contract for the per-category service-type lookup.
///
/// Resolves with a (possibly empty) list of [CategoryServiceOption] or throws a
/// [Failure] subclass from `core/errors/failures.dart`. Raw [DioException]s are
/// caught inside the implementation and never escape. No generated DTO type is
/// ever returned.
abstract interface class CategoryServiceRepository {
  /// Returns the bookable service types within the platform category identified
  /// by [categoryName] (the platform-category slug, e.g. `HAIR`, `EYELASH`).
  ///
  /// Wraps `GET /api/v1/service-types?categoryName=…`. Returns an empty list
  /// (not a throw) when the category has no service types.
  Future<List<CategoryServiceOption>> fetchServices(String categoryName);
}

/// HTTP implementation of [CategoryServiceRepository].
///
/// Inject via `categoryServiceRepositoryProvider` — never construct directly.
final class HttpCategoryServiceRepository implements CategoryServiceRepository {
  HttpCategoryServiceRepository(this._catalogApi);

  final ServiceCatalogControllerApi _catalogApi;

  static const _tag = 'feature.discovery.repository';

  @override
  Future<List<CategoryServiceOption>> fetchServices(String categoryName) async {
    try {
      final res = await _catalogApi.getServiceTypesByPlatformCategory(
        categoryName: categoryName,
      );
      final list = res.data?.data;
      if (list == null) {
        return const <CategoryServiceOption>[];
      }
      return list
          .map(
            (PlatformServiceTypeResponse dto) => CategoryServiceOption(
              key: dto.slug ?? '',
              displayName: dto.nameUk ?? '',
            ),
          )
          // Defensive: drop any malformed row missing both slug and label so a
          // bad item can never produce an unkeyable / blank chip.
          .where((o) => o.key.isNotEmpty && o.displayName.isNotEmpty)
          .toList(growable: false);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        // Log the failure shape only (type + status) — never the response body
        // (the catalog is curated/non-PII, but the feature's logging discipline
        // keeps payloads out of logs regardless).
        log(
          'fetchServices failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  /// Maps a [DioException] to a typed [Failure].
  ///
  /// Mirrors `HttpSearchRepository._mapDioException`: an interceptor-attached
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
