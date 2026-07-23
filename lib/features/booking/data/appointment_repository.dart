// MO-1 — AppointmentRepository: interface + HTTP implementation for the
// multi-service single-visit write/read path.
//
//   POST   /api/v1/appointments                       → create visit
//   GET    /api/v1/appointments/{appointmentId}         → enriched detail
//   PATCH  /api/v1/appointments/{appointmentId}/cancel   → CLIENT cancel
//   POST   /api/v1/appointments/{appointmentId}/review   → leave review
//
// SCOPE (MO-1): the CLIENT surface only. The provider visit transitions
// (`/decline`, `/complete`, `/not-complete`) exist on the backend and on the
// generated `AppointmentControllerApi`, but this client app has NO
// provider-side booking-transition surface today (the single-booking
// `BookingRepository` likewise exposes only the CLIENT `cancelBooking`, never
// `declineBooking`/`completeBooking`), so they are deliberately NOT wrapped
// here — added only if/when a provider visit-management screen needs them.
//
// Kept provider-free on purpose (mirrors `booking_repository.dart`) — see
// `booking_providers.dart` for the Riverpod wiring. Tests construct
// [HttpAppointmentRepository] directly with a mocktail
// [AppointmentControllerApi] + [ReviewControllerApi].
//
// Error / idempotency contract is transcribed 1:1 from
// `HttpBookingRepository`:
//   - [createAppointment] reuses the SAME idempotency-key channel (sent BOTH as
//     the `Idempotency-Key` header param AND on the body DTO — see
//     `_toWireCreateRequest`) and the SAME `_mapAppointmentWriteException`
//     mapping as booking creation: 409 `CLIENT_BOOKING_CONFLICT` →
//     [ClientBookingConflictFailure] (hand-decoded from the raw body — not in
//     the generated client), 409 `BOOKING_ALREADY_ELAPSED` →
//     [BookingAlreadyElapsedFailure], plain 409 → [ConflictFailure], 429 →
//     [BookingRateLimitedFailure], and the `badCertificate` MITM arm.
//   - Unlike booking creation (which returns a LEAN `BookingResponse` and does a
//     follow-up `getBookingById`), `POST /appointments` returns the FULL
//     `AppointmentDetailResponse`, so [createAppointment] maps it directly —
//     no second round-trip.
//
// AppConfig.baseUrl does NOT carry the `/api/v1` prefix — but every call here
// goes through the generated client, which prepends the full path itself, so
// (unlike the raw-Dio methods in `booking_repository.dart`) no manual prefixing
// is needed.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart' hide CreateAppointmentRequest;
import 'package:beautica_api/beautica_api.dart'
    as wire
    show CreateAppointmentRequest;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../domain/appointment.dart';
import '../domain/create_appointment_request.dart';
import 'appointment_mapper.dart';

const String _tag = 'feature.booking.appointment_repository';

/// Contract for the authenticated CLIENT multi-service visit layer.
///
/// Every method either resolves successfully or throws a [Failure] subclass
/// from `core/errors/failures.dart`. Raw [DioException]s never escape.
abstract interface class AppointmentRepository {
  /// Creates a multi-service visit for the authenticated client.
  ///
  /// Wraps `POST /appointments`. The endpoint returns the fully-enriched
  /// [AppointmentDetailResponse], so the returned [Appointment] is complete —
  /// no follow-up fetch.
  ///
  /// Throws [ClientBookingConflictFailure] on HTTP 409 when the CLIENT already
  /// has an overlapping visit/booking of their own, [BookingAlreadyElapsedFailure]
  /// on a 409 whose window is already past the server clock, [ConflictFailure]
  /// on any other 409 (a service slot was taken between fetching availability
  /// and submitting, or a lock-timeout retry case), and
  /// [BookingRateLimitedFailure] on HTTP 429.
  ///
  /// SURPRISE FOR MO-2/MO-3: a 409 whose body is the
  /// `{ "data": { "code": "DUPLICATE_SERVICE", ... } }` envelope
  /// (`DuplicateServiceResponse`) — the client picked the same service twice /
  /// a conflicting service — is currently mapped to the generic
  /// [ConflictFailure] here. MO-2/MO-3 should add a dedicated
  /// `DuplicateServiceFailure` (hand-decoded exactly like
  /// [_extractClientBookingConflict]) with its own localized copy; the
  /// selection UI should also prevent duplicates up-front.
  Future<Appointment> createAppointment(CreateAppointmentRequest req);

