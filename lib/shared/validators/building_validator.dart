// Phase 2.19 — Building number validator.
//
// Pure function — used by RegisterStep3Screen for the "Будинок" TextFormField
// validator (INDEPENDENT_MASTER + SALON_OWNER only; CLIENT never renders it).
//
// Rules (match backend address DTO constraints):
//   - Required for providers (the field is only attached for MASTER/OWNER).
//   - Minimum 1 non-whitespace character (a single digit "5" is valid).
//   - Maximum 50 characters (raw length, matches backend address DTO). Building
//     numbers like "12А", "8/2", "корп. 3" stay comfortably within this cap.

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Maximum building-number length accepted by the backend address DTO.
const int kBuildingMaxLength = 50;

/// Returns `null` when [v] is a valid building number, or a localised error.
///
/// Only attach this validator for provider roles (MASTER / OWNER) — the field
/// is required and not rendered for CLIENT.
String? validateBuilding(String? v, AppLocalizations l10n) {
  final trimmed = v?.trim() ?? '';
  if (trimmed.isEmpty) return l10n.errBuildingRequired;
  if ((v?.length ?? 0) > kBuildingMaxLength) return l10n.errBuildingTooLong;
  return null;
}
