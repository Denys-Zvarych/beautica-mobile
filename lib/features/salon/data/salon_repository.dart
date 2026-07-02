// Phase 2.19 — SalonRepository (hand-written Dio) — salon creation.
// Phase 13.6 — extended with the PUBLIC, client-facing read path: salon
// detail, the masters rail, the service catalogue, and the reviews
// summary/list. These new reads use the generated SalonApi/ServiceApi/
// ReviewApi DTOs (per the file's own former TODO) rather than hand-written
// payloads.
//
// Created during registration Step 3 for the SALON_OWNER role: immediately
// after the owner's account registers, the app POSTs the salon (name +
// locality + address) so the owner lands on a fully-provisioned salon, per
// backend Phase 10.6.
//
// Backend contract (locked):
//   POST /api/v1/salons
//     Body: { name, cityId (UUID), districtId? (UUID|null), street, buildingNo,
//             locationNote?, phone? }
//     Returns: ApiResponse<SalonResponse> — the mobile layer does not need the
//              body here, so the method resolves with void.
//   GET  /api/v1/salons/{salonId}                    → PublicSalonResponse
//   GET  /api/v1/salons/{salonId}/masters             → Page<MasterSummaryResponse>
//   GET  /api/v1/salons/{salonId}/services            → SalonServiceCatalogResponse
//   GET  /api/v1/salons/{salonId}/reviews/summary     → SalonReviewSummaryResponse
//   GET  /api/v1/salons/{salonId}/reviews?sort=&page=&size= → Page<SalonReviewResponse>
//
// WIRE-FORMAT NOTE (masters + reviews pagination): the generated
// `SalonControllerApi.getMastersBySalon` / `ReviewControllerApi.getSalonReviews`
// take a typed `Pageable` parameter, whose generated `encodeQueryParameter`
// JSON-encodes the WHOLE object into a single `pageable=` query value (the
// exact bug documented in `discovery/data/search_repository.dart`'s file
// header — Spring's `PageableHandlerMethodArgumentResolver` expects FLAT
// `page`/`size`/`sort` query keys, not one nested blob). Both paginated reads
// below therefore bypass the generated Pageable-taking methods and issue a
// raw GET through the shared authenticated [Dio] with flat query params,
// deserializing the response with the SAME [standardSerializers] the
// generated client uses.
//
// AppConfig.baseUrl does NOT carry the `/api/v1` prefix (see app_config.dart).
// All paths here must include the full `/api/v1/` segment explicitly.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/salon.dart';
import '../domain/salon_master_summary.dart';
import '../domain/salon_portfolio_photo.dart';
import '../domain/salon_review.dart';
import '../domain/salon_service_catalog.dart';
import 'salon_mapper.dart';

part 'salon_repository.g.dart';

/// Default page size for the salon masters rail (Phase 13.6 "Майстри" tab).
const int kSalonMastersPageSize = 50;

/// Default page size for the salon reviews list (Phase 13.6 "Відгуки" tab).
const int kSalonReviewsPageSize = 20;

/// Immutable write payload for `POST /salons`.
///
/// Hand-written (no generated DTO yet). [districtId], [locationNote], and
/// [phone] are nullable optionals; [toJson] omits them when null/empty so the
/// backend sees a clean body rather than explicit nulls.
@immutable
final class SalonCreateDto {
  const SalonCreateDto({
    required this.name,
    required this.cityId,
    this.districtId,
    required this.street,
    required this.buildingNo,
    this.locationNote,
    this.phone,
  });

  /// Salon display name (collected in Step 2 as `salonName`).
  final String name;

  /// UUID of the salon's city.
  final String cityId;

  /// UUID of the salon's district, or null when the city is a leaf.
  final String? districtId;

  /// Street line.
  final String street;

  /// Building number / identifier.
  final String buildingNo;

  /// Optional free-text note (floor, entrance, intercom, …).
  final String? locationNote;

  /// Optional contact phone number for the salon.
  ///
  /// Nullable — callers that do not have phone data pass null and [toJson]
  /// will omit the field entirely. Backend validates with `@Pattern + @Size`
  /// when present, so an empty string is also omitted rather than sent.
  final String? phone;

  /// Serialises to the backend body, omitting empty optionals.
  Map<String, dynamic> toJson() {
    final trimmedNote = locationNote?.trim();
    final trimmedPhone = phone?.trim();
    final json = <String, dynamic>{
      'name': name.trim(),
      'cityId': cityId,
      'street': street.trim(),
      'buildingNo': buildingNo.trim(),
    };
    if (districtId != null && districtId!.isNotEmpty) {
      json['districtId'] = districtId;
    }
    if (trimmedNote != null && trimmedNote.isNotEmpty) {
      json['locationNote'] = trimmedNote;
    }
    if (trimmedPhone != null && trimmedPhone.isNotEmpty) {
      json['phone'] = trimmedPhone;
    }
    return json;
  }
}

