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
import 'role_home.dart';
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
  // Phase 2.13 / Beautica OTP task Phase B — the forgot-password flow
  // (/forgot-password + /reset-password/otp) is unauthenticated-only.
  // /reset-password/otp now receives the submitted email via in-app
  // navigation `extra` rather than being reached from an emailed link
  // directly. NOTE: /reset-password (the final "set new password" step) is
  // deliberately NOT listed here — see [isAtDualAccessResetPasswordRoute]
  // below, since that screen is also reachable authenticated.
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
      location == RouteNames.resetOtpVerification ||
      location == RouteNames.acceptInvite;

  // Beautica OTP task Phase B4/B5 — /reset-password ("set new password") is
  // reachable by BOTH unauthenticated users (the forgot-password OTP flow)
  // and authenticated users (the settings change-password flow) —
  // `ResetPasswordScreen` is the SAME widget for both, distinguished only by
  // the `fromChangePassword` flag carried in its `ResetPasswordArgs` extra.
  // Mirrors [isAtPostRegisterRoute]'s rationale: an authenticated user here
  // must NOT be bounced to /home, so this is excluded from the strict
  // "authenticated + unauthOnlyRoute → role home" rule below.
  final isAtDualAccessResetPasswordRoute = location == RouteNames.resetPassword;

  // Routes where an unauthenticated user may remain once session has settled.
  // /splash is NOT included — it is only valid while session.isLoading is true.
  final isAtAuthRoute =
      isAtUnauthOnlyRoute ||
      isAtPostRegisterRoute ||
      isAtDualAccessResetPasswordRoute;

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

  // mobile-security / mobile-qa LOW (2026-09-05) — TWO reads, on purpose.
  //
  // [isAuthenticated] is the LENIENT one: it reads `.value` raw, so an
  // `AsyncError` still carrying a previous `AsyncData(Authenticated)` counts as
  // authenticated. It backs this file's eight raw `session.value` reads — this
  // one plus the seven role gates below.
  //
  // Why leaving it lenient is SAFE — verified 2026-09-05 by enumerating every
  // producer of `AsyncError` on `authProvider`. There are FIVE:
  //
  //   auth_notifier.dart:373  login()        — reachable only from /login
  //   auth_notifier.dart:448  register()     — reachable only from /register/*
  //   auth_notifier.dart:605  verifyEmail()  — reachable only from /verification
  //   auth_notifier.dart:906  acceptInvite() — reachable only from /invite/accept
  //   auth_notifier.dart:237  build()        — any surface; cold start, or a
  //                                            `ref.invalidate(authProvider)`
  //
  // `build()` belongs on that list: its catch-all spans only the `try` opened
  // at `auth_notifier.dart:291` and closed at `:335`. Three statements run
  // BEFORE that try and are uncovered by it — `:261`
  // `ref.read(secureStorageProvider)`, `:262` `await
  // storage.readRefreshToken()` and `:287` `await storage.deleteAll()` — and
  // `SecureStorage` forwards the latter two straight to the
  // `FlutterSecureStorage` platform channel with no guard of its own
  // (`secure_storage.dart:102`, `:142`). Whatever they throw therefore
  // surfaces as an `AsyncError` on `authProvider`. Do NOT re-assert that
  // `build()` cannot throw.
  //
  // Riverpod's `copyWithPrevious` is what leaves the errored state still
  // carrying a value, and in all five cases that retained value belongs to the
  // SAME account as the user in front of the screen:
  //
  //   * the four action producers are each reachable only after a settled
  //     emission — `AsyncData(Unauthenticated)` for the three unauth-only
  //     ones, `AsyncData(Authenticated)` for the auto-logged-in,
  //     email-unverified user on `/verification`;
  //   * a cold-start `build()` rejection has no previous `AsyncData` to
  //     retain, so `.value` is null, `isAuthenticated` is false, and the
  //     `!isAuthenticated` bounce below routes the user to `/login` —
  //     fail-CLOSED, not lenient at all;
  //   * a `build()` rejection after `ref.invalidate(authProvider)` retains the
  //     value of the session that was live an instant earlier — the same
  //     account.
  //
  // So a cross-account stale-role read — the only thing hardening would buy —
  // is not constructible. Leniency here is therefore a UX choice (do not tear
  // a user off a protected surface for a same-account transient), NOT a safety
  // property. Re-derive it from the five producers above before trusting it.
  //
  // Corrected 2026-09-05 — two claims this comment used to make are FALSE; do
  // not reinstate them. Hardening this read would NOT eject the OTP-mistyping
  // user to `/login` (`/verification` is `isAtPostRegisterRoute`, hence
  // `isAtAuthRoute`, so the bounce below is already false for them), and it
  // would NOT turn any role gate into an ADMIT (that bounce returns `/login`
  // BEFORE every role gate on `/services`, `/master/*`, `/staff/*`,
  // `/salon/*`, `/schedule`, `/client/*` and the client branches). Hardening
  // would be strictly fail-CLOSED; it is declined on UX grounds alone.
  //
  // [resolvedAuth] is the STRICT one, gated on the concrete `AsyncData`
  // subtype exactly like `app_router.dart`'s `resolvedSession()`. It backs the
  // one arm below that is fail-OPEN — the "authenticated user sitting on an
  // unauth-only route → send them to their role home" forward. That arm ACTS
  // on the role rather than merely fencing it, so a stale role there is a
  // wrong destination rather than a harmless extra fence: under
  // `AsyncError(previous: Authenticated A)` a visitor on `/login` would be
  // forwarded into account A's role home. The producer enumeration above says
  // that state is not constructible on `/login` today, so this strictness is
  // defence in depth against a future post-auth error producer, not a fix for
  // a live bug. Unresolved means "no forward", which leaves the user on
  // `/login` — where the next settled emission decides properly.
  final isAuthenticated = session.value is Authenticated;
  final Authenticated? resolvedAuth =
      session is AsyncData<AuthSession> && session.value is Authenticated
      ? session.value as Authenticated
      : null;

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
  // Role dispatch (Phase 4.2 + Phase 13.1):
  //   INDEPENDENT_MASTER → /master/profile (the Phase 4 master home screen)
  //   CLIENT             → /home (the Phase 13.1 5-tab client shell landing)
  //   all other roles    → / (home shell, shows a "coming soon" screen)
  //
  // This is the single source of truth for post-login landing — both this gate
  // and the post-login `context.go` in login_screen.dart resolve the landing
  // path through the shared [roleHomePath] helper, so the dispatch can never
  // drift between the two sites.
  //
  // Gated on [resolvedAuth], NOT [isAuthenticated] — this arm FORWARDS on the
  // role instead of fencing on it, so it is the one place a stale role is a
  // wrong destination rather than a conservative bounce. See the two reads'
  // note above.
  if (resolvedAuth != null && (isAtUnauthOnlyRoute || isAtSplash)) {
    return roleHomePath(resolvedAuth.user.role);
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
      return roleHomePath(auth.user.role);
    }
  }

  // Role gate: /master/* is only accessible to INDEPENDENT_MASTER.
  //
  // Any other authenticated role (CLIENT, SALON_OWNER, SALON_ADMIN,
  // SALON_MASTER) that navigates to a /master/* path (working hours, profile,
  // edit, etc.) is redirected to the home shell which renders the "coming
  // soon" surface. SALON_MASTER has a read-only calendar but that surface is
  // under /calendar, not /master — so no /master/* role is carved out for it.
  if (isAuthenticated && location.startsWith('/master/')) {
    final Authenticated auth = session.value! as Authenticated;
    if (auth.user.role != UserRole.independentMaster) {
      return roleHomePath(auth.user.role);
    }
  }

  // Role gate: /staff/* is only accessible to SALON_MASTER.
  //
  // The symmetric counterpart of the /master/* gate immediately above: the
  // invited SALON_MASTER's own read-only personal-profile surface
  // (`/staff/profile`, `/staff/settings`, `/staff/edit/personal`) — the fix
  // for the "blank home" landing bug (see `role_home.dart`). Deliberately a
  // SEPARATE subtree from `/master/*` rather than a widened admission there:
  // INDEPENDENT_MASTER's bookings/schedule/services surfaces under
  // `/master/*` must stay fenced off from SALON_MASTER, which this scope
  // explicitly does not grant. Any other authenticated role that navigates
  // to a /staff/* path is redirected to its own landing.
  if (isAuthenticated && location.startsWith('/staff/')) {
    final Authenticated auth = session.value! as Authenticated;
    if (auth.user.role != UserRole.salonMaster) {
      return roleHomePath(auth.user.role);
    }
  }

  // Role gate (Phase 250): /salon/* is only accessible to SALON_OWNER /
  // SALON_ADMIN.
  //
  // Mirrors the /master/* gate immediately above — `/salon/bookings/new`
  // (the SALON «Новий запис» wizard) is the first route under this prefix;
  // any other authenticated role (CLIENT, INDEPENDENT_MASTER, SALON_MASTER)
  // that navigates to a /salon/* path is redirected to the home shell. This
  // did NOT exist before Phase 250 — checked, and there is no pre-existing
  // /salon/* gate anywhere in this file to reuse or drift out of agreement
  // with (the CLIENT-facing salon booking flow lives under the DIFFERENT
  // `/booking/salon/*` prefix and is gated per-route by `app_router.dart`'s
  // own `clientOnlyGuard`, not here). SALON_MASTER is deliberately excluded:
  // that role has a read-only calendar, not a walk-in-booking affordance.
  if (isAuthenticated && location.startsWith('/salon/')) {
    final Authenticated auth = session.value! as Authenticated;
    if (auth.user.role != UserRole.salonOwner &&
        auth.user.role != UserRole.salonAdmin) {
      return roleHomePath(auth.user.role);
    }
  }

  // Role gate (Phase 15.6 — OQ-2 hardening): the schedule EDIT surfaces are
  // INDEPENDENT_MASTER-only, PERMANENTLY — this is not an interim MVP state.
  // `/schedule` (MasterScheduleScreen) already gates every edit affordance on
  // `scheduleEditableProvider`; but the deep edit destinations —
  // `/schedule/weekly` (WeeklyTemplateEditorScreen), `/schedule/day`,
  // `/schedule/copy` — are full edit surfaces. Redirect every
  // non-INDEPENDENT_MASTER role away from the entire `/schedule` subtree to
  // the home "coming soon" shell, mirroring the `/master/*` and `/services`
  // gates above.
  //
  // Phase 309 (CLOSED, D1/D3): salon staff do NOT get this gate widened.
  // `SALON_MASTER` reads the SAME `MasterScheduleScreen` at the SEPARATE
  // `/staff/schedule` route instead — the `/staff/*` gate above is what
  // admits them there, not this one. `/schedule` and its subtree stay
  // INDEPENDENT_MASTER-only whether or not `/staff/schedule` exists. Phase
  // 311 (CLOSED) then made `WeeklyTemplateEditorScreen`, `DayHoursSheet` and
  // `ApplyScheduleSheet` self-check `scheduleEditableProvider` too, so the
  // edit surfaces are enclosed by two independent mechanisms — this router
  // gate is not made redundant by that; both stay in force.
  if (isAuthenticated && location.startsWith('/schedule')) {
    final Authenticated auth = session.value! as Authenticated;
    if (auth.user.role != UserRole.independentMaster) {
      return roleHomePath(auth.user.role);
    }
  }

  // Role gate: /client/* is only accessible to CLIENT.
  //
  // The mirror of the /master/* gate above: the CLIENT settings hub and its
  // per-section edit pages (/client/menu, /client/edit/personal, etc.) are
  // CLIENT-only. Any non-CLIENT authenticated role (INDEPENDENT_MASTER, salon
  // roles) that navigates to a /client/* path is redirected to its own landing
  // (INDEPENDENT_MASTER → profile, everyone else → "coming soon" home shell).
  // These routes are NOT opened to any other role.
  if (isAuthenticated && location.startsWith('/client/')) {
    final Authenticated auth = session.value! as Authenticated;
    if (auth.user.role != UserRole.client) {
      return roleHomePath(auth.user.role);
    }
  }

  // Role gate (Phase 13.1 + Phase 13.7): CLIENT-only surfaces.
  //
  // The inverse of the /master/*, /services, /schedule gates above: any non-
  // CLIENT authenticated role (INDEPENDENT_MASTER, salon roles) that lands on a
  // client branch is bounced to its own landing — INDEPENDENT_MASTER back to
  // its profile, everyone else to the "coming soon" home shell. This keeps the
  // CLIENT and MASTER shells mutually fenced off: a MASTER can never reach
  // /home, /favorites, /search, /bookings, /passport, or any other CLIENT-only
  // surface, and the gates above already keep a CLIENT out of every /master/*,
  // /services and /schedule surface.
  //
  // Phase 13.7 (revised) — /rating (MyRatingScreen) is a CLIENT quick-link
  // target added outside the StatefulShellRoute branches; it must be gated here
  // to prevent non-CLIENT roles from reaching it.
  // Exact-segment matching avoids snagging unrelated future paths.
  if (isAuthenticated) {
    const clientBranchPrefixes = <String>[
      RouteNames.clientHome,
      RouteNames.clientFavorites,
      RouteNames.clientSearch,
      RouteNames.clientBookings,
      RouteNames.clientPassport,
      // Phase 13.7 (revised) — standalone CLIENT quick-link targets (not in shell branches)
      RouteNames.myRating,
    ];
    final isAtClientBranch = clientBranchPrefixes.any(
      (p) => location == p || location.startsWith('$p/'),
    );
    if (isAtClientBranch) {
      final Authenticated auth = session.value! as Authenticated;
      if (auth.user.role != UserRole.client) {
        return roleHomePath(auth.user.role);
      }
    }
  }

  // No redirect needed.
  return null;
}
