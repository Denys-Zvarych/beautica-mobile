// Phase 322 (D1/D4) — the single salon-scoped "can this viewer manage this
// salon" predicate.
//
// PROMOTED (REUSE-FIRST) from `schedule_capability.dart`'s private
// `_managesSalon` — Phase 312 (D8) needed the exact same fact ("does the
// caller manage THIS salon") for its owner/admin schedule-edit arm, and
// wrote it as a private, unexported helper. Being private was not a licence
// to duplicate: this phase needs the identical fact for service-management
// affordances, so the helper is promoted here — moved to a shared file, the
// leading `_` dropped, `schedule_capability.dart` rewired onto THIS
// provider instead of its own private copy (see that file's own note) — so
// the two sides can never drift apart the way `_selectRailDay` once did.
//
// Mirrors backend phase 306 D1 verbatim: "An actor may manage a service
// definition iff the definition is salon-owned and the actor has management
// access to that salon (owner or admin of it) ... Management access, not
// role." `true` iff:
//   * SALON_ADMIN whose OWN `salonId` ([authUserSalonIdSettledOrNull])
//     equals [salonId] EXACTLY — an admin of salon B does NOT manage salon
//     A (D4 — this is the salon-scoping a bare `role == salonAdmin` check
//     would be missing, and mutation check 2 exists to prove it);
//   * SALON_OWNER whose resolved [mySalonsProvider] list contains [salonId];
//   * any other role (SALON_MASTER, INDEPENDENT_MASTER, CLIENT), or an
//     unresolved/unauthenticated/errored session → `false` (fail-closed —
//     D3: no guard built from this predicate ever admits SALON_MASTER).
//
// Uses the STRICT `...SettledOrNull` selectors (never [AsyncValue.value]'s
// lenient unwrap) — this predicate gates MUTATION affordances (add/remove a
// service), not a nav-target pick, so it must resolve `false` the instant
// the session is not a settled, authenticated `AsyncData` rather than ride a
// Riverpod `copyWithPrevious`-attached stale value forward through a later
// `AsyncLoading`/`AsyncError` (see [authUserRoleSettledOrNull]'s own doc for
// the full mechanism this guards against).
//
// Reads [mySalonsProvider] gated on the concrete `AsyncData` SUBTYPE, never
// a bare `.value` — same reasoning, and the same shape `salonManageGuard`
// (`app_router.dart`) and `_ownerOrAdminCanEdit`'s own former private copy
// both already used: an unresolved/errored `mySalonsProvider` must NOT be
// treated as "owns nothing" silently passing through a stale list, it is
// deliberately excluded from the "any" check by the subtype gate itself.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../domain/salon.dart';
import 'my_salons_notifier.dart';

part 'salon_manage_capability.g.dart';

/// `true` only when the current viewer manages [salonId] — as
/// [SALON_OWNER] (via [mySalonsProvider]) or as [SALON_ADMIN] of exactly
/// this salon (via `User.salonId`). See this file's header for the full
/// contract. Generated provider name: `canManageSalonProvider` (a family —
/// call `canManageSalonProvider(salonId)`).
@riverpod
bool canManageSalon(Ref ref, String salonId) {
  final UserRole? role = ref.watch(
    authProvider.select(authUserRoleSettledOrNull),
  );
  if (role == UserRole.salonAdmin) {
    final String? myAdminSalonId = ref.watch(
      authProvider.select(authUserSalonIdSettledOrNull),
    );
    return myAdminSalonId != null && myAdminSalonId == salonId;
  }
  if (role == UserRole.salonOwner) {
    final AsyncValue<List<Salon>> mySalons = ref.watch(mySalonsProvider);
    if (mySalons is! AsyncData<List<Salon>>) return false;
    return mySalons.value.any((Salon salon) => salon.id == salonId);
  }
  // Fail CLOSED for every other role/session shape — SALON_MASTER (D3),
  // INDEPENDENT_MASTER, CLIENT, and an unresolved/unauthenticated session
  // all resolve to "cannot manage".
  return false;
}
