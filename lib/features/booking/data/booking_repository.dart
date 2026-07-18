// Phase 14.0 — BookingRepository: interface + HTTP implementation.
//
// Wraps the CLIENT-side authenticated booking write/read path:
//   POST   /api/v1/bookings                     → create
//   GET    /api/v1/bookings/me                   → paged "my bookings" list
//   GET    /api/v1/bookings/{bookingId}           → enriched detail (19.3)
//   PATCH  /api/v1/bookings/{bookingId}/cancel     → cancel
//   PATCH  /api/v1/bookings/{bookingId}/reschedule → reschedule (19.2)
//
// Kept provider-free on purpose (mirrors `schedule_repository.dart` /
// `favorite_repository.dart`) — see `booking_providers.dart` for the Riverpod
// wiring. Tests construct [HttpBookingRepository] directly with a mocktail
// [Dio] + [BookingControllerApi].
//
// NOT used: `PublicBookingControllerApi` — that is the unauthenticated
// guest-booking flow, a different feature. This repository is the
// authenticated CLIENT booking flow only.
//
// WIRE-FORMAT NOTE (getMyBookings pagination): the generated
// `BookingControllerApi.listMyBookings` takes a typed `Pageable` parameter,
// whose generated `encodeQueryParameter` JSON-encodes the WHOLE object into a
// single `pageable=` query value — the exact bug documented in
// `salon_repository.dart` / `discovery/data/search_repository.dart` (Spring's
// `PageableHandlerMethodArgumentResolver` expects FLAT `page`/`size`/`sort`
// query keys, not one nested blob). [getMyBookings] therefore bypasses
// `listMyBookings` and issues a raw GET through the shared authenticated
// [Dio] with flat query params, deserializing the response with the SAME
// [standardSerializers] the generated client uses.
//
// NAMING COLLISION: the domain `CreateBookingRequest`
// (`features/booking/domain/create_booking_request.dart`) and the generated
// wire `CreateBookingRequest` (`beautica_api`) share the exact same class
// name (per the phase doc's Step 8 sketch). Resolved below via a `hide` +
// aliased-`show` import pair rather than renaming either type.
//
// AppConfig.baseUrl does NOT carry the `/api/v1` prefix (see app_config.dart).
// All raw-Dio paths here must include the full `/api/v1/` segment explicitly.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart' hide CreateBookingRequest;
import 'package:beautica_api/beautica_api.dart'
    as wire
    show CreateBookingRequest;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../domain/booking.dart';
import '../domain/booking_status.dart';
import '../domain/create_booking_request.dart';
import 'booking_mapper.dart';

/// Default page size for the "my bookings" list (Phase 14.3).
const int kBookingsPageSize = 20;

const String _tag = 'feature.booking.repository';

/// Contract for the authenticated CLIENT booking layer.
///
/// Every method either resolves successfully or throws a [Failure] subclass
/// from `core/errors/failures.dart`. Raw [DioException]s never escape.
abstract interface class BookingRepository {
  /// Creates a booking for the authenticated client.
  ///
  /// Wraps `POST /bookings`. The create endpoint itself returns the LEAN
  /// `BookingResponse` (no enriched master/service/address fields), so this
  /// method follows up with [getBookingById] and returns the fully-enriched
  /// [Booking] the detail/confirmation screens need — see the file header of
  /// `booking_mapper.dart` for why `Booking` mirrors `BookingDetailResponse`.
  ///
  /// Throws [ConflictFailure] on HTTP 409 (the slot was taken between the
  /// client fetching available slots and submitting — or, under contention, a
  /// server-side lock timeout), or [ClientBookingConflictFailure] on HTTP 409
  /// when the CLIENT already has an overlapping booking of their own (see that
  /// failure's doc). Throws [BookingRateLimitedFailure] on HTTP 429 (per-user
  /// booking-write rate limit).
  Future<Booking> createBooking(CreateBookingRequest req);