/// Contract for the salon layer: the registration-time write path plus the
/// PUBLIC, client-facing read path (Phase 13.6).
///
/// Every method either resolves successfully or throws a [Failure] subclass
/// from `core/errors/failures.dart`. Raw [DioException]s never escape.
abstract interface class SalonRepository {
  /// Creates a salon owned by the authenticated user.
  ///
  /// Wraps `POST /salons`. Throws a typed [Failure] on any transport or server
  /// error.
  Future<void> create({required SalonCreateDto dto});

  /// Fetches the PUBLIC salon detail for [salonId].
  ///
  /// Wraps `GET /salons/{salonId}`. Safe to call from a CLIENT session — it
  /// drives the client-facing public salon profile (Phase 13.6).
  Future<Salon> getSalonById(String salonId);

  /// Fetches the salon's masters rail (first page, up to
  /// [kSalonMastersPageSize] entries).
  ///
  /// Wraps `GET /salons/{salonId}/masters`. Returns an empty list when the
  /// salon has no masters.
  Future<List<SalonMasterSummary>> getSalonMasters(String salonId);

  /// Fetches the salon's public service catalogue, grouped by category
  /// (already ordered server-side).
  ///
  /// Wraps `GET /salons/{salonId}/services`.
  Future<List<SalonServiceCategoryEntry>> getSalonServiceCatalog(
    String salonId,
  );

  /// Fetches the salon's aggregate review summary (average + distribution).
  ///
  /// Wraps `GET /salons/{salonId}/reviews/summary`.
  Future<SalonReviewSummary> getSalonReviewSummary(String salonId);

  /// Fetches one page of the salon's reviews, server-sorted by [sort].
  ///
  /// Wraps `GET /salons/{salonId}/reviews?sort=&page=&size=`. [page] is
  /// zero-based; [size] caps the page.
  Future<List<SalonReviewItem>> getSalonReviews({
    required String salonId,
    required SalonReviewSort sort,
    int page = 0,
    int size = kSalonReviewsPageSize,
  });

  /// Fetches the salon's public portfolio photo gallery ("Про салон" tab).
  ///
  /// Wraps `GET /salons/{salonId}/portfolio` (public, unauthenticated). Returns
  /// an empty list when the salon has no portfolio photos.
  Future<List<SalonPortfolioPhoto>> getSalonPortfolio(String salonId);
}

/// HTTP implementation of [SalonRepository].
///
/// Inject via [salonRepositoryProvider] — never construct directly.
final class HttpSalonRepository implements SalonRepository {
  HttpSalonRepository(
    this._dio,
    this._salonApi,
    this._serviceApi,
    this._reviewApi,
    this._mediaApi,
  );

  final Dio _dio;
  final SalonControllerApi _salonApi;
  final ServiceControllerApi _serviceApi;
  final ReviewControllerApi _reviewApi;
  final MediaControllerApi _mediaApi;

