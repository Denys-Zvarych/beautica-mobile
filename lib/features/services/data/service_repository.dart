// Phase 5.1 — ServiceRepository: interface, HTTP implementation, and provider.
//
// Wraps the generated [ServiceControllerApi] for the INDEPENDENT_MASTER service
// management surface:
//   - listMyServices()  → GET  /api/v1/masters/{masterId}/services
//   - getMyService(id)  → GET  /api/v1/masters/{masterId}/services (filter by id;
//                          no single-resource endpoint exists in the current API)
//   - create(input)     → POST /api/v1/independent-masters/me/services
//   - update(id, patch) → PATCH /api/v1/independent-masters/me/services/{id}
//                          (hand-written; no generated update request exists)
//   - deactivate(id)    → DELETE /api/v1/services/{id}
//
// The [masterId] required by [getMasterServices] is resolved from the
// authenticated session at provider construction time via [authProvider] so
// the repository interface remains parameter-free for list/get operations.
// This mirrors how [MasterProfileNotifier] resolves the user ID.
//
// All DioExceptions are mapped to typed [Failure] subclasses. No raw Dio
// types cross this boundary into the domain or presentation layers.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'master_service_mapper.dart';

part 'service_repository.g.dart';

/// Contract for the service management layer.
///
/// Every method either resolves successfully or throws a [Failure] subclass
/// from `core/errors/failures.dart`. Raw [DioException]s are caught inside
/// the implementation and never escape.
abstract interface class ServiceRepository {
  /// Returns the full list of services configured for the authenticated master.
  ///
  /// Wraps `GET /api/v1/masters/{masterId}/services`. Returns an empty list
  /// when the master has no services configured.
  Future<List<MasterService>> listMyServices();

  /// Returns a single service by its assignment [id].
  ///
  /// Fetches the full list and filters client-side (no single-resource
  /// endpoint in the current API). Throws [NotFoundFailure] when the
  /// requested [id] is absent from the list.
  Future<MasterService> getMyService(String id);

  /// Creates a new service for the authenticated master.
  ///
  /// Wraps `POST /api/v1/independent-masters/me/services`. Returns the
  /// newly-created [MasterService] as mapped from the backend response.
  Future<MasterService> create(MasterServiceCreate input);

  /// Partially updates an existing service identified by [id].
  ///
  /// Wraps `PATCH /api/v1/independent-masters/me/services/{id}`. Only fields
  /// present in [patch] (non-null) are sent; absent fields are left unchanged
  /// on the backend. Returns the updated [MasterService].
  Future<MasterService> update(String id, MasterServiceUpdate patch);

  /// Deactivates (soft-deletes) a service identified by [id].
  ///
  /// Wraps `DELETE /api/v1/services/{id}`. The backend marks the service as
  /// inactive rather than removing it. Calling this method twice is
  /// idempotent — a 200 on either call resolves without throwing.
  Future<void> deactivate(String id);
}

/// HTTP implementation of [ServiceRepository].
///
/// Inject via [serviceRepositoryProvider] — never construct directly.
///
/// [_serviceApi] drives all generated-API calls. [_dio] drives the hand-
/// written PATCH update call (no generated update request DTO exists).
/// [_masterId] is resolved from the authenticated session at provider
/// construction time and used as the path parameter for list/get operations.
final class HttpServiceRepository implements ServiceRepository {
  HttpServiceRepository({
    required ServiceControllerApi serviceApi,
    required Dio dio,
    required String masterId,
  }) : _serviceApi = serviceApi,
       _dio = dio,
       _masterId = masterId;

  final ServiceControllerApi _serviceApi;
  final Dio _dio;
  final String _masterId;

  static const _tag = 'feature.services.repository';

  /// Throws [UnauthorizedFailure] immediately if [_masterId] is empty.
  ///
  /// An empty masterId means the auth session is not [Authenticated]. Letting
  /// the call proceed would produce a malformed URL
  /// (`/api/v1/masters//services`) and an opaque [NotFoundFailure]. Failing
  /// fast here surfaces the real cause to callers.
  void _assertAuthenticated() {
    if (_masterId.isEmpty) {
      throw const UnauthorizedFailure();
    }
  }

