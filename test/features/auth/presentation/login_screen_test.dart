// Phase 2.5 — Widget tests for LoginScreen.
//
// Tests use a minimal GoRouter (initial route = /login → LoginScreen) so that
// context.go / context.push work inside the widget under test. Auth state is
// controlled via ProviderScope overrides.
//
// Covered scenarios:
//   1. Valid email + password → submit → login(email, password) is called.
//   2. Invalid email → validator error shown, login NOT called.
//   3. While loading (AsyncLoading state) → submit button is disabled.
//   4. login() results in AsyncError(UnauthorizedFailure) → SnackBar shown.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/login_screen.dart';
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
/// A placeholder occupies / (home) so navigation after login works.
GoRouter _makeRouter() => GoRouter(
  initialLocation: RouteNames.login,
  redirect: (context, state) => null,
  routes: [
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: RouteNames.register,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('register'))),
    ),
    GoRoute(
      path: RouteNames.home,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('home'))),
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
        find.byKey(const Key('field-email')),
        'test@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('field-password')),
        'secret123',
      );

      await tester.ensureVisible(find.byKey(const Key('btn-submit-login')));
      await tester.tap(find.byKey(const Key('btn-submit-login')));
      await tester.pumpAndSettle();

      expect(repo.loginCalls, hasLength(1));
      expect(repo.loginCalls.first.email, equals('test@example.com'));
      expect(repo.loginCalls.first.password, equals('secret123'));
    });

    // -----------------------------------------------------------------------
    // Test 2 — Invalid email → validator error shown, login NOT called
    // -----------------------------------------------------------------------
    testWidgets('2. invalid email → validator error shown, login not called', (
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

      // Enter a clearly invalid email (no @ sign).
      await tester.enterText(
        find.byKey(const Key('field-email')),
        'not-an-email',
      );
      await tester.enterText(
        find.byKey(const Key('field-password')),
        'password',
      );

      await tester.ensureVisible(find.byKey(const Key('btn-submit-login')));
      await tester.tap(find.byKey(const Key('btn-submit-login')));
      await tester.pump();

      // Validator error should be shown.
      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('field-email'))),
      );
      expect(find.text(l10n.errEmailInvalid), findsOneWidget);

      // No login call should have been made.
      expect(repo.loginCalls, isEmpty);
    });

    // -----------------------------------------------------------------------
    // Test 3 — While loading → submit button is disabled
    // -----------------------------------------------------------------------
    testWidgets('3. while AsyncLoading → submit button is disabled', (
      tester,
    ) async {
      final storage = FakeSecureStorage();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Override authProvider with a notifier that stays in AsyncLoading.
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
      // pumpAndSettle would hang — the Completer in _LoadingAuthNotifier never
      // settles. A single pump + short delay is sufficient to trigger the first
      // frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The CTA is now DecoratedBox → ClipRRect → Material → InkWell (Impeller
      // fix). The Key is on the outer GestureDetector; find InkWell underneath.
      final inkWell = tester.widget<InkWell>(
        find.descendant(
          of: find.byKey(const Key('btn-submit-login')),
          matching: find.byType(InkWell),
        ),
      );
      expect(inkWell.onTap, isNull);
    });
    // -----------------------------------------------------------------------
    // Test 3b — While loading → CTA button shows CircularProgressIndicator
    //           and hides the label text
    // -----------------------------------------------------------------------
    testWidgets(
      '3b. while AsyncLoading → CTA button shows CircularProgressIndicator '
      'and label text is not visible',
      (tester) async {
        final storage = FakeSecureStorage();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              // Override authProvider with a notifier that stays in AsyncLoading.
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
        // pumpAndSettle would hang — the Completer in _LoadingAuthNotifier never
        // settles. A single pump + short delay triggers the first frame.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // The _MochaCtaButton renders a CircularProgressIndicator when
        // isLoading == true (driven by authState.isLoading).
        expect(
          find.byType(CircularProgressIndicator),
          findsOneWidget,
          reason:
              '_MochaCtaButton must show a CircularProgressIndicator inside '
              'btn-submit-login when authProvider is in AsyncLoading state',
        );

        // The label text must NOT be visible — the spinner replaces it.
        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(
          find.text(l10n.loginSubmit),
          findsNothing,
          reason:
              'The CTA button label must be hidden while isLoading == true; '
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
            // Override authProvider with a notifier that immediately errors
            // when login() is called.
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
        find.byKey(const Key('field-email')),
        'user@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('field-password')),
        'password',
      );

      await tester.ensureVisible(find.byKey(const Key('btn-submit-login')));
      await tester.tap(find.byKey(const Key('btn-submit-login')));
      await tester.pumpAndSettle();

      // The SnackBar must be present.
      expect(find.byType(SnackBar), findsOneWidget);

      // The message must match the l10n string for UnauthorizedFailure.
      final l10n = AppLocalizations.of(tester.element(find.byType(SnackBar)));
      expect(find.text(l10n.errUnauthorized), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 5 — btn-go-to-register key exists
    // -----------------------------------------------------------------------
    testWidgets('5. btn-go-to-register key is present in the widget tree', (
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

      expect(find.byKey(const Key('btn-go-to-register')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 6 — tapping btn-go-to-register navigates to /register
    // -----------------------------------------------------------------------
    testWidgets(
      '6. tapping btn-go-to-register navigates to /register placeholder',
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

        // AuthScaffold wraps content in a SingleChildScrollView, so the
        // "go to register" link can flow below the default 800x600 test
        // viewport fold. Scroll it into view before tapping or the
        // hit-test misses and navigation never fires.
        await tester.ensureVisible(find.byKey(const Key('btn-go-to-register')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn-go-to-register')));
        await tester.pumpAndSettle();

        // The /register route renders the 'register' placeholder text.
        expect(find.text('register'), findsOneWidget);
      },
    );
    // -----------------------------------------------------------------------
    // Test 7 — _GlassCard BackdropFilter exists (glassmorphism regression guard)
    // -----------------------------------------------------------------------
    testWidgets('7. glass card contains a BackdropFilter with sigma 20', (
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

      // Both _BrandRow (sigma 8) and _GlassCard (sigma 20) use BackdropFilter.
      expect(
        find.byType(BackdropFilter),
        findsWidgets,
        reason:
            '_GlassCard must contain a BackdropFilter; '
            'removing it breaks the glassmorphism effect',
      );

      // At least one BackdropFilter must use sigma 20 (_GlassCard._kBlur).
      final filters = tester
          .widgetList<BackdropFilter>(find.byType(BackdropFilter))
          .toList();
      final hasCardSigma = filters.any(
        (bf) => bf.filter.toString().contains('20'),
      );
      expect(
        hasCardSigma,
        isTrue,
        reason:
            'Expected a BackdropFilter with sigma 20 (_GlassCard._kBlur); '
            'sigma must remain 20 to match the HTML backdrop-filter: blur(20px)',
      );
    });
  });
}

/// AuthNotifier stub that transitions to [AsyncError<UnauthorizedFailure>]
/// when [login] is called and immediately returns [Unauthenticated] on build.
class _ErrorAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();

  @override
  Future<void> login(String email, String password) async {
    state = const AsyncError(UnauthorizedFailure(), StackTrace.empty);
  }
}

/// AuthNotifier stub that stays in [AsyncLoading] indefinitely.
///
/// Uses a [Completer] that is never completed, and is cancelled via
/// [ref.onDispose] to avoid "pending timers" test failures.
class _LoadingAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    // Never completing completer — no pending timer unlike Future.delayed.
    final completer = Completer<AuthSession>();
    ref.onDispose(() {
      if (!completer.isCompleted) {
        completer.complete(const AuthSession.unauthenticated());
      }
    });
    return completer.future;
  }
}
