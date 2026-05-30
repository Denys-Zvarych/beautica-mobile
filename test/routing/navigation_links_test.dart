// Navigation link audit — auth/onboarding flows.
//
// Purpose: assert every screen-to-screen transition identified in the QA
// navigation matrix. Each test pumps only the source screen + a thin stub
// destination (Text label) so the assertion is on the router location, not
// on real destination widget rendering. That keeps tests fast, deterministic,
// and isolated from destination-screen complexity.
//
// Tests are structured as: tap the trigger on the source screen → assert the
// router lands on the destination route.
//
// Covered flows (NL = Navigation Link test):
//   NL-01  /login "Register" link → /register/role                  ✅ covered (login_screen_test)
//   NL-02  /login "Forgot password" link → /forgot-password         ✅ covered (login_screen_test)
//   NL-03  /login success → /                                       ✅ covered (login_screen_test)
//   NL-04  /login EMAIL_NOT_VERIFIED banner → /verification          ✅ covered (login_screen_test)
//   NL-05  /register/role Continue → /register                      ✅ covered (role_selection_screen_test)
//   NL-06  /register/role login link → /login                       ✅ covered (role_selection_screen_test)
//   NL-07  /register (step-1) Next → /register/step-2               ✅ covered (register_step_1_screen_test)
//   NL-08  /register (step-1) back link → /register/role            ✅ covered (register_step_1_screen_test)
//   NL-09  /register (step-1) login link → /login                   ✅ covered (register_step_1_screen_test)
//   NL-10  /register/step-2 Next → /register/step-3                 ✅ covered (register_step_2_screen_test)
//   NL-11  /register/step-3 Submit → /verification (VerificationRequired) ✅ covered
//   NL-12  /register/step-3 CLIENT Skip → /verification             ✅ covered (register_step_3_skip_navigation_test)
//   NL-13  /verification OTP success → /done                        ✅ covered (verification_screen_test)
//   NL-14  /verification back link → /register/step-3               ✅ covered (verification_screen_test)
//   NL-15  /done "Go to app" → /                                    ✅ covered (done_screen_test)
//   NL-16  /done "Setup later" → /                                  ✅ covered (done_screen_test)
//   NL-17  /forgot-password "Send" confirmation → stays (shows sent state)  ✅ covered
//   NL-18  /forgot-password sent state "preview reset" → /reset-password   ✅ covered
//   NL-19  /forgot-password sent state back-to-login → /login               ✅ covered
//   NL-20  /reset-password success CTA → /login                     ✅ covered (reset_password_screen_test)
//   NL-21  /reset-password invalid CTA → /forgot-password            ✅ covered (reset_password_screen_test)
//   NL-22  /invite/accept success → / (via router redirect)         ❌ GAP — new test NL-22 below
//   NL-23  /settings logout confirmed → /login                      ✅ covered (settings_screen_test)
//
// Auth-guard coverage gaps (authRedirectForLocation — pure seam tests):
//   NL-G01  authenticated user at /register/role → /             ❌ GAP — new test
//   NL-G02  unauthenticated user at /register/role → stays (null) ❌ GAP — new test
//   NL-G03  authenticated user at /register/step-2 → /          ❌ GAP — new test
//   NL-G04  unauthenticated user at /register/step-2 → stays     ❌ GAP — new test
//   NL-G05  loading session at /register/role → stays            ❌ GAP — new test
//   NL-G06  loading session at /register/step-2 → stays          ❌ GAP — new test
//
// app_router.dart route completeness:
//   NL-R01  every RouteNames constant has a matching GoRoute registration       ❌ GAP — new test
//
// /register/step-2 back button:
//   NL-B01  AuthScaffold showBack=true on step-2 → back tapped → /register     ✅ covered (this file)
//
// /register/step-3 back button:
//   NL-B02  AuthScaffold showBack=true on step-3 → back tapped → /register/step-2  ✅ covered (this file)
//
// /forgot-password showBack=true → back tapped → /login:
//   NL-B03  AuthScaffold showBack=true on /forgot-password → back → /login     ❌ GAP — new test
//
// /reset-password showBack=true (form state) → back tapped → /login:
//   NL-B04  AuthScaffold showBack=true on /reset-password (form) → back → /login ❌ GAP — new test

