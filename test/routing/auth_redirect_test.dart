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

/// A CLIENT-role user. Phase 13.1: CLIENT now lands on the 5-tab client shell
/// at [RouteNames.clientHome]; the master gates still bounce CLIENT off every
/// /master/*, /services and /schedule surface to [RouteNames.home].
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

    // Phase 13.1 — CLIENT now lands on the 5-tab client shell at /home (was /).
    test('CLIENT role at /login is redirected to /home', () {
      expect(
        authRedirectForLocation(_clientSession, RouteNames.login),
        equals(RouteNames.clientHome),
      );
    });

    test('CLIENT role at /splash is redirected to /home', () {
      expect(
        authRedirectForLocation(_clientSession, RouteNames.splash),
        equals(RouteNames.clientHome),
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

    // Beautica OTP task Phase B5 — RouteNames.changePassword is a protected
    // route like /settings (default behaviour: no allow-list entry needed).
    // Unlike /reset-password, it is NEVER reachable unauthenticated — the
    // authenticated settings change-password flow is its only entry point.
    test('authenticated user at /settings/change-password stays (null)', () {
      expect(
        authRedirectForLocation(
          _authenticatedSession,
          RouteNames.changePassword,
        ),
        isNull,
      );
    });

    test(
      'anonymous user at /settings/change-password is redirected to /login',
      () {
        expect(
          authRedirectForLocation(
            _unauthenticatedSession,
            RouteNames.changePassword,
          ),
          equals(RouteNames.login),
        );
      },
    );

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

    // Phase 2.13 / Beautica OTP task Phase B — the forgot-password flow
    // (/forgot-password + /reset-password/otp) is unauthenticated-only
    // (auth_redirect.dart). /reset-password (the final "set new password"
    // step) is DUAL-ACCESS — see the next test — because Phase B5 reuses the
    // SAME ResetPasswordScreen for the authenticated settings
    // change-password flow.

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

    // mobile-qa gap fix — Beautica OTP task Phase B post-audit addition.
    // RouteNames.resetOtpVerification sits in the SAME `isAtUnauthOnlyRoute`
    // OR-clause as RouteNames.forgotPassword (auth_redirect.dart), but unlike
    // its sibling it had no dedicated test — a typo dropping it from that
    // clause (or referencing the wrong RouteNames constant) would silently
    // let an authenticated user reach the OTP-entry screen and would only be
    // caught if a future test happened to exercise it incidentally.
    test('INDEPENDENT_MASTER at /reset-password/otp is redirected to '
        '/master/profile', () {
      expect(
        authRedirectForLocation(
          _authenticatedSession,
          RouteNames.resetOtpVerification,
        ),
        equals(RouteNames.masterProfile),
      );
    });

    test('anonymous user at /reset-password/otp stays (null)', () {
      expect(
        authRedirectForLocation(
          _unauthenticatedSession,
          RouteNames.resetOtpVerification,
        ),
        isNull,
      );
    });

    // Beautica OTP task Phase B5 — /reset-password is now DUAL-ACCESS: an
    // authenticated user reaching it (the settings change-password flow) must
    // NOT be bounced to /master/profile — mirrors /verification + /done's
    // isAtPostRegisterRoute treatment. This intentionally REVERSES the old
    // Phase 2.13 pin (an authenticated user used to always be bounced here,
    // back when /reset-password was reachable ONLY via an emailed deep link).
    test('authenticated user at /reset-password stays (null)', () {
      expect(
        authRedirectForLocation(
          _authenticatedSession,
          RouteNames.resetPassword,
        ),
        isNull,
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
    // INDEPENDENT_MASTER may access /services. Phase 13.1: every other role is
    // bounced through the shared [roleHomePath] helper, so a CLIENT lands on
    // /home (the 5-tab client shell) — NOT / (the no-bottom-bar "coming soon"
    // shell). The pre-Phase-13.1 expectation of / was the routing bug this
    // regression block now pins shut.

    test('INDEPENDENT_MASTER at /services stays (null)', () {
      expect(
        authRedirectForLocation(_authenticatedSession, RouteNames.services),
        isNull,
      );
    });

    // The /services/* leaf these two cases exercise was RETARGETED from
    // /services/create to /services/setup (2026-08-04): the single-create form
    // was deleted and both add-service entry points collapsed onto
    // /services/setup, so RouteNames.serviceCreate no longer exists. The
    // property being pinned is unchanged — a /services/* LEAF must be
    // role-gated exactly like the /services root, not just the root itself.
    test('INDEPENDENT_MASTER at /services/setup stays (null)', () {
      expect(
        authRedirectForLocation(_authenticatedSession, RouteNames.serviceSetup),
        isNull,
      );
    });

    test('CLIENT role at /services is redirected to /home', () {
      expect(
        authRedirectForLocation(_clientSession, RouteNames.services),
        equals(RouteNames.clientHome),
      );
    });

    test('CLIENT role at /services/setup is redirected to /home', () {
      expect(
        authRedirectForLocation(_clientSession, RouteNames.serviceSetup),
        equals(RouteNames.clientHome),
      );
    });

    test('CLIENT role at /services/:id/edit is redirected to /home', () {
      expect(
        authRedirectForLocation(
          _clientSession,
          RouteNames.serviceEdit('svc-001'),
        ),
        equals(RouteNames.clientHome),
      );
    });

    // Phase 6.2 — /master/working-hours role gate (SEC regression).
    //
    // The /master/* prefix guard in auth_redirect.dart redirects any
    // authenticated role that is NOT INDEPENDENT_MASTER to RouteNames.home.
    // These three tests pin that guard for the working-hours route specifically
    // so a refactor that widens /master/* access is caught immediately.

    test('INDEPENDENT_MASTER at /master/working-hours is allowed (null)', () {
      expect(
        authRedirectForLocation(_authenticatedSession, RouteNames.workingHours),
        isNull,
      );
    });

    test('SALON_MASTER at /master/working-hours is redirected to /', () {
      const salonMasterUser = User(
        id: 'u-sm',
        email: 'salonmaster@example.com',
        role: UserRole.salonMaster,
        firstName: 'Salon',
        lastName: 'Master',
      );
      const salonMasterSession = AsyncData<AuthSession>(
        AuthSession.authenticated(user: salonMasterUser, accessToken: 'token'),
      );
      expect(
        authRedirectForLocation(salonMasterSession, RouteNames.workingHours),
        equals(RouteNames.home),
      );
    });

    test('SALON_OWNER at /master/working-hours is redirected to '
        '/salons/home', () {
      const salonOwnerUser = User(
        id: 'u-so',
        email: 'owner@example.com',
        role: UserRole.salonOwner,
        firstName: 'Salon',
        lastName: 'Owner',
      );
      const salonOwnerSession = AsyncData<AuthSession>(
        AuthSession.authenticated(user: salonOwnerUser, accessToken: 'token'),
      );
      expect(
        authRedirectForLocation(salonOwnerSession, RouteNames.workingHours),
        equals(RouteNames.salonHome),
      );
    });

    test('CLIENT at /master/working-hours is redirected to /home', () {
      // Phase 13.1: the /master/* gate routes a CLIENT through roleHomePath →
      // /home (client shell), not / — the cross-shell bounce-target bug.
      expect(
        authRedirectForLocation(_clientSession, RouteNames.workingHours),
        equals(RouteNames.clientHome),
      );
    });

    // Phase 250 — /salon/* role gate (new prefix guard).
    //
    // `/salon/bookings/new` (the SALON «Новий запис» wizard) is the first
    // route under this prefix. Mirrors the /master/* group immediately
    // above: SALON_OWNER/SALON_ADMIN are allowed, every other authenticated
    // role is redirected to its own landing. See `salon_bookings_route
    // _shadowing_test.dart` for the widget-level pin of the resolved screen
    // itself; these are the pure-function role-gate cases.

    test('SALON_OWNER at /salon/bookings/new is allowed (null)', () {
      const salonOwnerUser = User(
        id: 'u-so2',
        email: 'owner2@example.com',
        role: UserRole.salonOwner,
        firstName: 'Salon',
        lastName: 'Owner',
      );
      const salonOwnerSession = AsyncData<AuthSession>(
        AuthSession.authenticated(user: salonOwnerUser, accessToken: 'token'),
      );
      expect(
        authRedirectForLocation(
          salonOwnerSession,
          RouteNames.salonStaffBookingNew,
        ),
        isNull,
      );
    });

    test('SALON_ADMIN at /salon/bookings/new is allowed (null)', () {
      const salonAdminUser = User(
        id: 'u-sa',
        email: 'admin@example.com',
        role: UserRole.salonAdmin,
        firstName: 'Salon',
        lastName: 'Admin',
      );
      const salonAdminSession = AsyncData<AuthSession>(
        AuthSession.authenticated(user: salonAdminUser, accessToken: 'token'),
      );
      expect(
        authRedirectForLocation(
          salonAdminSession,
          RouteNames.salonStaffBookingNew,
        ),
        isNull,
      );
    });

    test('SALON_MASTER at /salon/bookings/new is redirected to / — a read-only '
        'calendar is not a walk-in-booking affordance', () {
      const salonMasterUser = User(
        id: 'u-sm2',
        email: 'salonmaster2@example.com',
        role: UserRole.salonMaster,
        firstName: 'Salon',
        lastName: 'Master',
      );
      const salonMasterSession = AsyncData<AuthSession>(
        AuthSession.authenticated(user: salonMasterUser, accessToken: 'token'),
      );
      expect(
        authRedirectForLocation(
          salonMasterSession,
          RouteNames.salonStaffBookingNew,
        ),
        equals(RouteNames.home),
      );
    });

    test('INDEPENDENT_MASTER at /salon/bookings/new is redirected to '
        '/master/profile', () {
      expect(
        authRedirectForLocation(
          _authenticatedSession,
          RouteNames.salonStaffBookingNew,
        ),
        equals(RouteNames.masterProfile),
      );
    });

    test('CLIENT at /salon/bookings/new is redirected to /home', () {
      expect(
        authRedirectForLocation(
          _clientSession,
          RouteNames.salonStaffBookingNew,
        ),
        equals(RouteNames.clientHome),
      );
    });

    // Auth gate precedence: an unauthenticated session is forwarded to
    // /login BEFORE the role gate is even reached — deep-linking to
    // /salon/bookings/new while signed out must never expose the screen,
    // nor leak the role-gate's non-login bounce targets. Mirrors the
    // /schedule/* and CLIENT-shell precedence tests below.
    test('unauthenticated at /salon/bookings/new is redirected to /login', () {
      expect(
        authRedirectForLocation(
          _unauthenticatedSession,
          RouteNames.salonStaffBookingNew,
        ),
        equals(RouteNames.login),
      );
    });

    // Phase 15.6 — /schedule/* role gate (OQ-2 hardening regression).
    //
    // The schedule EDIT surfaces are INDEPENDENT_MASTER-only in MVP. The
    // /schedule prefix guard in auth_redirect.dart:223-228 redirects EVERY
    // authenticated role that is NOT INDEPENDENT_MASTER to RouteNames.home —
    // closing the leak where a read-only role (SALON_MASTER) or any other role
    // deep-linking/pushing straight to /schedule/weekly|day|copy could reach
    // editable controls (those editor screens do NOT self-check the capability;
    // only MasterScheduleScreen gates on scheduleEditableProvider). These tests
    // pin the gate across the WHOLE /schedule subtree and every role so a
    // refactor that widens access is caught immediately. The auth gate keeps
    // precedence — an unauthenticated session still goes to /login regardless of
    // path — so that is asserted too.
    //
    // Local role fixtures (the existing _clientSession + _authenticatedSession
    // cover CLIENT and INDEPENDENT_MASTER; SALON_MASTER/OWNER/ADMIN are built
    // inline to keep this block self-contained and the matrix explicit).
    const salonMasterSession = AsyncData<AuthSession>(
      AuthSession.authenticated(
        user: User(
          id: 'u-sm',
          email: 'salonmaster@example.com',
          role: UserRole.salonMaster,
          firstName: 'Salon',
          lastName: 'Master',
        ),
        accessToken: 'token',
      ),
    );
    const salonOwnerSession = AsyncData<AuthSession>(
      AuthSession.authenticated(
        user: User(
          id: 'u-so',
          email: 'owner@example.com',
          role: UserRole.salonOwner,
          firstName: 'Salon',
          lastName: 'Owner',
        ),
        accessToken: 'token',
      ),
    );
    const salonAdminSession = AsyncData<AuthSession>(
      AuthSession.authenticated(
        user: User(
          id: 'u-sa',
          email: 'admin@example.com',
          role: UserRole.salonAdmin,
          firstName: 'Salon',
          lastName: 'Admin',
        ),
        accessToken: 'token',
      ),
    );

    // The full /schedule subtree under audit: the landing screen plus the three
    // deep edit destinations that do NOT self-check the capability.
    const scheduleRoutes = <String>[
      RouteNames.masterSchedule, // /schedule
      RouteNames.scheduleWeeklyEditor, // /schedule/weekly
      RouteNames.scheduleDayOverride, // /schedule/day
      RouteNames.schedulePropagate, // /schedule/copy
    ];

    group('/schedule role gate (Phase 15.6 OQ-2)', () {
      for (final route in scheduleRoutes) {
        test('INDEPENDENT_MASTER at $route is allowed (null)', () {
          expect(
            authRedirectForLocation(_authenticatedSession, route),
            isNull,
            reason: 'the schedule owner role must reach $route',
          );
        });

        // Phase 13.1: a CLIENT bounced off any /schedule edit surface lands on
        // /home (the client shell), not / — routed through roleHomePath. This
        // is the cross-shell bounce-target regression; the salon roles below
        // have no client shell and still resolve to /.
        test('CLIENT at $route is redirected to /home', () {
          expect(
            authRedirectForLocation(_clientSession, route),
            equals(RouteNames.clientHome),
          );
        });

        test('SALON_MASTER at $route is redirected to /', () {
          expect(
            authRedirectForLocation(salonMasterSession, route),
            equals(RouteNames.home),
            reason:
                'a read-only SALON_MASTER must NOT reach the schedule edit '
                'surfaces (the exact OQ-2 leak this gate closes)',
          );
        });

        test('SALON_OWNER at $route is redirected to /salons/home', () {
          expect(
            authRedirectForLocation(salonOwnerSession, route),
            equals(RouteNames.salonHome),
          );
        });

        test('SALON_ADMIN at $route is redirected to /salons/home', () {
          expect(
            authRedirectForLocation(salonAdminSession, route),
            equals(RouteNames.salonHome),
            reason:
                'Phase 21.8 — SALON_ADMIN now shares the Salon Shell landing '
                'with SALON_OWNER instead of falling through to the bare `/` '
                'wildcard.',
          );
        });

        // Auth gate precedence: an unauthenticated session is forwarded to
        // /login BEFORE the role gate is even reached — deep-linking to a
        // /schedule route while signed out must never expose the screen.
        test('unauthenticated at $route is redirected to /login', () {
          expect(
            authRedirectForLocation(_unauthenticatedSession, route),
            equals(RouteNames.login),
          );
        });
      }
    });

    // Phase 13.1 — CLIENT 5-tab shell role gate. The inverse of the master
    // gates: CLIENT reaches the five branches; every other role is bounced to
    // its own landing (INDEPENDENT_MASTER → /master/profile, salon roles → /).
    group('CLIENT shell role gate (Phase 13.1 + Phase 13.7)', () {
      const clientRoutes = <String>[
        RouteNames.clientHome,
        RouteNames.clientFavorites,
        RouteNames.clientSearch,
        RouteNames.clientBookings,
        RouteNames.clientPassport,
        // Phase 13.7 (revised) — standalone CLIENT quick-link outside the shell
        // branches. Must be gated identically to the five shell paths above so
        // that a non-CLIENT role cannot reach /rating via direct navigation or
        // a deep link.
        RouteNames.myRating,
      ];

      for (final route in clientRoutes) {
        test('CLIENT at $route is allowed (null)', () {
          expect(
            authRedirectForLocation(_clientSession, route),
            isNull,
            reason: 'the CLIENT role must reach its own shell branch $route',
          );
        });

        test(
          'INDEPENDENT_MASTER at $route is redirected to /master/profile',
          () {
            expect(
              authRedirectForLocation(_authenticatedSession, route),
              equals(RouteNames.masterProfile),
              reason: 'a master must NOT land on the client shell',
            );
          },
        );

        test('SALON_OWNER at $route is redirected to /salons/home', () {
          expect(
            authRedirectForLocation(salonOwnerSession, route),
            equals(RouteNames.salonHome),
          );
        });

        test('unauthenticated at $route is redirected to /login', () {
          expect(
            authRedirectForLocation(_unauthenticatedSession, route),
            equals(RouteNames.login),
          );
        });
      }
    });

    // -----------------------------------------------------------------------
    // CLIENT cross-shell bounce contract (regression — Step 2.7 Rule 3).
    //
    // THE BUG: two sites hardcoded RouteNames.home ('/') as the bounce target
    // for an authenticated user kicked off a foreign-shell route, instead of
    // dispatching through the shared roleHomePath() helper. For a CLIENT that
    // sent them to '/' — the no-bottom-bar "Скоро…" placeholder — instead of
    // '/home' (RouteNames.clientHome), the real 5-tab ClientShell. The fix
    // routed BOTH bounce sites (auth_redirect.dart + done_screen.dart) through
    // roleHomePath.
    //
    // These cases pin the invariant directly: for a CLIENT, EVERY cross-shell
    // bounce must resolve to clientHome ('/home'), never home ('/'). The
    // /master/profile case is the exact repro the integration tier exercises
    // (client_shell_flow_test.dart Test 3). The matrix above covers the gates
    // individually; this block states the contract as one explicit assertion so
    // a regression that reintroduces a hardcoded '/' is caught by name.
    group('CLIENT cross-shell bounce always lands on clientHome (regression)', () {
      // The repro case: a CLIENT deep-linking into the MASTER profile must be
      // bounced to /home (the client shell), NEVER to / (the placeholder).
      test('CLIENT at /master/profile → /home (clientHome), not / (home)', () {
        final target = authRedirectForLocation(
          _clientSession,
          RouteNames.masterProfile,
        );
        expect(
          target,
          equals(RouteNames.clientHome),
          reason:
              'the master-profile bounce is the integration repro — a CLIENT '
              'must land on the 5-tab client shell, not the no-bar placeholder',
        );
        expect(
          target,
          isNot(equals(RouteNames.home)),
          reason: 'hardcoded RouteNames.home here is the exact bug under guard',
        );
      });

      test('CLIENT at /services → /home (clientHome), not / (home)', () {
        expect(
          authRedirectForLocation(_clientSession, RouteNames.services),
          allOf(equals(RouteNames.clientHome), isNot(equals(RouteNames.home))),
        );
      });

      test('CLIENT at /schedule/weekly → /home (clientHome), not / (home)', () {
        expect(
          authRedirectForLocation(
            _clientSession,
            RouteNames.scheduleWeeklyEditor,
          ),
          allOf(equals(RouteNames.clientHome), isNot(equals(RouteNames.home))),
        );
      });
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

    // Beautica OTP task Phase B5 — /reset-password is DUAL-ACCESS: an
    // authenticated user (the settings change-password flow) stays on the
    // route rather than being bounced, reversing the old Phase 2.13 pin (see
    // the plain-function test above for the full rationale). The old
    // `?token=...` deep-link query param is retired — Phase B4 carries the
    // reset ticket via in-app `extra` instead.
    testWidgets('INDEPENDENT_MASTER @ /reset-password stays on the route', (
      tester,
    ) async {
      await pumpRouterWith(
        tester,
        _authenticatedSession,
        RouteNames.resetPassword,
      );
      expect(find.text('reset-password'), findsOneWidget);
      expect(find.text('master-profile'), findsNothing);
      expect(find.text('home'), findsNothing);
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
        RouteNames.resetPassword,
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
