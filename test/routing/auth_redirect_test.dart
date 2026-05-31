// Phase 2.9 — Unit tests for the REAL authRedirect guard.
//
// HIGH-1 remediation: this file previously asserted against a hand-copied
// `_locationRedirect` duplicate of the production logic, which could diverge
// silently. That duplicate is DELETED. We now exercise the production
// `authRedirectForLocation` (the @visibleForTesting pure seam that
// `authRedirect` delegates to) directly, plus nine real-`GoRouterState`
// widget tests through `authRedirect` itself.
//
// `authRedirect(AsyncValue<AuthSession>, GoRouterState)` extracts
// `state.matchedLocation` and forwards to `authRedirectForLocation`. Because
// `GoRouterState` has an internal constructor (it needs a `RouteConfiguration`
// that is not publicly constructible), the matrix tests target the pure
// location-string seam; nine widget tests pump a real `GoRouter` so the
// `authRedirect` → `authRedirectForLocation` wiring is covered end-to-end.
//
// F4 — The isLoading branch exists as a defensive guard for: (a) cold-start
// background session restore (Keystore read + token refresh + /users/me,
// 100–500 ms on Android); (b) mid-registration register() call which briefly
// emits AsyncLoading before settling. During cold start, isLoading parks on
// /splash to prevent flashing /login to a returning authenticated user.
//
// Covered scenarios (redirect matrix):
//   - authenticated → protected → allow (null)
//   - unauthenticated → protected → /login
//   - loading → protected → /splash (cold-start parking); loading @ auth route → stay
//   - loading @ /splash → /splash (self-redirect, GoRouter no-op); once settled → /home or /login
//   - authenticated @ auth route → /home
//   - unauthenticated @ auth route → allow (null)
//   - settled unauthenticated @ /splash → /login
//   - AsyncError → treated as unauthenticated → /login

import 'package:beautica_mobile/core/app_start_time.dart';
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

/// A CLIENT-role user for testing that non-INDEPENDENT_MASTER roles still
/// land on [RouteNames.home] (the "coming soon" shell).
const _clientUser = User(
  id: 'u2',
  email: 'client@example.com',
  role: UserRole.client,
  firstName: 'Client',
  lastName: 'User',
);

