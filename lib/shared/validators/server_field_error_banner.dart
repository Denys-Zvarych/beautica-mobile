// Server field-error banner helper.
//
// Builds a single human-readable banner string from a [ValidationFailure]'s
// `fieldErrors` map for screens where the failing field is NOT rendered (e.g.
// the post-OTP save on VerificationScreen surfaces register step 2/3 field
// errors, and register step 3's submit surfaces step 2/3 field errors).
//
// Each line is "<localized field name>: <fieldErrorGeneric>" via the
// `validationFieldErrorLine` l10n template. Unknown field keys fall back to
// the raw key — guarded through `serverFieldNameOr` (mobile-security,
// 2026-08: `ErrorMapperInterceptor._extractFieldErrors` caps the backend
// `errors` map's VALUES at 200 chars but never caps the KEYS) — so a backend
// contract drift never hides the error while an oversized/control-char key
// still can't reach the liveRegion surface below verbatim. When the map is
// empty the caller should fall back to `Failure.userMessage(context)` — this
// helper returns null in that case.
//
// mobile-security, 2026-08 — this banner is the GENERIC summary surface for
// screens that cannot render the failing field inline (it routes to a
// VelvetSnack or an `AuthBanner`, both wrapped in `Semantics(liveRegion:
// true)` and therefore narrated to screen readers unconditionally, unlike a
// per-field `errorText` a user encounters by focusing that field). It
// therefore NEVER embeds the backend's raw per-field message — that value can
// be untranslated/technical (see `ErrorMapperInterceptor`) and would be read
// aloud verbatim. Only the FIELD NAME survives (mapped through
// [localizedFieldName], itself always either a localized label or a raw JSON
// key — never free-form server prose); the message slot is always the fixed
// [AppLocalizations.fieldErrorGeneric] notice. This is a deliberate trade:
// the user still learns exactly WHICH field(s) to fix, just not the backend's
// exact wording for why. True inline per-field surfaces (the `_serverFieldErrors`
// → `errorText` pattern in `service_form.dart` / the edit screens) are a
// different, narrower-audience surface and are NOT affected by this rule —
// see `server_field_message.dart`'s `serverFieldMessageOr` for that surface's
// own (length/char) guard.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/server_field_message.dart';

/// Maps a backend field key (JSON path) to a localized display name.
///
/// Returns the raw [key] when no localized label is known and [key] is fit
/// to render (see [serverFieldNameOr]) so the error is always surfaced
/// rather than silently dropped; otherwise falls back to the localized
/// [AppLocalizations.fieldNameUnknown] notice — this banner renders on a
/// live-narrated `Semantics(liveRegion: true)` surface (mobile-security,
/// 2026-08), so an oversized or control/bidi-laden raw key must never reach
/// it verbatim.
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
      return serverFieldNameOr(key, l10n.fieldNameUnknown);
  }
}

/// Builds a multi-line banner message naming every field in [fieldErrors], or
/// `null` when the map is empty (caller should fall back to
/// `Failure.userMessage(context)`).
///
/// Deliberately ignores the map's VALUES (the backend's per-field message) —
/// see this file's header comment. Only the KEYS (field names) are rendered.
String? buildFieldErrorBanner(
  Map<String, String> fieldErrors,
  AppLocalizations l10n,
) {
  if (fieldErrors.isEmpty) return null;
  return fieldErrors.keys
      .map(
        (key) => l10n.validationFieldErrorLine(
          localizedFieldName(key, l10n),
          l10n.fieldErrorGeneric,
        ),
      )
      .join('\n');
}
