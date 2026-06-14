// Phase 2.6 — Name field validator.
//
// Pure function — no side effects, no dependencies beyond AppLocalizations.
// Used by RegisterScreen for firstName and lastName TextFormField validators.

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Maximum allowed length for a name field, mirroring the backend `@Size(max =
/// 100)` constraint on first/last name and the service-definition name. Shared
/// so validators and input formatters agree on the same cap.
const int kNameMaxLength = 100;

/// Returns null when [v] is a valid name, or a localised error message.
///
/// Validation rules (mirrors backend constraints):
///   - Not null and not blank (at least one non-whitespace character).
///   - No longer than [kNameMaxLength] characters.
String? validateName(String? v, AppLocalizations l10n) {
  if (v == null || v.trim().isEmpty) return l10n.errNameRequired;
  if (v.length > kNameMaxLength) return l10n.errNameTooLong;
  return null;
}
