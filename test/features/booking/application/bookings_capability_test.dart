// Tests for [bookingTransitionsEnabledProvider] and
// [bookingCreationEnabledProvider] (lib/features/booking/application/
// bookings_capability.dart) — the phase 328 read-only gate for the shared
// «Записи» surfaces.
//
// WHY THIS FILE EXISTS (mobile-qa branch audit, 2026-09-15). The track that
// introduced these two providers shipped with NO test file for them at all,
// and every widget test that touched the gated surfaces exercised only the
// PERMISSIVE arm (an `INDEPENDENT_MASTER` session). The behaviour the whole
// track exists for — an invited `SALON_MASTER` seeing NO write affordance —
// was unverified in both directions. Two distinct gaps:
//
//   GAP 1 — the negative case. Nothing anywhere seeded `salonMaster` and
//   asserted `false`. Group 1 below is that matrix, for BOTH providers (they
//   are deliberately separate providers with an identical mapping today —
//   see the source file header — so a test that covers only one would miss a
//   divergence introduced by a future edit to the other).
//
//   GAP 2 — the STRICT-selector choice was unenforced (mobile-security LOW).
//   Both providers read `authProvider.select(authUserRoleSettledOrNull)` —
//   the concrete-`AsyncData`-subtype gate. A future "simplify" swapping it
//   for the lenient `authUserRoleOrNull` (`.value` unwrap) would COMPILE,
//   behave identically for every settled session, and stay green under
//   Group 1's whole matrix — silently restoring the phase-309 MEDIUM, because
//   Riverpod 3 auto-applies `copyWithPrevious` to every `AsyncNotifier` state
//   transition (`riverpod-3.2.1/.../element.dart:66`), so a stale settled
//   `Authenticated` rides along attached to a later `AsyncLoading`/
//   `AsyncError` and `.value` still returns it. Group 2 is the ONLY assertion
//   in the repo that goes red on that swap: it drives the real transition and
//   requires `false` while `.value` still reports the master's role.
//
// This file mirrors the shape and rigour of its sibling
// `test/features/schedule/presentation/schedule_capability_test.dart`, which
// pins the same hardening for `scheduleEditableProvider`.
//
// Test matrix:
//   GROUP 1 — settled-session role mapping (both providers, each role):
//     1. AsyncData(Authenticated(independentMaster)) → true / true.
//     2. AsyncData(Authenticated(salonOwner))        → true / true.
//     3. AsyncData(Authenticated(salonAdmin))        → true / true.
//     4. AsyncData(Authenticated(salonMaster))       → false / false  ← the
//        case the entire track exists for.
//     5. AsyncData(Authenticated(client))            → false / false.
//     6. AsyncData(Unauthenticated)                  → false / false.
//   GROUP 2 — strict-selector (copyWithPrevious) hardening:
//     7. AsyncLoading carrying a copyWithPrevious-attached previous
//        AsyncData(Authenticated(independentMaster)) → false / false.
//     8. The AsyncError shape of the same → false / false.
//     9. A SEAMLESS REFRESH of a settled session — `container.refresh(
//        authProvider)` — which in riverpod 3.2.1 does NOT produce an
//        `AsyncLoading` at all: `AsyncLoading.copyWithPrevious(previous,
//        isRefresh: true)` over a `data` previous returns
//        `AsyncData._(previousValue!, loading: _loading)`
//        (`async_value.dart:789-796`), i.e. a real `AsyncData` carrying the
//        STALE `Authenticated` with `isRefreshing == true`. Cases 7 and 8
//        cannot see this shape — it passes the `is AsyncData<AuthSession>`
//        subtype gate — so the write gate must ALSO fence on `isLoading`.
//        → false / false.

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_capability.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _kAccessToken = 'test-access-token';

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
/// `schedule_capability_test.dart`'s `_FixedAuthNotifier`. Only ever handed a
/// settled `AsyncData` (an `AsyncLoading`/`AsyncError` assigned inside
/// `build` would be clobbered by the returned value settling the state right
/// after); Group 2 uses [_TransitionableAuthNotifier] instead.
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
      AuthSession.authenticated(user: user, accessToken: _kAccessToken);
}

/// Settles to an [Authenticated] session for [user], then exposes
/// [forceLoading]/[forceError] so the test body can drive a REAL post-settle
/// state transition — the production mechanism that attaches the stale
/// previous value (`asyncTransition` → `copyWithPrevious`), rather than a
/// hand-assembled `AsyncValue` that might not match what Riverpod actually
/// produces. Same idiom as `schedule_capability_test.dart`'s stub of the same
/// name.
class _TransitionableAuthNotifier extends AuthNotifier {
  _TransitionableAuthNotifier(this.user);
  final User user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: user, accessToken: _kAccessToken);

  void forceLoading() {
    state = const AsyncLoading<AuthSession>();
  }

  void forceError(Object error) {
    state = AsyncError<AuthSession>(error, StackTrace.current);
  }
}

