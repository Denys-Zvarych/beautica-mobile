// MO-1 — AppointmentMapper: the single translation boundary between the
// generated `beautica_api` appointment DTOs (`AppointmentDetailResponse`,
// `AppointmentItemResponse`) and the domain models in
// `features/booking/domain/appointment.dart`.
//
// Mirrors `booking_mapper.dart`'s contract and error handling:
//   - [AppointmentMapper.fromDto] requires [AppointmentDetailResponse.id],
//     [.status], [.startsAt] and [.endsAt] — a null on any of these means a
//     broken backend contract and surfaces as [ServerFailure] (statusCode
//     null). All other nullable header fields fall back to a safe default
//     ('' / 0 / 0.0 / false), EXCEPT `totalPriceMax`, whose null is a real
//     signal ("single total") carried through as `Appointment.totalPriceMax ==
//     null` — see that field's doc.
//   - An unrecognised [.status] wire value is NOT an error: [BookingStatus
//     .fromWire] logs and decodes it to [BookingStatus.unknown] (keep-and-deny),
//     so the visit stays visible while granting no capability — same rationale
//     as the booking mapper.
//   - Each [AppointmentItemResponse] is mapped by [AppointmentItemMapper]. An
//     item missing its `bookingId`/`masterServiceId`/`startsAt`/`endsAt` is a
//     broken contract for the WHOLE visit (a visit's total is the sum of its
//     items, so a silently-dropped item would corrupt the totals) — it throws
//     [ServerFailure] and fails the whole `fromDto`, rather than the
//     drop-one-row leniency the booking LIST mapper uses. A visit is a single
//     aggregate fetched by id, not a page of independent rows.
//
// Generated DTO types must NEVER cross this boundary into the domain or
// presentation layers — only `HttpAppointmentRepository` may import this file's
// DTOs.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:flutter/foundation.dart';

import '../domain/appointment.dart';
import '../domain/booking_status.dart';

const String _tag = 'feature.booking.appointment_mapper';

/// Converts generated `beautica_api` appointment types into the domain
/// [Appointment] / [AppointmentItem] entities.
///
/// Pure translation — no network calls, no state. Call only from
/// [HttpAppointmentRepository].
abstract final class AppointmentMapper {
  /// Maps an [AppointmentDetailResponse] DTO to the domain [Appointment].
  ///
  /// Throws [ServerFailure] (statusCode `null`) when [dto.id], [dto.status],
  /// [dto.startsAt] or [dto.endsAt] is absent, or when any item is malformed
  /// (see the file header). An unrecognised [dto.status] wire value does NOT
  /// throw — it decodes to [BookingStatus.unknown].
  static Appointment fromDto(AppointmentDetailResponse dto) {
    final id = dto.id;
    final statusDto = dto.status;
    final startsAt = dto.startsAt;
    final endsAt = dto.endsAt;
    if (id == null ||
        id.isEmpty ||
        statusDto == null ||
        startsAt == null ||
        endsAt == null) {
      if (kDebugMode) {
        log(
          'AppointmentDetailResponse missing id/status/startsAt/endsAt — '
          'broken backend contract',
          name: _tag,
          level: 1000,
        );
      }
      throw const ServerFailure(statusCode: null);
    }

    // Keep-and-deny on an unrecognised status — same contract and rationale as
    // BookingMapper.fromDto (see BookingStatus.fromWire's doc). NOT decoded to
    // `confirmed`.
    final BookingStatus status = BookingStatus.fromWire(statusDto.name);

    final List<AppointmentItem> items = <AppointmentItem>[
      for (final AppointmentItemResponse itemDto
          in dto.items ?? const <AppointmentItemResponse>[])
        AppointmentItemMapper.fromDto(itemDto),
    ];

    return Appointment(
      id: id,
      status: status,
      masterId: dto.masterId ?? '',
      masterFirstName: dto.masterFirstName ?? '',
      masterLastName: dto.masterLastName ?? '',
      masterProfessionalTitle: dto.masterProfessionalTitle,
      masterAvatarUrl: dto.masterAvatarUrl,
      masterType: dto.masterType?.name ?? '',
      salonName: dto.salonName,
      startAt: startsAt,
      endAt: endsAt,
      totalDurationMinutes: dto.totalDurationMinutes ?? 0,
      totalPrice: dto.totalPrice?.toDouble() ?? 0.0,
      // NOT coalesced — a null ceiling MEANS "single total"; defaulting it
      // would erase that. Carried nullable all the way to the price formatter.
      totalPriceMax: dto.totalPriceMax?.toDouble(),
      items: items,
      canReview: dto.canReview ?? false,
      clientComment: dto.clientComment,
      providerComment: dto.providerComment,
      clientCancellationNote: dto.clientCancellationNote,
      cityLabel: dto.cityLabel,
      districtLabel: dto.districtLabel,
      street: dto.street,
      buildingNo: dto.buildingNo,
      locationNote: dto.locationNote,
      createdAt: dto.createdAt,
    );
  }
}

/// Converts a generated [AppointmentItemResponse] DTO into the domain
/// [AppointmentItem].
abstract final class AppointmentItemMapper {
  /// Maps an [AppointmentItemResponse] to [AppointmentItem].
  ///
  /// Throws [ServerFailure] (statusCode `null`) when [dto.bookingId],
  /// [dto.masterServiceId], [dto.startsAt] or [dto.endsAt] is absent — a
  /// malformed item corrupts the visit's totals, so it fails the whole
  /// appointment rather than being silently dropped (see the file header).
  /// `priceMaxAtBooking` stays nullable — a null there means "single price",
  /// not a missing value.
  static AppointmentItem fromDto(AppointmentItemResponse dto) {
    final bookingId = dto.bookingId;
    final masterServiceId = dto.masterServiceId;
    final startsAt = dto.startsAt;
    final endsAt = dto.endsAt;
    if (bookingId == null ||
        bookingId.isEmpty ||
        masterServiceId == null ||
        masterServiceId.isEmpty ||
        startsAt == null ||
        endsAt == null) {
      if (kDebugMode) {
        log(
          'AppointmentItemResponse missing bookingId/masterServiceId/'
          'startsAt/endsAt — broken backend contract',
          name: _tag,
          level: 1000,
        );
      }
      throw const ServerFailure(statusCode: null);
    }
    return AppointmentItem(
      bookingId: bookingId,
      masterServiceId: masterServiceId,
      serviceName: dto.serviceName ?? '',
      startAt: startsAt,
      endAt: endsAt,
      durationMinutes: dto.durationMinutesAtBooking ?? 0,
      price: dto.priceAtBooking?.toDouble() ?? 0.0,
      priceMax: dto.priceMaxAtBooking?.toDouble(),
    );
  }
}
