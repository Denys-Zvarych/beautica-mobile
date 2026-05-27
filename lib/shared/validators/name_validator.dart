// Phase 2.6 — Name field validator.
//
// Pure function — no side effects, no dependencies beyond AppLocalizations.
// Used by RegisterScreen for firstName and lastName TextFormField validators.

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Returns null when [v] is a valid name, or a localised error message.
///
/// Validation rules (mirrors backend constraints):
///   - Not null and not blank (at least one non-whitespace character).
///   - No longer than 100 characters.
String? validateName(String? v, AppLocalizations l10n) {
  if (v == null || v.trim().isEmpty) return l10n.errNameRequired;
  if (v.length > 100) return l10n.errNameTooLong;
  return null;
}