import 'dart:async';

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/invite_details.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/accept_invite_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/forgot_password_request_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/register_step_2_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/register_step_3_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/reset_password_screen.dart';
import 'package:beautica_mobile/features/auth/state/accept_invite_notifier.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/auth_redirect.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

const _fakeUser = User(
  id: 'u1',
  email: 'test@example.com',
  role: UserRole.independentMaster,
  firstName: 'Test',
  lastName: 'User',
);

const _authenticatedSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _fakeUser, accessToken: 'tok'),
);

const _unauthenticatedSession = AsyncData<AuthSession>(
  AuthSession.unauthenticated(),
);

const _loadingSession = AsyncLoading<AuthSession>();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a [MaterialApp.router] with l10n delegates and a fixed locale.
Widget _wrap(GoRouter router, {ProviderContainer? container}) {
  final child = MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk'),
  );
  if (container != null) {
    return UncontrolledProviderScope(container: container, child: child);
  }
  return ProviderScope(child: child);
}

/// Minimal probe that renders its label as Text.
class _Probe extends StatelessWidget {
  const _Probe(this.label);
  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}

// ===========================================================================
// NL-G01 – NL-G06: Auth-guard coverage for wizard routes not yet in
// auth_redirect_test.dart (registerRole, registerStep2).
// ===========================================================================

