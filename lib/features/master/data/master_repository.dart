// Phase 4.1 — MasterRepository extended with getMyProfile.
//
// Phase 2.19 introduced [HttpMasterRepository] with a hand-written Dio
// implementation of [updateLocality]. Phase 4.1 adds [getMyProfile], which
// uses the generated [MasterControllerApi] (via [masterApiProvider]) so that
// deserialization of the `MasterDetailResponse` envelope is handled by the
// generated built_value serializers — no manual JSON parsing needed.
//
// The constructor now accepts both [Dio] (for [updateLocality]) and
// [MasterControllerApi] (for [getMyProfile]). Both are injected via
// [masterRepositoryProvider] — never construct directly.
//
// Backend contracts:
//   PATCH /api/v1/independent-masters/me — see Phase 2.19 comment.
//   GET   /api/v1/masters/{masterId}     — returns ApiResponse<MasterDetailResponse>.
//
// AppConfig.baseUrl does NOT carry the `/api/v1` prefix (see app_config.dart).
// All paths here must include the full `/api/v1/` segment explicitly.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/api_client_provider.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'master_mapper.dart';
import 'master_review_mapper.dart';

part 'master_repository.g.dart';

/// Default page size for the master received-reviews list (Phase 4.5). Matches
/// the salon reviews page size — first page only, no infinite scroll.
const int kMasterReviewsPageSize = 20;

/// Contract for the independent-master profile layer.
///
/// Every method either resolves successfully or throws a [Failure] subclass
/// from `core/errors/failures.dart`. Raw [DioException]s are caught inside the
/// implementation and never escape.
abstract interface class MasterRepository {
  /// Persists the authenticated master's working address.
  ///
  /// Wraps `PATCH /independent-masters/me`. [districtId] and [locationNote] are
  /// optional — pass `null` for a city without districts / no note. Throws a
  /// typed [Failure] on any transport or server error.
  Future<void> updateLocality({
    required String cityId,
    String? districtId,
    required String street,
    required String buildingNo,
    String? locationNote,
  });

  /// Fetches the master profile for the given [masterId].
  ///
  /// Wraps `GET /masters/{masterId}`. For the authenticated master's own
  /// profile, pass the user's id (available from [AuthSession.user.id]).
  /// Throws a typed [Failure] on any transport or server error.
  Future<Master> getMyProfile(String masterId);

  /// Fetches the PUBLIC profile for an arbitrary [masterId].
  ///
  /// Wraps `GET /masters/{masterId}` via the generated [MasterControllerApi]'s
  /// `getMasterDetail`. Unlike [getMyProfile] (which resolves the master from
  /// the JWT principal), this reads any master by id and is safe to call from a
  /// CLIENT session — it drives the client-facing public master profile
  /// (Phase 13.5). Throws a typed [Failure] on any transport or server error.
  Future<Master> getMasterById(String masterId);

  /// Persists the authenticated master's editable profile fields.
  ///
  /// Wraps `PATCH /independent-masters/me/profile`. All [update] fields are
  /// trimmed before sending. Backend contract (`UserService.updateMasterProfile`):
  ///   - `bio` and `instagram` are written whenever the key is **non-null**, so
  ///     an empty string `''` clears them server-side. They are therefore ALWAYS
  ///     included in the body (sending the trimmed value, `''` on clear).
  ///   - `phoneNumber` / `firstName` / `lastName` are REQUIRED — the edit form
  ///     blocks Save when any is empty, so they always arrive non-blank. They
  ///     are also filtered for blank (`!s.isBlank()`) on the backend, so phone
  ///     can never be cleared by design — `phoneNumber` is omitted when blank.
  /// Throws a typed [Failure] on any transport or server error; throws
  /// [ValidationFailure] with [fieldErrors] when the backend returns HTTP 422.
  Future<void> updateMyProfile(MasterUpdate update);

  /// Fetches the aggregate review summary (average + 5★→1★ distribution) for
  /// [masterId].
  ///
  /// Wraps `GET /masters/{masterId}/reviews/summary`. For the authenticated
  /// master's own reviews, pass the session user id (see Phase 4.5). Throws a
  /// typed [Failure] on any transport or server error.
  Future<MasterReviewSummary> getMasterReviewSummary(String masterId);

