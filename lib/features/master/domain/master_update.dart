// Phase 4.3 — MasterUpdate value object.
//
// Carries the editable subset of the master profile fields that the user can
// modify on [MasterEditScreen]. Passed to [MasterRepository.updateMyProfile].
//
// Pure Dart: no Flutter imports. Mirrors the backend PATCH
// /independent-masters/me request body (Phase 4.3).

/// Editable profile fields for INDEPENDENT_MASTER.
///
/// All fields are optional at the Dart level — pass empty string for fields
/// the user cleared. The repository trims each value before sending to the
/// backend; the backend ignores null-equivalent fields.
final class MasterUpdate {
  const MasterUpdate({
    required this.firstName,
    required this.lastName,
    required this.bio,
    required this.contactPhone,
    required this.instagram,
  });

  /// Master's given name.
  final String firstName;

  /// Master's family name.
  final String lastName;

  /// Short bio text (max 2000 characters). Empty string means "clear the bio".
  final String bio;

  /// Optional contact phone number. Empty string means "clear the phone".
  final String contactPhone;

  /// Optional Instagram handle (without `@`). Empty string means "clear it".
  final String instagram;
}
