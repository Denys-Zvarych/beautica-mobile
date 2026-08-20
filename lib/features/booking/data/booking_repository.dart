// Phase 14.0 — BookingRepository: interface + HTTP implementation.
//
// Wraps the CLIENT-side authenticated booking write/read path:
//   POST   /api/v1/bookings                     → create
//   GET    /api/v1/bookings/me                   → paged "my bookings" list
//   GET    /api/v1/bookings/{bookingId}           → enriched detail (19.3)
//   PATCH  /api/v1/bookings/{bookingId}/cancel     → cancel
//   PATCH  /api/v1/bookings/{bookingId}/reschedule → reschedule (19.2)
//
// ...plus, since Phase 246, ONE provider-side path on the same repository
// (kept here rather than a separate file — it shares the same [Failure]
// taxonomy as the rest of this repository; since Phase 252 it maps its
// response directly via `AppointmentMapper` rather than following up with
// `getBookingById`):
//   POST   /api/v1/masters/{masterId}/bookings     → createMasterBooking
//                                                      (walk-in VISIT, backend
//                                                      22.4, widened to
//                                                      multi-service by 22.8–
//                                                      22.16 / mobile Phase 252)
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
// [beauticaSerializers] the generated client is built on in
// `booking_providers.dart` — the tolerant instance, so an unrecognised booking
// status degrades identically on the list and the detail path.
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
import 'dart:math' as math;

import 'package:beautica_api/beautica_api.dart' hide CreateBookingRequest;
import 'package:beautica_api/beautica_api.dart'
    as wire
    show CreateBookingRequest;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/beautica_serializers.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../domain/appointment.dart';
import 'appointment_mapper.dart';
// Phase 252: [maxServicesPerVisit] is the ONLY thing pulled from
// `slot_repository.dart` here — a `data/`→`data/` import (legal; the
// forbidden direction is `domain/`→`data/`). See
// `create_master_booking_request.dart`'s file header for why the cap isn't
// validated in the domain model itself.
import 'slot_repository.dart' show maxServicesPerVisit;

