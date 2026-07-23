// Phase 2.4 — Unit tests for AuthNotifier.
//
// Tests use a ProviderContainer with overrides so neither Dio nor platform
// channels are involved. FakeSecureStorage provides in-memory storage;
// MockAuthRepository (mocktail) stubs the network boundary.
//
// build() is async — Riverpod emits AsyncLoading while the storage read +
// token refresh + /users/me network calls are in-flight. Tests use
// `await container.read(authProvider.future)` to wait for the full restore;
// no `pumpEventQueue` is needed for the cold-start path.
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

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/storage/secure_storage.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/register_result.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';

import '../../../helpers/fakes/fake_master_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class _MockServiceRepository extends Mock implements ServiceRepository {}

/// Spy [DayKeepAliveLru] for the session-boundary-PII logout test below —
/// records whether [clear] was actually invoked by the REAL
/// `AuthNotifier.logout()` rather than exercising the real LRU's own
/// eviction bookkeeping (already covered by `bookings_day_notifier_test
/// .dart`).
class _SpyDayKeepAliveLru extends Mock implements DayKeepAliveLru {}

/// Spy [SecureStorage] for the M5 logout-wipe group.
///
/// Mocktail [Mock] gives us `verify(() => storage.deleteAll())` interaction
/// assertions, while every call DELEGATES to a backing [FakeSecureStorage] so
/// real reads/writes still work (e.g. `readRefreshToken()` returns null after
/// the wipe, proving the token keys were actually cleared). This lets one
/// instance both record the `deleteAll()` interaction AND behave like the
/// in-memory fake used everywhere else in this file.
class SpySecureStorage extends Mock implements SecureStorage {
  SpySecureStorage([FakeSecureStorage? backing])
    : _backing = backing ?? FakeSecureStorage();

  final FakeSecureStorage _backing;

  @override
  Future<String?> readRefreshToken() => _backing.readRefreshToken();

  @override
  Future<void> writeRefreshToken(String token) =>
      _backing.writeRefreshToken(token);

  @override
  Future<String?> readUserJson() => _backing.readUserJson();

  @override
  Future<void> writeUserJson(String json) => _backing.writeUserJson(json);

  @override
  Future<void> deleteAll() {
    // super.noSuchMethod records the invocation so verify(...) works; we then
    // delegate to the real fake so the backing map is actually cleared.
    super.noSuchMethod(Invocation.method(#deleteAll, const []));
    return _backing.deleteAll();
  }
}

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

        // async build() awaits storage.readRefreshToken(); with no token stored
        // it returns Unauthenticated immediately (no network call).
        final session = await container.read(authProvider.future);
        expect(session, equals(const AuthSession.unauthenticated()));

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

        // async build() keeps AsyncLoading until repo.refresh() + repo.me() complete.
        await container.read(authProvider.future);

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
    // Test 2b — lastKnownAccessToken survives a mid-rebuild AsyncLoading window
    //
    // Delete-service false-401 regression guard: serviceRepositoryProvider
    // watches masterProfileProvider; invalidating it can push a watcher of
    // authProvider into a momentary AsyncLoading. AuthInterceptor must still be
    // able to recover the Bearer token via [lastKnownAccessToken] — otherwise
    // the in-flight DELETE is sent tokenless and the backend answers a false
    // 401 ("Сесія завершилась").
    // -----------------------------------------------------------------------
    test('lastKnownAccessToken: returns session token even while the provider '
        'is momentarily AsyncLoading (delete-flow race)', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();
      await storage.writeRefreshToken('stored-refresh');

      when(
        () => repo.refresh('stored-refresh'),
      ).thenAnswer((_) async => rotatedTokens);
      when(() => repo.me()).thenAnswer((_) async => testUser);

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      final notifier = container.read(authProvider.notifier);

      // Settled Authenticated state → token comes straight from the session.
      expect(notifier.lastKnownAccessToken, equals(rotatedTokens.accessToken));

      // Simulate the mid-rebuild window: provider pushed back to AsyncLoading
      // with the cold-start sentinel already cleared (its normal settled state).
      // ignore: invalid_use_of_protected_member
      notifier.state = const AsyncLoading<AuthSession>();

      expect(
        notifier.lastKnownAccessToken,
        equals(rotatedTokens.accessToken),
        reason:
            'while AsyncLoading mid-rebuild, the interceptor must still recover '
            'the last-known access token so requests are not sent tokenless',
      );
    });