  /// Fetches one page of the authenticated client's bookings, server-sorted
  /// by `startsAt` in the direction [ascending] requests.
  ///
  /// Wraps `GET /bookings/me`. [statuses] narrows to the given [BookingStatus]
  /// set, sent as REPEATED `status` query params in one request (backend
  /// Phase 26.1 — `EnumSet`-normalised and unioned server-side, then
  /// globally paginated — this is what lets a tab spanning two statuses, e.g.
  /// Минулі's `COMPLETED`+`NOT_COMPLETED`, read as ONE correctly-ordered,
  /// correctly-paginated stream instead of merging two independently-paged
  /// fetches client-side). Pass an empty set for no status filter (all
  /// statuses).
  ///
  /// [ascending] drives the `sort=startsAt,<asc|desc>` param (backend Phase
  /// 26.3): `true` for soonest-first ("what's next" — the Майбутні tab),
  /// `false` for most-recent-first ("what just happened" — Минулі/Скасовані).
  /// Only `startsAt` is sent — the client «Мої записи» screen has no sort
  /// sheet, unlike the independent-master booking list.
  ///
  /// [page] is zero-based; [size] caps the page (default [kBookingsPageSize]).
  Future<PageResponse<Booking>> getMyBookings({
    required Set<BookingStatus> statuses,
    required bool ascending,
    required int page,
    int size = kBookingsPageSize,
  });

  /// Fetches the enriched detail for a single booking.
  ///
  /// Wraps `GET /bookings/{bookingId}` (backend 19.3 enrichment). Throws
  /// [NotFoundFailure] on HTTP 404.
  Future<Booking> getBookingById(String id);

  /// Cancels a booking on behalf of the authenticated client.
  ///
  /// Wraps `PATCH /bookings/{bookingId}/cancel`. [reason] is forwarded as the
  /// free-text `comment`; the `cancellationReason` enum is always sent as
  /// `CLIENT_CANCELLED` — this repository only ever cancels the client's OWN
  /// booking (the master/no-show/duplicate reasons are provider-side
  /// concerns, not exposed here).
  Future<void> cancelBooking(String id, {String? reason});

  /// Reschedules a booking to a new start time.
  ///
  /// Wraps `PATCH /bookings/{bookingId}/reschedule` (backend 19.2). Pre-track
  /// 24.x, a CONFIRMED booking was moved back to PENDING server-side;
  /// `PENDING` is now retired (booking auto-confirm) and a rescheduled
  /// booking simply stays CONFIRMED — the returned [Booking] reflects
  /// whatever status the server computed either way. Throws
  /// [ConflictFailure] on HTTP 409 (new slot taken, or the booking is no
  /// longer in a reschedulable state — or, under contention, a server-side
  /// lock timeout), or [ClientBookingConflictFailure] on HTTP 409 when the
  /// CLIENT already has a DIFFERENT overlapping booking of their own at the
  /// new time (see that failure's doc). Throws [BookingRateLimitedFailure] on
  /// HTTP 429 (per-user booking-write rate limit).
  Future<Booking> rescheduleBooking(String id, DateTime newStartAt);

  /// Leaves a review for a COMPLETED booking on behalf of the authenticated
  /// client (Phase 14.6).
  ///
  /// Wraps `POST /reviews`. [rating] is 1–5; [comment] is optional free text
  /// (an empty/blank string is sent as null so the backend sees no comment).
  /// The backend enforces COMPLETED + booking ownership + not-already-reviewed
  /// — the client must not re-derive those beyond the `Booking.canReview`
  /// gate. Throws [ReviewAlreadyExistsFailure] on HTTP 409 (already reviewed)
  /// and [ReviewNotAllowedFailure] on 403 (not the owner) / other 4xx (e.g. the
  /// booking is not COMPLETED).
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  });
}

/// HTTP implementation of [BookingRepository].
///
/// Inject via [bookingRepositoryProvider] — never construct directly outside
/// tests.
final class HttpBookingRepository implements BookingRepository {
  HttpBookingRepository(this._dio, this._bookingApi, this._reviewApi);

  final Dio _dio;
  final BookingControllerApi _bookingApi;
  final ReviewControllerApi _reviewApi;

