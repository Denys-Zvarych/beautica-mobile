// Phase 4.3 — Bio field validator.
//
// Optional field — empty/null input returns null (no error). The only
// restriction is the 2000-character hard cap that mirrors the backend's
// `@Size(max = 2000)` constraint on `MasterDetailResponse.bio`.
//
// No special-character restrictions — a bio may legitimately contain any
// Unicode text (emoji, punctuation, Cyrillic, etc.).

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Returns `null` when [v] is a valid bio value (empty or ≤ 2000 chars), or a
/// localised error string otherwise.
///
/// Called from the `field-bio` [TextFormField] validator on the
/// [MasterEditScreen].
String? validateBio(String? v, AppLocalizations l10n) {
  if (v == null || v.trim().isEmpty) return null;
  // Use trimmed.length (code-unit count) to match the backend's
  // Java String.length() constraint. Emoji count as 2 code units, but
  // in practice a 2000-code-unit cap is generous enough for any bio.
  if (v.trim().length > 2000) return l10n.errBioTooLong;
  return null;
}
