// Tests for auth selector providers.
//
// Covers [currentUserProvider] and [isAuthenticatedProvider] from
// lib/features/auth/presentation/auth_selectors.dart.
//
// Both providers derive their value from [authProvider]; tests use a
// [ProviderContainer] with [authProvider] overridden by a fixed-state stub.
//
// Test matrix (6 tests):
//   currentUserProvider:
//     1. Loading auth state → null
//     2. Authenticated state → returns the test user
//     3. Unauthenticated state → null
//   isAuthenticatedProvider:
//     4. Loading auth state → false
//     5. Authenticated state → true
//     6. Unauthenticated state → false

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_selectors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _testUser = User(
  id: 'u1',
  email: 'test@example.com',
  role: UserRole.independentMaster,
  firstName: 'Test',
  lastName: 'User',
);

const _fakeAccessToken = 'test-access-token';

// ---------------------------------------------------------------------------
// AuthNotifier stub that returns a fixed AsyncValue<AuthSession>.
// ---------------------------------------------------------------------------

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
}

// ---------------------------------------------------------------------------
// Container factory
// ---------------------------------------------------------------------------

/// Creates a [ProviderContainer] with [authProvider] overridden by a stub
/// that immediately emits [authState].
ProviderContainer _makeContainer(AsyncValue<AuthSession> authState) {
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      authProvider.overrideWith(() => _FixedAuthNotifier(authState)),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // currentUserProvider
  // =========================================================================

  group('currentUserProvider', () {
    // -----------------------------------------------------------------------
    // Test 1 — Loading auth state → null
    // -----------------------------------------------------------------------
    test('loading auth state → currentUser is null', () async {
      final container = _makeContainer(const AsyncLoading<AuthSession>());
      // Do not await the future — the notifier sets state to AsyncLoading
      // and build() never throws from _FixedAuthNotifier, but the selector
      // reads `.value` which is null for AsyncLoading.
      //
      // Read after triggering build by initialising the provider.
      container.read(authProvider); // trigger build
      // Allow microtasks to run.
      await Future<void>.delayed(Duration.zero);

      final currentUser = container.read(currentUserProvider);
      expect(currentUser, isNull);
    });

    // -----------------------------------------------------------------------
    // Test 2 — Authenticated state → returns the user
    // -----------------------------------------------------------------------
    test('authenticated state → currentUser is the test user', () async {
      const authState = AsyncData<AuthSession>(
        AuthSession.authenticated(
          user: _testUser,
          accessToken: _fakeAccessToken,
        ),
      );

      final container = _makeContainer(authState);
      await container.read(authProvider.future);

      final currentUser = container.read(currentUserProvider);
      expect(currentUser, equals(_testUser));
    });

    // -----------------------------------------------------------------------
    // Test 3 — Unauthenticated state → null
    // -----------------------------------------------------------------------
    test('unauthenticated state → currentUser is null', () async {
      const authState = AsyncData<AuthSession>(AuthSession.unauthenticated());

      final container = _makeContainer(authState);
      await container.read(authProvider.future);

      final currentUser = container.read(currentUserProvider);
      expect(currentUser, isNull);
    });
  });

  // =========================================================================
  // isAuthenticatedProvider
  // =========================================================================

  group('isAuthenticatedProvider', () {
    // -----------------------------------------------------------------------
    // Test 4 — Loading auth state → false
    // -----------------------------------------------------------------------
    test('loading auth state → isAuthenticated is false', () async {
      final container = _makeContainer(const AsyncLoading<AuthSession>());
      container.read(authProvider);
      await Future<void>.delayed(Duration.zero);

      final isAuthenticated = container.read(isAuthenticatedProvider);
      expect(isAuthenticated, isFalse);
    });

    // -----------------------------------------------------------------------
    // Test 5 — Authenticated state → true
    // -----------------------------------------------------------------------
    test('authenticated state → isAuthenticated is true', () async {
      const authState = AsyncData<AuthSession>(
        AuthSession.authenticated(
          user: _testUser,
          accessToken: _fakeAccessToken,
        ),
      );

      final container = _makeContainer(authState);
      await container.read(authProvider.future);

      final isAuthenticated = container.read(isAuthenticatedProvider);
      expect(isAuthenticated, isTrue);
    });

    // -----------------------------------------------------------------------
    // Test 6 — Unauthenticated state → false
    // -----------------------------------------------------------------------
    test('unauthenticated state → isAuthenticated is false', () async {
      const authState = AsyncData<AuthSession>(AuthSession.unauthenticated());

      final container = _makeContainer(authState);
      await container.read(authProvider.future);

      final isAuthenticated = container.read(isAuthenticatedProvider);
      expect(isAuthenticated, isFalse);
    });
  });
}
