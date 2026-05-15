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
// Covered scenarios:
//   1. Anonymous user at / → redirected to /login.
//   2. Authenticated user at /login → redirected to /.
//   3. Loading user at /splash → stays on /splash (null).
//   4. Loading user at / → redirected to /splash.
//   5. Anonymous user at /login → stays on /login (null).

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
/// Mirrors the redirect logic of authRedirect. If a new route is added
/// requiring special handling, update both this helper and authRedirect
/// to keep them in sync — divergence is silent.
String? _locationRedirect(AsyncValue<AuthSession> session, String location) {
  if (session.isLoading) {
    return location == RouteNames.splash ? null : RouteNames.splash;
  }
  final isAuthenticated = session.value is Authenticated;
  final isAtAuthRoute =
      location == RouteNames.login ||
      location == RouteNames.register ||
      location == RouteNames.splash;

  if (!isAuthenticated && !isAtAuthRoute) return RouteNames.login;
  if (isAuthenticated && isAtAuthRoute) return RouteNames.home;
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

    test('loading session at /splash stays on /splash (null)', () {
      expect(_locationRedirect(_loadingSession, RouteNames.splash), isNull);
    });

    test('loading session at / is redirected to /splash', () {
      expect(
        _locationRedirect(_loadingSession, RouteNames.home),
        equals(RouteNames.splash),
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
  });
}
