// Phase 14.0 — BookingMapper / BookingSlotMapper: the single translation
// boundary between the generated `beautica_api` booking/slot DTOs and the
// domain models in `features/booking/domain/`.
//
// Generated DTO types (`BookingDetailResponse`,
// `BookingDetailResponse*Enum`, `AvailableSlotResponse`) must NEVER cross this
// boundary into the domain or presentation layers — only
// `HttpBookingRepository` / `HttpSlotRepository` may import this file's DTOs.
//
// Error contract (mirrors `SalonMapper.fromDto` — ServerFailure for a missing
// required id):
//   - [BookingMapper.fromDto] requires [BookingDetailResponse.id],
//     [BookingDetailResponse.status], [BookingDetailResponse.startsAt], and
//     [BookingDetailResponse.endsAt] — a null value on any of these means the
//     backend contract is broken (a booking with no id/status/time makes no
//     sense downstream) and surfaces as [ServerFailure]. All other nullable
//     fields fall back to a safe default ('' / 0 / 0.0 / false).
//   - An unrecognised [BookingDetailResponse.status] wire value (rejected by
//     [BookingStatus.fromWire]'s `ArgumentError`) surfaces as [UnknownFailure]
//     — mirrors `HttpAuthRepository.validateInvite`'s `UserRole.fromWire`
//     handling. Both this case and the missing-field case above are [Failure]
//     subclasses, so [fromDtoList]'s `on Failure { continue; }` loop drops
//     just the one broken row instead of blanking the whole page.
//
// DEVIATION (BookingSlot.available): see the file header of
// `domain/booking_slot.dart` — `AvailableSlotResponse` carries no availability
// boolean on the wire, so [BookingSlotMapper] always maps `available: true`.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:flutter/foundation.dart';

import '../domain/booking.dart';
import '../domain/booking_slot.dart';
import '../domain/booking_status.dart';
import '../domain/working_day.dart';

/// Converts generated `beautica_api` booking types into the domain [Booking]
/// entity.
///
/// Pure translation — no network calls, no state. Call only from
/// [HttpBookingRepository].
abstract final class BookingMapper {
  /// Maps a [BookingDetailResponse] DTO to the domain [Booking] model.
  ///
  /// Throws [ServerFailure] (statusCode `null`) when [dto.id], [dto.status],
  /// [dto.startsAt], or [dto.endsAt] is absent, or [UnknownFailure] when
  /// [dto.status] is an unrecognised wire value — see the file header.
  static Booking fromDto(BookingDetailResponse dto) {
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
          'BookingDetailResponse missing id/status/startsAt/endsAt — broken '
          'backend contract',
          name: 'feature.booking.mapper',
          level: 1000,
        );
      }
      throw const ServerFailure(statusCode: null);
    }

    final BookingStatus status;
    try {
      status = BookingStatus.fromWire(statusDto.name);
    } on ArgumentError {
      // A future/unrecognised backend status value must not crash the whole
      // "my bookings" page — rethrow as a [Failure] so [fromDtoList]'s
      // `on Failure { continue; }` loop drops just this one row. Mirrors
      // `HttpAuthRepository.validateInvite`'s `UserRole.fromWire` handling.
      if (kDebugMode) {
        log(
          'BookingDetailResponse.status unrecognised: ${statusDto.name}',
          name: 'feature.booking.mapper',
          level: 1000,
        );
      }
      throw const UnknownFailure(cause: 'unknown booking status');
    }

    return Booking(
      id: id,
      masterId: dto.masterId ?? '',
      masterFirstName: dto.masterFirstName ?? '',
      masterLastName: dto.masterLastName ?? '',
      masterAvatarUrl: dto.masterAvatarUrl,
      masterType: dto.masterType?.name ?? '',
      salonName: dto.salonName,
      serviceId: dto.masterServiceId ?? '',
      serviceName: dto.serviceName ?? '',
      categoryName: dto.categoryName,
      cityLabel: dto.cityLabel,
      districtLabel: dto.districtLabel,
      street: dto.street,
      buildingNo: dto.buildingNo,
      durationMinutes: dto.durationMinutesAtBooking ?? 0,
      price: dto.priceAtBooking?.toDouble() ?? 0.0,
      startAt: startsAt,
      endAt: endsAt,
      status: status,
      canReview: dto.canReview ?? false,
      clientComment: dto.clientComment,
      providerComment: dto.providerComment,
    );
  }

  /// Entries that fail [fromDto]'s required-field check (or carry an
  /// unrecognised [BookingStatus]) are dropped (logged) rather than thrown —
  /// one broken row must not blank the whole "my bookings" page. Mirrors the
  /// `SalonMasterMapper.fromDtoList` pattern.
  static List<Booking> fromDtoList(Iterable<BookingDetailResponse> dtos) {
    final List<Booking> out = <Booking>[];
    for (final BookingDetailResponse dto in dtos) {
      try {
        out.add(fromDto(dto));
      } on Failure {
        // Already logged inside fromDto — skip this row.
        continue;
      }
    }
    return out;
  }
}

