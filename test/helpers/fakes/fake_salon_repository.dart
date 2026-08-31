// Shared fake [SalonRepository] for widget tests — promoted (REUSE-FIRST,
// mobile-qa finding, Phase 21.2 audit) out of two near-identical private
// `_FakeSalonRepository` classes that had drifted apart:
//   - `salon_management_profile_screen_test.dart` needed a real
//     [updateSalon] that applies the partial request onto the held [Salon]
//     (so a save round-trip is observable) plus [updateError] injection.
//   - `salon_settings_screen_test.dart` only needed [deleteSalon] with
//     [deleteError] injection; its [updateSalon] was an `UnimplementedError`
//     guard that this screen never exercises.
//
// This single fake supports BOTH: [updateSalon] always applies the diff (the
// settings-screen tests never call it, so the guard's absence changes no
// assertion), and both [updateError] / [deleteError] are available for
// whichever screen's tests need to inject a failure.
//
// [salon] is a required constructor param (no hidden default) — each caller
// passes its own fixture explicitly so assertions that compare against a
// local `_stubSalon` stay obviously correct.
//
// Phase 21.3 — ADDITIVE: [createRequests] records every [SalonCreateDto]
// passed to [create] (previously a bare no-op) and [createError] lets a test
// inject a failure, mirroring [updateError]/[deleteError]'s shape exactly.
// Every pre-existing caller that never sets [createError] sees [create]
// succeed silently, same as before this phase.
//
// Phase 21.4 — ADDITIVE: [inviteRequests] records every `(salonId, email,
// role)` tuple passed to [inviteStaff] and [inviteError] lets a test inject
// a failure, mirroring [createError]'s shape exactly.
//
// Phase 21.11 — ADDITIVE: [pendingInvites] (a growable list, empty by
// default) backs [listPendingInvites]; [cancelInvite] records its
// `(salonId, inviteId)` tuples in [cancelInviteRequests] and removes the
// matching entry on success. [listPendingInvitesError] / [cancelInviteError]
// inject failures, and [cancelInviteGate] blocks a cancel so the in-flight
// row spinner is observable across a real frame. Every pre-existing caller
// passes none of these and sees an empty pending list — the branch both
// consuming screens already render as "no pending block at all".
//
// Phase 21.6 — ADDITIVE: [siblingSalons] (a growable list, empty by default)
// backs [getSiblingSalons]; [removeAdmin]/[rotateAdmin] record their tuples
// and, on success, drop the matching row from [staff] — which is why [staff]
// is now a GROWABLE copy of whatever the caller passed rather than the
// caller's own (possibly `const`) list. Three error slots and three gates
// mirror [cancelInviteError]/[cancelInviteGate] exactly. Every pre-existing
// caller passes none of these: it sees an empty sibling list, an untouched
// roster and no behaviour change at all.

import 'dart:async';

import 'package:beautica_api/beautica_api.dart' show UpdateSalonRequest;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/bookable_master_assignment.dart';
import 'package:beautica_mobile/features/salon/domain/pending_invite.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_portfolio_photo.dart';
import 'package:beautica_mobile/features/salon/domain/salon_review.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/domain/sibling_salon_option.dart';

/// In-memory [SalonRepository] fake for widget tests.
///
/// `updateSalon` APPLIES the partial request onto the held [Salon] (mirroring
/// what the backend does) so a save round-trip is observable by re-reading
/// the screen, and records every [UpdateSalonRequest] sent so the dirty-field
/// diff can be asserted. `deleteSalon` just counts calls unless [deleteError]
/// is set.
class FakeSalonRepository implements SalonRepository {
  FakeSalonRepository({
    required Salon salon,
    this.masters = const <SalonMasterSummary>[],
    List<SalonStaffMember>? staff,
    List<PendingInvite>? pendingInvites,
    List<SiblingSalonOption>? siblingSalons,
  }) : _salon = salon,
       // A GROWABLE copy for the same reason [pendingInvites] takes one.
       siblingSalons = <SiblingSalonOption>[...?siblingSalons],
       // A GROWABLE copy — `cancelInvite` mutates it so a refetch after a
       // cancel observes the removal (the default `const []` of every
       // pre-existing caller would throw on `removeWhere`).
       pendingInvites = <PendingInvite>[...?pendingInvites],
       staff = <SalonStaffMember>[...?staff];

  Salon _salon;
  final List<SalonMasterSummary> masters;

