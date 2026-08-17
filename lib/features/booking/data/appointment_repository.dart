// MO-1 — AppointmentRepository: interface + HTTP implementation for the
// multi-service single-visit write/read path.
//
//   POST   /api/v1/appointments                                          → create visit
//   GET    /api/v1/appointments/{appointmentId}                          → enriched detail
//   PATCH  /api/v1/appointments/{appointmentId}/services/{bookingId}/reschedule
//                                                                          → CLIENT or PROVIDER per-item reschedule (dual-actor)
//   PATCH  /api/v1/appointments/{appointmentId}/services/{bookingId}/complete
//                                                                          → PROVIDER per-item complete
//   PATCH  /api/v1/appointments/{appointmentId}/cancel                    → CLIENT cancel
//   PATCH  /api/v1/appointments/{appointmentId}/complete                  → PROVIDER complete
//   PATCH  /api/v1/appointments/{appointmentId}/decline                   → PROVIDER decline
//
// SCOPE (MO-1, extended track 27.x/MO-6, cut over to per-item track 30.x):
// the CLIENT surface plus [completeAppointment]/[declineAppointment]
// (PROVIDER-only, whole-visit lockstep — retained on the interface, no longer
// reached from any provider-facing screen) and the per-item trio
// [rescheduleAppointmentItem] (dual-actor: the visit's own CLIENT or an
// assigned PROVIDER — see `_onReschedule` in `booking_detail_screen.dart`),
// [declineAppointmentService] and [completeAppointmentService].
//
// HISTORY — WHY THE WHOLE-VISIT ENDPOINTS EXIST, AND WHY NOTHING CALLS THEM
// ANY MORE. The backend's `assertNotAppointmentChild` guard used to 409 EVERY
// per-booking transition once `booking.appointment != null`, so a
// multi-service visit could only be completed/declined in lockstep through the
// whole-visit endpoints. That is NO LONGER the contract: the backend now
// exposes a per-item `complete` and `decline` under
// `.../services/{bookingId}/`, and every provider-facing screen routes an
// appointment child to the per-item endpoint. Lockstep completion was ALSO a
// correctness bug on the wire: `PATCH /appointments/{id}/complete` runs its
// `assertElapsedForComplete` temporal guard against the VISIT's `startsAt`
// (the FIRST service), so completing from a row whose own service starts hours
// later silently completed that not-yet-started sibling too — the per-item
// endpoint guards each child on its OWN `startsAt`. What is still true is the
// negative: an appointment child must NEVER go through
// `BookingRepository.completeBooking`/`declineBooking` (the bare per-booking
// routes) — the visit-aware endpoints on this repository are the only legal
// path.
//
// Reschedule was the FIRST transition to leave lockstep: the mobile app used to
// call a whole-visit `PATCH /appointments/{id}/reschedule` here (removed —
// the backend endpoint itself is untouched, only this client's use of it),
// but now moves exactly ONE service via [rescheduleAppointmentItem], leaving
// siblings' windows byte-for-byte unchanged (locked product decision — no
// re-layout, no cascade, no gap-closing; the visit may legally become
// non-contiguous). `booking_detail_screen.dart` routes here whenever the
// booking it is showing carries a non-null `Booking.appointmentId` (each
// service of a visit still opens its OWN single-booking detail screen — see
// that file's `_onReschedule`/`_confirmComplete`/`_confirmDecline`).
//
// Kept provider-free OTHERWISE (mirrors `booking_repository.dart`'s CLIENT-only
// shape apart from its own track-27.x provider additions) — see
// `booking_providers.dart` for the Riverpod wiring. Tests construct
// [HttpAppointmentRepository] directly with a mocktail
// [AppointmentControllerApi].
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

  /// Marks a visit COMPLETED on behalf of the authenticated PROVIDER (track
  /// 27.x / MO-6) — the whole-visit counterpart to
  /// `BookingRepository.completeBooking`.
  ///
  /// Wraps `PATCH /appointments/{appointmentId}/complete` — no request body.
  /// The backend transitions EVERY booking belonging to the visit to
  /// COMPLETED in lockstep; there is no partial-visit completion.
  ///
  /// NO PROVIDER SCREEN CALLS THIS ANY MORE — use
  /// [completeAppointmentService]. Its 409 temporal guard is evaluated against
  /// the VISIT's `startsAt` (the first service), so completing from a row
  /// whose own service starts later also completed not-yet-started siblings
  /// with no guard of their own. Kept on the interface only because the
  /// endpoint still exists; do not reintroduce a call site.
  ///
  /// Throws [ProviderCompleteNotStartedFailure] on HTTP 409 — the same
  /// `BookingTemporalGuard.assertElapsedForComplete` guard the single-booking
  /// endpoint enforces (the visit's `startsAt` is still in the future; SERVER
  /// clock authoritative).
  Future<void> completeAppointment(String id);

  /// Marks ONE service (`bookingId`) of a multi-service visit
  /// (`appointmentId`) COMPLETED on behalf of the authenticated PROVIDER,
  /// leaving the visit's OTHER services CONFIRMED — the per-service
  /// counterpart to [completeAppointment] (which completes the WHOLE visit in
  /// lockstep), and the exact mirror of [declineAppointmentService].
  ///
  /// Wraps `PATCH /appointments/{appointmentId}/services/{bookingId}/complete`
  /// — no request body (completion collects no note; see
  /// `CompleteBookingDialog`'s doc). Per the OpenAPI description: siblings stay
  /// CONFIRMED, the visit header collapses to COMPLETED and the visit's single
  /// review-requested notification fires only once the LAST CONFIRMED sibling
  /// completes.
  ///
  /// Each service of a visit opens its OWN single-booking
  /// `BookingDetailScreen`, and the master «Архів» list renders one row PER
  /// SERVICE, so the «Виконано»/«Завершити» tapped there must complete only
  /// that one child — `booking_detail_screen.dart`'s `_confirmComplete` and
  /// `master_archive_screen.dart`'s `_confirmComplete` both route here
  /// (passing `appointmentId = Booking.appointmentId`,
  /// `bookingId = Booking.id`) whenever the shown booking carries a non-null
  /// `Booking.appointmentId`.
  ///
  /// CRITICALLY, the 409 guard is per-CHILD here: the backend evaluates
  /// `BookingTemporalGuard.assertElapsedForComplete` against THIS booking's
  /// own `startsAt`, not the visit header's. That is the whole point of the
  /// cut-over — [completeAppointment] guarded only the FIRST service's start,
  /// so a sibling starting hours later was completed unguarded.
  ///
  /// Throws [NotFoundFailure] on HTTP 404 (the `bookingId` is not a child of
  /// `appointmentId`) and [ProviderCompleteNotStartedFailure] on HTTP 409 (this
  /// child has not started yet, or it is already terminal) — the same 409 type
  /// [completeAppointment] surfaces, so both screens' existing
  /// `on ProviderCompleteNotStartedFailure` handling covers this route
  /// unchanged. A 403 (no provider authority) defers to the shared
  /// error-mapper's [Failure].
  Future<void> completeAppointmentService(
    String appointmentId,
    String bookingId,
  );

  /// Moves ONE service (`bookingId`) of a multi-service visit
  /// (`appointmentId`) to [newStartAt] (track 30.x), leaving the visit's
  /// OTHER services' windows byte-for-byte unchanged — the per-item
  /// counterpart of `BookingRepository.rescheduleBooking`, and the direct
  /// replacement for the retired whole-visit
  /// `rescheduleAppointment(id, newStartAt)` (the backend's own
  /// `PATCH /appointments/{id}/reschedule` is untouched; only this client's
  /// call to it was removed). Dual-actor on the backend (the visit's own
  /// CLIENT or an assigned PROVIDER — see
  /// `AppointmentController.rescheduleAppointmentItem`); either footer of
  /// `booking_detail_screen.dart`'s `_onReschedule` invokes this whenever the
  /// shown booking carries a non-null `Booking.appointmentId`.
  ///
  /// Wraps
  /// `PATCH /appointments/{appointmentId}/services/{bookingId}/reschedule`
  /// (`AppointmentItemRescheduleRequest.newStartsAt`). Contiguity is
  /// DELIBERATELY relaxed — no follower re-layout, no cascade, no
  /// gap-closing; the ONE invariant that still holds is no-overlap with a
  /// CONFIRMED sibling of the same visit. Returns the re-fetched (enriched)
  /// [Appointment] — no follow-up GET needed.
  ///
  /// Throws [NotFoundFailure] on HTTP 404 (`bookingId` is not a child of
  /// `appointmentId`), [BookingAlreadyElapsedFailure] on a 409 whose body is
  /// the `BOOKING_ALREADY_ELAPSED` envelope (the CLIENT is moving an
  /// already-elapsed item), and [ConflictFailure] on any OTHER 409 — the
  /// backend cannot distinguish, on the wire, a sibling-overlap / "master
  /// busy" conflict from the visit-or-item "changed concurrently — please
  /// retry" guard: both are plain `BusinessException(CONFLICT, …)` instances
  /// that serialize to the SAME bare `data: null` envelope (see
  /// `AppointmentTransitionService.rescheduleAppointmentItem`'s Javadoc), so
  /// both collapse to the one generic "this time is no longer available"
  /// [ConflictFailure] here — there is no `data.code` to branch on. A plain
  /// 400 (the backend's 15-minute–180-day window guard) defers to whatever
  /// [Failure] the shared error-mapper interceptor already attached — see
  /// [_mapAppointmentItemRescheduleException], transcribed from
  /// `HttpBookingRepository._mapBookingWriteException`.
  Future<Appointment> rescheduleAppointmentItem(
    String appointmentId,
    String bookingId,
    DateTime newStartAt,
  );

  /// Declines a visit on behalf of the authenticated PROVIDER (track 27.x /
  /// MO-6) — the whole-visit counterpart to `BookingRepository.declineBooking`.
  ///
  /// Wraps `PATCH /appointments/{appointmentId}/decline`. [comment] is the
  /// OPTIONAL free-text `providerComment`, mutually visible to the client on
  /// EVERY booking in the visit once it reads DECLINED (CLAUDE.md booking-
  /// notes rule — symmetric, mutual visibility, no audience suppression).
  ///
  /// Throws [ProviderDeclineWindowClosedFailure] on HTTP 409 — the same
  /// `BookingTemporalGuard.assertFutureForProviderCancel` guard the
  /// single-booking endpoint enforces.
  Future<void> declineAppointment(String id, {String? comment});

  /// Declines ONE service (`bookingId`) of a multi-service visit
  /// (`appointmentId`) on behalf of the authenticated PROVIDER, leaving the
  /// visit's OTHER services CONFIRMED — the per-service counterpart to
  /// [declineAppointment] (which declines the WHOLE visit in lockstep).
  ///
  /// Wraps `PATCH /appointments/{appointmentId}/services/{bookingId}/decline`.
  /// [comment] is the OPTIONAL free-text `providerComment`, mutually visible to
  /// the client on THIS booking once it reads DECLINED (CLAUDE.md booking-notes
  /// rule — symmetric, mutual visibility, no audience suppression). The siblings
  /// are untouched.
  ///
  /// Each service of a visit opens its OWN single-booking
  /// `BookingDetailScreen`, so the provider decline tapped there must decline
  /// only that one child — `booking_detail_screen.dart`'s `_confirmDecline`
  /// routes here (passing `appointmentId = Booking.appointmentId`,
  /// `bookingId = Booking.id`) whenever the shown booking carries a non-null
  /// `Booking.appointmentId`.
  ///
  /// Throws [NotFoundFailure] on HTTP 404 (the `bookingId` is not a child of
  /// `appointmentId`) and [ProviderDeclineWindowClosedFailure] on HTTP 409 (the
  /// child is already terminal, or another `BookingTemporalGuard` rejection) —
  /// the same 409 type [declineAppointment] surfaces, so `_confirmDecline`'s
  /// existing failure handling covers both routes unchanged. A 403 (no provider
  /// authority) defers to the shared error-mapper's [Failure].
  Future<void> declineAppointmentService(
    String appointmentId,
    String bookingId, {
    String? comment,
  });
}