/// Converts the generated [AvailableSlotResponse] DTO into the domain
/// [BookingSlot] entity.
abstract final class BookingSlotMapper {
  /// Maps an [AvailableSlotResponse] DTO to [BookingSlot].
  ///
  /// Returns `null` (rather than throwing) when [dto.startsAt] or
  /// [dto.endsAt] is absent — a single malformed slot must not blank the
  /// whole day's picker; the caller (`fromDtoList`) drops it.
  ///
  /// `available` is always mapped to `true` — see the DEVIATION note at the
  /// top of this file / `domain/booking_slot.dart`.
  static BookingSlot? fromDto(AvailableSlotResponse dto) {
    final startAt = dto.startsAt;
    final endAt = dto.endsAt;
    if (startAt == null || endAt == null) {
      if (kDebugMode) {
        log(
          'AvailableSlotResponse missing startsAt/endsAt — dropping slot',
          name: 'feature.booking.mapper',
          level: 900,
        );
      }
      return null;
    }
    return BookingSlot(startAt: startAt, endAt: endAt, available: true);
  }

  /// Maps a list of [AvailableSlotResponse] DTOs to [BookingSlot]s, dropping
  /// any malformed entries (see [fromDto]).
  static List<BookingSlot> fromDtoList(Iterable<AvailableSlotResponse> dtos) {
    final List<BookingSlot> out = <BookingSlot>[];
    for (final AvailableSlotResponse dto in dtos) {
      final slot = fromDto(dto);
      if (slot != null) out.add(slot);
    }
    return out;
  }
}

/// Converts the generated [MasterWorkingDayResponse] DTO (Phase 14.14 —
/// `GET /masters/{masterId}/working-days`) into the domain [WorkingDay]
/// entity.
abstract final class WorkingDayMapper {
  /// Maps a [MasterWorkingDayResponse] DTO to [WorkingDay].
  ///
  /// Returns `null` (rather than throwing) when [dto.date] or [dto.working]
  /// is absent — a single malformed entry must not blank the whole month's
  /// calendar gating; the caller ([fromDtoList]) drops it, and
  /// `SlotDateScreen` treats a day missing from the resolved set as
  /// conservatively non-working rather than defaulting it to tappable.
  static WorkingDay? fromDto(MasterWorkingDayResponse dto) {
    final date = dto.date;
    final working = dto.working;
    if (date == null || working == null) {
      if (kDebugMode) {
        log(
          'MasterWorkingDayResponse missing date/working — dropping entry',
          name: 'feature.booking.mapper',
          level: 900,
        );
      }
      return null;
    }
    return WorkingDay(date: date.toDateTime(), working: working);
  }

  /// Maps a list of [MasterWorkingDayResponse] DTOs to [WorkingDay]s,
  /// dropping any malformed entries (see [fromDto]).
  static List<WorkingDay> fromDtoList(Iterable<MasterWorkingDayResponse> dtos) {
    final List<WorkingDay> out = <WorkingDay>[];
    for (final MasterWorkingDayResponse dto in dtos) {
      final day = fromDto(dto);
      if (day != null) out.add(day);
    }
    return out;
  }
}
