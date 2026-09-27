// Phase 13.1 — shared post-login landing dispatch.
//
// Single source of truth for the role → landing-path mapping. Previously this
// switch was duplicated in `login_screen.dart` (post-login `context.go`) and
// `auth_redirect.dart` (the authenticated-on-auth-route gate). Both now call
// [roleHomePath] so the dispatch can never drift.
//
// Pure function: no Flutter, no Riverpod, no side effects — trivially testable.

import '../features/auth/domain/user_role.dart';
import 'route_names.dart';

/// Returns the post-login landing path for [role].
///
///   * [UserRole.client]            → [RouteNames.clientHome] (`/home`, the
///     Phase 13.1 5-tab client shell landing).
///   * [UserRole.independentMaster] → [RouteNames.masterProfile]
///     (`/master/profile`, the Phase 4 master home).
///   * [UserRole.salonOwner]        → [RouteNames.salonHome] (`/salons/home`,
///     the Phase 21.8 Salon Shell landing — a resolver that forwards to the
///     owner's primary salon's shell). Previously [RouteNames.mySalons]
///     (`/salons/mine`, the Phase 21.1 My Salons Hub) — that hub is now
///     reached via the salon settings hub's «Мої салони» row instead (Phase
///     21.8 Step M11), not as the landing itself.
///   * [UserRole.salonAdmin]        → [RouteNames.salonHome] — same shared
///     landing as the owner; the resolver reads `session.user.salonId`
///     synchronously (an admin belongs to exactly one salon) instead of
///     watching `mySalonsProvider`.
///   * [UserRole.salonMaster]       → [RouteNames.salonMasterProfile], the
///     role's own read-only personal-profile surface (`/staff/profile`).
///     Previously fell through the `_` wildcard below and landed on the bare
///     `_Placeholder('home')` — the "blank home" bug. The switch is now
///     EXHAUSTIVE over every [UserRole] value with no wildcard, so a future
///     sixth role is a compile error here rather than another blank page.
String roleHomePath(UserRole role) => switch (role) {
  UserRole.independentMaster => RouteNames.masterProfile,
  UserRole.client => RouteNames.clientHome,
  UserRole.salonOwner => RouteNames.salonHome,
  UserRole.salonAdmin => RouteNames.salonHome,
  UserRole.salonMaster => RouteNames.salonMasterProfile,
};
