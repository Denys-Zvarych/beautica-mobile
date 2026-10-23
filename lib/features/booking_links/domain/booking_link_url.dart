// Phase 413 — share URL builder (D5); phase 418 — UTM decoration removed.
//
// Copy and share send the bare canonical booking link exactly as the
// backend built it — `https://beautica.app/book/<slug>` (master) or
// `https://beautica.app/book/s/<slug>` (salon). Phase 418 (user decision
// 2026-10-23): the `utm_*` query made the link too long to post on social
// media, so nothing is appended any more.
//
// The canonical-shape rules (slug format + exact URL) live here, in the
// domain, so the repository's ingest filter (`isTrustedBookingLinkUrl`) and
// the share-time guard ([BookingLinkUrl.forSharing]) run ONE check, never
// two copies that can drift.
//
// Pure Dart: no Flutter imports in this file. The public web origin is
// passed in by the caller (`AppConfig.publicWebOrigin`), because the domain
// layer does not import `core/config`.

import 'booking_link.dart';

/// Backend booking-slug format (`BookingSlugService` + the DB CHECK).
final RegExp _bookingSlugPattern = RegExp(r'^[a-z0-9][a-z0-9-]*[a-z0-9]$');

/// Backend `BookingSlugService.MAX_SLUG_LENGTH`.
const int _maxBookingSlugLength = 60;

/// Whether [slug] has the backend booking-slug shape. Rejects anything that
/// could smuggle encoding, whitespace, control or bidi characters (`%2F`,
/// newline, U+202E, space, uppercase) into the shared URL.
bool isValidBookingSlug(String slug) =>
    slug.length <= _maxBookingSlugLength && _bookingSlugPattern.hasMatch(slug);

/// Whether [url] is exactly the canonical public booking page for [kind] +
/// [slug] on [origin]: `<origin>/book/<slug>` (master) or
/// `<origin>/book/s/<slug>` (salon), with [slug] in the backend format.
///
/// An exact string match, not a parse: any query (`?r=...`), fragment, port,
/// userinfo, dot-segment, scheme or casing difference fails it.
bool isCanonicalBookingLinkUrl(
  String url, {
  required String origin,
  required BookingLinkKind kind,
  required String slug,
}) {
  if (!isValidBookingSlug(slug)) return false;
  final String expected = switch (kind) {
    BookingLinkKind.master => '$origin/book/$slug',
    BookingLinkKind.salon => '$origin/book/s/$slug',
  };
  return url == expected;
}

/// Builds the outgoing share URL for a booking link.
abstract final class BookingLinkUrl {
  /// The exact [url] to put on the clipboard / in the share sheet.
  ///
  /// [url] must be the canonical booking link on [origin] — the same exact
  /// check the repository applied on ingest ([isCanonicalBookingLinkUrl]);
  /// it is then returned byte-identical. Anything else (foreign host,
  /// `http`, `javascript:`, a query, fragment, port, userinfo, bad slug)
  /// throws [ArgumentError] — it is never passed through, because an
  /// unvalidated string must not reach the clipboard / share sheet. A throw
  /// (not an `assert`) so the guarantee also holds in release builds, where
  /// asserts are compiled out.
  static String forSharing(String url, {required String origin}) {
    final String salonPrefix = '$origin/book/s/';
    final String masterPrefix = '$origin/book/';
    final (BookingLinkKind kind, String slug)? parts =
        url.startsWith(salonPrefix)
        ? (BookingLinkKind.salon, url.substring(salonPrefix.length))
        : url.startsWith(masterPrefix)
        ? (BookingLinkKind.master, url.substring(masterPrefix.length))
        : null;
    if (parts == null ||
        !isCanonicalBookingLinkUrl(
          url,
          origin: origin,
          kind: parts.$1,
          slug: parts.$2,
        )) {
      throw ArgumentError.value(url, 'url', 'not a canonical booking link');
    }
    return url;
  }
}
