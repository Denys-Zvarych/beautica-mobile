// Phase 2.9 — Unit tests for the REAL authRedirect guard.
//
// HIGH-1 remediation: this file previously asserted against a hand-copied
// `_locationRedirect` duplicate of the production logic, which could diverge
// silently. That duplicate is DELETED. We now exercise the production
// `authRedirectForLocation` (the @visibleForTesting pure seam that
// `authRedirect` delegates to) directly, plus one real-`GoRouterState`
// integration test through `authRedirect` itself.
//
// `authRedirect(AsyncValue<AuthSession>, GoRouterState)` extracts
// `state.matchedLocation` and forwards to `authRedirectForLocation`. Because
// `GoRouterState` has an internal constructor (it needs a `RouteConfiguration`
// that is not publicly constructible), the matrix tests target the pure
// location-string seam; one widget test pumps a real `GoRouter` so the
// `authRedirect` → `authRedirectForLocation` wiring is covered end-to-end.
//
// F4 — AuthNotifier.build() now returns SYNCHRONOUSLY with Unauthenticated,
// so AsyncLoading should rarely (if ever) reach this guard at cold start.
// The loading branch is retained as a defensive fallback (e.g. an action
// method that sets `state = AsyncLoading()` mid-flight).
//
// Covered scenarios (redirect matrix):
//   - authenticated → protected → allow (null)
//   - unauthenticated → protected → /login
//   - loading → protected → /login; loading @ auth route → stay
//   - authenticated @ auth route → /home
//   - unauthenticated @ auth route → allow (null)
//   - settled unauthenticated @ /splash → /login
//   - AsyncError → treated as unauthenticated → /login

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/auth_redirect.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fixtures
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
// Tests — pure seam (authRedirectForLocation)
// ---------------------------------------------------------------------------

