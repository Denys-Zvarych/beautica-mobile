// Shared "street, buildingNo, city" address-line formatter.
//
// Extracted from the byte-identical private `_masterAddressLine` that lived
// in `booking_summary_cards.dart` (itself mirrored from
// `PublicMasterProfileScreen._buildLocationLine`) — promoted to a shared
// formatter now that a THIRD caller needs the identical join: the salon
// booking confirm/success screens compose the salon's own street/buildingNo/
// city the exact same way `BookingSummaryCards.fromMaster` already did for a
// `Master`. Deliberately generic over raw string parts (not typed to
// `Master` or `Salon`) so either domain entity's fields can be passed
// straight through with no adapter.
//
// NOT a replacement for `PublicSalonProfileScreen._buildLocationLine`, which
// solves a different, more elaborate problem (falling back to the legacy
// free-text `city`/`address` pair when the taxonomy fields are unset) — this
// formatter only joins the three parts it is given, verbatim.
//
// Pure Dart — no Flutter imports.

/// Composes a "street, buildingNo, city" address line from raw parts, or
/// `null` when neither [street] nor [city] is set — the caller then falls
/// back to its own "address unknown" placeholder string.
String? formatStreetCityLine({
  required String? street,
  required String? buildingNo,
  required String? city,
}) {
  final String? s = (street?.isNotEmpty ?? false) ? street : null;
  final String? b = (buildingNo?.isNotEmpty ?? false) ? buildingNo : null;
  final String? c = (city?.isNotEmpty ?? false) ? city : null;

  if (s == null && c == null) return null;

  final StringBuffer buf = StringBuffer();
  if (s != null) {
    buf.write(s);
    if (b != null) {
      buf
        ..write(', ')
        ..write(b);
    }
    if (c != null) {
      buf
        ..write(', ')
        ..write(c);
    }
  } else {
    buf.write(c);
  }
  return buf.toString();
}
