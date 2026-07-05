// Phase 14.0 — Client booking data foundation: [Booking] domain model.
//
// Mirrors the ENRICHED `BookingDetailResponse` DTO (backend 19.3), not the
// lean master-only `BookingResponse` — see the "Decisions locked" note in
// `docs/mobile-phases/phase-094-14.0-booking-data-foundation.md` (Option A /
// decision 2). This gives the detail / my-bookings / feedback screens every
// field they need without a second round-trip once the client already has a
// `Booking`.
//
// [masterType] is carried as the raw wire string (`"INDEPENDENT_MASTER"` /
// `"SALON_MASTER"` / ...) rather than the shared `MasterType` domain enum from
// `features/master/domain/master.dart` — this keeps the booking domain layer
// free of a cross-feature domain dependency for a field that is purely
// informational here (it only decides whether [salonName] is rendered).
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'booking_status.dart';

part 'booking.freezed.dart';

/// A client-facing booking, enriched with master/service/address display
/// fields so the detail, my-bookings, and review screens never need a
/// secondary fetch.
@freezed
abstract class Booking with _$Booking {
  const factory Booking({
    required String id,
    required String masterId,
    required String masterFirstName,
    required String masterLastName,
    String? masterAvatarUrl,

    /// Raw backend wire value: `"INDEPENDENT_MASTER"` | `"SALON_MASTER"` |
    /// (in principle any `MasterType`-family value the DTO carries).
    required String masterType,

    /// Null for an `INDEPENDENT_MASTER` booking; set for a salon-employed
    /// master's booking.
    String? salonName,
    required String serviceId,
    required String serviceName,
    String? categoryName,
    String? cityLabel,
    String? districtLabel,
    String? street,
    String? buildingNo,
    required int durationMinutes,
    required double price,
    required DateTime startAt,
    required DateTime endAt,
    required BookingStatus status,

    /// `true` only when [status] is [BookingStatus.completed] AND the client
    /// has not already left a review for this booking. Server-computed —
    /// the client must not re-derive this from [status] alone.
    required bool canReview,
    String? clientComment,
    String? providerComment,
  }) = _Booking;
}
