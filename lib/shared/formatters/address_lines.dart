// Phase 220 — split address-line composition, originally built for
// [MasterProfileScreen] and [PublicMasterProfileScreen].
//
// Phase 223 (a) — promoted from `features/master/presentation/widgets/
// master_address_lines.dart` to `shared/formatters/` (renamed
// `buildMasterLocalityLine`/`buildMasterStreetLine` -> `buildLocalityLine`/
// `buildStreetLine`, and re-typed from a `Master`-shaped parameter to plain
// `String?` fields) now that the salon feature's public profile needs the
// same two-line composition for a salon's address fields. A `shared/`
// formatter cannot depend on one feature's `domain/` entity — genericizing
// the parameters to the underlying strings (rather than the whole domain
// object) is what actually makes this reusable across features, not just a
// file-system move. Each call site now passes its own entity's fields
// (`buildLocalityLine(master.city)`, `buildLocalityLine(salon.city)`, ...).
//
// Before Phase 220, both master screens joined street + buildingNo + city
// into ONE string (each with its own copy-pasted `_buildLocationLine`), then
// rendered it in a single `Text` squeezed into the identity card's ~150px
// right-hand column. A `locationNote` up to 1000 chars long (backend
// `@Size(max=1000)`) made that budget hopeless for anything past a short
// street name.
//
// This file splits composition into two independent pieces so each gets its
// own line budget on screen:
//   - [buildLocalityLine] — the city, alone (Line 1 — city-first, matching
//     the convention in
//     `lib/features/discovery/presentation/widgets/result_address_block.dart`).
//   - [buildStreetLine]   — street + building number (Line 2).
//
// Pure Dart — no Flutter import — mirrors the existing `formatLocality`
// helper convention in `result_card_text.dart`.
//
// Phase 221 audit fix (mobile-security MEDIUM) — city/street/buildingNo are
// provider-authored free text with the same backend `@Size`-only (no
// character-class) validation as `locationNote`, so both lines are run
// through `sanitizeDisplayText` before being returned — see
// `shared/util/sanitize_display_text.dart` for what it strips and why.

import '../util/sanitize_display_text.dart';

/// Phase 224 audit fix — the ONE place every builder below decides whether a
/// field has visible content, and the ONE place it is sanitized.
///
/// SANITIZE-THEN-TEST ORDERING IS THE WHOLE POINT
/// ----------------------------------------------
/// Every builder used to test emptiness on the RAW field and sanitize only the
/// already-joined result. A field made entirely of characters
/// `sanitizeDisplayText` strips (a lone U+200B, say) is `isNotEmpty` before
/// sanitization and empty after it, so it passed the presence test, claimed a
/// segment, and then rendered as nothing — taking its `", "` separator with it
/// into the output. Verified defects that ordering produced:
///   - `buildCombinedAddressLine('<ZWSP>', 'вул. X', '22')` → `", вул. X, 22"`
///     (leading comma — the split path never produced this);
///   - `buildStreetLine('вул. X', '<ZWSP>')` → `"вул. X, "` (trailing comma);
///   - `buildLocalityLine('   ')` → `"   "` (an all-whitespace line that
///     occupies a row and shows nothing — the old local was even NAMED
///     `trimmed` while never calling `trim()`).
///
/// Sanitizing FIRST and trimming the result means a segment that reduces to
/// nothing is `null` here, so it is dropped by the `<String>[?a, ?b]` spreads
/// below and its separator disappears with it. All three builders share this
/// helper so the collapsed and split renderings of the SAME address can never
/// disagree about which segments exist — the invariant
/// `buildCombinedAddressLine != null ⟺ (buildLocalityLine != null ||
/// buildStreetLine != null)` that both master screens gate their whole address
/// block on.
///
/// Trimming also normalises `'  Київ  '` to `'Київ'`, which matters because
/// these strings are comma-joined: untrimmed padding would surface as
/// `"Київ , вул. X"`.
String? _visibleOrNull(String? value) {
  if (value == null) return null;
  final String sanitized = sanitizeDisplayText(value).trim();
  return sanitized.isEmpty ? null : sanitized;
}

/// The locality (city) line — Line 1 of a split identity/hero-card address.
///
/// Returns `null` when [city] is null, blank, whitespace-only, or reduces to
/// nothing once sanitized, so the caller can hide the line entirely rather
/// than rendering an empty (or all-space) string.
String? buildLocalityLine(String? city) => _visibleOrNull(city);

