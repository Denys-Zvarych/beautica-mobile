// Phase 2.5 — Password field validator.
//
// Pure function — no side effects, no dependencies beyond AppLocalizations.
// Used by LoginScreen and RegisterScreen TextFormField validators.

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Returns null when [v] is an acceptable password, or a localised error message.
///
/// Validation rules (mirrors backend constraints):
///   - Not null or empty.
///   - Between 1 and 128 characters inclusive.
String? validatePassword(String? v, AppLocalizations l10n) {
  if (v == null || v.isEmpty) return l10n.errPasswordRequired;
  if (v.length > 128) return l10n.errPasswordLength;
  return null;
}
