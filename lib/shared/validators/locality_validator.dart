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
//   INDEPENDENT_MASTER → oblastCode + cityId are required. If the chosen city
//   / SALON_OWNER        has districts (cityHasDistricts == true) then a
//                        districtId is also required; if the city is a leaf
//                        (no urban districts) the districtId must stay null.
//
// The "has districts" signal is read client-side from the selected City's
// `hasDistricts` flag (carried in [cityHasDistricts]) — exactly the same source
// the cascade uses to enable/disable the District row. No extra network call.

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Which cascade level failed provider locality validation.
///
/// Lets the screen attach the error message to the matching row (Defect 7)
/// instead of rendering it once below the whole cascade. `null` (no value at
/// all from [validateProviderLocality]) means the selection is valid.
enum LocalityLevel { oblast, city, district }

/// The outcome of validating the locality cascade for a provider role.
///
/// `null` means the selection is valid; a non-null result carries BOTH the
/// failing [level] (so the screen routes the message to the right
/// [LocalityTapRow]) and the localised [message] for the FIRST unsatisfied
/// requirement (oblast → city → district order).
class LocalityValidationError {
  const LocalityValidationError(this.level, this.message);

  final LocalityLevel level;
  final String message;
}

/// Validates the locality cascade for a provider role. Returns `null` when the
/// selection is valid, otherwise a [LocalityValidationError] identifying the
/// first unsatisfied level and its localised message.
LocalityValidationError? validateProviderLocality({
  required String? oblastCode,
  required String? cityId,
  required String? districtId,
  required bool cityHasDistricts,
  required AppLocalizations l10n,
}) {
  if (oblastCode == null || oblastCode.isEmpty) {
    return LocalityValidationError(
      LocalityLevel.oblast,
      l10n.errLocalityOblastRequired,
    );
  }
  if (cityId == null || cityId.isEmpty) {
    return LocalityValidationError(
      LocalityLevel.city,
      l10n.errLocalityCityRequired,
    );
  }
  // District is required only when the city actually subdivides into districts.
  if (cityHasDistricts && (districtId == null || districtId.isEmpty)) {
    return LocalityValidationError(
      LocalityLevel.district,
      l10n.errLocalityDistrictRequired,
    );
  }
  return null;
}
