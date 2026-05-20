// Phase 2.16 — RegisterDraftNotifier (cross-step Riverpod state holder).
//
// Lifecycle:
//   • Created when the user picks a role on the role-selection screen
//     (via [RegisterDraftNotifier.start]).
//   • Updated as the user fills each step (updateStep1/2/3).
//   • Cleared on /done arrival or on logout ([reset]).
//
// In-memory only — registration is a short flow; if the user backgrounds
// the app it is acceptable for the draft to be discarded.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/user_role.dart';
import 'register_draft.dart';

part 'register_draft_notifier.g.dart';

/// Riverpod notifier holding the cross-step [RegisterDraft].
///
/// `null` until the user picks a role; non-null while the wizard is in
/// progress; reset back to `null` when the wizard completes (or the user
/// abandons it).
@Riverpod(keepAlive: true)
class RegisterDraftNotifier extends _$RegisterDraftNotifier {
  @override
  RegisterDraft? build() => null;

  /// Initialises the draft with the user's chosen [role]. Called by the
  /// role-selection screen when the user advances out of it.
  void start(UserRole role) {
    state = RegisterDraft(role: role);
  }

  /// Merges the Step 1 (Account) slice into the draft. Safe to call before
  /// [start] — this will be a no-op if the draft is `null` (defensive: the
  /// router guard should prevent this).
  void updateStep1({
    required String email,
    required String password,
    required String confirmPassword,
  }) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      email: email,
      password: password,
      confirmPassword: confirmPassword,
    );
  }

  /// Merges the Step 2 (Profile) slice. [salonName] is OWNER-only — pass
  /// the empty string for non-owner roles.
  void updateStep2({
    required String firstName,
    required String lastName,
    required String phone,
    String salonName = '',
  }) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      salonName: salonName,
    );
  }

  /// Merges the Step 3 (Address) slice.
  void updateStep3({
    String? oblastCode,
    int? cityId,
    int? districtId,
    String street = '',
    String buildingNo = '',
    String locationNote = '',
  }) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      oblastCode: oblastCode,
      cityId: cityId,
      districtId: districtId,
      street: street,
      buildingNo: buildingNo,
      locationNote: locationNote,
    );
  }

  /// Clears the draft. Called on `/done` arrival or on logout.
  void reset() {
    state = null;
  }
}