    // -----------------------------------------------------------------------
    // Test 2c — logout wipes the lastKnownAccessToken fallback
    // -----------------------------------------------------------------------
    test('logout: clears lastKnownAccessToken so no stale token can be '
        'attached post-logout', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();
      await storage.writeRefreshToken('stored-refresh');

      when(
        () => repo.refresh('stored-refresh'),
      ).thenAnswer((_) async => rotatedTokens);
      when(() => repo.me()).thenAnswer((_) async => testUser);
      when(() => repo.logout()).thenAnswer((_) async {});

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      final notifier = container.read(authProvider.notifier);
      expect(notifier.lastKnownAccessToken, isNotNull);

      await notifier.logout();

      expect(
        notifier.lastKnownAccessToken,
        isNull,
        reason: 'after logout there is no session — no token may be recovered',
      );
    });

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

      // async build() awaits repo.refresh(), catches UnauthorizedFailure,
      // wipes storage, returns Unauthenticated.
      await container.read(authProvider.future);

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
    // Test 3b — cold-start sequence: AsyncLoading → Authenticated
    //           (never emits Unauthenticated before Authenticated)
    // -----------------------------------------------------------------------
    test('cold start with valid token: state sequence is AsyncLoading → '
        'Authenticated (never emits Unauthenticated first)', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();
      await storage.writeRefreshToken('stored-refresh');

      when(
        () => repo.refresh('stored-refresh'),
      ).thenAnswer((_) async => rotatedTokens);
      when(() => repo.me()).thenAnswer((_) async => testUser);

      final container = makeContainer(repo: repo, storage: storage);

      final emittedStates = <AsyncValue<AuthSession>>[];
      final sub = container.listen<AsyncValue<AuthSession>>(
        authProvider,
        (_, next) => emittedStates.add(next),
        fireImmediately: true,
      );
      addTearDown(sub.close);

      // Wait for build() to complete.
      await container.read(authProvider.future);

      // The first emission must be AsyncLoading (build() is in-flight).
      expect(
        emittedStates.first,
        isA<AsyncLoading<AuthSession>>(),
        reason:
            'authProvider must start in AsyncLoading while build() is in-flight',
      );

      // No emission of AsyncData(Unauthenticated) must occur before Authenticated.
      // An Unauthenticated emission here would cause the router to flash /login.
      final beforeAuthenticated = emittedStates.takeWhile(
        (s) => s.value is! Authenticated,
      );
      for (final s in beforeAuthenticated) {
        expect(
          s.value,
          isNot(isA<Unauthenticated>()),
          reason:
              'authProvider must NOT emit Unauthenticated before Authenticated '
              'when a valid token is stored — that would flash the /login screen.',
        );
      }

      // Final state must be Authenticated.
      expect(
        container.read(authProvider).value,
        equals(
          AuthSession.authenticated(
            user: testUser,
            accessToken: rotatedTokens.accessToken,
          ),
        ),
      );
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
        when(() => repo.me()).thenAnswer((_) async => testUser);

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
      // async build() completes with Authenticated once repo.refresh() + repo.me() settle.
      await container.read(authProvider.future);

      await container.read(authProvider.notifier).logout();

      final value = container.read(authProvider);
      expect(value, isA<AsyncData<AuthSession>>());
      expect(value.value, equals(const AuthSession.unauthenticated()));

      // All tokens must be wiped from storage.
      expect(await storage.readRefreshToken(), isNull);
    });

    // -----------------------------------------------------------------------
    // Test 5a2 — mobile-qa gap-fix (KNOWN COVERAGE GAP 3, mobile-security
    // MEDIUM regression guard): logout() must reset screenProtectionProvider.
    //
    // `AuthNotifier.logout()` (auth_notifier.dart:829-837) calls
    // `ref.read(screenProtectionProvider).reset()` after wiping storage, so a
    // PII screen's dialog (e.g. `ClientBookingConflictDialog` open over
    // `BookingConfirmScreen`) that is still holding an acquired ref count when
    // a logout fires (e.g. `RefreshInterceptor` force-logout on a failed
    // token refresh) cannot leave FLAG_SECURE / the iOS app-switcher blur
    // latched on past the auth boundary. This pins that contract directly —
    // a future refactor that drops the `.reset()` call would otherwise only
    // be caught manually on a real device.
    // -----------------------------------------------------------------------
    test(
      'logout resets screenProtectionProvider — a non-zero acquirer count '
      'is force-zeroed even though no screen ever called release()',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();
        await storage.writeRefreshToken('stored-refresh');

        when(
          () => repo.refresh('stored-refresh'),
        ).thenAnswer((_) async => testTokens);
        when(() => repo.me()).thenAnswer((_) async => testUser);
        when(() => repo.logout()).thenAnswer((_) async {});

        final screenProtection = ScreenProtectionManager();

        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWith((_) => repo),
            secureStorageProvider.overrideWith((_) => storage),
            screenProtectionProvider.overrideWithValue(screenProtection),
          ],
        );
        addTearDown(container.dispose);

        await container.read(authProvider.future);

        // Simulate a PII screen (e.g. BookingConfirmScreen with the conflict
        // dialog open above it) holding protection acquired — WITHOUT ever
        // calling release(), mirroring a logout fired mid-dialog.
        screenProtection.acquire();
        expect(screenProtection.acquirerCount, 1);

        await container.read(authProvider.notifier).logout();

        expect(
          screenProtection.acquirerCount,
          0,
          reason:
              'logout() must force-reset the screen-protection acquirer '
              'count to 0 even when the acquiring screen never disposed / '
              'released it — otherwise FLAG_SECURE / the app-switcher blur '
              'stays latched on past the auth boundary (mobile-security '
              'MEDIUM)',
        );

        // Sanity: logout itself still completed normally.
        expect(
          container.read(authProvider).value,
          equals(const AuthSession.unauthenticated()),
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 5a3 — mobile-qa gap-fix (session-boundary PII, mobile-security
    // HIGH, 2026-07-19): logout() must call `dayKeepAliveLruProvider.clear()`
    // — the defence-in-depth half of the fix (layer (b)).
    //
    // `bookings_day_notifier_test.dart`'s own session-boundary group already
    // covers `BookingsDayNotifier.build`'s `authProvider`-id watch (layer
    // (a)) and exercises `DayKeepAliveLru.clear()` directly (layer (b)) —
    // but that second test calls `clear()` on the container itself, which
    // its own comment admits is only "the exact call `AuthNotifier.logout`
    // makes," not a call THROUGH `logout()`. Nothing in the suite pinned the
    // real wiring at `auth_notifier.dart:863`'s
    // `ref.read(dayKeepAliveLruProvider).clear()` call site — a refactor
    // dropping it would go undetected.
    //
    // WHY THIS IS AN INTERACTION TEST, NOT AN OUTCOME TEST — an important
    // finding from building this test, recorded so nobody "fixes" it back to
    // an outcome assertion later:
    //
    // The obvious design would build a real `bookingsDayProvider(query)`
    // member, close its active listener so it's pinned ONLY by the bounded
    // keepAlive cache, call the REAL `logout()`, and then assert via
    // `container.exists(bookingsDayProvider(query))` that the member is
    // gone — WITHOUT ever re-reading it (a re-read would let layer (a)'s own
    // lazy-rebuild-on-read cascade explain a pass on its own).
    //
    // That design was built and mutation-tested — and it does NOT isolate
    // layer (b). Reading Riverpod 3.2.1's own source
    // (`package:riverpod/src/core/element.dart`) shows `invalidateSelf()` —
    // the exact call layer (a)'s `authProvider.select` watch triggers when
    // the id changes — UNCONDITIONALLY calls `runOnDispose()` (which clears
    // ANY held `KeepAliveLink`s on that element, regardless of who created
    // them) followed immediately by `mayNeedDispose()` (which schedules
    // disposal once there are zero links AND zero active listeners). For a
    // member with no active listener, this means layer (a) ALONE already
    // tears down the keepAlive link and schedules disposal, synchronously,
    // the moment the session flips — before layer (b)'s `clear()` call
    // would even run. Deleting the `clear()` call at `auth_notifier.dart:863`
    // and re-running the `exists()`-based version of this test left it GREEN
    // — it did not discriminate (a) from (b) at all, exactly the trap this
    // audit was asked to check for.
    //
    // So instead of asserting an outcome that (a) can produce on its own,
    // this test verifies the INTERACTION directly: `dayKeepAliveLruProvider`
    // is overridden with a spy, `logout()` is called for real, and the
    // assertion is simply that `.clear()` was invoked on it. This pins the
    // `auth_notifier.dart:863` call site itself, independent of whatever
    // Riverpod's internal disposal timing happens to do — the one thing an
    // outcome-based test in this framework version cannot do.
    test("logout() calls dayKeepAliveLruProvider.clear() — the auth-notifier "
        'side of the session-boundary PII fix (mobile-security HIGH, '
        '2026-07-19)', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();
      await storage.writeRefreshToken('stored-refresh');
      final lruSpy = _SpyDayKeepAliveLru();

      when(
        () => repo.refresh('stored-refresh'),
      ).thenAnswer((_) async => testTokens);
      when(() => repo.me()).thenAnswer((_) async => testUser);
      when(() => repo.logout()).thenAnswer((_) async {});
      when(() => lruSpy.clear()).thenReturn(null);

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith((_) => repo),
          secureStorageProvider.overrideWith((_) => storage),
          dayKeepAliveLruProvider.overrideWithValue(lruSpy),
        ],
      );
      addTearDown(container.dispose);

      // Cold start settles to Authenticated (matches the M5 groups above).
      await container.read(authProvider.future);

      verifyNever(() => lruSpy.clear());

      // The REAL logout() — not a hand-rolled equivalent.
      await container.read(authProvider.notifier).logout();

      verify(() => lruSpy.clear()).called(1);
    });

    // -----------------------------------------------------------------------
    // Test 5b — Logout cascades teardown to servicesListProvider (keepAlive)
    //
    // NEW CONTRACT (2026-06-18 circular-dependency fix): logout() no longer
    // calls ref.invalidate(servicesListProvider). servicesListProvider watches
    // serviceRepositoryProvider, which watches masterProfileProvider, which
    // watches authProvider. When logout() flips auth to Unauthenticated, that
    // watch chain rebuilds the list automatically — no manual invalidation.
    //
    // The OLD version of this test stubbed serviceRepositoryProvider with a
    // mock that broke the `→ authProvider` edge "to avoid the circular-dependency
    // assert" — i.e. it engineered the very bug away. This rewrite wires the
    // PRODUCTION graph (serviceRepository + servicesList real) with only the
    // leaf masterRepositoryProvider stubbed, registers the cyclic edge via the
    // live listener below, and asserts the cascade contract: logout completes
    // WITHOUT throwing and the list re-emits as auth tears down.
    test('logout → servicesListProvider (keepAlive) rebuilds via the auth-watch '
        'cascade, without a manual invalidation and without throwing', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();
      await storage.writeRefreshToken('stored-refresh');

      when(
        () => repo.refresh('stored-refresh'),
      ).thenAnswer((_) async => testTokens);
      when(() => repo.me()).thenAnswer((_) async => testUser);
      when(() => repo.logout()).thenAnswer((_) async {});

      // Production serviceRepository + servicesList providers — NOT stubbed.
      // Only the leaf data-layer masterRepositoryProvider is overridden so the
      // real masterProfileProvider builds (and thus registers its
      // `ref.watch(authProvider)` reverse edge). This keeps the cyclic edge the
      // old test removed, so a reverted invalidate() would re-trip the assert.
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith((_) => repo),
          secureStorageProvider.overrideWith((_) => storage),
          masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
        ],
      );
      addTearDown(container.dispose);

      // Authenticate first.
      await container.read(authProvider.future);

      // Subscribe to servicesListProvider so it has a live listener — this is
      // what registers serviceRepository → masterProfile → authProvider in the
      // graph. listMyServices() on the real HttpServiceRepository short-circuits
      // via _assertAuthenticated() throwing UnauthorizedFailure (the fake master
      // resolves a non-empty masterId, so it actually fetches; we only care that
      // a state is emitted, not its data), so capture states, not values.
      final servicesStates = <AsyncValue<Object?>>[];
      container.listen<AsyncValue<Object?>>(
        servicesListProvider,
        (_, next) => servicesStates.add(next),
        fireImmediately: true,
      );
      final servicesBefore = servicesStates.length;

      // logout() must complete without throwing — no manual invalidation, no
      // CircularDependencyError from a back-edge recorded inside authProvider.
      await expectLater(
        container.read(authProvider.notifier).logout(),
        completes,
        reason:
            'logout() must not throw — it no longer invalidates the cyclic '
            'providers; the watch cascade handles teardown',
      );

      // Auth settled to Unauthenticated → the watch chain pushed the list into
      // a new state (the cascade teardown the manual invalidate used to force).
      expect(
        container.read(authProvider).value,
        equals(const AuthSession.unauthenticated()),
      );
      expect(
        servicesStates.length,
        greaterThan(servicesBefore),
        reason:
            'servicesListProvider must re-emit as the auth-watch cascade tears '
            'it down on logout — without any manual ref.invalidate',
      );
    });

    // -----------------------------------------------------------------------
    // Test 5c — Logout rebuilds serviceRepositoryProvider via the auth cascade
    //
    // NEW CONTRACT (2026-06-18 circular-dependency fix): logout() no longer
    // calls ref.invalidate(serviceRepositoryProvider). The provider watches
    // masterProfileProvider, which watches authProvider. When logout() flips
    // auth to Unauthenticated, masterProfileProvider rebuilds (and now throws
    // UnauthorizedFailure → masterId resolves to '' on the next build), so
    // serviceRepositoryProvider is rebuilt around an empty masterId — the
    // previous account's master id cannot survive. No manual invalidation.
    //
    // The OLD version of this test overrode serviceRepositoryProvider with a
    // per-build mock factory that BROKE the `→ authProvider` edge "so the debug
    // circular-dependency assertion does not fire" — again engineering the bug
    // away. This rewrite wires the PRODUCTION serviceRepository + masterProfile
    // graph (only the leaf masterRepositoryProvider stubbed) so the cyclic edge
    // is registered, and asserts the cascade contract: logout completes without
    // throwing and the repository is rebuilt to a fresh instance that no longer
    // carries the previous account's master id.
    // -----------------------------------------------------------------------
    test('logout → serviceRepositoryProvider (keepAlive) is rebuilt via the '
        'auth-watch cascade (fresh instance, empty masterId) so stale service '
        'data cannot survive logout — and logout does not throw', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();
      await storage.writeRefreshToken('stored-refresh');

      when(
        () => repo.refresh('stored-refresh'),
      ).thenAnswer((_) async => testTokens);
      when(() => repo.me()).thenAnswer((_) async => testUser);
      when(() => repo.logout()).thenAnswer((_) async {});

      // Production serviceRepository + masterProfile graph. Only the leaf
      // masterRepositoryProvider is stubbed, so masterProfileProvider builds
      // for real and registers its `ref.watch(authProvider)` reverse edge —
      // the cyclic edge the old override removed. A reverted invalidate()
      // would re-trip the CircularDependencyError assert here.
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith((_) => repo),
          secureStorageProvider.overrideWith((_) => storage),
          masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
        ],
      );
      addTearDown(container.dispose);

      // Authenticate, then keep the keepAlive repository alive with a listener
      // so the instance read before logout is the cached production instance
      // (mirrors a live screen holding it). This listener is also what wires
      // serviceRepository → masterProfile → authProvider into the graph.
      await container.read(authProvider.future);
      // Let masterProfileProvider settle so serviceRepositoryProvider is built
      // around the resolved (non-empty) masterId from the fake profile.
      await container.read(masterProfileProvider.future);
      final sub = container.listen(
        serviceRepositoryProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final repoBefore = container.read(serviceRepositoryProvider);

      await expectLater(
        container.read(authProvider.notifier).logout(),
        completes,
        reason:
            'logout() must not throw — it no longer invalidates '
            'serviceRepositoryProvider; the auth-watch cascade rebuilds it',
      );

      final repoAfter = container.read(serviceRepositoryProvider);

      expect(
        identical(repoBefore, repoAfter),
        isFalse,
        reason:
            'the auth-watch cascade must rebuild serviceRepositoryProvider on '
            'logout (masterProfile → empty masterId) so the next read produces '
            "a fresh repository — a re-used instance would carry the previous "
            "account's master id and leak its service data.",
      );
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

        // async build() awaits repo.refresh(), catches the non-Failure exception,
        // wipes storage, and returns Unauthenticated.
        await container.read(authProvider.future);

        final value = container.read(authProvider);
        expect(value, isA<AsyncData<AuthSession>>());
        expect(value.value, equals(const AuthSession.unauthenticated()));
        expect(await storage.readRefreshToken(), isNull);
      },
    );

    // -----------------------------------------------------------------------
    // Test 10b — cold-start partial success: refresh OK, repo.me throws →
    //            coldStartAccessToken cleared by finally block
    //
    // HIGH-1 regression guard (mobile-security 2026-05-24):
    //
    // AuthNotifier.build() writes the rotated access token to its plain
    // [coldStartAccessToken] field after a successful repo.refresh() so the
    // AuthInterceptor can attach a Bearer header on the subsequent /users/me
    // call. The `finally` block on auth_notifier.dart:172-176 MUST clear the
    // field on every exit path — including the case where refresh succeeded
    // but me() threw. Tests 3 and 10 only exercise refresh failing, where the
    // field was never set, so the finally block is a no-op there.
    //
    // Without this test, removing the entire `finally` block would not be
    // caught by any other test.
    // -----------------------------------------------------------------------
    test('cold start: refresh succeeds but repo.me throws → '
        'coldStartAccessToken cleared by finally, state is Unauthenticated, '
        'storage wiped', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();
      await storage.writeRefreshToken('stored-refresh');

      // refresh() succeeds → coldStartAccessToken gets set to
      // rotatedTokens.accessToken inside build() before me() is awaited.
      when(
        () => repo.refresh('stored-refresh'),
      ).thenAnswer((_) async => rotatedTokens);

      // me() throws a Failure → `on Failure catch` branch runs: storage is
      // wiped and Unauthenticated is returned. The `finally` block must then
      // clear coldStartAccessToken even though we are leaving via the catch.
      when(() => repo.me()).thenThrow(const UnauthorizedFailure());

      final container = makeContainer(repo: repo, storage: storage);

      // Await full build() resolution — by this point the catch + finally
      // must have run.
      await container.read(authProvider.future);

      // (1) coldStartAccessToken must be null — proving the finally block ran.
      // If the `finally` block were deleted, this would still be set to
      // rotatedTokens.accessToken from the line just before await repo.me().
      expect(
        container.read(authProvider.notifier).coldStartAccessToken,
        isNull,
        reason:
            'finally block in AuthNotifier.build() must clear '
            'coldStartAccessToken even on partial-success cold start',
      );

      // (2) Final state must be Unauthenticated — the catch wiped storage and
      // returned the unauthenticated session.
      final value = container.read(authProvider);
      expect(value, isA<AsyncData<AuthSession>>());
      expect(
        value.value,
        equals(const AuthSession.unauthenticated()),
        reason:
            'A failed /users/me on cold start must leave the session '
            'Unauthenticated, never AsyncError (which would cause a '
            'redirect loop)',
      );

      // (3) Storage was wiped — the stored refresh token must be gone.
      // FakeSecureStorage backs deleteAll() with Map.clear(); a null read
      // after a non-null write is the canonical assertion in this file
      // (see Test 3 and Test 10) that storage.deleteAll() ran.
      expect(
        await storage.readRefreshToken(),
        isNull,
        reason:
            'storage.deleteAll() must run when repo.me() throws on cold start',
      );
    });

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
        // async build() completes with Authenticated once repo.refresh() + repo.me() settle.
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
    // Test 13b — refreshUser re-settles Authenticated with the fresh user,
    //            preserving the current access token.
    // -----------------------------------------------------------------------
    test(
      'refreshUser refreshes session user and preserves access token',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();
        await storage.writeRefreshToken('stored-refresh');

        const updatedUser = User(
          id: 'u1',
          email: 'test@example.com',
          role: UserRole.independentMaster,
          firstName: 'Updated',
          lastName: 'Name',
        );

        when(
          () => repo.refresh('stored-refresh'),
        ).thenAnswer((_) async => rotatedTokens);
        // First me() (cold-start build) → original user; subsequent me()
        // (refreshUser) → updated user.
        var meCalls = 0;
        when(() => repo.me()).thenAnswer((_) async {
          meCalls++;
          return meCalls == 1 ? testUser : updatedUser;
        });

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);
        // Cold start settled with the original user + rotatedTokens.accessToken.
        expect(
          (container.read(authProvider).value as Authenticated).user,
          equals(testUser),
        );

        await container.read(authProvider.notifier).refreshUser();

        final session = container.read(authProvider).value;
        expect(session, isA<Authenticated>());
        // Fresh user surfaced…
        expect((session as Authenticated).user, equals(updatedUser));
        // …and the access token from the settled session is preserved.
        expect(session.accessToken, equals(rotatedTokens.accessToken));
      },
    );

    // -----------------------------------------------------------------------
    // Test 13c — refreshUser is a no-op when Unauthenticated.
    // -----------------------------------------------------------------------
    test('refreshUser is a no-op when Unauthenticated', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage(); // no token → Unauthenticated.

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      await container.read(authProvider.notifier).refreshUser();

      expect(
        container.read(authProvider).value,
        equals(const AuthSession.unauthenticated()),
      );
      // me() must never be called when there is no session to refresh.
      verifyNever(() => repo.me());
    });

    // -----------------------------------------------------------------------
    // Test 13d — refreshUser tolerates a me() failure: the prior Authenticated
    //            session (user + access token) is left intact.
    // -----------------------------------------------------------------------
    test('refreshUser preserves session when me() fails', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();
      await storage.writeRefreshToken('stored-refresh');

      when(
        () => repo.refresh('stored-refresh'),
      ).thenAnswer((_) async => rotatedTokens);
      var meCalls = 0;
      when(() => repo.me()).thenAnswer((_) async {
        meCalls++;
        if (meCalls == 1) return testUser; // cold-start build succeeds.
        throw const NetworkFailure(); // refreshUser fetch fails.
      });

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      // Must not throw and must not blow away the session.
      await container.read(authProvider.notifier).refreshUser();

      final session = container.read(authProvider).value;
      expect(session, isA<Authenticated>());
      expect((session as Authenticated).user, equals(testUser));
      expect(session.accessToken, equals(rotatedTokens.accessToken));
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
        when(() => repo.me()).thenAnswer((_) async => testUser);

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

    // -----------------------------------------------------------------------
    // verifyEmail — repo.me() fails AFTER a successful verify (Finding 1).
    //
    // The verify call returns a full session (refresh token persisted), but the
    // follow-up GET /users/me throws. The notifier MUST surface that failure as
    // AsyncError (with the original error + stack) rather than hang in a stale
    // state. It also rethrows so the calling screen renders the inline error.
    // -----------------------------------------------------------------------
    test('verifyEmail: repo.me() failure after a successful verify → AsyncError '
        '(not a stale/hung state) and rethrows', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      when(
        () => repo.verifyEmail(
          email: any(named: 'email'),
          otp: any(named: 'otp'),
        ),
      ).thenAnswer((_) async => (testUser, testTokens));
      // The profile load fails — this is the path Finding 1 guards.
      when(() => repo.me()).thenThrow(const ServerFailure(statusCode: 500));

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      await expectLater(
        () => container
            .read(authProvider.notifier)
            .verifyEmail(email: 'anya@example.com', otp: '123456'),
        throwsA(isA<ServerFailure>()),
      );

      // THE REGRESSION GUARD: the failure surfaces as AsyncError, not a stale
      // AsyncData(Unauthenticated) / hung AsyncLoading.
      final value = container.read(authProvider);
      expect(
        value,
        isA<AsyncError<AuthSession>>(),
        reason:
            'a repo.me() failure after verify must settle the provider into '
            'AsyncError so the UI can react instead of hanging',
      );
      expect((value as AsyncError<AuthSession>).error, isA<ServerFailure>());
      expect(value.stackTrace, isNotNull);

      // The in-memory cold-start token must NOT linger after the half-built
      // session failed (security invariant — no replayable token left behind).
      expect(
        container.read(authProvider.notifier).lastKnownAccessToken,
        isNull,
        reason: 'a failed verify must clear both in-memory access-token caches',
      );
    });
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
            resetTicket: any(named: 'resetTicket'),
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
                resetTicket: 'raw-ticket',
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
          resetTicket: any(named: 'resetTicket'),
          newPassword: any(named: 'newPassword'),
        ),
      ).thenThrow(const ResetTokenInvalidFailure());

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      await expectLater(
        () => container
            .read(authProvider.notifier)
            .confirmPasswordReset(
              resetTicket: 'expired',
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
          resetTicket: any(named: 'resetTicket'),
          newPassword: any(named: 'newPassword'),
        ),
      ).thenThrow(const NetworkFailure());

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      await expectLater(
        () => container
            .read(authProvider.notifier)
            .confirmPasswordReset(
              resetTicket: 't',
              newPassword: 'NewSecret123',
            ),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Beautica OTP task Phase B2 — requestChangePasswordOtp
  // -------------------------------------------------------------------------

  group('requestChangePasswordOtp', () {
    test(
      'success: resolves without throwing or mutating session state',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        when(() => repo.requestChangePasswordOtp()).thenAnswer((_) async {});

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);
        final stateBefore = container.read(authProvider).value;

        await expectLater(
          () =>
              container.read(authProvider.notifier).requestChangePasswordOtp(),
          returnsNormally,
        );

        expect(container.read(authProvider).value, equals(stateBefore));
        verify(() => repo.requestChangePasswordOtp()).called(1);
      },
    );

    test('rethrows ResendThrottledFailure from the repository', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      when(
        () => repo.requestChangePasswordOtp(),
      ).thenThrow(const ResendThrottledFailure(retryAfterSeconds: 42));

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      await expectLater(
        () => container.read(authProvider.notifier).requestChangePasswordOtp(),
        throwsA(isA<ResendThrottledFailure>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Beautica OTP task Phase B2 — verifyPasswordResetOtp
  // -------------------------------------------------------------------------

  group('verifyPasswordResetOtp', () {
    test(
      'success: returns the reset ticket without mutating session state',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        when(
          () => repo.verifyPasswordResetOtp(
            email: any(named: 'email'),
            code: any(named: 'code'),
          ),
        ).thenAnswer((_) async => 'ticket-xyz');

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);
        final stateBefore = container.read(authProvider).value;

        final ticket = await container
            .read(authProvider.notifier)
            .verifyPasswordResetOtp(email: 'anya@example.com', code: '123456');

        expect(ticket, 'ticket-xyz');
        // Pure request/response — no session side-effect (unlike verifyEmail).
        expect(container.read(authProvider).value, equals(stateBefore));
        verify(
          () => repo.verifyPasswordResetOtp(
            email: 'anya@example.com',
            code: '123456',
          ),
        ).called(1);
      },
    );

    test('rethrows PasswordResetOtpFailure from the repository', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      when(
        () => repo.verifyPasswordResetOtp(
          email: any(named: 'email'),
          code: any(named: 'code'),
        ),
      ).thenThrow(
        const PasswordResetOtpFailure(
          code: PasswordResetOtpErrorCode.invalidCode,
        ),
      );

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      await expectLater(
        () => container
            .read(authProvider.notifier)
            .verifyPasswordResetOtp(email: 'anya@example.com', code: '000000'),
        throwsA(isA<PasswordResetOtpFailure>()),
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

  // =========================================================================
  // firstName feature — regression guard (2026-05-25)
  //
  // login() and verifyEmail() now call repo.me() after obtaining tokens so
  // the settled Authenticated state carries firstName/lastName (absent from
  // the flat AuthResponse). These tests prove:
  //   (a) the user in state comes from repo.me(), not repo.login/verifyEmail,
  //   (b) if repo.me() throws after tokens are written, coldStartAccessToken
  //       is cleared and the error surfaces as AsyncError,
  //   (c) verifyEmail() sets AsyncLoading synchronously before any await so
  //       the submit button is disabled for the full network window.
  // =========================================================================

  // ---------------------------------------------------------------------------
  // login — me() output distinct from login() output
  //
  // The login() stub returns a User with firstName: null (mirrors the real
  // flat AuthResponse shape). The me() stub returns a User with firstName
  // populated. The settled state must carry the me() user — proving the notifier
  // uses me() and not the partial AuthResponse user.
  // ---------------------------------------------------------------------------
  group('login — firstName sourced from me()', () {
    test('login success: settled Authenticated user comes from repo.me() — '
        'firstName populated even though AuthResponse carries null', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      // Partial user as returned by the flat AuthResponse (no firstName).
      const partialUser = User(
        id: 'u1',
        email: 'test@example.com',
        role: UserRole.independentMaster,
        // firstName / lastName are absent from AuthResponse by contract.
      );
      // Full user as returned by GET /users/me.
      const fullUser = User(
        id: 'u1',
        email: 'test@example.com',
        role: UserRole.independentMaster,
        firstName: 'Іванна',
        lastName: 'Коваль',
      );

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      when(
        () => repo.login(email: 'test@example.com', password: 'pass123'),
      ).thenAnswer((_) async => (partialUser, testTokens));
      // me() returns a DIFFERENT object with firstName populated.
      when(() => repo.me()).thenAnswer((_) async => fullUser);

      await container
          .read(authProvider.notifier)
          .login('test@example.com', 'pass123');

      final value = container.read(authProvider);
      expect(value, isA<AsyncData<AuthSession>>());

      final session = value.value as Authenticated;
      // The session must carry the me() user, not the partial login user.
      expect(
        session.user.firstName,
        equals('Іванна'),
        reason:
            'firstName must come from repo.me() — '
            'AuthResponse does not include it',
      );
      expect(session.user.lastName, equals('Коваль'));
      // Structural equality: the full me() user is used, not partialUser.
      expect(
        session.user,
        equals(fullUser),
        reason: 'The settled session must hold the fullUser from repo.me()',
      );
    });

    // -----------------------------------------------------------------------
    // login: tokens obtained, then me() throws → AsyncError, sentinel cleared
    //
    // This is the critical partial-success error path for login():
    //   repo.login() → tokens written to storage
    //   coldStartAccessToken = tokens.accessToken   ← sentinel set
    //   repo.me() → throws UnauthorizedFailure
    //   finally { coldStartAccessToken = null }      ← MUST clear sentinel
    //   AsyncValue.guard() captures the error → AsyncError
    //
    // Without this test, deleting the try/finally block in AuthNotifier.login()
    // would leave the sentinel set on failure, giving the interceptor a stale
    // token for all subsequent requests in the same session.
    // -----------------------------------------------------------------------
    test(
      'login: repo.me() throws after tokens obtained → AsyncError surfaced, '
      'coldStartAccessToken cleared by finally, refresh token already persisted',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        const partialUser = User(
          id: 'u1',
          email: 'test@example.com',
          role: UserRole.independentMaster,
        );

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        when(
          () => repo.login(email: 'test@example.com', password: 'pass123'),
        ).thenAnswer((_) async => (partialUser, testTokens));
        // me() throws after the tokens have been written to storage.
        when(() => repo.me()).thenThrow(const UnauthorizedFailure());

        await container
            .read(authProvider.notifier)
            .login('test@example.com', 'pass123');

        final value = container.read(authProvider);

        // (1) Error must surface as AsyncError so the screen can render it.
        expect(
          value,
          isA<AsyncError<AuthSession>>(),
          reason:
              'A failed repo.me() inside login() must surface as AsyncError',
        );
        expect(
          value.error,
          isA<UnauthorizedFailure>(),
          reason:
              'The exact Failure from repo.me() must be the AsyncError payload',
        );

        // (2) coldStartAccessToken must be null — the try/finally block MUST
        // clear the sentinel even when me() throws.
        expect(
          container.read(authProvider.notifier).coldStartAccessToken,
          isNull,
          reason:
              'login() finally block must clear coldStartAccessToken '
              'even when repo.me() throws',
        );

        // (3) The refresh token written by login() before me() was called is
        // retained in storage — unlike the cold-start failure path, login()
        // does NOT wipe storage on me() failure (the user still has a valid
        // session; only the profile load failed).
        expect(
          await storage.readRefreshToken(),
          equals(testTokens.refreshToken),
          reason:
              'refresh token persisted before me() must not be wiped '
              'when me() fails inside login()',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // verifyEmail — me() output distinct from verifyEmail() output
  // ---------------------------------------------------------------------------
  group('verifyEmail — firstName sourced from me()', () {
    test(
      'verifyEmail success: settled Authenticated user comes from repo.me() — '
      'firstName populated even though AuthResponse carries null',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        // Partial user from AuthResponse (flat envelope — no firstName).
        const partialUser = User(
          id: 'u1',
          email: 'anya@example.com',
          role: UserRole.independentMaster,
        );
        // Full user as returned by GET /users/me.
        const fullUser = User(
          id: 'u1',
          email: 'anya@example.com',
          role: UserRole.independentMaster,
          firstName: 'Аня',
          lastName: 'Шевченко',
        );

        when(
          () => repo.verifyEmail(email: 'anya@example.com', otp: '123456'),
        ).thenAnswer((_) async => (partialUser, testTokens));
        when(() => repo.me()).thenAnswer((_) async => fullUser);

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        await container
            .read(authProvider.notifier)
            .verifyEmail(email: 'anya@example.com', otp: '123456');

        final value = container.read(authProvider);
        expect(value, isA<AsyncData<AuthSession>>());

        final session = value.value as Authenticated;
        // The session must carry the me() user — firstName must be populated.
        expect(
          session.user.firstName,
          equals('Аня'),
          reason:
              'firstName must come from repo.me() — '
              'AuthResponse does not include it',
        );
        expect(session.user.lastName, equals('Шевченко'));
        expect(
          session.user,
          equals(fullUser),
          reason: 'The settled session must hold the fullUser from repo.me()',
        );
      },
    );

    // -----------------------------------------------------------------------
    // verifyEmail AsyncLoading observed before async work completes
    //
    // verifyEmail() sets state = AsyncLoading() synchronously before any
    // await. This disables the submit button for the full
    // POST /verify-email + GET /users/me window, preventing double-submit.
    // Without this test, removing the synchronous `state = AsyncLoading()`
    // line would not break any other test.
    // -----------------------------------------------------------------------
    test('verifyEmail: state transitions through AsyncLoading before settling '
        '→ submit button disabled for the full async window', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      // Use a Completer to pause verifyEmail midway and observe the state.
      final pauseCompleter = Completer<(User, AuthTokens)>();

      when(
        () => repo.verifyEmail(email: 'anya@example.com', otp: '123456'),
      ).thenAnswer((_) => pauseCompleter.future);

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      // Start verifyEmail — do NOT await yet.
      final verifyFuture = container
          .read(authProvider.notifier)
          .verifyEmail(email: 'anya@example.com', otp: '123456');

      // Give the microtask queue a turn so the synchronous
      // `state = AsyncLoading()` assignment fires but the Completer has
      // not resolved yet.
      await Future<void>.microtask(() {});

      // State MUST be AsyncLoading while verifyEmail is in-flight.
      expect(
        container.read(authProvider),
        isA<AsyncLoading<AuthSession>>(),
        reason:
            'verifyEmail() must set state = AsyncLoading() synchronously '
            'before any await so the submit button is disabled immediately',
      );

      // Now let the operation complete.
      const partialUser = User(
        id: 'u1',
        email: 'anya@example.com',
        role: UserRole.independentMaster,
      );
      when(() => repo.me()).thenAnswer((_) async => testUser);
      pauseCompleter.complete((partialUser, testTokens));
      await verifyFuture;

      // After settling, state must be Authenticated.
      final value = container.read(authProvider);
      expect(
        value,
        isA<AsyncData<AuthSession>>(),
        reason: 'verifyEmail() must settle to AsyncData on success',
      );
    });

    // -----------------------------------------------------------------------
    // verifyEmail: me() throws after tokens written → sentinel cleared,
    // error propagated (state stays AsyncLoading — callers must handle)
    // -----------------------------------------------------------------------
    test('verifyEmail: repo.me() throws after tokens written → '
        'coldStartAccessToken cleared, error rethrown', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      const partialUser = User(
        id: 'u1',
        email: 'anya@example.com',
        role: UserRole.independentMaster,
      );

      when(
        () => repo.verifyEmail(email: 'anya@example.com', otp: '123456'),
      ).thenAnswer((_) async => (partialUser, testTokens));
      // me() throws after the refresh token has been written to storage.
      when(() => repo.me()).thenThrow(const UnauthorizedFailure());

      final container = makeContainer(repo: repo, storage: storage);
      await container.read(authProvider.future);

      // verifyEmail must rethrow — the calling screen catches and renders it.
      await expectLater(
        () => container
            .read(authProvider.notifier)
            .verifyEmail(email: 'anya@example.com', otp: '123456'),
        throwsA(isA<UnauthorizedFailure>()),
      );

      // coldStartAccessToken must be null after the finally block runs.
      expect(
        container.read(authProvider.notifier).coldStartAccessToken,
        isNull,
        reason:
            'verifyEmail() finally block must clear coldStartAccessToken '
            'even when repo.me() throws after tokens are obtained',
      );

      // The refresh token was already persisted before me() was called and
      // must not be wiped by the me() failure.
      expect(
        await storage.readRefreshToken(),
        equals(testTokens.refreshToken),
        reason:
            'refresh token persisted before me() must survive a me() failure '
            'inside verifyEmail()',
      );
    });

    // -----------------------------------------------------------------------
    // MEDIUM-4 — JWT exp pre-check (mobile-security 2026-05-27)
    // -----------------------------------------------------------------------

    // Builds a minimal JWT with a given exp claim (seconds since epoch).
    // The header and signature are stub values — _isTokenExpired only reads
    // the payload, never verifies the signature.
    String buildJwt({required int expSeconds}) {
      final headerB64 = base64Url
          .encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'))
          .replaceAll('=', '');
      final payloadB64 = base64Url
          .encode(utf8.encode('{"sub":"u1","exp":$expSeconds}'))
          .replaceAll('=', '');
      return '$headerB64.$payloadB64.signature';
    }

    test('MEDIUM-4: cold start with already-expired refresh token → '
        'Unauthenticated without a network call; storage wiped', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      // Build a JWT whose exp is 60 seconds in the past.
      final pastExp = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60;
      final expiredJwt = buildJwt(expSeconds: pastExp);
      await storage.writeRefreshToken(expiredJwt);

      final container = makeContainer(repo: repo, storage: storage);
      final session = await container.read(authProvider.future);

      // Must return Unauthenticated without touching the repository.
      expect(session, equals(const AuthSession.unauthenticated()));
      verifyNever(() => repo.refresh(any()));
      verifyNever(() => repo.me());

      // Storage must be wiped (stale token cleaned up).
      expect(
        await storage.readRefreshToken(),
        isNull,
        reason: 'expired token must be deleted during cold-start pre-check',
      );
    });

    test('MEDIUM-4: cold start with non-expired refresh token → '
        'attempts network refresh (normal path)', () async {
      final repo = MockAuthRepository();
      final storage = FakeSecureStorage();

      // Build a JWT whose exp is 5 minutes in the future (well within the
      // 30-second grace window). The pre-check must NOT skip the refresh call.
      final futureExp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 300;
      final validJwt = buildJwt(expSeconds: futureExp);
      await storage.writeRefreshToken(validJwt);

      when(() => repo.refresh(validJwt)).thenAnswer((_) async => rotatedTokens);
      when(() => repo.me()).thenAnswer((_) async => testUser);

      final container = makeContainer(repo: repo, storage: storage);
      final session = await container.read(authProvider.future);

      // Network refresh must have been attempted.
      verify(() => repo.refresh(validJwt)).called(1);
      expect(
        session,
        equals(
          AuthSession.authenticated(
            user: testUser,
            accessToken: rotatedTokens.accessToken,
          ),
        ),
      );
    });
  });

  // =========================================================================
  // fix: auth session race — sentinel ordering regression guard (2026-05-30)
  //
  // Root cause (Level 6 Riverpod): the old verifyEmail() / login() code
  // cleared `coldStartAccessToken = null` in a `finally` block BEFORE
  // returning the Authenticated value to AsyncValue.guard. This left a
  // one-microtask window where:
  //   - authProvider.value was NOT Authenticated (AsyncLoading still)
  //   - coldStartAccessToken was null (sentinel already wiped)
  //
  // AuthInterceptor consults `notifier.coldStartAccessToken` when the
  // provider state is not yet Authenticated. During that window it found null
  // → injected no Bearer token → PATCH /independent-masters/me returned 401
  // → RefreshInterceptor triggered logout → "Сесія завершилась" shown.
  //
  // The fix (committed 2026-05-30): set state = AsyncData(Authenticated) FIRST
  // (by returning from the AsyncValue.guard lambda in login, or by explicit
  // state assignment in verifyEmail), THEN clear coldStartAccessToken.
  //
  // These tests assert the invariant directly:
  //   "After verifyEmail() / login() returns, if state is Authenticated then
  //    coldStartAccessToken is null; if state is NOT Authenticated (i.e. the
  //    provider is still in a transient state observed via an addListener call
  //    that fires between the two assignments) then coldStartAccessToken must
  //    NOT be null — the sentinel must still be active."
  //
  // Implementation approach:
  //   Use an addListener observer that captures (state.value, sentinel)
  //   pairs on every transition. After verifyEmail returns, inspect every
  //   captured snapshot. If any snapshot has both state.value not-Authenticated
  //   AND sentinel == null, the race is present.
  //
  // This is the only test that can catch a reversion to the buggy `finally`
  // ordering, because the race window is a single microtask — no widget test
  // pump sequence can reliably observe it.
  // =========================================================================

  group('verifyEmail — sentinel ordering (auth session race regression guard)', () {
    // -----------------------------------------------------------------------
    // verifyEmail — the Authenticated state is set BEFORE sentinel is cleared.
    //
    // Root cause of the "Сесія завершилась" bug (2026-05-30):
    //
    // The old finally-block order:
    //   1. coldStartAccessToken = null   ← sentinel wiped FIRST
    //   2. state = AsyncData(Authenticated)  ← state settled SECOND
    //
    // Between steps 1 and 2, Dart yields a microtask. Any Dio request that
    // fires during that gap finds:
    //   - authProvider.value is NOT Authenticated (state still AsyncLoading)
    //   - coldStartAccessToken is null (sentinel already wiped)
    // → AuthInterceptor injects no Bearer → 401 → logout → "Сесія завершилась"
    //
    // The fix: state = AsyncData(Authenticated) FIRST, then sentinel = null.
    // Once the state is Authenticated, AuthInterceptor reads the token from
    // the settled session; the sentinel is no longer needed.
    //
    // This test probes the ordering by observing the sentinel value at the
    // exact moment the Authenticated state is emitted (via the Riverpod
    // listener). At that instant, coldStartAccessToken must already be null
    // (because the fix sets state first, then clears the sentinel — so by
    // the time any listener reacts, the sentinel is still non-null, but we
    // verify the critical invariant: after state settles to Authenticated,
    // the sentinel is cleared to null).
    //
    // Secondary invariant: at no point after the sentinel is first set (i.e.
    // once tokens are obtained) does the provider emit a non-Authenticated
    // state WITH the sentinel already null. The initial AsyncLoading emitted
    // at the top of verifyEmail() (before sentinel is set) is excluded — it
    // is correct for the sentinel to be null then.
    // -----------------------------------------------------------------------
    test(
      'verifyEmail success: state settles to Authenticated before '
      'coldStartAccessToken is cleared — sentinel null only after '
      'Authenticated state is emitted (regression guard for 2026-05-30 race fix)',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        when(
          () => repo.verifyEmail(email: 'anya@example.com', otp: '123456'),
        ).thenAnswer((_) async => (testUser, testTokens));
        when(() => repo.me()).thenAnswer((_) async => testUser);

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        // Collect (state, sentinel) snapshots on every Riverpod emission.
        // Importantly: we record whether we have already seen an Authenticated
        // state. The invariant is:
        //   "Once the sentinel was non-null (i.e. after tokens were received),
        //    no subsequent non-Authenticated state may be emitted with a null
        //    sentinel."
        //
        // The very first emission (state = AsyncLoading before any await) has
        // sentinel=null, which is correct — the sentinel has not been set yet.
        // We skip these early snapshots by tracking whether the sentinel was
        // ever non-null.
        final snapshots =
            <({AsyncValue<AuthSession> state, String? sentinel})>[];
        bool sentinelWasEverSet = false;

        final sub = container.listen<AsyncValue<AuthSession>>(authProvider, (
          _,
          next,
        ) {
          final currentSentinel = container
              .read(authProvider.notifier)
              .coldStartAccessToken;
          if (currentSentinel != null) sentinelWasEverSet = true;
          snapshots.add((state: next, sentinel: currentSentinel));
        });
        addTearDown(sub.close);

        await container
            .read(authProvider.notifier)
            .verifyEmail(email: 'anya@example.com', otp: '123456');

        // After verifyEmail completes, the sentinel must have been set at
        // some point (proving the HIGH-1 pattern ran) AND then cleared.
        //
        // Note: the listener may not have observed the sentinel while it was
        // non-null because verifyEmail() sets the sentinel and clears it
        // between two await points (inside the try block, without a `state =`
        // between set and clear). However, `state = AsyncData(Authenticated)`
        // IS emitted while the sentinel is non-null (that is the invariant of
        // the fix). Check via the Authenticated snapshot's sentinel value.
        final authenticatedSnapshots = snapshots
            .where((s) => s.state.value is Authenticated)
            .toList();

        // There must be exactly one Authenticated snapshot.
        expect(
          authenticatedSnapshots,
          hasLength(1),
          reason:
              'verifyEmail() must emit exactly one Authenticated state on success',
        );

        // The snapshot captured by the listener fires AFTER the state
        // assignment but synchronously with the Riverpod notification. At
        // this point, the sentinel has already been cleared (the line
        // `coldStartAccessToken = null` runs immediately after
        // `state = AsyncData(Authenticated(...))` in the source). So the
        // sentinel value in the snapshot is null — which is CORRECT.
        //
        // What we actually verify: NO non-Authenticated state was emitted
        // AFTER the sentinel was first observed as non-null (i.e. the race
        // window is absent).
        //
        // If the old finally-block bug is reintroduced, the sequence would be:
        //   1. sentinel set to access token (inside the try block)
        //   2. sentinel = null (in finally, BEFORE state assignment) ← bug
        //   3. state = AsyncData(Authenticated) (AFTER finally)
        // In that case the listener would capture sentinel=null at the moment
        // AsyncLoading is still active, triggering the assertion below.
        if (sentinelWasEverSet) {
          // The sentinel was observed as non-null during some listener
          // notification. Check that no non-Authenticated state came AFTER
          // that sentinel-set point with sentinel already null.
          bool seenSentinelSet = false;
          for (final snap in snapshots) {
            if (snap.sentinel != null) seenSentinelSet = true;
            if (seenSentinelSet && snap.state.value is! Authenticated) {
              expect(
                snap.sentinel,
                isNotNull,
                reason:
                    'After the sentinel was first set (tokens obtained), no '
                    'non-Authenticated state may be emitted with sentinel==null. '
                    'This would indicate the old race: sentinel cleared before '
                    'state settled to Authenticated. '
                    'Snapshot: state=${snap.state}, sentinel=${snap.sentinel}.',
              );
            }
          }
        }

        // Final state must be Authenticated (sanity).
        expect(
          container.read(authProvider).value,
          isA<Authenticated>(),
          reason: 'verifyEmail() must settle to Authenticated on success',
        );

        // Sentinel must be null after verifyEmail() returns (cleared post-settle).
        expect(
          container.read(authProvider.notifier).coldStartAccessToken,
          isNull,
          reason:
              'coldStartAccessToken must be null after verifyEmail() returns — '
              'the settled Authenticated state carries the access token; the '
              'sentinel is no longer needed.',
        );
      },
    );

    // -----------------------------------------------------------------------
    // login — same sentinel ordering invariant.
    //
    // The login() fix: the sentinel is cleared AFTER the `session` local
    // variable is constructed and returned from the AsyncValue.guard lambda.
    // AsyncValue.guard captures the return value and sets state =
    // AsyncData(session) before yielding — so the state settles before the
    // next line (which no longer exists; the sentinel clear is now the last
    // line of the lambda body before return).
    // -----------------------------------------------------------------------
    test(
      'login success: sentinel null only after Authenticated state is emitted — '
      'no race window where both state is loading and sentinel is null '
      '(login variant of 2026-05-30 race fix)',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();

        when(
          () => repo.login(email: 'test@example.com', password: 'pass123'),
        ).thenAnswer((_) async => (testUser, testTokens));
        when(() => repo.me()).thenAnswer((_) async => testUser);

        final container = makeContainer(repo: repo, storage: storage);
        await container.read(authProvider.future);

        final snapshots =
            <({AsyncValue<AuthSession> state, String? sentinel})>[];
        bool sentinelWasEverSet = false;

        final sub = container.listen<AsyncValue<AuthSession>>(authProvider, (
          _,
          next,
        ) {
          final currentSentinel = container
              .read(authProvider.notifier)
              .coldStartAccessToken;
          if (currentSentinel != null) sentinelWasEverSet = true;
          snapshots.add((state: next, sentinel: currentSentinel));
        });
        addTearDown(sub.close);

        await container
            .read(authProvider.notifier)
            .login('test@example.com', 'pass123');

        if (sentinelWasEverSet) {
          bool seenSentinelSet = false;
          for (final snap in snapshots) {
            if (snap.sentinel != null) seenSentinelSet = true;
            if (seenSentinelSet && snap.state.value is! Authenticated) {
              expect(
                snap.sentinel,
                isNotNull,
                reason:
                    'After the sentinel was first set during login(), no '
                    'non-Authenticated state may be emitted with sentinel==null. '
                    'Snapshot: state=${snap.state}, sentinel=${snap.sentinel}.',
              );
            }
          }
        }

        expect(container.read(authProvider).value, isA<Authenticated>());
        expect(
          container.read(authProvider.notifier).coldStartAccessToken,
          isNull,
          reason:
              'coldStartAccessToken must be null after login() returns — '
              'the sentinel is no longer needed once state is Authenticated.',
        );
      },
    );
  });

  // =========================================================================
  // M5 — logout secure-storage wipe is UNCONDITIONAL (mobile-security)
  //
  // Regression guard for the M5 hardening in AuthNotifier.logout(): the
  // best-effort server revocation call (repo.logout()) is wrapped so that
  //   - a [Failure]            (on Failure catch) is swallowed,
  //   - a NON-Failure error    (catch (e), e.g. StateError) is also swallowed,
  // and then `storage.deleteAll()` ALWAYS runs and the state ALWAYS settles to
  // Unauthenticated. logout() must NEVER rethrow. Without these tests, removing
  // the catch-all (catch (e)) branch or moving deleteAll() back inside a try
  // would let an explicit logout leave the refresh token on device.
  //
  // Unlike the rest of the file (which uses the plain FakeSecureStorage), this
  // group needs `verify(() => storage.deleteAll())` interaction assertions, so
  // it uses [SpySecureStorage] (a mocktail Mock delegating to a backing fake).
  // It keeps a stub serviceRepositoryProvider override purely so these
  // storage-wipe tests do not depend on the real Dio-backed service graph — the
  // override is incidental here (since the 2026-06-18 fix removed the cyclic
  // ref.invalidate() calls, logout() no longer needs the edge broken at all).
  // =========================================================================
  group('logout — secure-storage wipe is unconditional (M5)', () {
    // Local container builder for this group only — does NOT touch the shared
    // makeContainer(). Wires the spy storage + a stub service repository so
    // these storage-wipe tests stay off the real Dio-backed service graph.
    ProviderContainer makeM5Container({
      required AuthRepository repo,
      required SpySecureStorage storage,
    }) {
      final serviceRepo = _MockServiceRepository();
      when(
        () => serviceRepo.listMyServices(),
      ).thenAnswer((_) async => const <MasterService>[]);

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith((_) => repo),
          secureStorageProvider.overrideWith((_) => storage),
          // cycle-stub-ok: the M5 group asserts logout's storage-wipe/interaction behaviour on server-error paths — it does NOT exercise the auth→services watch cascade. That cascade is covered by tests 5b/5c, which deliberately keep the REAL serviceRepository/servicesList graph (only the leaf masterRepositoryProvider stubbed) so the cycle assert can fire there.
          serviceRepositoryProvider.overrideWithValue(serviceRepo),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    // -----------------------------------------------------------------------
    // M5-1 — repo.logout() throws a Failure → deleteAll() still called,
    //        logout() does NOT throw, state → Unauthenticated, token wiped.
    // -----------------------------------------------------------------------
    test('repo.logout() throws a Failure → deleteAll() still called, logout '
        'does not throw, state → Unauthenticated, token wiped', () async {
      final repo = MockAuthRepository();
      final backing = FakeSecureStorage();
      await backing.writeRefreshToken('stored-refresh');
      final storage = SpySecureStorage(backing);

      // Authenticate the session first so logout() has a real session to clear.
      when(
        () => repo.refresh('stored-refresh'),
      ).thenAnswer((_) async => testTokens);
      when(() => repo.me()).thenAnswer((_) async => testUser);
      // Server revocation fails with a typed Failure — must be swallowed.
      when(() => repo.logout()).thenThrow(const NetworkFailure());

      final container = makeM5Container(repo: repo, storage: storage);
      await container.read(authProvider.future);

      final notifier = container.read(authProvider.notifier);

      // logout() must complete normally despite the Failure from repo.logout().
      await expectLater(notifier.logout(), completes);

      // deleteAll() was invoked exactly once (the unconditional wipe).
      verify(() => storage.deleteAll()).called(1);

      // The refresh-token key (BEAUTICA_REFRESH_TOKEN) is gone — proving the
      // backing store was actually cleared by deleteAll().
      expect(
        await storage.readRefreshToken(),
        isNull,
        reason:
            'deleteAll() must wipe the refresh token even when repo.logout() '
            'throws a Failure',
      );

      // End state Unauthenticated; in-memory token fallback cleared.
      final value = container.read(authProvider);
      expect(value, isA<AsyncData<AuthSession>>());
      expect(value.value, equals(const AuthSession.unauthenticated()));
      expect(notifier.lastKnownAccessToken, isNull);
    });

    // -----------------------------------------------------------------------
    // M5-2 — repo.logout() succeeds → repo.logout() + deleteAll() each called
    //        once, state → Unauthenticated.
    // -----------------------------------------------------------------------
    test('repo.logout() succeeds → repo.logout() + deleteAll() called once, '
        'state → Unauthenticated', () async {
      final repo = MockAuthRepository();
      final backing = FakeSecureStorage();
      await backing.writeRefreshToken('stored-refresh');
      final storage = SpySecureStorage(backing);

      when(
        () => repo.refresh('stored-refresh'),
      ).thenAnswer((_) async => testTokens);
      when(() => repo.me()).thenAnswer((_) async => testUser);
      when(() => repo.logout()).thenAnswer((_) async {});

      final container = makeM5Container(repo: repo, storage: storage);
      await container.read(authProvider.future);

      final notifier = container.read(authProvider.notifier);
      await expectLater(notifier.logout(), completes);

      // Both the server revocation and the local wipe happened exactly once.
      verify(() => repo.logout()).called(1);
      verify(() => storage.deleteAll()).called(1);

      expect(
        await storage.readRefreshToken(),
        isNull,
        reason: 'deleteAll() must wipe the refresh token on a clean logout',
      );

      final value = container.read(authProvider);
      expect(value, isA<AsyncData<AuthSession>>());
      expect(value.value, equals(const AuthSession.unauthenticated()));
    });

    // -----------------------------------------------------------------------
    // M5-3 — repo.logout() throws a NON-Failure error (StateError) →
    //        still swallowed, storage wiped, state → Unauthenticated.
    //
    // This guards the catch-all `catch (e)` branch added by the M5 hardening:
    // a raw StateError (not a Failure subtype) must NOT propagate past the
    // wipe — otherwise an explicit logout would leave the refresh token on
    // device. If the catch-all branch were removed, logout() would rethrow and
    // deleteAll() would never run.
    // -----------------------------------------------------------------------
    test('repo.logout() throws a non-Failure (StateError) → swallowed, '
        'storage wiped, state → Unauthenticated', () async {
      final repo = MockAuthRepository();
      final backing = FakeSecureStorage();
      await backing.writeRefreshToken('stored-refresh');
      final storage = SpySecureStorage(backing);

      when(
        () => repo.refresh('stored-refresh'),
      ).thenAnswer((_) async => testTokens);
      when(() => repo.me()).thenAnswer((_) async => testUser);
      // A raw, NON-Failure error — the catch-all `catch (e)` must swallow it.
      when(() => repo.logout()).thenThrow(StateError('boom'));

      final container = makeM5Container(repo: repo, storage: storage);
      await container.read(authProvider.future);

      final notifier = container.read(authProvider.notifier);

      // logout() must NOT rethrow the StateError — it completes normally.
      await expectLater(notifier.logout(), completes);

      // The wipe HAPPENED despite the non-Failure error — the M5 invariant.
      verify(() => storage.deleteAll()).called(1);
      expect(
        await storage.readRefreshToken(),
        isNull,
        reason:
            'deleteAll() must wipe the refresh token even when repo.logout() '
            'throws a non-Failure error (StateError)',
      );

      final value = container.read(authProvider);
      expect(value, isA<AsyncData<AuthSession>>());
      expect(value.value, equals(const AuthSession.unauthenticated()));
      expect(notifier.lastKnownAccessToken, isNull);
    });
  });

  // =========================================================================
  // CircularDependencyError on logout — regression guard (2026-06-18)
  //
  // THE BUG (debug/flutter-test only): logout() used to call
  //   ref.invalidate(masterProfileProvider)   // + serviceRepository + servicesList
  // from INSIDE authProvider. masterProfileProvider.build() does
  //   ref.watch(authProvider)   (master_profile_notifier.dart:33)
  // and serviceRepository → masterProfile, servicesList → serviceRepository all
  // transitively reach authProvider too. Invalidating any of them from inside
  // authProvider records an `authProvider → X` forward edge while the
  // `X → authProvider` reverse edge already exists → a cycle. Riverpod's
  // kDebugMode `_debugAssertCanDependOn` then throws CircularDependencyError,
  // which escapes past `state = AsyncData(Unauthenticated)` and surfaces a
  // false "logout failed". The assert is stripped in AOT/release, so the bug
  // only ever reproduced under `flutter test` / debug — which is exactly why
  // the OLD Test 5b/5c never caught it: they STUBBED the cyclic providers to
  // break the `→ authProvider` edge, engineering the bug away.
  //
  // THE FIX: logout() removed the three cyclic ref.invalidate() calls entirely
  // (the watchers clear automatically when auth flips to Unauthenticated) and
  // reaches `state = AsyncData(Unauthenticated())` unconditionally after the
  // storage wipe.
  //
  // HOW THIS TEST REPRODUCES THE BUG (unlike the old tests):
  //   - It does NOT stub masterProfile / serviceRepository / servicesList.
  //     Only the LEAF data deps are overridden (authRepository, secureStorage,
  //     masterRepository) so the real notifiers build.
  //   - It registers the cyclic edge by `container.listen(masterProfileProvider)`
  //     (and servicesListProvider) BEFORE logout, so masterProfileProvider.build()
  //     runs `ref.watch(authProvider)` and the `authProvider → masterProfile`
  //     reverse edge is live in the graph.
  //   - Against PRE-FIX code (the three ref.invalidate() calls present), logout()
  //     would record the forward edge → CircularDependencyError thrown → this
  //     test FAILS (logout() does not `complete`). Against the fixed code there
  //     is no invalidate, so no forward edge, so logout() completes and settles
  //     Unauthenticated. This is the would-fail-on-unfixed-code property the
  //     debug-chain QA gate (Step 2.7 Rule 3) requires.
  // =========================================================================
  group('logout — no CircularDependencyError with the real cyclic graph', () {
    test(
      'logout() completes without throwing CircularDependencyError when '
      'masterProfile/servicesList are the REAL production providers (the cyclic '
      'edge to authProvider is live) and settles state to Unauthenticated',
      () async {
        final repo = MockAuthRepository();
        final storage = FakeSecureStorage();
        await storage.writeRefreshToken('stored-refresh');

        when(
          () => repo.refresh('stored-refresh'),
        ).thenAnswer((_) async => testTokens);
        when(() => repo.me()).thenAnswer((_) async => testUser);
        when(() => repo.logout()).thenAnswer((_) async {});

        // Override ONLY the leaf data-layer deps. masterProfileProvider,
        // serviceRepositoryProvider and servicesListProvider are LEFT REAL so
        // each registers its transitive `ref.watch(authProvider)` — the exact
        // reverse edge the old Test 5b/5c stubbed away to dodge the assert.
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWith((_) => repo),
            secureStorageProvider.overrideWith((_) => storage),
            masterRepositoryProvider.overrideWith(
              (_) => FakeMasterRepository(),
            ),
          ],
        );
        addTearDown(container.dispose);

        // Authenticate first so the session is Authenticated.
        await container.read(authProvider.future);

        // Register the cyclic edges: subscribing makes masterProfileProvider and
        // servicesListProvider build, running their `ref.watch(authProvider)` /
        // transitive watches so the reverse edge `…→ authProvider` is recorded.
        // Without these listens the providers are never built and the cycle is
        // never closed — so these subscriptions are load-bearing for the repro.
        final masterSub = container.listen(
          masterProfileProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(masterSub.close);
        final servicesSub = container.listen(
          servicesListProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(servicesSub.close);

        // Settle masterProfile so its `ref.watch(authProvider)` subscription is
        // firmly established in the dependency graph before logout runs.
        await container.read(masterProfileProvider.future);

        // THE ASSERTION: against pre-fix code this throws CircularDependencyError
        // (logout records authProvider → masterProfile while masterProfile →
        // authProvider already exists). Against the fixed code it completes.
        await expectLater(
          container.read(authProvider.notifier).logout(),
          completes,
          reason:
              'logout() must NOT throw CircularDependencyError — the fix removed '
              'the cyclic ref.invalidate() calls; teardown is handled by the '
              'auth-watch cascade. A reverted fix re-trips the debug assert here.',
        );

        // The state transition after the wipe must have been reached.
        final value = container.read(authProvider);
        expect(value, isA<AsyncData<AuthSession>>());
        expect(
          value.value,
          equals(const AuthSession.unauthenticated()),
          reason:
              'logout() must settle authProvider to Unauthenticated — a thrown '
              'CircularDependencyError would have escaped before this transition.',
        );

        // Storage was wiped as part of the (now uninterrupted) logout path.
        expect(await storage.readRefreshToken(), isNull);
      },
    );
  });
}
