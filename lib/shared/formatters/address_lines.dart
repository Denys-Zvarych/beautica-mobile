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

/// The locality (city) line — Line 1 of a split identity/hero-card address.
///
/// Returns `null` when [city] is null or blank, so the caller can hide the
/// line entirely rather than rendering an empty string.
String? buildLocalityLine(String? city) {
  final String? trimmed = (city?.isNotEmpty ?? false) ? city : null;
  return trimmed == null ? null : sanitizeDisplayText(trimmed);
}

/// The street (+ optional building-number) line — Line 2 of a split
/// identity/hero-card address (e.g. "вул. Хрещатик, 22").
///
/// Returns `null` when [street] is null or blank — a building number with no
/// street is never rendered as its own line (there is nothing to attach it
/// to). When [buildingNo] is null or blank the building number is simply
/// omitted (no dangling comma).
String? buildStreetLine(String? street, [String? buildingNo]) {
  final String? trimmedStreet = (street?.isNotEmpty ?? false) ? street : null;
  if (trimmedStreet == null) return null;

  final String? building = (buildingNo?.isNotEmpty ?? false)
      ? buildingNo
      : null;
  final String raw = building == null
      ? trimmedStreet
      : '$trimmedStreet, $building';
  return sanitizeDisplayText(raw);
}
