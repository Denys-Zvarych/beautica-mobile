// Phase 2.19 — Street validator.
//
// Pure function — used by RegisterStep3Screen for the "Вулиця" TextFormField
// validator (INDEPENDENT_MASTER + SALON_OWNER only; CLIENT never renders it).
//
// Rules (match backend address DTO constraints):
//   - Required for providers (the field is only attached for MASTER/OWNER).
//   - Minimum 2 non-whitespace characters (trim before length check).
//   - Maximum 120 characters (raw length, JPA @Column(length = 120)).

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Maximum street length accepted by the backend address DTO.
const int kStreetMaxLength = 120;

/// Returns `null` when [v] is a valid street, or a localised error string.
///
/// Only attach this validator for provider roles (MASTER / OWNER) — the field
/// is required and not rendered for CLIENT.
String? validateStreet(String? v, AppLocalizations l10n) {
  final trimmed = v?.trim() ?? '';
  if (trimmed.isEmpty) return l10n.errStreetRequired;
  if (trimmed.length < 2) return l10n.errStreetRequired;
  if ((v?.length ?? 0) > kStreetMaxLength) return l10n.errStreetTooLong;
  return null;
}
