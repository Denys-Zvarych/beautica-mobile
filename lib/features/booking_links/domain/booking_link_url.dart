// Phase 413 — share URL builder (D5).
//
// Appends the website's UTM convention to a backend-built booking link:
//   utm_source   = copy | share   (v1: the native share sheet does not report
//                                  the chosen target reliably, so only the
//                                  ACTION is recorded)
//   utm_medium   = social
//   utm_campaign = master_link | salon_link
//
// The input is the exact canonical booking URL (no query, no fragment — see
// the [BookingLinkUrl.withUtm] precondition), so
// `Uri.replace(queryParameters:)` only adds the `utm_*` keys; encoding is
// done by `Uri`.
//
// Pure Dart: no Flutter imports in this file.

import 'booking_link.dart';

/// HOW the user is sending the link — the `utm_source` value.
enum BookingLinkShareSource {
  /// Copied to the clipboard.
  copy('copy'),

  /// Sent through the native share sheet.
  share('share');

  const BookingLinkShareSource(this.utmValue);

  /// The wire value written into `utm_source`.
  final String utmValue;
}

/// Builds the outgoing share URL for a booking link.
abstract final class BookingLinkUrl {
  /// `utm_medium` for every booking-link share.
  static const String utmMedium = 'social';

  /// `utm_campaign` for [kind].
  static String campaignFor(BookingLinkKind kind) => switch (kind) {
    BookingLinkKind.master => 'master_link',
    BookingLinkKind.salon => 'salon_link',
  };

  /// [url] with the UTM parameters for [kind] and [source] applied.
  ///
  /// Precondition: [url] is a [BookingLink.url] that already passed the
  /// repository's exact canonical-URL filter (`isTrustedBookingLinkUrl`), so
  /// it always parses and carries no query or fragment of its own. A [url]
  /// that does not parse throws [ArgumentError] — it is never passed through
  /// unchanged, because an unvalidated string must
  /// not reach the clipboard / share sheet. A throw (not an `assert`) so the
  /// guarantee also holds in release builds, where asserts are compiled out.
  static String withUtm(
    String url, {
    required BookingLinkKind kind,
    required BookingLinkShareSource source,
  }) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      throw ArgumentError.value(url, 'url', 'not a parsable booking link');
    }
    final Map<String, List<String>> query = <String, List<String>>{
      ...uri.queryParametersAll,
      'utm_source': <String>[source.utmValue],
      'utm_medium': const <String>[utmMedium],
      'utm_campaign': <String>[campaignFor(kind)],
    };
    return uri.replace(queryParameters: query).toString();
  }
}
