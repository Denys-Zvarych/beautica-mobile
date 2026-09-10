// Phase 21.5 — Salon staff member (master OR admin) management profile
// loader.
//
// A `@riverpod` family keyed on `(salonId, memberId)`. Rather than issuing
// its own `GET /salons/{salonId}/staff` round trip, it `ref.watch`es the
// ALREADY-CACHED [salonManagementProfileProvider] (the same roster the
// «Персонал» grid tab already resolved) and selects the entry by [memberId]
// (the roster row's `userId`) — an in-app navigation from a grid card tap
// costs no extra round trip. A cold deep link simply triggers the parent
// provider's own fetch, exactly as if the viewer had opened the «Персонал»
// tab directly.
//
// For a MASTER entry, the master's active services are additionally fetched
// (the same `getMasterServices` call `public_master_profile_notifier.dart`
// makes) so the screen can render the read-only service-categories section.
// An ADMIN entry never has a [SalonStaffMember.masterId] to fetch services
// for, so [SalonStaffMemberProfileData.services] is always empty for one.
//
// Throws [NotFoundFailure] when [memberId] is absent from the resolved
// roster (e.g. a stale deep link to a removed staff member) — an EXISTING
// [Failure] subtype, not a new one (see `core/errors/failures.dart`'s
// cardinality ledger in `test/core/`).

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';

import '../../services/data/service_repository.dart';
import '../../services/domain/master_service.dart';
import '../domain/salon.dart';
import '../domain/salon_staff_member.dart';
import 'salon_management_profile_notifier.dart';

part 'salon_staff_member_notifier.g.dart';

/// The data the staff member management profile screen renders: the roster
/// entry (master or admin) paired with the master's active services (always
/// empty for an admin entry).
typedef SalonStaffMemberProfileData = (
  SalonStaffMember member,
  List<MasterService> services,
);

/// Finds the roster entry whose [SalonStaffMember.userId] is [memberId],
/// or `null` when the roster carries no such entry (a stale deep link to a
/// removed staff member).
///
/// PROMOTED out of [salonStaffMemberProfile]'s body (phase 317 audit F2) so
/// the two ROUTE BUILDERS that need only the member — `app_router.dart`'s
/// `_SalonMasterServicesShell` and `_SalonMasterScheduleRoute`, both of which
/// want nothing but [SalonStaffMember.masterId] — can resolve it straight off
/// the already-cached [salonManagementProfileProvider] roster instead of
/// awaiting this provider, whose extra `getMasterServices` round trip they
/// fetch, retain for the subtree's lifetime and never read. REUSE-FIRST: one
/// scan, three call sites, no forked copy of the `userId ==` predicate.
///
/// Pure and synchronous — it is NOT a provider, so it adds no element to the
/// graph and nothing to phase 317's `dependencies:` cascade.
SalonStaffMember? findSalonStaffMember(
  List<SalonStaffMember> staff,
  String memberId,
) {
  for (final SalonStaffMember candidate in staff) {
    if (candidate.userId == memberId) {
      return candidate;
    }
  }
  return null;
}

/// Loads the staff roster entry [memberId] of salon [salonId], plus the
/// master's active services when [memberId] resolves to a master.
///
/// Generated provider name: `salonStaffMemberProfileProvider` (a family —
/// call it with `(salonId, memberId)`, e.g.
/// `salonStaffMemberProfileProvider(salonId, memberId)`).
@riverpod
Future<SalonStaffMemberProfileData> salonStaffMemberProfile(
  Ref ref,
  String salonId,
  String memberId,
) async {
  final (Salon _, List<SalonStaffMember> staff) = await ref.watch(
    salonManagementProfileProvider(salonId).future,
  );

  final SalonStaffMember member =
      findSalonStaffMember(staff, memberId) ?? (throw const NotFoundFailure());

  final String? masterId = member.masterId;
  if (member.role != SalonStaffRole.master ||
      masterId == null ||
      masterId.isEmpty) {
    return (member, const <MasterService>[]);
  }

  final ServiceRepository serviceRepo = ref.read(
    publicServiceRepositoryProvider,
  );
  final List<MasterService> services = await serviceRepo.getMasterServices(
    masterId,
  );
  return (member, services);
}
