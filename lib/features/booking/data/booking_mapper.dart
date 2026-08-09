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
//     [BookingDetailResponse.startsAt], and [BookingDetailResponse.endsAt] — a
//     null value on any of these means the backend contract is broken (a
//     booking with no id/time makes no sense downstream) and surfaces as
//     [ServerFailure]. [BookingDetailResponse.status] is NOT in that set: a
//     null status decodes to [BookingStatus.unknown] and the row is kept, both
//     because the backend omitting it is survivable and because that null is
//     how `UnknownEnumTolerancePlugin` reports a status wire value this build
//     does not recognise. All other nullable
//     fields fall back to a safe default ('' / 0 / 0.0 / false), EXCEPT
//     `priceMaxAtBooking`, whose null is a real signal ("single price") and is
//     carried through as `Booking.priceMax == null` — see that field's doc.
//   - An unrecognised [BookingDetailResponse.status] wire value is NOT an
//     error: [BookingStatus.fromWire] logs and decodes it to
//     [BookingStatus.unknown], so the row is KEPT and rendered. It is NOT
//     decoded to [BookingStatus.confirmed] — `confirmed` is the one status
//     that grants capabilities (`canAddToCalendar`, cancel/decline actions),
//     so falling back to it would let a status this build does not understand
//     unlock write access. [unknown] keeps the booking visible while granting
//     nothing. See [BookingStatus.fromWire]'s doc.
//   - [fromDtoList]'s `on Failure { continue; }` loop therefore guards only
//     the missing-field case above — one broken row is dropped instead of
//     blanking the whole page.
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
  /// Throws [ServerFailure] (statusCode `null`) when [dto.id], [dto.startsAt],
  /// or [dto.endsAt] is absent. [dto.status] is deliberately NOT in that set:
  /// an unrecognised — or entirely absent — status does NOT throw, it decodes
  /// to [BookingStatus.unknown] and the booking is returned. See the file
  /// header.
  static Booking fromDto(BookingDetailResponse dto) {
    final id = dto.id;
    final statusDto = dto.status;
    final startsAt = dto.startsAt;
    final endsAt = dto.endsAt;
    if (id == null || id.isEmpty || startsAt == null || endsAt == null) {
      if (kDebugMode) {
        log(
          'BookingDetailResponse missing id/startsAt/endsAt — broken '
          'backend contract',
          name: 'feature.booking.mapper',
          level: 1000,
        );
      }
      throw const ServerFailure(statusCode: null);
    }

    // Phase 7.1: [BookingStatus.fromWire] does not throw on an unrecognised
    // wire value — it logs and decodes to [BookingStatus.unknown], so the row
    // is KEPT but NON-ACTIONABLE (previously this method rethrew as a Failure
    // and [fromDtoList]'s loop dropped the booking entirely, so a status this
    // build predates made the record silently vanish from «Мої записи»).
    //
    // The fallback is [BookingStatus.unknown], NOT [BookingStatus.confirmed] —
    // do not "simplify" it back. `confirmed` is the capability-granting status:
    // `canAddToCalendar`, the cancel/decline footer actions and the price row
    // all key off it, so decoding an unrecognised status as `confirmed` would
    // fail OPEN and let a booking whose real state this build cannot interpret
    // be written to the device calendar and acted on. `unknown` grants none of
    // those while still keeping the row visible — keep-and-deny, not
    // keep-and-allow. See [BookingStatus.fromWire]'s doc.
    //
    // The former `on ArgumentError` catch here was therefore unreachable and
    // has been removed rather than left as dead reassurance. The resilience
    // loop below still guards every OTHER mapping failure (missing id /
    // startsAt / endsAt → ServerFailure).
    //
    // A NULL `statusDto` also lands on [BookingStatus.unknown] rather than the
    // `ServerFailure` above, and this is the wiring that finally makes the
    // whole paragraph true on the real network path. The generated DTO enum
    // has no unknown member and its serializer THREW on any sixth wire value,
    // one layer BELOW this mapper — so `fromWire`'s fallback and
    // [fromDtoList]'s resilience loop were both dead code on the wire.
    // `UnknownEnumTolerancePlugin` (`core/network/`) now strips an
    // unrecognised status out of the payload before it reaches that
    // serializer, which surfaces here as `status == null`. Treating that as
    // `unknown` is the same keep-and-deny trade the rest of this comment
    // argues for, and it also covers the pre-existing "backend omitted status
    // entirely" case, which used to drop the row outright.
    final BookingStatus status = statusDto == null
        ? BookingStatus.unknown
        : BookingStatus.fromWire(statusDto.name);

    return Booking(
      id: id,
      masterId: dto.masterId ?? '',
      masterFirstName: dto.masterFirstName ?? '',
      masterLastName: dto.masterLastName ?? '',
      masterAvatarUrl: dto.masterAvatarUrl,
      masterType: dto.masterType?.name ?? '',
      salonName: dto.salonName,
      // Phase 232. Deliberately NOT in the required-field set above: a null
      // `salonId` is a legitimate INDEPENDENT_MASTER booking, never a broken
      // payload, so it must not throw [ServerFailure] and must not be dropped
      // by [fromDtoList]'s resilience loop. Mapped verbatim and INDEPENDENTLY
      // of `salonName` — neither is derived from the other (see
      // `Booking.salonId`'s doc).
      salonId: dto.salonId,
      // Phase 7.2 — the counterparty as the PROVIDER sees it. `clientId` is
      // legitimately null on a guest/LINK booking; `clientFirstName`/
      // `clientLastName` are NOT defaulted to '' here (unlike the master
      // fields above) because `BookingDisplayX.clientName` distinguishes
      // "absent" from "empty" to pick its «Гість» fallback.
      clientId: dto.clientId?.toString(),
      clientFirstName: dto.clientFirstName,
      clientLastName: dto.clientLastName,
      // NOT coalesced to '' for the same reason as the two names above, and
      // one more: the empty string is not a URL, so defaulting would hand
      // `Image.network` a value it would try to fetch. Null stays null all the
      // way to the card, where it selects the fallback glyph. See
      // `Booking.clientAvatarUrl` — null here is "no photo", never "not
      // permitted to see it".
      clientAvatarUrl: dto.clientAvatarUrl,
      serviceId: dto.masterServiceId ?? '',
      serviceName: dto.serviceName ?? '',
      categoryName: dto.categoryName,
      cityLabel: dto.cityLabel,
      districtLabel: dto.districtLabel,
      street: dto.street,
      buildingNo: dto.buildingNo,
      durationMinutes: dto.durationMinutesAtBooking ?? 0,
      price: dto.priceAtBooking?.toDouble() ?? 0.0,
      // NOT coalesced — unlike every other nullable field above, a null
      // ceiling is MEANINGFUL: it is the backend saying "this booking has a
      // single price". Defaulting it to 0.0 (or to `priceAtBooking`) would
      // erase that distinction; `Booking.priceMax` stays nullable all the way
      // to `formatBookingPrice`, which is the one place the floor-vs-band
      // choice is made. See `Booking.priceMax`'s doc.
      priceMax: dto.priceMaxAtBooking?.toDouble(),
      startAt: startsAt,
      endAt: endsAt,
      status: status,
      canReview: dto.canReview ?? false,
      // Real value only on GET /bookings/{id}; both GET /bookings/me listing
      // paths hardcode false server-side, so a null/false wire value here is
      // the expected shape there, not a missing-field defect. See
      // `Booking.providerCanReviewClient`'s doc.
      providerCanReviewClient: dto.providerCanReviewClient ?? false,
      // Phase 29.2 field; defaulted so a pre-29.2 backend omitting it entirely
      // cannot crash the mapper. See `Booking.awaitingClosure`'s doc.
      awaitingClosure: dto.awaitingClosure ?? false,
      clientComment: dto.clientComment,
      providerComment: dto.providerComment,
      clientCancellationNote: dto.clientCancellationNote,
      masterProfessionalTitle: dto.masterProfessionalTitle,
      // Phase 240. NOT coalesced, for the same reason as `priceMax` above: a
      // null average is MEANINGFUL — it is the backend saying "this master has
      // no reviews yet". The wire value is already normalised server-side (the
      // stored 0.00 of an unreviewed master is sent as null), so a `?? 0` here
      // would launder that signal back into a rating of zero and show a
      // brand-new master zero stars. Stays nullable all the way to the UI.
      masterAvgRating: dto.masterAvgRating?.toDouble(),
      // Left nullable rather than defaulted to 0: a pre-240 backend omitting
      // the field entirely means "unknown", which is not the same as a genuine
      // zero-review master. See `Booking.masterReviewCount`'s doc.
      masterReviewCount: dto.masterReviewCount,
      locationNote: dto.locationNote,
      // Additive (MO-1): null on a standalone single-service booking, set when
      // this booking is one line of a multi-service visit. Carried through for
      // MO-5's list grouping — nothing keys off it yet.
      appointmentId: dto.appointmentId,
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