  /// Fetches one page of [masterId]'s received reviews, server-sorted by
  /// [sort].
  ///
  /// Wraps `GET /masters/{masterId}/reviews?sort=&page=&size=`. [page] is
  /// zero-based; [size] caps the page. Throws a typed [Failure] on any
  /// transport or server error.
  Future<List<MasterReviewItem>> getMasterReviews({
    required String masterId,
    required MasterReviewSort sort,
    int page = 0,
    int size = kMasterReviewsPageSize,
  });
}

/// HTTP implementation of [MasterRepository].
///
/// Inject via [masterRepositoryProvider] — never construct directly.
///
/// [_dio] drives [updateLocality] (hand-written PATCH envelope).
/// [_masterApi] drives [getMyProfile] using the generated [MasterControllerApi]
/// so that built_value deserialization handles the response envelope.
final class HttpMasterRepository implements MasterRepository {
  HttpMasterRepository(this._dio, this._masterApi);

  final Dio _dio;
  final MasterControllerApi _masterApi;

  @override
  Future<void> updateLocality({
    required String cityId,
    String? districtId,
    required String street,
    required String buildingNo,
    String? locationNote,
  }) async {
    // Build the body explicitly so null / empty optionals are omitted rather
    // than sent as `null` strings (backlog pattern 5 — trim once).
    final trimmedNote = locationNote?.trim();
    final body = <String, dynamic>{
      'cityId': cityId,
      'street': street.trim(),
      'buildingNo': buildingNo.trim(),
    };
    if (districtId != null && districtId.isNotEmpty) {
      body['districtId'] = districtId;
    }
    if (trimmedNote != null && trimmedNote.isNotEmpty) {
      body['locationNote'] = trimmedNote;
    }

    await _runIdempotentPatch(
      operation: 'updateLocality',
      request: () => _dio.patch<Map<String, dynamic>>(
        '/api/v1/independent-masters/me',
        data: body,
      ),
    );
  }

