// CLIENT edit-profile AsyncNotifier.
//
// Loads and caches the authenticated CLIENT's FULL [User] profile (including the
// location fields the home-hub summary does not carry) via
// [ClientProfileRepository.getMyProfile] (`GET /users/me`). The three client
// edit screens (Personal / Contacts / Location) watch this notifier so they all
// seed their fields from one cached source and merge their slice onto it on save
// — exactly the role the [masterProfileProvider] plays for the master edit
// screens.
//
// [keepAlive: true] mirrors [masterProfileProvider]: the cached profile is read
// by every edit screen, so disposing + refetching on each navigation would waste
// bandwidth. Each edit screen calls `ref.invalidate(clientEditProfileProvider)`
// after a successful save to force a re-fetch.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../salon/application/salon_management_profile_notifier.dart';
import '../data/client_profile_repository.dart';
import 'home_hub_notifier.dart';

part 'client_edit_profile_notifier.g.dart';

/// Loads and caches the authenticated CLIENT's own full [User] profile.
///
/// Generated provider name: `clientEditProfileProvider`.
@Riverpod(keepAlive: true)
class ClientEditProfile extends _$ClientEditProfile {
  @override
  Future<User> build() {
    // NARROWED with `.select` (mobile-perf MEDIUM follow-through, 2026-08-31)
    // — the same fix, for the same reason, as `master_profile_notifier.dart`'s
    // own `build()`. `AuthNotifier.setAccessToken` re-emits `Authenticated`
    // with a new accessToken on EVERY silent token refresh; watching the whole
    // `AsyncValue<AuthSession>` refetched `GET /users/me` each time. Narrowing
    // only `masterProfileProvider` would have closed half the leak: this
    // provider is the OTHER upstream of `ownerOwnProfileProvider`, so a silent
    // refresh would still have re-run that loader (and its uncached
    // `GET /masters/{id}/services`) while the owner sat on another tab.
    //
    // The selector itself was PROMOTED to [authUserIdOrNull] (2026-09-01) —
    // see its doc for why there is one definition rather than a copy per site.
    final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
    if (userId == null) {
      throw const UnauthorizedFailure();
    }
    // clientProfileRepositoryProvider is a keepAlive singleton that never emits
    // a new value — ref.read is correct for a one-shot async fetch.
    return ref.read(clientProfileRepositoryProvider).getMyProfile();
  }
}

/// Phase 356 — the shared post-save refresh both `ClientPersonalInfoEditScreen`
/// and `ClientContactsEditScreen` call, extracted from what used to be each
/// screen's own two-line `ref.invalidate` pair so a THIRD caller (the
/// SALON_ADMIN own-profile settings hub, which reuses both screens verbatim —
/// see `route_names.dart`'s `adminEditPersonal`/`adminEditContacts` docs) gets
/// the same refresh without copying it a third time.
///
/// Invalidates:
///   * [clientEditProfileProvider] — the cached seed both edit screens read
///     from (re-fetches `GET /users/me` on next watch).
///   * [clientProfileProvider] — the CLIENT home-hub summary derived from the
///     same identity (a no-op invalidate for a non-CLIENT caller: nothing
///     watches it outside the CLIENT home hub).
///   * [salonManagementProfileProvider], SCOPED to the caller's own salon —
///     an admin's own row on the salon roster «Команда» (`salon_management_
///     profile_notifier.dart`). It is `autoDispose`, but `SalonShellScreen`
///     keeps slot 0 warm for the lifetime of the shell, so without this the
///     roster would keep showing the pre-edit name/photo after a save. A
///     no-op for a CLIENT caller — nothing in that role's tree watches a
///     salon management family member, and `User.salonId` is always null for
///     that role (see below).
///
///     mobile-perf LOW follow-up (audit-fix cycle 1, 2026-09-26) — this used
///     to be a BARE `ref.invalidate(salonManagementProfileProvider)` (the
///     WHOLE family, every salonId any screen in this session ever warmed),
///     the one outlier against every other call site of this exact family,
///     which all scope by salonId (`staff_settings_screen.dart:427/495`,
///     `move_admin_salon_screen.dart:173`). Fixed to invalidate only the
///     caller's own keyed element. The salonId is DERIVED here rather than
///     threaded as a param onto either client editor screen — both are
///     reused VERBATIM by SALON_ADMIN (see this file's own header doc), and
///     adding a required param to either would break that reuse. The
///     derivation mirrors the ONE place this codebase already keys this
///     family off the signed-in admin's OWN identity rather than a route
///     param: `AdminOwnProfileScreen`'s `_AdminProfileBody` reads
///     `admin.salonId` (`User.salonId`) as its `selfKey` fallback
///     (`admin_own_profile_screen.dart:465`) — [authUserSalonIdSettledOrNull]
///     (`auth_notifier.dart`) is the STRICT, already-existing selector for
///     that exact field, gated on a settled (non-loading, non-error)
///     `Authenticated` session so a mid-refresh/mid-logout stale value can
///     never leak through. A CLIENT's `User.salonId` is always null (the
///     field is salon-role-only), so the invalidate is skipped entirely for
///     that role — there is no salon-scoped family element to target.
void invalidateOwnIdentity(WidgetRef ref) {
  // cycle-safe: this is a free function called from a SCREEN's WidgetRef
  // after a save resolves, never from inside a Notifier's own build/method —
  // there is no back-edge for any of the three targets below to close.
  // cycle-safe: ClientEditProfile.build() only reads authProvider +
  // clientProfileRepositoryProvider — neither watches this provider back.
  ref.invalidate(clientEditProfileProvider);
  // cycle-safe: ClientProfile (home_hub_notifier.dart) derives from the
  // CLIENT session/repository layer, not from clientEditProfileProvider —
  // no back-edge.
  ref.invalidate(clientProfileProvider);
  // mobile-perf LOW (audit-fix cycle 1, 2026-09-26) — scoped by salonId, not
  // a bare family invalidate; see the doc above for why this specific
  // derivation is safe and additive. `ref.read`, not `ref.watch`: this is a
  // one-shot post-save read of the CURRENT session, exactly like
  // `ClientEditProfile.build()`'s own `ref.read(clientProfileRepositoryProvider)`
  // above — this free function has no `build()` of its own to re-run.
  final String? salonId = authUserSalonIdSettledOrNull(
    ref.read(authProvider),
  )?.trim();
  if (salonId != null && salonId.isNotEmpty) {
    // cycle-safe: SalonManagementProfile.build() reads authProvider +
    // salonRepositoryProvider — it has no dependency on
    // clientEditProfileProvider or on this free function's caller, so
    // invalidating it here (now keyed on the caller's own salonId, not the
    // whole family) closes no cycle.
    ref.invalidate(salonManagementProfileProvider(salonId));
  }
}
