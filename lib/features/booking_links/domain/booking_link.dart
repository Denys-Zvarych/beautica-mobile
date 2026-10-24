// Phase 413 — BOOKING LINKS domain model.
//
// The caller's shareable public booking-page links, hydrated off
// `GET /api/v1/booking-links/mine` (backend 375 + 376) by
// `HttpBookingLinksRepository`. One MASTER link for a master (independent or
// salon owner in master mode), one SALON link per salon the caller can share.
//
// [BookingLinks.shareEnabled] is the backend kill-switch: while it is `false`
// the app hides the entry point entirely (D4) — see [BookingLinks.isVisible].
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'booking_link.freezed.dart';

/// Which public booking page a link opens.
enum BookingLinkKind {
  /// `https://beautica.app/book/{slug}` — one master's page.
  master,

  /// `https://beautica.app/book/s/{slug}` — a salon's page.
  salon,
}

/// Phase 415 — whether a link works (backend 378 `status`).
enum BookingLinkStatus {
  /// The link works: [BookingLink.slug] and [BookingLink.url] are set.
  active,

  /// Switched off through the API (the app itself never revokes — 415 D1):
  /// no slug, no url; the card offers «Створити нове посилання» only.
  revoked,
}

/// One shareable public booking-page link.
@freezed
abstract class BookingLink with _$BookingLink {
  const BookingLink._();

  const factory BookingLink({
    required BookingLinkKind kind,

    /// `null` only when [status] is [BookingLinkStatus.revoked] (415 D5).
    required String? slug,

    /// Absolute https URL, exactly as the backend built it (no UTM); `null`
    /// only when [status] is [BookingLinkStatus.revoked].
    required String? url,
    required String displayName,

    /// The salon this link belongs to; `null` for a [BookingLinkKind.master]
    /// link.
    String? salonId,

    /// Whether a client can actually book through the page right now
    /// (services + schedule present). A non-bookable link is still shareable.
    required bool bookable,

    /// Phase 415 — [BookingLinkStatus.active] unless the API says revoked.
    @Default(BookingLinkStatus.active) BookingLinkStatus status,
  }) = _BookingLink;

  bool get isRevoked => status == BookingLinkStatus.revoked;

  /// Stable per-card identity for widget keys: the slug of an active link;
  /// `revoked-master` / `revoked-salon-<salonId>` for a revoked one (the
  /// mapper keeps a revoked SALON link only with a UUID salon id, so two
  /// revoked cards never collide).
  String get keyId =>
      slug ??
      switch (kind) {
        BookingLinkKind.master => 'revoked-master',
        BookingLinkKind.salon => 'revoked-salon-${salonId ?? ''}',
      };
}

/// Phase 415 — what a regenerate call came back with. Every outcome the UI
/// treats specially is a value here (415 D7); anything else is thrown as a
/// `Failure`.
@freezed
sealed class BookingLinkMutationOutcome with _$BookingLinkMutationOutcome {
  /// The new link (replaces the card it was made from).
  const factory BookingLinkMutationOutcome.done(BookingLink link) =
      BookingLinkMutationDone;

  /// HTTP 409 — `currentSlug` was stale: the link changed elsewhere.
  const factory BookingLinkMutationOutcome.stale() = BookingLinkMutationStale;

  /// HTTP 404 — sharing switched off server-side (or the owner is gone).
  const factory BookingLinkMutationOutcome.unavailable() =
      BookingLinkMutationUnavailable;

  /// HTTP 429 — the per-user regenerate/revoke budget is spent.
  const factory BookingLinkMutationOutcome.rateLimited() =
      BookingLinkMutationRateLimited;
}

/// The caller's booking links plus the backend share kill-switch.
@freezed
abstract class BookingLinks with _$BookingLinks {
  const BookingLinks._();

  const factory BookingLinks({
    required bool shareEnabled,
    required List<BookingLink> links,
  }) = _BookingLinks;

  /// The "nothing to show" value: kill-switch off, no links. Used when there
  /// is no session to ask the backend for.
  static const BookingLinks hidden = BookingLinks(
    shareEnabled: false,
    links: <BookingLink>[],
  );

  /// Whether the share entry point may be shown at all (D4).
  bool get isVisible => shareEnabled && links.isNotEmpty;
}
