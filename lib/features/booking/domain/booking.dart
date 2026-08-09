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

    /// The salon this booking was made AT, as snapshotted on the booking row
    /// (`bookings.salon_id`).
    ///
    /// Null for an `INDEPENDENT_MASTER` booking. Exists to key salon-side cache
    /// invalidation after a review (`invalidateSalonReviewSurfaces` in
    /// `features/review/presentation/review_surface_invalidation.dart`) — and
    /// for nothing else. It is the id whose `avgRating` / `reviewCount` the
    /// backend just moved: `ReviewService#createReview` stamps the review with
    /// the BOOKING's salon, and `ReviewEventListener` recalculates THAT salon.
    ///
    /// ⚠️ NOT interchangeable with [salonName], even though backend phase 242
    /// made both resolve from this same booking snapshot (before 242 [salonName]
    /// came from the master's LIVE salon and the two could disagree after a
    /// rotation). They stay separate fields carrying separate meanings: one is a
    /// cache key, the other is display text, and an older backend still on the
    /// pre-242 contract can send one without the other. `atSalon` stays
    /// `salonName != null` — do not re-express it on this field, and do not
    /// derive either field from the other at the mapping boundary.
    String? salonId,

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

    /// The client's profile photo — an already-PUBLIC Cloudflare R2 object
    /// URL, exactly like [masterAvatarUrl] (never a signed URL, never a raw
    /// storage key), so it needs no auth header and can be handed straight to
    /// an `Image.network`.
    ///
    /// ## Null means "render the fallback", and NOTHING else
    ///
    /// The backend sends null in exactly two cases and they are deliberately
    /// indistinguishable on the wire: a guest/LINK booking (no registered
    /// account at all, so no photo AND no fallback — unlike
    /// [clientFirstName]/[clientLastName], which the server does resolve from
    /// the OTP-verified guest name), or a registered client who never uploaded
    /// one. **Do not branch on which.** Both mean strictly "this booking has
    /// no client photo".
    ///
    /// Null never encodes WHO IS ASKING. The value is a function of the
    /// booking alone, identical on `GET /bookings/{id}` and on every row of
    /// `GET /bookings/me`, for the provider and for the client reading their
    /// own booking — so it is safe to cache by booking id across both.
    String? clientAvatarUrl,
    required String serviceId,
    required String serviceName,
    String? categoryName,
    String? cityLabel,
    String? districtLabel,
    String? street,
    String? buildingNo,
    required int durationMinutes,

    /// The price agreed AT BOOKING TIME (`priceAtBooking` on the wire), never
    /// re-read from the live catalogue. When [priceMax] is non-null this is the
    /// band's FLOOR; otherwise it is the whole price.
    required double price,

    /// The band's CEILING, agreed at booking time (`priceMaxAtBooking`).
    ///
    /// **Null means SINGLE PRICE — render [price] alone.** It is not a missing
    /// value and not an error state: the backend populates it only when the
    /// master genuinely left this service as a `RANGE` (no `priceOverride`) at
    /// the moment the booking was made, and freezes it there.
    ///
    /// The client must NEVER re-derive a band from `priceType`/`priceOverride`
    /// or the service's current catalogue state — those describe the service
    /// today, not what was agreed then. Render via
    /// `BookingDisplayX.priceLabel` (→ `formatBookingPrice`), which is the one
    /// place the floor/band choice is made.
    double? priceMax,
    required DateTime startAt,
    required DateTime endAt,
    required BookingStatus status,

    /// `true` when the client has not already left a review for this
    /// booking AND either [status] is [BookingStatus.completed], OR
    /// [status] is [BookingStatus.confirmed] with [endAt] already elapsed
    /// (an appointment the provider never marked COMPLETED — there is no
    /// auto-complete job, so it stays CONFIRMED forever otherwise).
    /// Server-computed — the client must not re-derive this from [status]
    /// alone.
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

    /// The master's public average rating (1.0–5.0), as served by
    /// `GET /bookings/{id}` and `GET /bookings/me` (Phase 240).
    ///
    /// **`null` means "no reviews yet" — NEVER render it as `0.0`.** The
    /// backend stores `0.00` for an unreviewed master (`masters.avg_rating` is
    /// `NOT NULL DEFAULT 0.00`) and deliberately normalises that storage
    /// artefact to `null` on the wire, precisely so a brand-new master is not
    /// shown a damning zero stars. Coalescing this to `0` client-side would
    /// re-introduce exactly the bug the backend just removed.
    ///
    /// This is the same denormalised column `GET /masters/{id}` serves, and the
    /// backend evicts the master-detail cache when a review lands, so the value
    /// here agrees exactly with the profile screen rather than eventually.
    ///
    /// Render the no-rating treatment when null — see [masterReviewCount] for
    /// the count that accompanies it, and `MasterStrip` for the established
    /// presentation.
    double? masterAvgRating,

    /// How many reviews [masterAvgRating] is computed from.
    ///
    /// `0` is a TRUE fact about an unreviewed master (unlike a `0.0` average),
    /// so it is meaningful and safe to render. Kept nullable to distinguish
    /// "unknown" (field absent — e.g. a pre-Phase-240 backend) from a genuine
    /// zero; treat `null` as unknown, not as zero.
    int? masterReviewCount,

    /// The provider's free-text arrival hint («3-й поверх, код на дверях
    /// 1234»), resolved server-side by the same salon-vs-independent rule as
    /// [street]/[buildingNo]. Never part of the composed address — see
    /// `composeAddressLine`'s doc. Independently nullable; most providers
    /// never set one.
    String? locationNote,

    /// The id of the multi-service VISIT this booking belongs to, when it was
    /// placed as one line of a multi-service single-visit appointment
    /// (`appointmentId` on the wire, backend `feat/multi-service-appointments`).
    ///
    /// **Null means a standalone single-service booking** — the legacy shape,
    /// still the common case. MO-5 groups the «Мої записи» list by this id so
    /// the N per-service bookings of one visit render as a single card; a null
    /// value is its own group of one. Additive and purely informational here —
    /// no existing behaviour keys off it.
    String? appointmentId,

    /// `true` only when the CURRENT authenticated viewer is the provider AND
    /// this booking's client may still be reviewed by them — server-computed
    /// (mirrors [canReview], but from the PROVIDER's side): COMPLETED,
    /// non-guest client, no `ClientReview` yet for this booking. Defaults to
    /// `false`, matching the backend's own hardcoded-`false` rows on
    /// `GET /bookings/me` (both the client and provider listing paths) — only
    /// `GET /bookings/{id}` ever sends a real value here. Gates the master
    /// footer's «Залишити відгук про клієнта» CTA; the write endpoint
    /// (`POST /client-reviews`) re-checks the same conditions server-side
    /// regardless of this value, so a stale/duplicate submit still surfaces
    /// as a 409 rather than being trusted client-side.
    @Default(false) bool providerCanReviewClient,

    /// `true` only when [status] is still [BookingStatus.confirmed] AND
    /// [endAt] has already elapsed — server-derived, read-time-only (backend
    /// Phase 29.1/29.2). Flags the bookings a provider still needs to close
    /// via complete/not-complete/decline; no scheduled job ever transitions
    /// these automatically. Defaulted to `false` at the mapping boundary
    /// ([BookingMapper.fromDto]) so an older backend that omits this field
    /// entirely (pre-29.2) cannot crash the mapper — nothing reads this field
    /// yet (phases 227/229 do).
    @Default(false) bool awaitingClosure,
  }) = _Booking;
}
