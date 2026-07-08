// Phase 4.3 — MasterUpdate value object.
//
// Carries the editable subset of the master profile fields that the user can
// modify on [MasterEditScreen]. Passed to [MasterRepository.updateMyProfile].
//
// Pure Dart: no Flutter imports. Mirrors the backend PATCH
// /independent-masters/me request body (Phase 4.3).

/// Editable profile fields for INDEPENDENT_MASTER.
///
/// [firstName], [lastName] and [contactPhone] are REQUIRED — the edit form
/// blocks Save when any is empty, so they always arrive non-blank. The
/// repository trims each value before sending. Per the backend contract: an
/// empty [bio] / [instagram] CLEARS the value server-side (the key is always
/// sent), whereas a blank [contactPhone] is a no-op (the key is omitted) —
/// phone cannot be cleared by design.
final class MasterUpdate {
  const MasterUpdate({
    required this.firstName,
    required this.lastName,
    required this.bio,
    required this.contactPhone,
    required this.instagram,
    required this.professionalTitle,
  });

  /// Master's given name.
  final String firstName;

  /// Master's family name.
  final String lastName;

  /// Short bio text (max 2000 characters). Empty string means "clear the bio".
  final String bio;

  /// Contact phone number. REQUIRED for all users — the edit form blocks Save
  /// when empty, so this never arrives blank and is never cleared.
  final String contactPhone;

  /// Optional Instagram handle (without `@`). Empty string means "clear it".
  final String instagram;

  /// Optional professional title (e.g. "Майстер манікюру"). Max 100 chars.
  /// Empty string means "clear it" — same semantics as [bio] and [instagram].
  final String professionalTitle;
}