  @override
  Future<void> create({required SalonCreateDto dto}) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/api/v1/salons',
        data: dto.toJson(),
      );
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'salon create failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<Salon> getSalonById(String salonId) async {
    try {
      final res = await _salonApi.getSalon(salonId: salonId);
      final dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'getSalonById: ApiResponsePublicSalonResponse.data is null',
            name: 'salon.repository',
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return SalonMapper.fromDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getSalonById failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<List<SalonMasterSummary>> getSalonMasters(String salonId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/salons/${Uri.encodeComponent(salonId)}/masters',
        queryParameters: <String, dynamic>{
          'page': 0,
          'size': kSalonMastersPageSize,
        },
      );
      final decoded =
          _deserialize<ApiResponsePageResponseMasterSummaryResponse>(
            response.data,
            const FullType(ApiResponsePageResponseMasterSummaryResponse),
          );
      final content = decoded?.data?.data ?? const <MasterSummaryResponse>[];
      return SalonMasterMapper.fromDtoList(content);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getSalonMasters failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<List<SalonServiceCategoryEntry>> getSalonServiceCatalog(
    String salonId,
  ) async {
    try {
      final res = await _serviceApi.getSalonServiceCatalog(salonId: salonId);
      final dto = res.data?.data;
      if (dto == null) return const <SalonServiceCategoryEntry>[];
      return SalonServiceCatalogMapper.fromDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getSalonServiceCatalog failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<SalonReviewSummary> getSalonReviewSummary(String salonId) async {
    try {
      final res = await _reviewApi.getSalonReviewSummary(salonId: salonId);
      final dto = res.data?.data;
      if (dto == null) return const SalonReviewSummary();
      return SalonReviewMapper.summaryFromDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getSalonReviewSummary failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<List<SalonReviewItem>> getSalonReviews({
    required String salonId,
    required SalonReviewSort sort,
    int page = 0,
    int size = kSalonReviewsPageSize,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/salons/${Uri.encodeComponent(salonId)}/reviews',
        queryParameters: <String, dynamic>{
          'sort': sort.wireValue,
          'page': page,
          'size': size,
        },
      );
      final decoded = _deserialize<ApiResponsePageResponseSalonReviewResponse>(
        response.data,
        const FullType(ApiResponsePageResponseSalonReviewResponse),
      );
      final content = decoded?.data?.data ?? const <SalonReviewResponse>[];
      return SalonReviewMapper.reviewsFromDtoList(content);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getSalonReviews failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<List<SalonPortfolioPhoto>> getSalonPortfolio(String salonId) async {
    try {
      final res = await _mediaApi.getSalonPortfolio(salonId: salonId);
      // WIRE-FORMAT NOTE: unlike [getSalonMasters]/[getSalonReviews] above
      // (which decode the hand-rolled custom `PageResponse` shape via
      // `.data?.data`), this read goes through the GENERATED
      // [MediaControllerApi] client, whose `PageMediaFileResponse` follows
      // Spring's DEFAULT `Page<T>` JSON shape — the row list lives under
      // `content`, not `data`.
      final content = res.data?.data?.content ?? const <MediaFileResponse>[];
      return SalonPortfolioMapper.fromDtoList(content);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getSalonPortfolio failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  /// Deserializes a raw JSON [data] map via the SAME [standardSerializers]
  /// the generated client uses. Returns `null` when [data] is null (an empty
  /// body); any deserialization failure is wrapped as a [ServerFailure] by the
  /// caller's catch-all (see `catch (e, st)` fallthrough at each call site —
  /// this method deliberately does not swallow errors itself).
  T? _deserialize<T>(Object? data, FullType type) {
    if (data == null) return null;
    return standardSerializers.deserialize(data, specifiedType: type) as T?;
  }

  /// Maps a [DioException] to a typed [Failure]. See [HttpMasterRepository] for
  /// the identical mapping rationale.
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

/// Provides the [SalonRepository] singleton backed by the authenticated Dio
/// and the generated Salon/Service/Review API clients.
///
/// Override in tests with a mocktail mock — never construct [HttpSalonRepository]
/// directly in tests.
@Riverpod(keepAlive: true)
SalonRepository salonRepository(Ref ref) => HttpSalonRepository(
  ref.watch(dioProvider),
  ref.watch(salonApiProvider),
  ref.watch(salonServiceApiProvider),
  ref.watch(salonReviewApiProvider),
  ref.watch(salonMediaApiProvider),
);

/// Provides the generated [SalonControllerApi] singleton.
///
/// A dedicated provider local to this feature file (mirrors the pattern
/// [ServiceControllerApi] uses in `services/data/service_repository.dart`)
/// rather than importing another feature's data layer, per the architecture's
/// cross-feature import rule (data/ may only import its OWN feature's
/// domain/, never another feature's data/).
@Riverpod(keepAlive: true)
SalonControllerApi salonApi(Ref ref) =>
    SalonControllerApi(ref.watch(dioProvider), standardSerializers);

/// Provides the generated [ServiceControllerApi] singleton for salon reads
/// (`getSalonServiceCatalog`). Named distinctly from the services feature's
/// own `serviceApiProvider` to avoid a cross-feature data/ import while still
/// sharing the same generated API class + serializers.
@Riverpod(keepAlive: true)
ServiceControllerApi salonServiceApi(Ref ref) =>
    ServiceControllerApi(ref.watch(dioProvider), standardSerializers);

/// Provides the generated [ReviewControllerApi] singleton.
@Riverpod(keepAlive: true)
ReviewControllerApi salonReviewApi(Ref ref) =>
    ReviewControllerApi(ref.watch(dioProvider), standardSerializers);

/// Provides the generated [MediaControllerApi] singleton for the salon
/// portfolio read (`getSalonPortfolio`).
@Riverpod(keepAlive: true)
MediaControllerApi salonMediaApi(Ref ref) =>
    MediaControllerApi(ref.watch(dioProvider), standardSerializers);
