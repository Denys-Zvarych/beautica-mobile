// Tests for [scheduleEditableProvider] (lib/features/schedule/presentation/
// schedule_capability.dart).
//
// mobile-security MEDIUM, phase 309–311 track (2026-09-06): before this
// file, NOTHING drove `scheduleEditableProvider` through an `AsyncError` or
// a stale-value `AsyncLoading` — the provider used the lenient `.value` read,
// which Riverpod 3's automatic `copyWithPrevious` (every `Notifier`/
// `AsyncNotifier` state transition, `riverpod-3.2.1/.../element.dart:66`)
// can keep pointing at a PREVIOUS settled `Authenticated` session across a
// later `AsyncLoading`/`AsyncError`. `scheduleEditable` is the write-gate for
// every schedule-mutation affordance across `MasterScheduleScreen`,
// `WeeklyTemplateEditorScreen`, `DayHoursSheet` and `ApplyScheduleSheet`, so
// that leniency is a real hazard: it can keep granting edit access after the
// session it was granted for is no longer definitely valid.
//
// The fix routes through `authUserRoleSettledOrNull` (auth_notifier.dart) —
// the concrete-subtype gate (`session is AsyncData<AuthSession>`), not
// `.value`.
//
// Tests 14-16 in `auth_selectors_test.dart` establish the pattern this file
// reuses: drive a REAL Riverpod state transition via the notifier's own
// public `state =` setter (the exact mechanism production `AuthNotifier`
// uses) and let the framework's own internal `asyncTransition` apply
// `copyWithPrevious` — never hand-roll a fake `AsyncError`/`AsyncLoading`
// carrying a manually-attached previous value, since `copyWithPrevious` is
// `@internal` and not constructible directly outside the framework.
//
// Test matrix:
//   1. AsyncError carrying a copyWithPrevious-attached previous
//      Authenticated(independentMaster) → false (THE ONE THAT MATTERS —
//      verified RED against the pre-fix `.value` implementation, see the
//      task report).
//   2. AsyncLoading with the same stale previous value → false.
//   3. AsyncData(Authenticated(independentMaster)) → true (positive
//      counterpart — proves test 1 is not passing because everything
//      resolves false).
//   4. AsyncData(Authenticated(salonMaster)) → false.
//   5-6. AsyncData(Authenticated(salonOwner / salonAdmin)) → true — role
//      mapping preserved exactly per the provider's doc comment.
//   7. AsyncData(Authenticated(client)) → false.
//   8. Unauthenticated → false.

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_capability.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _fakeAccessToken = 'test-access-token';

User _userWith(UserRole role) => User(
  id: 'u-${role.name}',
  email: '${role.name}@beautica.ua',
  role: role,
  firstName: 'Тест',
  lastName: 'Юзер',
);

// ---------------------------------------------------------------------------
// AuthNotifier stubs
// ---------------------------------------------------------------------------

/// Resolves immediately to a fixed [AsyncValue<AuthSession>] — mirrors
/// `auth_selectors_test.dart`'s `_FixedAuthNotifier`.
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
}

/// Resolves immediately to an [Authenticated] session for [user].
class _AuthenticatedAs extends AuthNotifier {
  _AuthenticatedAs(this.user);
  final User user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: user, accessToken: _fakeAccessToken);
}

/// Settles to an [Authenticated] session for [user], then exposes
/// [forceError]/[forceLoading] to drive a REAL post-settle state transition
/// from the test body — same pattern as `auth_selectors_test.dart`'s
/// `_TransitionableAuthNotifier`, promoted here would be premature (single
/// consumer today); kept local per REUSE-FIRST's "additive, not speculative"
/// guidance.
class _TransitionableAuthNotifier extends AuthNotifier {
  _TransitionableAuthNotifier(this.user);
  final User user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: user, accessToken: _fakeAccessToken);

  /// The SAME `state = AsyncError(e, st)` shape production `AuthNotifier`
  /// uses (e.g. `auth_notifier.dart`'s `verifyEmail` catch block). Riverpod's
  /// own `asyncTransition` carries the previous settled `.value` FORWARD
  /// onto the resulting `AsyncError`.
  void forceError(Object error) {
    state = AsyncError<AuthSession>(error, StackTrace.current);
  }

  /// The mid-retry `AsyncLoading` shape: calling this immediately after
  /// [forceError] carries the PRIOR error's stale value forward too (same
  /// `asyncTransition` mechanism, via `onLoading`).
  void forceLoading() {
    state = const AsyncLoading<AuthSession>();
  }
}

