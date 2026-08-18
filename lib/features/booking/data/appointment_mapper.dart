// MO-1 — AppointmentMapper: the single translation boundary between the
// generated `beautica_api` appointment DTOs (`AppointmentDetailResponse`,
// `AppointmentItemResponse`) and the domain models in
// `features/booking/domain/appointment.dart`.
//
// Mirrors `booking_mapper.dart`'s contract and error handling:
//   - [AppointmentMapper.fromDto] requires [AppointmentDetailResponse.id],
//     [.startsAt] and [.endsAt] — a null on any of these means a broken
//     backend contract and surfaces as [ServerFailure] (statusCode null). All
//     other nullable header fields fall back to a safe default
//     ('' / 0 / 0.0 / false), EXCEPT `totalPriceMax`, whose null is a real
//     signal ("single total") carried through as `Appointment.totalPriceMax ==
//     null` — see that field's doc.
//   - An unrecognised [.status] wire value is NOT an error: [BookingStatus
//     .fromWire] logs and decodes it to [BookingStatus.unknown] (keep-and-deny),
//     so the visit stays visible while granting no capability — same rationale
//     as the booking mapper. A NULL [.status] lands on the same
//     [BookingStatus.unknown] rather than the [ServerFailure] above; see
//     [AppointmentMapper.fromDto].
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
  /// Throws [ServerFailure] (statusCode `null`) when [dto.id], [dto.startsAt]
  /// or [dto.endsAt] is absent, or when any item is malformed (see the file
  /// header). Neither an unrecognised NOR an absent [dto.status] throws — both
  /// decode to [BookingStatus.unknown].
  static Appointment fromDto(AppointmentDetailResponse dto) {
    final id = dto.id;
    final statusDto = dto.status;
    final startsAt = dto.startsAt;
    final endsAt = dto.endsAt;
    if (id == null || id.isEmpty || startsAt == null || endsAt == null) {
      if (kDebugMode) {
        log(
          'AppointmentDetailResponse missing id/startsAt/endsAt — '
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
    //
    // A NULL `statusDto` lands here too, and deliberately no longer joins the
    // `ServerFailure` guard above. It is the shape
    // `UnknownEnumTolerancePlugin` produces: the generated
    // `AppointmentDetailResponseStatusEnum` is a built_value `EnumClass` with
    // no unknown member, so its serializer THREW `ArgumentError` on any wire
    // value this build predates — one layer BELOW this mapper, which made the
    // `fromWire` fallback directly above unreachable dead code on the real
    // network path (the identical defect fixed for `BookingDetailResponse`).
    // The plugin now strips that value so the field arrives absent; treating
    // absent as `unknown` is what turns a hard failure into the keep-and-deny
    // degrade the paragraph above promises. Rejecting null here instead would
    // convert a graceful degrade into a `ServerFailure` — strictly worse than
    // the throw it replaced. It also covers the pre-existing "backend omitted
    // status entirely" case, which used to fail the whole visit.
    final BookingStatus status = statusDto == null
        ? BookingStatus.unknown
        : BookingStatus.fromWire(statusDto.name);

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
  ///
  /// [dto.status] (the per-item status) is registered in
  /// `kBeauticaToleratedEnums` alongside the two response-level statuses even
  /// though this mapper does not read it and [AppointmentItem] has no `status`
  /// field. That is not an oversight: tolerance is needed at the WIRE layer,
  /// not the mapper layer. `AppointmentItemResponseStatusEnum` is its own
  /// `EnumClass` with its own throwing serializer, and the items list is
  /// deserialized as part of the parent `AppointmentDetailResponse` — so an
  /// unrecognised status on ONE line item would abort the whole visit's
  /// deserialization before this mapper (or the parent's) ever ran, no matter
  /// that the value is subsequently discarded. Nothing to teach here; the
  /// stripped field is simply never read.
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
