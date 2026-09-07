// Phase 15.2 — Schedule edit-capability resolver (OQ-2 role gating).
// Phase 312 — became MEMBERSHIP-AWARE (D8): takes the viewed [ScheduleScope]
// and, for a SALON_OWNER/SALON_ADMIN, verifies the viewed master actually
// belongs to a salon the caller manages, instead of returning an
// unconditional `true` for that role pair. THIS IS A SECURITY-RELEVANT
// CHANGE — see the header note below and `master_schedule_screen.dart` /
// `weekly_template_editor_screen.dart` / `day_hours_sheet.dart` /
// `apply_schedule_sheet.dart` for the eight call sites this gates.
//
// Resolves whether the current viewer may EDIT the schedule they are viewing,
// from the auth/role state (plus, for the owner/admin arm, server-derived
// salon-membership facts). The schedule screen gates every edit affordance
// (Редагувати, day pencil, + Додати час, + Time Off, copy/propagate, and the
// NO_SCHEDULE CTA) on this capability so a read-only role never sees an edit
// entry point — client-side, not relying on a backend 403 alone.
//
// MVP scope (ARCHITECTURE-mobile § 4 — INDEPENDENT_MASTER first):
//   • INDEPENDENT_MASTER (viewing own scope)                → editable.
//   • SALON_OWNER / SALON_ADMIN (viewing a master ON THEIR
//     OWN salon's roster — [ScheduleScope.salonMaster])     → editable (D2).
//   • SALON_MASTER (viewing own scope, read-only role)      → read-only.
//   • CLIENT / loading / unauthenticated                    → read-only
//     (defensive: a CLIENT never reaches this screen, but defaulting to
//     read-only keeps the gate fail-safe).
//   • ANY role viewing a [ScheduleScope.salonMaster] that is NOT proven to
//     belong to a salon the caller manages, or whose viewed master is not
//     proven to be on that salon's roster → read-only. Fail-closed, never
//     "trust the route's `:salonId`" — see [_ownerOrAdminCanEdit]'s doc.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../salon/application/my_salons_notifier.dart';
import '../../salon/application/salon_management_profile_notifier.dart';
import '../../salon/domain/salon.dart';
import '../../salon/domain/salon_staff_member.dart';
import '../domain/schedule_scope.dart';

part 'schedule_capability.g.dart';

/// `true` when the current viewer may edit the schedule on screen (Phase 312:
/// the schedule identified by [scope]).
///
/// Read-only resolves to `false` for SALON_MASTER (and defensively for any
/// non-master / unresolved session). Generated provider name:
/// `scheduleEditableProvider` (a family — call
/// `scheduleEditableProvider(scope)`).
///
/// Watches through [authUserRoleSettledOrNull] — the STRICT selector, not
/// [authUserRoleOrNull] (mobile-security MEDIUM, phase 309–311 track,
/// 2026-09-06). This provider is the WRITE-GATE for schedule mutation (every
/// edit affordance across `MasterScheduleScreen`,
/// `WeeklyTemplateEditorScreen`, `DayHoursSheet` and `ApplyScheduleSheet`
/// gates on it), so it must resolve read-only — not "whatever the last known
/// role was" — the instant the session is anything other than a settled,
/// authenticated `AsyncData`. A bare `.value` read (the lenient unwrap
/// [authUserRoleOrNull] deliberately uses for nav-target picks) would let a
/// STALE `Authenticated` ride a later `AsyncLoading`/`AsyncError` via
/// Riverpod's automatic `copyWithPrevious` and keep granting edit access
/// after the session it was granted for is no longer definitely valid — see
/// [authUserRoleSettledOrNull]'s doc comment for the full reasoning and why
/// the two selectors must NOT be collapsed into one.
///
/// Selecting on the role (rather than watching `authProvider` un-narrowed)
/// also keeps this provider silent across a silent token refresh —
/// `AuthNotifier.setAccessToken` emits a new `AsyncData(Authenticated(...))`
/// on every refresh (same user, new `accessToken`, which is part of
/// `Authenticated`'s `@freezed` equality) — see [authUserRoleOrNull]'s doc
/// comment (mobile-perf MEDIUM, 2026-09-06) for the measurement. Un-narrowing
/// this watch would reintroduce that churn on the four screens above.
///
/// Stays a plain SYNC `bool` (Phase 312, D8) rather than an `AsyncValue<bool>`
/// — the owner/admin membership check below reads two ALREADY-RESOLVED
/// provider states rather than awaiting anything, so wrapping the return type
/// would ripple through every one of the eight existing `ref.watch`/`ref.read`
/// call sites for no benefit.
@riverpod
bool scheduleEditable(Ref ref, ScheduleScope scope) {
  final role = ref.watch(authProvider.select(authUserRoleSettledOrNull));
  return switch (role) {
    UserRole.independentMaster => scope is OwnScheduleScope,
    UserRole.salonOwner ||
    UserRole.salonAdmin => _ownerOrAdminCanEdit(ref, scope),
    UserRole.salonMaster || UserRole.client || null => false,
  };
}

