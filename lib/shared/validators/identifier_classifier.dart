// M515 (AUTH-46 / AUTH-D15) — the login identifier classifier and the
// Ukrainian-mobile phone check shared by login and registration.
//
// * Input containing «@» is an email (validated by [validateEmail]).
// * Anything else is a phone: `0XXXXXXXXX`, `380…` and `+380…` (spaces,
//   dashes and brackets ignored) are normalised to `+380XXXXXXXXX`, and only
//   Ukrainian MOBILE operator codes are accepted — a landline, a foreign
//   number or junk is refused inline with «Потрібен український мобільний
//   номер» before any request.
//
// The backend re-checks every value (400 PHONE_NOT_UA_MOBILE); this is the
// UX gate, not the security boundary.

import '../../l10n/app_localizations.dart';
import 'email_validator.dart';

/// Ukrainian mobile operator codes (the two digits after `+380`).
const Set<String> kUaMobileOperatorCodes = <String>{
  '39', '50', '63', '66', '67', '68', '73', '75', '77', //
  '91', '92', '93', '94', '95', '96', '97', '98', '99',
};

final RegExp _kNonDigits = RegExp(r'\D');

/// `+380XXXXXXXXX` for a Ukrainian mobile number in any accepted spelling,
/// else `null`.
String? normalizeUaMobile(String raw) {
  final String digits = raw.replaceAll(_kNonDigits, '');
  final String subscriber = digits.startsWith('380')
      ? digits.substring(3)
      : digits.startsWith('0')
      ? digits.substring(1)
      : digits;
  if (subscriber.length != 9) return null;
  if (!kUaMobileOperatorCodes.contains(subscriber.substring(0, 2))) {
    return null;
  }
  return '+380$subscriber';
}

/// `null` when [raw] is a Ukrainian mobile number, else the inline error.
String? validateUaMobile(String raw, AppLocalizations l10n) =>
    normalizeUaMobile(raw) == null ? l10n.errPhoneNotUaMobile : null;

/// Whether a login / forgot-password identifier is an email (contains «@»).
bool isEmailIdentifier(String raw) => raw.trim().contains('@');

/// Login identifier check: empty → required; «@» → email rules; else the
/// Ukrainian-mobile rule.
String? validateIdentifier(String raw, AppLocalizations l10n) {
  final String value = raw.trim();
  if (value.isEmpty) return l10n.errIdentifierRequired;
  if (isEmailIdentifier(value)) return validateEmail(value, l10n);
  return validateUaMobile(value, l10n);
}

/// The wire value for a VALID identifier: the trimmed email, or the phone
/// normalised to `+380…`. Call only after [validateIdentifier] returned null.
String normalizeIdentifier(String raw) {
  final String value = raw.trim();
  if (isEmailIdentifier(value)) return value;
  return normalizeUaMobile(value) ?? value;
}
