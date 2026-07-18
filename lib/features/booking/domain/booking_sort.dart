// Phase 7.1 — the sort axis for the independent master's «Мої записи» list.
//
// The four options the approved design's sort sheet offers
// (`docs/signup-designs/SalonManagementDesign/lib/widgets/bookings_toolbar.dart`),
// mapped to the backend's `sort=<property>,<direction>` param.
//
// ## The whitelist is NOT advisory
//
// Backend Phase 26.6 replaced Spring's permissive `Pageable` sort binding with
// an explicit property whitelist containing exactly `startsAt` and
// `priceAtBooking`. Anything else — including the `createdAt` this enum
// briefly carried — now returns **HTTP 400**, not a silently-ignored param.
// So: never add a member whose property is outside that pair without the
// backend whitelist widening first.
//
// ## No labels here
//
// The design's Ukrainian labels («Спочатку нові» …) deliberately do NOT live
// on this enum. A user-facing literal in `lib/` trips the `no_raw_ui_strings`
// CI gate, and a `domain/` type must stay free of presentation concerns. The
// labels live in `app_uk.arb` under the `bookingSort*` keys; the sort sheet
// (Phase 7.6) resolves them through `AppLocalizations`.
//
// Pure Dart: no Flutter imports.

/// A server-side sort option for `GET /bookings/me`.
///
/// [wireValue] is sent verbatim as the `sort` query param. The client never
/// re-sorts the returned page — the server owns the order (see
/// `MasterBookingsNotifier`).
enum BookingSort {
  /// Latest appointments first — the list's default.
  newest('startsAt,desc'),

  /// Earliest appointments first.
  oldest('startsAt,asc'),

  /// Highest price first.
  priceDesc('priceAtBooking,desc'),

  /// Lowest price first.
  priceAsc('priceAtBooking,asc');

  const BookingSort(this.wireValue);

  /// The exact `sort=` query value, `<property>,<direction>`. Both properties
  /// used here are on the backend's Phase 26.6 whitelist — see the file
  /// header before adding a member.
  final String wireValue;
}
