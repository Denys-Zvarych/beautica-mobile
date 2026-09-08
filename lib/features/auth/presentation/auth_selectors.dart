// Phase 2.4 — Derived auth selectors.
//
// Thin computed providers that shield feature code from needing to unwrap
// AsyncValue<AuthSession> directly. These re-compute only when the auth
// session changes — downstream providers that watch them will not rebuild
// on unrelated state changes.
//
// Both providers use `Ref` (not typed ref variants — deprecated in
// Riverpod 3.x). `.value` is used (not the removed `.valueOrNull`).

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/auth_session.dart';
import '../domain/user.dart';
import '../domain/user_role.dart';
import 'auth_notifier.dart';

part 'auth_selectors.g.dart';

/// Returns the authenticated [User], or `null` when unauthenticated or loading.
///
/// Widgets that only need the user profile (e.g. displaying the avatar) should
/// watch this provider rather than unwrapping [authProvider] themselves.
@riverpod
User? currentUser(Ref ref) {
  final session = ref.watch(authProvider).value;
  return switch (session) {
    Authenticated(:final user) => user,
    _ => null,
  };
}

/// Returns `true` when the user has a valid, settled [Authenticated] session.
///
/// Use this for gating UI elements that require auth (e.g. showing the FAB
/// to create a new service). Route-level gating is handled by the router
/// guard in `routing/auth_redirect.dart` (Phase 2.9).
@riverpod
bool isAuthenticated(Ref ref) {
  final session = ref.watch(authProvider).value;
  return session is Authenticated;
}

/// Returns `true` only when the settled session is [Authenticated] with
/// `role == UserRole.salonOwner`.
///
/// PROMOTED (REUSE-FIRST, mobile-security MEDIUM, swipe-to-delete audit
/// 2026-09) out of three duplicated inline `authProvider.select(...)`
/// blocks that all read the exact same
/// `s.value is Authenticated && (s.value! as Authenticated).user.role ==
/// UserRole.salonOwner` shape:
///   - `MySalonsScreen.build` (swipe-to-delete owner gate)
///   - `SettingsScreen._showDeleteSalonRow`
///   - `SalonSettingsScreen.build` (navigational owner-only group)
///
/// Hardened against Riverpod 3.x's `copyWithPrevious`, which carries a
/// settled `.value` FORWARD through a later `AsyncError` (confirmed against
/// `riverpod 3.1.0` `async_value.dart:873`). Reading `.value` alone — as all
/// three call sites used to — would keep reporting a STALE role during an
/// `AsyncError` that follows an `Authenticated` state, which is harmless for
/// a settings-row visibility toggle but wrong for gating a destructive,
/// irreversible action (swipe-to-delete). This selector explicitly checks
/// [AsyncValue.hasError] first, so an `AsyncError` — even one still carrying
/// a truthy `.value` — always resolves to `false`.
///
/// `AsyncLoading` that carries a previous value forward during a refresh
/// (no error) is NOT excluded here — that matches every pre-existing call
/// site's behaviour verbatim (they never special-cased `isLoading`), and
/// excluding it would be a behavioural change beyond the stale-value fix
/// this promotion is scoped to.
///
/// No `Authenticated → AsyncError` transition exists in [AuthNotifier]
/// today (its producers are `auth_notifier.dart:373`, `:448`, `:605`,
/// `:906`, none of which touch an already-`Authenticated` state), so this is
/// not a currently-reachable bug — it is hardening against the next producer
/// that adds one.
@riverpod
bool isSalonOwner(Ref ref) {
  final AsyncValue<AuthSession> session = ref.watch(authProvider);
  if (session.hasError) return false;
  final AuthSession? value = session.value;
  return value is Authenticated && value.user.role == UserRole.salonOwner;
}

/// Returns `true` only when the settled session is [Authenticated] with
/// `role == UserRole.client`.
///
/// Sibling of [isSalonOwner] — same idiom, same hardening, one role swapped.
/// Added for the CLIENT-only «Видалити акаунт» row on [SettingsScreen]
/// (`DELETE /api/v1/users/me` is CLIENT-only server-side; every other role
/// gets a 403). See [isSalonOwner]'s doc for why `hasError` is checked
/// before `.value` — the same `copyWithPrevious`-staleness hazard applies
/// here: gating a destructive, irreversible action must fail closed on an
/// `AsyncError`, never fall back to a stale settled role.
@riverpod
bool isClient(Ref ref) {
  final AsyncValue<AuthSession> session = ref.watch(authProvider);
  if (session.hasError) return false;
  final AuthSession? value = session.value;
  return value is Authenticated && value.user.role == UserRole.client;
}