// ---------------------------------------------------------------------------
// Container factories
// ---------------------------------------------------------------------------

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
  group('scheduleEditableProvider — copyWithPrevious hardening', () {
    // -------------------------------------------------------------------
    // Test 1 — THE ONE THAT MATTERS.
    // -------------------------------------------------------------------
    test('an Authenticated(independentMaster) session that TRANSITIONS to '
        'AsyncError resolves scheduleEditable=false — NOT the stale '
        'carried-forward role', () async {
      final notifier = _TransitionableAuthNotifier(
        _userWith(UserRole.independentMaster),
      );
      final container = _makeContainerFor(notifier);
      await container.read(authProvider.future);
      // Sanity: the settled session reads editable=true BEFORE the
      // transition — otherwise this test could pass for the wrong reason.
      expect(container.read(scheduleEditableProvider), isTrue);

      notifier.forceError(const NetworkFailure());
      final AsyncValue<AuthSession> afterError = container.read(authProvider);
      // Prove the trap is real before asserting the fix: Riverpod's own
      // copyWithPrevious carries the stale Authenticated value forward
      // onto the AsyncError.
      expect(afterError.hasError, isTrue);
      expect(
        afterError.value,
        isNotNull,
        reason:
            'sanity: if .value were null here, scheduleEditable would '
            'read false for a DIFFERENT reason (no stale value to leak) '
            'and this test would not be pinning the actual bug',
      );

      expect(
        container.read(scheduleEditableProvider),
        isFalse,
        reason:
            'must fail closed (read-only) on AsyncError even though '
            '.value still reports the stale '
            'Authenticated(independentMaster) session',
      );
    });

    // -------------------------------------------------------------------
    // Test 2 — the AsyncLoading(retrying) shape.
    // -------------------------------------------------------------------
    test('AsyncLoading carrying the same stale previous value resolves '
        'scheduleEditable=false', () async {
      final notifier = _TransitionableAuthNotifier(
        _userWith(UserRole.independentMaster),
      );
      final container = _makeContainerFor(notifier);
      await container.read(authProvider.future);

      notifier.forceError(const NetworkFailure());
      notifier.forceLoading();
      final AsyncValue<AuthSession> midRetry = container.read(authProvider);
      // Pin the shape itself, not just the outcome —
      // `project_asyncvalue_haserror_retrying_trap`: a test asserting only
      // `hasError`/`error` cannot distinguish this from a terminal
      // AsyncError.
      expect(midRetry, isA<AsyncLoading<AuthSession>>());
      expect(
        midRetry.value,
        isNotNull,
        reason: 'sanity: the stale value must actually be riding along',
      );

      expect(container.read(scheduleEditableProvider), isFalse);
    });
  });

  group('scheduleEditableProvider — settled-session role mapping', () {
    // -------------------------------------------------------------------
    // Test 3 — positive counterpart to test 1.
    // -------------------------------------------------------------------
    test('AsyncData(Authenticated(independentMaster)) → true', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.independentMaster)),
      );
      await container.read(authProvider.future);

      expect(container.read(scheduleEditableProvider), isTrue);
    });

    // -------------------------------------------------------------------
    // Test 4 — required negative case.
    // -------------------------------------------------------------------
    test('AsyncData(Authenticated(salonMaster)) → false', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.salonMaster)),
      );
      await container.read(authProvider.future);

      expect(container.read(scheduleEditableProvider), isFalse);
    });

    // -------------------------------------------------------------------
    // Tests 5-7 — remaining roles, preserving the exact mapping documented
    // on `scheduleEditable`'s doc comment.
    // -------------------------------------------------------------------
    for (final UserRole role in <UserRole>[
      UserRole.salonOwner,
      UserRole.salonAdmin,
    ]) {
      test('AsyncData(Authenticated(${role.name})) → true', () async {
        final container = _makeContainerFor(_AuthenticatedAs(_userWith(role)));
        await container.read(authProvider.future);

        expect(container.read(scheduleEditableProvider), isTrue);
      });
    }

    test('AsyncData(Authenticated(client)) → false', () async {
      final container = _makeContainerFor(
        _AuthenticatedAs(_userWith(UserRole.client)),
      );
      await container.read(authProvider.future);

      expect(container.read(scheduleEditableProvider), isFalse);
    });

    // -------------------------------------------------------------------
    // Test 8 — Unauthenticated.
    // -------------------------------------------------------------------
    test('Unauthenticated session → false', () async {
      final container = _makeContainer(
        const AsyncData<AuthSession>(AuthSession.unauthenticated()),
      );
      await container.read(authProvider.future);

      expect(container.read(scheduleEditableProvider), isFalse);
    });
  });
}