const _clientSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _clientUser, accessToken: 'token'),
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
  // The splash duration gate (auth_redirect.dart) now applies in every build
  // mode — including tests. Backdate AppStartTime so the existing matrix
  // assertions exercise post-gate behaviour (i.e. elapsed() > minSplashDuration).
  // Individual tests that need to exercise the within-gate path reset the
  // start time themselves.
  setUp(() {
    AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );
  });

  tearDown(AppStartTime.resetForTest);

  group('authRedirectForLocation (production logic)', () {
    test('anonymous user at / is redirected to /login', () {
      expect(
        authRedirectForLocation(_unauthenticatedSession, RouteNames.home),
        equals(RouteNames.login),
      );
    });

    // Phase 4.2 — INDEPENDENT_MASTER lands on /master/profile, not /.
    test('INDEPENDENT_MASTER at /login is redirected to /master/profile', () {
      expect(
        authRedirectForLocation(_authenticatedSession, RouteNames.login),
        equals(RouteNames.masterProfile),
      );
    });

    test(
      'INDEPENDENT_MASTER at /register is redirected to /master/profile',
      () {
        expect(
          authRedirectForLocation(_authenticatedSession, RouteNames.register),
          equals(RouteNames.masterProfile),
        );
      },
    );

    test('INDEPENDENT_MASTER at /splash is redirected to /master/profile', () {
      expect(
        authRedirectForLocation(_authenticatedSession, RouteNames.splash),
        equals(RouteNames.masterProfile),
      );
    });

    // Non-INDEPENDENT_MASTER (CLIENT) roles still land on /.
    test('CLIENT role at /login is redirected to /', () {
      expect(
        authRedirectForLocation(_clientSession, RouteNames.login),
        equals(RouteNames.home),
      );
    });

    test('CLIENT role at /splash is redirected to /', () {
      expect(
        authRedirectForLocation(_clientSession, RouteNames.splash),
        equals(RouteNames.home),
      );
    });

    test('loading session at /login stays on /login (null)', () {
      expect(
        authRedirectForLocation(_loadingSession, RouteNames.login),
        isNull,
      );
    });

    test('loading session at / is redirected to /splash', () {
      expect(
        authRedirectForLocation(_loadingSession, RouteNames.home),
        equals(RouteNames.splash),
      );
    });

    test('loading session at /splash stays on /splash during loading', () {
      // /splash is the cold-start parking screen. The guard returns RouteNames.splash
      // (a self-redirect) which GoRouter collapses to a no-op — the user stays on
      // /splash while the session resolves. Once settled:
      //   Authenticated  → /home (auth_redirect.dart: authenticated + isAtSplash → /home)
      //   Unauthenticated → /login (auth_redirect.dart: !isAuthenticated + isAtSplash → /login)
      expect(
        authRedirectForLocation(_loadingSession, RouteNames.splash),
        equals(RouteNames.splash),
      );
    });

    // Loading-branch reorder lock — while the session is AsyncLoading (the
    // register flow flips authProvider to AsyncLoading mid-submit), auth-flow
    // routes stay put (null) and protected routes park on /splash until the
    // session settles (Authenticated → /home, Unauthenticated → /login).

    test('loading session at /settings is redirected to /splash', () {
      expect(
        authRedirectForLocation(_loadingSession, RouteNames.settings),
        equals(RouteNames.splash),
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

    test(
      'INDEPENDENT_MASTER at /forgot-password is redirected to /master/profile',
      () {
        expect(
          authRedirectForLocation(
            _authenticatedSession,
            RouteNames.forgotPassword,
          ),
          equals(RouteNames.masterProfile),
        );
      },
    );

    test(
      'INDEPENDENT_MASTER at /reset-password is redirected to /master/profile',
      () {
        expect(
          authRedirectForLocation(
            _authenticatedSession,
            RouteNames.resetPassword,
          ),
          equals(RouteNames.masterProfile),
        );
      },
    );

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

    // Phase 2.20 — /invite/accept is an unauthenticated-only route. An
    // anonymous user arriving via the emailed deep link must stay on the
    // screen; an already-authenticated user must be bounced to /.

    test(
      'INDEPENDENT_MASTER at /invite/accept is redirected to /master/profile',
      () {
        expect(
          authRedirectForLocation(
            _authenticatedSession,
            RouteNames.acceptInvite,
          ),
          equals(RouteNames.masterProfile),
        );
      },
    );

    test('anonymous user at /invite/accept stays (null)', () {
      expect(
        authRedirectForLocation(
          _unauthenticatedSession,
          RouteNames.acceptInvite,
        ),
        isNull,
      );
    });

    test('loading session at /invite/accept stays (null)', () {
      expect(
        authRedirectForLocation(_loadingSession, RouteNames.acceptInvite),
        isNull,
      );
    });

    // Phase 5.2 — /services/* role gate (SEC MEDIUM-2).
    // INDEPENDENT_MASTER may access /services; all other roles are redirected
    // to / (the "coming soon" home shell).

    test('INDEPENDENT_MASTER at /services stays (null)', () {
      expect(
        authRedirectForLocation(_authenticatedSession, RouteNames.services),
        isNull,
      );
    });

    test('INDEPENDENT_MASTER at /services/create stays (null)', () {
      expect(
        authRedirectForLocation(
          _authenticatedSession,
          RouteNames.serviceCreate,
        ),
        isNull,
      );
    });

    test('CLIENT role at /services is redirected to /', () {
      expect(
        authRedirectForLocation(_clientSession, RouteNames.services),
        equals(RouteNames.home),
      );
    });

    test('CLIENT role at /services/create is redirected to /', () {
      expect(
        authRedirectForLocation(_clientSession, RouteNames.serviceCreate),
        equals(RouteNames.home),
      );
    });

    test('CLIENT role at /services/:id/edit is redirected to /', () {
      expect(
        authRedirectForLocation(
          _clientSession,
          RouteNames.serviceEdit('svc-001'),
        ),
        equals(RouteNames.home),
      );
    });
  });

  // Splash duration gate — the animated wordmark (880 ms reveal) must always
  // play to completion. The gate parks the router on /splash until
  // AppStartTime.elapsed() >= AppStartTime.minSplashDuration regardless of
  // build mode. Previously gated by !kDebugMode, which caused the static
  // native-splash "B" pillow to be the only thing debug users ever saw.
  group('splash duration gate (build-mode-independent)', () {
    test(
      'Settled Unauthenticated user on /splash within minSplashDuration → stays on /splash',
      () {
        AppStartTime.resetForTest();
        AppStartTime.record(); // elapsed ≈ 0 → strictly less than minSplashDuration
        final result = authRedirectForLocation(
          _unauthenticatedSession,
          RouteNames.splash,
        );
        expect(result, RouteNames.splash);
      },
    );

    test(
      'Settled Authenticated user on /splash within minSplashDuration → stays on /splash',
      () {
        AppStartTime.resetForTest();
        AppStartTime.record(); // elapsed ≈ 0 → strictly less than minSplashDuration
        final result = authRedirectForLocation(
          _authenticatedSession,
          RouteNames.splash,
        );
        expect(result, RouteNames.splash);
      },
    );
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
          // Phase 4.2 — INDEPENDENT_MASTER lands here instead of /.
          GoRoute(
            path: RouteNames.masterProfile,
            builder: (c, s) => const _Probe('master-profile'),
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

    // Phase 4.2 — INDEPENDENT_MASTER lands on /master/profile, not /.
    testWidgets('INDEPENDENT_MASTER @ /login → redirected to /master/profile', (
      tester,
    ) async {
      await pumpRouterWith(tester, _authenticatedSession, RouteNames.login);
      expect(find.text('master-profile'), findsOneWidget);
      expect(find.text('home'), findsNothing);
    });

    // Phase 2.13 — forgot-password flow guard wiring through real GoRouterState.

    // Phase 4.2 — INDEPENDENT_MASTER lands on /master/profile.
    testWidgets(
      'INDEPENDENT_MASTER @ /forgot-password → redirected to /master/profile',
      (tester) async {
        await pumpRouterWith(
          tester,
          _authenticatedSession,
          RouteNames.forgotPassword,
        );
        expect(find.text('master-profile'), findsOneWidget);
        expect(find.text('forgot-password'), findsNothing);
        expect(find.text('home'), findsNothing);
      },
    );

    testWidgets(
      'INDEPENDENT_MASTER @ /reset-password → redirected to /master/profile',
      (tester) async {
        // The router strips the `?token=...` query string before matchedLocation,
        // so navigating with a token still resolves to RouteNames.resetPassword.
        await pumpRouterWith(
          tester,
          _authenticatedSession,
          '${RouteNames.resetPassword}?token=x',
        );
        expect(find.text('master-profile'), findsOneWidget);
        expect(find.text('reset-password'), findsNothing);
        expect(find.text('home'), findsNothing);
      },
    );

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

    // Phase 4.2 — INDEPENDENT_MASTER settles to /master/profile, not /.
    testWidgets(
      'cold-start: loading at /home parks on /splash, then INDEPENDENT_MASTER → /master/profile (no /login flash)',
      (tester) async {
        var session = _loadingSession as AsyncValue<AuthSession>;
        late void Function() triggerRefresh;
        final listenable = _CallbackListenable((cb) => triggerRefresh = cb);

        final router = GoRouter(
          initialLocation: RouteNames.home,
          refreshListenable: listenable,
          redirect: (context, state) => authRedirect(session, state),
          routes: [
            GoRoute(
              path: RouteNames.splash,
              builder: (_, _) => const _Probe('splash'),
            ),
            GoRoute(
              path: RouteNames.login,
              builder: (_, _) => const _Probe('login'),
            ),
            GoRoute(
              path: RouteNames.home,
              builder: (_, _) => const _Probe('home'),
            ),
            GoRoute(
              path: RouteNames.masterProfile,
              builder: (_, _) => const _Probe('master-profile'),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        expect(
          find.text('splash'),
          findsOneWidget,
          reason: 'loading session must park on /splash, not /login',
        );
        expect(
          find.text('login'),
          findsNothing,
          reason: 'authenticated user must never see /login on cold start',
        );

        // Simulate session settling to authenticated (INDEPENDENT_MASTER).
        session = _authenticatedSession;
        triggerRefresh();
        await tester.pumpAndSettle();

        expect(
          find.text('master-profile'),
          findsOneWidget,
          reason:
              'INDEPENDENT_MASTER must forward to /master/profile after settle',
        );
        expect(
          find.text('login'),
          findsNothing,
          reason:
              '/login must never appear in the authenticated cold-start chain',
        );
        expect(
          find.text('splash'),
          findsNothing,
          reason: '/splash must be left once session settles',
        );
      },
    );

    testWidgets(
      'cold-start: loading at /home parks on /splash, then unauthenticated → /login',
      (tester) async {
        var session = _loadingSession as AsyncValue<AuthSession>;
        late void Function() triggerRefresh;
        final listenable = _CallbackListenable((cb) => triggerRefresh = cb);

        final router = GoRouter(
          initialLocation: RouteNames.home,
          refreshListenable: listenable,
          redirect: (context, state) => authRedirect(session, state),
          routes: [
            GoRoute(
              path: RouteNames.splash,
              builder: (_, _) => const _Probe('splash'),
            ),
            GoRoute(
              path: RouteNames.login,
              builder: (_, _) => const _Probe('login'),
            ),
            GoRoute(
              path: RouteNames.home,
              builder: (_, _) => const _Probe('home'),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        expect(
          find.text('splash'),
          findsOneWidget,
          reason: 'loading session must park on /splash',
        );

        // Simulate session settling to unauthenticated.
        session = _unauthenticatedSession;
        triggerRefresh();
        await tester.pumpAndSettle();

        expect(
          find.text('login'),
          findsOneWidget,
          reason: 'unauthenticated session must reach /login after settle',
        );
        expect(
          find.text('splash'),
          findsNothing,
          reason: '/splash must be left once unauthenticated session settles',
        );
      },
    );
  });
}

/// A [ChangeNotifier] that captures its first [notifyListeners] callback so
/// tests can trigger a GoRouter refresh on demand.
class _CallbackListenable extends ChangeNotifier {
  _CallbackListenable(void Function(void Function()) capture) {
    capture(notifyListeners);
  }
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
