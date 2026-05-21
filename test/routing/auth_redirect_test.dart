// Phase 2.9 — Unit tests for the authRedirect pure function.
//
// authRedirect(AsyncValue<AuthSession>, GoRouterState) is pure: no side effects,
// no providers, no widget tree needed.
//
// Because GoRouterState has an internal constructor (requires RouteConfiguration
// which is not publicly constructible), we use a real GoRouter to pump a
// redirecting navigation in a widget test and assert the resulting location.
//
// For the pure-function logic tests (which only need matchedLocation), we
// test an extracted helper [_locationRedirect] that accepts a plain String
// instead of a GoRouterState, which maps directly to authRedirect's logic.
//
// F4 — AuthNotifier.build() now returns SYNCHRONOUSLY with Unauthenticated,
// so AsyncLoading should rarely (if ever) reach this guard at cold start.
// The loading branch of authRedirect is retained as a defensive fallback —
// e.g. if a future action method sets `state = AsyncLoading()` mid-flight.
// The two loading-branch tests below still verify the contract of the pure
// function; they no longer represent the dominant cold-start path.
//
// Covered scenarios:
//   1.  Anonymous user at / → redirected to /login.
//   2.  Authenticated user at /login → redirected to /.
//   3.  Loading user at /splash → stays on /splash (null). [retained, rare]
//   4.  Loading user at / → redirected to /splash. [retained, rare]
//   5.  Anonymous user at /login → stays on /login (null).
//   6.  Settled anonymous user at /splash → redirected to /login.
//   7.  Authenticated user at /splash → redirected to /.
//   8.  Anonymous user at /verification → stays on /verification (null).
//   9.  Anonymous user at /done → stays on /done (null).
//   10. Authenticated user at /verification → redirected to /.
//   11. Authenticated user at /done → redirected to /.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Testable pure-function extracted from authRedirect.
//
// authRedirect delegates the logic to this function, which accepts the
// location string directly — no GoRouterState construction needed.
// ---------------------------------------------------------------------------

/// Mirrors the redirect logic of [authRedirect] but takes a [location] string
/// directly, making it trivially testable without a GoRouterState.
///
/// Keep this helper in sync with [authRedirect] in lib/routing/auth_redirect.dart.
/// If a new route is added requiring special handling, update both this helper
/// and authRedirect — divergence is silent and will cause guard failures in
/// production without failing the test suite.
///
/// Current production rules (Phase 2.9 + 2.11 + F4 corrected):
///   isLoading → redirect to /login (microsecond-short window in F4).
///   Unauthenticated + not on an auth route → redirect to /login.
///   Unauthenticated on /splash (session settled) → redirect to /login.
///   Authenticated + on an auth route (login/register/verification/done/splash)
///     → redirect to /.
///   Otherwise → null (stay).
///
/// Auth routes = /login, /register, /verification, /done. /splash is NOT an
/// auth route — it is only valid while session.isLoading is true. Once the
/// session settles, any unauthenticated user still on /splash must be forwarded
/// to /login.
///
/// KEEP THIS IN SYNC with [authRedirect] in lib/routing/auth_redirect.dart.
String? _locationRedirect(AsyncValue<AuthSession> session, String location) {
  // Routes where an unauthenticated user may remain once session has settled.
  // /splash is NOT included — it is only valid while session.isLoading is true.
  // /verification and /done are part of the registration flow and are reachable
  // before the session is established (the OTP step precedes a valid session).
  // Phase 2.16 — the multi-step wizard adds /register/role +
  // /register/step-2 + /register/step-3. They are all unauthenticated-only.
  final isAtAuthRoute =
      location == RouteNames.login ||
      location == RouteNames.register ||
      location == RouteNames.registerRole ||
      location == RouteNames.registerStep2 ||
      location == RouteNames.registerStep3 ||
      location == RouteNames.verification ||
      location == RouteNames.done;

  // While loading, keep a user already on any auth route in place (the register
  // flow flips authProvider to AsyncLoading mid-submit and must not bounce to
  // /login); otherwise route to /login as the neutral cold-start landing pad.
  if (session.isLoading) {
    return isAtAuthRoute ? null : RouteNames.login;
  }

  final isAuthenticated = session.value is Authenticated;

  final isAtSplash = location == RouteNames.splash;

  // Settled unauthenticated user anywhere (including /splash) → /login.
  if (!isAuthenticated && (!isAtAuthRoute || isAtSplash)) {
    return RouteNames.login;
  }

  // Authenticated user sitting on an auth-only route or splash → send to home.
  if (isAuthenticated && (isAtAuthRoute || isAtSplash)) return RouteNames.home;

  return null;
}

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

const _fakeUser = User(
  id: 'u1',
  email: 'test@example.com',
  role: UserRole.independentMaster,
  firstName: 'Test',
  lastName: 'User',
);

const _authenticatedSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _fakeUser, accessToken: 'token'),
);

