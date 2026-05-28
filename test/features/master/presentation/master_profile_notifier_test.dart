// Phase 4.2 — Unit tests for MasterProfile AsyncNotifier.
//
// Covers:
//   1. build() — returns Master when session is Authenticated.
//   2. build() — AsyncError(UnauthorizedFailure) when session is Unauthenticated.
//   3. build() — AsyncError(NetworkFailure) when repository throws.
//   4. refresh() — transitions to updated AsyncData on success.
//   5. refresh() — transitions to AsyncError on repo failure.
//
// Strategy:
//   Override [authProvider] with a stub that resolves synchronously (via
//   Future.value) to either [Authenticated] or [Unauthenticated], and also
//   override [secureStorageProvider] with [FakeSecureStorage] so no platform
//   channel is touched. [masterRepositoryProvider] is overridden with a
//   mocktail mock.
//
//   Each test creates a fresh [ProviderContainer] and disposes it in
//   [addTearDown] (M1 hygiene).
//
//   Pure Dart — no widget tree.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockMasterRepository extends Mock implements MasterRepository {}

// ---------------------------------------------------------------------------
// Stub data
// ---------------------------------------------------------------------------

const _testUserId = 'user-42';

const _stubUser = User(
  id: _testUserId,
  email: 'master@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Оля',
  lastName: 'Тест',
);

const _stubMaster = Master(
  id: _testUserId,
  firstName: 'Оля',
  lastName: 'Тест',
  avgRating: 4.7,
  reviewCount: 11,
  type: MasterType.independentMaster,
);

// ---------------------------------------------------------------------------
// Stub AuthNotifier that resolves to [Authenticated] immediately.
// ---------------------------------------------------------------------------

/// Resolves to [Authenticated] without touching platform channels.
///
/// Uses [Future.value] so the [AsyncNotifier] resolves in the very next
/// microtask — no platform I/O, no storage read.
class _StubAuthAuthenticated extends AuthNotifier {
  @override
  Future<AuthSession> build() => Future.value(
    AuthSession.authenticated(user: _stubUser, accessToken: 'tok'),
  );
}

/// Resolves to [Unauthenticated] immediately.
class _StubAuthUnauthenticated extends AuthNotifier {
  @override
  Future<AuthSession> build() => Future.value(
    const AuthSession.unauthenticated(),
  );
}

// ---------------------------------------------------------------------------
// Container factory
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer({
  required AuthNotifier Function() authFactory,
  required MasterRepository repo,
}) {
  final container = ProviderContainer(
    overrides: [
      // Override auth so it never touches the real SecureStorage or Dio.
      authProvider.overrideWith(authFactory),
      // Provide a no-op storage so any provider that refs secureStorageProvider
      // does not touch platform channels.
      secureStorageProvider.overrideWithValue(FakeSecureStorage()),
      // Provide a no-op fake auth repo so AuthNotifier doesn't require
      // authRepositoryProvider to be wired to a real Dio instance.
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      // MasterRepository under test.
      masterRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockMasterRepository repo;

  setUp(() {
    repo = _MockMasterRepository();
  });

  // ── 1. build() — happy path ──────────────────────────────────────────────

  group('build()', () {
    test('returns Master when session is Authenticated', () async {
      when(() => repo.getMyProfile(_testUserId))
          .thenAnswer((_) async => _stubMaster);

      final container = _makeContainer(
        authFactory: _StubAuthAuthenticated.new,
        repo: repo,
      );

      // Settle authProvider first so it is Authenticated before
      // masterProfileProvider.build() runs its ref.watch(authProvider) check.
      await container.read(authProvider.future);

      final master = await container.read(masterProfileProvider.future);

      expect(master.id, _testUserId);
      expect(master.firstName, 'Оля');
      expect(master.type, MasterType.independentMaster);
    });

    test('emits AsyncError(UnauthorizedFailure) when session is Unauthenticated',
        () async {
      final container = _makeContainer(
        authFactory: _StubAuthUnauthenticated.new,
        repo: repo,
      );

      // Settle authProvider first so it resolves to Unauthenticated before
      // masterProfileProvider builds. This avoids the Loading→Unauthenticated
      // transition triggering a second rebuild mid-test.
      await container.read(authProvider.future);

      // Trigger the build by reading the provider. Build() sees Unauthenticated
      // and throws synchronously — Riverpod wraps this in AsyncError.
      // expectLater with the .future properly observes the first completion.
      // We use catchError to handle the StateError that Riverpod emits when a
      // keepAlive provider disposes during a never-completing build. Instead,
      // read the state after a microtask when the error is settled.
      container.read(masterProfileProvider); // trigger build
      await Future<void>.delayed(Duration.zero); // let microtask settle

      final state = container.read(masterProfileProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<UnauthorizedFailure>());

      // Repo must never be called when the auth guard fires.
      verifyNever(() => repo.getMyProfile(any()));
    });

    test('emits AsyncError(NetworkFailure) when repository throws', () async {
      when(() => repo.getMyProfile(_testUserId))
          .thenThrow(const NetworkFailure());

      final container = _makeContainer(
        authFactory: _StubAuthAuthenticated.new,
        repo: repo,
      );

      // Settle auth so masterProfileProvider sees Authenticated on its build.
      await container.read(authProvider.future);

      // Trigger build + allow the async error to settle without rethrowing.
      // We cannot use .future (keepAlive provider dispose throws StateError), so
      // trigger the build lazily and drain one microtask cycle instead.
      container.read(masterProfileProvider); // triggers build
      await Future<void>.delayed(Duration.zero); // let NetworkFailure settle

      final state = container.read(masterProfileProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<NetworkFailure>());
    });
  });

  // ── 2. refresh() ─────────────────────────────────────────────────────────

  group('refresh()', () {
    test('transitions to updated AsyncData on success', () async {
      when(() => repo.getMyProfile(_testUserId))
          .thenAnswer((_) async => _stubMaster);

      final container = _makeContainer(
        authFactory: _StubAuthAuthenticated.new,
        repo: repo,
      );

      // Settle auth first, then wait for initial build to complete.
      await container.read(authProvider.future);
      await container.read(masterProfileProvider.future);

      // Update the repo stub to return a different master.
      const updatedMaster = Master(
        id: _testUserId,
        firstName: 'Оля',
        lastName: 'Оновлена',
        avgRating: 5.0,
        reviewCount: 20,
        type: MasterType.independentMaster,
      );
      when(() => repo.getMyProfile(_testUserId))
          .thenAnswer((_) async => updatedMaster);

      await container.read(masterProfileProvider.notifier).refresh();

      final state = container.read(masterProfileProvider);
      expect(state.value?.lastName, 'Оновлена');
      expect(state.value?.reviewCount, 20);
    });

    test('transitions to AsyncError on repo failure', () async {
      when(() => repo.getMyProfile(_testUserId))
          .thenAnswer((_) async => _stubMaster);

      final container = _makeContainer(
        authFactory: _StubAuthAuthenticated.new,
        repo: repo,
      );

      // Settle auth first, then wait for initial build.
      await container.read(authProvider.future);
      await container.read(masterProfileProvider.future);

      // Stub the repo to fail on next call (refresh).
      when(() => repo.getMyProfile(_testUserId))
          .thenThrow(const ServerFailure(statusCode: 503));

      await container.read(masterProfileProvider.notifier).refresh();

      final state = container.read(masterProfileProvider);
      expect(state.hasError, isTrue);
      expect(
        state.error,
        isA<ServerFailure>()
            .having((f) => f.statusCode, 'statusCode', 503),
      );
    });
  });
}
