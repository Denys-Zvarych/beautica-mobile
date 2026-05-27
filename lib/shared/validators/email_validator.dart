// Phase 2.5 — Email field validator.
//
// Pure function — no side effects, no dependencies beyond AppLocalizations.
// Used by LoginScreen and RegisterScreen TextFormField validators.

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Module-level final so the [RegExp] object is created once and reused
/// across all [validateEmail] calls. Avoids repeated allocation on every
/// `AutovalidateMode.onUserInteraction` trigger.
final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Returns null when [v] is a valid email address, or a localised error message.
///
/// Validation rules (mirrors backend constraints):
///   - Not null or empty.
///   - Matches the RFC-5322-ish pattern `^[^@\s]+@[^@\s]+\.[^@\s]+$`.
///   - No longer than 255 characters.
String? validateEmail(String? v, AppLocalizations l10n) {
  if (v == null || v.isEmpty) return l10n.errEmailRequired;
  if (!_emailRegex.hasMatch(v)) {
    return l10n.errEmailInvalid;
  }
  if (v.length > 255) return l10n.errEmailTooLong;
  return null;
}
