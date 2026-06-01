// Phase 5.1 — ServiceRepository: interface, HTTP implementation, and provider.
//
// Wraps the generated [ServiceControllerApi] for the INDEPENDENT_MASTER service
// management surface:
//   - listMyServices()  → GET  /api/v1/masters/{masterId}/services
//   - getMyService(id)  → GET  /api/v1/masters/{masterId}/services (filter by id;
//                          no single-resource endpoint exists in the current API)
//   - create(input)     → POST  /api/v1/independent-masters/me/services
//   - update(defId, …)  → PATCH /api/v1/services/{serviceDefId}
//                          (generated updateServiceDefinition; keyed on the
//                           service-definition id, NOT the assignment id)
//   - deactivate(defId) → DELETE /api/v1/services/{serviceDefId}
//                          (keyed on the service-definition id)
//
// The [masterId] required by [getMasterServices] is resolved from
// [masterProfileProvider] at provider construction time — this is the
// Master-row UUID (from MasterDetailResponse.masterId), NOT the User UUID
// from the auth session. User.id != Master.id; using the wrong UUID caused
// GET /api/v1/masters/{masterId}/services to always return [].
//
// All DioExceptions are mapped to typed [Failure] subclasses. No raw Dio
// types cross this boundary into the domain or presentation layers.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
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

  /// Partially updates an existing service identified by its
  /// service-definition id ([serviceDefId]).
  ///
  /// Wraps `PATCH /api/v1/services/{serviceDefId}`. [serviceDefId] MUST be
  /// [MasterService.serviceDefId] (the underlying service-definition UUID), NOT
  /// [MasterService.id] (the assignment UUID) — the backend keys this endpoint
  /// on the definition and a wrong id yields a 404 ("Запис не знайдено").
  ///
  /// Only fields present in [patch] (non-null) are sent; absent fields are left
  /// unchanged on the backend. [assignmentId] is carried through onto the
  /// returned [MasterService.id] (the PATCH response omits the assignment id).
  /// Returns the updated [MasterService].
  Future<MasterService> update(
    String serviceDefId,
    MasterServiceUpdate patch, {
    required String assignmentId,
  });

  /// Deactivates (soft-deletes) a service identified by its service-definition
  /// id ([serviceDefId]).
  ///
  /// Wraps `DELETE /api/v1/services/{serviceDefId}`. [serviceDefId] MUST be
  /// [MasterService.serviceDefId] (the underlying service-definition UUID), NOT
  /// [MasterService.id] (the assignment UUID) — the backend keys this endpoint
  /// on the definition and a wrong id fails to resolve/authorise. The backend
  /// marks the service inactive rather than removing it. Calling this method
  /// twice is idempotent — a 200 on either call resolves without throwing.
  Future<void> deactivate(String serviceDefId);

  /// Returns the list of approved service categories for the picker.
  ///
  /// Wraps `GET /api/v1/service-categories/approved` (authenticated). Each
  /// option carries the wire [ServiceCategoryOption.name] (sent to the
  /// backend) and the Ukrainian [ServiceCategoryOption.displayName] (shown to
  /// the user). Returns an empty list when no categories are approved.
  Future<List<ServiceCategoryOption>> fetchApprovedCategories();

  /// Submits a request to add a new service category for admin review.
  ///
  /// Wraps `POST /api/v1/service-categories/requests` (authenticated;
  /// master/owner/admin only). The new category is created in a PENDING state
  /// and approved out-of-band by an admin — it does NOT immediately appear in
  /// [fetchApprovedCategories].
  ///
  /// - [name]: uppercase wire slug matching `^[A-Z][A-Z0-9_]*$` (≤50 chars).
  /// - [displayName]: non-blank Ukrainian label (≤100 chars).
  ///
  /// Throws:
  ///   - [CategoryAlreadyExistsFailure] on **409** (already exists/pending).
  ///   - [CategoryRequestThrottledFailure] on **429** (rate-limited, 5/hr).
  ///   - [ValidationFailure] on **400/422** (malformed name/displayName).
  Future<void> requestCategory({
    required String name,
    required String displayName,
  });
}

/// HTTP implementation of [ServiceRepository].
///
/// Inject via [serviceRepositoryProvider] — never construct directly.
///
/// [_serviceApi] drives all generated-API calls (list/create/update/deactivate).
/// [_masterId] is resolved from the authenticated session at provider
/// construction time and used as the path parameter for list/get operations.
final class HttpServiceRepository implements ServiceRepository {
  HttpServiceRepository({
    required ServiceControllerApi serviceApi,
    required CategoryRequestControllerApi categoryApi,
    required String masterId,
  }) : _serviceApi = serviceApi,
       _categoryApi = categoryApi,
       _masterId = masterId;