  @override
  Future<Master> getMyProfile(String masterId) async {
    try {
      // Uses GET /masters/me — the backend resolves masterId from the
      // authenticated JWT. The masterId parameter is kept on the interface
      // for mapper compatibility but is not sent over the wire.
      final res = await _masterApi.getMyProfile();
      final dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'getMyProfile: ApiResponseMasterDetailResponse.data is null',
            name: 'master.repository',
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return MasterMapper.fromDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMyProfile failed: ${e.type} ${e.response?.statusCode}',
          name: 'master.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<Master> getMasterById(String masterId) async {
    try {
      // GET /masters/{masterId} — the public master-detail endpoint, keyed on
      // the Master-row UUID (NOT the User UUID). Uses the generated
      // [MasterControllerApi] so built_value deserialization handles the
      // ApiResponse<MasterDetailResponse> envelope.
      final res = await _masterApi.getMasterDetail(masterId: masterId);
      final dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'getMasterById: ApiResponseMasterDetailResponse.data is null',
            name: 'master.repository',
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return MasterMapper.fromDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMasterById failed: ${e.type} ${e.response?.statusCode}',
          name: 'master.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> updateMyProfile(MasterUpdate update) async {
    // Trim all values before building the body so the backend never receives
    // untrimmed whitespace.
    //
    // Endpoint: PATCH /independent-masters/me/profile (not /me, which is the
    // locality endpoint). Field name is 'phoneNumber' (not 'contactPhone') to
    // match MasterProfileUpdateRequest on the backend.
    //
    // Backend contract (UserService.updateMasterProfile):
    //   - bio / instagram are persisted whenever the key is non-null, so an
    //     empty string '' CLEARS them. We therefore ALWAYS include both keys,
    //     sending the trimmed value ('' on clear) so a user-cleared field
    //     actually persists. Omitting the key (the old bug) left the stale
    //     server value untouched.
    //   - phoneNumber is REQUIRED — the edit form blocks Save when it is empty,
    //     so it always arrives non-blank. It is also filtered for blank
    //     server-side (!s.isBlank()) and cannot clear by design, so the
    //     omit-on-blank guard below is now purely defensive (unreachable in
    //     practice) — keep it.
    final body = <String, dynamic>{
      'firstName': update.firstName,
      'lastName': update.lastName,
      'bio': update.bio.trim(), // '' clears server-side
      'instagram': update.instagram.trim(), // '' clears server-side
      'professionalTitle': update.professionalTitle
          .trim(), // '' clears server-side
    };
    final trimmedPhone = update.contactPhone.trim();
    if (trimmedPhone.isNotEmpty) body['phoneNumber'] = trimmedPhone;

    await _runIdempotentPatch(
      operation: 'updateMyProfile',
      request: () => _dio.patch<Map<String, dynamic>>(
        '/api/v1/independent-masters/me/profile',
        data: body,
      ),
    );
  }

  @override
  Future<MasterReviewSummary> getMasterReviewSummary(String masterId) async {
    // Raw GET through the shared authenticated [Dio], decoded with the SAME
    // [standardSerializers] the generated client uses — mirroring
    // [HttpSalonRepository.getSalonReviews]'s decode path. A raw GET (rather
    // than the generated `ReviewControllerApi.getMasterReviewSummary`) keeps
    // this repository on the single injected Dio (no second client, no
    // constructor churn) while still producing a generated built_value DTO.
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/masters/${Uri.encodeComponent(masterId)}/reviews/summary',
      );
      final decoded = _deserialize<ApiResponseMasterReviewSummaryResponse>(
        response.data,
        const FullType(ApiResponseMasterReviewSummaryResponse),
      );
      final dto = decoded?.data;
      if (dto == null) return const MasterReviewSummary();
      return MasterReviewMapper.summaryFromDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMasterReviewSummary failed: ${e.type} ${e.response?.statusCode}',
          name: 'master.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    } catch (e, st) {
      // Total catch: a built_value deserialization error surfaces as a raw
      // TypeError/Error — wrap it as a typed ServerFailure so NO raw error
      // reaches the UI (mirrors [_runIdempotentPatch]'s guarantee). Only the
      // runtimeType is logged — never PII / review comments.
      if (kDebugMode) {
        log(
          'getMasterReviewSummary unexpected error: ${e.runtimeType}',
          name: 'master.repository',
          level: 1000,
          stackTrace: st,
        );
      }
      throw ServerFailure(cause: e);
    }
  }

