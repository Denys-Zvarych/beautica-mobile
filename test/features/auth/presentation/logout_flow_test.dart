// Phase 2.8 — Unit tests for the logout flow in AuthNotifier.
//
// Uses a ProviderContainer with FakeSecureStorage + FakeAuthRepository.
// No Dio, no platform channels.
//
// Covered scenarios:
//   1. logout() wipes tokens; state becomes Unauthenticated.
//   2. logout() tolerates server 4xx (repo throws UnauthorizedFailure);
//      state still becomes Unauthenticated and deleteAll is still called.
//   3. Calling logout() twice is idempotent (no crash, no duplicate side effects
//      that could break tests). Asserts logoutCallCount == 2.
//   4. SettingsScreen widget-layer: tap Key('btn-logout') → logout() called →
//      navigate to /login.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/settings/presentation/settings_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _testUser = User(
  id: 'u1',
  email: 'master@beautica.test',
  role: UserRole.independentMaster,
  firstName: 'Test',
  lastName: 'User',
);

const _testTokens = AuthTokens(
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer({
  required FakeSecureStorage storage,
  required FakeAuthRepository repo,
}) {
  final container = ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWith((_) => storage),
      authRepositoryProvider.overrideWith((_) => repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Seeds storage and repo so cold-start resolves to Authenticated.
///
/// Returns both the [ProviderContainer] and the [FakeAuthRepository] so that
/// callers can assert on [FakeAuthRepository.logoutCallCount] without
/// re-reading from the container (which would require a cast).
Future<(ProviderContainer, FakeAuthRepository)>
_makeAuthenticatedContainer() async {
  final storage = FakeSecureStorage();
  await storage.writeRefreshToken('stored-refresh');

  final repo = FakeAuthRepository()
    ..refreshResult = _testTokens
    ..meResult = _testUser;

  final container = _makeContainer(storage: storage, repo: repo);
  // Wait for cold-start to complete.
  await container.read(authProvider.future);

  return (container, repo);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AuthNotifier.logout', () {
    // -----------------------------------------------------------------------
    // Test 1 — logout wipes tokens; state becomes Unauthenticated
    // -----------------------------------------------------------------------
    test('should wipe tokens and set state to Unauthenticated', () async {
      final (container, _) = await _makeAuthenticatedContainer();

      // Verify we start Authenticated.
      expect(container.read(authProvider).value, isA<Authenticated>());

      // Verify refresh token is in storage.
      final storage = container.read(secureStorageProvider);
      expect(await storage.readRefreshToken(), isNotNull);

      await container.read(authProvider.notifier).logout();

      // State must be Unauthenticated.
      final afterState = container.read(authProvider);
      expect(afterState, isA<AsyncData<AuthSession>>());
      expect(afterState.value, equals(const AuthSession.unauthenticated()));

      // Storage must be empty.
      expect(await storage.readRefreshToken(), isNull);
    });

    // -----------------------------------------------------------------------
    // Test 2 — logout tolerates server 4xx; state still Unauthenticated
    // -----------------------------------------------------------------------
    test(
      'should tolerate server error on logout; state still becomes Unauthenticated',
      () async {
        final storage = FakeSecureStorage();
        await storage.writeRefreshToken('stored-refresh');

        final repo = FakeAuthRepository()
          ..refreshResult = _testTokens
          ..meResult = _testUser
          ..logoutThrows = true; // repo.logout() will throw UnauthorizedFailure

        final container = _makeContainer(storage: storage, repo: repo);
        await container.read(authProvider.future);

        // Logout must NOT throw despite repo throwing.
        // Direct await — if logout() throws, the test fails.
        await container.read(authProvider.notifier).logout();

        // State must still be Unauthenticated.
        final afterState = container.read(authProvider);
        expect(afterState.value, equals(const AuthSession.unauthenticated()));

        // Storage must still be wiped.
        expect(await storage.readRefreshToken(), isNull);
      },
    );

    // -----------------------------------------------------------------------
    // Test 3 — logout is idempotent (calling twice doesn't crash)
    // -----------------------------------------------------------------------
    test('calling logout twice is idempotent', () async {
      final (container, repo) = await _makeAuthenticatedContainer();

      await container.read(authProvider.notifier).logout();
      // Second call on already-unauthenticated state must be safe.
      await expectLater(
        () => container.read(authProvider.notifier).logout(),
        returnsNormally,
      );

      expect(
        container.read(authProvider).value,
        equals(const AuthSession.unauthenticated()),
      );

      // Repository must have been called both times — no idempotency short-circuit.
      expect(repo.logoutCallCount, equals(2));
    });

    // -----------------------------------------------------------------------
    // Test 4 — SettingsScreen widget-layer logout
    // -----------------------------------------------------------------------
    testWidgets(
      'tapping btn-logout in SettingsScreen calls logout and navigates to /login',
      (tester) async {
        final storage = FakeSecureStorage();
        await storage.writeRefreshToken('stored-refresh');

        final repo = FakeAuthRepository()
          ..refreshResult = _testTokens
          ..meResult = _testUser;

        final router = GoRouter(
          initialLocation: RouteNames.settings,
          redirect: (context, state) => null,
          routes: [
            GoRoute(
              path: RouteNames.settings,
              builder: (context, state) => const SettingsScreen(),
            ),
            GoRoute(
              path: RouteNames.login,
              builder: (context, state) =>
                  const Scaffold(body: Center(child: Text('login'))),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              secureStorageProvider.overrideWith((_) => storage),
              authRepositoryProvider.overrideWith((_) => repo),
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

        // Tap the logout tile.
        await tester.tap(find.byKey(const Key('btn-logout')));
        await tester.pumpAndSettle();

        // The router must have navigated to /login.
        expect(find.text('login'), findsOneWidget);

        // The repository logout method must have been called once.
        expect(repo.logoutCallCount, equals(1));
      },
    );
  });
}