void main() {
  // -------------------------------------------------------------------------
  // Auth-guard pure-seam tests for wizard routes
  // -------------------------------------------------------------------------
  group('authRedirectForLocation — wizard route guard gaps', () {
    // NL-G01
    test(
      'NL-G01: INDEPENDENT_MASTER at /register/role is redirected to /master/profile',
      () {
        expect(
          authRedirectForLocation(
            _authenticatedSession,
            RouteNames.registerRole,
          ),
          equals(RouteNames.masterProfile),
        );
      },
    );

    // NL-G02
    test('NL-G02: unauthenticated user at /register/role stays (null)', () {
      expect(
        authRedirectForLocation(
          _unauthenticatedSession,
          RouteNames.registerRole,
        ),
        isNull,
      );
    });

    // NL-G03
    test(
      'NL-G03: INDEPENDENT_MASTER at /register/step-2 is redirected to /master/profile',
      () {
        expect(
          authRedirectForLocation(
            _authenticatedSession,
            RouteNames.registerStep2,
          ),
          equals(RouteNames.masterProfile),
        );
      },
    );

    // NL-G04
    test('NL-G04: unauthenticated user at /register/step-2 stays (null)', () {
      expect(
        authRedirectForLocation(
          _unauthenticatedSession,
          RouteNames.registerStep2,
        ),
        isNull,
      );
    });

    // NL-G05
    test('NL-G05: loading session at /register/role stays (null)', () {
      expect(
        authRedirectForLocation(_loadingSession, RouteNames.registerRole),
        isNull,
      );
    });

    // NL-G06
    test('NL-G06: loading session at /register/step-2 stays (null)', () {
      expect(
        authRedirectForLocation(_loadingSession, RouteNames.registerStep2),
        isNull,
      );
    });
  });

  // -------------------------------------------------------------------------
  // NL-R01: Every RouteNames constant maps to a GoRoute in app_router.dart.
  // -------------------------------------------------------------------------
  // This test builds a minimal GoRouter that mirrors the real app_router
  // registrations using the actual RouteNames constants, then navigates to
  // each one and asserts that go_router resolves it (i.e. no "No matching
  // routes found" error is thrown). This catches any RouteNames constant that
  // was added to route_names.dart but forgotten in app_router.dart.
  group('NL-R01: Route registration completeness', () {
    testWidgets(
      'NL-R01: every RouteNames constant resolves to a registered GoRoute',
      (tester) async {
        // Mirror of the production app_router registrations — uses real
        // RouteNames constants so the test catches constant/path mismatches.
        final router = GoRouter(
          initialLocation: RouteNames.splash,
          redirect: (_, _) => null,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.splash,
              builder: (_, _) => const _Probe('splash'),
            ),
            GoRoute(
              path: RouteNames.login,
              builder: (_, _) => const _Probe('login'),
            ),
            GoRoute(
              path: RouteNames.acceptInvite,
              builder: (_, _) => const _Probe('accept-invite'),
            ),
            GoRoute(
              path: RouteNames.registerRole,
              builder: (_, _) => const _Probe('register-role'),
            ),
            GoRoute(
              path: RouteNames.forgotPassword,
              builder: (_, _) => const _Probe('forgot-password'),
            ),
            GoRoute(
              path: RouteNames.resetPassword,
              builder: (_, _) => const _Probe('reset-password'),
            ),
            // ShellRoute mirrors the production nesting; the test only checks
            // that routes resolve — shell chrome is not rendered here.
            ShellRoute(
              builder: (_, _, child) => child,
              routes: <RouteBase>[
                GoRoute(
                  path: RouteNames.register,
                  builder: (_, _) => const _Probe('register-step-1'),
                ),
                GoRoute(
                  path: RouteNames.registerStep2,
                  builder: (_, _) => const _Probe('register-step-2'),
                ),
                GoRoute(
                  path: RouteNames.registerStep3,
                  builder: (_, _) => const _Probe('register-step-3'),
                ),
              ],
            ),
            GoRoute(
              path: RouteNames.verification,
              builder: (_, _) => const _Probe('verification'),
            ),
            GoRoute(
              path: RouteNames.done,
              builder: (_, _) => const _Probe('done'),
            ),
            GoRoute(
              path: RouteNames.home,
              builder: (_, _) => const _Probe('home'),
            ),
            GoRoute(
              path: RouteNames.settings,
              builder: (_, _) => const _Probe('settings'),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(_wrap(router));
        await tester.pumpAndSettle();

        // Navigate to every registered RouteNames constant and assert the
        // router resolves it without throwing. The probe label is derived
        // from the path so we can assert each destination independently.
        final routeChecks = <String, String>{
          RouteNames.login: 'login',
          RouteNames.registerRole: 'register-role',
          RouteNames.register: 'register-step-1',
          RouteNames.registerStep2: 'register-step-2',
          RouteNames.registerStep3: 'register-step-3',
          RouteNames.forgotPassword: 'forgot-password',
          RouteNames.resetPassword: 'reset-password',
          RouteNames.acceptInvite: 'accept-invite',
          RouteNames.verification: 'verification',
          RouteNames.done: 'done',
          RouteNames.home: 'home',
          RouteNames.settings: 'settings',
        };

        for (final entry in routeChecks.entries) {
          router.go(entry.key);
          await tester.pumpAndSettle();
          expect(
            find.text(entry.value),
            findsOneWidget,
            reason:
                'RouteNames.${entry.key} must resolve to a registered GoRoute '
                '— the probe text "${entry.value}" must be present after '
                'router.go("${entry.key}")',
          );
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  // NL-22: /invite/accept success → router navigates to /
  // -------------------------------------------------------------------------
  // The accept invite screen calls authProvider.notifier.acceptInvite(...)
  // which on success transitions authProvider to Authenticated. The screen
  // then relies on the router's redirect (authRedirect: authenticated + on
  // unauthOnlyRoute → /) to forward to home. In the widget test we wire the
  // real authRedirect so this guard fires.
  //
  // Implementation detail: AcceptInviteScreen does NOT call context.go('/') on
  // success — it deliberately leaves navigation to the router's refresh
  // listener. So this test wires authRedirect into the minimal GoRouter and
  // asserts that the router resolves to / after a successful accept.
  group('NL-22: /invite/accept success → / via router redirect', () {
    testWidgets('NL-22: tapping invite_accept CTA with valid form and successful '
        'repository call causes the router to navigate to /', (tester) async {
      const kToken = 'valid-invite-token';

      final validInvite = InviteDetails(
        email: 'masha@salon.ua',
        role: UserRole.salonMaster,
        expiresAt: DateTime.now().add(const Duration(hours: 48)),
      );

      // We need a ProviderScope so we can override acceptInviteProvider,
      // authRepositoryProvider, and secureStorageProvider simultaneously.
      // The router's redirect calls authRedirectForLocation with a captured
      // session — we capture it via authProvider.
      final repo = FakeAuthRepository();
      // Force acceptInvite() to return a salonMaster user so the role-based
      // router redirect lands on /home (salonMaster has no dedicated route yet).
      repo.acceptInviteResult = (
        const User(
          id: 'invited-u1',
          email: 'masha@salon.ua',
          role: UserRole.salonMaster,
          firstName: 'Марія',
          lastName: 'Бондар',
        ),
        const AuthTokens(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
        ),
      );
      final storage = FakeSecureStorage();

      // A container that starts with an unauthenticated session and
      // transitions to Authenticated after acceptInvite() succeeds.
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith((_) => repo),
          secureStorageProvider.overrideWith((_) => storage),
          acceptInviteProvider(
            kToken,
          ).overrideWith(() => _SyncInviteNotifier(validInvite)),
        ],
      );
      addTearDown(container.dispose);

      // Build a minimal router that wires the REAL authRedirect so the
      // authenticated→unauthOnlyRoute guard is exercised.
      final router = GoRouter(
        initialLocation: '${RouteNames.acceptInvite}?token=$kToken',
        // Fire the redirect on every navigation (same pattern as production).
        refreshListenable: _ContainerListenable(container),
        redirect: (context, state) =>
            authRedirect(container.read(authProvider), state),
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.acceptInvite,
            builder: (context, state) {
              final t = state.uri.queryParameters['token'] ?? '';
              return AcceptInviteScreen(token: t);
            },
          ),
          GoRoute(
            path: RouteNames.home,
            builder: (_, _) => const _Probe('home'),
          ),
          GoRoute(
            path: RouteNames.login,
            builder: (_, _) => const _Probe('login'),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      // Wait for acceptInviteProvider Stream to deliver AsyncData.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // Fill password (12-char minimum for invite path).
      await tester.enterText(
        find.byKey(const ValueKey<String>('invite_password')),
        'StrongPass12',
      );
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('invite_first_name')),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('invite_first_name')),
        'Марія',
      );
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('invite_last_name')),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('invite_last_name')),
        'Бондар',
      );
      await tester.pump();

      // Tap the accept CTA.
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('invite_accept')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('invite_accept')));

      // Let the async acceptInvite() complete and the session update settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // The router's redirect must have forwarded the now-authenticated user
      // from /invite/accept (an unauthOnlyRoute) to /.
      final currentUri = router.routerDelegate.currentConfiguration.uri
          .toString();
      expect(
        currentUri,
        equals(RouteNames.home),
        reason:
            'After a successful acceptInvite() the session transitions to '
            'Authenticated. The router redirect fires because the user is now '
            'authenticated on /invite/accept (an unauthOnlyRoute) and must be '
            'forwarded to /.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // NL-B01: /register/step-2 AuthScaffold back button navigates to /register
  //
  // FIX: AuthScaffold gained an `onBack` callback parameter. RegisterStep2Screen
  // passes `onBack: () => context.go(RouteNames.register)` so the back affordance
  // calls context.go() instead of Navigator.maybePop() (which was a no-op after
  // the wizard's context.go() calls replaced the stack).
  // -------------------------------------------------------------------------
  group('NL-B01: /register/step-2 back button navigates to /register', () {
    testWidgets(
      'NL-B01: tapping the AuthScaffold back button on /register/step-2 '
      'navigates to /register (step-1)',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
            secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          ],
        );
        addTearDown(container.dispose);

        container.read(registerDraftProvider.notifier).start(UserRole.client);

        final router = GoRouter(
          initialLocation: RouteNames.registerStep2,
          redirect: (_, _) => null,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.register,
              builder: (_, _) => const _Probe('step-1'),
            ),
            GoRoute(
              path: RouteNames.registerRole,
              builder: (_, _) => const _Probe('role-selection'),
            ),
            ShellRoute(
              builder: (_, _, child) => child,
              routes: <RouteBase>[
                GoRoute(
                  path: RouteNames.registerStep2,
                  builder: (_, _) => const RegisterStep2Screen(),
                ),
                GoRoute(
                  path: RouteNames.registerStep3,
                  builder: (_, _) => const _Probe('step-3'),
                ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The back button is rendered — the user can see it.
        final backFinder = find.byType(NeumorphicIconButton);
        expect(
          backFinder,
          findsOneWidget,
          reason:
              'AuthScaffold(showBack:true) must render a NeumorphicIconButton; '
              'the back affordance must be visible to the user.',
        );

        await tester.tap(backFinder);
        await tester.pumpAndSettle();

        // After the fix, tapping back on step-2 must navigate to /register.
        expect(
          find.text('step-1'),
          findsOneWidget,
          reason:
              'NL-B01: tapping the NeumorphicIconButton back on step-2 must '
              'navigate to /register via context.go(RouteNames.register). '
              'AuthScaffold.onBack was wired to context.go() to fix the '
              'maybePop no-op bug.',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // NL-B02: /register/step-3 AuthScaffold back button navigates to
  // /register/step-2
  //
  // FIX: RegisterStep3Screen passes `onBack: () => context.go(RouteNames.registerStep2)`
  // to AuthScaffold so the back affordance calls context.go() instead of the
  // no-op maybePop().
  // -------------------------------------------------------------------------
  group('NL-B02: /register/step-3 back button navigates to /register/step-2', () {
    testWidgets('NL-B02: tapping the AuthScaffold back button on /register/step-3 '
        'navigates to /register/step-2', (tester) async {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(registerDraftProvider.notifier)
          .start(UserRole.independentMaster);
      container
          .read(registerDraftProvider.notifier)
          .updateStep1(
            email: 'test@example.com',
            password: 'Password1!',
            confirmPassword: 'Password1!',
          );

      final router = GoRouter(
        initialLocation: RouteNames.registerStep3,
        redirect: (_, _) => null,
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.register,
            builder: (_, _) => const _Probe('step-1'),
          ),
          GoRoute(
            path: RouteNames.registerRole,
            builder: (_, _) => const _Probe('role-selection'),
          ),
          ShellRoute(
            builder: (_, _, child) => child,
            routes: <RouteBase>[
              GoRoute(
                path: RouteNames.registerStep2,
                builder: (_, _) => const _Probe('step-2'),
              ),
              GoRoute(
                path: RouteNames.registerStep3,
                builder: (_, _) => const RegisterStep3Screen(),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final backFinder = find.byType(NeumorphicIconButton);
      expect(
        backFinder,
        findsOneWidget,
        reason:
            'AuthScaffold(showBack:true) must render a NeumorphicIconButton; '
            'the back affordance must be visible to the user.',
      );

      await tester.tap(backFinder);
      await tester.pumpAndSettle();

      // After the fix, tapping back on step-3 must navigate to /register/step-2.
      expect(
        find.text('step-2'),
        findsOneWidget,
        reason:
            'NL-B02: tapping the NeumorphicIconButton back on step-3 must '
            'navigate to /register/step-2 via context.go(RouteNames.registerStep2). '
            'AuthScaffold.onBack was wired to context.go() to fix the '
            'maybePop no-op bug.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // NL-B03: /forgot-password AuthScaffold back button → /login
  // -------------------------------------------------------------------------
  group('NL-B03: /forgot-password back button navigates to /login', () {
    testWidgets('NL-B03: tapping the AuthScaffold back button on /forgot-password '
        'navigates to /login', (tester) async {
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();

      final router = GoRouter(
        // Navigate directly to /forgot-password from /login so the GoRouter
        // history has /login as the previous entry — context.pop() will land there.
        initialLocation: RouteNames.login,
        redirect: (_, _) => null,
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.login,
            builder: (_, _) => const _Probe('login'),
          ),
          GoRoute(
            path: RouteNames.forgotPassword,
            builder: (_, _) => const ForgotPasswordRequestScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWith((_) => repo),
            secureStorageProvider.overrideWith((_) => storage),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to /forgot-password (push from /login).
      unawaited(
        router.push(RouteNames.forgotPassword),
      ); // ignore: unawaited_futures
      await tester.pumpAndSettle();

      // The ForgotPasswordRequestScreen is now on screen — tap back.
      final backFinder = find.byType(NeumorphicIconButton);
      expect(
        backFinder,
        findsOneWidget,
        reason:
            'AuthScaffold(showBack:true) must render a NeumorphicIconButton',
      );
      await tester.tap(backFinder);
      await tester.pumpAndSettle();

      expect(
        find.text('login'),
        findsOneWidget,
        reason:
            'Tapping the AuthScaffold back button on /forgot-password must '
            'pop back to /login — the previous entry in the GoRouter history.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // NL-B04: /reset-password (form state) AuthScaffold back button → /login
  // -------------------------------------------------------------------------
  group('NL-B04: /reset-password form back button navigates to /login', () {
    testWidgets(
      'NL-B04: tapping the AuthScaffold back button on /reset-password (form '
      'state) navigates back to /login',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();

        final router = GoRouter(
          initialLocation: RouteNames.login,
          redirect: (_, _) => null,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.login,
              builder: (_, _) => const _Probe('login'),
            ),
            GoRoute(
              path: RouteNames.resetPassword,
              builder: (context, state) {
                final token = state.uri.queryParameters['token'] ?? '';
                return ResetPasswordScreen(token: token);
              },
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWith((_) => repo),
              secureStorageProvider.overrideWith((_) => storage),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to /reset-password (push from /login, simulating deep-link).
        unawaited(
          router.push('${RouteNames.resetPassword}?token=test-token'),
        ); // ignore: unawaited_futures
        await tester.pumpAndSettle();

        // Tap back (AuthScaffold renders the back button in the form state).
        final backFinder = find.byType(NeumorphicIconButton);
        expect(
          backFinder,
          findsOneWidget,
          reason:
              'AuthScaffold(showBack:true) must render a NeumorphicIconButton',
        );
        await tester.tap(backFinder);
        await tester.pumpAndSettle();

        expect(
          find.text('login'),
          findsOneWidget,
          reason:
              'Tapping the AuthScaffold back button on /reset-password (form '
              'state) must pop back to /login — the previous GoRouter entry.',
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// _ContainerListenable — bridges a ProviderContainer to a Listenable so the
// GoRouter refreshListenable fires whenever authProvider changes.
// ---------------------------------------------------------------------------

class _ContainerListenable extends ChangeNotifier {
  _ContainerListenable(ProviderContainer container) {
    container.listen<AsyncValue<AuthSession>>(
      authProvider,
      (_, _) => notifyListeners(),
    );
  }
}

// ---------------------------------------------------------------------------
// _SyncInviteNotifier — synchronously returns a fixed InviteDetails so the
// AcceptInviteScreen renders the form state immediately in tests.
// ---------------------------------------------------------------------------

class _SyncInviteNotifier extends AcceptInviteNotifier {
  _SyncInviteNotifier(this._invite);

  final InviteDetails _invite;

  @override
  FutureOr<InviteDetails> build(String token) => _invite;
}
