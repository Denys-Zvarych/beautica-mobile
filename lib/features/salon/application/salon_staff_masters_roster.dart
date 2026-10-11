// 2026-10-05 — the STAFF-side master roster: every master of a salon as the
// salon's own management sees it, for the owner/admin surfaces that must not
// lose a column just because a master is not publicly bookable right now.
//
// ## Why not [salonMastersRosterProvider]
//
// That provider reads the PUBLIC `GET /salons/{id}/masters` rail. The backend
// narrows that rail to BOOKABLE masters (a bookable future slot) so a client
// never sees an owner-master who takes no bookings. A staff surface needs the
// opposite: a master whose schedule was cleared still has CONFIRMED bookings
// on the «Записи» board and must keep their column.
//
// ## Why not a new `getSalonStaff` call
//
// REUSE-FIRST: [salonManagementProfileProvider] already reads
// `GET /salons/{id}/staff` (`SalonRepository.getSalonStaff`) — the
// management-scoped roster, masters AND admins — and every staff surface that
// needs this roster already has it mounted (the shell's «Команда» tab, and
// the board itself watches it for its subtitle). Deriving from it costs ZERO
// extra requests, shares its auth-boundary eviction, and inherits its in-place
// patches (a viewer's own new avatar lands in the board header with no
// refetch). Invalidating [salonManagementProfileProvider] refreshes this.
//
// Authorization: `/staff` is owner/admin only. Every consumer is gated by
// `canManageSalonProvider` / the staff route guard, same as the profile.

import 'package:flutter/foundation.dart' show listEquals;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../master/domain/master.dart';
import '../domain/salon_master_summary.dart';
import '../domain/salon_staff_member.dart';
import 'salon_management_profile_notifier.dart';

part 'salon_staff_masters_roster.g.dart';

/// Projects a management staff roster onto the masters it contains, in the
/// backend's order: every [SalonStaffRole.master] entry WITH a master row —
/// the salon's own owner-master included (`masterType: salonOwner`). Admins
/// (no master row) are dropped.
///
/// [SalonStaffMember.masterType] is null only for an unrecognised wire role;
/// it falls back to [MasterType.salonMaster], the same fallback every staff
/// display site uses.
List<SalonMasterSummary> staffMastersOf(List<SalonStaffMember> staff) =>
    List<SalonMasterSummary>.unmodifiable(<SalonMasterSummary>[
      for (final SalonStaffMember m in staff)
        if (m.role == SalonStaffRole.master)
          if (m.masterId case final String masterId)
            SalonMasterSummary(
              masterId: masterId,
              firstName: m.firstName,
              lastName: m.lastName,
              professionalTitle: m.professionalTitle,
              avatarUrl: m.avatarUrl,
              avgRating: m.avgRating,
              reviewCount: m.reviewCount,
              type: m.masterType ?? MasterType.salonMaster,
            ),
    ]);

/// Every master of [salonId] as its management sees it — built from
/// `GET /salons/{id}/staff`, NOT the public (bookable-only) roster.
///
/// Generated provider name: `salonStaffMastersRosterProvider` — a family,
/// call it with the target salon id.
///
/// ## Cold-start cost (accepted, 2026-10-05 audit P2)
///
/// Mounting a consumer COLD — the walk-in wizard opened straight from the
/// «Записи» board's FAB before the «Команда» tab ever built, or a deep link
/// into either — builds [salonManagementProfileProvider], which fetches
/// `GET /salons/{id}` AND `GET /salons/{id}/staff` together. The wizard only
/// needs the latter; the salon read rides along. This is ACCEPTED, not an
/// oversight: the two arrive in one parallel round-trip, the board and the
/// «Команда» tab reuse the same cached pair afterwards, and a dedicated
/// `/staff`-only provider would duplicate the profile's auth-boundary
/// eviction and in-place avatar patches (REUSE-FIRST, file header). Revisit
/// only if the wizard ever becomes reachable without the shell.
///
/// ## Stable identity (2026-10-05 audit P2)
///
/// A class [AsyncNotifier], not a function provider, PURELY so [build] can
/// read its own previous value. [salonManagementProfileProvider] is patched
/// in place for changes this roster never shows — the salon's logo/cover
/// (`patchImage`), an ADMIN's avatar (`patchStaffAvatar`) — and each patch
/// rebuilds this provider. A fresh, content-equal list on every such rebuild
/// would break the `identical()` memos keyed on the roster: the board's
/// `_columnsFor` / `_masterFilterOptions` (`salon_bookings_screen.dart`) and
/// the wizard's `_coveringMasterIds` / `_resolveDerived`
/// (`salon_booking_wizard_steps.dart`). So when the projection is
/// `listEquals` to the previous value ([SalonMasterSummary] is `@freezed`,
/// value-equal), the PREVIOUS list instance is returned instead.
///
/// The loading semantics are unchanged from the function provider this
/// replaced: a parent patch still rebuilds this notifier exactly once, and the
/// transient state between the rebuild starting and `.future` resolving
/// carries the previous value (`copyWithPrevious`), so `.value` readers never
/// lose the roster mid-patch.
@riverpod
class SalonStaffMastersRoster extends _$SalonStaffMastersRoster {
  @override
  Future<List<SalonMasterSummary>> build(String salonId) async {
    // Captured BEFORE the await: on a rebuild `state` carries the previous
    // value until this build completes.
    final List<SalonMasterSummary>? previous = state.value;
    final SalonManagementProfileData data = await ref.watch(
      salonManagementProfileProvider(salonId).future,
    );
    final List<SalonMasterSummary> next = staffMastersOf(data.$2);
    if (previous != null && listEquals(previous, next)) return previous;
    return next;
  }
}
