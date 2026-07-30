// Phase 220 — split address-line composition shared by [MasterProfileScreen]
// and [PublicMasterProfileScreen].
//
// Before this phase, both screens joined street + buildingNo + city into ONE
// string (each with its own copy-pasted `_buildLocationLine`), then rendered
// it in a single `Text` squeezed into the identity card's ~150px right-hand
// column. A `locationNote` up to 1000 chars long (backend `@Size(max=1000)`)
// made that budget hopeless for anything past a short street name.
//
// This file splits composition into two independent pieces so each gets its
// own line budget on screen:
//   - [buildMasterLocalityLine] — the city, alone (Line 1 — city-first,
//     matching the convention in
//     `lib/features/discovery/presentation/widgets/result_address_block.dart`).
//   - [buildMasterStreetLine]   — street + building number (Line 2).
//
// Pure Dart — no Flutter import — mirrors the existing `formatLocality`
// helper convention in `result_card_text.dart` (same feature-local
// presentation/widgets co-location as the text styles it pairs with).
//
// Phase 221 audit fix (mobile-security MEDIUM) — `city`, `street`, and
// `buildingNo` are provider-authored free text with the same backend
// `@Size`-only (no character-class) validation as `locationNote` (255 / 50
// chars respectively), so both lines are run through
// `sanitizeDisplayText` before being returned — see
// `master_text_sanitizer.dart` for what it strips and why.

import '../../domain/master.dart';
import 'master_text_sanitizer.dart';

/// The locality (city) line — Line 1 of the split identity-card address.
///
/// Returns `null` when [Master.city] is null or blank, so the caller can hide
/// the line entirely rather than rendering an empty string.
String? buildMasterLocalityLine(Master master) {
  final String? city = (master.city?.isNotEmpty ?? false) ? master.city : null;
  return city == null ? null : sanitizeDisplayText(city);
}

/// The street + building-number line — Line 2 of the split identity-card
/// address (e.g. "вул. Хрещатик, 22").
///
/// Returns `null` when [Master.street] is null or blank — a building number
/// with no street is never rendered as its own line (there is nothing to
/// attach it to). When [Master.buildingNo] is null or blank the building
/// number is simply omitted (no dangling comma).
String? buildMasterStreetLine(Master master) {
  final String? street = (master.street?.isNotEmpty ?? false)
      ? master.street
      : null;
  if (street == null) return null;

  final String? building = (master.buildingNo?.isNotEmpty ?? false)
      ? master.buildingNo
      : null;
  final String raw = building == null ? street : '$street, $building';
  return sanitizeDisplayText(raw);
}