  /// Fetches the enriched detail for a single visit.
  ///
  /// Wraps `GET /appointments/{appointmentId}`. Throws [NotFoundFailure] on
  /// HTTP 404.
  Future<Appointment> getAppointment(String id);

  /// Cancels a visit on behalf of the authenticated client.
  ///
  /// Wraps `PATCH /appointments/{appointmentId}/cancel`. [note] is forwarded as
  /// the optional free-text `clientCancellationNote` (mutually visible to the
  /// provider — see CLAUDE.md booking-notes rule). This repository only ever
  /// cancels the client's OWN visit; the provider decline/no-show transitions
  /// are out of scope (see the file header).
  Future<void> cancelAppointment(String id, {String? note});

  /// Leaves a review for a COMPLETED visit on behalf of the authenticated
  /// client.
  ///
  /// Wraps `POST /appointments/{appointmentId}/review`. [rating] is 1–5;
  /// [comment] is optional free text (an empty/blank string is sent as null).
  /// The backend enforces COMPLETED + ownership + not-already-reviewed — the
  /// client must not re-derive those beyond the `Appointment.canReview` gate.
  /// Throws [ReviewAlreadyExistsFailure] on HTTP 409 and [ReviewNotAllowedFailure]
  /// on 403 / other 4xx.
  Future<void> createAppointmentReview(
    String id, {
    required int rating,
    String? comment,
  });
}

/// HTTP implementation of [AppointmentRepository].
///
/// Inject via [appointmentRepositoryProvider] — never construct directly
/// outside tests.
final class HttpAppointmentRepository implements AppointmentRepository {
  HttpAppointmentRepository(this._appointmentApi, this._reviewApi);

  final AppointmentControllerApi _appointmentApi;
  final ReviewControllerApi _reviewApi;

  @override
  Future<Appointment> createAppointment(CreateAppointmentRequest req) async {
    try {
      final res = await _appointmentApi.createAppointment(
        createAppointmentRequest: _toWireCreateRequest(req),
        idempotencyKey: req.idempotencyKey,
      );
      final dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'createAppointment: response data is null',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return AppointmentMapper.fromDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'createAppointment failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapAppointmentWriteException(e);
    }
  }

