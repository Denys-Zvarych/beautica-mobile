// Router-tier guard: an UNAUTHENTICATED deep-link to any protected route must
// redirect to /login (mobile-qa M5 + M10).
//
// WHY THIS FILE EXISTS (the gap it closes)
// ----------------------------------------
// `auth_redirect_test.dart` proves the redirect matrix for a handful of hand-
// picked locations, but no test asserted, as a parameterized contract over the
// real protected-route surface, that EVERY protected entry point an external
// deep link can target bounces an unauthenticated session to /login. A refactor
// that drops a single role/auth gate (e.g. removes the `/passport` CLIENT branch
// from the gate list) would silently expose a protected screen to a logged-out
// user via a cold deep link, and nothing would catch it. This is that contract:
// a small representative route list × the unauthenticated session, asserting the
// production `authRedirectForLocation` seam sends each to /login.
//
// TIER: this is the FAST, deterministic router tier — it exercises the pure
// `authRedirectForLocation` decision function (the @visibleForTesting seam that
// `authRedirect` → `GoRouter.redirect` delegates to) with no widget tree, no
// emulator, runs in CI. The complementary integration tier (drives the same
// redirect through a live GoRouter AFTER a real logout, with secure storage
// cleared) lives in integration_test/client_logout_flow_test.dart.
//
// FINDERS: pure-function test — no widget tree, so no `find.*` at all; the
// no-raw-Cyrillic-finder policy is satisfied vacuously.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/routing/auth_redirect.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// A settled, unauthenticated session — the state a cold deep-link from a
// logged-out user arrives in.
const AsyncValue<AuthSession> _unauthenticatedSession = AsyncData<AuthSession>(
  AuthSession.unauthenticated(),
);

// Representative protected entry points an external deep link can target, one
// per protected surface family:
//   • /home              — CLIENT shell landing (StatefulShellRoute branch)
//   • /passport          — CLIENT beauty-passport branch
//   • /master/profile    — INDEPENDENT_MASTER home
//   • /services          — INDEPENDENT_MASTER catalogue
//   • /schedule          — INDEPENDENT_MASTER schedule subtree
//   • /client/menu       — CLIENT settings hub (/client/* gate)
// Each is reachable by deep link and must be fenced off from a logged-out user.
const List<String> _protectedRoutes = <String>[
  RouteNames.clientHome,
  RouteNames.clientPassport,
  RouteNames.masterProfile,
  RouteNames.services,
  RouteNames.masterSchedule,
  RouteNames.clientMenu,
];

void main() {
  group('unauthenticated deep-link → /login', () {
    for (final String route in _protectedRoutes) {
      test('deep-link to $route while logged out redirects to /login', () {
        final String? redirect = authRedirectForLocation(
          _unauthenticatedSession,
          route,
        );

        expect(
          redirect,
          equals(RouteNames.login),
          reason:
              'an unauthenticated deep-link to the protected route $route must '
              'be redirected to /login, never allowed through',
        );
      });
    }

    test('the protected-route list is non-empty (guards against an empty '
        'parameterization silently passing)', () {
      expect(_protectedRoutes, isNotEmpty);
    });
  });
}
