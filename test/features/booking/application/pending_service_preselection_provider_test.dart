// Unit tests for [PendingServicePreselectionController] — the one-shot,
// targetId-guarded, auth-cleared holder that carries the search service filter
// into the booking flow.
//
// Pure-Dart provider units: no widget tree. Each test builds a FRESH
// [ProviderContainer] (disposed in addTearDown) so the keepAlive controller
// state never leaks between cases. The provider `ref.watch`es [authProvider]
// (to self-clear on a session flip), so the container stubs the auth graph with
// a mutable [AuthNotifier] — mirroring
// `search_filters_controller_test.dart`'s `_make` harness — which also lets the
// auth-flip reset be exercised deterministically.
//
// Contract under test (see pending_service_preselection_provider.dart):
//   • set        — records the payload; copies the caller's sets so a later
//                  mutation of the caller's filter set can never rewrite it.
//   • consumeFor — returns the payload IFF its targetId matches, NULLING it in
//                  the same call (strict one-shot). A non-matching target
//                  returns null and leaves the payload intact.
//   • clear      — resets to null unconditionally.
//   • auth flip  — Unauthenticated rebuilds the controller back to null.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/pending_service_preselection_provider.dart';
import 'package:beautica_mobile/features/booking/domain/pending_service_preselection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Auth stub (mirrors search_filters_controller_test.dart)
// ---------------------------------------------------------------------------

const _testUser = User(
  id: 'u-client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Дмитро',
  lastName: 'Клієнт',
);

const _authenticated = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _testUser, accessToken: 'tok'),
);

const _unauthenticated = AsyncData<AuthSession>(AuthSession.unauthenticated());

/// A mutable [AuthNotifier] whose settled session a test can flip AFTER build()
/// so a watcher (the preselection controller) rebuilds — exercising the
/// session-flip self-clear.
class _MutableAuthNotifier extends AuthNotifier {
  _MutableAuthNotifier(this._initial);

  final AsyncValue<AuthSession> _initial;

  @override
  Future<AuthSession> build() async {
    state = _initial;
    return _initial.value ?? const AuthSession.unauthenticated();
  }

  void emit(AsyncValue<AuthSession> next) => state = next;
}

({ProviderContainer container, _MutableAuthNotifier auth}) _make({
  AsyncValue<AuthSession> auth = _authenticated,
}) {
  final notifier = _MutableAuthNotifier(auth);
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: <Object>[
      authProvider.overrideWith(() => notifier),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    ].cast(),
  );
  addTearDown(container.dispose);
  return (container: container, auth: notifier);
}

PendingServicePreselectionController _controller(ProviderContainer c) =>
    c.read(pendingServicePreselectionControllerProvider.notifier);

PendingServicePreselection? _state(ProviderContainer c) =>
    c.read(pendingServicePreselectionControllerProvider);

