// Phase 21.6, generalized Phase 305 — staff settings actions.
//
// Backing state for [StaffSettingsScreen] and [MoveAdminSalonScreen]: the two
// write paths an owner/admin has over ONE salon administrator, plus the read
// that feeds the rotate-destination picker. Named `StaffSettings` (not
// `AdminSettings`) since Phase 305, so phase 307's `removeMaster` sits beside
// [StaffSettings.removeAdmin] without ambiguity.
//
//   • [StaffSettings.removeAdmin] → `DELETE /salons/{salonId}/admins/{userId}`
//     — backend Phase 299 turned this into a HARD DELETE of the admin's user
//     account (it used to null `salon_id` and leave the row alive) and
//     narrowed the caller to `SALON_OWNER`. Both staff-removal endpoints hard-
//     delete now; there is no surviving "admin only unassigns" distinction.
//   • [StaffSettings.rotate]      → `PATCH  /salons/{salonId}/admins/{userId}/salon`
//   • [siblingSalons]             → `GET    /salons/{salonId}/sibling-salons`
//
// SHAPE — mirrors `InviteStaff` (`invite_staff_notifier.dart`), not
// `SalonManagementProfile`: there is nothing for this notifier to LOAD, so
// `build()` is a no-op and both mutations return `Future<Failure?>` (null on
// success). That keeps the failure on the calling screen, which is the only
// place that can turn a 403 into the right sentence — a self-removal and a
// cross-owner rotation are both 403s and they mean completely different
// things to the person reading them.
//
// WHAT THIS NOTIFIER DELIBERATELY DOES NOT DO
//
//   * It does NOT invalidate the staff roster itself. The invalidation has to
//     happen while the SCREEN's element is still mounted and BEFORE it pops
//     (the `InviteStaffScreen._submit` precedent), and the screen also owns
//     the tab reconciliation that goes with it. Doing half of that here and
//     half there is how the two drift apart.
//   * It does NOT re-check authorization. Self-removal and cross-owner
//     rotation are gated by the backend; re-implementing either client-side
//     would be a second, silently-divergent copy of the rule (see
//     `SalonManagementProfile.deleteSalon`'s identical note).
//
// LIFECYCLE — both methods touch `ref` ONLY before their own `await`
// (`ref.read(salonRepositoryProvider)` resolves first), so an autoDispose
// element torn down mid-request cannot reproduce `RegisterSalon.submit`'s
// `UnmountedRefException`. The screens still guard their own `mounted` after
// the await, because they navigate and show snacks.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';

import '../data/salon_repository.dart';

part 'admin_settings_notifier.g.dart';

/// The rotate-admin destination list for [salonId] — the ACTIVE salons
/// sharing this salon's owner, minus this salon.
///
/// Generated provider name: `siblingSalonsProvider` (a family — call it with
/// the SOURCE salon id, e.g. `siblingSalonsProvider(salonId)`).
///
/// Deliberately NOT `mySalonsProvider`: `GET /salons/mine` is owner-only and
/// 403s for the `SALON_ADMIN` who may equally be doing the rotating. This is
/// the endpoint backend Phase 21.3b added for exactly that reason — see
/// [SalonRepository.getSiblingSalons].
///
/// `autoDispose` (the `@riverpod` default): the picker is a pushed page, and
/// an owner who adds or closes a salon between two visits must not be shown
/// the list from the first one.
@riverpod
Future<List<SiblingSalonOption>> siblingSalons(Ref ref, String salonId) {
  return ref.read(salonRepositoryProvider).getSiblingSalons(salonId);
}

/// Drives the two administrator actions on [StaffSettingsScreen].
///
/// Generated provider name: `staffSettingsProvider`.
@riverpod
class StaffSettings extends _$StaffSettings {
  @override
  void build() {}

  /// Removes admin [userId] from salon [salonId].
  ///
  /// Returns `null` on success or the [Failure] on error. Backend Phase 299
  /// turned this into a HARD DELETE of the admin's user account (it used to
  /// null `salon_id` and leave the row alive) and narrowed the caller to
  /// `SALON_OWNER` — the calling screen's copy and gating must say/enforce
  /// so, and must NOT claim the account survives.
  Future<Failure?> removeAdmin({
    required String salonId,
    required String userId,
  }) async {
    final SalonRepository repo = ref.read(salonRepositoryProvider);
    try {
      await repo.removeAdmin(salonId: salonId, userId: userId);
      return null;
    } on Failure catch (f) {
      return f;
    }
  }

  /// Removes master [masterId] from salon [salonId] (Phase 307; backend
  /// Phase 297 + 298 via [SalonRepository.removeMaster], Phase 304's client).
  ///
  /// Returns `null` on success or the [Failure] on error. Mirrors
  /// [removeAdmin] exactly — same shape, same "no re-check, no invalidation
  /// here" contract from this file's header — the ONLY difference is which
  /// repository method it calls. [masterId] is the `Master`-row id
  /// (`SalonStaffMember.masterId`), never the roster's `userId`; the caller
  /// (`StaffSettingsScreen._confirmRemoveMaster`) is responsible for passing
  /// the right one — see [SalonRepository.removeMaster]'s own doc for the
  /// D2 trap this exists to avoid.
  Future<Failure?> removeMaster({
    required String salonId,
    required String masterId,
  }) async {
    final SalonRepository repo = ref.read(salonRepositoryProvider);
    try {
      await repo.removeMaster(salonId: salonId, masterId: masterId);
      return null;
    } on Failure catch (f) {
      return f;
    }
  }

  /// Moves admin [userId] from salon [salonId] to [destinationSalonId].
  ///
  /// Returns `null` on success or the [Failure] on error. A destination
  /// owned by somebody else is a server-side 403 — see this file's header
  /// for why that check is not duplicated here.
  Future<Failure?> rotate({
    required String salonId,
    required String userId,
    required String destinationSalonId,
  }) async {
    final SalonRepository repo = ref.read(salonRepositoryProvider);
    try {
      await repo.rotateAdmin(
        salonId: salonId,
        userId: userId,
        destinationSalonId: destinationSalonId,
      );
      return null;
    } on Failure catch (f) {
      return f;
    }
  }
}
