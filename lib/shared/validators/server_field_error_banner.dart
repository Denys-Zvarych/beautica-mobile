// Server field-error banner helper.
//
// Builds a single human-readable banner string from a [ValidationFailure]'s
// `fieldErrors` map for screens where the failing field is NOT rendered (e.g.
// the post-OTP save on VerificationScreen surfaces register step 2/3 field
// errors, and register step 3's submit surfaces step 2/3 field errors).
//
// Each line is "<localized field name>: <server message>" via the
// `validationFieldErrorLine` l10n template. Unknown field keys fall back to the
// raw key so a backend contract drift never hides the error. When the map is
// empty the caller should fall back to `serverMessage` and then the generic
// `errValidation` string — this helper returns null in that case.

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Maps a backend field key (JSON path) to a localized display name.
///
/// Returns the raw [key] when no localized label is known so the error is
/// always surfaced rather than silently dropped.
String localizedFieldName(String key, AppLocalizations l10n) {
  switch (key) {
    case 'firstName':
      return l10n.fieldNameFirstName;
    case 'lastName':
      return l10n.fieldNameLastName;
    case 'phone':
    case 'phoneNumber':
    case 'contactPhone':
      return l10n.fieldNamePhone;
    case 'salonName':
    case 'businessName':
    case 'name':
      return l10n.fieldNameSalonName;
    case 'street':
      return l10n.fieldNameStreet;
    case 'buildingNo':
      return l10n.fieldNameBuildingNo;
    case 'locationNote':
      return l10n.fieldNameLocationNote;
    case 'cityId':
    case 'city':
      return l10n.fieldNameCity;
    case 'email':
      return l10n.fieldNameEmail;
    default:
      return key;
  }
}

/// Builds a multi-line banner message from [fieldErrors], or `null` when the
/// map is empty (caller should fall back to `serverMessage` / `errValidation`).
String? buildFieldErrorBanner(
  Map<String, String> fieldErrors,
  AppLocalizations l10n,
) {
  if (fieldErrors.isEmpty) return null;
  return fieldErrors.entries
      .map(
        (e) => l10n.validationFieldErrorLine(
          localizedFieldName(e.key, l10n),
          e.value,
        ),
      )
      .join('\n');
}