  final ServiceControllerApi _serviceApi;
  final CategoryRequestControllerApi _categoryApi;
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
  Future<MasterService> update(
    String serviceDefId,
    MasterServiceUpdate patch, {
    required String assignmentId,
  }) async {
    _assertAuthenticated();
    final request = MasterServiceMapper.toUpdateRequest(patch);
    try {
      // PATCH /api/v1/services/{serviceDefId} — the backend's update endpoint
      // keys on the service-definition id, NOT the assignment id. Uses the
      // generated client (UpdateServiceDefinitionRequest now exists after the
      // OpenAPI regen), so no hand-written Dio path is needed.
      final res = await _serviceApi.updateServiceDefinition(
        serviceDefId: serviceDefId,
        updateServiceDefinitionRequest: request,
      );
      // The update endpoint returns a ServiceDefinitionResponse (not a
      // MasterServiceResponse) — it carries no assignment id, so we thread the
      // original assignmentId through to keep MasterService.id stable.
      final dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'update: response data is null for serviceDefId=$serviceDefId',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return MasterServiceMapper.fromServiceDefinitionDto(
        dto,
        assignmentId: assignmentId,
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'update failed: ${e.type} ${e.response?.statusCode} '
          'serviceDefId=$serviceDefId',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> deactivate(String serviceDefId) async {
    _assertAuthenticated();
    try {
      // DELETE /api/v1/services/{serviceDefId} — keyed on the service-definition
      // id, NOT the assignment id.
      await _serviceApi.deactivateServiceDefinition(serviceDefId: serviceDefId);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'deactivate failed: ${e.type} ${e.response?.statusCode} '
          'serviceDefId=$serviceDefId',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<List<ServiceCategoryOption>> fetchApprovedCategories() async {
    try {
      final res = await _categoryApi.listApproved();
      final list = res.data?.data;
      if (list == null) {
        if (kDebugMode) {
          log(
            'fetchApprovedCategories: '
            'ApiResponseListApprovedCategoryResponse.data is null',
            name: _tag,
            level: 1000,
          );
        }
        return const [];
      }
      return MasterServiceMapper.fromApprovedCategoryList(list);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'fetchApprovedCategories failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> requestCategory({
    required String name,
    required String displayName,
  }) async {
    try {
      final request = CreateCategoryRequestRequest(
        (b) => b
          ..name = name
          ..displayName = displayName,
      );
      await _categoryApi.submitRequest(createCategoryRequestRequest: request);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'requestCategory failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapCategoryRequestException(e);
    }
  }

  /// Maps a [DioException] from `POST /service-categories/requests` to a typed
  /// [Failure], distinguishing the two category-specific HTTP statuses:
  ///   - **409** → [CategoryAlreadyExistsFailure] (already exists/pending).
  ///   - **429** → [CategoryRequestThrottledFailure] (rate-limited, 5/hr).
  /// All other statuses defer to the shared [_mapDioException].
  ///
  /// The 409/429 status checks run BEFORE deferring to any [Failure] already
  /// attached by [ErrorMapperInterceptor]. The interceptor maps a non-auth
  /// 409 to a generic [ServerFailure] and an unmatched 429 to
  /// [UnknownFailure] — neither of which carries the category-specific copy —
  /// so we re-map by status code here to surface the friendly messages.
  Failure _mapCategoryRequestException(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 409) return CategoryAlreadyExistsFailure(cause: e);
    if (statusCode == 429) return CategoryRequestThrottledFailure(cause: e);
    if (e.error is Failure) return e.error as Failure;
    return _mapDioException(e);
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
/// the generated [ServiceControllerApi], and the current master's UUID from
/// [masterProfileProvider].
///
/// IMPORTANT: [_masterId] must be the Master-row UUID
/// (from MasterDetailResponse.masterId), NOT the User UUID from the auth
/// session. User.id != Master.id. The list endpoint
/// `GET /api/v1/masters/{masterId}/services` matches against the masters table
/// primary key; passing a user UUID always returns [].
///
/// Both this provider and [masterProfileProvider] are [keepAlive: true], so
/// the watch is stable. The repository is re-created whenever the master
/// profile loads or changes (e.g. on first login after the profile resolves).
///
/// Override in tests with a mocktail mock — never construct
/// [HttpServiceRepository] directly in production or test code.
@Riverpod(keepAlive: true)
ServiceRepository serviceRepository(Ref ref) {
  // masterId is the Master-row UUID (from MasterDetailResponse.masterId),
  // NOT the User UUID from the auth session. User.id != Master.id.
  // AsyncValue.value returns null when loading/error; ?? '' keeps the
  // _assertAuthenticated() guard intact until the profile resolves.
  // masterProfileProvider is also keepAlive: true, so this watch is stable.
  final masterId = ref.watch(masterProfileProvider).value?.id ?? '';
  return HttpServiceRepository(
    serviceApi: ref.watch(serviceApiProvider),
    categoryApi: ref.watch(categoryRequestApiProvider),
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

/// Provides the generated [CategoryRequestControllerApi] singleton.
///
/// Drives the approved-category picker (`GET /service-categories/approved`)
/// and the suggestion submission (`POST /service-categories/requests`). Same
/// authenticated Dio + serializers as the other API providers. Kept alive to
/// avoid re-construction on every provider read.
@Riverpod(keepAlive: true)
CategoryRequestControllerApi categoryRequestApi(Ref ref) =>
    CategoryRequestControllerApi(ref.watch(dioProvider), standardSerializers);

/// Async list of approved service categories for the service-form picker.
///
/// Watched by the category chip selector in `service_form.dart`. The list is
/// small and changes rarely, so the provider is [keepAlive: true] — it is
/// fetched once and shared across the create and edit screens for the lifetime
/// of the app session.
///
/// NOT invalidated after a successful [ServiceRepository.requestCategory]: a
/// freshly-requested category is PENDING admin review, not yet approved, so it
/// must not appear in the picker until an admin approves it out-of-band.
///
/// On error, the picker row shows a compact retry affordance that calls
/// `ref.invalidate(approvedCategoriesProvider)` — the rest of the form stays
/// usable (category is optional).
@Riverpod(keepAlive: true)
Future<List<ServiceCategoryOption>> approvedCategories(Ref ref) {
  return ref.watch(serviceRepositoryProvider).fetchApprovedCategories();
}
