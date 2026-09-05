// Phase 4.3 — MasterUpdate value object.
//
// Carries the editable subset of the master profile fields that the user can
// modify on [MasterEditScreen]. Passed to [MasterRepository.updateMyProfile].
//
// Pure Dart: no Flutter imports. [MasterType] (`../domain/master.dart`) is
// itself pure Dart, so importing it here does not break that rule. Mirrors
// the backend PATCH /independent-masters/me request body (Phase 4.3).

import 'master.dart' show MasterType;

/// Editable profile fields for INDEPENDENT_MASTER and SALON_MASTER — both
/// roles reuse the same edit screens (`personal_info_edit_screen.dart`,
/// `contacts_edit_screen.dart`) and therefore the same update shape.
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
    this.masterType = MasterType.independentMaster,
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

  /// The caller's role, used ONLY by [MasterRepository.updateMyProfile] to
  /// pick the endpoint that admits it — [MasterType.independentMaster] (the
  /// default) PATCHes `/independent-masters/me/profile`,
  /// [MasterType.salonMaster] PATCHes `/masters/me/profile`. Never sent on
  /// the wire itself. Defaults to [MasterType.independentMaster] so every
  /// pre-existing call site (and every test constructing a `const
  /// MasterUpdate(...)` without this field) keeps hitting the same endpoint
  /// it always has — see `master_repository.dart`'s `updateMyProfile` doc for
  /// why [MasterType.salonOwner] is deliberately left on that same default
  /// (no salon-owner-as-master caller exists yet; see the
  /// `project_owner_as_master_multisalon_blocked` decision).
  final MasterType masterType;
}
