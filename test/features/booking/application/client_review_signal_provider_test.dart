// Unit tests for [ClientReviewSignal] — the session-scoped set of booking ids
// this provider has just left client feedback about
// (`lib/features/booking/application/client_review_signal_provider.dart`).
//
// The load-bearing group here is the SESSION-BOUNDARY one. This is a
// `keepAlive` provider holding user-scoped booking ids, so it outlives every
// screen that reads it; without the `authProvider` watch in `build()`, one
// master's reviewed-booking ids would still be sitting in the set after a
// different account logged in on the same device and would suppress «Відгук»
// CTAs in THEIR archive. That is the PII-leak guard, and it is the reason this
// file exists at all — the add/idempotence tests below are supporting cast.
//
// The other invariant pinned here is the FAIL-CLOSED direction: the notifier's
// only mutation ADDS an id. There is deliberately no remove/clear counterpart,
// so nothing in this mechanism can hand a row its «Відгук» CTA back. The
// consumer half of that invariant (`markClientReviewed` writes a hardcoded
// `false`, never `true`) is pinned in `master_archive_notifier_test.dart`.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/client_review_signal_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const User _masterA = User(
  id: 'user-a',
  email: 'a@example.com',
  role: UserRole.independentMaster,
);

const User _masterB = User(
  id: 'user-b',
  email: 'b@example.com',
  role: UserRole.independentMaster,
);

AsyncValue<AuthSession> _sessionFor(User user, {String token = 'tok-1'}) =>
    AsyncData<AuthSession>(
      AuthSession.authenticated(user: user, accessToken: token),
    );

const AsyncValue<AuthSession> _loggedOut = AsyncData<AuthSession>(
  AuthSession.unauthenticated(),
);

/// [AuthNotifier] stub whose session can be flipped mid-test — the only way to
/// drive a real logout / account switch / silent token refresh through the
/// ordinary Riverpod cascade rather than simulating one.
class _SettableAuthNotifier extends AuthNotifier {
  _SettableAuthNotifier(this._initial);

  final AsyncValue<AuthSession> _initial;

  @override
  Future<AuthSession> build() async {
    return _initial.value ?? const AuthSession.unauthenticated();
  }

  void emit(AsyncValue<AuthSession> next) => state = next;
}

void main() {
  /// Builds a container with a flippable auth session and returns it plus the
  /// stub notifier. `keepAlive: true` on the provider under test means nothing
  /// has to keep listening for the state to survive — but the auth watch only
  /// re-runs `build()` if the provider is actually alive, so every test reads
  /// it at least once before flipping.
  Future<(ProviderContainer, _SettableAuthNotifier)> boot(
    AsyncValue<AuthSession> initial,
  ) async {
    late _SettableAuthNotifier auth;
    final ProviderContainer container = ProviderContainer(
      // Untyped literal on purpose: `Override` is not on `flutter_riverpod`'s
      // show-list (it lives on the advanced `misc.dart` surface), and this
      // file has no other reason to import that.
      overrides: [
        authProvider.overrideWith(() {
          auth = _SettableAuthNotifier(initial);
          return auth;
        }),
      ],
    );
    addTearDown(container.dispose);
    // Settle `build()`'s future so a later `emit` is not overwritten by the
    // notifier's own initial resolution.
    await container.read(authProvider.future);
    return (container, auth);
  }

  group('the set itself', () {
    test('starts empty', () async {
      final (ProviderContainer c, _) = await boot(_sessionFor(_masterA));
      expect(c.read(clientReviewSignalProvider), isEmpty);
    });

    test('markReviewed adds the id, and accumulates across several reviews '
        'in one session', () async {
      final (ProviderContainer c, _) = await boot(_sessionFor(_masterA));
      final ClientReviewSignal signal = c.read(
        clientReviewSignalProvider.notifier,
      );

      signal.markReviewed('booking-1');
      expect(c.read(clientReviewSignalProvider), <String>{'booking-1'});

      signal.markReviewed('booking-2');
      expect(c.read(clientReviewSignalProvider), <String>{
        'booking-1',
        'booking-2',
      });
    });

    test('re-signalling an id already in the set keeps the SAME set instance '
        '— it publishes no state change, so a consumer that rebuilds off this '
        'provider cannot be spun by a repeat signal', () async {
      final (ProviderContainer c, _) = await boot(_sessionFor(_masterA));
      final ClientReviewSignal signal = c.read(
        clientReviewSignalProvider.notifier,
      );
      signal.markReviewed('booking-1');
      final Set<String> before = c.read(clientReviewSignalProvider);

      signal.markReviewed('booking-1');

      expect(
        identical(before, c.read(clientReviewSignalProvider)),
        isTrue,
        reason:
            'an idempotent no-op must not allocate a new set — a new '
            'instance would notify every watcher for nothing',
      );
    });

    test('FAIL-CLOSED — the published set is unmodifiable, so a consumer '
        'cannot quietly remove an id and resurrect a «Відгук» CTA', () async {
      final (ProviderContainer c, _) = await boot(_sessionFor(_masterA));
      c.read(clientReviewSignalProvider.notifier).markReviewed('booking-1');

      final Set<String> published = c.read(clientReviewSignalProvider);

      expect(() => published.remove('booking-1'), throwsUnsupportedError);
      expect(() => published.clear(), throwsUnsupportedError);
      expect(
        c.read(clientReviewSignalProvider),
        <String>{'booking-1'},
        reason: 'the failed mutation attempts left the real set intact',
      );
    });
  });

  group('SEC — session boundary (the PII guard)', () {
    test('a DIFFERENT account logging in resets the set to empty — one '
        "master's reviewed-booking ids must never suppress CTAs in another "
        "master's archive", () async {
      final (ProviderContainer c, _SettableAuthNotifier auth) = await boot(
        _sessionFor(_masterA),
      );
      c.read(clientReviewSignalProvider.notifier).markReviewed('booking-1');
      expect(
        c.read(clientReviewSignalProvider),
        <String>{'booking-1'},
        reason: 'precondition — user A really did leave a signal behind',
      );

      auth.emit(_sessionFor(_masterB));

      expect(
        c.read(clientReviewSignalProvider),
        isEmpty,
        reason:
            'THE LEAK: a keepAlive provider holding user-scoped booking ids '
            'must rebuild when the authenticated identity changes',
      );
    });

    test('logging OUT resets the set to empty', () async {
      final (ProviderContainer c, _SettableAuthNotifier auth) = await boot(
        _sessionFor(_masterA),
      );
      c.read(clientReviewSignalProvider.notifier).markReviewed('booking-1');
      expect(c.read(clientReviewSignalProvider), <String>{'booking-1'});

      auth.emit(_loggedOut);

      expect(c.read(clientReviewSignalProvider), isEmpty);
    });

    test('a SILENT TOKEN REFRESH (same user id, new access token) does NOT '
        'clear the set — the watch selects the identity slice only, so an '
        'ordinary refresh mid-session cannot resurrect an already-reviewed '
        "row's CTA", () async {
      final (ProviderContainer c, _SettableAuthNotifier auth) = await boot(
        _sessionFor(_masterA),
      );
      c.read(clientReviewSignalProvider.notifier).markReviewed('booking-1');

      auth.emit(_sessionFor(_masterA, token: 'tok-2-refreshed'));

      expect(
        c.read(clientReviewSignalProvider),
        <String>{'booking-1'},
        reason:
            'keeps the account-switch assertion above non-vacuous: it must '
            'be the IDENTITY that clears the set, not any session emission',
      );
    });
  });
}
