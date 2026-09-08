// Tests for auth selector providers.
//
// Covers [currentUserProvider], [isAuthenticatedProvider], and
// [isSalonOwnerProvider] from lib/features/auth/presentation/auth_selectors
// .dart.
//
// All providers derive their value from [authProvider]; tests use a
// [ProviderContainer] with [authProvider] overridden by a fixed-state stub.
//
// Test matrix:
//   currentUserProvider:
//     1. Loading auth state → null
//     2. Authenticated state → returns the test user
//     3. Unauthenticated state → null
//   isAuthenticatedProvider:
//     4. Loading auth state → false
//     5. Authenticated state → true
//     6. Unauthenticated state → false
//   isSalonOwnerProvider (mobile-security MEDIUM, swipe-to-delete audit
//   2026-09) — the regression NOTHING exercised before this file's
//   additions:
//     7-11. Ordinary truth table — salonOwner → true, every other role
//           (client/salonAdmin/salonMaster/independentMaster) → false
//     12. Unauthenticated → false
//     13. Never-resolved AsyncLoading (no prior value) → false
//     14. THE ONE THAT MATTERS — an Authenticated(salonOwner) session that
//         TRANSITIONS to AsyncError → false, NOT the stale carried-forward
//         role. Riverpod 3.x's own `asyncTransition`/`copyWithPrevious`
//         (confirmed empirically against this repo's pinned `riverpod
//         3.1.0` — a REAL `state = AsyncError(...)` assignment on a settled
//         Authenticated notifier keeps `.value` pointing at the stale
//         session while `.hasError` flips true) is what the provider's own
//         `if (session.hasError) return false;` line guards against.
//     15. The `AsyncLoading` shape produced by a mid-retry cycle — runtime
//         type `AsyncLoading`, but `hasError == true` because the prior
//         failed attempt's error rides along (same `asyncTransition`
//         mechanism as #14, just via `onLoading` instead of `onError`) —
//         must ALSO fail closed.
//     16. A non-error refresh (AsyncLoading with NO error) carrying a prior
//         Authenticated(salonOwner) forward still yields TRUE — this
//         behaviour is deliberately preserved (every pre-promotion call
//         site never special-cased `isLoading`), so #14/#15's hardening
//         must not regress it.
//   isClientProvider (mobile-security LOW — regression-coverage asymmetry,
//   relocated delete-account row audit 2026-09-08) — byte-for-byte sibling
//   of isSalonOwnerProvider's group, one role swapped; same 10-test shape
//   (truth table, unauthenticated, unsettled AsyncLoading, and the three
//   copyWithPrevious hardening cases). See the `isClientProvider` group
//   below for details.
//
// Tests 14-16 do NOT call the `@internal` `AsyncValue.copyWithPrevious`
// directly (that API is package-internal and would trip
// `invalid_use_of_internal_member` under `flutter analyze --fatal-infos`).
// Instead they trigger a REAL Riverpod state transition via the notifier's
// own public `state =` setter — the exact same mechanism production
// `AuthNotifier` uses at `auth_notifier.dart:605` (`state = AsyncError(e,
// st);`) — and let the framework's own internal `asyncTransition` apply
// `copyWithPrevious` for us. This is not a simulation of the bug; it is the
// bug's real production trigger, driven from a test.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
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

User _userWith(UserRole role) => User(
  id: 'u-${role.name}',
  email: '${role.name}@beautica.ua',
  role: role,
  firstName: 'Тест',
  lastName: 'Юзер',
);

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

/// Resolves immediately to an [Authenticated] session for [user] — mirrors
/// the `_AuthenticatedAs` shape already used across
/// `delete_salon_flow_test.dart` / `settings_screen_delete_salon_row_test
/// .dart`.
class _AuthenticatedAs extends AuthNotifier {
  _AuthenticatedAs(this.user);
  final User user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: user, accessToken: _fakeAccessToken);
}

/// NEVER resolves — pins the fail-closed behaviour of an unsettled
/// `AsyncValue<AuthSession>` (no prior `.value`) deliberately, mirroring
/// `settings_screen_delete_salon_row_test.dart`'s own `_LoadingForeverNotifier`.
class _LoadingForeverNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() => Completer<AuthSession>().future;
}

