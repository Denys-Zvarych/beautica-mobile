// Phase 377 (24.4) — the set of service definitions the salon OWNER performs.
//
// Backend 345: a SALON_ADMIN gets 403 on the shared definition PATCH for any
// SALON definition with an ACTIVE assignment on the owner's master row. The
// 403 body is generic, so the app must know the set itself to lock the
// identity fields (name / category / service type) before the admin submits.
//
// Built ONLY from two existing reads: the management roster
// ([salonManagementProfileProvider], member with `MasterType.salonOwner`) and
// the public per-master catalogue (`getMasterServices`), which the backend
// serves as ACTIVE assignments only, unfiltered for a management viewer
// (`ServiceCatalogService.getMasterServices` -> `findByMasterIdAndIsActiveTrue…`).
//
// ERROR / no owner row fail OPEN (the backend still enforces); LOADING is
// `pending` so the edit route never shows an editable form that would 403.

import 'package:beautica_mobile/features/master/domain/master.dart'
    show MasterType;
import 'package:beautica_mobile/features/salon/application/salon_manage_capability.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'owner_performed_services_provider.g.dart';

/// `serviceDefId`s of the ACTIVE assignments on [ownerMasterId]'s row.
/// Auto-disposed; separate from [serviceIdentityLock] so the roster
/// watch and the catalogue read each own their own loading/error state.
@riverpod
Future<Set<String>> ownerMasterServiceDefIds(
  Ref ref,
  String ownerMasterId,
) async {
  final List<MasterService> services = await ref
      .watch(publicServiceRepositoryProvider)
      .getMasterServices(ownerMasterId);
  return <String>{
    for (final MasterService s in services)
      if (s.isActive) s.serviceDefId,
  };
}

/// Whether a salon service's identity (name / category / type) is locked for
/// the viewer. [pending] = not yet known (roster or owner catalogue still
/// loading) — the route shows its loading scaffold rather than an editable
/// form the backend would 403.
enum ServiceIdentityLock { pending, locked, unlocked }

/// Derived lock verdict for [serviceDefId] in [salonId] — the ONE provider the
/// salon-manage edit route watches (phase 377 audit-fix 1).
///
/// * the viewer owns the salon -> [ServiceIdentityLock.unlocked];
/// * roster / owner catalogue still loading -> [ServiceIdentityLock.pending];
/// * roster / owner catalogue ERROR, or no owner row -> `unlocked` (fail-open:
///   the backend still enforces, and the save maps its 403 to the hint);
/// * otherwise `locked` iff the owner performs [serviceDefId].
@riverpod
ServiceIdentityLock serviceIdentityLock(
  Ref ref,
  String salonId,
  String serviceDefId,
) {
  if (ref.watch(viewerOwnsSalonProvider(salonId))) {
    return ServiceIdentityLock.unlocked;
  }
  final AsyncValue<SalonManagementProfileData> roster = ref.watch(
    salonManagementProfileProvider(salonId),
  );
  // A REFRESH (invalidate / mutation) turns AsyncData into an AsyncLoading that
  // still carries the previous value: that is RESOLVED, not pending — treating
  // it as pending would swap a form with unsaved edits for the scaffold. Only a
  // first load with no value is pending. `hasError` (no value) fails open at
  // once, including while the retry policy re-runs a failed read.
  final SalonManagementProfileData? rosterData = roster.hasValue
      ? roster.value
      : null;
  if (rosterData == null) {
    return roster.hasError
        ? ServiceIdentityLock.unlocked
        : ServiceIdentityLock.pending;
  }
  String? ownerMasterId;
  for (final SalonStaffMember member in rosterData.$2) {
    if (member.masterType == MasterType.salonOwner) {
      ownerMasterId = member.masterId;
      break;
    }
  }
  if (ownerMasterId == null || ownerMasterId.isEmpty) {
    return ServiceIdentityLock.unlocked;
  }
  final AsyncValue<Set<String>> defs = ref.watch(
    ownerMasterServiceDefIdsProvider(ownerMasterId),
  );
  final Set<String>? ownerDefs = defs.hasValue ? defs.value : null;
  if (ownerDefs == null) {
    return defs.hasError
        ? ServiceIdentityLock.unlocked
        : ServiceIdentityLock.pending;
  }
  return ownerDefs.contains(serviceDefId)
      ? ServiceIdentityLock.locked
      : ServiceIdentityLock.unlocked;
}
