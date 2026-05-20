// Phase 2.16 — Multi-step registration draft (cross-step form state).
//
// Owns every field collected across the four-pill registration wizard:
//   • Step 1 (Account)       — email + password + confirmPassword
//   • Step 2 (Profile)       — firstName + lastName + phone + salonName
//   • Step 3 (Address)       — oblastCode + cityId + districtId + street/...
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
    // Step 2 — Profile
    @Default('') String firstName,
    @Default('') String lastName,
    @Default('') String phone,
    @Default('') String salonName,
    // Step 3 — Address
    String? oblastCode,
    int? cityId,
    int? districtId,
    @Default('') String street,
    @Default('') String buildingNo,
    @Default('') String locationNote,
  }) = _RegisterDraft;
}
