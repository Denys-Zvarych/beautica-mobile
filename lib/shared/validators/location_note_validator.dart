// Phase 2.19 — Location note validator.
//
// Pure function — used by RegisterStep3Screen for the "Примітка" textarea
// (INDEPENDENT_MASTER + SALON_OWNER only; CLIENT never renders it).
//
// Rules (match backend address DTO constraints):
//   - OPTIONAL — an empty note is valid (returns null).
//   - Maximum 1000 characters (raw length). The textarea also enforces this via
//     a maxLength input formatter; this validator is the defensive backstop.

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Maximum location-note length accepted by the backend address DTO.
const int kLocationNoteMaxLength = 1000;

/// Returns `null` when [v] is a valid (or empty) location note, or a localised
/// error string when it exceeds [kLocationNoteMaxLength].
String? validateLocationNote(String? v, AppLocalizations l10n) {
  // Optional field — empty / null is always valid.
  if ((v?.length ?? 0) > kLocationNoteMaxLength) {
    return l10n.errLocationNoteTooLong;
  }
  return null;
}