void main() {
  group('initial state', () {
    test('starts null (nothing pending)', () {
      final c = _make().container;

      expect(_state(c), isNull);
    });
  });

  group('set + consumeFor (one-shot, targetId-guarded)', () {
    test('consumeFor returns the payload for a matching targetId', () {
      final c = _make().container;

      _controller(c).set(
        targetId: 'master-1',
        serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
        serviceTypeLabels: <String>{'Класичний манікюр'},
      );

      final PendingServicePreselection? consumed = _controller(
        c,
      ).consumeFor('master-1');

      expect(consumed, isNotNull);
      expect(consumed!.targetId, 'master-1');
      expect(consumed.serviceTypeSlugs, <String>{'CLASSIC_MANICURE'});
      expect(consumed.serviceTypeLabels, <String>{'Класичний манікюр'});
    });

    test('consume is one-shot — a matching consume NULLS the state, and a '
        'second consume for the same target returns null', () {
      final c = _make().container;
      _controller(c).set(
        targetId: 'master-1',
        serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
        serviceTypeLabels: const <String>{},
      );

      // First consume drains it …
      expect(_controller(c).consumeFor('master-1'), isNotNull);
      expect(
        _state(c),
        isNull,
        reason:
            'a matching consume must null the stored payload in the '
            'same call',
      );
      // … so re-entering the booking flow for the SAME master gets nothing.
      expect(
        _controller(c).consumeFor('master-1'),
        isNull,
        reason: 're-entry must not re-preselect (strict one-shot)',
      );
    });

    test('consumeFor returns null for a NON-matching targetId and leaves the '
        'payload intact for the real target', () {
      final c = _make().container;
      _controller(c).set(
        targetId: 'salon-xyz',
        serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
        serviceTypeLabels: const <String>{},
      );

      // A different provider's booking screen must NOT drain this payload.
      expect(_controller(c).consumeFor('master-1'), isNull);
      expect(
        _state(c),
        isNotNull,
        reason: 'a target mismatch must leave the pending payload intact',
      );

      // The intended target still consumes it.
      final PendingServicePreselection? consumed = _controller(
        c,
      ).consumeFor('salon-xyz');
      expect(consumed, isNotNull);
      expect(consumed!.targetId, 'salon-xyz');
    });
  });

  group('set — immutability of the stored payload', () {
    test('mutating the caller\'s slug/label sets after set() does NOT rewrite '
        'the stored payload', () {
      final c = _make().container;
      final Set<String> callerSlugs = <String>{'CLASSIC_MANICURE'};
      final Set<String> callerLabels = <String>{'Класичний манікюр'};

      _controller(c).set(
        targetId: 'master-1',
        serviceTypeSlugs: callerSlugs,
        serviceTypeLabels: callerLabels,
      );

      // The caller keeps mutating its own filter set afterward …
      callerSlugs.add('GEL_MANICURE');
      callerLabels.add('Манікюр гель-лак');

      // … but the stored payload was copied (Set.unmodifiable), so it is
      // unchanged — no leaked reference into the pending booking pre-selection.
      final PendingServicePreselection? consumed = _controller(
        c,
      ).consumeFor('master-1');
      expect(consumed!.serviceTypeSlugs, <String>{'CLASSIC_MANICURE'});
      expect(consumed.serviceTypeLabels, <String>{'Класичний манікюр'});
    });
  });

  group('clear', () {
    test('clear() empties a pending payload', () {
      final c = _make().container;
      _controller(c).set(
        targetId: 'master-1',
        serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
        serviceTypeLabels: const <String>{},
      );
      expect(_state(c), isNotNull);

      _controller(c).clear();

      expect(_state(c), isNull);
    });
  });

  group('session flip self-clear', () {
    test('flipping the watched session to Unauthenticated resets a pending '
        'payload back to null', () {
      final made = _make(auth: _authenticated);
      final c = made.container;
      _controller(c).set(
        targetId: 'master-1',
        serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
        serviceTypeLabels: const <String>{},
      );
      expect(_state(c), isNotNull);

      // Logout: the keepAlive controller watches authProvider, so build()
      // re-runs and the per-user payload is shed with no manual eviction —
      // one user's search never pre-checks the next user's booking.
      made.auth.emit(_unauthenticated);

      expect(
        _state(c),
        isNull,
        reason:
            'a fresh session must not inherit the prior user\'s '
            'pending service pre-selection',
      );
    });

    // ── The auth watch is NARROWED to the user id ─────────────────────────
    //
    // mobile-perf LOW (2026-09-01), and a CORRECTNESS fix rather than only
    // waste. `AuthNotifier.setAccessToken` is called by
    // `refresh_interceptor.dart` on EVERY silent token refresh and re-emits
    // `Authenticated` with the SAME user and a new accessToken. Rebuilding
    // this controller resets `state` to null, so the old bare
    // `ref.watch(authProvider)` WIPED the payload the user was mid-flow with:
    // search with a service filter → tap a result → a refresh lands during
    // the push → the booking step opens with nothing pre-checked.
    //
    // The pair below: the token-only re-emission must be INERT, and a real
    // identity change must STILL clear the payload — that second half is the
    // cross-session hole the watch was added for, and a `.select` returning a
    // constant would pass the first test alone.
    test('a silent token refresh (same user, new accessToken) does NOT clear '
        'the pending payload', () {
      final made = _make();
      final c = made.container;
      _controller(c).set(
        targetId: 'master-1',
        serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
        serviceTypeLabels: <String>{'Класичний манікюр'},
      );

      // Exactly what `refresh_interceptor.dart` does after a 401 → refresh.
      c.read(authProvider.notifier).setAccessToken('tok-rotated-2');

      expect(
        _state(c)?.targetId,
        'master-1',
        reason:
            'a token rotation is not a session change — the pending '
            'pre-selection must survive it, or the user loses their '
            'pre-checked services mid-flow',
      );
      expect(
        c.read(authProvider).value,
        isA<Authenticated>().having(
          (Authenticated a) => a.accessToken,
          'accessToken',
          'tok-rotated-2',
        ),
        reason:
            'sanity: the session really did re-emit with a new token, so the '
            'assertion above is about the .select narrowing and not about '
            'setAccessToken having silently no-opped',
      );
    });

    test('logging in as a DIFFERENT user DOES clear the pending payload', () {
      final made = _make();
      final c = made.container;
      _controller(c).set(
        targetId: 'master-1',
        serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
        serviceTypeLabels: <String>{'Класичний манікюр'},
      );
      expect(_state(c), isNotNull);

      made.auth.emit(
        const AsyncData<AuthSession>(
          AuthSession.authenticated(
            user: User(
              id: 'u-client-2',
              email: 'other@beautica.ua',
              role: UserRole.client,
            ),
            accessToken: 'tok',
          ),
        ),
      );

      expect(
        _state(c),
        isNull,
        reason:
            'one user\'s search must never pre-check services in the next '
            'user\'s booking flow',
      );
    });
  });
}
