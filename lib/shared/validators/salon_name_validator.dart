// Phase 2.17 — Salon name validator.
//
// Pure function — no side effects, no dependencies beyond AppLocalizations.
// Used by RegisterStep2Screen for the "Назва салону" TextFormField validator.
//
// Validation rules:
//   - Required only when the draft's role is SALON_OWNER.
//   - Minimum 2 non-whitespace characters (trim before length check).
//   - Maximum 255 characters (raw length, consistent with backend constraints).
//   - No ASCII control characters (matches the backend reject of C0/C1 control
//     bytes in business names).
//
// For non-SALON_OWNER roles the field is not rendered, so the validator is
// never attached — this validator is used ONLY when isSalonOwner == true.

import 'package:beautica_mobile/l10n/app_localizations.dart';

// Hoisted to file level — matches any ASCII C0/C1 control character.
final _kControlCharRe = RegExp(r'[\x00-\x1F\x7F]');

/// Returns `null` when [v] is a valid salon name, or a localised error string.
///
/// [v] is always validated as a required field — callers must only attach this
/// validator when the user is registering as SALON_OWNER.
String? validateSalonName(String? v, AppLocalizations l10n) {
  final trimmed = v?.trim() ?? '';
  if (trimmed.isEmpty) return l10n.errSalonNameRequired;
  if (trimmed.length < 2) return l10n.errSalonNameRequired;
  // Raw length cap — consistent with backend address/salon DTO (255).
  if ((v?.length ?? 0) > 255) return l10n.errSalonNameTooLong;
  // Control-char guard — backend rejects C0/C1 control bytes in names.
  if (_kControlCharRe.hasMatch(trimmed)) return l10n.errSalonNameInvalid;
  return null;
}
