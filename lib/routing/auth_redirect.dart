// Phase 2.9 — Auth redirect guard (real implementation).
//
// Pure function: takes the current [AsyncValue<AuthSession>] and the
// [GoRouterState], returns either a redirect path or null to stay on the
// current location.
//
// Rules:
//   isLoading → park on /splash; redirect all other locations to /splash.
//   Unauthenticated + not on an auth route → redirect to /login.
//   Unauthenticated on /splash (session settled) → redirect to /login.
//   Authenticated + on an auth route (login/register/splash) → redirect to /.
//   Otherwise → null (stay).
//
// Auth routes = /login, /register. /splash is NOT an auth route — it is only
// valid while session.isLoading is true. Once the session settles, any
// unauthenticated user still on /splash must be forwarded to /login.
//
// Testable without a widget tree: the function is pure and has no side effects.
// See test/routing/auth_redirect_test.dart.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'route_names.dart';

/// Pure guard function wired into [GoRouter.redirect].
///
/// Returns the redirect target path, or null to allow navigation to proceed.
///
/// [session] is the current value of [authProvider].
/// [state] is the [GoRouterState] provided by [GoRouter].
String? authRedirect(AsyncValue<AuthSession> session, GoRouterState state) {
  final location = state.matchedLocation;

  // While the session is resolving (cold-start), park on the splash screen.
  if (session.isLoading) {
    return location == RouteNames.splash ? null : RouteNames.splash;
  }

  final isAuthenticated = session.value is Authenticated;

  // Routes where an unauthenticated user may remain once session has settled.
  // /splash is NOT included — it is only valid while session.isLoading is true.
  // /verification and /done are part of the registration flow and are reachable
  // before the session is established (the OTP step precedes a valid session).
  final isAtAuthRoute =
      location == RouteNames.login ||
      location == RouteNames.register ||
      location == RouteNames.verification ||
      location == RouteNames.done;

  final isAtSplash = location == RouteNames.splash;

  // Settled unauthenticated user anywhere (including /splash) → /login.
  if (!isAuthenticated && (!isAtAuthRoute || isAtSplash)) {
    return RouteNames.login;
  }

  // Authenticated user sitting on an auth-only route or splash → send to home.
  if (isAuthenticated && (isAtAuthRoute || isAtSplash)) return RouteNames.home;

  // No redirect needed.
  return null;
}