/// The owner/admin arm of [scheduleEditable] (Phase 312, D8) — the ONE
/// unconditional `true` this phase's brief calls out as WRONG the moment a
/// schedule screen becomes reachable for these two roles: "may edit whatever
/// schedule is on screen", with no proof the viewed master belongs to a salon
/// the caller manages.
///
/// `scope is! SalonMasterScheduleScope` → `false` immediately: an
/// owner/admin has no "own" master row this feature ever constructs a scope
/// for (`own_schedule_scope.dart`'s OQ-4 refusal), so any OTHER scope shape
/// reaching here is already a bug upstream — fail closed rather than trust
/// it.
///
/// Otherwise this is the AND of two server-derived, ALREADY-RESOLVED facts,
/// each gated on the concrete `AsyncData` SUBTYPE (never `value == null`,
/// never `hasError` — `AsyncLoading(retrying: true)` satisfies `hasError`
/// without meaning failure, and a bare `.value` read tolerates a
/// `copyWithPrevious`-attached STALE value exactly like
/// [authUserRoleSettledOrNull]'s own doc warns against):
///
///   1. The caller manages [SalonMasterScheduleScope.salonId] — admin via
///      [authUserSalonIdSettledOrNull] (a strict, non-churning selector —
///      see that function's own doc for why a bare `ref.watch(authProvider)`
///      is not used here), owner via [mySalonsProvider] containing the id,
///      reusing `app_router.dart`'s `salonManageGuard` owner arm's EXACT
///      gate (`AsyncData<List<Salon>>` subtype check, then `.any(id ==)`).
///   2. The viewed master is actually ON that salon's roster —
///      [salonManagementProfileProvider]'s resolved roster contains an entry
///      whose [SalonStaffMember.masterId] equals [SalonMasterScheduleScope
///      .masterId] with [SalonStaffMember.role] == [SalonStaffRole.master].
///      This is the part [SalonMasterScheduleScope.salonId] alone CANNOT
///      prove: the route's `:salonId` only PROPOSES a salon, and
///      [salonManagementProfileProvider]'s own backend read is already gated
///      on `canManageSalon` — reusing it here is how this provider gets real
///      roster proof for free, with no new network call.
///
///      NOT [salonStaffMemberProfileProvider] — that family is keyed on the
///      roster row's `userId`, a DIFFERENT id than [ScheduleScope.masterId]
///      (the Master-row UUID; see `salon_staff_member.dart`'s header for why
///      the two never coincide). [ScheduleScope.salonMaster] never carries a
///      `userId` at all, so this scans [salonManagementProfileProvider]'s
///      roster by `masterId` directly instead.
bool _ownerOrAdminCanEdit(Ref ref, ScheduleScope scope) {
  if (scope is! SalonMasterScheduleScope) return false;

  final bool managesSalon = _managesSalon(ref, scope.salonId);
  if (!managesSalon) return false;

  final AsyncValue<SalonManagementProfileData> rosterAsync = ref.watch(
    salonManagementProfileProvider(scope.salonId),
  );
  if (rosterAsync is! AsyncData<SalonManagementProfileData>) return false;
  final List<SalonStaffMember> roster = rosterAsync.value.$2;
  return roster.any(
    (SalonStaffMember member) =>
        member.masterId == scope.masterId &&
        member.role == SalonStaffRole.master,
  );
}

/// Fact 1 of [_ownerOrAdminCanEdit] — "does the caller manage [salonId]" —
/// factored out so its two role arms (admin / owner) each read exactly one
/// already-resolved provider, mirroring `salonManageGuard`'s own shape
/// (`app_router.dart:305-368`) as closely as a `Ref`-based provider can (that
/// guard runs as a synchronous `GoRouterState` redirect and cannot itself be
/// called from here).
bool _managesSalon(Ref ref, String salonId) {
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
  // Fail CLOSED. `_managesSalon` is only ever reached from the
  // salonOwner/salonAdmin arm of [scheduleEditable], so this is unreachable
  // today — but a future role added to that arm without a branch here must
  // be DENIED, never admitted by default. (Reverted 2026-09-07: a mutation
  // artifact `return true` was left live in the tree by an interrupted
  // mutation-testing pass, which admitted any unrecognized role.)
  return false;
}
