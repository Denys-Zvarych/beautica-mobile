// Phase 14.0 — SlotRepository: interface + HTTP implementation.
//
// Wraps `GET /api/v1/masters/{masterId}/slots` (the generated
// `MasterControllerApi.getAvailableSlots`) — NOT `PublicBookingControllerApi`,
// which is the unauthenticated guest-booking flow (a different feature).
//
// Kept provider-free on purpose (mirrors `booking_repository.dart` /
// `schedule_repository.dart`) — see `booking_providers.dart` for the Riverpod
// wiring. Tests construct [HttpSlotRepository] directly with a mocktail
// [MasterControllerApi].

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../domain/booking_slot.dart';
import 'booking_mapper.dart';

const String _tag = 'feature.booking.slot_repository';

/// Contract for the master-availability read layer.
///
/// Every method either resolves successfully or throws a [Failure] subclass
/// from `core/errors/failures.dart`. Raw [DioException]s never escape.
abstract interface class SlotRepository {
  /// Fetches the bookable time slots for [masterId] + [serviceId] on the
  /// given calendar [date] (time-of-day component discarded).
  ///
  /// Wraps `GET /masters/{masterId}/slots`. Returns an empty list when the
  /// master has no availability that day (a valid, non-error result — the
  /// slot picker renders an empty-state, not an error).
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required String serviceId,
    required DateTime date,
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
    required String serviceId,
    required DateTime date,
  }) async {
    try {
      final res = await _masterApi.getAvailableSlots(
        masterId: masterId,
        serviceId: serviceId,
        // Date-only wire param (year-month-day only; time-of-day discarded) —
        // mirrors `ScheduleMapper.dateToWire`.
        date: Date(date.year, date.month, date.day),
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
