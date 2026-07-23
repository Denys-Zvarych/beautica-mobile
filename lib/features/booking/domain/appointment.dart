// MO-1 — Multi-service single-visit data foundation: [Appointment] +
// [AppointmentItem] domain models.
//
// The VISIT aggregate: one appointment groups N per-service bookings the client
// placed against the SAME master for ONE arrival (backend
// `feat/multi-service-appointments`, migrations V124–V127). Mirrors the
// enriched `AppointmentDetailResponse` DTO (header + ordered `items[]` +
// visit-level totals), exactly as [Booking] mirrors `BookingDetailResponse` —
// see `booking.dart` — so the visit detail / grouping screens (MO-2…MO-5) never
// need a secondary fetch once they hold an [Appointment].
//
// This is the SERVER-side visit aggregate returned by `GET /appointments/{id}`.
//
// [status] reuses the shared [BookingStatus] enum: the appointment status
// machine is the same five states as a booking (CONFIRMED / DECLINED /
// COMPLETED / NOT_COMPLETED / CANCELLED — no PENDING), so the visit reuses the
// booking domain's `fromWire`/`unknown` keep-and-deny contract rather than
// duplicating an enum. [masterType] is carried as the raw wire string for the
// same reason `Booking.masterType` is — to keep this domain file free of a
// cross-feature `MasterType` dependency for a purely informational field.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'booking_status.dart';

part 'appointment.freezed.dart';

/// One line of a multi-service visit: a single service the client booked as
/// part of the appointment, with its own per-item window, duration and price
/// snapshot. Mirrors `AppointmentItemResponse`.
@freezed
abstract class AppointmentItem with _$AppointmentItem {
  const factory AppointmentItem({
    /// The id of the underlying single-service booking this item resolves to
    /// (`bookingId` on the wire). Lets MO-5 cross-link an item back to its
    /// legacy per-service booking row.
    required String bookingId,

    /// The `MasterService.id` this item was booked against.
    required String masterServiceId,
    required String serviceName,

    /// This item's own start/end within the visit (the visit's services run
    /// back-to-back, so item windows are contiguous but distinct).
    required DateTime startAt,
    required DateTime endAt,
    required int durationMinutes,

    /// The price agreed AT BOOKING TIME (`priceAtBooking`). When [priceMax] is
    /// non-null this is the band FLOOR; otherwise it is the whole price. Never
    /// re-read from the live catalogue — see `Booking.price`.
    required double price,

    /// The band CEILING agreed at booking time (`priceMaxAtBooking`). **Null
    /// means SINGLE PRICE — render [price] alone.** Not a missing value — see
    /// `Booking.priceMax`.
    double? priceMax,
  }) = _AppointmentItem;
}

/// A multi-service single-visit appointment: the header (master summary,
/// window, locality), the ordered [items], and the visit-level totals.
///
/// Enriched to mirror `AppointmentDetailResponse` so the detail / grouping
/// screens have every field without a second round-trip.
@freezed
abstract class Appointment with _$Appointment {
  const factory Appointment({
    required String id,
    required BookingStatus status,
    required String masterId,
    required String masterFirstName,
    required String masterLastName,
    String? masterProfessionalTitle,
    String? masterAvatarUrl,

    /// Raw backend wire value: `"INDEPENDENT_MASTER"` | `"SALON_MASTER"` | …
    /// (any `MasterType`-family value the DTO carries). Only decides whether
    /// [salonName] is rendered — see the file header.
    required String masterType,

    /// Null for an `INDEPENDENT_MASTER` visit; set for a salon-employed
    /// master's visit.
    String? salonName,

    /// The visit's overall window: the earliest item start and the latest item
    /// end.
    required DateTime startAt,
    required DateTime endAt,

    /// Sum of the items' durations (`totalDurationMinutes`).
    required int totalDurationMinutes,

    /// Sum of the items' price floors (`totalPrice`). When [totalPriceMax] is
    /// non-null this is the band FLOOR.
    required double totalPrice,

    /// The visit's aggregate band CEILING (`totalPriceMax`). **Null means the
    /// whole visit resolved to a single total — render [totalPrice] alone.**
    /// Non-null when at least one item carried a range at booking time.
    double? totalPriceMax,

    /// The ordered services in this visit (`items` — server-ordered by start).
    required List<AppointmentItem> items,

    /// `true` only when [status] is [BookingStatus.completed] AND the client
    /// has not already reviewed this visit. Server-computed — never re-derived
    /// from [status] alone.
    required bool canReview,

    /// The client's free-text note written at booking time (`clientComment`).
    /// Visible to the provider; echoed back to the client. Distinct from
    /// [clientCancellationNote].
    String? clientComment,

    /// **Free text written by the PROVIDER** (never an enum) — set on
    /// [BookingStatus.declined] / [BookingStatus.notCompleted], null otherwise.
    /// Mutually visible (see CLAUDE.md booking-notes rule).
    String? providerComment,

    /// **Free text written by the CLIENT** at cancellation
    /// ([BookingStatus.cancelled]). Optional — a null here is the common case,
    /// not a missing one.
    String? clientCancellationNote,

    /// PII-masked locality labels (resolved server-side by the same
    /// salon-vs-independent rule as `Booking`'s address fields).
    String? cityLabel,
    String? districtLabel,
    String? street,
    String? buildingNo,
    String? locationNote,

    /// When the visit was created (`createdAt`).
    DateTime? createdAt,
  }) = _Appointment;
}
