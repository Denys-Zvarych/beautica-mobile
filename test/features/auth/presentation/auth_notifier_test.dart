// Phase 2.4 — Unit tests for AuthNotifier.
//
// Tests use a ProviderContainer with overrides so neither Dio nor platform
// channels are involved. FakeSecureStorage provides in-memory storage;
// MockAuthRepository (mocktail) stubs the network boundary.
//
// Coverage:
//   1.  Cold start — no refresh token → Unauthenticated (no repo calls).
//   2.  Cold start — valid refresh token → Authenticated (session restored).
//   3.  Cold start — stale token throws UnauthorizedFailure → Unauthenticated
//       and storage is wiped.
//   4.  login success → Authenticated with correct user + token; refresh token
//       persisted to storage.
//   5.  logout → Unauthenticated; storage is empty.
//   ...
//   Phase 2.11 additions:
//   verifyEmail group — success, Failure rethrow, UnimplementedError rethrow.
//   resendCode group  — success, Failure rethrow.

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
  setUpAll(() {
    // Required by mocktail when `any(named: 'role')` is used for a UserRole
    // parameter. Registers a fallback so mocktail can construct the matcher
    // without a TypeError in sound null-safe Dart.
    registerFallbackValue(UserRole.independentMaster);
  });

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

    // -----------------------------------------------------------------------
    // Test 6 — register success
    // -----------------------------------------------------------------------
    test(
      'register success → Authenticated, refresh token persisted, access token in state',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage(); // empty — no pre-existing session

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        when(
          () => repo.registerIndependentMaster(
            email: 'new@example.com',
            password: 'pass123',
            firstName: 'Іван',
            lastName: 'Коваль',
            role: UserRole.independentMaster,
          ),
        ).thenAnswer((_) async => (testUser, testTokens));

        await container
            .read(authProvider.notifier)
            .register(
              email: 'new@example.com',
              password: 'pass123',
              firstName: 'Іван',
              lastName: 'Коваль',
            );

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

        // Only the refresh token is persisted.
        expect(
          await storage.readRefreshToken(),
          equals(testTokens.refreshToken),
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 7 — register ValidationFailure
    // -----------------------------------------------------------------------
    test(
      'register ValidationFailure → AsyncError with ValidationFailure',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        const failure = ValidationFailure(fieldErrors: {'email': 'taken'});
        when(
          () => repo.registerIndependentMaster(
            email: any(named: 'email'),
            password: any(named: 'password'),
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
            role: any(named: 'role'),
          ),
        ).thenThrow(failure);

        await container
            .read(authProvider.notifier)
            .register(
              email: 'dup@example.com',
              password: 'pass123',
              firstName: 'Test',
              lastName: 'User',
            );

        final value = container.read(authProvider);
        expect(value, isA<AsyncError<AuthSession>>());
        expect(value.error, isA<ValidationFailure>());
        expect(
          (value.error as ValidationFailure).fieldErrors,
          equals({'email': 'taken'}),
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 8 — login UnauthorizedFailure
    // -----------------------------------------------------------------------
    test(
      'login UnauthorizedFailure → AsyncError with UnauthorizedFailure',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        when(
          () => repo.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenThrow(const UnauthorizedFailure());

        await container
            .read(authProvider.notifier)
            .login('bad@example.com', 'wrongpass');

        final value = container.read(authProvider);
        expect(value, isA<AsyncError<AuthSession>>());
        expect(value.error, isA<UnauthorizedFailure>());
      },
    );

    // -----------------------------------------------------------------------
    // Test 9 — login NetworkFailure
    // -----------------------------------------------------------------------
    test('login NetworkFailure → AsyncError with NetworkFailure', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      when(
        () => repo.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(const NetworkFailure());

      await container
          .read(authProvider.notifier)
          .login('test@example.com', 'pass123');

      final value = container.read(authProvider);
      expect(value, isA<AsyncError<AuthSession>>());
      expect(value.error, isA<NetworkFailure>());
    });

    // -----------------------------------------------------------------------
    // Test 10 — cold-start raw exception (non-Failure)
    // -----------------------------------------------------------------------
    test(
      'cold start: raw Exception (non-Failure) from repo.refresh → AsyncError',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();
        await storage.writeRefreshToken('stored-refresh');

        // Throw a raw exception that is NOT a Failure subclass.
        // build() catches only `on Failure` — raw exceptions propagate and
        // Riverpod's AsyncNotifier machinery sets state = AsyncError<Exception>.
        when(
          () => repo.refresh('stored-refresh'),
        ).thenThrow(Exception('format error'));

        final container = makeContainer(repo: repo, storage: storage);

        // Trigger build by reading — do NOT await .future because the raw
        // exception may cause it to never resolve in certain Riverpod versions.
        // Instead, listen to state transitions via a subscription and wait for
        // the state to settle away from AsyncLoading.
        container.read(authProvider); // trigger build

        // Poll until state is no longer AsyncLoading (max 2 seconds).
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          final v = container.read(authProvider);
          if (!v.isLoading) break;
        }

        final value = container.read(authProvider);
        // In Riverpod 3.x, an uncaught exception in AsyncNotifier.build() causes
        // the provider to enter retry mode: the state becomes AsyncLoading with
        // a non-null .error (i.e. the exception is captured and available).
        // We assert the error is exposed regardless of whether the state is
        // AsyncError or AsyncLoading(retrying: true) — both indicate the raw
        // exception was not silently swallowed.
        expect(value.error, isA<Exception>());
      },
    );

    // -----------------------------------------------------------------------
    // Test 11 — logout from Unauthenticated (idempotency)
    // -----------------------------------------------------------------------
    test(
      'logout from Unauthenticated initial state → no crash, state stays Unauthenticated',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage(); // empty — no stored token

        when(() => repo.logout()).thenAnswer((_) async {});

        final container = makeContainer(repo: repo, storage: storage);
        // Cold start with no token → Unauthenticated.
        await container.read(authProvider.future);

        // logout() from Unauthenticated must not throw.
        await expectLater(
          () => container.read(authProvider.notifier).logout(),
          returnsNormally,
        );

        final value = container.read(authProvider);
        expect(value.value, equals(const AuthSession.unauthenticated()));

        // Storage was already empty — deleteAll() on an empty store must not throw.
        expect(await storage.readRefreshToken(), isNull);
      },
    );

    // -----------------------------------------------------------------------
    // Test 12 — setAccessToken updates in-memory access token when Authenticated
    // -----------------------------------------------------------------------
    test(
      'setAccessToken updates in-memory access token when Authenticated',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();
        await storage.writeRefreshToken('stored-refresh');

        when(
          () => repo.refresh('stored-refresh'),
        ).thenAnswer((_) async => rotatedTokens);
        when(() => repo.me()).thenAnswer((_) async => testUser);

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        // State is now Authenticated with rotatedTokens.accessToken.
        container.read(authProvider.notifier).setAccessToken('brand-new-token');

        final value = container.read(authProvider);
        final session = value.value;
        expect(session, isA<Authenticated>());
        expect(
          (session as Authenticated).accessToken,
          equals('brand-new-token'),
        );
        // User must be unchanged.
        expect(session.user, equals(testUser));
      },
    );

    // -----------------------------------------------------------------------
    // Test 13 — setAccessToken is a no-op when Unauthenticated
    // -----------------------------------------------------------------------
    test('setAccessToken is a no-op when Unauthenticated', () async {
      final repo = MockAuthRepository();
      final storage =
          FakeSecureStorage(); // no stored token → cold start → Unauthenticated

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      // Must not throw and must not change state.
      container.read(authProvider.notifier).setAccessToken('irrelevant-token');

      final value = container.read(authProvider);
      expect(value.value, equals(const AuthSession.unauthenticated()));
    });

    // -----------------------------------------------------------------------
    // Test 14 — register passes businessName through to the repository
    // -----------------------------------------------------------------------
    test(
      'register with businessName → businessName forwarded to repository',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        when(
          () => repo.registerIndependentMaster(
            email: 'owner@example.com',
            password: 'pass123',
            firstName: 'Олена',
            lastName: 'Бойко',
            role: UserRole.salonOwner,
            businessName: 'Краса Студія',
          ),
        ).thenAnswer((_) async => (testUser, testTokens));

        await container
            .read(authProvider.notifier)
            .register(
              email: 'owner@example.com',
              password: 'pass123',
              firstName: 'Олена',
              lastName: 'Бойко',
              role: UserRole.salonOwner,
              businessName: 'Краса Студія',
            );

        final value = container.read(authProvider);
        // Strict stub: if businessName were dropped the stub would not match and
        // the call would throw MissingStubError, failing this test.
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
      },
    );

    // -----------------------------------------------------------------------
    // Test 15 — register with null businessName (independentMaster default)
    //           passes null through, not an empty string
    // -----------------------------------------------------------------------
    test(
      'register without businessName → null forwarded to repository, not empty string',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        // Strict stub: businessName is absent from named args (defaults to null).
        // If the notifier passed '' instead of null, this stub would not match.
        when(
          () => repo.registerIndependentMaster(
            email: 'master@example.com',
            password: 'pass123',
            firstName: 'Іван',
            lastName: 'Коваль',
            role: UserRole.independentMaster,
          ),
        ).thenAnswer((_) async => (testUser, testTokens));

        await container
            .read(authProvider.notifier)
            .register(
              email: 'master@example.com',
              password: 'pass123',
              firstName: 'Іван',
              lastName: 'Коваль',
              // role and businessName use defaults (independentMaster, null)
            );

        final value = container.read(authProvider);
        expect(value, isA<AsyncData<AuthSession>>());
      },
    );

    // -----------------------------------------------------------------------
    // Test 16 — register with address and phone forwards both to repository
    // -----------------------------------------------------------------------
    test('register with address and phone forwards both to repository', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      // Strict stub — all named params are exact matches, including address
      // and phone. If the notifier drops either field the stub will not match
      // and mocktail will throw MissingStubError, failing this test.
      // That is the intended regression guard.
      when(
        () => repo.registerIndependentMaster(
          email: 'owner@example.com',
          password: 'pass123',
          firstName: 'Олена',
          lastName: 'Бойко',
          role: UserRole.salonOwner,
          businessName: 'Краса Студія',
          address: 'вул. Хрещатик, 1',
          phone: '+380501234567',
        ),
      ).thenAnswer((_) async => (testUser, testTokens));

      await container
          .read(authProvider.notifier)
          .register(
            email: 'owner@example.com',
            password: 'pass123',
            firstName: 'Олена',
            lastName: 'Бойко',
            role: UserRole.salonOwner,
            businessName: 'Краса Студія',
            address: 'вул. Хрещатик, 1',
            phone: '+380501234567',
          );

      final value = container.read(authProvider);
      // If either address or phone was silently dropped by the notifier the
      // strict stub above would not have matched and we would never reach here.
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
    });
  });

  // =========================================================================
  // Phase 2.11 — verifyEmail (QA HIGH-2 fix)
  // =========================================================================
  group('verifyEmail', () {
    // -----------------------------------------------------------------------
    // verifyEmail — success: resolves without mutating session state
    // -----------------------------------------------------------------------
    test(
      'verifyEmail success: resolves without throwing or mutating session state',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        when(
          () => repo.verifyEmail(
            email: any(named: 'email'),
            otp: any(named: 'otp'),
          ),
        ).thenAnswer((_) async {});

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        // Capture state before the call — it must not change.
        final stateBefore = container.read(authProvider).value;

        await expectLater(
          () => container
              .read(authProvider.notifier)
              .verifyEmail(email: 'anya@example.com', otp: '123456'),
          returnsNormally,
        );

        // verifyEmail must not mutate the auth session.
        expect(container.read(authProvider).value, equals(stateBefore));
      },
    );

    // -----------------------------------------------------------------------
    // verifyEmail — Failure rethrow
    // -----------------------------------------------------------------------
    test('verifyEmail rethrows a Failure from the repository', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      const failure = ValidationFailure(fieldErrors: {'otp': 'invalid'});
      when(
        () => repo.verifyEmail(
          email: any(named: 'email'),
          otp: any(named: 'otp'),
        ),
      ).thenThrow(failure);

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      await expectLater(
        () => container
            .read(authProvider.notifier)
            .verifyEmail(email: 'anya@example.com', otp: '000000'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    // -----------------------------------------------------------------------
    // verifyEmail — UnimplementedError rethrow (backend not yet live)
    // -----------------------------------------------------------------------
    test(
      'verifyEmail rethrows UnimplementedError when backend endpoint is not yet live',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        when(
          () => repo.verifyEmail(
            email: any(named: 'email'),
            otp: any(named: 'otp'),
          ),
        ).thenThrow(UnimplementedError('endpoint not live'));

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        await expectLater(
          () => container
              .read(authProvider.notifier)
              .verifyEmail(email: 'anya@example.com', otp: '111111'),
          throwsA(isA<UnimplementedError>()),
        );
      },
    );
  });

  // =========================================================================
  // Phase 2.11 — resendCode (QA HIGH-2 fix)
  // =========================================================================
  group('resendCode', () {
    // -----------------------------------------------------------------------
    // resendCode — success: resolves without mutating session state
    // -----------------------------------------------------------------------
    test(
      'resendCode success: resolves without throwing or mutating session state',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        when(
          () => repo.resendVerificationCode(email: any(named: 'email')),
        ).thenAnswer((_) async {});

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        final stateBefore = container.read(authProvider).value;

        await expectLater(
          () => container
              .read(authProvider.notifier)
              .resendCode(email: 'anya@example.com'),
          returnsNormally,
        );

        // resendCode must not mutate the auth session.
        expect(container.read(authProvider).value, equals(stateBefore));
      },
    );

    // -----------------------------------------------------------------------
    // resendCode — Failure rethrow
    // -----------------------------------------------------------------------
    test('resendCode rethrows a Failure from the repository', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      when(
        () => repo.resendVerificationCode(email: any(named: 'email')),
      ).thenThrow(const NetworkFailure());

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      await expectLater(
        () => container
            .read(authProvider.notifier)
            .resendCode(email: 'anya@example.com'),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });
}
