// Phase 2.19 — Locality validator (per-role most-specific-node enforcement).
//
// Pure function — no Flutter widget dependencies beyond AppLocalizations.
// Mirrors the backend Phase 10.6 locality matrix:
//
//   CLIENT             → locality is fully optional. Even a partial selection
//                        is tolerated (the "Пропустити" CTA nulls everything
//                        out, the "Зберегти" CTA persists whatever is set).
//                        This validator is therefore never blocking for CLIENT.
//
//   INDEPENDENT_MASTER → cityId (the settlement) is required. If the chosen
//   / SALON_OWNER        settlement has districts (cityHasDistricts == true)
//                        then a districtId is also required; if it is a leaf
//                        (no urban districts) the districtId must stay null.
//
// Phase 346 — `oblastCode` is GONE along with the «Область» step. The oblast was
// never submitted; it was a cascade parent, and a flat settlement autocomplete
// has none. [LocalityLevel.oblast] went with it, so a caller can no longer route
// a message to a row that does not exist.
//
// The "has districts" signal is carried in [cityHasDistricts] — the SAME
// `districtsOf` read the settlement field uses to decide whether to render the
// District row at all, so the validator and the row can never disagree.

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Which locality row failed provider validation.
///
/// Lets the screen attach the error message to the matching row (Defect 7)
/// instead of rendering it once below the whole block. `null` (no value at
/// all from [validateProviderLocality]) means the selection is valid.
enum LocalityLevel { city, district }

/// The outcome of validating the locality for a provider role.
///
/// `null` means the selection is valid; a non-null result carries BOTH the
/// failing [level] (so the screen routes the message to the right row) and the
/// localised [message] for the FIRST unsatisfied requirement (settlement, then
/// district).
class LocalityValidationError {
  const LocalityValidationError(this.level, this.message);

  final LocalityLevel level;
  final String message;
}

/// Validates the locality for a provider role. Returns `null` when the
/// selection is valid, otherwise a [LocalityValidationError] identifying the
/// first unsatisfied level and its localised message.
LocalityValidationError? validateProviderLocality({
  required String? cityId,
  required String? districtId,
  required bool cityHasDistricts,
  required AppLocalizations l10n,
}) {
  if (cityId == null || cityId.isEmpty) {
    return LocalityValidationError(
      LocalityLevel.city,
      l10n.errSettlementRequired,
    );
  }
  // District is required only when the settlement subdivides into districts.
  if (cityHasDistricts && (districtId == null || districtId.isEmpty)) {
    return LocalityValidationError(
      LocalityLevel.district,
      l10n.errLocalityDistrictRequired,
    );
  }
  return null;
}
