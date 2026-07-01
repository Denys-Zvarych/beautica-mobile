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
///   * every other role             → [RouteNames.home] (`/`, the home shell
///     "coming soon" surface).
String roleHomePath(UserRole role) => switch (role) {
  UserRole.independentMaster => RouteNames.masterProfile,
  UserRole.client => RouteNames.clientHome,
  _ => RouteNames.home,
};
