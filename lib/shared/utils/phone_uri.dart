// Pure, Flutter-free helper that converts a stored phone contact value into a
// canonical, validated `tel:` URI.
//
// SECURITY (mobile-security audit, required control): this is a STRICT
// allow-list. The stored value is verbatim user input and MUST NEVER be handed
// to `launchUrl` unvalidated. Anything that is not provably a safe dialable
// number returns `null` so the caller can no-op / show a neutral message.
//
// Accepted inputs (after stripping spaces and common separators):
//   • Local digits          "0671234567"      → tel:0671234567
//   • E.164 international    "+380671234567"   → tel:+380671234567
// The dialable string is an optional leading "+" followed by 7–15 digits.
//
// Rejected (returns null): empty / "—" / null; values with no digits; values
// whose digit count is outside 7–15; anything containing characters other than
// the recognised separators, digits, and a single leading "+".
//
// Kept pure (no `package:flutter/*` import) so it is unit-testable without a
// widget tree.
library;

/// Sentinel rendered in the UI when a contact value is absent.
const String _emptyPlaceholder = '—';

/// Separators stripped before validation: spaces, hyphens, parentheses, dots.
/// Hoisted top-level `final` so the pattern compiles exactly once.
final RegExp _phoneSeparators = RegExp(r'[\s\-().]');

/// Dialable phone shape: optional leading "+" then 7–15 digits. Hoisted so the
/// pattern compiles exactly once (no per-call allocation).
final RegExp _telPattern = RegExp(r'^\+?\d{7,15}$');

/// Converts a stored phone contact [value] into a canonical, validated `tel:`
/// [Uri], or `null` when [value] cannot be safely resolved to a dialable
/// number.
///
/// Never returns an un-validated [Uri]; callers may launch the result directly.
Uri? canonicalTelUri(String? value) {
  if (value == null) return null;

  final String trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == _emptyPlaceholder) return null;

  // Strip presentation separators, then validate the remaining string against
  // the strict dialable shape before composing the tel: URI.
  final String compact = trimmed.replaceAll(_phoneSeparators, '');
  if (!_telPattern.hasMatch(compact)) return null;

  return Uri(scheme: 'tel', path: compact);
}