  /// Phase 21.5 — the management-scoped `GET /salons/{salonId}/staff`
  /// roster (masters + admins). Distinct from [masters] (the public
  /// `GET /salons/{salonId}/masters` rail, still used by the CLIENT-facing
  /// public salon profile) — `SalonManagementProfile.build()` reads THIS
  /// field, not [masters].
  ///
  /// GROWABLE as of Phase 21.6: [removeAdmin]/[rotateAdmin] mutate it so a
  /// refetch after either write observes the roster the backend would now
  /// serve. Callers still pass a `const []` literal freely — the constructor
  /// copies it.
  final List<SalonStaffMember> staff;

  final List<UpdateSalonRequest> updateRequests = <UpdateSalonRequest>[];
  final List<SalonCreateDto> createRequests = <SalonCreateDto>[];
  final List<({String salonId, String email, UserRole role})> inviteRequests =
      <({String salonId, String email, UserRole role})>[];

  /// Phase 21.11 — the pending-invite list `listPendingInvites` returns.
  /// Mutable: a successful [cancelInvite] removes the matching entry, so a
  /// later refetch sees what the backend would have.
  final List<PendingInvite> pendingInvites;

  /// Every `(salonId, inviteId)` tuple passed to [cancelInvite].
  final List<({String salonId, String inviteId})> cancelInviteRequests =
      <({String salonId, String inviteId})>[];

  int deleteCalls = 0;
  int listPendingInvitesCalls = 0;
  Failure? updateError;
  Failure? deleteError;
  Failure? createError;
  Failure? inviteError;
  Failure? listPendingInvitesError;
  Failure? cancelInviteError;

  /// When non-null, [cancelInvite] blocks on this until the test completes
  /// it — the only way to observe the in-flight row spinner across a real
  /// frame. Mirrors `invite_staff_screen_test.dart`'s own Completer-gated
  /// notifier precedent.
  Completer<void>? cancelInviteGate;

  // ── Phase 21.6 — admin management (all ADDITIVE) ────────────────────────
  // Every pre-existing caller passes none of these: [siblingSalons] defaults
  // to empty (the "owner has only this salon" branch), the three error slots
  // and the two gates default to null, and the request logs simply stay
  // empty. No existing test observes a behaviour change.

  /// Every `(salonId, userId)` tuple passed to [removeAdmin].
  final List<({String salonId, String userId})> removeAdminRequests =
      <({String salonId, String userId})>[];

  /// Every `(salonId, userId, destinationSalonId)` tuple passed to
  /// [rotateAdmin] — the destination is what a mis-wired picker would get
  /// wrong, so it is recorded rather than merely counted.
  final List<({String salonId, String userId, String destinationSalonId})>
  rotateAdminRequests =
      <({String salonId, String userId, String destinationSalonId})>[];

  /// The rotate-destination list `getSiblingSalons` returns.
  final List<SiblingSalonOption> siblingSalons;

  int siblingSalonsCalls = 0;

  Failure? removeAdminError;
  Failure? rotateAdminError;
  Failure? siblingSalonsError;

  /// Block the corresponding call until the test completes the gate — the
  /// only way to observe an in-flight state across a real frame. Same shape
  /// as [cancelInviteGate].
  Completer<void>? removeAdminGate;
  Completer<void>? rotateAdminGate;
  Completer<void>? siblingSalonsGate;

  @override
  Future<void> create({required SalonCreateDto dto}) async {
    createRequests.add(dto);
    if (createError != null) throw createError!;
  }

  @override
  Future<void> inviteStaff({
    required String salonId,
    required String email,
    required UserRole role,
  }) async {
    inviteRequests.add((salonId: salonId, email: email, role: role));
    if (inviteError != null) throw inviteError!;
  }

  @override
  Future<List<Salon>> getMySalons() async => <Salon>[_salon];

  @override
  Future<Salon> getSalonById(String salonId) async => _salon;

  @override
  Future<List<SalonMasterSummary>> getSalonMasters(String salonId) async =>
      masters;

  /// Phase 21.6 mobile-qa gap-closure — reads of the management roster.
  ///
  /// `AdminSettingsScreen`/`MoveAdminSalonScreen` invalidate
  /// `salonManagementProfileProvider` after a successful write; without a
  /// counter here that invalidation is unobservable at the widget tier (the
  /// screens pop, so "the row is gone" is satisfied by the pop alone).
  int getSalonStaffCalls = 0;

