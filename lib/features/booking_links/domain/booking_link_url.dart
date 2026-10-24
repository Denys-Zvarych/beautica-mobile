// Phase 413 — share URL builder (D5); phase 418 — UTM decoration removed;
// phase 419 — one-character channel flag.
//
// Copy and share send the canonical booking link exactly as the backend
// built it — `https://beautica.app/book/<slug>` (master) or
// `https://beautica.app/book/s/<slug>` (salon) — plus ONE channel flag:
// `?s=c` (copy) or `?s=s` (share sheet). Phase 418 (user decision
// 2026-10-23) dropped the ~60-char `utm_*` query as too long for social
// media; phase 419 (user decision 2026-10-23, research
// `docs/website-phases/research-short-booking-link-attribution.md`) keeps
// the only real data point — copy vs share — in 4 characters. The flag is a
// channel label shared by every link: never a per-sender or per-click id.
// Kind (master/salon) is already in the path; the website derives the rest.
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

/// How a booking link leaves the app — encoded as the `s` query flag.
enum BookingLinkChannel {
  /// «Копіювати» — the link goes to the clipboard (`?s=c`).
  copy('c'),

  /// «Поділитися» — the link goes to the system share sheet (`?s=s`).
  share('s');

  const BookingLinkChannel(this.flag);

  /// The single-character `s` value the website allow-lists ({c, s}).
  final String flag;
}

/// Builds the outgoing share URL for a booking link.
abstract final class BookingLinkUrl {
  /// The exact string to put on the clipboard / in the share sheet:
  /// [url] + `?s=<channel.flag>` — e.g. `https://beautica.app/book/anna-k?s=c`.
  ///
  /// [url] must be the BARE canonical booking link on [origin] — the same
  /// exact check the repository applied on ingest
  /// ([isCanonicalBookingLinkUrl], which accepts no query at all). Only
  /// after that check passes is exactly one flag appended, so the output is
  /// always canonical + `?s=c` or canonical + `?s=s`, nothing else. Anything
  /// else as input (foreign host, `http`, `javascript:`, a query — including
  /// an `?s=` already present — fragment, port, userinfo, bad slug) throws
  /// [ArgumentError] — it is never passed through, because an unvalidated
  /// string must not reach the clipboard / share sheet. A throw (not an
  /// `assert`) so the guarantee also holds in release builds, where asserts
  /// are compiled out.
  static String forSharing(
    String url, {
    required String origin,
    required BookingLinkChannel channel,
  }) {
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
    return '$url?s=${channel.flag}';
  }
}