  @override
  Future<Appointment> getAppointment(String id) async {
    try {
      final res = await _appointmentApi.getAppointment(appointmentId: id);
      final dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'getAppointment: ApiResponseAppointmentDetailResponse.data is null',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return AppointmentMapper.fromDto(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getAppointment failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> cancelAppointment(String id, {String? note}) async {
    // Blank/whitespace-only note → send no note at all (the field is optional
    // on the wire; a null keeps the payload clean).
    final String? trimmed = note?.trim();
    final String? effectiveNote = (trimmed == null || trimmed.isEmpty)
        ? null
        : trimmed;
    try {
      await _appointmentApi.cancelAppointment(
        appointmentId: id,
        appointmentCancelRequest: AppointmentCancelRequest(
          (b) => b..clientCancellationNote = effectiveNote,
        ),
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'cancelAppointment failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapAppointmentCancelException(e);
    }
  }

  @override
  Future<void> createAppointmentReview(
    String id, {
    required int rating,
    String? comment,
  }) async {
    final String? trimmed = comment?.trim();
    final String? effectiveComment = (trimmed == null || trimmed.isEmpty)
        ? null
        : trimmed;
    try {
      await _reviewApi.createAppointmentReview(
        appointmentId: id,
        createAppointmentReviewRequest: CreateAppointmentReviewRequest(
          (b) => b
            ..rating = rating
            ..comment = effectiveComment,
        ),
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'createAppointmentReview failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapReviewException(e);
    }
  }

  /// Builds the generated wire `CreateAppointmentRequest` DTO from the domain
  /// [CreateAppointmentRequest]. The `idempotencyKey` is sent BOTH as the
  /// `Idempotency-Key` request header AND on the body — same rationale as
  /// `HttpBookingRepository._toWireCreateRequest` (the OpenAPI spec exposes the
  /// field on both channels and which one the backend reads is not observable
  /// from the spec; sending both is harmless and correct either way).
  wire.CreateAppointmentRequest _toWireCreateRequest(
    CreateAppointmentRequest req,
  ) {
    return wire.CreateAppointmentRequest(
      (b) => b
        ..masterId = req.masterId
        ..masterServiceIds.replace(req.masterServiceIds)
        ..startsAt = req.startAt
        ..idempotencyKey = req.idempotencyKey
        ..clientComment = req.clientComment,
    );
  }

  /// Maps a [DioException] from `POST /appointments` to a typed [Failure] —
  /// transcribed from `HttpBookingRepository._mapBookingWriteException` so the
  /// visit flow and the single-booking flow surface identical errors.
  Failure _mapAppointmentWriteException(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 409) {
      if (_isBookingAlreadyElapsed(e)) {
        return BookingAlreadyElapsedFailure(cause: e);
      }
      return _extractClientBookingConflict(e) ?? ConflictFailure(cause: e);
    }
    if (statusCode == 429) return BookingRateLimitedFailure(cause: e);
    if (e.error is Failure) return e.error as Failure;
    return _mapDioException(e);
  }

  /// Maps a [DioException] from `PATCH /appointments/{id}/cancel`. The one
  /// special case is the `BOOKING_ALREADY_ELAPSED` 409 (the visit already ended
  /// server-side); everything else defers to [_mapDioException].
  Failure _mapAppointmentCancelException(DioException e) {
    if (e.response?.statusCode == 409 && _isBookingAlreadyElapsed(e)) {
      return BookingAlreadyElapsedFailure(cause: e);
    }
    return _mapDioException(e);
  }

  /// Maps a [DioException] from `POST /appointments/{id}/review` — transcribed
  /// from `HttpBookingRepository._mapReviewException`:
  ///   - 409 → [ReviewAlreadyExistsFailure]
  ///   - 403 / 400 / 422 → [ReviewNotAllowedFailure]
  ///   - otherwise → [_mapDioException]
  Failure _mapReviewException(DioException e) {
    final int? statusCode = e.response?.statusCode;
    if (statusCode == 409) return ReviewAlreadyExistsFailure(cause: e);
    if (statusCode == 403 || statusCode == 400 || statusCode == 422) {
      return ReviewNotAllowedFailure(cause: e);
    }
    return _mapDioException(e);
  }

  /// `true` when [e] is a 409 whose body is the
  /// `{ "data": { "code": "BOOKING_ALREADY_ELAPSED" } }` envelope. Hand-decoded
  /// from the raw JSON body (this code is not part of the generated client),
  /// mirroring `HttpBookingRepository._isBookingAlreadyElapsed`.
  bool _isBookingAlreadyElapsed(DioException e) {
    final body = e.response?.data;
    if (body is! Map<String, dynamic>) return false;
    final data = body['data'];
    if (data is! Map<String, dynamic>) return false;
    return data['code'] == 'BOOKING_ALREADY_ELAPSED';
  }

  /// Extracts a [ClientBookingConflictFailure] from a 409 body whose
  /// `data.code == "CLIENT_BOOKING_CONFLICT"` — transcribed verbatim from
  /// `HttpBookingRepository._extractClientBookingConflict` (the envelope is not
  /// part of the generated client, so it is hand-decoded; `startsAt`/`endsAt`
  /// are parsed with the same `DateTime.parse(...).toUtc()` the generated
  /// client applies to every other booking DateTime). Returns `null` on any
  /// non-matching / malformed body so the caller falls back to the generic
  /// [ConflictFailure].
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

  /// Maps a [DioException] to a typed [Failure]. Transcribed from
  /// `HttpBookingRepository._mapDioException`, including the dedicated
  /// `badCertificate` MITM arm (deliberately NOT gated behind `kDebugMode` — a
  /// possible MITM on this PII-dense visit traffic must be visible in
  /// release-build telemetry; no PII/token/id is logged, only the fact that
  /// certificate validation failed). The [Failure] handed to the UI is
  /// deliberately unchanged ([ServerFailure] — fails closed); only the log
  /// signal is split out.
  Failure _mapDioException(DioException e) {
    if (e.error is Failure) return e.error as Failure;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(cause: e);
      case DioExceptionType.badCertificate:
        log(
          'TLS/certificate validation failed for appointment traffic — '
          'possible MITM',
          name: 'booking.appointment_repository.security',
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