void main() {
  group('authRedirectForLocation (production logic)', () {
    test('anonymous user at / is redirected to /login', () {
      expect(
        authRedirectForLocation(_unauthenticatedSession, RouteNames.home),
        equals(RouteNames.login),
      );
    });

    test('authenticated user at /login is redirected to /', () {
      expect(
        authRedirectForLocation(_authenticatedSession, RouteNames.login),
        equals(RouteNames.home),
      );
    });

    test('authenticated user at /register is redirected to /', () {
      expect(
        authRedirectForLocation(_authenticatedSession, RouteNames.register),
        equals(RouteNames.home),
      );
    });

    test('authenticated user at /splash is redirected to /', () {
      expect(
        authRedirectForLocation(_authenticatedSession, RouteNames.splash),
        equals(RouteNames.home),
      );
    });

    test('loading session at /login stays on /login (null)', () {
      expect(
        authRedirectForLocation(_loadingSession, RouteNames.login),
        isNull,
      );
    });

    test('loading session at / is redirected to /login', () {
      expect(
        authRedirectForLocation(_loadingSession, RouteNames.home),
        equals(RouteNames.login),
      );
    });

    test('loading session at /splash is redirected to /login', () {
      // F4 corrected: /splash is no longer the loading parking spot. The
      // loading window (microsecond) resolves to /login as a neutral landing
      // pad; if the background restore flips to Authenticated, the next
      // redirect pass forwards to /home.
      expect(
        authRedirectForLocation(_loadingSession, RouteNames.splash),
        equals(RouteNames.login),
      );
    });

    // Loading-branch reorder lock — while the session is AsyncLoading (the
    // register flow flips authProvider to AsyncLoading mid-submit), auth-flow
    // routes stay put (null) and protected routes still bounce to /login.

    test('loading session at /settings is redirected to /login', () {
      expect(
        authRedirectForLocation(_loadingSession, RouteNames.settings),
        equals(RouteNames.login),
      );
    });

    test('loading session at /register/step-3 stays (null)', () {
      expect(
        authRedirectForLocation(_loadingSession, RouteNames.registerStep3),
        isNull,
      );
    });

    test('loading session at /verification stays (null)', () {
      expect(
        authRedirectForLocation(_loadingSession, RouteNames.verification),
        isNull,
      );
    });

    test('anonymous user at /login stays on /login (null)', () {
      expect(
        authRedirectForLocation(_unauthenticatedSession, RouteNames.login),
        isNull,
      );
    });

    test('anonymous user at /register stays on /register (null)', () {
      expect(
        authRedirectForLocation(_unauthenticatedSession, RouteNames.register),
        isNull,
      );
    });

    // /splash is only valid while session.isLoading. Once the session settles
    // and the user is unauthenticated, the guard must forward them to /login.
    test('settled anonymous user at /splash is redirected to /login', () {
      expect(
        authRedirectForLocation(_unauthenticatedSession, RouteNames.splash),
        equals(RouteNames.login),
      );
    });

    test('authenticated user at / stays on / (null)', () {
      expect(
        authRedirectForLocation(_authenticatedSession, RouteNames.home),
        isNull,
      );
    });

    test('authenticated user at /settings stays on /settings (null)', () {
      expect(
        authRedirectForLocation(_authenticatedSession, RouteNames.settings),
        isNull,
      );
    });

    test('anonymous user at /settings is redirected to /login', () {
      expect(
        authRedirectForLocation(_unauthenticatedSession, RouteNames.settings),
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
        authRedirectForLocation(errorSession, RouteNames.home),
        equals(RouteNames.login),
      );
    });

    // Phase 2.11 — /verification and /done are auth routes (reachable before
    // a valid session is established).

    test('anonymous user at /verification stays on /verification (null)', () {
      expect(
        authRedirectForLocation(
          _unauthenticatedSession,
          RouteNames.verification,
        ),
        isNull,
      );
    });

    test('anonymous user at /done stays on /done (null)', () {
      expect(
        authRedirectForLocation(_unauthenticatedSession, RouteNames.done),
        isNull,
      );
    });

    // Post-registration routes are NOT bounced for an authenticated user. The
    // auto-login register flow returns an Authenticated session while the email
    // is still unverified; the user must be able to remain on /verification (or
    // /done) to finish the OTP step instead of being yanked to /home. This is
    // the regression that broke CLIENT "Пропустити" on Step 3.
    test('authenticated-but-unverified user at /verification stays (null)', () {
      expect(
        authRedirectForLocation(_authenticatedSession, RouteNames.verification),
        isNull,
      );
    });

    test('authenticated-but-unverified user at /done stays (null)', () {
      expect(
        authRedirectForLocation(_authenticatedSession, RouteNames.done),
        isNull,
      );
    });

    // Phase 2.13 — the forgot-password flow (/forgot-password +
    // /reset-password) is unauthenticated-only (auth_redirect.dart:78-89).
    // /reset-password is reached via the emailed deep link with a `?token=`
    // query param; matchedLocation strips the query string, so the guard sees
    // the bare RouteNames.resetPassword path here.

    test('authenticated user at /forgot-password is redirected to /', () {
      expect(
        authRedirectForLocation(
          _authenticatedSession,
          RouteNames.forgotPassword,
        ),
        equals(RouteNames.home),
      );
    });

    test('authenticated user at /reset-password is redirected to /', () {
      expect(
        authRedirectForLocation(
          _authenticatedSession,
          RouteNames.resetPassword,
        ),
        equals(RouteNames.home),
      );
    });

    test('anonymous user at /forgot-password stays (null)', () {
      expect(
        authRedirectForLocation(
          _unauthenticatedSession,
          RouteNames.forgotPassword,
        ),
        isNull,
      );
    });

    test('anonymous user at /reset-password stays (null)', () {
      expect(
        authRedirectForLocation(
          _unauthenticatedSession,
          RouteNames.resetPassword,
        ),
        isNull,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Integration — REAL authRedirect(session, GoRouterState) wiring.
  //
  // Pumps a real GoRouter whose `redirect` calls the production `authRedirect`
  // with a captured AsyncValue. This proves that authRedirect correctly reads
  // `state.matchedLocation` and forwards to authRedirectForLocation — the seam
  // the matrix tests above cannot reach (GoRouterState is not constructible).
  // -------------------------------------------------------------------------
  group('authRedirect (real GoRouterState wiring)', () {
    Future<GoRouter> pumpRouterWith(
      WidgetTester tester,
      AsyncValue<AuthSession> session,
      String initialLocation,
    ) async {
      final router = GoRouter(
        initialLocation: initialLocation,
        redirect: (context, state) => authRedirect(session, state),
        routes: [
          GoRoute(
            path: RouteNames.splash,
            builder: (c, s) => const _Probe('splash'),
          ),
          GoRoute(
            path: RouteNames.login,
            builder: (c, s) => const _Probe('login'),
          ),
          GoRoute(
            path: RouteNames.home,
            builder: (c, s) => const _Probe('home'),
          ),
          GoRoute(
            path: RouteNames.settings,
            builder: (c, s) => const _Probe('settings'),
          ),
          GoRoute(
            path: RouteNames.forgotPassword,
            builder: (c, s) => const _Probe('forgot-password'),
          ),
          GoRoute(
            path: RouteNames.resetPassword,
            builder: (c, s) => const _Probe('reset-password'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('unauthenticated → protected route lands on /login', (
      tester,
    ) async {
      await pumpRouterWith(
        tester,
        _unauthenticatedSession,
        RouteNames.settings,
      );
      expect(find.text('login'), findsOneWidget);
      expect(find.text('settings'), findsNothing);
    });

    testWidgets('authenticated → protected route stays on the route', (
      tester,
    ) async {
      await pumpRouterWith(tester, _authenticatedSession, RouteNames.settings);
      expect(find.text('settings'), findsOneWidget);
      expect(find.text('login'), findsNothing);
    });

    testWidgets('authenticated @ /login → redirected to /', (tester) async {
      await pumpRouterWith(tester, _authenticatedSession, RouteNames.login);
      expect(find.text('home'), findsOneWidget);
    });

    // Phase 2.13 — forgot-password flow guard wiring through real GoRouterState.

    testWidgets('authenticated @ /forgot-password → redirected to /', (
      tester,
    ) async {
      await pumpRouterWith(
        tester,
        _authenticatedSession,
        RouteNames.forgotPassword,
      );
      expect(find.text('home'), findsOneWidget);
      expect(find.text('forgot-password'), findsNothing);
    });

    testWidgets('authenticated @ /reset-password → redirected to /', (
      tester,
    ) async {
      // The router strips the `?token=...` query string before matchedLocation,
      // so navigating with a token still resolves to RouteNames.resetPassword.
      await pumpRouterWith(
        tester,
        _authenticatedSession,
        '${RouteNames.resetPassword}?token=x',
      );
      expect(find.text('home'), findsOneWidget);
      expect(find.text('reset-password'), findsNothing);
    });

    testWidgets('anonymous @ /forgot-password stays on the route', (
      tester,
    ) async {
      await pumpRouterWith(
        tester,
        _unauthenticatedSession,
        RouteNames.forgotPassword,
      );
      expect(find.text('forgot-password'), findsOneWidget);
      expect(find.text('login'), findsNothing);
    });

    testWidgets('anonymous @ /reset-password stays on the route', (
      tester,
    ) async {
      await pumpRouterWith(
        tester,
        _unauthenticatedSession,
        '${RouteNames.resetPassword}?token=x',
      );
      expect(find.text('reset-password'), findsOneWidget);
      expect(find.text('login'), findsNothing);
    });
  });
}

/// Minimal probe screen rendering its label so the resolved route can be
/// asserted via [find.text].
class _Probe extends StatelessWidget {
  const _Probe(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}