/// The street (+ optional building-number) line — Line 2 of a split
/// identity/hero-card address (e.g. "вул. Хрещатик, 22").
///
/// Returns `null` when [street] has no visible content — a building number
/// with no street is never rendered as its own line (there is nothing to
/// attach it to). When [buildingNo] has no visible content the building number
/// is simply omitted (no dangling comma) — see [_visibleOrNull] for why the
/// sanitize-then-test ordering is what makes that true.
String? buildStreetLine(String? street, [String? buildingNo]) {
  final String? road = _visibleOrNull(street);
  if (road == null) return null;

  final String? building = _visibleOrNull(buildingNo);
  return building == null ? road : '$road, $building';
}

/// The WHOLE address on one line, city-first — e.g. "Київ, вул. Хрещатик, 22".
///
/// This is the collapsed counterpart of [buildLocalityLine] +
/// [buildStreetLine]: the identity card renders it INSTEAD of the two-row
/// split whenever it actually fits on a single line at the real available
/// width (measured by `MasterAddressBlock`, which owns that decision — this
/// function is pure composition and knows nothing about layout).
///
/// The city-first order is the Phase 220 decision and is deliberate: it is the
/// same primary→secondary ordering the split path uses, and the same
/// convention as
/// `lib/features/discovery/presentation/widgets/result_address_block.dart`.
/// It is NOT the pre-220 street-first "вул. Хрещатик, 22, Київ" string — that
/// order must not come back.
///
/// Composition rules, identical to the two split builders so the collapsed and
/// split renderings can never disagree about what the address IS:
///   - a [city] with no visible content is omitted (no leading comma);
///   - a [street] with no visible content is omitted, and [buildingNo] goes
///     with it — a building number with no street to attach to is dropped
///     entirely, the same rule [buildStreetLine] already enforces;
///   - a [buildingNo] with no visible content is omitted (no trailing comma);
///   - nothing visible anywhere returns `null`, so the caller hides the whole
///     block.
///
/// "No visible content" means null, blank, whitespace-only, OR reducible to
/// nothing by `sanitizeDisplayText` — all four are decided by [_visibleOrNull]
/// BEFORE a segment claims its separator. See that helper for the leading-
/// comma defect the previous test-then-sanitize ordering produced here.
///
/// The `", "` separator is punctuation, not copy — no ARB entry, nothing here
/// is translated.
String? buildCombinedAddressLine(
  String? city,
  String? street, [
  String? buildingNo,
]) {
  final String? locality = _visibleOrNull(city);
  final String? road = _visibleOrNull(street);
  // A building number rides on the street or not at all.
  final String? building = road == null ? null : _visibleOrNull(buildingNo);

  final List<String> parts = <String>[?locality, ?road, ?building];
  if (parts.isEmpty) return null;
  return parts.join(', ');
}

/// Phase 21.14 — the FULL address, hierarchy-ordered: oblast (region) ->
/// city -> district -> street + building. An intentional extension of
/// [buildCombinedAddressLine] (which only ever had city/street/buildingNo to
/// work with) for callers that have resolved oblast/city/district DISPLAY
/// NAMES available — see `features/location/state/resolved_locality_provider
/// .dart`, which resolves those names from the `oblastId`/`cityId`/
/// `districtId` UUIDs a [Salon]/[Master] actually carries.
///
/// Every parameter is a plain display-name string, deliberately NOT the
/// legacy free-text `city`/`region` fields on those domain entities — both
/// are frozen (no longer written by the backend since Phase 10.6, see
/// `Salon.city`/`Salon.region`'s own doc) and must never be mixed in here;
/// pass the resolved [Oblast.name]/[City.name]/[CityDistrict.name] instead.
///
/// Same composition contract as [buildCombinedAddressLine] and
/// [buildStreetLine] — each shares [_visibleOrNull], so all four builders
/// agree on what counts as "no visible content" (null, blank, whitespace-
/// only, or reducible to nothing by `sanitizeDisplayText`) and a segment
/// with none is omitted with no dangling separator:
///   - [buildingNo] rides on [street] or not at all (same rule as the other
///     two builders — a building number with no street to attach to is
///     dropped entirely);
///   - every other segment is independently optional;
///   - nothing visible anywhere returns `null`, so the caller can fall back
///     to a legacy pre-taxonomy `address` string or hide the line entirely.
///
/// The `", "` separator is punctuation, not copy — no ARB entry, nothing
/// here is translated.
String? buildFullAddressLine({
  String? oblastName,
  String? cityName,
  String? districtName,
  String? street,
  String? buildingNo,
}) {
  final String? region = _visibleOrNull(oblastName);
  final String? locality = _visibleOrNull(cityName);
  final String? district = _visibleOrNull(districtName);
  final String? road = _visibleOrNull(street);
  // A building number rides on the street or not at all.
  final String? building = road == null ? null : _visibleOrNull(buildingNo);

  final List<String> parts = <String>[
    ?region,
    ?locality,
    ?district,
    ?road,
    ?building,
  ];
  if (parts.isEmpty) return null;
  return parts.join(', ');
}