  @override
  Future<List<MasterService>> listMyServices() async {
    _assertAuthenticated();
    try {
      final res = await _serviceApi.getMasterServices(masterId: _masterId);
      final list = res.data?.data;
      if (list == null) {
        if (kDebugMode) {
          log(
            'listMyServices: ApiResponseListMasterServiceResponse.data is null',
            name: _tag,
            level: 1000,
          );
        }
        return const [];
      }
      return list.map(MasterServiceMapper.fromDto).toList(growable: false);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'listMyServices failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<MasterService> getMyService(String id) async {
    _assertAuthenticated();
    final services = await listMyServices();
    final match = services.where((s) => s.id == id).firstOrNull;
    if (match == null) {
      throw const NotFoundFailure();
    }
    return match;
  }

  @override
  Future<MasterService> create(MasterServiceCreate input) async {
    _assertAuthenticated();
    try {
      final request = MasterServiceMapper.toCreateRequest(input);
      final res = await _serviceApi.addIndependentMasterService(
        createServiceDefinitionRequest: request,
      );
      final dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'create: ApiResponseMasterServiceResponse.data is null',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return MasterServiceMapper.fromDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'create failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<MasterService> update(String id, MasterServiceUpdate patch) async {
    _assertAuthenticated();
    final body = MasterServiceMapper.toUpdateBody(patch);
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/api/v1/independent-masters/me/services/$id',
        data: body,
      );
      // The backend returns the updated MasterServiceResponse in the standard
      // `{success, data}` envelope. Deserialise the inner `data` map directly
      // using the generated built_value serializer + StandardJsonPlugin — this
      // avoids a second GET round-trip (perf finding P1-1).
      final dataMap = res.data?['data'] as Map<String, dynamic>?;
      if (dataMap == null) {
        if (kDebugMode) {
          log(
            'update: PATCH response data is null for id=$id',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      final dto = standardSerializers.deserializeWith(
        MasterServiceResponse.serializer,
        dataMap,
      );
      if (dto == null) {
        if (kDebugMode) {
          log(
            'update: deserializeWith returned null for id=$id',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return MasterServiceMapper.fromDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'update failed: ${e.type} ${e.response?.statusCode} id=$id',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> deactivate(String id) async {
    _assertAuthenticated();
    try {
      await _serviceApi.deactivateServiceDefinition(serviceDefId: id);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'deactivate failed: ${e.type} ${e.response?.statusCode} id=$id',
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
  /// If [ErrorMapperInterceptor] has already attached a [Failure] as `e.error`,
  /// that instance is re-thrown directly. Otherwise the Dio exception type and
  /// HTTP status code are inspected to produce the most appropriate subtype.
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

/// Provides the [ServiceRepository] singleton backed by the authenticated Dio,
/// the generated [ServiceControllerApi], and the current user's ID from the
/// auth session.
///
/// The provider re-creates the repository whenever the auth session changes
/// (e.g. after login or logout) so the [_masterId] is always current.
///
/// Override in tests with a mocktail mock — never construct
/// [HttpServiceRepository] directly in production or test code.
@Riverpod(keepAlive: true)
ServiceRepository serviceRepository(Ref ref) {
  final session = ref.watch(authProvider).value;
  final masterId = switch (session) {
    Authenticated(:final user) => user.id,
    _ => '',
  };
  return HttpServiceRepository(
    serviceApi: ref.watch(serviceApiProvider),
    dio: ref.watch(dioProvider),
    masterId: masterId,
  );
}

/// Provides the generated [ServiceControllerApi] singleton.
///
/// Same Dio instance and serializers as the other API providers in
/// `core/network/api_client_provider.dart`. Kept alive to avoid re-construction
/// on every provider read.
@Riverpod(keepAlive: true)
ServiceControllerApi serviceApi(Ref ref) =>
    ServiceControllerApi(ref.watch(dioProvider), standardSerializers);
