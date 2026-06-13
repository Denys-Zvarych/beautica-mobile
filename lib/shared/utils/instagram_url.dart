// Pure, Flutter-free helper that converts a stored Instagram contact value into
// a canonical, validated `https://instagram.com/<handle>` URI.
//
// SECURITY (mobile-security audit, required control): this is a STRICT
// allow-list. The stored value is verbatim user input and MUST NEVER be handed
// to `launchUrl` unvalidated. Anything that is not provably a safe Instagram
// destination returns `null` so the caller can no-op / show a neutral message.
//
// Accepted inputs:
//   • Bare handle            "olena_nails"            → https://instagram.com/olena_nails
//   • "@"-prefixed handle    "@olena_nails"           → https://instagram.com/olena_nails
//   • Full Instagram URL     "https://instagram.com/x"     → echoed (canonical host)
//                            "https://www.instagram.com/x" → echoed (canonical host)
//
// Rejected (returns null): empty / "—" / null; any non-https scheme
// (http, javascript:, tel:, data:, etc.); any host other than instagram.com or
// www.instagram.com; handles outside Instagram's charset.
//
// Kept pure (no `package:flutter/*` import) so it is unit-testable without a
// widget tree.
library;

/// Instagram username charset: letters, digits, period, underscore; 1–30 chars.
/// Hoisted to `static`-equivalent top-level `final` so the pattern compiles
/// exactly once (no per-call allocation).
final RegExp _instagramHandlePattern = RegExp(r'^[A-Za-z0-9._]{1,30}$');

/// Sentinel rendered in the UI when a contact value is absent.
const String _emptyPlaceholder = '—';

/// Hosts accepted for a full-URL input. Exact-match only.
const Set<String> _allowedHosts = <String>{
  'instagram.com',
  'www.instagram.com',
};

/// Converts a stored Instagram contact [value] into a canonical, validated
/// `https://instagram.com/<handle>` [Uri], or `null` when [value] cannot be
/// safely resolved to an Instagram destination.
///
/// Never returns an un-validated [Uri]; callers may launch the result directly.
Uri? canonicalInstagramUri(String? value) {
  if (value == null) return null;

  final String trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == _emptyPlaceholder) return null;

  // Full-URL branch: anything containing "://" is treated as a URL and must
  // pass the https + host allow-list. We do not try to coerce a malformed URL
  // into a handle — that would risk laundering a hostile string.
  if (trimmed.contains('://')) {
    final Uri? parsed = Uri.tryParse(trimmed);
    if (parsed == null) return null;
    if (parsed.scheme != 'https') return null;
    if (!_allowedHosts.contains(parsed.host)) return null;
    return parsed;
  }

  // Handle branch: strip a single leading "@", then validate against the
  // Instagram charset before composing the canonical URL.
  final String handle = trimmed.startsWith('@')
      ? trimmed.substring(1)
      : trimmed;
  if (!_instagramHandlePattern.hasMatch(handle)) return null;

  return Uri.parse('https://instagram.com/$handle');
}
