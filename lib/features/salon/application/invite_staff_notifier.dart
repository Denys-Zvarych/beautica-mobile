// Phase 21.4 — Invite Staff notifier.
//
// Backing notifier for `InviteStaffScreen`: a `SALON_OWNER`/`SALON_ADMIN`
// inviting a new admin or master to their salon. There is nothing to load
// (no pending-invites list this phase — descoped to Phase 21.11) so, exactly
// like `RegisterSalon` (`register_salon_notifier.dart`), `build()` is a
// no-op; the notifier exists purely to own [submit] and its `ref` outside
// the widget tree, mirroring `RegisterSalon.submit`'s `Future<Failure?>`
// mutate-method shape rather than inventing a different convention.
//
// REUSE-FIRST — no new write path: [submit] wraps the EXISTING
// `SalonRepository.inviteStaff` verbatim (`salon_repository.dart`).
//
// Lifecycle guarding — mirrors `RegisterSalon`/`RegisterSalonScreen`'s own
// CRITICAL fix (an autoDispose notifier's element disposed mid-`await`
// throws `UnmountedRefException` on the next `ref` access). Unlike
// `RegisterSalon.submit`, THIS method never touches `ref` after its own
// `await` (there is no `mySalonsProvider`-style cache to invalidate this
// phase — see the file header above), so it cannot itself reproduce that
// exact crash. The guarding is still reproduced on the WATCHING side
// (`InviteStaffScreen.build()`'s `ref.watch(inviteStaffProvider)` +
// `PopScope`) per the architect's brief, both to keep this notifier's
// element alive for the whole in-flight request (defensive — a future edit
// that adds a post-await `ref` call here, e.g. once Phase 21.11 wires a
// pending-invites cache to invalidate, inherits the same protection for
// free) and to keep the back-navigation-mid-submit path — which IS a real
// hazard regardless of what [submit] does internally, since disposing the
// screen mid-request would otherwise abandon the in-flight POST with no
// user feedback — guarded exactly like `RegisterSalonScreen`'s own.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';

import '../data/salon_repository.dart';

part 'invite_staff_notifier.g.dart';

/// Drives the `InviteStaffScreen` submit — invites a new admin or master via
/// `POST /salons/{salonId}/invite`.
///
/// Generated provider name: `inviteStaffProvider`.
@riverpod
class InviteStaff extends _$InviteStaff {
  @override
  void build() {}

  /// Sends the invite via [SalonRepository.inviteStaff].
  ///
  /// Returns `null` on success or the [Failure] on error. Callers branch on
  /// `failure is ServerFailure ? failure.statusCode : null` to pick distinct
  /// copy for 403 (forbidden) / 429 (rate-limited) rather than the generic
  /// [Failure.userMessage] — see `InviteStaffScreen`'s own doc.
  Future<Failure?> submit({
    required String salonId,
    required String email,
    required UserRole role,
  }) async {
    try {
      await ref
          .read(salonRepositoryProvider)
          .inviteStaff(salonId: salonId, email: email, role: role);
      return null;
    } on Failure catch (f) {
      return f;
    }
  }
}
