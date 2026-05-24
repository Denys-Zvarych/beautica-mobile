// Phase 2.5 — Widget tests for LoginScreen (VelvetTouch neumorphic redesign).
//
// Tests use a minimal GoRouter (initial route = /login → LoginScreen) so that
// context.go / context.push work inside the widget under test. Auth state is
// controlled via ProviderScope overrides.
//
// Design change notes (glassmorphism → VelvetTouch):
//   - Keys renamed: field-email→login_email, field-password→login_password,
//     btn-submit-login→login_submit, btn-forgot-password→login_forgot,
//     btn-go-to-register→login_signup.
//   - No Form wrapper — validation uses inline errorText on NeumorphicTextField.
//   - No BackdropFilter / GlassCard — no glassmorphism tests.
//   - NeumorphicButton owns its own disabled state (onPressed=null).
//   - AuthBanner shown when auth returns EMAIL_NOT_VERIFIED UnauthorizedFailure.
//
// Covered scenarios:
//   1. Valid email + password → submit → login(email, password) is called.
//   2. Invalid email → inline errorText shown on email field, login NOT called.
//   3. While loading (AsyncLoading state) → NeumorphicButton shows spinner,
//      label text is not visible.
//   4. login() results in AsyncError(UnauthorizedFailure) → SnackBar shown.
//   5. login_signup key is present in the widget tree.
//   6. Tapping login_signup navigates to /register/role.
//   7. Tapping login_forgot navigates to /forgot-password.
//   8. EMAIL_NOT_VERIFIED error → AuthBanner shown, no SnackBar.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/login_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a minimal test router with LoginScreen at /login.
GoRouter _makeRouter() => GoRouter(
  initialLocation: RouteNames.login,
  redirect: (context, state) => null,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: RouteNames.registerRole,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('role-selection'))),
    ),
    GoRoute(
      path: RouteNames.home,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('home'))),
    ),
    GoRoute(
      path: RouteNames.forgotPassword,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('forgot-password'))),
    ),
    GoRoute(
      path: RouteNames.verification,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('verification'))),
    ),
  ],
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LoginScreen', () {
    // -----------------------------------------------------------------------
    // Test 1 — Valid form submits login(email, password)
    // -----------------------------------------------------------------------
    testWidgets('1. valid email + password → login(email, password) called', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();
      final router = _makeRouter();
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

      await tester.enterText(
        find.byKey(const ValueKey<String>('login_email')),
        'test@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('login_password')),
        'secret123',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('login_submit')),
      );
      // NeumorphicButton is a GestureDetector at its root — tap it.
      await tester.tap(find.byKey(const ValueKey<String>('login_submit')));
      await tester.pumpAndSettle();

      expect(repo.loginCalls, hasLength(1));
      expect(repo.loginCalls.first.email, equals('test@example.com'));
      expect(repo.loginCalls.first.password, equals('secret123'));
    });

    // -----------------------------------------------------------------------
    // Test 2 — Invalid email → inline errorText shown, login NOT called
    // -----------------------------------------------------------------------
    testWidgets(
      '2. invalid email → inline errorText shown on field, login not called',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
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

        // Enter a clearly invalid email (no @ sign).
        await tester.enterText(
          find.byKey(const ValueKey<String>('login_email')),
          'not-an-email',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('login_password')),
          'password',
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('login_submit')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('login_submit')));
        await tester.pump();

        // NeumorphicTextField renders inline errorText below the field.
        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const ValueKey<String>('login_email'))),
        );
        expect(find.text(l10n.errEmailInvalid), findsOneWidget);

        // No login call should have been made.
        expect(repo.loginCalls, isEmpty);
      },
    );

    // -----------------------------------------------------------------------
    // Test 3 — While loading → NeumorphicButton shows spinner, label hidden
    // -----------------------------------------------------------------------
    testWidgets(
      '3. while AsyncLoading → NeumorphicButton shows CircularProgressIndicator '
      'and label text is not visible',
      (tester) async {
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _LoadingAuthNotifier()),
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
        // pumpAndSettle would hang — the Completer never completes.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.byType(CircularProgressIndicator),
          findsOneWidget,
          reason:
              'NeumorphicButton must show a CircularProgressIndicator when '
              'loading == true',
        );

        // The label text must NOT be visible — the spinner replaces it.
        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(
          find.text(l10n.loginSubmit),
          findsNothing,
          reason:
              'NeumorphicButton label must be hidden while loading == true; '
              'only the CircularProgressIndicator is shown',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 4 — login() error → SnackBar shows the localised failure message
    // -----------------------------------------------------------------------
    testWidgets('4. shows SnackBar with error message on failed login', (
      tester,
    ) async {
      final storage = FakeSecureStorage();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => _ErrorAuthNotifier()),
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

      // Enter a syntactically valid email + password so local validation passes.
      await tester.enterText(
        find.byKey(const ValueKey<String>('login_email')),
        'user@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('login_password')),
        'password',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('login_submit')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('login_submit')));
      await tester.pumpAndSettle();

      // The SnackBar must be present.
      expect(find.byType(SnackBar), findsOneWidget);

      // The message must match the l10n string for UnauthorizedFailure.
      final l10n = AppLocalizations.of(tester.element(find.byType(SnackBar)));
      expect(find.text(l10n.errUnauthorized), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 5 — login_signup key exists
    // -----------------------------------------------------------------------
    testWidgets('5. login_signup key is present in the widget tree', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();
      final router = _makeRouter();
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

      expect(
        find.byKey(const ValueKey<String>('login_signup')),
        findsOneWidget,
      );
    });

    // -----------------------------------------------------------------------
    // Test 6 — Tapping login_signup navigates to /register/role
    // -----------------------------------------------------------------------
    testWidgets(
      '6. tapping login_signup navigates to /register/role placeholder',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
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

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('login_signup')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('login_signup')));
        await tester.pumpAndSettle();

        expect(find.text('role-selection'), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // Test 7 — Tapping login_forgot navigates to /forgot-password
    // -----------------------------------------------------------------------
    testWidgets('7. login_forgot navigates to /forgot-password', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();
      final router = _makeRouter();
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

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('login_forgot')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('login_forgot')));
      await tester.pumpAndSettle();

      expect(find.text('forgot-password'), findsOneWidget);
      // No login attempt was made by tapping the link.
      expect(repo.loginCalls, isEmpty);
    });

    // -----------------------------------------------------------------------
    // Test 9 — Successful login → navigates to /home
    // -----------------------------------------------------------------------
    testWidgets('9. successful login → navigates to home screen', (
      tester,
    ) async {
      // FakeAuthRepository.login defaults to success (returns _defaultUser +
      // _defaultTokens) when loginResult is null, which puts authProvider into
      // AsyncData(authenticated). The screen should then call context.go('/home').
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();
      final router = _makeRouter();
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

      await tester.enterText(
        find.byKey(const ValueKey<String>('login_email')),
        'test@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('login_password')),
        'secret123',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('login_submit')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('login_submit')));
      await tester.pumpAndSettle();

      // After a successful login authProvider transitions to authenticated and
      // LoginScreen calls context.go(RouteNames.home).
      expect(
        find.text('home'),
        findsOneWidget,
        reason:
            'LoginScreen must navigate to /home after a successful login; '
            'the test router renders "home" text on that route',
      );
    });

    // -----------------------------------------------------------------------
    // Test 10 — Empty password → inline errorText shown, login NOT called
    // -----------------------------------------------------------------------
    testWidgets(
      '10. empty password → errPasswordRequired shown on field, login not called',
      (tester) async {
        final repo = FakeAuthRepository();
        final storage = FakeSecureStorage();
        final router = _makeRouter();
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

        // Valid email, but password field left empty.
        await tester.enterText(
          find.byKey(const ValueKey<String>('login_email')),
          'valid@example.com',
        );
        // Explicitly clear the password field (default is empty, but be explicit).
        await tester.enterText(
          find.byKey(const ValueKey<String>('login_password')),
          '',
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('login_submit')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('login_submit')));
        await tester.pump();

        // NeumorphicTextField renders inline errorText for the password field.
        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const ValueKey<String>('login_password'))),
        );
        expect(
          find.text(l10n.errPasswordRequired),
          findsOneWidget,
          reason:
              'validatePassword must return errPasswordRequired for empty input '
              'and LoginScreen must surface it as inline errorText',
        );

        // No network call should have been made.
        expect(repo.loginCalls, isEmpty);
      },
    );

    // -----------------------------------------------------------------------
    // Test 11 — AuthBanner action tap → navigates to /verification
    // -----------------------------------------------------------------------
    testWidgets(
      '11. tapping AuthBanner action after EMAIL_NOT_VERIFIED navigates to '
      '/verification',
      (tester) async {
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _UnverifiedAuthNotifier()),
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

        // Trigger the EMAIL_NOT_VERIFIED state.
        await tester.enterText(
          find.byKey(const ValueKey<String>('login_email')),
          'unverified@example.com',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('login_password')),
          'password',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('login_submit')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('login_submit')));
        await tester.pumpAndSettle();

        // AuthBanner must be present before we tap its action.
        expect(find.byType(AuthBanner), findsOneWidget);

        // The action label is localised — tap it by text (AuthBanner renders
        // a plain GestureDetector with no Key; tracked as LOW M2 finding).
        final l10n = AppLocalizations.of(
          tester.element(find.byType(AuthBanner)),
        );
        await tester.tap(find.text(l10n.loginUnverifiedAction));
        await tester.pumpAndSettle();

        // The test router renders "verification" text at /verification.
        expect(
          find.text('verification'),
          findsOneWidget,
          reason:
              'Tapping the AuthBanner action must navigate to /verification '
              'so the user can complete email verification without re-entering '
              'their address',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 8 — EMAIL_NOT_VERIFIED → AuthBanner shown, no SnackBar
    // -----------------------------------------------------------------------
    testWidgets(
      '8. EMAIL_NOT_VERIFIED error → AuthBanner shown instead of SnackBar',
      (tester) async {
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _UnverifiedAuthNotifier()),
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

        await tester.enterText(
          find.byKey(const ValueKey<String>('login_email')),
          'unverified@example.com',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('login_password')),
          'password',
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('login_submit')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('login_submit')));
        await tester.pumpAndSettle();

        // AuthBanner must be visible (rendered as a NeumorphicCard inside the
        // auth_scaffold.dart AuthBanner widget).
        expect(
          find.byType(AuthBanner),
          findsOneWidget,
          reason:
              'AuthBanner must appear when login returns EMAIL_NOT_VERIFIED; '
              'no SnackBar should be shown',
        );

        // No floating SnackBar should appear for the unverified case.
        expect(
          find.byType(SnackBar),
          findsNothing,
          reason:
              'SnackBar must NOT appear for EMAIL_NOT_VERIFIED — '
              'the AuthBanner is the inline feedback for this state',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 12 — VelvetLogo present; VelvetHeader absent (layout regression)
    //
    // Phase 2.x replaced `VelvetHeader()` on the login screen with
    // `Center(child: VelvetLogo(compact: true))` so the logo sits at the same
    // vertical position as the icon tiles on the register/wizard screens.
    // -----------------------------------------------------------------------
    testWidgets('12. VelvetLogo(compact) is present and VelvetHeader is absent '
        '(layout parity with wizard icon tiles)', (tester) async {
      final repo = FakeAuthRepository();
      final storage = FakeSecureStorage();
      final router = _makeRouter();
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

      // The compact VelvetLogo must be rendered exactly once.
      expect(
        find.byType(VelvetLogo),
        findsOneWidget,
        reason:
            'LoginScreen must render VelvetLogo(compact: true) after '
            'VelvetHeader was replaced in the Phase 2.x layout alignment.',
      );

      // VelvetHeader must NOT be in the tree — it carries extra topSpacing
      // (VelvetSpacing.sm) that offset the logo below the wizard icon tiles.
      expect(
        find.byType(VelvetHeader),
        findsNothing,
        reason:
            'VelvetHeader must be absent — it was replaced with '
            'Center(child: VelvetLogo(compact: true)) + SizedBox(lg) '
            'so the logo aligns with icon tiles on all other auth screens.',
      );

      // VelvetLogo must render the wordmark text.
      expect(
        find.text('beautica'),
        findsOneWidget,
        reason: 'VelvetLogo must render the "beautica" wordmark text.',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// AuthNotifier stubs
// ---------------------------------------------------------------------------

/// Returns [UnauthorizedFailure] (generic) on login — triggers the SnackBar path.
class _ErrorAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();

  @override
  Future<void> login(String email, String password) async {
    state = const AsyncError(UnauthorizedFailure(), StackTrace.empty);
  }
}

/// Stays in [AsyncLoading] indefinitely — tests the spinner + disabled state.
class _LoadingAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    final completer = Completer<AuthSession>();
    ref.onDispose(() {
      if (!completer.isCompleted) {
        completer.complete(const AuthSession.unauthenticated());
      }
    });
    return completer.future;
  }
}

/// Returns [UnauthorizedFailure] with [emailNotVerified] = true — triggers
/// the inline [AuthBanner] path instead of the SnackBar.
///
/// MEDIUM-2 (mobile-security 2026-05-24): the screen now checks
/// `e.emailNotVerified` (a typed field set by ErrorMapperInterceptor) instead
/// of the fragile `e.cause?.toString().contains('EMAIL_NOT_VERIFIED')` probe.
/// The test must therefore set `emailNotVerified: true`, not put the string in
/// `cause`.
class _UnverifiedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();

  @override
  Future<void> login(String email, String password) async {
    state = const AsyncError(
      UnauthorizedFailure(emailNotVerified: true),
      StackTrace.empty,
    );
  }
}