import '../domain/booking.dart';
import '../domain/booking_partition.dart';
import '../domain/booking_sort.dart';
import '../domain/booking_status.dart';
import '../domain/create_booking_request.dart';
import '../domain/create_master_booking_request.dart';
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

  /// Creates a CONFIRMED, `STAFF`-sourced WALK-IN VISIT on [masterId]'s
  /// calendar on behalf of the authenticated PROVIDER (Phase 246 — backend
  /// Phase 22.4, `docs/backend-phases/
  /// phase-171-22.4-staff-booking-endpoint-and-authz.md`; widened to
  /// multi-service by Phase 252 — backend track 22.8–22.16). The caller may
  /// be an independent master booking THEMSELVES, or a salon owner/admin
  /// booking a master they manage — `@authz.canBookForMaster` enforces which
  /// on the backend; this method sends the same request either way.
  ///
  /// Wraps `POST /api/v1/masters/{masterId}/bookings`. ONE `Appointment`
  /// header + N chained `Booking` rows are created server-side from
  /// [CreateMasterBookingRequest.masterServiceIds] — the SAME visit shape
  /// the CLIENT multi-service flow ([AppointmentRepository.createAppointment])
  /// produces, per the locked product decision that a walk-in is "EXACTLY
  /// same logic as we already have for independent master when client
  /// making the bookings". Unlike [createBooking]/the PRE-252 shape of this
  /// method (which returned the LEAN `BookingResponse` and needed a
  /// follow-up [getBookingById]), the endpoint now returns the FULL
  /// `AppointmentDetailResponse` directly — mapped here via
  /// [AppointmentMapper.fromDto] (REUSED verbatim from the client
  /// multi-service path; no second visit model/mapper). No follow-up fetch.
  ///
  /// Throws [ArgumentError] — NOT a [Failure] — when
  /// [CreateMasterBookingRequest.masterServiceIds] is empty or exceeds
  /// [maxServicesPerVisit], BEFORE any HTTP call is made. This guards a real
  /// spec-fidelity gap: the published OpenAPI schema renders
  /// `masterServiceIds` with `minItems: 0` even though the backend enforces
  /// `@NotEmpty` server-side (the annotation didn't merge into the SpringDoc
  /// output), so the generated client's own validation cannot be relied on —
  /// an empty list would otherwise reach the wire and come back as an opaque
  /// 400. Mirrors the [ArgumentError] precedent in
  /// `MasterServiceMapper.toCreateRequest` — a caller bug, not a runtime
  /// [Failure], so it is thrown OUTSIDE the try/catch below and never mapped.
  ///
  /// Error contract (backend Phase 22.4's "Error contract" section):
  ///   - **403** → [MasterBookingNotPermittedFailure]. Covers "wrong salon /
  ///     not your own profile / read-only SALON_MASTER" AND "unknown or
  ///     inactive master" — the backend deliberately collapses both into one
  ///     status (a probe defence). Never surface a "master not found"
  ///     message for this — see that failure's doc.
  ///   - **409 / 422** → [ConflictFailure] — overlapping booking, outside
  ///     working hours, day-off, past time, or the master doesn't offer one
  ///     of [CreateMasterBookingRequest.masterServiceIds]. The same generic
  ///     slot-conflict copy [createBooking] itself surfaces on 409.
  ///   - **400** → [ValidationFailure] (missing/malformed walk-in guest
  ///     field, bad phone shape) — mapped by [ErrorMapperInterceptor] before
  ///     this repository ever sees the [DioException]; [fieldErrors] names
  ///     the offending field.
  ///
  /// [CreateMasterBookingRequest.startsAt] is normalised to UTC
  /// (`.toUtc()`) before it reaches the wire — see that field's doc for why.
  Future<Appointment> createMasterBooking(
    String masterId,
    CreateMasterBookingRequest request,
  );

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
  /// [sort] drives the `sort=<property>,<direction>` param (backend Phase
  /// 26.3). The client «Мої записи» screen has no sort sheet and passes only
  /// the two `startsAt` directions ([BookingSort.oldest] for soonest-first —
  /// "what's next", the Майбутні tab; [BookingSort.newest] for
  /// most-recent-first — "what just happened", Минулі/Скасовані). The
  /// independent-master list additionally offers the two price orders. Pass
  /// null to omit the param entirely and take the backend's own
  /// `@PageableDefault` (`startsAt,DESC`).
  ///
  /// Only the properties on the backend's Phase 26.6 whitelist are accepted —
  /// [BookingSort] is exactly that whitelist, which is why this takes the enum
  /// rather than a raw string.
  ///
  /// [serviceIds] narrows to bookings placed against the given MasterService
  /// ids, sent as REPEATED `serviceId` params (backend Phase 26.4, capped at
  /// 50 server-side). [from]/[to] bound `startsAt` to an inclusive local
  /// (Europe/Kyiv) day range (backend Phase 26.2, capped at 366 days), each
  /// independently optional — `from` alone is an open-ended future window,
  /// `to` alone an open-ended past window. All three are omitted from the
  /// query string when null/empty, applying no predicate.
  ///
  /// [page] is zero-based; [size] caps the page (default [kBookingsPageSize]).
  ///
  /// [statuses]/[serviceIds] are `Iterable` rather than `Set` (perf P5) so a
  /// caller holding the canonically-sorted, unmodifiable `List`s that
  /// `MasterBookingsQuery.of` produces can pass them straight through instead
  /// of round-tripping each through a throwaway `Set` on every fetch. Both
  /// shapes are accepted; neither is retained.
  ///
  /// [cancelToken] (mobile-perf MEDIUM-3, 2026-07-20) lets callers — notably
  /// `BookingsDayNotifier`, whose family member is evicted the instant the
  /// rail is scrubbed past the day-rail's 220ms debounce — cancel an
  /// in-flight request when it is superseded before it resolves, mirroring
  /// `SlotRepository.getMasterSlots`/`getWorkingDays`. Disposing a Riverpod
  /// element stops the RESULT from landing but does not, by itself, abort the
  /// underlying Dio request; this makes that possible.
  ///
  /// [partition] is the Phase 28.2/29.3 time-based partition — sent as its
  /// [BookingPartition.wireValue] (`UPCOMING`/`PAST`/`CANCELLED`/
  /// `AWAITING_CLOSURE`), omitted entirely when null (the backend then falls
  /// back to the pre-Phase-28 `status`-only filtering, its own
  /// additive-rollout safety valve; when [partition] IS sent, the backend
  /// ignores [statuses] server-side, but this method still sends both — the
  /// caller decides which filtering mode it wants by which param(s) it
  /// populates). Typed as [BookingPartition] rather than a raw `String?`
  /// (mobile-security LOW, audit-fix cycle 1) precisely because an unknown
  /// wire value degrades silently server-side — see [BookingPartition]'s doc.
  /// **No caller passes this in Phase 226** — added here so its wire wiring
  /// and the behaviour change that consumes it (Phase 227) land as separate,
  /// independently reviewable diffs.
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    required int page,
    int size = kBookingsPageSize,
    BookingSort? sort,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    BookingPartition? partition,
    CancelToken? cancelToken,
  });

  /// The set of local days on which the authenticated caller has at least one
  /// booking, across the inclusive `[from, to]` local-day range.
  ///
  /// Wraps `GET /bookings/me/booked-days` (backend Phase 26.5), which returns
  /// bare `yyyy-MM-dd` strings — parsed here into date-only LOCAL
  /// [DateTime]s via [parseApiDate].
  ///
  /// **Filter-independent by design**: the endpoint takes no status/serviceId
  /// param, so the returned days reflect ALL of the caller's bookings in the
  /// range. This is deliberate — the day-rail's dots must not vanish as the
  /// user narrows the list filter (see `bookedDaysProvider`).
  ///
  /// The backend caps the range at 366 days and requires both bounds.
  ///
  /// [cancelToken] (mobile-perf LOW, 2026-07-22) mirrors [getMyBookings]'.
  /// This is the single heaviest request in the feature — a full ±180-day
  /// sweep — so a logout or a screen pop mid-flight must be able to abort it
  /// rather than leave it running to completion for a result nobody will read.
  /// Disposing the Riverpod element stops the RESULT from landing but does
  /// not, by itself, abort the underlying Dio request.
  Future<List<DateTime>> getMyBookedDays({
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
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

  /// Declines a booking on behalf of the authenticated PROVIDER (an
  /// independent master, or a salon owner/admin with authority over it —
  /// track 27.x Wave A).
  ///
  /// Wraps `PATCH /bookings/{bookingId}/decline`. `StatusUpdateRequest
  /// .cancellationReason` is `@NotNull` on the backend; this repository
  /// always sends `PROVIDER_UNAVAILABLE` — the provider-initiated-decline
  /// reason — mirroring how [cancelBooking] always bakes in
  /// `CLIENT_CANCELLED` for the client's own cancel. `CLIENT_NO_SHOW`/
  /// `CLIENT_CANCELLED` are the client-side reasons; `DUPLICATE`/`OTHER` are
  /// not offered by this UI (see `cancel_booking_dialog.dart`'s "DO NOT BUILD
  /// A PICKER OUT OF THE ENUM" warning — the same reasoning applies here: a
  /// machine-facing taxonomy code has no business in front of a provider
  /// declining an appointment).
  ///
  /// [comment] is the OPTIONAL free-text `providerComment`, mutually visible
  /// to the client once the booking reads `DECLINED` (see CLAUDE.md booking-
  /// notes rule — symmetric, mutual visibility, no audience suppression).
  ///
  /// Throws [ProviderDeclineWindowClosedFailure] on HTTP 409 — the backend's
  /// Phase 27.1 `assertFutureForProviderCancel` guard: the booking's
  /// `startsAt` is no longer strictly in the future (SERVER clock
  /// authoritative; `Booking.hasStarted` is the UX-only mirror).
  Future<void> declineBooking(String id, {String? comment});

  /// Marks a booking COMPLETED on behalf of the authenticated PROVIDER
  /// (track 27.x Wave A).
  ///
  /// Wraps `PATCH /bookings/{bookingId}/complete` — no request body; the
  /// endpoint records no free-text account of the visit (unlike decline,
  /// which writes `providerComment`).
  ///
  /// Throws [ProviderCompleteNotStartedFailure] on HTTP 409 — the backend's
  /// Phase 27.1 `assertElapsedForComplete` guard: the booking's `startsAt` is
  /// still in the future (SERVER clock authoritative; `Booking.hasStarted` is
  /// the UX-only mirror).
  Future<void> completeBooking(String id);

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
  HttpBookingRepository(
    this._dio,
    this._bookingApi,
    this._reviewApi,
    this._staffBookingsApi,
  );

  final Dio _dio;
  final BookingControllerApi _bookingApi;
  final ReviewControllerApi _reviewApi;
  final StaffBookingsApi _staffBookingsApi;

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
  Future<Appointment> createMasterBooking(
    String masterId,
    CreateMasterBookingRequest request,
  ) async {
    // Thrown BEFORE the try/catch — a caller bug (empty/oversized list), not
    // a runtime Failure. See this method's doc for the spec-fidelity gap this
    // closes (published `minItems: 0` vs. the backend's real `@NotEmpty`).
    final int serviceCount = request.masterServiceIds.length;
    if (serviceCount == 0 || serviceCount > maxServicesPerVisit) {
      throw ArgumentError.value(
        request.masterServiceIds,
        'request.masterServiceIds',
        'must be a non-empty ordered list of at most $maxServicesPerVisit '
            'ids (got $serviceCount) — mirrors the backend '
            'MAX_SERVICES_PER_VISIT; fail fast before the wasted round-trip.',
      );
    }

    try {
      final res = await _staffBookingsApi.createStaffBooking(
        masterId: masterId,
        createStaffBookingRequest: _toWireStaffBookingRequest(request),
      );
      final dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'createMasterBooking: response data is null',
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
          'createMasterBooking failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapMasterBookingWriteException(e);
    }
  }

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    required int page,
    int size = kBookingsPageSize,
    BookingSort? sort,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    BookingPartition? partition,
    CancelToken? cancelToken,
  }) async {
    // Canonicalised ONCE, here at the serialisation boundary. See the comment
    // on the `status` param below for why this stays despite perf P5, and why
    // it sorts by `index` (not by wire string).
    //
    // `unknown` is stripped: it is a decode-only member with no wire
    // representation, and `status=UNKNOWN` would be a 400 (the backend's
    // `@Size(max = 5)` cap is sized to `BookingStatus.filterable` exactly).
    final List<String> statusParams =
        (statuses
                .where((BookingStatus s) => s != BookingStatus.unknown)
                .toList(growable: false)
              ..sort(
                (BookingStatus a, BookingStatus b) =>
                    a.index.compareTo(b.index),
              ))
            .map((BookingStatus s) => s.wireValue)
            .toList(growable: false);
    final List<String>? serviceIdParams = serviceIds == null
        ? null
        : (serviceIds.toList(growable: false)..sort());

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/bookings/me',
        queryParameters: <String, dynamic>{
          'page': page,
          'size': size,
          if (sort != null) 'sort': sort.wireValue,
          // A List value renders as REPEATED bare `status=` params under
          // Dio's default `ListFormat.multi` — mirrors the identical
          // `serviceTypeSlugs` precedent in
          // `discovery/data/search_repository.dart`. Spring's `Pageable`/
          // `@RequestParam` resolver binds repeated same-name params into the
          // backend's `EnumSet<BookingStatus>` (Phase 26.1). Omitted entirely
          // when empty so the backend applies no status filter.
          //
          // ⚠ Do NOT switch this Dio instance to `ListFormat.multiCompatible`:
          // that emits `status[]=CONFIRMED`, which Spring binds to a param
          // literally NAMED `status[]` — so the filter silently does nothing
          // and the endpoint returns unfiltered 200s. The failure is invisible
          // (no error, plausible-looking data), which is exactly why the
          // emitted query string is asserted in `booking_repository_test.dart`.
          //
          // Both repeated-param lists are canonically SORTED before
          // serialisation so the emitted URL is a pure function of the filter's
          // value, not of the order the user tapped the chips — see the
          // `MasterBookingsQuery` file header.
          //
          // Perf P5 proposed deleting this sort as "dead work duplicating
          // `MasterBookingsQuery.of`". Kept, with one change — see
          // `statusParams` above. `.of()`'s sort is NOT the same sort and is
          // not redundant with this one: it exists so two identically-valued
          // queries are `==`-equal and therefore ONE family member (List
          // equality is order-sensitive), which is the family-leak guard the
          // whole query class exists for. THIS sort exists so the emitted URL
          // is canonical for EVERY caller — including `MyBookingsNotifier`,
          // which passes `BookingTab.statuses` and never goes through `.of()`
          // at all. Deleting it would move that invariant into each call site.
          // What it cost was two sorts that disagreed (`.of()` by enum index,
          // this one by wire STRING), so the query's canonical order did not
          // survive to the wire; this one now also sorts by index, making it
          // idempotent on an already-canonical list. Cost is ≤5 elements once
          // per HTTP request.
          if (statusParams.isNotEmpty) 'status': statusParams,
          if (serviceIdParams != null && serviceIdParams.isNotEmpty)
            'serviceId': serviceIdParams,
          // `yyyy-MM-dd` off the LOCAL calendar fields — never
          // `toIso8601String()`/`.toUtc()`, which would shift the day for any
          // device east of UTC. See `shared/formatters/api_date.dart`.
          if (from != null) 'from': toApiDate(from),
          if (to != null) 'to': toApiDate(to),
          // Phase 227: `MyBookingsNotifier` now passes [partition] from BOTH
          // `_fetchFirstPage` and `loadMore`. Serialised through
          // [BookingPartition.wireValue] — the sole hand-written string this
          // repository is allowed to emit for it — and omitted entirely when
          // null, not sent as `partition=null`/`''`: `partition?.wireValue`
          // evaluates to null right along with `partition` itself, so the
          // null-aware map element below still drops the key entirely.
          //
          // ⚠ `partition` and the legacy `status` above are sent TOGETHER on
          // every request — this is deliberate, not leftover dead weight.
          // Spring silently DROPS unknown query params instead of 400ing, so
          // a client sending only `partition` against a backend that hasn't
          // shipped Phase 28.2 would send effectively no filter and get back
          // the caller's entire unfiltered booking history. Sending both
          // degrades safely to status-only filtering on a stale backend.
          // `status` is slated for removal once the backend floor is
          // confirmed to have 28.2 — not yet. See [getMyBookings]'s doc for
          // the byte-identical back-compat contract this preserves.
          //
          // ⚠ HARD SEQUENCING HAZARD — DOES NOT APPLY to `partition:
          // BookingPartition.history` (the master «Архів» page, since its
          // HISTORY cutover). The "safely degrades" reasoning two paragraphs
          // up is about an unrecognised query-parameter NAME (a wholly
          // pre-28.2 backend, which has no `partition` param declared at
          // all, so Spring drops it). `HISTORY` is a different failure mode:
          // `partition` IS a known param on any backend that shipped 28.2,
          // bound server-side to a typed `BookingPartition` enum
          // (`@RequestParam(required = false) BookingPartition partition`).
          // A VALUE that enum doesn't recognise — `HISTORY` against any
          // backend older than `81e8166` (`feat/booking-partition-history`)
          // — is a `MethodArgumentTypeMismatchException`, i.e. an HTTP 400,
          // NOT a silent degrade to the legacy `status` set sent alongside
          // it. The archive genuinely hard-requires a HISTORY-capable
          // backend; a future reader must not assume this repository's
          // additive-rollout valve protects `history` the way it protects
          // `upcoming`/`past`/`cancelled`/`awaitingClosure`. See
          // [BookingPartition]'s file header for the full reasoning.
          'partition': ?partition?.wireValue,
        },
        cancelToken: cancelToken,
      );
      return _decodeBookingsPage(response.data, requestedPage: page);
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
  Future<List<DateTime>> getMyBookedDays({
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) async {
    try {
      // Raw Dio rather than the generated client, for the same reason
      // `getMyBookings` bypasses it (see the file header): this response is a
      // bare `ApiResponse<List<LocalDate>>` of plain strings, which the
      // built_value serializers have no registered type for.
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/bookings/me/booked-days',
        queryParameters: <String, dynamic>{
          'from': toApiDate(from),
          'to': toApiDate(to),
        },
        cancelToken: cancelToken,
      );

      final Object? payload = response.data?['data'];
      if (payload is! List) {
        if (kDebugMode) {
          log(
            'getMyBookedDays: expected a List, got ${payload.runtimeType}',
            name: _tag,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }

      final List<DateTime> days = <DateTime>[];
      for (final Object? raw in payload) {
        if (raw is! String) continue;
        try {
          days.add(parseApiDate(raw));
        } on FormatException {
          // One malformed day must not blank the whole rail — the dots are a
          // hint, not a correctness gate. Skip it and keep the rest.
          if (kDebugMode) {
            log(
              'getMyBookedDays: skipping unparseable day "$raw"',
              name: _tag,
              level: 900,
            );
          }
        }
      }
      return days;
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMyBookedDays failed: ${e.type} ${e.response?.statusCode}',
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
  Future<void> declineBooking(String id, {String? comment}) async {
    final String? trimmed = comment?.trim();
    final String? effectiveComment = (trimmed == null || trimmed.isEmpty)
        ? null
        : trimmed;
    try {
      await _bookingApi.declineBooking(
        bookingId: id,
        statusUpdateRequest: StatusUpdateRequest(
          (b) => b
            ..cancellationReason =
                StatusUpdateRequestCancellationReasonEnum.PROVIDER_UNAVAILABLE
            ..comment = effectiveComment,
        ),
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'declineBooking failed: ${e.type} ${e.response?.statusCode}',
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
  Future<void> completeBooking(String id) async {
    try {
      await _bookingApi.completeBooking(bookingId: id);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'completeBooking failed: ${e.type} ${e.response?.statusCode}',
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
  /// re-map-by-status-code precedent in `services/data/service_repository.dart`.
  /// All other statuses defer to the shared [_mapDioException] (which honours
  /// any attached [Failure] and otherwise maps by transport type).
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

  /// Builds the generated wire `CreateStaffBookingRequest` DTO from the
  /// domain [CreateMasterBookingRequest] (Phase 246; widened to a
  /// multi-service list by Phase 252).
  ///
  /// [CreateMasterBookingRequest.startsAt] is forced to UTC (`.toUtc()`)
  /// here, unconditionally — the generated `Iso8601DateTimeSerializer`
  /// THROWS `ArgumentError` on a non-UTC `DateTime` at actual serialization
  /// time (`api/lib/src/serializers.dart`), and `.toUtc()` is idempotent on a
  /// value that is already UTC. This is the single point that guarantees the
  /// wire `startsAt` always carries a real, unambiguous ISO-8601 offset
  /// (`Z`) regardless of what zone the caller's `DateTime` happened to carry
  /// — see [CreateMasterBookingRequest.startsAt]'s doc for the full
  /// reasoning, including why this matters under `TZ=UTC` test runs.
  ///
  /// `..masterServiceIds.replace(...)` — NEVER `..addAll` onto a builder that
  /// may carry state from a previous build, and never `.toSet()`/sort the
  /// list first: order IS the performance order the backend chains on, and
  /// duplicates are a legal visit (the same service twice). A `.toSet()`
  /// "for safety" would silently drop that legal duplicate case and reorder
  /// the chain — see `create_master_booking_request.dart`'s doc.
  ///
  /// No naming collision with `CreateStaffBookingRequest` — unlike
  /// `CreateBookingRequest` (shared by both the domain and wire types), this
  /// generated class name is unique, so no `hide`/`show` aliasing is needed.
  CreateStaffBookingRequest _toWireStaffBookingRequest(
    CreateMasterBookingRequest req,
  ) {
    return CreateStaffBookingRequest(
      (b) => b
        ..masterServiceIds.replace(req.masterServiceIds)
        ..startsAt = req.startsAt.toUtc()
        ..guest.name = req.guest.name
        ..guest.surname = req.guest.surname
        ..guest.phone = req.guest.phone,
    );
  }

  /// Decodes the `GET /bookings/me` envelope ROW BY ROW.
  ///
  /// This used to be one `_deserialize<ApiResponsePageResponseBookingDetail
  /// Response>` call over the whole envelope, which made the page ATOMIC: any
  /// single unparseable row threw, the throw propagated as a [Failure], and
  /// «Мої записи» rendered EMPTY — the one outcome
  /// [BookingMapper.fromDtoList]'s `on Failure { continue; }` loop exists to
  /// prevent. That loop was unreachable, because the failure happened one
  /// layer below it, during envelope deserialization.
  ///
  /// Deserializing each row on its own restores the intended contract: a
  /// malformed row is skipped and logged, every sibling row still renders, and
  /// the page counters still come off the envelope. Row COUNT is deliberately
  /// NOT recomputed from the surviving rows — `totalElements`/`totalPages` are
  /// the SERVER's pagination cursor state and must stay authoritative, or a
  /// dropped row would shorten the list AND convince the pager it had reached
  /// the end.
  ///
  /// ## A DROPPED ROW IS NOT A TRUNCATED DAY (mobile-debugger MEDIUM,
  /// 2026-08-20)
  ///
  /// `BookingsDayNotifier` derives `BookingsDayState.isTruncated` from
  /// `page.totalElements > page.items.length` — "the day reports more bookings
  /// than fit in one page". Left alone, EVERY decode drop satisfied that
  /// inequality too, so a broken row rendered the master a soothing "day too
  /// dense" notice instead of anything resembling a failure. That is worse
  /// than silent: it actively disguises a decode bug as a capacity condition,
  /// and it disguises it on the exact screen where such a bug shows up.
  ///
  /// Two things fix that, and NEITHER weakens the drop-don't-throw resilience
  /// above — a broken row is still skipped, its siblings still render, and
  /// nothing here throws:
  ///
  ///   1. The drop is LOGGED unconditionally (not `kDebugMode`-gated, unlike
  ///      [_deserialize]'s own line, so it survives into a release build's
  ///      crash reporter). Count and page index only — a bookings envelope is
  ///      full of client PII and none of it belongs in a log line.
  ///   2. `totalElements` is reduced by the number of rows THIS page dropped,
  ///      so the inequality above once again means only what it says: the
  ///      SERVER withheld rows. This is not the "recompute from the surviving
  ///      rows" the paragraph above forbids — `totalPages` is untouched, and
  ///      `PageResponse.hasMore` reads `totalPages`, never `totalElements`, so
  ///      no pager can be talked into believing it reached the end. A
  ///      genuinely over-full day still truncates (150 elements, 100 rows, one
  ///      of them broken → `149 > 99`).
  ///
  /// ROW tolerance is NOT envelope tolerance. The row loop's leniency stops at
  /// the row boundary: an absent or wrong-shaped `data` / `data.data` throws
  /// [UnknownFailure], exactly as the old whole-envelope decode did. Degrading
  /// a malformed envelope to `PageResponse(items: [], totalPages: 0,
  /// totalElements: 0)` would render byte-identically to the legitimate "you
  /// have no bookings yet" empty state — no error copy, no retry affordance,
  /// no way for the user to tell a broken response from an empty account. That
  /// is strictly worse than the atomic failure this method was written to
  /// avoid, and it would also contradict the sibling [getBookingById], which
  /// still throws on a null envelope.
  ///
  /// An envelope that is well-formed but carries ZERO rows (`data.data: []`)
  /// is a legitimate empty page and returns normally.
  PageResponse<Booking> _decodeBookingsPage(
    Map<String, dynamic>? body, {
    required int requestedPage,
  }) {
    final Object? pageJson = body?['data'];
    if (pageJson is! Map<String, dynamic>) {
      throw _malformedBookingsEnvelope('data', pageJson);
    }
    final Map<String, dynamic> pageMap = pageJson;
    final Object? rowsJson = pageMap['data'];
    if (rowsJson is! List) {
      throw _malformedBookingsEnvelope('data.data', rowsJson);
    }

    final List<BookingDetailResponse> rows = <BookingDetailResponse>[];
    for (final Object? rowJson in rowsJson) {
      if (rowJson is! Map<String, dynamic>) continue;
      try {
        final BookingDetailResponse? dto = _deserialize<BookingDetailResponse>(
          rowJson,
          const FullType(BookingDetailResponse),
        );
        if (dto != null) rows.add(dto);
      } on Failure {
        // Already logged by [_deserialize]. One broken row must not blank
        // the page — that is this method's entire reason to exist.
        continue;
      }
    }

    // BOTH drop layers, counted against what the server actually SENT in this
    // page: the row loop above skips undeserializable JSON, and
    // [BookingMapper.fromDtoList] independently skips any DTO it cannot map
    // (`on Failure { continue; }`). Either one shrinks `items` without the
    // server having withheld anything.
    final List<Booking> items = BookingMapper.fromDtoList(rows);
    final int droppedRows = rowsJson.length - items.length;
    if (droppedRows > 0) {
      // Unconditional (see this method's doc, point 1). Counts only — never a
      // row's contents, which are client PII.
      log(
        'getMyBookings: dropped $droppedRows of ${rowsJson.length} row(s) on '
        'page $requestedPage — undeserializable or unmappable',
        name: _tag,
        level: 1000,
      );
    }

    final int serverTotal = _intOr(pageMap['totalElements'], 0);
    return PageResponse<Booking>(
      items: items,
      page: _intOr(pageMap['page'], requestedPage),
      totalPages: _intOr(pageMap['totalPages'], 0),
      // See this method's doc, point 2 — a drop must not read as truncation.
      // Clamped at 0 so a malformed `totalElements` smaller than the rows it
      // shipped can never produce a negative count.
      totalElements: droppedRows > 0
          ? math.max(0, serverTotal - droppedRows)
          : serverTotal,
    );
  }

  /// Builds (and logs) the [UnknownFailure] for a `GET /bookings/me` envelope
  /// whose [field] is absent or of the wrong JSON type.
  ///
  /// Only the RUNTIME TYPE of the offending value is logged, never its
  /// contents — a bookings envelope carries client names and other PII, and
  /// this log line survives into any attached crash reporter.
  Failure _malformedBookingsEnvelope(String field, Object? value) {
    if (kDebugMode) {
      log(
        'getMyBookings envelope malformed: "$field" is ${value.runtimeType}, '
        'expected ${field == 'data' ? 'a JSON object' : 'a JSON array'}',
        name: _tag,
        level: 1000,
      );
    }
    return const UnknownFailure();
  }

  /// Defensive int read off a raw JSON envelope — the transport hands back a
  /// Dart `int` or a stringified number depending on the path.
  static int _intOr(Object? raw, int fallback) => switch (raw) {
    final int value => value,
    final String value => int.tryParse(value) ?? fallback,
    _ => fallback,
  };

  /// Deserializes a raw JSON [data] map via the SAME [beauticaSerializers]
  /// `bookingApiProvider` builds the generated client on. Returns `null` when
  /// [data] is null (an empty body).
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
      return beauticaSerializers.deserialize(data, specifiedType: type) as T?;
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
  /// — mirroring the `ServiceDuplicateFailure` /
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

  /// Maps a [DioException] from `POST /api/v1/masters/{masterId}/bookings`
  /// to a typed [Failure] (Phase 246 — backend Phase 22.4's error contract,
  /// see [BookingRepository.createMasterBooking]'s doc).
  ///
  ///   - **403** → [MasterBookingNotPermittedFailure]. Backend amendment A6
  ///     collapses BOTH "wrong master" (not the owner/admin's salon, not the
  ///     independent master's own profile, a read-only `SALON_MASTER`
  ///     caller) AND "unknown/inactive master" into this ONE status — a
  ///     probe defence, not a real 404. Never surface "майстра не знайдено"
  ///     for this — see that failure's doc.
  ///   - **409 / 422** → [ConflictFailure] — overlapping booking, outside
  ///     working hours, day-off, past time, service not offered. This
  ///     endpoint has no typed `data.code` 409/422 envelope documented (no
  ///     `CLIENT_BOOKING_CONFLICT`-style sub-type the way [createBooking]'s
  ///     mapper needs one), so both statuses share the one generic
  ///     slot-conflict copy.
  ///   - everything else (notably **400**) defers to [_mapDioException] —
  ///     which already returns the [ErrorMapperInterceptor]'s
  ///     [ValidationFailure] for 400/422 via its `e.error is Failure` check.
  ///     The 403/409/422 branches here run FIRST specifically to override
  ///     what the interceptor already attached for those three codes (it has
  ///     no master-booking-specific 403 case — an unmatched 403 there falls
  ///     through to [UnknownFailure] — and maps a bare 409 to a generic
  ///     [ServerFailure] with no slot-conflict copy), mirroring the
  ///     [_mapBookingWriteException] precedent above. 422 is deliberately
  ///     NOT deferred to the interceptor's own 422 → [ValidationFailure]
  ///     branch: on THIS endpoint a 422 is a slot-availability rejection
  ///     (backend Phase 22.4's contract groups 409/422 together), not a
  ///     per-field validation error.
  Failure _mapMasterBookingWriteException(DioException e) {
    final int? statusCode = e.response?.statusCode;
    if (statusCode == 403) return MasterBookingNotPermittedFailure(cause: e);
    if (statusCode == 409 || statusCode == 422) {
      return ConflictFailure(cause: e);
    }
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

  /// Maps a [DioException] from `PATCH /bookings/{id}/decline` or
  /// `PATCH /bookings/{id}/complete` to a typed [Failure] (track 27.x Wave
  /// A). Every 409 from either endpoint means the backend's Phase 27.1
  /// `BookingTemporalGuard` rejected the action's timing — there is no typed
  /// `data.code` envelope to decode (see [ProviderDeclineWindowClosedFailure]
  /// 's doc for why), so [onConflict] resolves it PURELY by call site.
  /// Everything else defers to [_mapDioException].
  Failure _mapProviderActionException(
    DioException e, {
    required Failure Function(DioException e) onConflict,
  }) {
    if (e.response?.statusCode == 409) return onConflict(e);
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
  ///
  /// `badCertificate` gets its own branch (mobile-security LOW) rather than
  /// sharing the `badResponse`/`cancel`/`unknown` catch-all, exactly as
  /// `HttpSalonRepository._mapDioException` already does — copying that
  /// precedent CONVERGES the two files rather than diverging this one. The
  /// motivation is sharper here than it was there: this repository's
  /// `CancelToken` plumbing makes `DioExceptionType.cancel` a ROUTINE event
  /// (every logout, every `bookedDaysProvider` dispose), so a possible-MITM
  /// TLS failure on the app's most PII-dense traffic would otherwise be
  /// indistinguishable in telemetry from a user popping a screen. The
  /// [Failure] handed back to the UI is deliberately UNCHANGED
  /// ([ServerFailure] — still fails closed); only the log signal is split
  /// out. The cross-repository sweep of the remaining lump-everything
  /// mappers stays a separate backlog item.
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
        // per-call-site DioException logs elsewhere in this file): a possible
        // MITM must be visible in release-build telemetry, not only in local
        // debug runs. No PII, no token, no booking id is logged — just the
        // fact that certificate validation failed for booking traffic.
        log(
          'TLS/certificate validation failed for booking traffic — '
          'possible MITM',
          name: 'booking.repository.security',
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
