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
//   DELETE /api/v1/salons/{salonId}/admins/{userId}         → 204 (unassign)
//   PATCH  /api/v1/salons/{salonId}/admins/{userId}/salon   → SalonAdminResponse
//   GET    /api/v1/salons/{salonId}/sibling-salons          → List<SiblingSalonOption>
//
// Phase 21.6 — the three admin-management calls above. All three go through
// the GENERATED client. `getSiblingSalons` was the one exception while
// backend Phase 21.3b sat outside the committed spec snapshot; the snapshot
// has since been refreshed, so the raw GET + hand-rolled row parsing is gone
// and the schema is compiler-enforced like every other call here.
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
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/bookable_master_assignment.dart';
import '../domain/salon_invite.dart';
import '../domain/salon.dart';
import '../domain/salon_master_summary.dart';
import '../domain/salon_portfolio_photo.dart';
import '../domain/salon_review.dart';
import '../domain/salon_service_catalog.dart';
import '../domain/salon_staff_member.dart';
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
    this.instagramUrl,
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

  /// Optional Instagram handle/URL for the new salon.
  ///
  /// ADDITIVE (Phase 21.3) — the backend's `CreateSalonRequest` has always
  /// accepted `instagramUrl` (`CreateSalonRequest.java`), but this DTO never
  /// carried it: the only pre-existing caller (`VerificationScreen`'s
  /// post-registration `POST /salons`) never collects an Instagram handle at
  /// that point in the flow, so the gap went unnoticed until
  /// [RegisterSalonScreen] needed to send one. Nullable/omitted like [phone]
  /// — every existing caller that never sets it renders/sends identically.
  final String? instagramUrl;

  /// Serialises to the backend body, omitting empty optionals.
  Map<String, dynamic> toJson() {
    final trimmedNote = locationNote?.trim();
    final trimmedPhone = phone?.trim();
    final trimmedInstagram = instagramUrl?.trim();
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
    if (trimmedInstagram != null && trimmedInstagram.isNotEmpty) {
      json['instagramUrl'] = trimmedInstagram;
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

  /// Fetches every salon owned by the authenticated `SALON_OWNER` (Phase
  /// 21.1 «Мої салони» hub).
  ///
  /// Wraps `GET /salons/mine` (the generated `SalonControllerApi
  /// .getOwnedSalons`). Each entry is the SAME `SalonResponse` shape `PATCH
  /// /salons/{salonId}` returns — carries `isPrimary`/`phone`/`isActive`/
  /// `ownerId`, unlike the public `PublicSalonResponse` — so this reuses
  /// [SalonMapper.fromUpdateDto] per item rather than a fresh mapper.
  Future<List<Salon>> getMySalons();

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

  /// Applies a partial update to salon [salonId] (Phase 21.2 — owner/admin
  /// editable profile).
  ///
  /// Wraps `PATCH /salons/{salonId}`. [request] should carry ONLY the fields
  /// the caller actually wants to change — see
  /// `SalonManagementProfile.save`'s dirty-field diff, which also always
  /// includes `street`/`buildingNo` because [UpdateSalonRequest] declares
  /// both non-nullable/required even on a partial update. Returns the
  /// server's post-update [Salon] snapshot — see [SalonMapper.fromUpdateDto]
  /// for which fields that snapshot does NOT carry (callers must merge those
  /// back in from the previous [Salon]).
  Future<Salon> updateSalon(String salonId, UpdateSalonRequest request);

  /// Soft-deactivates salon [salonId] (owner-only per backend
  /// `SalonController.java:104`; the client-side role gate is UX only — the
  /// server is the real authority).
  ///
  /// Wraps `DELETE /salons/{salonId}`.
  Future<void> deleteSalon(String salonId);

  /// Fetches masters actually bookable for [serviceDefId] within [salonId] —
  /// active, actively assigned to the service, AND schedule-usable (backend
  /// Phase 23.x gate; a scheduleless master is simply absent from the
  /// response, fixing the salon booking calendar's all-dates-disabled bug at
  /// the source).
  ///
  /// Wraps `GET /salons/{salonId}/services/{serviceDefId}/masters`. Returns
  /// an empty list when no master is bookable for this service (200 `[]`).
  Future<List<BookableMasterAssignment>> getBookableMasters({
    required String salonId,
    required String serviceDefId,
  });

  /// Invites a new admin or master to join salon [salonId] (Phase 21.4 —
  /// form-only; the pending-invites list/cancel pair is descoped to Phase
  /// 21.11, once backend Phase 23.1's `GET/DELETE /salons/{salonId}/invites/
  /// ...` endpoints exist).
  ///
  /// Wraps `POST /salons/{salonId}/invite` (the generated
  /// `SalonControllerApi.inviteMaster`). [role] must be
  /// [UserRole.salonAdmin] or [UserRole.salonMaster] — any other value
  /// throws [ArgumentError] before a request is made (this repository never
  /// invites a CLIENT/SALON_OWNER/INDEPENDENT_MASTER). Throws a typed
  /// [Failure] on any transport or server error, including a 403 (caller
  /// does not own/administer this salon) and 429 (backend's per-IP
  /// `salonInviteBuckets`, 15 requests/60s) — the CALLER maps those
  /// [ServerFailure.statusCode] values to distinct copy, not this method.
  Future<void> inviteStaff({
    required String salonId,
    required String email,
    required UserRole role,
  });

  /// Fetches the salon's management-scoped staff roster (masters + admins,
  /// unmasked contact details) for [salonId] (Phase 21.5).
  ///
  /// Wraps `GET /salons/{salonId}/staff` (the generated
  /// `SalonControllerApi.getSalonStaff`). Requires management access to the
  /// salon (owner or assigned admin) — the same authorization
  /// [salonManageGuard] already binds client-side. Returns an empty list when
  /// the salon has no staff (should not normally happen — the owner
  /// themself is never listed, but a brand-new salon has no invited staff
  /// yet).
  Future<List<SalonStaffMember>> getSalonStaff(String salonId);

  /// Lists the salon's outbound staff-invitation HISTORY — pending,
  /// accepted, expired and cancelled alike, newest first.
  ///
  /// Wraps `GET /salons/{salonId}/invites` (the generated
  /// `SalonControllerApi.listSalonInvites`). Owner + admin scoped
  /// backend-side — the same authorization [salonManageGuard] binds
  /// client-side, and BOTH roles see the full history (a locked product
  /// decision; there is no role-based filtering of this list). Returns an
  /// empty list for a salon that has never invited anyone, which is the
  /// NORMAL state, not an error.
  ///
  /// The response DTO carries no token material — `inviteId`,
  /// `recipientEmail`, `role`, `status`, `createdAt`, `expiresAt` only.
  ///
  /// ORDER IS THE SERVER'S (`createdAt DESC, id DESC`) and is preserved
  /// verbatim; see [SalonInviteMapper.fromDtoList]. The server caps the page
  /// at its 200 most recent rows and reports the cut in
  /// [SalonInviteHistory.truncated], which the caller must surface rather
  /// than drop — a silently short list reads as "this is everything".
  Future<SalonInviteHistory> listSalonInvites(String salonId);

  /// Cancels the PENDING invitation [inviteId] of salon [salonId].
  ///
  /// Wraps `DELETE /salons/{salonId}/invites/{inviteId}` (the generated
  /// `SalonControllerApi.cancelInvite`). Backend-side the row is revoked, not
  /// deleted: it stays in the history reading CANCELLED, and
  /// `POST /auth/invite/accept` rejects it from then on.
  ///
  /// ONLY a pending invitation may be cancelled — the endpoint 404s a used,
  /// revoked, expired or cross-salon id, INCLUDING a second cancel of the
  /// same invitation. So this call is NOT idempotent and callers must gate it
  /// on [SalonInvite.isCancellable] rather than fire it optimistically.
  /// Throws a typed [Failure] on any transport or server error.
  Future<void> cancelInvite({
    required String salonId,
    required String inviteId,
  });

  /// Removes admin [userId] from salon [salonId] (Phase 21.6).
  ///
  /// Wraps `DELETE /salons/{salonId}/admins/{userId}` (the generated
  /// `SalonControllerApi.removeAdmin`; 204 No Content on success). Backend-
  /// side this UNASSIGNS the admin — it nulls their `salon_id` — it does NOT
  /// delete their account, so the copy around this call must never promise
  /// account deletion.
  ///
  /// Self-removal is refused server-side (403), as is a caller without
  /// management access to the salon. Throws a typed [Failure] like every
  /// other method here; the CALLER maps a 403 to distinct copy, exactly as
  /// [inviteStaff]'s own doc describes — note a bare 403 arrives as
  /// [UnknownFailure], not [ServerFailure] (see `InviteStaffScreen
  /// ._errorMessage`'s doc for why), so read the status off [Failure.cause].
  Future<void> removeAdmin({required String salonId, required String userId});

  /// Moves admin [userId] from salon [salonId] to [destinationSalonId]
  /// (Phase 21.6).
  ///
  /// Wraps `PATCH /salons/{salonId}/admins/{userId}/salon` (the generated
  /// `SalonControllerApi.rotateAdmin`). The destination MUST share the
  /// source salon's owner — enforced server-side with a 403; this method
  /// never re-implements that check client-side. The response body
  /// (`SalonAdminResponse`) carries nothing the caller needs beyond "it
  /// worked", so this resolves with `void`.
  Future<void> rotateAdmin({
    required String salonId,
    required String userId,
    required String destinationSalonId,
  });

  /// Lists the ACTIVE salons sharing [salonId]'s owner, excluding [salonId]
  /// itself — the rotate-admin destination picker's source (Phase 21.6,
  /// backend Phase 21.3b).
  ///
  /// Wraps `GET /salons/{salonId}/sibling-salons`. Owner AND assigned-admin
  /// scoped server-side, which is the whole reason this endpoint exists:
  /// `GET /salons/mine` ([getMySalons]) is owner-only and returns nothing
  /// useful to the admin doing the rotating.
  ///
  /// Routed through the GENERATED [SalonControllerApi.getSiblingSalons] —
  /// unlike [getSalonMasters]/[getSalonReviews], whose generated counterparts
  /// take a typed `Pageable` (see the WIRE-FORMAT NOTE in this file's
  /// header). This operation takes `salonId` ONLY and returns a plain
  /// `List`, so there is no `pageable=` blob to dodge and no reason to
  /// hand-roll the request. Rows are then normalised by
  /// [SiblingSalonOptionMapper.fromDtoList] — see its doc for the two things
  /// the schema itself cannot express (blank-id drop, blank-address
  /// collapse).
  ///
  /// Returns an empty list when the owner has no other active salon (200
  /// `[]`) — the NORMAL single-salon state, not an error. An empty list is
  /// therefore NEVER returned for a payload that merely failed to parse: a
  /// malformed 2xx body degrades to its readable rows (see
  /// `HttpSalonRepository._salvageSiblingSalons`) and throws when none survive.
  Future<List<SiblingSalonOption>> getSiblingSalons(String salonId);
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
  Future<List<Salon>> getMySalons() async {
    try {
      final res = await _salonApi.getOwnedSalons();
      final dtos = res.data?.data ?? const <SalonResponse>[];
      return <Salon>[
        for (final SalonResponse dto in dtos) SalonMapper.fromUpdateDto(dto),
      ];
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMySalons failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    } catch (e, st) {
      // A malformed response (e.g. a row missing the now-required
      // `cityId`/`oblastId`) throws `BuiltValueNullFieldError` — a Dart
      // `Error`, not an `Exception`, so it matches neither arm above and
      // would otherwise propagate with no breadcrumb at all. Log it, then
      // rethrow UNCHANGED — Riverpod's `AsyncNotifier` machinery still maps
      // it to a graceful `UnknownFailure` error screen with retry (see
      // `salon_shell_landing_flow_test.dart`'s mobile-security INFO-1 pin);
      // this only makes that path diagnosable.
      if (kDebugMode) {
        log(
          'getMySalons: malformed response, deserialization failed: $e',
          name: 'salon.repository',
          level: 1000,
          error: e,
          stackTrace: st,
        );
      }
      rethrow;
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
    } catch (e, st) {
      // See `getMySalons`'s identical catch above — a malformed response
      // (missing `cityId`/`oblastId`) throws `BuiltValueNullFieldError`, a
      // Dart `Error` neither arm above matches. Log it, then rethrow
      // UNCHANGED so the resulting `UnknownFailure` error screen is unaffected.
      if (kDebugMode) {
        log(
          'getSalonById: malformed response, deserialization failed: $e',
          name: 'salon.repository',
          level: 1000,
          error: e,
          stackTrace: st,
        );
      }
      rethrow;
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

  @override
  Future<Salon> updateSalon(String salonId, UpdateSalonRequest request) async {
    try {
      final res = await _salonApi.updateSalon(
        salonId: salonId,
        updateSalonRequest: request,
      );
      final dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'updateSalon: ApiResponseSalonResponse.data is null',
            name: 'salon.repository',
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return SalonMapper.fromUpdateDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'updateSalon failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    } catch (e, st) {
      // See `getMySalons`'s identical catch above — a malformed response
      // (missing `cityId`/`oblastId`) throws `BuiltValueNullFieldError`, a
      // Dart `Error` neither arm above matches. Log it, then rethrow
      // UNCHANGED so the resulting `UnknownFailure` error screen is unaffected.
      if (kDebugMode) {
        log(
          'updateSalon: malformed response, deserialization failed: $e',
          name: 'salon.repository',
          level: 1000,
          error: e,
          stackTrace: st,
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteSalon(String salonId) async {
    try {
      await _salonApi.deactivateSalon(salonId: salonId);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'deleteSalon failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<List<BookableMasterAssignment>> getBookableMasters({
    required String salonId,
    required String serviceDefId,
  }) async {
    try {
      final res = await _salonApi.getBookableMasters(
        salonId: salonId,
        serviceDefId: serviceDefId,
      );
      final dtos = res.data?.data;
      if (dtos == null) return const <BookableMasterAssignment>[];
      return SalonBookableMasterMapper.fromDtoList(dtos);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getBookableMasters failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> inviteStaff({
    required String salonId,
    required String email,
    required UserRole role,
  }) async {
    try {
      await _salonApi.inviteMaster(
        salonId: salonId,
        inviteRequest: InviteRequest(
          (InviteRequestBuilder b) => b
            ..email = email
            ..role = _inviteRoleWireValue(role),
        ),
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'inviteStaff failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<List<SalonStaffMember>> getSalonStaff(String salonId) async {
    try {
      final res = await _salonApi.getSalonStaff(salonId: salonId);
      final dtos = res.data?.data ?? const <SalonStaffMemberResponse>[];
      return SalonStaffMemberMapper.fromDtoList(dtos);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getSalonStaff failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<SalonInviteHistory> listSalonInvites(String salonId) async {
    try {
      final res = await _salonApi.listSalonInvites(salonId: salonId);
      // `data` is an OBJECT here, not a bare array: the history envelope
      // wraps the rows so it can carry `truncated` alongside them.
      final SalonInviteHistoryResponse? history = res.data?.data;
      return (
        invites: SalonInviteMapper.fromDtoList(
          history?.invites ?? const <SalonInviteResponse>[],
        ),
        truncated: history?.truncated ?? false,
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'listSalonInvites failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> cancelInvite({
    required String salonId,
    required String inviteId,
  }) async {
    try {
      await _salonApi.cancelInvite(salonId: salonId, inviteId: inviteId);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'cancelInvite failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> removeAdmin({
    required String salonId,
    required String userId,
  }) async {
    try {
      await _salonApi.removeAdmin(salonId: salonId, userId: userId);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'removeAdmin failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> rotateAdmin({
    required String salonId,
    required String userId,
    required String destinationSalonId,
  }) async {
    try {
      await _salonApi.rotateAdmin(
        salonId: salonId,
        userId: userId,
        rotateAdminRequest: RotateAdminRequest(
          (RotateAdminRequestBuilder b) =>
              b..destinationSalonId = destinationSalonId,
        ),
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'rotateAdmin failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<List<SiblingSalonOption>> getSiblingSalons(String salonId) async {
    try {
      final Response<ApiResponseListSiblingSalonOption> response =
          await _salonApi.getSiblingSalons(salonId: salonId);
      // A null/absent `data` is treated as "no siblings", the same way an
      // explicit `[]` is: both mean there is nowhere to rotate to.
      final BuiltList<SiblingSalonOption>? rows = response.data?.data;
      if (rows == null) return const <SiblingSalonOption>[];
      return SiblingSalonOptionMapper.fromDtoList(rows);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      // RECOVERABILITY (deliberate, Phase 21.6 QA MEDIUM). The generated
      // client deserializes the WHOLE envelope in one step, so a single
      // contract-broken row used to fail the entire call — and this screen's
      // `ErrorState` retry re-fetches the identical payload, so the owner was
      // permanently unable to rotate an administrator anywhere. Before giving
      // up, try to read the rows individually off the raw body.
      final List<SiblingSalonOption>? salvaged = _salvageSiblingSalons(e);
      if (salvaged != null) {
        return SiblingSalonOptionMapper.fromDtoList(salvaged);
      }
      if (kDebugMode) {
        log(
          'getSiblingSalons failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    } catch (e, st) {
      // Catch-all fallthrough, matching `getMySalons`/`getSalonById`/
      // `updateSalon` (Phase 21.6 QA LOW): a `BuiltValueNullFieldError` or any
      // other Dart `Error` matches neither arm above and would otherwise
      // escape with no breadcrumb. DIVERGES from those three in ONE respect —
      // they rethrow unchanged, because an existing mobile-security pin
      // (`salon_shell_landing_flow_test.dart` INFO-1) fixes their raw-rethrow
      // behaviour. This path is new and unpinned, so it honours the
      // [SalonRepository] contract literally ("every method ... throws a
      // [Failure] subclass", line 163) instead of leaning on Riverpod to
      // wrap it.
      if (kDebugMode) {
        log(
          'getSiblingSalons: malformed response, deserialization failed: $e',
          name: 'salon.repository',
          level: 1000,
          error: e,
          stackTrace: st,
        );
      }
      throw ServerFailure(statusCode: null, cause: e);
    }
  }

  /// Recovers the still-readable rows of a `GET
  /// /salons/{salonId}/sibling-salons` response whose ENVELOPE failed to
  /// deserialize. Returns `null` when nothing can be salvaged, meaning the
  /// caller must fail the whole call.
  ///
  /// WHY THIS ENDPOINT AND NOT THE OTHERS IN THIS FILE. The whole-call-failure
  /// ruling for `getMySalons`/`getSalonById`/`updateSalon` stands and is not
  /// re-opened here: those return ONE primary resource (or the list that IS
  /// the screen), where a broken payload leaves nothing to show and an error
  /// screen is the honest result. `getSiblingSalons` is a different shape — a
  /// picker of independently actionable ALTERNATIVES, where the remaining N-1
  /// rows stay fully usable without the broken one. That is the same family as
  /// [SalonInviteMapper.fromDtoList] and
  /// [SalonBookableMasterMapper.fromDtoList], which already drop per row in
  /// this very file, and the same policy [SiblingSalonOptionMapper] already
  /// applies to a blank-`id` row. The compile fix narrowed that policy to the
  /// blank-`id` case by accident; this restores it for the structural case.
  ///
  /// TWO INVARIANTS make the degradation safe:
  ///
  ///  * ONLY a 2xx body is salvaged. A non-2xx (or an absent response, i.e. a
  ///    transport failure) keeps its mapped [Failure] untouched — a 403/404
  ///    error envelope must never be mined for rows.
  ///  * NEVER degrade to an EMPTY list. `[]` is load-bearing on this screen —
  ///    it renders "you own no other salon" — so returning it for a payload we
  ///    merely could not read would state something false. Zero survivors stays
  ///    a whole-call failure, and in that case the `ErrorState` retry is no
  ///    longer a lie: a total contract break is a server-side fault that a
  ///    backend rollback/redeploy genuinely does fix.
  ///
  /// The drop is logged UNGATED (unlike this file's routine `kDebugMode`
  /// per-call-site logs): a backend contract break is not routine and must be
  /// visible in release telemetry. Only counts are logged — never a row.
  List<SiblingSalonOption>? _salvageSiblingSalons(DioException e) {
    final Response<dynamic>? response = e.response;
    final int? status = response?.statusCode;
    if (response == null || status == null || status < 200 || status >= 300) {
      return null;
    }
    final Object? body = response.data;
    if (body is! Map) return null;
    final Object? rows = body['data'];
    if (rows is! List) return null;

    final List<SiblingSalonOption> kept = <SiblingSalonOption>[];
    int dropped = 0;
    for (final Object? row in rows) {
      try {
        final SiblingSalonOption? option = _deserialize<SiblingSalonOption>(
          row,
          const FullType(SiblingSalonOption),
        );
        if (option == null) {
          dropped++;
          continue;
        }
        kept.add(option);
      } catch (_) {
        dropped++;
      }
    }
    if (kept.isEmpty) return null;
    log(
      'sibling-salons: malformed payload — salvaged ${kept.length} row(s), '
      'dropped $dropped unreadable row(s)',
      name: 'salon.repository',
      level: 1000,
    );
    return kept;
  }

  /// Maps the domain [UserRole] to the generated invite wire enum. [role]
  /// must be [UserRole.salonAdmin] or [UserRole.salonMaster] — this
  /// repository never invites any other role (see [inviteStaff]'s own doc).
  InviteRequestRoleEnum _inviteRoleWireValue(UserRole role) => switch (role) {
    UserRole.salonAdmin => InviteRequestRoleEnum.SALON_ADMIN,
    UserRole.salonMaster => InviteRequestRoleEnum.SALON_MASTER,
    UserRole.client || UserRole.salonOwner || UserRole.independentMaster =>
      throw ArgumentError('inviteStaff: unsupported role $role'),
  };

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
  ///
  /// `badCertificate` gets its own branch (mobile-security LOW fix,
  /// bookable-masters audit — project-wide pattern tracked at backlog line
  /// 47) rather than being lumped into the `badResponse`/`cancel`/`unknown`
  /// catch-all: a TLS/pinning failure is a possible MITM, not a transient
  /// server hiccup, and folding it into the same log signal made the two
  /// indistinguishable in telemetry. The failure type returned to the UI is
  /// unchanged ([ServerFailure] — still fails closed); only the log signal
  /// is distinct. This is an in-file fix only — the full cross-repository
  /// sweep remains a separate backlog item.
  Failure _mapDioException(DioException e) {
    if (e.error is Failure) return e.error as Failure;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(cause: e);
      case DioExceptionType.badCertificate:
        // Deliberately NOT gated behind `kDebugMode` (unlike the routine
        // per-call-site DioException logs elsewhere in this file): a
        // possible MITM must be visible in release-build telemetry, not
        // only local debug runs. No PII or token is logged — just the fact
        // that certificate validation failed for this repository's traffic.
        log(
          'TLS/certificate validation failed for salon read — possible MITM',
          name: 'salon.repository.security',
          level: 1000,
        );
        return ServerFailure(statusCode: e.response?.statusCode, cause: e);
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
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
