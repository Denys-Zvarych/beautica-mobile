// Phase 14.3 — the four-field ("cityLabel", "districtLabel", "street",
// "buildingNo") address composer for the My Bookings card / booking detail
// screen.
//
// NOT a replacement for `street_city_line.dart`'s `formatStreetCityLine` —
// that formatter is district-blind (fed only street/buildingNo/city) and
// stays the booking-FLOW screens' composer (they never carry a district).
// [Booking] is enriched with a FOURTH field, `districtLabel`, so this file
// owns the two extra rules a district-aware join needs — see
// `composeAddressLine`'s doc.
//
// Ported from `docs/signup-designs/MyBookings/lib/util/uk_format.dart`
// (`composeAddressLine` / `composeAddressBlock`) verbatim.
//
// Pure Dart — no Flutter imports.

/// Composes the four independently-nullable location fields the backend
/// returns (`cityLabel`, `districtLabel`, `street`, `buildingNo`) into ONE
/// readable line a human reads at a glance before travelling — or `null`
/// when nothing is worth saying, so the caller can omit the row entirely.
///
/// Ukrainian addresses are written fine → coarse: «вул. Хрещатик, 22, Київ».
///
/// ## Two rules that are design decisions, not plumbing
///
/// 1. **The district is dropped as soon as there is a street.** A district
///    answers *roughly where in the city* — a question that stops existing
///    the moment you have the actual street. It earns its place only when it
///    is the ONLY refinement over the bare city name («Сихівський, Львів»).
///    [composeAddressBlock] (the DETAIL screen) is free to show the full
///    chain — see that function's doc.
/// 2. **A building number without a street is discarded.** The four fields
///    are independently nullable, so a half-filled provider profile can hand
///    us `buildingNo: '7'` with `street: null`. «7, Львів» is not an
///    address — it is a bug wearing an address's clothes. The number only
///    survives when it has a street to attach to.
///
/// Every part is trimmed and blank-checked, so a whitespace-only string
/// coming back from the API can never produce an orphan comma.
String? composeAddressLine({
  String? cityLabel,
  String? districtLabel,
  String? street,
  String? buildingNo,
}) {
  final String? city = _clean(cityLabel);
  final String? district = _clean(districtLabel);
  final String? st = _clean(street);
  final String? no = _clean(buildingNo);

  final List<String> parts = <String>[];

  if (st != null) {
    // Rule 2: the number attaches to the street or it does not appear at all.
    parts.add(no != null ? '$st, $no' : st);
  } else if (district != null) {
    // Rule 1: district only when there is no street to outrank it.
    parts.add(district);
  }

  if (city != null) parts.add(city);

  return parts.isEmpty ? null : parts.join(', ');
}

/// The SAME four fields composed for «Деталі запису», which — unlike the
/// scanned list card — has room for the **full chain** and a person standing
/// in the street who needs it.
///
/// Returns a `(value, detail)` pair for one [LabelledRow]-shaped «Адреса»
/// block: the precise line on top, the coarser locators beneath it. Both may
/// be null.
///
/// This is the one place [composeAddressLine]'s rule 1 (district loses to
/// street) is deliberately RELAXED: on a scanned card row the district is
/// noise the street already answered; standing on Городоцька looking for
/// number 15, «Галицький район, Львів» underneath is orientation, not noise.
///
/// Rule 2 (a lone building number is not an address) is NOT relaxed, here or
/// anywhere.
///
///   * street + no → `("вул. Городоцька, 15", "Галицький район, Львів")`
///   * district only → `("Сихівський район", "Львів")`
///   * city only → `("Львів", null)`
///   * nothing → `(null, null)` — the caller omits the whole row.
(String?, String?) composeAddressBlock({
  String? cityLabel,
  String? districtLabel,
  String? street,
  String? buildingNo,
}) {
  final String? city = _clean(cityLabel);
  final String? district = _clean(districtLabel);
  final String? st = _clean(street);
  final String? no = _clean(buildingNo);

  final String? districtLine = district == null ? null : '$district район';

  if (st != null) {
    final String value = no != null ? '$st, $no' : st;
    final List<String> coarse = <String>[?districtLine, ?city];
    return (value, coarse.isEmpty ? null : coarse.join(', '));
  }
  if (districtLine != null) return (districtLine, city);
  if (city != null) return (city, null);
  return (null, null);
}

/// Trims and treats blank/whitespace-only as absent — the single guard that
/// makes an orphan comma impossible upstream of [composeAddressLine].
String? _clean(String? v) {
  if (v == null) return null;
  final String t = v.trim();
  return t.isEmpty ? null : t;
}
