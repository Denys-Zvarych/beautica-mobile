// Phase 2.16 — Multi-step registration draft (cross-step form state).
//
// Owns every field collected across the four-pill registration wizard:
//   • Step 1 (Account)       — email + password + confirmPassword +
//                              termsAccepted
//   • M515 phone-first order: phone (+ termsAccepted) -> SMS code
//     (registrationTicket) -> password -> name -> address. `email` stays
//     empty on that path (no email field for any role, AUTH-D11).
//   • Step 2 (Profile)       — firstName + lastName + phone + salonName
//   • Step 3 (Address)       — cityId + districtId + street/...
//
// One [RegisterDraft] is created when the user picks a role on the
// role-selection screen and cleared on /done arrival or on logout. Persists
// in memory only — see [RegisterDraftNotifier] for the lifecycle contract.
//
// Pure Dart (no Flutter imports) — must be testable without a widget tree.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../domain/user_role.dart';

part 'register_draft.freezed.dart';

/// Cross-step registration form state. All fields default to empty/`null`
/// except [role], which is set when the user picks a role on the
/// role-selection screen (the entry point of the wizard).
@freezed
sealed class RegisterDraft with _$RegisterDraft {
  /// Empty draft (the default for tests). The role-selection screen will
  /// always set a real [role] before any of the four step screens render.
  const factory RegisterDraft({
    required UserRole role,
    // Step 1 — Account
    @Default('') String email,
    @Default('') String password,
    @Default('') String confirmPassword,
    // Phase 443 — the required terms + privacy checkbox on Step 1. Sent as
    // the consent triple by Step 3's `register()` call.
    @Default(false) bool termsAccepted,
    // M515 (AUTH-41) — the single-use, 15-minute ticket from
    // `POST /auth/register/phone/otp/verify` (the phone is proven by SMS).
    // A credential: wiped by [RegisterDraftNotifier.clearCredentials] and
    // [RegisterDraftNotifier.updatePhone], never persisted.
    String? registrationTicket,
    // Step 2 — Profile
    @Default('') String firstName,
    @Default('') String lastName,
    @Default('') String phone,
    @Default('') String salonName,
    // Step 3 — Address.
    // Locality IDs are backend UUIDs (String), NOT ints — they mirror the
    // location domain models (Oblast/City/CityDistrict all use String ids).
    // Phase 346 — `oblastCode` is GONE. It only ever existed to fetch the
    // cascade's city list and re-hydrate its oblast picker on "← Назад". It
    // was never submitted to any endpoint.
    // [cityId] / [districtId] hold the chosen settlement / district UUIDs.
    // Step 3 WRITES them on submit, and `_persistPendingLocality` READS them to
    // build the durable `PendingLocality` blob submitted after OTP. Step 3 does
    // NOT read them back: re-entering the screen starts with an empty
    // settlement field (the draft holds no display label to seed it with).
    String? cityId,
    String? districtId,
    @Default('') String street,
    @Default('') String buildingNo,
    @Default('') String locationNote,
  }) = _RegisterDraft;

  const RegisterDraft._();

  /// Credentials and PII never print (logs, crash reports, test failure
  /// output): [password], [confirmPassword] and [registrationTicket] are
  /// redacted to a set / unset marker, and so are the personal fields
  /// [email], [phone], [firstName], [lastName], [street], [buildingNo] and
  /// [locationNote]. Freezed skips its own `toString` for this class.
  @override
  String toString() =>
      'RegisterDraft(role: $role, email: ${_presence(email)}, '
      'password: ${_redact(password)}, '
      'confirmPassword: ${_redact(confirmPassword)}, '
      'termsAccepted: $termsAccepted, '
      'registrationTicket: ${_redact(registrationTicket)}, '
      'firstName: ${_presence(firstName)}, '
      'lastName: ${_presence(lastName)}, phone: ${_presence(phone)}, '
      'salonName: $salonName, cityId: $cityId, districtId: $districtId, '
      'street: ${_presence(street)}, buildingNo: ${_presence(buildingNo)}, '
      'locationNote: ${_presence(locationNote)})';

  static String _presence(String value) => value.isEmpty ? '<empty>' : '<set>';

  static String _redact(String? secret) =>
      secret == null || secret.isEmpty ? '<empty>' : '<redacted>';
}
