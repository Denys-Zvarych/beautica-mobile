// Phase 5.1 — ServiceRepository: interface, HTTP implementation, and provider.
//
// Wraps the generated [ServiceControllerApi] for the INDEPENDENT_MASTER service
// management surface:
//   - listMyServices()  → GET  /api/v1/independent-masters/me/services
//                          (Phase 16.9 — authenticated owner endpoint; derives
//                           the master from the JWT principal and INCLUDES
//                           drafts. The public GET /masters/{masterId}/services
//                           still exists for public-browse but is no longer
//                           used here because it filters drafts out.)
//   - getMyService(id)  → GET  /api/v1/independent-masters/me/services (filter by id;
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
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'master_service_mapper.dart';
import 'service_type_mapper.dart';

part 'service_repository.g.dart';

/// Contract for the service management layer.
///
/// Every method either resolves successfully or throws a [Failure] subclass
/// from `core/errors/failures.dart`. Raw [DioException]s are caught inside
/// the implementation and never escape.
abstract interface class ServiceRepository {
  /// Returns the full list of services configured for the authenticated master.
  ///
  /// Wraps `GET /api/v1/independent-masters/me/services` — the authenticated
  /// owner endpoint, master derived from the JWT principal. Returns an empty
  /// list when the master has no services configured — but ONLY for a
  /// well-formed empty array. A 200 whose envelope carries a null `data`
  /// throws [ServerFailure]: a malformed success must never be presentable as
  /// an empty catalogue.
  Future<List<MasterService>> listMyServices();

  /// Returns a single service by its assignment [id].
  ///
  /// Fetches the full list and filters client-side (no single-resource
  /// endpoint in the current API). Throws [NotFoundFailure] when the
  /// requested [id] is absent from the list.
  Future<MasterService> getMyService(String id);

  /// Returns the active services for an arbitrary [masterId] (public browse).
  ///
  /// Wraps the PUBLIC `GET /api/v1/masters/{masterId}/services` endpoint (drafts
  /// are filtered out server-side). Unlike [listMyServices] this takes the
  /// target master as a parameter and does NOT require the caller to be that
  /// master, so it is safe to call from a CLIENT session — it drives the
  /// services stat tile and the read-only service-categories section on the
  /// client-facing public master profile (Phase 13.5).
  /// Returns an empty list when the master has no active services — but ONLY
  /// for a well-formed empty array; a 200 with a null `data` envelope throws
  /// [ServerFailure], exactly as [listMyServices] does.
  Future<List<MasterService>> getMasterServices(String masterId);

  /// Creates a new service for the authenticated master.
  ///
  /// Wraps `POST /api/v1/independent-masters/me/services`. Returns the
  /// newly-created [MasterService] as mapped from the backend response.
  Future<MasterService> create(MasterServiceCreate input);