// ---------------------------------------------------------------------------
// Container factory
// ---------------------------------------------------------------------------

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

/// Reads BOTH capabilities as a record, so every case asserts the pair — the
/// two providers are separate on purpose and must be pinned separately.
({bool transitions, bool creation}) _capabilities(ProviderContainer c) => (
  transitions: c.read(bookingTransitionsEnabledProvider),
  creation: c.read(bookingCreationEnabledProvider),
);

void main() {
  group('bookings capability — settled-session role mapping', () {
    Future<void> expectRoleResolves(
      UserRole role, {
      required bool expected,
    }) async {
      final container = _makeContainerFor(_AuthenticatedAs(_userWith(role)));
      await container.read(authProvider.future);

      expect(
        _capabilities(container),
        (transitions: expected, creation: expected),
        reason:
            'Authenticated(${role.name}) must resolve both booking '
            'capabilities to $expected',
      );
    }

    test('INDEPENDENT_MASTER → transitions + creation enabled', () async {
      await expectRoleResolves(UserRole.independentMaster, expected: true);
    });

    test('SALON_OWNER → transitions + creation enabled', () async {
      await expectRoleResolves(UserRole.salonOwner, expected: true);
    });

    test('SALON_ADMIN → transitions + creation enabled', () async {
      await expectRoleResolves(UserRole.salonAdmin, expected: true);
    });

    // -----------------------------------------------------------------------
    // THE CASE THE TRACK EXISTS FOR (gap 1). Before this test, nothing in the
    // repo seeded `salonMaster` against these providers at all.
    // -----------------------------------------------------------------------
    test('SALON_MASTER (invited, READ-ONLY) → transitions + creation BOTH '
        'disabled', () async {
      await expectRoleResolves(UserRole.salonMaster, expected: false);
    });

    test('CLIENT → transitions + creation disabled', () async {
      await expectRoleResolves(UserRole.client, expected: false);
    });

    test('an Unauthenticated (settled) session → both disabled', () async {
      final container = _makeContainerFor(
        _FixedAuthNotifier(
          const AsyncData<AuthSession>(AuthSession.unauthenticated()),
        ),
      );
      await container.read(authProvider.future);

      expect(_capabilities(container), (transitions: false, creation: false));
    });
  });

  group('bookings capability — strict-selector (copyWithPrevious) '
      'hardening', () {
    // -----------------------------------------------------------------------
    // GAP 2 — THE ONE THAT MATTERS. This is the only assertion in the repo
    // that distinguishes `authUserRoleSettledOrNull` from `authUserRoleOrNull`
    // at these two call sites: every settled session reads identically through
    // either selector, so Group 1 cannot tell them apart.
    // -----------------------------------------------------------------------
    test('AsyncLoading carrying a copyWithPrevious-attached previous '
        'AsyncData(Authenticated(independentMaster)) → both capabilities '
        'read false (NOT the stale carried-forward role)', () async {
      final notifier = _TransitionableAuthNotifier(
        _userWith(UserRole.independentMaster),
      );
      final container = _makeContainerFor(notifier);
      await container.read(authProvider.future);
      // Sanity: the SETTLED session reads enabled before the transition —
      // otherwise this test could go green for the wrong reason (e.g. a
      // fixture whose role never granted anything in the first place).
      expect(_capabilities(container), (transitions: true, creation: true));

      notifier.forceLoading();
      final AsyncValue<AuthSession> midFlight = container.read(authProvider);

      // Pin the SHAPE, not just the outcome
      // (`project_asyncvalue_haserror_retrying_trap`): assert the concrete
      // `AsyncLoading` subtype AND that the stale value is genuinely riding
      // along. If `.value` were null here, the lenient-selector mutation
      // this test exists to catch would ALSO read `false` and the test
      // would be pinning nothing.
      expect(midFlight, isA<AsyncLoading<AuthSession>>());
      expect(
        midFlight.value,
        isNotNull,
        reason:
            'sanity: Riverpod must actually be carrying the previous '
            'settled Authenticated session forward onto this AsyncLoading '
            '— that carried value IS the hazard under test',
      );
      expect(
        (midFlight.value! as Authenticated).user.role,
        UserRole.independentMaster,
        reason:
            'sanity: the stale value carries a role that WOULD grant both '
            'capabilities if read leniently via `.value`',
      );

      expect(
        _capabilities(container),
        (transitions: false, creation: false),
        reason:
            'both providers are WRITE-GATES and must fail closed the '
            'instant the session is not a settled AsyncData — even though '
            '`.value` still reports the stale '
            'Authenticated(independentMaster). This is the assertion that '
            'goes red if `authUserRoleSettledOrNull` is ever "simplified" '
            'to `authUserRoleOrNull`.',
      );
    });

    test('AsyncError carrying the same stale previous value → both '
        'capabilities read false', () async {
      final notifier = _TransitionableAuthNotifier(
        _userWith(UserRole.independentMaster),
      );
      final container = _makeContainerFor(notifier);
      await container.read(authProvider.future);
      expect(_capabilities(container), (transitions: true, creation: true));

      notifier.forceError(const NetworkFailure());
      final AsyncValue<AuthSession> afterError = container.read(authProvider);
      expect(afterError, isA<AsyncError<AuthSession>>());
      expect(
        afterError.value,
        isNotNull,
        reason: 'sanity: the stale session must actually be riding along',
      );

      expect(_capabilities(container), (transitions: false, creation: false));
    });

    // -----------------------------------------------------------------------
    // THE SHAPE CASES 7 AND 8 CANNOT REACH (mobile-security MEDIUM,
    // 2026-09-15). A SEAMLESS refresh — `container.refresh(authProvider)` /
    // `ref.invalidate(authProvider)` from an already-settled session — never
    // materialises an `AsyncLoading` for a subscriber to observe. In riverpod
    // 3.2.1 the element computes `seamless: !ref.isReload` (`element.dart:50`,
    // fed by `isReload: _didChangeDependency` at `:572`) and hands it to
    // `AsyncLoading.copyWithPrevious(previous, isRefresh: true)`, whose `data`
    // arm returns `AsyncData._(previousValue!, loading: _loading)`
    // (`async_value.dart:789-796`). The result is a genuine
    // `AsyncData<AuthSession>` that still carries the stale `Authenticated`
    // and reports `isRefreshing == true`.
    //
    // A gate written as `session is AsyncData<AuthSession>` therefore ADMITS
    // this window and keeps granting write affordances off a session that is
    // being re-fetched. No call site reaches it today (both
    // `ref.invalidate(authProvider)` sites sit on a non-`Authenticated` arm),
    // but the selector's own doc promises the opposite, so the first
    // pull-to-refresh on the session would reopen the bypass silently. This
    // test pins the promise, not the current call graph.
    test('a SEAMLESS refresh of a settled session — an AsyncData that is '
        'still isRefreshing over the stale Authenticated(independentMaster) '
        '— reads false on both capabilities', () async {
      final notifier = _TransitionableAuthNotifier(
        _userWith(UserRole.independentMaster),
      );
      final container = _makeContainerFor(notifier);
      await container.read(authProvider.future);
      // Sanity: enabled BEFORE the refresh, so a green result cannot come
      // from a fixture that never granted anything.
      expect(_capabilities(container), (transitions: true, creation: true));

      final AsyncValue<AuthSession> midRefresh = container.refresh(
        authProvider,
      );

      // Pin the SHAPE explicitly. If a future riverpod version changes
      // `copyWithPrevious` so that a seamless refresh emits an `AsyncLoading`
      // (or drops the carried value), these three preconditions go red and
      // tell us the hazard moved — rather than letting the final booleans
      // pass for the wrong reason.
      expect(
        midRefresh,
        isA<AsyncData<AuthSession>>(),
        reason:
            'precondition: a seamless refresh over a data previous produces '
            'AsyncData, NOT AsyncLoading (async_value.dart:789-796) — that '
            'is precisely why the `is AsyncData` subtype gate is not enough',
      );
      expect(
        midRefresh.isRefreshing,
        isTrue,
        reason:
            'precondition: the session is genuinely in flight — `isLoading` '
            'is the only signal distinguishing this from a settled AsyncData',
      );
      expect(
        midRefresh.value,
        isA<Authenticated>().having(
          (Authenticated a) => a.user.role,
          'user.role',
          UserRole.independentMaster,
        ),
        reason:
            'precondition: the STALE authenticated session is riding along — '
            'that carried role WOULD grant both capabilities if the gate '
            'stopped at the AsyncData subtype check',
      );

      expect(
        _capabilities(container),
        (transitions: false, creation: false),
        reason:
            'both providers are WRITE-GATES: an in-flight re-fetch of the '
            'session is not a settled session, so they must fail closed for '
            'the whole refresh window even though the value is non-null and '
            'the subtype is AsyncData. Goes red if `!session.isLoading` is '
            'dropped from `authUserRoleSettledOrNull`.',
      );
    });
  });
}