  @override
  Future<List<MasterReviewItem>> getMasterReviews({
    required String masterId,
    required MasterReviewSort sort,
    int page = 0,
    int size = kMasterReviewsPageSize,
  }) async {
    // WIRE-FORMAT NOTE: the generated `ReviewControllerApi.getReviewsByMaster`
    // takes a typed `Pageable` whose `encodeQueryParameter` JSON-encodes the
    // whole object into a single `pageable=` value — Spring expects FLAT
    // `page`/`size` keys (the same bug documented in
    // `HttpSalonRepository.getSalonReviews`). So bypass it: issue a raw GET with
    // flat query params and deserialize with the shared serializers.
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/masters/${Uri.encodeComponent(masterId)}/reviews',
        queryParameters: <String, dynamic>{
          'sort': sort.wireValue,
          'page': page,
          'size': size,
        },
      );
      final decoded = _deserialize<ApiResponsePageResponseReviewResponse>(
        response.data,
        const FullType(ApiResponsePageResponseReviewResponse),
      );
      final content = decoded?.data?.data ?? const <ReviewResponse>[];
      return MasterReviewMapper.reviewsFromDtoList(content);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMasterReviews failed: ${e.type} ${e.response?.statusCode}',
          name: 'master.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    } catch (e, st) {
      // Total catch: a built_value deserialization error surfaces as a raw
      // TypeError/Error — wrap it as a typed ServerFailure so NO raw error
      // reaches the UI (mirrors [_runIdempotentPatch]'s guarantee). Only the
      // runtimeType is logged — never PII / review comments.
      if (kDebugMode) {
        log(
          'getMasterReviews unexpected error: ${e.runtimeType}',
          name: 'master.repository',
          level: 1000,
          stackTrace: st,
        );
      }
      throw ServerFailure(cause: e);
    }
  }

  /// Deserializes a raw JSON [data] map via the SAME [standardSerializers] the
  /// generated client uses. Returns `null` when [data] is null (an empty body);
  /// any deserialization failure propagates to the caller's `catch` as a
  /// [ServerFailure] (this helper deliberately does not swallow errors).
  T? _deserialize<T>(Object? data, FullType type) {
    if (data == null) return null;
    return standardSerializers.deserialize(data, specifiedType: type) as T?;
  }

  /// Runs an idempotent PATCH upsert with a total catch and a bounded
  /// single retry for transient auth/network failures.
  ///
  /// Both `/independent-masters/me` and `/independent-masters/me/profile` are
  /// idempotent upserts, so replaying once is safe. The retry only fires for a
  /// transient [UnauthorizedFailure] (a 401 that triggered a token refresh — by
  /// the second attempt the token is fresh) or a [NetworkFailure] (a single
  /// transport hiccup). Real auth expiry / persistent network loss surfaces on
  /// the second failure, exactly as before, so the retry can never hide a
  /// genuine logout. All other failures rethrow on the first attempt.
  ///
  /// Catch order is total: the [DioException] arm maps to a typed [Failure];
  /// `on Failure { rethrow }` passes through any [Failure] already produced
  /// upstream (e.g. by [RefreshInterceptor]); the final `catch` wraps any
  /// remaining non-[Failure] (a stray `TypeError`/`Error`) as a [ServerFailure]
  /// so NO raw error can ever escape to the screen as errUnknown.
  Future<void> _runIdempotentPatch({
    required String operation,
    required Future<Response<Map<String, dynamic>>> Function() request,
  }) async {
    var attemptedRetry = false;
    while (true) {
      try {
        await request();
        return;
      } on Failure catch (f) {
        if (!attemptedRetry &&
            (f is UnauthorizedFailure || f is NetworkFailure)) {
          attemptedRetry = true;
          if (kDebugMode) {
            log(
              '$operation transient ${f.runtimeType} — retrying once',
              name: 'master.repository',
              level: 800,
            );
          }
          continue;
        }
        rethrow;
      } on DioException catch (e, st) {
        if (kDebugMode) {
          log(
            '$operation failed: ${e.type} ${e.response?.statusCode}',
            name: 'master.repository',
            level: 900,
            stackTrace: st,
          );
        }
        final failure = _mapDioException(e);
        if (!attemptedRetry &&
            (failure is UnauthorizedFailure || failure is NetworkFailure)) {
          attemptedRetry = true;
          if (kDebugMode) {
            log(
              '$operation transient ${failure.runtimeType} — retrying once',
              name: 'master.repository',
              level: 800,
            );
          }
          continue;
        }
        throw failure;
      } catch (e, st) {
        if (kDebugMode) {
          log(
            '$operation unexpected error: ${e.runtimeType}',
            name: 'master.repository',
            level: 1000,
            error: e,
            stackTrace: st,
          );
        }
        throw ServerFailure(cause: e);
      }
    }
  }

  /// Maps a [DioException] to a typed [Failure].
  ///
  /// If [ErrorMapperInterceptor] has already attached a [Failure] as `e.error`,
  /// that value is re-thrown directly; otherwise the Dio type is inspected so
  /// connectivity issues surface as [NetworkFailure] and everything else as
  /// [ServerFailure]. Raw [DioException] never escapes.
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

/// Provides the [MasterRepository] singleton backed by the authenticated Dio
/// and the generated [MasterControllerApi].
///
/// Override in tests with a mocktail mock — never construct
/// [HttpMasterRepository] directly in tests.
@Riverpod(keepAlive: true)
MasterRepository masterRepository(Ref ref) =>
    HttpMasterRepository(ref.watch(dioProvider), ref.watch(masterApiProvider));
