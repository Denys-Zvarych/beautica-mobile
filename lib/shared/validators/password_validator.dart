// Phase 2.5 — Password field validator.
//
// Pure function — no side effects, no dependencies beyond AppLocalizations.
// Used by LoginScreen and RegisterScreen TextFormField validators.
//
// Two validators are exposed:
//   validatePassword    — lenient; used on LOGIN (required + max-128 only so
//                         a user whose existing password predates the strength
//                         rule can still type it to log in).
//   validateNewPassword — strict; used on REGISTRATION (required, min-8,
//                         max-128, ≥1 digit, ≥1 uppercase) — must agree with
//                         the three helper criteria the registration UI shows.

import 'package:beautica_mobile/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Module-level RegExps — allocated once at class-load time, never per-call.
// These mirror the same patterns in password_strength_indicator.dart but are
// declared here so the pure-Dart validator has no Flutter/widget dependency.
// ---------------------------------------------------------------------------

final RegExp _reDigit = RegExp(r'\d');
final RegExp _reUpper = RegExp(r'[A-Z]');

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Lenient validator used on the **login** screen.
///
/// Rules:
///   1. Not null or empty → [AppLocalizations.errPasswordRequired].
///   2. Length > 128      → [AppLocalizations.errPasswordLength].
///   3. else              → null (valid).
///
/// Intentionally does NOT enforce minimum length or character classes so a
/// user whose existing password predates the strength policy can still sign in.
String? validatePassword(String? v, AppLocalizations l10n) {
  if (v == null || v.isEmpty) return l10n.errPasswordRequired;
  if (v.length > 128) return l10n.errPasswordLength;
  return null;
}

/// Strict validator used on the **registration** password field.
///
/// Rules (checked in order — first failing rule wins):
///   1. null/empty    → [AppLocalizations.errPasswordRequired].
///   2. length < 8    → [AppLocalizations.errPasswordTooShort].
///   3. length > 128  → [AppLocalizations.errPasswordLength].
///   4. no digit      → [AppLocalizations.errPasswordNoDigit].
///   5. no uppercase  → [AppLocalizations.errPasswordNoUppercase].
///   6. else          → null (valid).
///
/// Enforces exactly the three criteria advertised in the registration UI helper
/// row: 8+ chars, ≥1 digit, ≥1 uppercase letter. No additional rules are
/// applied so the validator stays in sync with what the user sees.
String? validateNewPassword(String? v, AppLocalizations l10n) {
  if (v == null || v.isEmpty) return l10n.errPasswordRequired;
  if (v.length < 8) return l10n.errPasswordTooShort;
  if (v.length > 128) return l10n.errPasswordLength;
  if (!_reDigit.hasMatch(v)) return l10n.errPasswordNoDigit;
  if (!_reUpper.hasMatch(v)) return l10n.errPasswordNoUppercase;
  return null;
}
