// Phase 334 — [ClientAuthoredReview]: the review THIS booking's CLIENT left
// about the master, as the PROVIDER reads it on «Деталі запису».
//
// Mirrors the generated `ClientAuthoredReviewResponse` DTO (backend #127),
// which carries exactly two fields and nothing else: a 1–5 [rating] and an
// optional [comment]. There is deliberately no review id, no author name and
// no timestamp on the wire — the booking already identifies the client and the
// visit, so re-sending either would be redundant. The render site
// (`booking_detail_screen.dart`) therefore seeds the shared `ReviewCard`'s id
// from the BOOKING id and its display name from the booking's own client name.
//
// ## NOT the provider's review of the client
//
// This is the client→master direction. The master→client direction is a
// separate entity entirely, written through `POST /client-reviews` and gated
// by [Booking.providerCanReviewClient]; the two never share a payload and must
// not be conflated. A booking can carry both, one, or neither.
//
// ## Served ONLY by `GET /bookings/{id}`
//
// Every listing surface — the provider AND client branches of
// `GET /bookings/me`, `GET /bookings/salon/{salonId}`, and the create /
// reschedule mutation responses — sends this field `null` UNCONDITIONALLY,
// because a booking CARD renders no review body and paying a per-page review
// fetch for a field nothing draws is not worth the statement (the generated
// DTO's own doc comment says so verbatim). A `null` on a list row therefore
// does NOT mean "this booking has no review" — it means "this surface does not
// answer that question". Do not read [Booking.reviewByClient] on a list, and
// do not add a per-row empty state keyed off it; re-read the booking through
// `GET /bookings/{id}` to learn the truth. This is the same explicitly
// surface-scoped contract [Booking.providerCanReviewClient] already documents.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'client_authored_review.freezed.dart';

/// One client-authored review of the master, attached to the booking it was
/// written about.
@freezed
abstract class ClientAuthoredReview with _$ClientAuthoredReview {
  const factory ClientAuthoredReview({
    /// The client's star rating for this booking, 1–5.
    required int rating,

    /// The client's review text, verbatim and unabridged, or `null` when they
    /// rated without writing anything.
    ///
    /// Already world-readable through the `permitAll`
    /// `GET /masters/{id}/reviews` listing (backend phase 317 decision D2), so
    /// it is never truncated or masked here — withholding from the provider
    /// text that any anonymous visitor can read would be theatre.
    String? comment,
  }) = _ClientAuthoredReview;
}