  /// Creates ALL of [items] in one request for the authenticated master.
  ///
  /// Wraps `POST /api/v1/independent-masters/me/services/bulk` — the one-pass
  /// multi-select setup endpoint. **Additive** since `beautica-backend` c5e420f:
  /// callable whether or not the master already has a catalogue, so it backs
  /// both first-time setup and "add more services". The backend derives each
  /// service's name + category from its `serviceTypeId`, then persists the
  /// per-item duration + pricing block. Returns the list of newly-created
  /// [MasterService] records as mapped from the response (same envelope shape
  /// `listMyServices()` parses).
  ///
  /// All-or-nothing: if any item collides, the whole batch is rolled back and
  /// nothing is written.
  ///
  /// The generated [ServiceControllerApi] does NOT yet expose this operation
  /// (the backend endpoint is on an unpushed branch; the mobile OpenAPI spec is
  /// stale), so the implementation issues the POST via the raw authenticated
  /// [Dio] instance and deserializes the response with the same
  /// [standardSerializers] used by the generated client.
  ///
  /// Throws:
  ///   - [ServiceDuplicateFailure] on **409** (`data.code ==
  ///     "DUPLICATE_SERVICE"` — one item names a service the master already
  ///     offers; the batch was rolled back).
  ///   - [BulkSetupBusyFailure] on **503** (per-master lock held past the
  ///     backend's 3 s ceiling). Transient; safe to retry, nothing was written.
  ///   - [ValidationFailure] on **400/422** (malformed items, or a service-type
  ///     id repeated within the batch).
  ///   - [NetworkFailure] / [ServerFailure] on other transport errors.
  Future<List<MasterService>> bulkCreate(List<MasterServiceBulkItem> items);

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
  /// - [initialServiceName]: OPTIONAL free-text name of an initial service-type
  ///   the requester wants seeded under the new category (≤255 chars server-side;
  ///   the UI caps at 100). Sent only when non-null/non-empty.
  ///
  /// Throws:
  ///   - [CategoryAlreadyExistsFailure] on **409** (already exists/pending).
  ///   - [CategoryRequestThrottledFailure] on **429** (rate-limited, 5/hr).
  ///   - [ValidationFailure] on **400/422** (malformed name/displayName).
  Future<void> requestCategory({
    required String name,
    required String displayName,
    String? initialServiceName,
  });

  /// Returns the list of platform service types under [categoryName] for the
  /// second-level picker.
  ///
  /// Wraps `GET /api/v1/service-catalog/service-types?categoryName=...`
  /// (the slug-contract `PlatformServiceTypeResponse` branch). Each option
  /// carries the wire [ServiceTypeOption.slug] (persisted on the service) and
  /// the Ukrainian [ServiceTypeOption.nameUk] (shown to the user and used to
  /// pre-fill the service name).
  ///
  /// Degrades gracefully: an unknown category, an empty backend result, or a
  /// response that resolves to the legacy alternate branch all yield an **empty
  /// list** rather than throwing. Transport errors are mapped to the feature's
  /// typed [Failure] subclasses.
  Future<List<ServiceTypeOption>> fetchServiceTypes(String categoryName);

  /// Submits a suggestion for a new platform service type under [categoryName]
  /// for admin review.
  ///
  /// Wraps `POST /api/v1/service-types/suggest` (authenticated). The suggested
  /// type is created in a PENDING state and approved out-of-band by an admin —
  /// it does NOT immediately appear in [fetchServiceTypes].
  ///
  /// - [categoryName]: the System-B slug of the owning category (NOT a UUID).
  ///   This is the wire `categoryName` field per the backend 16.7 contract.
  /// - [name]: non-blank Ukrainian label for the suggested service type.
  /// - [description]: optional free-form context for the reviewer; omitted from
  ///   the request when null/empty.
  ///
  /// Throws:
  ///   - [ValidationFailure] on **400/422** (malformed name/description),
  ///     carrying any field errors keyed by `name` / `description`.
  ///   - [CategoryRequestThrottledFailure] on **429** (rate-limited).
  ///   - [ServerFailure] / [NetworkFailure] on other transport errors.
  Future<void> suggestServiceType({
    required String categoryName,
    required String name,
    String? description,
  });
}

/// HTTP implementation of [ServiceRepository].
///
/// Inject via [serviceRepositoryProvider] — never construct directly.
///
/// [_serviceApi] drives all generated-API calls (list/create/update/deactivate).
/// [_masterId] is resolved from the authenticated session at provider
/// construction time. As of Phase 16.9 it is no longer a path parameter (the
/// list/get/create/update/deactivate endpoints all derive the master from the
/// JWT principal); it is retained purely as a readiness guard — a non-empty
/// value means the master profile has resolved, so [_assertAuthenticated] can
/// fail fast before issuing a call on an unauthenticated session.
final class HttpServiceRepository implements ServiceRepository {
  HttpServiceRepository({
    required ServiceControllerApi serviceApi,
    required CategoryRequestControllerApi categoryApi,
    required ServiceCatalogControllerApi catalogApi,
    required Dio dio,
    required String masterId,
  }) : _serviceApi = serviceApi,
       _categoryApi = categoryApi,
       _catalogApi = catalogApi,
       _dio = dio,
       _masterId = masterId;