/// Settles to an [Authenticated] session for [user], then exposes
/// [forceError]/[forceLoading] to drive a REAL post-settle state transition
/// from the test body — see this file's header for why this is the
/// production trigger for the `copyWithPrevious` carry-forward, not a
/// simulation of it.
class _TransitionableAuthNotifier extends AuthNotifier {
  _TransitionableAuthNotifier(this.user);
  final User user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: user, accessToken: _fakeAccessToken);

  /// The SAME `state = AsyncError(e, st)` shape production `AuthNotifier`
  /// uses at `auth_notifier.dart:605`. Riverpod's own `asyncTransition`
  /// (`onError`, `seamless: false` by default) carries the previous settled
  /// `.value` FORWARD onto the resulting `AsyncError` — confirmed
  /// empirically against this repo's pinned `riverpod 3.1.0`.
  void forceError(Object error) {
    state = AsyncError<AuthSession>(error, StackTrace.current);
  }

  /// The mid-retry `AsyncLoading` shape: calling this immediately after
  /// [forceError] carries the PRIOR error forward too (same
  /// `asyncTransition` mechanism, via `onLoading` instead of `onError`), so
  /// the resulting `AsyncLoading` reports `hasError == true` — the exact
  /// trap `project_asyncvalue_haserror_retrying_trap` documents. Calling it
  /// directly after a settled, error-free `AsyncData` instead produces an
  /// ordinary non-error refresh (`hasError == false`).
  void forceLoading() {
    state = const AsyncLoading<AuthSession>();
  }
}

// ---------------------------------------------------------------------------
// Container factories
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