  @override
  Future<Booking> createBooking(CreateBookingRequest req) async {
    final String bookingId;
    try {
      final res = await _bookingApi.createBooking(
        createBookingRequest: _toWireCreateRequest(req),
        idempotencyKey: req.idempotencyKey,
      );
      final id = res.data?.data?.id;
      if (id == null || id.isEmpty) {
        if (kDebugMode) {
          log('createBooking: response id is null', name: _tag, level: 1000);
        }
        throw const ServerFailure(statusCode: null);
      }
      bookingId = id;
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'createBooking failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapBookingWriteException(e);
    }

    return getBookingById(bookingId);
  }

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Set<BookingStatus> statuses,
    required bool ascending,
    required int page,
    int size = kBookingsPageSize,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/bookings/me',
        queryParameters: <String, dynamic>{
          'page': page,
          'size': size,
          'sort': 'startsAt,${ascending ? 'asc' : 'desc'}',
          // A List value renders as REPEATED bare `status=` params under
          // Dio's default `ListFormat.multi` — mirrors the identical
          // `serviceTypeSlugs` precedent in
          // `discovery/data/search_repository.dart`. Spring's `Pageable`/
          // `@RequestParam` resolver binds repeated same-name params into the
          // backend's `EnumSet<BookingStatus>` (Phase 26.1). Omitted entirely
          // when empty so the backend applies no status filter.
          if (statuses.isNotEmpty)
            'status': statuses
                .map((BookingStatus s) => s.wireValue)
                .toList(growable: false),
        },
      );
      final decoded =
          _deserialize<ApiResponsePageResponseBookingDetailResponse>(
            response.data,
            const FullType(ApiResponsePageResponseBookingDetailResponse),
          );
      final pageDto = decoded?.data;
      final content = pageDto?.data ?? const <BookingDetailResponse>[];
      return PageResponse<Booking>(
        items: BookingMapper.fromDtoList(content),
        page: pageDto?.page ?? page,
        totalPages: pageDto?.totalPages ?? 0,
        totalElements: pageDto?.totalElements ?? 0,
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMyBookings failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<Booking> getBookingById(String id) async {
    try {
      final res = await _bookingApi.getBooking(bookingId: id);
      final dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'getBookingById: ApiResponseBookingDetailResponse.data is null',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return BookingMapper.fromDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getBookingById failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> cancelBooking(String id, {String? reason}) async {
    try {
      await _bookingApi.cancelBooking(
        bookingId: id,
        cancelBookingRequest: CancelBookingRequest(
          (b) => b
            ..cancellationReason =
                CancelBookingRequestCancellationReasonEnum.CLIENT_CANCELLED
            ..comment = reason,
        ),
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'cancelBooking failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapBookingCancelException(e);
    }
  }

  @override
  Future<Booking> rescheduleBooking(String id, DateTime newStartAt) async {
    try {
      final res = await _bookingApi.rescheduleBooking(
        bookingId: id,
        rescheduleBookingRequest: RescheduleBookingRequest(
          (b) => b..newStartsAt = newStartAt,
        ),
      );
      final dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'rescheduleBooking: response data is null',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return BookingMapper.fromDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'rescheduleBooking failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapBookingWriteException(e);
    }
  }

  @override
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) async {
    // Blank/whitespace-only comment → send no comment at all (the field is
    // optional on the wire; a null keeps the payload clean).
    final String? trimmed = comment?.trim();
    final String? effectiveComment = (trimmed == null || trimmed.isEmpty)
        ? null
        : trimmed;
    try {
      await _reviewApi.createReview(
        createReviewRequest: CreateReviewRequest(
          (b) => b
            ..bookingId = bookingId
            ..rating = rating
            ..comment = effectiveComment,
        ),
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'createReview failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapReviewException(e);
    }
  }

  /// Maps a [DioException] from `POST /reviews` to a typed [Failure]
  /// (Phase 14.6).
  ///
  ///   - **409** → [ReviewAlreadyExistsFailure] (the client already reviewed
  ///     this booking).
  ///   - **403** (not the booking owner) or any other **4xx** (e.g. the booking
  ///     is not COMPLETED) → [ReviewNotAllowedFailure] — a single friendly
  ///     "can't be reviewed" message; the client never distinguishes the two.
  ///
  /// The status-code checks run BEFORE deferring to any [Failure] the
  /// [ErrorMapperInterceptor] may have attached (it maps a generic 409/403 to
  /// [ServerFailure] with no review-specific copy), mirroring the
  /// `MasterAlreadyHasServicesFailure` precedent. All other statuses defer to
  /// the shared [_mapDioException] (which honours any attached [Failure] and
  /// otherwise maps by transport type).
  Failure _mapReviewException(DioException e) {
    final int? statusCode = e.response?.statusCode;
    if (statusCode == 409) return ReviewAlreadyExistsFailure(cause: e);
    if (statusCode == 403 || statusCode == 400 || statusCode == 422) {
      return ReviewNotAllowedFailure(cause: e);
    }
    return _mapDioException(e);
  }

  /// Builds the generated wire `CreateBookingRequest` DTO from the domain
  /// [CreateBookingRequest]. The `idempotencyKey` is sent BOTH as the
  /// `Idempotency-Key` request header (the generated client's dedicated
  /// param — the conventional REST-idempotency channel) AND on the body,
  /// since the generated schema exposes the field on both the header param
  /// and the body DTO and the backend contract for which channel it actually
  /// reads is not observable from the OpenAPI spec alone. Sending both is
  /// harmless and guarantees correctness either way.
  wire.CreateBookingRequest _toWireCreateRequest(CreateBookingRequest req) {
    return wire.CreateBookingRequest(
      (b) => b
        ..masterId = req.masterId
        ..masterServiceId = req.serviceId
        ..startsAt = req.startAt
        ..idempotencyKey = req.idempotencyKey
        ..clientComment = req.clientComment,
    );
  }

  /// Deserializes a raw JSON [data] map via the SAME [standardSerializers]
  /// the generated client uses. Returns `null` when [data] is null (an empty
  /// body).
  ///
  /// Unlike the generated API client's own methods (e.g. [BookingControllerApi
  /// .getBooking]), which wrap their internal `_serializers.deserialize` call
  /// in a try/catch that re-throws as a [DioException] — letting the standard
  /// `on DioException` clause below map it to a typed [Failure] — this method
  /// is invoked directly against the raw [Dio] response (see the file header
  /// WIRE-FORMAT NOTE for why `getMyBookings` bypasses the generated client).
  /// `standardSerializers.deserialize` throws its own built_value error type
  /// (e.g. on an enum wire value it doesn't recognize), which is neither a
  /// [DioException] nor a [Failure] — so without this catch it would escape
  /// the caller's `on Failure` / `on DioException` clauses as a raw,
  /// unmapped exception. Caught here and re-thrown as [UnknownFailure] so it
  /// is always caught by the caller's `on Failure { rethrow; }` clause,
  /// preserving the "repositories only ever throw `Failure`" contract
  /// (`core/errors/failures.dart`).
  T? _deserialize<T>(Object? data, FullType type) {
    if (data == null) return null;
    try {
      return standardSerializers.deserialize(data, specifiedType: type) as T?;
    } on Failure {
      rethrow;
    } catch (e, st) {
      if (kDebugMode) {
        log(
          '_deserialize<$T> failed: ${e.runtimeType}',
          name: _tag,
          level: 1000,
          stackTrace: st,
        );
      }
      throw UnknownFailure(cause: e);
    }
  }

  /// Maps a [DioException] from a booking WRITE (create/reschedule) to a typed
  /// [Failure].
  ///
  ///   - **409** with `data.code == "CLIENT_BOOKING_CONFLICT"` →
  ///     [ClientBookingConflictFailure] — the authenticated CLIENT already has
  ///     an overlapping PENDING/CONFIRMED booking (backend commit f95d8fd).
  ///     Distinct from a plain 409, which still means the MASTER's slot is
  ///     taken (or, under contention, a server-side lock timeout — the backend
  ///     surfaces both as the same bare `data: null` envelope, so both
  ///     legitimately fall through to the line below).
  ///   - **409** otherwise → [ConflictFailure] (the slot was taken / no longer
  ///     reschedulable / a lock-timeout retry case).
  ///   - **429** → [BookingRateLimitedFailure] (per-user booking-write rate
  ///     limit, backend commit f95d8fd).
  ///
  /// The 409/429 status checks run BEFORE deferring to any [Failure] the
  /// [ErrorMapperInterceptor] may have attached — it maps a generic 409 to
  /// [ServerFailure] (no slot-conflict copy) and has no booking-specific 429
  /// case at all (an unmatched 429 would otherwise surface as [UnknownFailure])
  /// — mirroring the `MasterAlreadyHasServicesFailure` /
  /// `CategoryRequestThrottledFailure` precedents in
  /// `services/data/service_repository.dart`.
  ///
  /// All other statuses defer to [_mapDioException].
  Failure _mapBookingWriteException(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 409) {
      // BOOKING_ALREADY_ELAPSED (backend 952e441): the booking's window is
      // already past the SERVER clock — checked before the slot-conflict
      // fallbacks (the reschedule endpoint shares the 409 status with both).
      if (_isBookingAlreadyElapsed(e)) {
        return BookingAlreadyElapsedFailure(cause: e);
      }
      return _extractClientBookingConflict(e) ?? ConflictFailure(cause: e);
    }
    if (statusCode == 429) return BookingRateLimitedFailure(cause: e);
    if (e.error is Failure) return e.error as Failure;
    return _mapDioException(e);
  }

  /// Maps a [DioException] from `PATCH /bookings/{id}/cancel` to a typed
  /// [Failure]. The one case that needs special handling is the
  /// `BOOKING_ALREADY_ELAPSED` 409 (backend 952e441) — the booking already
  /// ended server-side, so it can no longer be cancelled. Everything else
  /// defers to the shared [_mapDioException] (a plain 409 stays a
  /// [ServerFailure], as before).
  Failure _mapBookingCancelException(DioException e) {
    if (e.response?.statusCode == 409 && _isBookingAlreadyElapsed(e)) {
      return BookingAlreadyElapsedFailure(cause: e);
    }
    return _mapDioException(e);
  }

  /// `true` when [e] is a 409 whose body is the
  /// `{ "data": { "code": "BOOKING_ALREADY_ELAPSED" } }` envelope (backend
  /// 952e441). Hand-decoded from the raw JSON body — like
  /// [_extractClientBookingConflict], this code is not part of the generated
  /// OpenAPI client (the local backend can't currently boot to refresh the
  /// spec snapshot — see CLAUDE.md). Any non-map / non-matching body returns
  /// `false` so the caller falls back to its generic mapping.
  bool _isBookingAlreadyElapsed(DioException e) {
    final body = e.response?.data;
    if (body is! Map<String, dynamic>) return false;
    final data = body['data'];
    if (data is! Map<String, dynamic>) return false;
    return data['code'] == 'BOOKING_ALREADY_ELAPSED';
  }

  /// Extracts a [ClientBookingConflictFailure] from a 409 response body whose
  /// `data.code == "CLIENT_BOOKING_CONFLICT"` (backend commit f95d8fd — see
  /// that failure's doc for the full envelope shape).
  ///
  /// This response is NOT part of the generated OpenAPI client (the local
  /// backend cannot currently boot to refresh the spec snapshot — see
  /// CLAUDE.md), so it is decoded by hand from the raw JSON body, mirroring
  /// the `_isEmailAlreadyRegistered` / `_extractVerificationCode` precedent in
  /// `ErrorMapperInterceptor`. `startsAt`/`endsAt` are parsed with the exact
  /// same `DateTime.parse(...).toUtc()` the generated client's
  /// `Iso8601DateTimeSerializer` applies to every other booking DateTime field
  /// (`api/lib/src/…`), so this failure's window formats identically to the
  /// rest of the booking flow.
  ///
  /// Returns `null` (swallowing any parse error) when the body is not this
  /// exact shape — the caller then falls back to the generic [ConflictFailure]
  /// so a malformed or future-shaped envelope still surfaces a sane error
  /// instead of throwing out of the mapper.
  ClientBookingConflictFailure? _extractClientBookingConflict(DioException e) {
    try {
      final body = e.response?.data;
      if (body is! Map<String, dynamic>) return null;
      final data = body['data'];
      if (data is! Map<String, dynamic>) return null;
      if (data['code'] != 'CLIENT_BOOKING_CONFLICT') return null;

      final String? conflictingBookingId =
          data['conflictingBookingId'] as String?;
      final String? serviceName = data['serviceName'] as String?;
      final String? masterName = data['masterName'] as String?;
      final String? startsAtRaw = data['startsAt'] as String?;
      final String? endsAtRaw = data['endsAt'] as String?;
      if (conflictingBookingId == null ||
          serviceName == null ||
          masterName == null ||
          startsAtRaw == null ||
          endsAtRaw == null) {
        return null;
      }

      return ClientBookingConflictFailure(
        conflictingBookingId: conflictingBookingId,
        serviceName: serviceName,
        masterName: masterName,
        startsAt: DateTime.parse(startsAtRaw).toUtc(),
        endsAt: DateTime.parse(endsAtRaw).toUtc(),
        cause: e,
      );
    } catch (err) {
      if (kDebugMode) {
        log(
          'Failed to parse CLIENT_BOOKING_CONFLICT envelope: $err',
          name: _tag,
          level: 900,
        );
      }
      return null;
    }
  }

  /// Maps a [DioException] to a typed [Failure]. Mirrors the identical
  /// mapping in `HttpSalonRepository` / `HttpMasterRepository`.
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