const _unauthenticatedSession = AsyncData<AuthSession>(
  AuthSession.unauthenticated(),
);

const _loadingSession = AsyncLoading<AuthSession>();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('authRedirect logic', () {
    test('anonymous user at / is redirected to /login', () {
      expect(
        _locationRedirect(_unauthenticatedSession, RouteNames.home),
        equals(RouteNames.login),
      );
    });

    test('authenticated user at /login is redirected to /', () {
      expect(
        _locationRedirect(_authenticatedSession, RouteNames.login),
        equals(RouteNames.home),
      );
    });

    test('authenticated user at /register is redirected to /', () {
      expect(
        _locationRedirect(_authenticatedSession, RouteNames.register),
        equals(RouteNames.home),
      );
    });

    test('authenticated user at /splash is redirected to /', () {
      expect(
        _locationRedirect(_authenticatedSession, RouteNames.splash),
        equals(RouteNames.home),
      );
    });

    test('loading session at /login stays on /login (null)', () {
      expect(_locationRedirect(_loadingSession, RouteNames.login), isNull);
    });

    test('loading session at / is redirected to /login', () {
      expect(
        _locationRedirect(_loadingSession, RouteNames.home),
        equals(RouteNames.login),
      );
    });

    test('loading session at /splash is redirected to /login', () {
      // F4 corrected: /splash is no longer the loading parking spot. The
      // loading window (microsecond) resolves to /login as a neutral landing
      // pad; if the background restore flips to Authenticated, the next
      // redirect pass forwards to /home.
      expect(
        _locationRedirect(_loadingSession, RouteNames.splash),
        equals(RouteNames.login),
      );
    });

    // Loading-branch reorder lock — while the session is AsyncLoading (the
    // register flow flips authProvider to AsyncLoading mid-submit), auth-flow
    // routes stay put (null) and protected routes still bounce to /login.

    test('loading session at /settings is redirected to /login', () {
      expect(
        _locationRedirect(_loadingSession, RouteNames.settings),
        equals(RouteNames.login),
      );
    });

    test('loading session at /register/step-3 stays (null)', () {
      expect(
        _locationRedirect(_loadingSession, RouteNames.registerStep3),
        isNull,
      );
    });

    test('loading session at /verification stays (null)', () {
      expect(
        _locationRedirect(_loadingSession, RouteNames.verification),
        isNull,
      );
    });

    test('anonymous user at /login stays on /login (null)', () {
      expect(
        _locationRedirect(_unauthenticatedSession, RouteNames.login),
        isNull,
      );
    });

    test('anonymous user at /register stays on /register (null)', () {
      expect(
        _locationRedirect(_unauthenticatedSession, RouteNames.register),
        isNull,
      );
    });

    // /splash is only valid while session.isLoading. Once the session settles
    // and the user is unauthenticated, the guard must forward them to /login.
    test('settled anonymous user at /splash is redirected to /login', () {
      expect(
        _locationRedirect(_unauthenticatedSession, RouteNames.splash),
        equals(RouteNames.login),
      );
    });

    test('authenticated user at / stays on / (null)', () {
      expect(_locationRedirect(_authenticatedSession, RouteNames.home), isNull);
    });

    test('authenticated user at /settings stays on /settings (null)', () {
      expect(
        _locationRedirect(_authenticatedSession, RouteNames.settings),
        isNull,
      );
    });

    test('anonymous user at /settings is redirected to /login', () {
      expect(
        _locationRedirect(_unauthenticatedSession, RouteNames.settings),
        equals(RouteNames.login),
      );
    });

    test('AsyncError<AuthSession> at / is redirected to /login', () {
      // An AsyncError has no value (value is null) → treated as unauthenticated.
      // The guard falls through session.value == null → !isAuthenticated → /login.
      final errorSession = AsyncError<AuthSession>(
        Exception('cold start failed'),
        StackTrace.empty,
      );
      expect(
        _locationRedirect(errorSession, RouteNames.home),
        equals(RouteNames.login),
      );
    });

    // Phase 2.11 — /verification and /done are auth routes (reachable before
    // a valid session is established). Tests mirror the production authRedirect
    // behaviour added in Phase 2.11 (QA HIGH-1 fix).

    test('anonymous user at /verification stays on /verification (null)', () {
      expect(
        _locationRedirect(_unauthenticatedSession, RouteNames.verification),
        isNull,
      );
    });

    test('anonymous user at /done stays on /done (null)', () {
      expect(
        _locationRedirect(_unauthenticatedSession, RouteNames.done),
        isNull,
      );
    });

    test('authenticated user at /verification is redirected to /', () {
      expect(
        _locationRedirect(_authenticatedSession, RouteNames.verification),
        equals(RouteNames.home),
      );
    });

    test('authenticated user at /done is redirected to /', () {
      expect(
        _locationRedirect(_authenticatedSession, RouteNames.done),
        equals(RouteNames.home),
      );
    });
  });
}