  final ServiceControllerApi _serviceApi;
  final CategoryRequestControllerApi _categoryApi;
  final ServiceCatalogControllerApi _catalogApi;

  /// The raw authenticated [Dio] instance (full interceptor chain). Used ONLY
  /// for the bulk-setup POST, which the generated [ServiceControllerApi] does
  /// not yet expose. All other calls go through the generated client.
  final Dio _dio;
  final String _masterId;

  static const _tag = 'feature.services.repository';

  /// Throws [UnauthorizedFailure] immediately if [_masterId] is empty.
  ///
  /// An empty masterId means the master profile has not yet resolved (the auth
  /// session is not [Authenticated]). The owner endpoints derive the master
  /// from the JWT principal, so this is no longer about a missing path segment;
  /// it is a readiness guard that surfaces the real cause to callers instead of
  /// firing a call that would 401 mid-flight.
  void _assertAuthenticated() {
    if (_masterId.isEmpty) {
      throw const UnauthorizedFailure();
    }
  }

  @override
  Future<List<MasterService>> listMyServices() async {
    _assertAuthenticated();
    try {
      // The owner's own services list uses the authenticated endpoint
      // `GET /api/v1/independent-masters/me/services`, which derives the master
      // from the JWT principal (no masterId path param). The public
      // `GET /masters/{masterId}/services` endpoint stays available for any
      // public-browse use; this caller no longer touches it.
      final res = await _serviceApi.getMyServices();
      final list = res.data?.data;
      if (list == null) {
        // A 200 whose envelope carries no `data` array is a MALFORMED success,
        // not an empty catalogue. Collapsing it onto `const []` (as this used
        // to) rendered the "no services" em-dash for a response that in fact
        // failed to deliver anything — a stripped/garbled body was
        // indistinguishable from a master who genuinely has zero services.
        // Throwing routes it to the error path instead (`ServicesStatTile`
        // then shows its distinct '?' glyph rather than '—'). Matches the
        // same-shape guard the write endpoints in this file already apply.
        if (kDebugMode) {
          log(
            'listMyServices: ApiResponseListMasterServiceResponse.data is null',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
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
  Future<List<MasterService>> getMasterServices(String masterId) async {
    // No [_assertAuthenticated] gate: this hits the PUBLIC endpoint keyed on the
    // [masterId] PATH parameter (not the JWT principal), so it must work even
    // when [_masterId] is empty (the CLIENT-safe provider passes '').
    try {
      final res = await _serviceApi.getMasterServices(masterId: masterId);
      final list = res.data?.data;
      if (list == null) {
        // See [listMyServices] — a 200 with a null `data` envelope is a
        // malformed success, never an empty catalogue, so it must reach the
        // caller's error branch rather than render as "this master offers no
        // services". For the public profile this matters more, not less: the
        // silent-empty version showed a CLIENT a services-less master page
        // built from a response that never arrived.
        if (kDebugMode) {
          log(
            'getMasterServices($masterId): '
            'ApiResponseListMasterServiceResponse.data is null',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return list.map(MasterServiceMapper.fromDto).toList(growable: false);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMasterServices($masterId) failed: '
          '${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
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
      throw _mapServiceWriteException(e);
    }
  }

  @override
  Future<List<MasterService>> bulkCreate(
    List<MasterServiceBulkItem> items,
  ) async {
    _assertAuthenticated();
    if (items.isEmpty) return const [];

    // Build the wire body by hand: the generated client has no bulk operation,
    // so we serialise each item to the shape the backend expects. Mode-
    // conditional price fields are omitted (not null) when not applicable so the
    // backend receives only the relevant subset, mirroring the generated
    // serializer's null-omission behaviour.
    final body = <String, Object?>{
      'items': <Map<String, Object?>>[
        for (final item in items) _bulkItemToJson(item),
      ],
    };

    try {
      // Path note: the generated client's relative paths all begin with
      // `/api/v1/...` (e.g. `r'/api/v1/independent-masters/me/services'`), and
      // `AppConfig.baseUrl` is normalised to NEVER carry the `/api/v1` prefix.
      // So the raw path MUST include `/api/v1` to match the generated calls —
      // omitting it would 404. (This is the inverse of the "double-prefix"
      // trap: here the prefix lives on the path, not the base URL.)
      final res = await _dio.post<Object?>(
        '/api/v1/independent-masters/me/services/bulk',
        data: body,
      );

      // The response envelope is ApiResponse<List<MasterServiceResponse>> — the
      // same shape `getMyServices()` parses. Deserialize each element with the
      // generated serializers, then map through the existing DTO→domain mapper.
      final raw = res.data;
      final dataList = (raw is Map<String, Object?>) ? raw['data'] : null;
      if (dataList is! List) {
        if (kDebugMode) {
          log(
            'bulkCreate: response `data` is not a list (got '
            '${dataList.runtimeType})',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return dataList
          .map((Object? element) {
            final dto = standardSerializers.deserializeWith(
              MasterServiceResponse.serializer,
              element,
            );
            if (dto == null) {
              throw const ServerFailure(statusCode: null);
            }
            return MasterServiceMapper.fromDto(dto);
          })
          .toList(growable: false);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'bulkCreate failed: ${e.type} ${e.response?.statusCode} '
          '(${items.length} items)',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapBulkCreateException(e);
    }
  }

  /// Serialises one [MasterServiceBulkItem] to the wire JSON the bulk endpoint
  /// expects, emitting only the mode-appropriate price fields.
  Map<String, Object?> _bulkItemToJson(MasterServiceBulkItem item) {
    final json = <String, Object?>{
      'serviceTypeId': item.serviceTypeId,
      'durationMinutes': item.durationMinutes,
      'priceType': switch (item.priceType) {
        ServicePriceType.fixed => 'FIXED',
        ServicePriceType.range => 'RANGE',
      },
    };
    switch (item.priceType) {
      case ServicePriceType.fixed:
        json['price'] = item.price;
      case ServicePriceType.range:
        json['priceMin'] = item.priceMin;
        json['priceMax'] = item.priceMax;
    }
    return json;
  }

  /// Maps a [DioException] from the bulk-setup POST to a typed [Failure].
  ///
  ///   - **409** → [ServiceDuplicateFailure]. Since `beautica-backend` c5e420f
  ///     made bulk create ADDITIVE, 409 on this endpoint means exactly ONE
  ///     thing: `data.code == DUPLICATE_SERVICE` — one item names a service the
  ///     master already offers. The whole batch is rolled back, so nothing was
  ///     written.
  ///   - **503** → [BulkSetupBusyFailure] (the per-master advisory lock was held
  ///     past the backend's 3 s ceiling). Transient and safe to retry.
  ///   - **429** → [ServiceRateLimitedFailure] (the per-master bulk bucket,
  ///     10/min, is exhausted). Reachable in ordinary use because the 503 branch
  ///     hands the master an explicit retry action.
  ///   - **400/422** → [ValidationFailure] (includes the in-batch duplicate
  ///     service-type-id case and the per-item `items[i].field` errors).
  /// All other statuses defer to the shared [_mapDioException].
  ///
  /// Both status checks run BEFORE deferring to any [Failure] the
  /// [ErrorMapperInterceptor] may have attached (it maps a non-auth 409 to a
  /// generic [ServerFailure] and a 503 to a generic 5xx [ServerFailure], neither
  /// of which carries the specific copy or the retry semantics), so we re-map by
  /// status code here.
  ///
  /// REMOVED (2026-08-04): the former `MasterAlreadyHasServicesFailure` branch
  /// for a non-`DUPLICATE_SERVICE` 409. That server condition — "bulk setup is
  /// only available for a master with no active services" — was DELETED
  /// backend-side when bulk create became additive. Keeping it as a defensive
  /// branch would have been actively harmful, not merely dead: it renders
  /// "you already have services" copy and routes the master AWAY from the screen
  /// without saving, so any future unrelated 409 would be mistranslated into a
  /// confident, wrong explanation plus a forced navigation. An unmodelled 409
  /// now falls through to the honest generic server error instead.
  Failure _mapBulkCreateException(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 409 && _isDuplicateService(e)) {
      // `serviceName` is null on the bulk envelope, so [ServiceDuplicateFailure]
      // renders its plain "already in your menu" message.
      return _extractDuplicateService(e);
    }
    // Decoded by STATUS CODE alone — the 503 body is deliberately generic
    // (`data: null`, non-machine-readable `message`), and there is no
    // `Retry-After` header to honour.
    if (statusCode == 503) return BulkSetupBusyFailure(cause: e);
    // 429 must be re-mapped by STATUS CODE here for the same reason 409 and 503
    // are: the interceptor has no generic-429 branch, so an unmapped throttle
    // reaches `_mapDioException`'s `badResponse` default and becomes
    // `ServerFailure(statusCode: 429)` — the generic "server error, try again"
    // copy, which is the one instruction guaranteed to fail while the bucket is
    // closed.
    if (statusCode == 429) return _rateLimited(e);
    if (e.error is Failure) return e.error as Failure;
    return _mapDioException(e);
  }

  /// Builds a [ServiceRateLimitedFailure] from a 429, threading the server's
  /// `Retry-After` through so the copy can name the wait.
  ServiceRateLimitedFailure _rateLimited(DioException e) =>
      ServiceRateLimitedFailure(
        retryAfterSeconds: _extractRetryAfterSeconds(e),
        cause: e,
      );

  /// Parses the `Retry-After` response header (RFC 7231 §7.1.3, integer-seconds
  /// form only — the backend always emits an integer, never an HTTP-date).
  ///
  /// Returns `null` when the header is absent, unparsable, negative, or beyond
  /// [_maxUxCooldownSeconds]; the copy then drops the countdown and says "wait a
  /// moment" instead. The ceiling is a UX guard AND an overflow guard: a rogue
  /// or misconfigured backend sending `Retry-After: 999999999` must never render
  /// a multi-year wait. Mirrors `HttpScheduleRepository._extractRetryAfterSeconds`
  /// and `ErrorMapperInterceptor._extractRetryAfterSecondsNullable`.
  int? _extractRetryAfterSeconds(DioException e) {
    final raw = e.response?.headers.value('retry-after');
    if (raw == null) return null;
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed < 0 || parsed > _maxUxCooldownSeconds) {
      return null;
    }
    return parsed;
  }

  /// 10 min — above this a countdown stops being useful information.
  static const int _maxUxCooldownSeconds = 600;

  /// `true` when [e] is a 409 whose body is the
  /// `{ "data": { "code": "DUPLICATE_SERVICE" } }` envelope — the service is
  /// already in the master's menu (or a DB unique-index race caught a concurrent
  /// add). Hand-decoded from the raw JSON body (this code is not part of the
  /// generated client), mirroring
  /// `HttpAppointmentRepository._isDuplicateService`.
  bool _isDuplicateService(DioException e) {
    final body = e.response?.data;
    if (body is! Map<String, dynamic>) return false;
    final data = body['data'];
    if (data is! Map<String, dynamic>) return false;
    return data['code'] == 'DUPLICATE_SERVICE';
  }

  /// Builds a [ServiceDuplicateFailure] from a 409 `DUPLICATE_SERVICE` body,
  /// threading through the two nullable diagnostic fields. Both `serviceName`
  /// (null on the bulk path) and `existingServiceDefId` (null on a DB
  /// unique-index race) are read defensively — a non-string value degrades to
  /// null so [ServiceDuplicateFailure.userMessage] still renders its plain copy.
  /// Precondition: [_isDuplicateService] returned `true` for [e].
  ServiceDuplicateFailure _extractDuplicateService(DioException e) {
    String? readString(Object? value) => value is String ? value : null;
    final body = e.response?.data;
    final data = (body is Map<String, dynamic>) ? body['data'] : null;
    final map = (data is Map<String, dynamic>)
        ? data
        : const <String, dynamic>{};
    return ServiceDuplicateFailure(
      serviceName: readString(map['serviceName']),
      existingServiceDefId: readString(map['existingServiceDefId']),
      cause: e,
    );
  }

  /// Maps a [DioException] from a service-catalog WRITE (`create` / `update` /
  /// `deactivate`) to a typed [Failure], distinguishing the two statuses the
  /// generic mapping mistranslates:
  ///   - **409** with `data.code == "DUPLICATE_SERVICE"` →
  ///     [ServiceDuplicateFailure] (the service is already in the master's menu).
  ///   - **429** → [ServiceRateLimitedFailure] (the per-master single-write
  ///     bucket, 60/min, is exhausted).
  /// All other statuses defer to the shared [_mapDioException].
  ///
  /// Both decodes run BEFORE deferring to any [Failure] the
  /// [ErrorMapperInterceptor] may have attached (it maps a non-auth 409 to a
  /// generic [ServerFailure] and has no 429 branch at all), so we hand-decode
  /// here to surface the friendly message — mirroring
  /// [_mapCategoryRequestException].
  Failure _mapServiceWriteException(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 409 && _isDuplicateService(e)) {
      return _extractDuplicateService(e);
    }
    if (statusCode == 429) return _rateLimited(e);
    if (e.error is Failure) return e.error as Failure;
    return _mapDioException(e);
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
      throw _mapServiceWriteException(e);
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
      // Shares the write mapper with create/update: DELETE sits in the same
      // per-master 60/min write bucket, so an unmapped 429 here would render
      // the same wrong "server error" copy. The mapper's DUPLICATE_SERVICE
      // branch cannot fire on this endpoint (no such body), so routing through
      // it changes nothing else.
      throw _mapServiceWriteException(e);
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
    String? initialServiceName,
  }) async {
    try {
      // The optional initial service name is attached only when
      // non-null/non-empty (mirrors the suggestServiceType description-omission
      // pattern); the generated model omits a null `initialServiceName` key.
      final initial = initialServiceName?.trim();
      final request = CreateCategoryRequestRequest(
        (b) => b
          ..name = name
          ..displayName = displayName
          ..initialServiceName = (initial == null || initial.isEmpty)
              ? null
              : initial,
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

  @override
  Future<List<ServiceTypeOption>> fetchServiceTypes(String categoryName) async {
    try {
      // The 200 response is now a single-shape
      // ApiResponseListPlatformServiceTypeResponse (the legacy oneOf alternate
      // was removed backend-side — the legacy operation is @Hidden). Read
      // `data` directly, mirroring [fetchApprovedCategories].
      final res = await _catalogApi.getServiceTypesByPlatformCategory(
        categoryName: categoryName,
      );
      final list = res.data?.data;
      if (list == null) {
        if (kDebugMode) {
          log(
            'fetchServiceTypes($categoryName): '
            'ApiResponseListPlatformServiceTypeResponse.data is null',
            name: _tag,
            level: 1000,
          );
        }
        return const [];
      }
      return ServiceTypeMapper.fromDtoList(list);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'fetchServiceTypes($categoryName) failed: '
          '${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> suggestServiceType({
    required String categoryName,
    required String name,
    String? description,
  }) async {
    try {
      // Sends the System-B `categoryName` slug (per backend 16.7) — NOT a
      // categoryId UUID. The generated SuggestServiceTypeRequest exposes
      // `name`, `categoryName`, and an optional `description`; the description
      // is only attached when non-null/non-empty (the serializer omits a null).
      final desc = description?.trim();
      final request = SuggestServiceTypeRequest(
        (b) => b
          ..name = name
          ..categoryName = categoryName
          ..description = (desc == null || desc.isEmpty) ? null : desc,
      );
      await _catalogApi.suggestServiceType(suggestServiceTypeRequest: request);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'suggestServiceType failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapServiceTypeSuggestionException(e);
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

  /// Maps a [DioException] from `POST /service-types/suggest` to a typed
  /// [Failure]:
  ///   - **400/422** → [ValidationFailure] (malformed name/description). If
  ///     [ErrorMapperInterceptor] already attached a [ValidationFailure] (with
  ///     parsed field errors), that instance is preferred so inline field-level
  ///     messages survive.
  ///   - **429** → [CategoryRequestThrottledFailure] (rate-limited). Reuses the
  ///     existing throttle failure / copy shared with the category-request flow.
  /// All other statuses defer to the shared [_mapDioException].
  ///
  /// The status checks run BEFORE deferring to any [Failure] already attached by
  /// the interceptor for the 429 case (the interceptor maps an unmatched 429 to
  /// [UnknownFailure], which lacks the throttle copy), so we re-map by status
  /// code here to surface the friendly message.
  Failure _mapServiceTypeSuggestionException(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 429) return CategoryRequestThrottledFailure(cause: e);
    // Prefer an interceptor-attached ValidationFailure (it carries the parsed
    // fieldErrors used for inline name/description messages).
    if (e.error is Failure) return e.error as Failure;
    if (statusCode == 400 || statusCode == 422) {
      return ValidationFailure(fieldErrors: const {}, cause: e);
    }
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
      // A TLS / certificate-validation failure is a transport-layer security
      // problem, NOT a transient 5xx. Classifying it as a [ServerFailure] would
      // make a man-in-the-middle / broken-trust-chain error indistinguishable
      // from a retryable backend hiccup — the UI would invite the user to
      // "try again" against a connection that should not be trusted. Map it
      // alongside the connectivity failures ([NetworkFailure]) so it surfaces as
      // a connection problem and never looks like a recoverable server error.
      // (This only changes error CLASSIFICATION; certificate validation itself
      // is unchanged — it stays enforced by the Dio/HttpClient trust chain.)
      case DioExceptionType.badCertificate:
        return NetworkFailure(cause: e);
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return ServerFailure(statusCode: statusCode, cause: e);
    }
  }
}

/// Provides the [ServiceRepository] singleton backed by the authenticated Dio,
/// the generated [ServiceControllerApi], and the current master's UUID from
/// [masterProfileProvider].
///
/// As of Phase 16.9 the owner list endpoint
/// (`GET /api/v1/independent-masters/me/services`) derives the master from the
/// JWT principal, so [_masterId] is no longer sent as a path parameter. It is
/// still watched here so the repository is re-created once the master profile
/// resolves and so [_assertAuthenticated] can fail fast on an unready session.
/// The value remains the Master-row UUID (from MasterDetailResponse.masterId),
/// NOT the User UUID — User.id != Master.id.
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
    catalogApi: ref.watch(serviceCatalogApiProvider),
    // Raw authenticated Dio (full interceptor chain) for the bulk-setup POST,
    // which the generated ServiceControllerApi does not yet expose.
    dio: ref.watch(dioProvider),
    masterId: masterId,
  );
}

/// Provides a CLIENT-safe [ServiceRepository] for PUBLIC reads only.
///
/// Used by the public master profile (Phase 13.5) to fetch the target master's
/// active services (stat tile count + the read-only service-categories
/// section) via [ServiceRepository.getMasterServices]. Unlike
/// [serviceRepositoryProvider] it does NOT `ref.watch(masterProfileProvider)`:
/// a CLIENT has no master profile, and dragging that master-only provider in
/// would fire `GET /api/v1/masters/me` (403 for a CLIENT) and trigger Riverpod's
/// retry storm — the same footgun the [approvedCategories] provider avoids by
/// sourcing the API directly. The [_masterId] readiness guard is passed empty
/// (`''`) on purpose: only [getMasterServices] (which hits the public,
/// path-parameterised endpoint and never calls `_assertAuthenticated`) is used
/// through this handle; the owner-only methods would correctly throw
/// [UnauthorizedFailure].
@Riverpod(keepAlive: true)
ServiceRepository publicServiceRepository(Ref ref) => HttpServiceRepository(
  serviceApi: ref.watch(serviceApiProvider),
  categoryApi: ref.watch(categoryRequestApiProvider),
  catalogApi: ref.watch(serviceCatalogApiProvider),
  dio: ref.watch(dioProvider),
  masterId: '',
);

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

/// Provides the generated [ServiceCatalogControllerApi] singleton.
///
/// Drives the platform service-catalog lookups — specifically the second-level
/// service-type picker (`GET /service-catalog/service-types?categoryName=...`).
/// Same authenticated Dio + serializers as the other API providers. Kept alive
/// to avoid re-construction on every provider read.
@Riverpod(keepAlive: true)
ServiceCatalogControllerApi serviceCatalogApi(Ref ref) =>
    ServiceCatalogControllerApi(ref.watch(dioProvider), standardSerializers);

/// Async list of approved service categories for the service-form picker.
///
/// Watched by the category chip selector in `service_form.dart` and by the
/// services-list cards (slug → display-name resolution). The list is small and
/// changes rarely, so the provider is [keepAlive: true] — the value is cached
/// in the root container and shared across the create and edit screens rather
/// than re-fetched on every watch.
///
/// Because the cache is long-lived, an admin approving a category out-of-band
/// would otherwise go unseen until a cold restart. The services-list screen
/// therefore invalidates this provider explicitly so the picker stays fresh:
///   • on first entry (post-frame callback in `ServicesListScreen.initState`);
///   • on return from the create / edit / request-category flows (the screen
///     awaits each `context.push(...)` and invalidates on pop-back — the
///     /services route is kept alive, so `initState` does not re-fire there);
///   • on pull-to-refresh (alongside the services reload).
/// A successful [ServiceRepository.requestCategory] does NOT itself add a row:
/// a freshly-requested category is PENDING admin review and only appears once
/// an admin approves it and one of the refresh paths above re-fetches.
///
/// On error, the picker row shows a compact retry affordance that calls
/// `ref.invalidate(approvedCategoriesProvider)` — the rest of the form stays
/// usable (category is optional).
/// Sourced directly from [categoryRequestApiProvider] (which depends only on
/// [dioProvider], NOT on the master-only [masterProfileProvider]) so that
/// CLIENT-side callers — e.g. the discovery search `_ServiceTypeGrid` — never
/// transitively drag in `GET /api/v1/masters/me` (a master-only endpoint that
/// 403s for a CLIENT and then gets retried ~4× by Riverpod's backoff). The
/// returned list mirrors [ServiceRepository.fetchApprovedCategories] exactly
/// (same `MasterServiceMapper.fromApprovedCategoryList` mapping + null/empty
/// handling), so master-side callers are unaffected.
@Riverpod(keepAlive: true)
Future<List<ServiceCategoryOption>> approvedCategories(Ref ref) async {
  final res = await ref.watch(categoryRequestApiProvider).listApproved();
  final list = res.data?.data;
  if (list == null) {
    return const [];
  }
  return MasterServiceMapper.fromApprovedCategoryList(list);
}