/// Creates a [ProviderContainer] with [authProvider] overridden to the
/// EXACT [notifier] instance passed in, so the caller can invoke its own
/// methods (e.g. [_TransitionableAuthNotifier.forceError]) after the
/// container is built.
ProviderContainer _makeContainerFor(AuthNotifier notifier) {
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      authProvider.overrideWith(() => notifier),
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

  // =========================================================================
  // isSalonOwnerProvider (mobile-security MEDIUM, swipe-to-delete audit
  // 2026-09) — see this file's header for the full test matrix.
  // =========================================================================

  group('isSalonOwnerProvider', () {
    // -----------------------------------------------------------------------
    // Test 7 — ordinary truth table: SALON_OWNER → true
    // -----------------------------------------------------------------------
    test('SALON_OWNER session → true', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.salonOwner)),
      );
      await container.read(authProvider.future);

      expect(container.read(isSalonOwnerProvider), isTrue);
    });

    // -----------------------------------------------------------------------
    // Tests 8-11 — ordinary truth table: every other role → false
    // -----------------------------------------------------------------------
    for (final UserRole role in <UserRole>[
      UserRole.client,
      UserRole.salonAdmin,
      UserRole.salonMaster,
      UserRole.independentMaster,
    ]) {
      test('${role.name} session → false', () async {
        final container = _makeContainerFor(_AuthenticatedAs(_userWith(role)));
        await container.read(authProvider.future);

        expect(container.read(isSalonOwnerProvider), isFalse);
      });
    }

    // -----------------------------------------------------------------------
    // Test 12 — Unauthenticated → false
    // -----------------------------------------------------------------------
    test('unauthenticated session → false', () async {
      final container = _makeContainer(
        const AsyncData<AuthSession>(AuthSession.unauthenticated()),
      );
      await container.read(authProvider.future);

      expect(container.read(isSalonOwnerProvider), isFalse);
    });

    // -----------------------------------------------------------------------
    // Test 13 — never-resolved AsyncLoading (no prior value) → false
    // -----------------------------------------------------------------------
    test(
      'never-resolved AsyncLoading (no prior value) → false (fails closed)',
      () async {
        final container = _makeContainerFor(_LoadingForeverNotifier());
        container.read(authProvider); // trigger build, do not await
        await Future<void>.delayed(Duration.zero);

        expect(container.read(isSalonOwnerProvider), isFalse);
      },
    );

    // -----------------------------------------------------------------------
    // Tests 14-16 — Riverpod copyWithPrevious hardening. THIS is the
    // regression the promotion exists to fix — see this file's header.
    // -----------------------------------------------------------------------
    group('Riverpod copyWithPrevious hardening', () {
      // Test 14 — THE ONE THAT MATTERS.
      test(
        'an Authenticated(salonOwner) session that TRANSITIONS to AsyncError '
        'yields false — NOT the stale carried-forward role',
        () async {
          final notifier = _TransitionableAuthNotifier(
            _userWith(UserRole.salonOwner),
          );
          final container = _makeContainerFor(notifier);
          await container.read(authProvider.future);
          // Sanity: the settled owner session reads true BEFORE the
          // transition — otherwise this test could pass for the wrong
          // reason.
          expect(container.read(isSalonOwnerProvider), isTrue);

          notifier.forceError(const NetworkFailure());
          final AsyncValue<AuthSession> afterError = container.read(
            authProvider,
          );
          // Prove the trap is real BEFORE asserting the fix: Riverpod's own
          // copyWithPrevious carries the stale Authenticated value forward
          // onto the AsyncError.
          expect(afterError.hasError, isTrue);
          expect(
            afterError.value,
            isNotNull,
            reason:
                'sanity: if .value were null here, isSalonOwnerProvider '
                'would read false for a DIFFERENT reason (no stale value to '
                'leak) and this test would not be pinning the actual bug',
          );

          expect(
            container.read(isSalonOwnerProvider),
            isFalse,
            reason:
                'must fail closed on AsyncError even though .value still '
                'reports the stale Authenticated(salonOwner) session',
          );
        },
      );

      // Test 15 — the AsyncLoading(retrying) shape.
      test('AsyncLoading mid-retry (hasError true, runtime type AsyncLoading) '
          'yields false (fails closed)', () async {
        final notifier = _TransitionableAuthNotifier(
          _userWith(UserRole.salonOwner),
        );
        final container = _makeContainerFor(notifier);
        await container.read(authProvider.future);

        notifier.forceError(const NetworkFailure());
        notifier.forceLoading();
        final AsyncValue<AuthSession> midRetry = container.read(authProvider);
        // Pin the shape itself, not just the outcome — this is
        // `project_asyncvalue_haserror_retrying_trap`: a test asserting
        // only `hasError`/`error` cannot distinguish this from a terminal
        // AsyncError.
        expect(midRetry, isA<AsyncLoading<AuthSession>>());
        expect(
          midRetry.hasError,
          isTrue,
          reason:
              'AsyncLoading(retrying) reports hasError == true even '
              'though the runtime type is AsyncLoading, not AsyncError',
        );

        expect(container.read(isSalonOwnerProvider), isFalse);
      });

      // Test 16 — the deliberately-preserved non-error refresh.
      test('a non-error refresh (AsyncLoading with NO error) carrying a prior '
          'Authenticated(salonOwner) forward still yields true', () async {
        final notifier = _TransitionableAuthNotifier(
          _userWith(UserRole.salonOwner),
        );
        final container = _makeContainerFor(notifier);
        await container.read(authProvider.future);

        notifier.forceLoading();
        final AsyncValue<AuthSession> refreshing = container.read(authProvider);
        expect(refreshing.hasError, isFalse);

        expect(
          container.read(isSalonOwnerProvider),
          isTrue,
          reason:
              'a loading refresh with no error must not regress every '
              'pre-promotion call site — none of them special-cased '
              'isLoading',
        );
      });
    });
  });

  // =========================================================================
  // isClientProvider (mobile-security LOW — regression-coverage asymmetry,
  // relocated delete-account row audit 2026-09-08) — byte-for-byte sibling
  // of isSalonOwnerProvider above: same hardened idiom
  // (`if (session.hasError) return false;` before reading `.value`), one
  // role swapped. Mirrors that group's test matrix exactly:
  //   1. CLIENT session → true
  //   2-5. every other role (salonOwner/salonAdmin/salonMaster/
  //        independentMaster) → false
  //   6. Unauthenticated → false
  //   7. Never-resolved AsyncLoading (no prior value) → false
  //   8. THE ONE THAT MATTERS — an Authenticated(client) session that
  //      TRANSITIONS to AsyncError → false, NOT the stale carried-forward
  //      role (real `state = AsyncError(...)` transition, same mechanism as
  //      isSalonOwnerProvider's test 14 above — not a simulation).
  //   9. AsyncLoading mid-retry (hasError true, runtime type AsyncLoading)
  //      → false.
  //   10. Non-error refresh (AsyncLoading with no error) carrying a prior
  //       Authenticated(client) forward → still true (preserved, not
  //       regressed by the hardening).
  // =========================================================================

  group('isClientProvider', () {
    // -----------------------------------------------------------------------
    // Test 1 — ordinary truth table: CLIENT → true
    // -----------------------------------------------------------------------
    test('CLIENT session → true', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.client)),
      );
      await container.read(authProvider.future);

      expect(container.read(isClientProvider), isTrue);
    });

    // -----------------------------------------------------------------------
    // Tests 2-5 — ordinary truth table: every other role → false
    // -----------------------------------------------------------------------
    for (final UserRole role in <UserRole>[
      UserRole.salonOwner,
      UserRole.salonAdmin,
      UserRole.salonMaster,
      UserRole.independentMaster,
    ]) {
      test('${role.name} session → false', () async {
        final container = _makeContainerFor(_AuthenticatedAs(_userWith(role)));
        await container.read(authProvider.future);

        expect(container.read(isClientProvider), isFalse);
      });
    }

    // -----------------------------------------------------------------------
    // Test 6 — Unauthenticated → false
    // -----------------------------------------------------------------------
    test('unauthenticated session → false', () async {
      final container = _makeContainer(
        const AsyncData<AuthSession>(AuthSession.unauthenticated()),
      );
      await container.read(authProvider.future);

      expect(container.read(isClientProvider), isFalse);
    });

    // -----------------------------------------------------------------------
    // Test 7 — never-resolved AsyncLoading (no prior value) → false
    // -----------------------------------------------------------------------
    test(
      'never-resolved AsyncLoading (no prior value) → false (fails closed)',
      () async {
        final container = _makeContainerFor(_LoadingForeverNotifier());
        container.read(authProvider); // trigger build, do not await
        await Future<void>.delayed(Duration.zero);

        expect(container.read(isClientProvider), isFalse);
      },
    );

    // -----------------------------------------------------------------------
    // Tests 8-10 — Riverpod copyWithPrevious hardening.
    // -----------------------------------------------------------------------
    group('Riverpod copyWithPrevious hardening', () {
      // Test 8 — THE ONE THAT MATTERS.
      test('an Authenticated(client) session that TRANSITIONS to AsyncError '
          'yields false — NOT the stale carried-forward role', () async {
        final notifier = _TransitionableAuthNotifier(
          _userWith(UserRole.client),
        );
        final container = _makeContainerFor(notifier);
        await container.read(authProvider.future);
        // Sanity: the settled client session reads true BEFORE the
        // transition — otherwise this test could pass for the wrong
        // reason.
        expect(container.read(isClientProvider), isTrue);

        notifier.forceError(const NetworkFailure());
        final AsyncValue<AuthSession> afterError = container.read(authProvider);
        // Prove the trap is real BEFORE asserting the fix: Riverpod's own
        // copyWithPrevious carries the stale Authenticated value forward
        // onto the AsyncError.
        expect(afterError.hasError, isTrue);
        expect(
          afterError.value,
          isNotNull,
          reason:
              'sanity: if .value were null here, isClientProvider would '
              'read false for a DIFFERENT reason (no stale value to leak) '
              'and this test would not be pinning the actual bug',
        );

        expect(
          container.read(isClientProvider),
          isFalse,
          reason:
              'must fail closed on AsyncError even though .value still '
              'reports the stale Authenticated(client) session',
        );
      });

      // Test 9 — the AsyncLoading(retrying) shape.
      test('AsyncLoading mid-retry (hasError true, runtime type AsyncLoading) '
          'yields false (fails closed)', () async {
        final notifier = _TransitionableAuthNotifier(
          _userWith(UserRole.client),
        );
        final container = _makeContainerFor(notifier);
        await container.read(authProvider.future);

        notifier.forceError(const NetworkFailure());
        notifier.forceLoading();
        final AsyncValue<AuthSession> midRetry = container.read(authProvider);
        // Pin the shape itself, not just the outcome — see
        // `project_asyncvalue_haserror_retrying_trap`: a test asserting
        // only `hasError`/`error` cannot distinguish this from a terminal
        // AsyncError.
        expect(midRetry, isA<AsyncLoading<AuthSession>>());
        expect(
          midRetry.hasError,
          isTrue,
          reason:
              'AsyncLoading(retrying) reports hasError == true even '
              'though the runtime type is AsyncLoading, not AsyncError',
        );

        expect(container.read(isClientProvider), isFalse);
      });

      // Test 10 — the deliberately-preserved non-error refresh.
      test('a non-error refresh (AsyncLoading with NO error) carrying a prior '
          'Authenticated(client) forward still yields true', () async {
        final notifier = _TransitionableAuthNotifier(
          _userWith(UserRole.client),
        );
        final container = _makeContainerFor(notifier);
        await container.read(authProvider.future);

        notifier.forceLoading();
        final AsyncValue<AuthSession> refreshing = container.read(authProvider);
        expect(refreshing.hasError, isFalse);

        expect(
          container.read(isClientProvider),
          isTrue,
          reason:
              'a loading refresh with no error must not regress every '
              'pre-promotion call site — none of them special-cased '
              'isLoading',
        );
      });
    });
  });

  // =========================================================================
  // canSelfDeleteAccountProvider (mobile-qa — staff/master delete-account
  // widening audit, 2026-09-08) — the selector `SettingsScreen
  // ._showDeleteAccountRow` ACTUALLY watches for the widened gate. Written
  // because neither `isSalonOwnerProvider`'s nor `isClientProvider`'s
  // copyWithPrevious hardening group covers this provider — it is a
  // separate `@riverpod` function, not a reuse of either — and the
  // widget-tier truth table in `settings_screen_delete_account_row_test
  // .dart` only exercises unauthenticated / never-resolved-loading /
  // salonOwner, never the settled-then-errored transition. Same idiom
  // (`if (session.hasError) return false;` before `.value`), same hazard:
  // a stale `Authenticated` value surviving a `copyWithPrevious`-carried
  // `AsyncError` would leave a DESTRUCTIVE, IRREVERSIBLE action ("Видалити
  // акаунт") visible for a session the app itself believes has failed.
  //
  // Test matrix:
  //   1-4. Ordinary truth table — client / salonAdmin / salonMaster /
  //        independentMaster → true.
  //   5. salonOwner → false (server-side 403; already covered elsewhere,
  //      repeated here for this provider directly).
  //   6. Unauthenticated → false.
  //   7. Never-resolved AsyncLoading (no prior value) → false.
  //   8-10. Riverpod copyWithPrevious hardening (independentMaster — the
  //      role this branch newly grants access to, not one already proven
  //      by a pre-existing selector): settled-then-AsyncError → false (THE
  //      ONE THAT MATTERS), AsyncLoading mid-retry (hasError true) →
  //      false, non-error refresh → still true (preserved).
  group('canSelfDeleteAccountProvider', () {
    // -----------------------------------------------------------------------
    // Tests 1-4 — ordinary truth table: every self-delete-eligible role
    // → true.
    // -----------------------------------------------------------------------
    for (final UserRole role in <UserRole>[
      UserRole.client,
      UserRole.salonAdmin,
      UserRole.salonMaster,
      UserRole.independentMaster,
    ]) {
      test('${role.name} session → true', () async {
        final container = _makeContainerFor(_AuthenticatedAs(_userWith(role)));
        await container.read(authProvider.future);

        expect(container.read(canSelfDeleteAccountProvider), isTrue);
      });
    }

    // -----------------------------------------------------------------------
    // Test 5 — SALON_OWNER → false (excluded; owns a salon with staff
    // beneath them; 403 server-side).
    // -----------------------------------------------------------------------
    test('SALON_OWNER session → false', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.salonOwner)),
      );
      await container.read(authProvider.future);

      expect(container.read(canSelfDeleteAccountProvider), isFalse);
    });

    // -----------------------------------------------------------------------
    // Test 6 — Unauthenticated → false
    // -----------------------------------------------------------------------
    test('unauthenticated session → false', () async {
      final container = _makeContainer(
        const AsyncData<AuthSession>(AuthSession.unauthenticated()),
      );
      await container.read(authProvider.future);

      expect(container.read(canSelfDeleteAccountProvider), isFalse);
    });

    // -----------------------------------------------------------------------
    // Test 7 — never-resolved AsyncLoading (no prior value) → false
    // -----------------------------------------------------------------------
    test(
      'never-resolved AsyncLoading (no prior value) → false (fails closed)',
      () async {
        final container = _makeContainerFor(_LoadingForeverNotifier());
        container.read(authProvider); // trigger build, do not await
        await Future<void>.delayed(Duration.zero);

        expect(container.read(canSelfDeleteAccountProvider), isFalse);
      },
    );

    // -----------------------------------------------------------------------
    // Tests 8-10 — Riverpod copyWithPrevious hardening, driven via
    // independentMaster — the role this branch's widening newly grants
    // access to.
    // -----------------------------------------------------------------------
    group('Riverpod copyWithPrevious hardening', () {
      // Test 8 — THE ONE THAT MATTERS.
      test(
        'an Authenticated(independentMaster) session that TRANSITIONS to '
        'AsyncError yields false — NOT the stale carried-forward role',
        () async {
          final notifier = _TransitionableAuthNotifier(
            _userWith(UserRole.independentMaster),
          );
          final container = _makeContainerFor(notifier);
          await container.read(authProvider.future);
          // Sanity: the settled master session reads true BEFORE the
          // transition — otherwise this test could pass for the wrong
          // reason.
          expect(container.read(canSelfDeleteAccountProvider), isTrue);

          notifier.forceError(const NetworkFailure());
          final AsyncValue<AuthSession> afterError = container.read(
            authProvider,
          );
          // Prove the trap is real BEFORE asserting the fix: Riverpod's own
          // copyWithPrevious carries the stale Authenticated value forward
          // onto the AsyncError.
          expect(afterError.hasError, isTrue);
          expect(
            afterError.value,
            isNotNull,
            reason:
                'sanity: if .value were null here, '
                'canSelfDeleteAccountProvider would read false for a '
                'DIFFERENT reason (no stale value to leak) and this test '
                'would not be pinning the actual bug',
          );

          expect(
            container.read(canSelfDeleteAccountProvider),
            isFalse,
            reason:
                'must fail closed on AsyncError even though .value still '
                'reports the stale Authenticated(independentMaster) '
                'session — otherwise a failed session would still see the '
                'destructive, irreversible «Видалити акаунт» row',
          );
        },
      );

      // Test 9 — the AsyncLoading(retrying) shape.
      test('AsyncLoading mid-retry (hasError true, runtime type AsyncLoading) '
          'yields false (fails closed)', () async {
        final notifier = _TransitionableAuthNotifier(
          _userWith(UserRole.independentMaster),
        );
        final container = _makeContainerFor(notifier);
        await container.read(authProvider.future);

        notifier.forceError(const NetworkFailure());
        notifier.forceLoading();
        final AsyncValue<AuthSession> midRetry = container.read(authProvider);
        // Pin the shape itself, not just the outcome —
        // `project_asyncvalue_haserror_retrying_trap`: a test asserting
        // only `hasError`/`error` cannot distinguish this from a terminal
        // AsyncError.
        expect(midRetry, isA<AsyncLoading<AuthSession>>());
        expect(
          midRetry.hasError,
          isTrue,
          reason:
              'AsyncLoading(retrying) reports hasError == true even '
              'though the runtime type is AsyncLoading, not AsyncError',
        );

        expect(container.read(canSelfDeleteAccountProvider), isFalse);
      });

      // Test 10 — the deliberately-preserved non-error refresh.
      test('a non-error refresh (AsyncLoading with NO error) carrying a '
          'prior Authenticated(independentMaster) forward still yields '
          'true', () async {
        final notifier = _TransitionableAuthNotifier(
          _userWith(UserRole.independentMaster),
        );
        final container = _makeContainerFor(notifier);
        await container.read(authProvider.future);

        notifier.forceLoading();
        final AsyncValue<AuthSession> refreshing = container.read(authProvider);
        expect(refreshing.hasError, isFalse);

        expect(
          container.read(canSelfDeleteAccountProvider),
          isTrue,
          reason:
              'a loading refresh with no error must not regress every '
              'pre-promotion call site — none of them special-cased '
              'isLoading',
        );
      });
    });
  });
}
