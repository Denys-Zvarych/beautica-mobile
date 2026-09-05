// Phase 21.3 — Salon contact phone validator.
//
// PROMOTED (REUSE-FIRST) out of `SalonContactsEditScreen`'s private
// `_validatePhone` (Phase 21.10) so `RegisterSalonScreen` (Phase 21.3) can
// reuse the SAME validation instead of duplicating it. `SalonContactsEditScreen`
// is rewired onto this function verbatim — same rules, same error keys, same
// behaviour, proven by that screen's own existing widget-test coverage
// (`test/features/salon/presentation/salon_edit_forms_test.dart`) staying
// green after the rewire.
//
// Mirrors backend `CreateSalonRequest`/`UpdateSalonRequest.phone`'s own
// `^[+\d\s\-()/]*$` + `@Size(max = 20)` constraints.
//
// Required client-side even though the backend field itself is nullable —
// matches `SalonContactsEditScreen`'s pre-existing behaviour: a salon is
// expected to carry a public contact number. Distinct from
// `shared/validators/phone_validator.dart`'s `validatePhone` (used for a
// PERSONAL account phone during registration — a stricter 9-digit
// Ukrainian-subscriber-number format); the salon contact field accepts the
// looser backend-mirrored character set instead.

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Maximum salon-phone length accepted by the backend (`@Size(max = 20)`).
const int kSalonPhoneMaxLength = 20;

final RegExp _kSalonPhoneAllowedChars = RegExp(r'^[+\d\s\-()/]*$');

/// Returns `null` when [v] is a valid salon contact phone, or a localised
/// error string otherwise.
String? validateSalonPhone(String? v, AppLocalizations l10n) {
  final trimmed = v?.trim() ?? '';
  if (trimmed.isEmpty) return l10n.errPhoneRequired;
  if (trimmed.length > kSalonPhoneMaxLength) return l10n.errPhoneTooLongEdit;
  if (!_kSalonPhoneAllowedChars.hasMatch(trimmed)) {
    return l10n.errPhoneInvalidEdit;
  }
  return null;
}
