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
//      that could break tests).

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
Future<ProviderContainer> _makeAuthenticatedContainer() async {
  final storage = FakeSecureStorage();
  await storage.writeRefreshToken('stored-refresh');

  final repo = FakeAuthRepository()
    ..refreshResult = _testTokens
    ..meResult = _testUser;

  final container = _makeContainer(storage: storage, repo: repo);
  // Wait for cold-start to complete.
  await container.read(authProvider.future);

  return container;
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
      final container = await _makeAuthenticatedContainer();

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
      final container = await _makeAuthenticatedContainer();

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
    });
  });
}
