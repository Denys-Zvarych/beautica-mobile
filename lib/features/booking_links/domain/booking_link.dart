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

/// One shareable public booking-page link.
@freezed
abstract class BookingLink with _$BookingLink {
  const factory BookingLink({
    required BookingLinkKind kind,
    required String slug,

    /// Absolute https URL, exactly as the backend built it (no UTM).
    required String url,
    required String displayName,

    /// The salon this link belongs to; `null` for a [BookingLinkKind.master]
    /// link.
    String? salonId,

    /// Whether a client can actually book through the page right now
    /// (services + schedule present). A non-bookable link is still shareable.
    required bool bookable,
  }) = _BookingLink;
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
