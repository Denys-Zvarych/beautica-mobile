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

    // ── The COUNTERPARTY as the PROVIDER sees it (Phase 7.2) ──────────────
    //
    // Added for the provider-view «Деталі запису». A client viewer never reads
    // these (they are the counterparty to themselves); a master viewer renders
    // them in place of the master strip.
    //
    /// The registered client's account id. **Null on a guest/LINK booking** —
    /// `client_id IS NULL` is the entire LINK flow, not an edge case (backend
    /// V89 `chk_bookings_guest_fields`). Present only so a caller can tell a
    /// registered client from a guest; never render it.
    String? clientId,

    /// The client's first name.
    ///
    /// ## The guest fallback already happened — SERVER-side
    ///
    /// On a guest/LINK booking the backend's `BookingDetailResponse` fills
    /// this from the booking's OTP-verified `guestName`, so the wire carries a
    /// usable name either way and the mobile side needs no `guestName`
    /// fallback of its own. (The Phase 7.2 phase doc asks for a client-side
    /// `guestName`/`guestSurname` fallback — those fields are not on this DTO
    /// at all, precisely because the server already resolved them. Do not add
    /// one; there is nothing to fall back TO.)
    ///
    /// Still nullable: an old row can carry neither. Render
    /// [BookingDisplayX.clientName], which degrades to a localized «Гість»
    /// rather than an empty strip.
    String? clientFirstName,

    /// The client's surname. Independently nullable — the backend's
    /// `guestSurname` column is optional, so a guest booking legitimately
    /// carries a first name and no surname.
    String? clientLastName,
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

    /// The client's free-text note written at booking time
    /// (`CreateBookingRequest.clientComment`). Visible to the provider; the
    /// client sees their own words echoed back on «Деталі запису» under
    /// «Ваші побажання». Distinct from [clientCancellationNote] — this is
    /// NOT the cancellation reason.
    String? clientComment,

    /// **Free text written by the PROVIDER** — never the `CancellationReason`
    /// enum. Set on exactly two statuses and required by the backend on
    /// both, so treat it as effectively always present there:
    ///   * [BookingStatus.declined]     — why the provider cancelled.
    ///   * [BookingStatus.notCompleted] — the provider's account of the
    ///     no-show.
    /// Null on every other status. See the Phase 14.3 README: if a value
    /// here ever reads `SCREAMING_SNAKE_CASE`, the wrong field was bound.
    String? providerComment,

    /// **Free text written by the CLIENT** at the moment they cancelled
    /// ([BookingStatus.cancelled]). Optional — a client may cancel without
    /// saying anything, so a null value here is the common case, not a
    /// missing one. The provider reads it; the client sees it echoed back
    /// under «Ваша причина».
    String? clientCancellationNote,

    /// The master's own free-text professional title/headline (e.g.
    /// «Перукар-стиліст»). Independently nullable — most masters never set
    /// one, and an absent value renders no fallback text (see `MasterStrip`'s
    /// generic-role fallback for where a placeholder DOES belong).
    String? masterProfessionalTitle,

    /// The provider's free-text arrival hint («3-й поверх, код на дверях
    /// 1234»), resolved server-side by the same salon-vs-independent rule as
    /// [street]/[buildingNo]. Never part of the composed address — see
    /// `composeAddressLine`'s doc. Independently nullable; most providers
    /// never set one.
    String? locationNote,
  }) = _Booking;
}