  @override
  Future<List<SalonStaffMember>> getSalonStaff(String salonId) async {
    getSalonStaffCalls++;
    return List<SalonStaffMember>.unmodifiable(staff);
  }

  @override
  Future<List<SalonServiceCategoryEntry>> getSalonServiceCatalog(
    String salonId,
  ) async => const <SalonServiceCategoryEntry>[];

  @override
  Future<SalonReviewSummary> getSalonReviewSummary(String salonId) async =>
      const SalonReviewSummary();

  @override
  Future<List<SalonReviewItem>> getSalonReviews({
    required String salonId,
    required SalonReviewSort sort,
    int page = 0,
    int size = kSalonReviewsPageSize,
  }) async => const <SalonReviewItem>[];

  @override
  Future<List<SalonPortfolioPhoto>> getSalonPortfolio(String salonId) async =>
      const <SalonPortfolioPhoto>[];

  @override
  Future<List<BookableMasterAssignment>> getBookableMasters({
    required String salonId,
    required String serviceDefId,
  }) async => const <BookableMasterAssignment>[];

  @override
  Future<Salon> updateSalon(String salonId, UpdateSalonRequest request) async {
    updateRequests.add(request);
    if (updateError != null) throw updateError!;
    _salon = _salon.copyWith(
      name: request.name ?? _salon.name,
      description: request.description ?? _salon.description,
      phone: request.phone ?? _salon.phone,
      instagramUrl: request.instagramUrl ?? _salon.instagramUrl,
      // Phase 21.10 — additive: the address/contacts edit-form tests also
      // need street/buildingNo/cityId/districtId/locationNote applied so a
      // save round-trip is observable, mirroring the four fields above.
      street: request.street.isNotEmpty ? request.street : _salon.street,
      buildingNo: request.buildingNo.isNotEmpty
          ? request.buildingNo
          : _salon.buildingNo,
      cityId: request.cityId ?? _salon.cityId,
      districtId: request.districtId ?? _salon.districtId,
      locationNote: request.locationNote ?? _salon.locationNote,
    );
    return _salon;
  }

  @override
  Future<void> deleteSalon(String salonId) async {
    deleteCalls++;
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<List<PendingInvite>> listPendingInvites(String salonId) async {
    listPendingInvitesCalls++;
    if (listPendingInvitesError != null) throw listPendingInvitesError!;
    return List<PendingInvite>.unmodifiable(pendingInvites);
  }

  @override
  Future<void> cancelInvite({
    required String salonId,
    required String inviteId,
  }) async {
    cancelInviteRequests.add((salonId: salonId, inviteId: inviteId));
    final Completer<void>? gate = cancelInviteGate;
    if (gate != null) await gate.future;
    if (cancelInviteError != null) throw cancelInviteError!;
    pendingInvites.removeWhere((PendingInvite i) => i.inviteId == inviteId);
  }

  @override
  Future<void> removeAdmin({
    required String salonId,
    required String userId,
  }) async {
    removeAdminRequests.add((salonId: salonId, userId: userId));
    final Completer<void>? gate = removeAdminGate;
    if (gate != null) await gate.future;
    if (removeAdminError != null) throw removeAdminError!;
    // Mirror the backend: the roster row is unassigned, so a refetch of
    // `getSalonStaff` no longer lists them.
    staff.removeWhere((SalonStaffMember m) => m.userId == userId);
  }

  @override
  Future<void> rotateAdmin({
    required String salonId,
    required String userId,
    required String destinationSalonId,
  }) async {
    rotateAdminRequests.add((
      salonId: salonId,
      userId: userId,
      destinationSalonId: destinationSalonId,
    ));
    final Completer<void>? gate = rotateAdminGate;
    if (gate != null) await gate.future;
    if (rotateAdminError != null) throw rotateAdminError!;
    // The admin now belongs to the DESTINATION salon, so the source salon's
    // roster no longer lists them — same observable effect as removeAdmin
    // from this salon's point of view.
    staff.removeWhere((SalonStaffMember m) => m.userId == userId);
  }

  @override
  Future<List<SiblingSalonOption>> getSiblingSalons(String salonId) async {
    siblingSalonsCalls++;
    if (siblingSalonsError != null) throw siblingSalonsError!;
    final Completer<void>? gate = siblingSalonsGate;
    if (gate != null) await gate.future;
    return List<SiblingSalonOption>.unmodifiable(siblingSalons);
  }
}
