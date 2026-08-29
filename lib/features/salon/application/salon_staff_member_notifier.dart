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

  SalonStaffMember? resolved;
  for (final SalonStaffMember candidate in staff) {
    if (candidate.userId == memberId) {
      resolved = candidate;
      break;
    }
  }
  final SalonStaffMember member = resolved ?? (throw const NotFoundFailure());

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
