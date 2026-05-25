// Phase 2.4 — Unit tests for AuthNotifier.
//
// Tests use a ProviderContainer with overrides so neither Dio nor platform
// channels are involved. FakeSecureStorage provides in-memory storage;
// MockAuthRepository (mocktail) stubs the network boundary.
//
// F4 — build() now returns SYNCHRONOUSLY with Unauthenticated; the storage
// read + refresh runs as a fire-and-forget background task that mutates
// [state] when it settles. Tests use `pumpEventQueue` to flush the
// microtask + pending Futures before reading the post-restore state.
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
import 'package:beautica_mobile/features/auth/domain/register_result.dart';
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

        // F4 — build() returns synchronously with Unauthenticated. The
        // initial read settles immediately; the background storage read
        // also resolves to "no token" so state stays Unauthenticated.
        final session = await container.read(authProvider.future);
        expect(session, equals(const AuthSession.unauthenticated()));

        // Flush the background microtask so any pending storage I/O drains
        // before asserting `verifyNever` — otherwise a late repo call could
        // slip through after the assertion.
        await pumpEventQueue();

        expect(
          container.read(authProvider).value,
          equals(const AuthSession.unauthenticated()),
        );

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

        // F4 — initial state settles synchronously to Unauthenticated, then
        // the background task swaps it to Authenticated once repo.refresh()
        // + repo.me() resolve. Drain the event queue to wait for that swap.
        await container.read(authProvider.future);
        await pumpEventQueue();

        expect(
          container.read(authProvider).value,
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

      // F4 — initial state is Unauthenticated synchronously. The background
      // task tries to refresh, gets UnauthorizedFailure, wipes storage and
      // re-asserts Unauthenticated. Drain the event queue to wait for that.
      await container.read(authProvider.future);
      await pumpEventQueue();

      expect(
        container.read(authProvider).value,
        equals(const AuthSession.unauthenticated()),
      );

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
      // F4 — wait for the background cold-start restore to complete
      // (state becomes Authenticated) before invoking logout().
      await container.read(authProvider.future);
      await pumpEventQueue();

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
        ).thenAnswer(
          (_) async => const RegisterResult.authenticated(
            user: testUser,
            tokens: testTokens,
          ),
        );

        final result = await container
            .read(authProvider.notifier)
            .register(
              email: 'new@example.com',
              password: 'pass123',
              firstName: 'Іван',
              lastName: 'Коваль',
            );

        expect(result, isA<AuthenticatedRegisterResult>());

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
    // Test 6b — register success (verification-required envelope)
    //
    // Regression guard for the `_TypeError: type 'Null' is not a subtype of
    // type 'Map<String, dynamic>'` crash. When the backend returns the
    // verification-required envelope, the notifier must:
    //   - leave state as AsyncData(Unauthenticated) (no session created),
    //   - return RegisterResult.verificationRequired so the screen can
    //     navigate to the OTP screen,
    //   - NOT persist any refresh token (there is none).
    // -----------------------------------------------------------------------
    test(
      'register success (verification-required) → state stays Unauthenticated, '
      'no refresh token written, RegisterResult.verificationRequired returned',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

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
        ).thenAnswer(
          (_) async => const RegisterResult.verificationRequired(
            email: 'new@example.com',
          ),
        );

        final result = await container
            .read(authProvider.notifier)
            .register(
              email: 'new@example.com',
              password: 'pass123',
              firstName: 'Іван',
              lastName: 'Коваль',
            );

        expect(result, isA<VerificationRequired>());
        expect((result! as VerificationRequired).email, 'new@example.com');

        final value = container.read(authProvider);
        expect(value, isA<AsyncData<AuthSession>>());
        expect(value.value, equals(const AuthSession.unauthenticated()));

        // No session → no refresh token written.
        expect(await storage.readRefreshToken(), isNull);
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
      'cold start: raw Exception (non-Failure) from repo.refresh → '
      'Unauthenticated (caught in background task) and storage wiped',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();
        await storage.writeRefreshToken('stored-refresh');

        // Throw a raw exception that is NOT a Failure subclass.
        // F4 — the background restoration task has a catch-all so any
        // non-Failure exception is treated like a failed refresh: storage
        // is wiped and state ends up Unauthenticated. The exception must
        // NOT bubble up to AsyncError because that would re-trigger
        // build() on `ref.invalidate(authProvider)` and produce a redirect
        // loop in production.
        when(
          () => repo.refresh('stored-refresh'),
        ).thenThrow(Exception('format error'));

        final container = makeContainer(repo: repo, storage: storage);

        // build() returns synchronously with Unauthenticated; the background
        // task fires the failing repo.refresh() then catches it.
        await container.read(authProvider.future);
        await pumpEventQueue();

        final value = container.read(authProvider);
        expect(value, isA<AsyncData<AuthSession>>());
        expect(value.value, equals(const AuthSession.unauthenticated()));
        expect(await storage.readRefreshToken(), isNull);
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
        // F4 — wait for the background restore to settle to Authenticated.
        await container.read(authProvider.future);
        await pumpEventQueue();

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
        ).thenAnswer(
          (_) async => const RegisterResult.authenticated(
            user: testUser,
            tokens: testTokens,
          ),
        );

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
        ).thenAnswer(
          (_) async => const RegisterResult.authenticated(
            user: testUser,
            tokens: testTokens,
          ),
        );

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
      ).thenAnswer(
        (_) async => const RegisterResult.authenticated(
          user: testUser,
          tokens: testTokens,
        ),
      );

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
  // Phase 2.11 — verifyEmail (backend Phase 1.5 — returns full session)
  //
  // Contract (locked, 2026-05-20):
  //   On success the verify-email endpoint returns AuthResponse just like
  //   /auth/login — the user is fully authenticated as a side-effect of
  //   verification. The notifier mirrors the login success path:
  //     - persists refresh token to secure storage,
  //     - transitions state to AsyncData(Authenticated(user, accessToken)).
  // =========================================================================
  group('verifyEmail', () {
    // -----------------------------------------------------------------------
    // verifyEmail — success: transitions to Authenticated and persists token
    // -----------------------------------------------------------------------
    test(
      'verifyEmail success: state → Authenticated, refresh token persisted',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        // M-QA-2 (2026-05-20): exact-match args instead of any(named: ...) so
        // a future arg-swap inside AuthNotifier.verifyEmail would fail this
        // test instead of silently passing.
        when(
          () => repo.verifyEmail(email: 'anya@example.com', otp: '123456'),
        ).thenAnswer((_) async => (testUser, testTokens));

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        await container
            .read(authProvider.notifier)
            .verifyEmail(email: 'anya@example.com', otp: '123456');

        // State must flip to Authenticated with the correct user + access token.
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

        // Only the refresh token is persisted (security invariant MS-1) —
        // the access token lives in-memory in the [Authenticated] state.
        expect(
          await storage.readRefreshToken(),
          equals(testTokens.refreshToken),
        );
      },
    );

    // -----------------------------------------------------------------------
    // verifyEmail — VerificationFailure rethrown (typed backend error)
    // -----------------------------------------------------------------------
    test('verifyEmail rethrows VerificationFailure for INVALID_CODE', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      const failure = VerificationFailure(
        code: VerificationErrorCode.invalidCode,
      );
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
        throwsA(isA<VerificationFailure>()),
      );

      // State must remain Unauthenticated and storage must stay empty.
      expect(
        container.read(authProvider).value,
        equals(const AuthSession.unauthenticated()),
      );
      expect(await storage.readRefreshToken(), isNull);
    });

    // -----------------------------------------------------------------------
    // verifyEmail — generic Failure rethrown (network, server, etc.)
    // -----------------------------------------------------------------------
    test(
      'verifyEmail rethrows a generic Failure from the repository',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        when(
          () => repo.verifyEmail(
            email: any(named: 'email'),
            otp: any(named: 'otp'),
          ),
        ).thenThrow(const NetworkFailure());

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        await expectLater(
          () => container
              .read(authProvider.notifier)
              .verifyEmail(email: 'anya@example.com', otp: '111111'),
          throwsA(isA<NetworkFailure>()),
        );

        // No token persisted, no state change.
        expect(await storage.readRefreshToken(), isNull);
      },
    );
  });

  // =========================================================================
  // Phase 2.11 — resendCode (backend Phase 1.6 — returns void; 429 throttled)
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

    // -----------------------------------------------------------------------
    // resendCode — ResendThrottledFailure (backend 429) preserves retryAfterSeconds
    // -----------------------------------------------------------------------
    test(
      'resendCode rethrows ResendThrottledFailure preserving retryAfterSeconds',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        const failure = ResendThrottledFailure(retryAfterSeconds: 42);
        when(
          () => repo.resendVerificationCode(email: any(named: 'email')),
        ).thenThrow(failure);

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        await expectLater(
          () => container
              .read(authProvider.notifier)
              .resendCode(email: 'anya@example.com'),
          throwsA(
            isA<ResendThrottledFailure>().having(
              (f) => f.retryAfterSeconds,
              'retryAfterSeconds',
              42,
            ),
          ),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Phase 2.13 — requestPasswordReset
  // -------------------------------------------------------------------------

  group('requestPasswordReset', () {
    test(
      'success: resolves without throwing or mutating session state',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        when(() => repo.requestPasswordReset(any())).thenAnswer((_) async {});

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);
        final stateBefore = container.read(authProvider).value;

        await expectLater(
          () => container
              .read(authProvider.notifier)
              .requestPasswordReset('anya@example.com'),
          returnsNormally,
        );

        // Must not mutate the auth session — it is a side-effect-only call.
        expect(container.read(authProvider).value, equals(stateBefore));
        verify(() => repo.requestPasswordReset('anya@example.com')).called(1);
      },
    );

    test('rethrows a Failure from the repository', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      when(
        () => repo.requestPasswordReset(any()),
      ).thenThrow(const NetworkFailure());

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      await expectLater(
        () => container
            .read(authProvider.notifier)
            .requestPasswordReset('anya@example.com'),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Phase 2.13 — confirmPasswordReset
  // -------------------------------------------------------------------------

  group('confirmPasswordReset', () {
    test(
      'success: resolves without mutating session (NO auto-login)',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        when(
          () => repo.confirmPasswordReset(
            token: any(named: 'token'),
            newPassword: any(named: 'newPassword'),
          ),
        ).thenAnswer((_) async {});

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);
        final stateBefore = container.read(authProvider).value;

        await expectLater(
          () => container
              .read(authProvider.notifier)
              .confirmPasswordReset(
                token: 'raw-token',
                newPassword: 'NewSecret123',
              ),
          returnsNormally,
        );

        // No session is issued on reset by design — state is unchanged and no
        // refresh token is written to storage.
        expect(container.read(authProvider).value, equals(stateBefore));
        expect(await storage.readRefreshToken(), isNull);
      },
    );

    test('rethrows ResetTokenInvalidFailure on generic 400', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      when(
        () => repo.confirmPasswordReset(
          token: any(named: 'token'),
          newPassword: any(named: 'newPassword'),
        ),
      ).thenThrow(const ResetTokenInvalidFailure());

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      await expectLater(
        () => container
            .read(authProvider.notifier)
            .confirmPasswordReset(
              token: 'expired',
              newPassword: 'NewSecret123',
            ),
        throwsA(isA<ResetTokenInvalidFailure>()),
      );
    });

    test('rethrows a generic Failure (network) unchanged', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      when(
        () => repo.confirmPasswordReset(
          token: any(named: 'token'),
          newPassword: any(named: 'newPassword'),
        ),
      ).thenThrow(const NetworkFailure());

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      await expectLater(
        () => container
            .read(authProvider.notifier)
            .confirmPasswordReset(token: 't', newPassword: 'NewSecret123'),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  // =========================================================================
  // Phase 2.18 — acceptInvite
  //
  // Contract: on success the notifier mirrors the login success path:
  //   - persists the refresh token to SecureStorage (MS-1 invariant),
  //   - transitions state to AsyncData(Authenticated(user, accessToken)).
  // On failure, state becomes AsyncError with the typed Failure.
  // =========================================================================
  group('acceptInvite', () {
    // -----------------------------------------------------------------------
    // AN-1 / AN-3 — happy path: transitions to Authenticated, persists refresh
    //               token, does NOT persist access token (combined per brief).
    // -----------------------------------------------------------------------
    test('acceptInvite success: state → Authenticated, refresh token persisted '
        '(access token in-memory only)', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      // Exact-match stub: if the notifier drops or renames any required arg
      // this stub will not match and mocktail throws MissingStubError.
      when(
        () => repo.acceptInvite(
          token: 'invite-abc123',
          password: 'SecurePass1!',
          firstName: 'Іван',
          lastName: 'Коваль',
          phoneNumber: '+380501234567',
        ),
      ).thenAnswer((_) async => (testUser, testTokens));

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      await container
          .read(authProvider.notifier)
          .acceptInvite(
            token: 'invite-abc123',
            password: 'SecurePass1!',
            firstName: 'Іван',
            lastName: 'Коваль',
            phoneNumber: '+380501234567',
          );

      // State must transition to AsyncData(Authenticated).
      final value = container.read(authProvider);
      expect(
        value,
        isA<AsyncData<AuthSession>>(),
        reason: 'After acceptInvite success state must be AsyncData',
      );
      expect(
        value.value,
        equals(
          AuthSession.authenticated(
            user: testUser,
            accessToken: testTokens.accessToken,
          ),
        ),
        reason:
            'Authenticated session must carry the correct user + access token',
      );

      // AN-3: Only the refresh token is persisted to SecureStorage (MS-1).
      // The access token lives exclusively in-memory inside [Authenticated].
      expect(
        await storage.readRefreshToken(),
        equals(testTokens.refreshToken),
        reason:
            'refresh token must be written to SecureStorage after '
            'acceptInvite success (MS-1 invariant)',
      );
    });

    // -----------------------------------------------------------------------
    // acceptInvite — optional phoneNumber omitted (null forwarded, not "")
    // -----------------------------------------------------------------------
    test('acceptInvite without phoneNumber: null forwarded to repository, '
        'state transitions to Authenticated', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      // Strict stub: phoneNumber is absent (null default).
      // If the notifier passed '' instead of null the stub would not match.
      when(
        () => repo.acceptInvite(
          token: 'invite-xyz',
          password: 'Secret1!',
          firstName: 'Олена',
          lastName: 'Шевченко',
          // phoneNumber intentionally absent — must stay null.
        ),
      ).thenAnswer((_) async => (testUser, testTokens));

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      await container
          .read(authProvider.notifier)
          .acceptInvite(
            token: 'invite-xyz',
            password: 'Secret1!',
            firstName: 'Олена',
            lastName: 'Шевченко',
            // phoneNumber omitted — default null.
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
    });

    // -----------------------------------------------------------------------
    // AN-2 — failure path: ValidationFailure → AsyncError
    // -----------------------------------------------------------------------
    test(
      'acceptInvite ValidationFailure → state becomes AsyncError<AuthSession> '
      'with a ValidationFailure, storage unchanged',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        const failure = ValidationFailure(
          fieldErrors: {'token': 'expired_or_invalid'},
        );
        when(
          () => repo.acceptInvite(
            token: any(named: 'token'),
            password: any(named: 'password'),
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
            phoneNumber: any(named: 'phoneNumber'),
          ),
        ).thenThrow(failure);

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        await container
            .read(authProvider.notifier)
            .acceptInvite(
              token: 'expired-token',
              password: 'Secret1!',
              firstName: 'Test',
              lastName: 'User',
            );

        final value = container.read(authProvider);
        expect(
          value,
          isA<AsyncError<AuthSession>>(),
          reason:
              'A ValidationFailure from acceptInvite must surface as '
              'AsyncError so the screen can render the inline error state',
        );
        expect(
          value.error,
          isA<ValidationFailure>(),
          reason: 'The error payload must be the original ValidationFailure',
        );
        expect(
          (value.error as ValidationFailure).fieldErrors,
          equals({'token': 'expired_or_invalid'}),
        );

        // No token must be written to storage on failure.
        expect(
          await storage.readRefreshToken(),
          isNull,
          reason: 'No refresh token must be persisted when acceptInvite fails',
        );
      },
    );

    // -----------------------------------------------------------------------
    // acceptInvite — generic NetworkFailure rethrown through AsyncError
    // -----------------------------------------------------------------------
    test(
      'acceptInvite NetworkFailure → AsyncError<AuthSession> with NetworkFailure',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        when(
          () => repo.acceptInvite(
            token: any(named: 'token'),
            password: any(named: 'password'),
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
            phoneNumber: any(named: 'phoneNumber'),
          ),
        ).thenThrow(const NetworkFailure());

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        await container
            .read(authProvider.notifier)
            .acceptInvite(
              token: 'token',
              password: 'Secret1!',
              firstName: 'Test',
              lastName: 'User',
            );

        final value = container.read(authProvider);
        expect(value, isA<AsyncError<AuthSession>>());
        expect(value.error, isA<NetworkFailure>());
        expect(await storage.readRefreshToken(), isNull);
      },
    );
  });
}