/// HTTP implementation of [AppointmentRepository].
///
/// Inject via [appointmentRepositoryProvider] — never construct directly
/// outside tests.
final class HttpAppointmentRepository implements AppointmentRepository {
  HttpAppointmentRepository(this._appointmentApi);

  final AppointmentControllerApi _appointmentApi;

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
  Future<Appointment> rescheduleAppointmentItem(
    String appointmentId,
    String bookingId,
    DateTime newStartAt,
  ) async {
    try {
      final res = await _appointmentApi.rescheduleAppointmentItem(
        appointmentId: appointmentId,
        bookingId: bookingId,
        appointmentItemRescheduleRequest: AppointmentItemRescheduleRequest(
          (b) => b..newStartsAt = newStartAt,
        ),
      );
      final dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'rescheduleAppointmentItem: response data is null',
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
          'rescheduleAppointmentItem failed: '
          '${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapAppointmentItemRescheduleException(e);
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
  Future<void> completeAppointment(String id) async {
    try {
      await _appointmentApi.completeAppointment(appointmentId: id);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'completeAppointment failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapProviderActionException(
        e,
        onConflict: (DioException e) =>
            ProviderCompleteNotStartedFailure(cause: e),
      );
    }
  }

  @override
  Future<void> completeAppointmentService(
    String appointmentId,
    String bookingId,
  ) async {
    try {
      await _appointmentApi.completeAppointmentItem(
        appointmentId: appointmentId,
        bookingId: bookingId,
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'completeAppointmentService failed: '
          '${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      // 409 (THIS child has not started / is already terminal) →
      // [ProviderCompleteNotStartedFailure], the identical mapping
      // [completeAppointment] applies — the guard is just evaluated against
      // this child's own `startsAt` instead of the visit header's. A 404
      // (bookingId not a child of appointmentId) surfaces as [NotFoundFailure],
      // but NOT because [_mapDioException] maps it — that method has no 404 arm
      // at all, and every un-mapped `badResponse` reaching it becomes
      // [ServerFailure]. `ErrorMapperInterceptor`
      // (`lib/core/network/error_mapper_interceptor.dart`, the `statusCode ==
      // 404` arm) has already built the [NotFoundFailure] and attached it to
      // `DioException.error` by the time this `catch` runs; the chain down
      // through [_mapProviderActionException] to [_mapDioException] then
      // returns it verbatim via that method's leading
      // `if (e.error is Failure) return e.error as Failure`. A 403 reaches the
      // UI the same way — the interceptor's [Failure], passed through
      // untouched.
      throw _mapProviderActionException(
        e,
        onConflict: (DioException e) =>
            ProviderCompleteNotStartedFailure(cause: e),
      );
    }
  }

  @override
  Future<void> declineAppointment(String id, {String? comment}) async {
    // Blank/whitespace-only comment → send no comment at all (the field is
    // optional on the wire; a null keeps the payload clean) — same trim rule
    // as `HttpBookingRepository.declineBooking`.
    final String? trimmed = comment?.trim();
    final String? effectiveComment = (trimmed == null || trimmed.isEmpty)
        ? null
        : trimmed;
    try {
      await _appointmentApi.declineAppointment(
        appointmentId: id,
        appointmentProviderNoteRequest: AppointmentProviderNoteRequest(
          (b) => b..providerComment = effectiveComment,
        ),
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'declineAppointment failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapProviderActionException(
        e,
        onConflict: (DioException e) =>
            ProviderDeclineWindowClosedFailure(cause: e),
      );
    }
  }

  @override
  Future<void> declineAppointmentService(
    String appointmentId,
    String bookingId, {
    String? comment,
  }) async {
    // Blank/whitespace-only comment → send no comment at all (the field is
    // optional on the wire; a null keeps the payload clean) — same trim rule
    // as [declineAppointment] / `HttpBookingRepository.declineBooking`.
    final String? trimmed = comment?.trim();
    final String? effectiveComment = (trimmed == null || trimmed.isEmpty)
        ? null
        : trimmed;
    try {
      await _appointmentApi.declineAppointmentItem(
        appointmentId: appointmentId,
        bookingId: bookingId,
        appointmentProviderNoteRequest: AppointmentProviderNoteRequest(
          (b) => b..providerComment = effectiveComment,
        ),
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'declineAppointmentService failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      // 409 (child already terminal / temporal guard) →
      // [ProviderDeclineWindowClosedFailure], mirroring [declineAppointment].
      // A 404 (bookingId not a child of appointmentId) surfaces as
      // [NotFoundFailure] by way of `ErrorMapperInterceptor`, not of
      // [_mapDioException] — see the identical note in
      // [completeAppointmentService] for the actual mechanism; a 403 reaches
      // the UI as the interceptor's [Failure], passed through untouched.
      throw _mapProviderActionException(
        e,
        onConflict: (DioException e) =>
            ProviderDeclineWindowClosedFailure(cause: e),
      );
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
      if (_isDuplicateService(e)) {
        return DuplicateServiceFailure(cause: e);
      }
      return _extractClientBookingConflict(e) ?? ConflictFailure(cause: e);
    }
    if (statusCode == 429) return BookingRateLimitedFailure(cause: e);
    if (e.error is Failure) return e.error as Failure;
    return _mapDioException(e);
  }

  /// Maps a [DioException] from
  /// `PATCH /appointments/{id}/services/{bookingId}/reschedule` to a typed
  /// [Failure] — transcribed from
  /// `HttpBookingRepository._mapBookingWriteException` so a per-item visit
  /// reschedule surfaces the SAME failure SHAPES as the single-booking one:
  ///   - 409 `BOOKING_ALREADY_ELAPSED` → [BookingAlreadyElapsedFailure] (the
  ///     CLIENT is moving an already-elapsed item).
  ///   - 409 `CLIENT_BOOKING_CONFLICT` → [ClientBookingConflictFailure] (see
  ///     [_extractClientBookingConflict]). The OpenAPI spec documents this
  ///     endpoint's 409 explicitly: "Header/item not CONFIRMED, elapsed,
  ///     sibling overlap, or slot unavailable (including
  ///     CLIENT_BOOKING_CONFLICT)" — and the backend's
  ///     `AppointmentTransitionService.rescheduleAppointmentItem` calls
  ///     `assertNoClientConflictExcludingBooking`, which throws
  ///     `ClientBookingConflictException` (the SAME coded envelope
  ///     `POST /appointments` emits) whenever moving this item would overlap
  ///     the owning client's own OTHER booking. This is not create-path-only:
  ///     moving an existing item to a new time is exactly the operation that
  ///     can create a fresh overlap with the client's unrelated bookings.
  ///     `clientOnlyGuard` currently makes the PROVIDER's own «Перенести»
  ///     entry point a dead end (see `routing/app_router.dart`), so the
  ///     CLIENT is the only actor that can complete this flow today — the
  ///     exact case that benefits from the richer failure.
  ///   - any OTHER 409 → [ConflictFailure] ("this time is no longer
  ///     available"). This covers the sibling-overlap / master-busy checks
  ///     AND the "changed concurrently — please retry" guard (the header or
  ///     the target item was mutated between this request's load and its
  ///     write-time recheck) — the backend raises the latter as a plain
  ///     `BusinessException(CONFLICT, …)`, wire-identical (`data: null`) to a
  ///     sibling-overlap 409, so there is no `data.code` to distinguish them;
  ///     both read to the user as an ordinary "slot unavailable".
  ///   - a 404 (`bookingId` is not a child of `appointmentId`) has no
  ///     dedicated branch here — it defers to the shared
  ///     `ErrorMapperInterceptor`'s [NotFoundFailure], via `e.error is
  ///     Failure` below.
  ///   - a plain 400 (the backend's 15-minute–180-day window guard) has no
  ///     dedicated type here either — it defers to whatever [Failure] the
  ///     shared `ErrorMapperInterceptor` already attached (a
  ///     [ValidationFailure] carrying the server's window message), via the
  ///     same `e.error is Failure` check.
  Failure _mapAppointmentItemRescheduleException(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 409) {
      if (_isBookingAlreadyElapsed(e)) {
        return BookingAlreadyElapsedFailure(cause: e);
      }
      return _extractClientBookingConflict(e) ?? ConflictFailure(cause: e);
    }
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

  /// Maps a [DioException] from `PATCH /appointments/{id}/decline` or
  /// `PATCH /appointments/{id}/complete` to a typed [Failure] — transcribed
  /// verbatim from `HttpBookingRepository._mapProviderActionException`. Every
  /// 409 from either endpoint means the backend's `BookingTemporalGuard`
  /// rejected the action's timing (there is no typed `data.code` envelope to
  /// decode), so [onConflict] resolves it PURELY by call site. Everything
  /// else defers to [_mapDioException].
  Failure _mapProviderActionException(
    DioException e, {
    required Failure Function(DioException e) onConflict,
  }) {
    if (e.response?.statusCode == 409) return onConflict(e);
    return _mapDioException(e);
  }

  /// `true` when [e] is a 409 whose body is the
  /// `{ "data": { "code": "DUPLICATE_SERVICE" } }` envelope
  /// (`DuplicateServiceResponse`) — the visit payload named the same service
  /// twice. Hand-decoded from the raw JSON body (this code is not part of the
  /// generated client), mirroring [_isBookingAlreadyElapsed]. MO-3 also dedupes
  /// the selection up-front so this normally never fires.
  bool _isDuplicateService(DioException e) {
    final body = e.response?.data;
    if (body is! Map<String, dynamic>) return false;
    final data = body['data'];
    if (data is! Map<String, dynamic>) return false;
    return data['code'] == 'DUPLICATE_SERVICE';
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
