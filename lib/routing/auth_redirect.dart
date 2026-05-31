// Phase 2.9 — Auth redirect guard (real implementation).
//
// Pure function: takes the current [AsyncValue<AuthSession>] and the
// [GoRouterState], returns either a redirect path or null to stay on the
// current location.
//
// Rules:
//   isLoading + not on an auth route → park on /splash (branded loading
//     screen) until the session settles. Prevents the cold-start /login flash:
//     the background session restore (Keystore read + token refresh + /users/me)
//     takes 100–500 ms on Android; parking on /splash avoids showing /login to
//     a returning authenticated user. Registration wizard flows are unaffected
//     because they are on auth routes (isAtAuthRoute = true → null is returned).
//   isLoading + on an auth route → null (stay). Preserves wizard mid-flight.
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
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_start_time.dart';
import 'route_names.dart';

/// Guaranteed minimum time the animated splash wordmark is visible.
///
/// Single source of truth: [AppStartTime.minSplashDuration] (3 000 ms).
/// The redirect gate parks the router on [RouteNames.splash] until this
/// duration has passed, even when the auth provider resolves synchronously
/// (as it does in release AOT builds for returning users). This ensures the
/// letter-by-letter wordmark reveal always plays to completion before
/// go_router navigates away.
const Duration _minSplashDuration = AppStartTime.minSplashDuration;

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
  //
  // Phase 2.13 — the forgot-password flow (/forgot-password + /reset-password)
  // is likewise unauthenticated-only. /reset-password is reached via the
  // emailed deep link with a `?token=` query param; matchedLocation strips the
  // query string, so it matches RouteNames.resetPassword here.
  //
  // Phase 2.20 — /invite/accept is unauthenticated-only. It is reached from
  // the emailed invite deep link (`/invite/accept?token=...`). Once the user
  // successfully accepts the invite they are transitioned to Authenticated and
  // the guard's "authenticated + unauthOnlyRoute → /home" rule forwards them
  // to the home shell automatically.
  final isAtUnauthOnlyRoute =
      location == RouteNames.login ||
      location == RouteNames.register ||
      location == RouteNames.registerRole ||
      location == RouteNames.registerStep2 ||
      location == RouteNames.registerStep3 ||
      location == RouteNames.forgotPassword ||
      location == RouteNames.resetPassword ||
      location == RouteNames.acceptInvite;

  // Routes where an unauthenticated user may remain once session has settled.
  // /splash is NOT included — it is only valid while session.isLoading is true.
  final isAtAuthRoute = isAtUnauthOnlyRoute || isAtPostRegisterRoute;

  // While the session is resolving, do NOT yank a user off an auth route they
  // are already on. This matters for the registration wizard: register()
  // briefly flips authProvider to AsyncLoading before settling to
  // Unauthenticated/Authenticated, which fires the router's refreshListenable.
  // Bouncing to /splash during that window would abort the Step 3 →
  // /verification navigation (the user would land on /splash instead).
  //
  // Cold start (on a protected route) parks on /splash — the branded loading
  // screen is designed for exactly this. Once the session settles the guard
  // fires again: Authenticated + /splash → /home; Unauthenticated + /splash →
  // /login. The isAtAuthRoute = true branch (registration wizard, forgot/reset
  // password, invite accept) is unaffected — null is returned, keeping the
  // user on their current auth route.
  if (session.isLoading) {
    return isAtAuthRoute ? null : RouteNames.splash;
  }

  // Minimum splash duration gate — enforces that the animated "beautica"
  // wordmark (880 ms) is always visible for at least 950 ms before routing
  // away. In release AOT builds authProvider resolves synchronously (Keystore
  // read is fast), so without this gate go_router redirects to /home or
  // /login before SplashScreen has a chance to run the animation.
  //
  // Applies only when the user is currently on /splash — does NOT affect any
  // other route, including auth wizard routes (isAtAuthRoute → null was already
  // returned above). Also does not apply if the session is still loading (the
  // isLoading branch above handles that path). The gate applies in every build
  // mode (debug and release alike) because the animated wordmark is the
  // verified UX surface; debug builds previously skipped it and showed only
  // the static "B" pillow from the native splash before the router yanked the
  // user to /login or /home.
  if (location == RouteNames.splash) {
    if (AppStartTime.elapsed() < _minSplashDuration) {
      return RouteNames.splash;
    }
  }

  final isAuthenticated = session.value is Authenticated;

  final isAtSplash = location == RouteNames.splash;

  // Settled unauthenticated user anywhere (including /splash) → /login.
  if (!isAuthenticated && (!isAtAuthRoute || isAtSplash)) {
    return RouteNames.login;
  }

  // Authenticated user sitting on a strict auth-only route or splash → send to
  // the role-appropriate landing screen. Post-registration routes
  // (/verification, /done) are deliberately excluded: a just-registered
  // (auto-logged-in but email-unverified) user must be able to remain there to
  // finish verification, instead of being yanked away before they can enter the
  // OTP.
  //
  // Role dispatch (Phase 4.2):
  //   INDEPENDENT_MASTER → /master/profile (the Phase 4 master home screen)
  //   all other roles    → / (home shell, shows a "coming soon" screen)
  if (isAuthenticated && (isAtUnauthOnlyRoute || isAtSplash)) {
    final auth = session.value as Authenticated;
    return switch (auth.user.role) {
      UserRole.independentMaster => RouteNames.masterProfile,
      _ => RouteNames.home,
    };
  }

  // Role gate: /services/* is only accessible to INDEPENDENT_MASTER.
  //
  // Any other authenticated role (CLIENT, SALON_OWNER, etc.) that navigates
  // to a /services path is redirected to the home shell which renders the
  // "coming soon" surface. This mirrors the guard already applied on the
  // masterProfile/masterEdit routes via the role-dispatch switch above.
  if (isAuthenticated && location.startsWith('/services')) {
    final Authenticated auth = session.value! as Authenticated;
    if (auth.user.role != UserRole.independentMaster) {
      return RouteNames.home;
    }
  }

  // No redirect needed.
  return null;
}
