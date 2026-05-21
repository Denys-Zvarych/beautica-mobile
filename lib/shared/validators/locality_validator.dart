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

/// The outcome of validating the locality cascade for a provider role.
///
/// `null` means the selection is valid; a non-null value is the localised
/// error string identifying the FIRST unsatisfied requirement (oblast → city →
/// district order), so the screen can surface a single clear message.
String? validateProviderLocality({
  required String? oblastCode,
  required String? cityId,
  required String? districtId,
  required bool cityHasDistricts,
  required AppLocalizations l10n,
}) {
  if (oblastCode == null || oblastCode.isEmpty) {
    return l10n.errLocalityOblastRequired;
  }
  if (cityId == null || cityId.isEmpty) {
    return l10n.errLocalityCityRequired;
  }
  // District is required only when the city actually subdivides into districts.
  if (cityHasDistricts && (districtId == null || districtId.isEmpty)) {
    return l10n.errLocalityDistrictRequired;
  }
  return null;
}
