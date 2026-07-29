// Phase 14.0 — SlotRepository: interface + HTTP implementation.
// Phase 14.14 extended this with [getWorkingDays].
//
// Wraps `GET /api/v1/masters/{masterId}/slots` (the generated
// `MasterControllerApi.getAvailableSlots`) and, since Phase 14.14,
// `GET /api/v1/masters/{masterId}/working-days`
// (`MasterControllerApi.getWorkingDays`) — NOT `PublicBookingControllerApi`,
// which is the unauthenticated guest-booking flow (a different feature).
// Deliberately kept in the BOOKING feature's data layer (not
// `schedule/data/`): `schedule_repository.dart` /
// `effectiveScheduleProvider` are hard-wired to "my own master only" via
// `masterProfileProvider`, whereas the client-facing calendar needs an
// arbitrary master's working days — mixing that into the schedule feature
// would break that "own profile only" boundary.
//
// Kept provider-free on purpose (mirrors `booking_repository.dart` /
// `schedule_repository.dart`) — see `booking_providers.dart` for the Riverpod
// wiring. Tests construct [HttpSlotRepository] directly with a mocktail
// [MasterControllerApi].

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../domain/booking_slot.dart';
import '../domain/working_day.dart';
import 'booking_mapper.dart';

const String _tag = 'feature.booking.slot_repository';

/// Max services in one multi-service availability query — mirrors the backend
/// `MAX_SERVICES_PER_VISIT` (`@Size(max = 10)` on the now-repeatable
/// `serviceId` query param). The booking UI (MO-3/MO-4) caps the visit
/// selection at this; the [SlotRepository] methods assert on it as a
/// fail-fast, dev-time guard so a malformed caller is caught before the wasted
/// round-trip that the backend would otherwise reject with a 400.
const int maxServicesPerVisit = 10;

/// Contract for the master-availability read layer.
///
/// Every method either resolves successfully or throws a [Failure] subclass
/// from `core/errors/failures.dart`. Raw [DioException]s never escape.
abstract interface class SlotRepository {
  /// Fetches the bookable time slots for [masterId] + [serviceIds] on the
  /// given calendar [date] (time-of-day component discarded).
  ///
  /// [serviceIds] is an ORDERED, non-empty list of ≤ [maxServicesPerVisit] ids
  /// (MO-2): the backend sizes each returned slot to the SUMMED duration of
  /// the listed services, performed back-to-back by this one master. Order is
  /// significant (it is the back-to-back running order) and is preserved on
  /// the wire as repeated `serviceId=` params in list order. A single-element
  /// list is the single-service path — byte-for-byte identical to the pre-MO-2
  /// one-`serviceId=` request. The multi-service flow screens are wired in
  /// MO-3/MO-4; today every caller passes exactly one id.
  ///
  /// Wraps `GET /masters/{masterId}/slots`. Returns an empty list when the
  /// master has no availability that day (a valid, non-error result — the
  /// slot picker renders an empty-state, not an error).
  ///
  /// [cancelToken] lets callers (the slot picker notifier) cancel an
  /// in-flight request when the client switches days again before this one
  /// resolves, so rapid day-switching never stacks N concurrent requests.
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
    CancelToken? cancelToken,
  });

  /// Fetches the per-date working/non-working signal for [masterId] across
  /// [from]..[to] (inclusive, date-only; time-of-day is discarded).
  ///
  /// Wraps `GET /masters/{masterId}/working-days`. Callers (the Phase 14.14
  /// calendar day-availability gate) MUST keep the span bounded — the backend
  /// rejects an over-wide window: ~365 days in schedule-shape mode, but only
  /// 62 days once [serviceIds] is supplied (400 beyond that).
  ///
  /// When [serviceIds] is non-null it is an ORDERED, non-empty list of ≤
  /// [maxServicesPerVisit] ids and the returned `working` flag is
  /// AVAILABILITY-AWARE (Phase 14.20 / MO-2): true iff a free range fits the
  /// SUMMED duration of the listed services with start >= now+15min — the same
  /// computation as [getMasterSlots], so the calendar's day gate agrees with
  /// the time grid. A single-element list is byte-for-byte identical to the
  /// pre-MO-2 one-`serviceId=` request. When null the flag is the older
  /// schedule-shape signal (master has intervals that day, duration-blind) and
  /// the query param is omitted entirely.
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
    List<String>? serviceIds,
    CancelToken? cancelToken,
  });
}

/// HTTP implementation of [SlotRepository].
///
/// Inject via [slotRepositoryProvider] — never construct directly outside
/// tests.
final class HttpSlotRepository implements SlotRepository {
  HttpSlotRepository(this._masterApi);

  final MasterControllerApi _masterApi;

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
    CancelToken? cancelToken,
  }) async {
    assert(
      serviceIds.isNotEmpty && serviceIds.length <= maxServicesPerVisit,
      'serviceIds must be a non-empty ordered list of at most '
      '$maxServicesPerVisit ids (got ${serviceIds.length}) — mirrors the '
      'backend MAX_SERVICES_PER_VISIT; fail fast before the wasted round-trip.',
    );
    try {
      final res = await _masterApi.getAvailableSlots(
        masterId: masterId,
        // `serviceId` is a REPEATABLE query param on the backend
        // (feat/multi-service-appointments — the generated param is a
        // `BuiltList<String>` for multi-service availability). The ordered
        // [serviceIds] pass straight through; a single-element list serialises
        // to exactly the one `serviceId=` param the pre-MO-2 code sent —
        // byte-for-byte identical. N ids serialise as N ordered `serviceId=`
        // params, and the backend sizes each slot to their summed duration.
        serviceId: BuiltList<String>(serviceIds),
        // Date-only wire param (year-month-day only; time-of-day discarded) —
        // mirrors `ScheduleMapper.dateToWire`.
        date: Date(date.year, date.month, date.day),
        cancelToken: cancelToken,
      );
      final slots = res.data?.data?.slots ?? const <AvailableSlotResponse>[];
      return BookingSlotMapper.fromDtoList(slots);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMasterSlots failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
    List<String>? serviceIds,
    CancelToken? cancelToken,
  }) async {
    assert(
      serviceIds == null ||
          (serviceIds.isNotEmpty && serviceIds.length <= maxServicesPerVisit),
      'serviceIds, when non-null, must be a non-empty ordered list of at most '
      '$maxServicesPerVisit ids (got ${serviceIds.length}) — mirrors the '
      'backend MAX_SERVICES_PER_VISIT; fail fast before the wasted round-trip.',
    );
    try {
      final res = await _masterApi.getWorkingDays(
        masterId: masterId,
        // Date-only wire params — mirrors `getMasterSlots`'s `date` param.
        from: Date(from.year, from.month, from.day),
        to: Date(to.year, to.month, to.day),
        // Availability-aware mode when non-null; the generated client omits
        // the query param entirely when null (schedule-shape mode). The
        // ordered [serviceIds] pass straight through the REPEATABLE
        // `BuiltList<String>` param (see `getMasterSlots`) — a single-element
        // list serialises to exactly the one `serviceId=` param the pre-MO-2
        // code sent.
        serviceId: serviceIds == null ? null : BuiltList<String>(serviceIds),
        cancelToken: cancelToken,
      );
      final days = res.data?.data ?? const <MasterWorkingDayResponse>[];
      return WorkingDayMapper.fromDtoList(days);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getWorkingDays failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  /// Maps a [DioException] to a typed [Failure]. Mirrors the identical
  /// mapping in `HttpBookingRepository`.
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
