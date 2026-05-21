// Phase 2.17 — Ukrainian phone number validator.
//
// Pure function — no side effects, no dependencies beyond AppLocalizations.
// Used by RegisterStep2Screen for the phone TextFormField validator.
//
// Validation rules (mirror backend + Ukrainian phone format):
//   - Not null and not blank.
//   - After stripping the +380 prefix and all spaces/dashes, exactly 9 digits
//     must remain (the subscriber number).
//   - Paste-guard: bare "38" prefix without the leading zero (e.g. "380501234567")
//     is also accepted — the guard ensures "38" alone doesn't yield "338...".
//
// Accepted inputs:
//   +380 50 123 4567
//   +380501234567
//   380501234567          ← pasted without +
//   0501234567            ← local format
//   50 123 4567           ← 9-digit bare subscriber number
//
// Rejected:
//   empty / whitespace
//   anything with non-digit/+/-/space characters
//   subscriber numbers shorter or longer than 9 digits

import 'package:beautica_mobile/l10n/app_localizations.dart';

// Hoisted to file-level to avoid constructing a new RegExp on every call.
final _kStripRe = RegExp(r'[\s\-]');
final _kNineDigitsRe = RegExp(r'^\d{9}$');

/// Returns `null` when [v] is a valid Ukrainian phone number, or a localised
/// error string otherwise.
///
/// Uses [AppLocalizations.errPhoneInvalid] for the error message.
String? validatePhone(String? v, AppLocalizations l10n) {
  if (v == null || v.trim().isEmpty) return l10n.errPhoneInvalid;

  final trimmed = v.trim();

  // Strip all whitespace and dashes for canonical comparison.
  final stripped = trimmed.replaceAll(_kStripRe, '');

  // Extract the subscriber digits (the 9 digits after the country/area prefix).
  String? subscriber;

  if (stripped.startsWith('+380')) {
    subscriber = stripped.substring(4); // after "+380"
  } else if (stripped.startsWith('380')) {
    // Phone number pasted as "380XXXXXXXXX" — paste-guard:
    // startsWith('38') && !startsWith('380') is rejected further below.
    subscriber = stripped.substring(3); // after "380"
  } else if (stripped.startsWith('0') && stripped.length == 10) {
    // Local format: 0XX XXX XXXX → 10 digits, first is the leading 0.
    subscriber = stripped.substring(1); // after "0"
  } else if (stripped.startsWith('38') && !stripped.startsWith('380')) {
    // Paste-guard: "38" prefix without the "0" → reject to prevent "338..." bug.
    return l10n.errPhoneInvalid;
  } else {
    // Bare 9-digit subscriber number (no country / area prefix).
    subscriber = stripped;
  }

  // Subscriber number must be exactly 9 digits.
  if (!_kNineDigitsRe.hasMatch(subscriber)) return l10n.errPhoneInvalid;

  return null;
}
