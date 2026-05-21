// Phase 2.9 — Auth redirect guard (real implementation).
//
// Pure function: takes the current [AsyncValue<AuthSession>] and the
// [GoRouterState], returns either a redirect path or null to stay on the
// current location.
//
// Rules:
//   isLoading → redirect to /login (F4 corrected design — the AsyncLoading
//     window now lasts microseconds, so /login is the right "neutral" landing
//     pad and avoids a visible /splash flash on cold start).
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
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'route_names.dart';

/// Pure guard function wired into [GoRouter.redirect].
///
/// Returns the redirect target path, or null to allow navigation to proceed.
///
/// [session] is the current value of [authProvider].
/// [state] is the [GoRouterState] provided by [GoRouter].
///
/// Thin adapter over [authRedirectForLocation] — it extracts
/// [GoRouterState.matchedLocation] and delegates all decision logic. The split
/// exists because [GoRouterState] has an internal constructor (it requires a
/// [RouteConfiguration] that is not publicly constructible), so the pure
/// decision logic cannot be unit-tested through this signature without standing
/// up a full widget tree. See test/routing/auth_redirect_test.dart.
String? authRedirect(AsyncValue<AuthSession> session, GoRouterState state) =>
    authRedirectForLocation(session, state.matchedLocation);

/// Pure redirect decision over the resolved [location] string.
///
/// This is the single source of truth for the auth redirect matrix. [authRedirect]
/// delegates to it after extracting the location from [GoRouterState], and tests
/// exercise it directly (no GoRouterState construction needed).
///
/// Returns the redirect target path, or null to allow navigation to proceed.
@visibleForTesting
String? authRedirectForLocation(
  AsyncValue<AuthSession> session,
  String location,
) {
  // Post-registration routes — reachable by BOTH unauthenticated users (the
  // verification-required backend flow: register() leaves the session
  // Unauthenticated and the OTP step precedes a valid session) AND just-
  // authenticated-but-unverified users (the auto-login register flow: register()
  // returns an Authenticated session yet the user must still complete email
  // verification). Critically, an Authenticated user on these routes must NOT be
  // bounced to /home — that bounce is exactly the bug that prevented a CLIENT
  // who taps "Пропустити" on Step 3 from landing on /verification when register
  // auto-logs them in. These routes are therefore excluded from the
  // "authenticated → /home" rule below.
  final isAtPostRegisterRoute =
      location == RouteNames.verification || location == RouteNames.done;

  // Strict auth-only routes — valid only while unauthenticated. An authenticated
  // user sitting on any of these is bounced to /home.
  //
  // Phase 2.16 — the multi-step wizard adds /register/role + /register/step-2
  // + /register/step-3. They are all unauthenticated-only and treated as the
  // same auth-route surface as /register.
  final isAtUnauthOnlyRoute =
      location == RouteNames.login ||
      location == RouteNames.register ||
      location == RouteNames.registerRole ||
      location == RouteNames.registerStep2 ||
      location == RouteNames.registerStep3;

  // Routes where an unauthenticated user may remain once session has settled.
  // /splash is NOT included — it is only valid while session.isLoading is true.
  final isAtAuthRoute = isAtUnauthOnlyRoute || isAtPostRegisterRoute;

  // While the session is resolving, do NOT yank a user off an auth route they
  // are already on. This matters for the registration wizard: register()
  // briefly flips authProvider to AsyncLoading before settling to
  // Unauthenticated/Authenticated, which fires the router's refreshListenable.
  // Bouncing to /login during that microsecond window would abort the Step 3 →
  // /verification navigation (the user would land on /login instead). Cold
  // start (on /splash or a protected route) still routes to /login as the safe
  // neutral landing pad. F4: this loading window is microseconds long.
  if (session.isLoading) {
    return isAtAuthRoute ? null : RouteNames.login;
  }

  final isAuthenticated = session.value is Authenticated;

  final isAtSplash = location == RouteNames.splash;

  // Settled unauthenticated user anywhere (including /splash) → /login.
  if (!isAuthenticated && (!isAtAuthRoute || isAtSplash)) {
    return RouteNames.login;
  }

  // Authenticated user sitting on a strict auth-only route or splash → send to
  // home. Post-registration routes (/verification, /done) are deliberately
  // excluded: a just-registered (auto-logged-in but email-unverified) user must
  // be able to remain there to finish verification, instead of being yanked to
  // /home before they can enter the OTP.
  if (isAuthenticated && (isAtUnauthOnlyRoute || isAtSplash)) {
    return RouteNames.home;
  }

  // No redirect needed.
  return null;
}
