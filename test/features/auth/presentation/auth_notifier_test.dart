// Phase 2.4 — Unit tests for AuthNotifier.
//
// Tests use a ProviderContainer with overrides so neither Dio nor platform
// channels are involved. FakeSecureStorage provides in-memory storage;
// MockAuthRepository (mocktail) stubs the network boundary.
//
// Coverage:
//   1. Cold start — no refresh token → Unauthenticated (no repo calls).
//   2. Cold start — valid refresh token → Authenticated (session restored).
//   3. Cold start — stale token throws UnauthorizedFailure → Unauthenticated
//      and storage is wiped.
//   4. login success → Authenticated with correct user + token; refresh token
//      persisted to storage.
//   5. logout → Unauthenticated; storage is empty.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';

import '../../../helpers/fakes/fake_secure_storage.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  const testUser = User(
    id: 'u1',
    email: 'test@example.com',
    role: UserRole.independentMaster,
    firstName: 'Test',
    lastName: 'User',
  );
  const testTokens = AuthTokens(
    accessToken: 'access-123',
    refreshToken: 'refresh-456',
  );
  const rotatedTokens = AuthTokens(
    accessToken: 'access-rotated',
    refreshToken: 'refresh-rotated',
  );

  ProviderContainer makeContainer({
    required AuthRepository repo,
    required FakeSecureStorage storage,
  }) {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((_) => repo),
        secureStorageProvider.overrideWith((_) => storage),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('AuthNotifier', () {
    // -----------------------------------------------------------------------
    // Test 1 — Cold start with no stored refresh token
    // -----------------------------------------------------------------------
    test(
      'cold start: no refresh token → Unauthenticated, no repo calls',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage(); // empty — no tokens written

        final container = makeContainer(repo: repo, storage: storage);
        final session = await container.read(authProvider.future);

        expect(session, equals(const AuthSession.unauthenticated()));

        // The repository must never be called when there is no stored token.
        verifyNever(() => repo.refresh(any()));
        verifyNever(() => repo.me());
      },
    );

    // -----------------------------------------------------------------------
    // Test 2 — Cold start with a valid refresh token
    // -----------------------------------------------------------------------
    test(
      'cold start: valid refresh token → Authenticated session restored',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();
        await storage.writeRefreshToken('stored-refresh');

        when(
          () => repo.refresh('stored-refresh'),
        ).thenAnswer((_) async => rotatedTokens);
        when(() => repo.me()).thenAnswer((_) async => testUser);

        final container = makeContainer(repo: repo, storage: storage);
        final session = await container.read(authProvider.future);

        expect(
          session,
          equals(
            AuthSession.authenticated(
              user: testUser,
              accessToken: rotatedTokens.accessToken,
            ),
          ),
        );

        // The rotated refresh token must be persisted; access token must NOT.
        expect(
          await storage.readRefreshToken(),
          equals(rotatedTokens.refreshToken),
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 3 — Cold start with a stale (expired/revoked) refresh token
    // -----------------------------------------------------------------------
    test('cold start: stale token throws UnauthorizedFailure '
        '→ Unauthenticated and storage wiped', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();
      await storage.writeRefreshToken('expired-refresh');

      when(
        () => repo.refresh('expired-refresh'),
      ).thenThrow(const UnauthorizedFailure());

      final container = makeContainer(repo: repo, storage: storage);
      final session = await container.read(authProvider.future);

      expect(session, equals(const AuthSession.unauthenticated()));

      // Storage must be wiped so the next cold start skips the refresh attempt.
      expect(await storage.readRefreshToken(), isNull);

      // me() must not be called when refresh has already failed.
      verifyNever(() => repo.me());
    });

    // -----------------------------------------------------------------------
    // Test 4 — Successful login
    // -----------------------------------------------------------------------
    test(
      'login success → Authenticated with correct user and token persisted',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage(); // no pre-existing session

        // Cold start resolves to Unauthenticated (no stored token).
        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        when(
          () => repo.login(email: 'test@example.com', password: 'pass123'),
        ).thenAnswer((_) async => (testUser, testTokens));

        await container
            .read(authProvider.notifier)
            .login('test@example.com', 'pass123');

        final value = container.read(authProvider);

        expect(value, isA<AsyncData<AuthSession>>());
        expect(
          value.value,
          equals(
            AuthSession.authenticated(
              user: testUser,
              accessToken: testTokens.accessToken,
            ),
          ),
        );

        // Only the refresh token is persisted; access token is in-memory only.
        expect(
          await storage.readRefreshToken(),
          equals(testTokens.refreshToken),
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 5 — Logout
    // -----------------------------------------------------------------------
    test('logout → Unauthenticated and storage is empty', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();
      await storage.writeRefreshToken('stored-refresh');

      when(
        () => repo.refresh('stored-refresh'),
      ).thenAnswer((_) async => testTokens);
      when(() => repo.me()).thenAnswer((_) async => testUser);
      when(() => repo.logout()).thenAnswer((_) async {});

      final container = makeContainer(repo: repo, storage: storage);
      // Wait for the cold-start to complete (Authenticated).
      await container.read(authProvider.future);

      await container.read(authProvider.notifier).logout();

      final value = container.read(authProvider);
      expect(value, isA<AsyncData<AuthSession>>());
      expect(value.value, equals(const AuthSession.unauthenticated()));

      // All tokens must be wiped from storage.
      expect(await storage.readRefreshToken(), isNull);
    });
  });
}
