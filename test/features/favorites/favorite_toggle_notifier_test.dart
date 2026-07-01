// Phase 13.4 — Unit tests for [FavoriteToggleNotifier].
//
// Drives the notifier directly through a [ProviderContainer] with the
// `favoriteRepositoryProvider` overridden by a controllable [FakeFavorite
// Repository], so no real Dio / network is involved. Covers the full optimistic
// state machine:
//   • optimistic flip is visible BEFORE the repo future resolves (pending == true);
//   • success keeps the flag + clears pending + returns null;
//   • failure reverts the flag + clears pending + returns the Failure (snackbar);
//   • in-flight double-tap is a no-op (no overlapping requests / corruption);
//   • primeIfAbsent seeds a `true` flag, skips a `false` one, never grows the map;
//   • a session change (logout → login) clears the map.
//
// The auth dependency is overridden with a mutable test notifier so the
// logout-reset path can flip the session and force `build()` to re-run.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes/fake_favorite_repository.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const FavoriteTarget _master = FavoriteTarget(
  type: FavoriteTargetType.master,
  id: 'master-1',
);

const FavoriteTarget _salon = FavoriteTarget(
  type: FavoriteTargetType.salon,
  id: 'salon-1',
);

const User _user = User(
  id: 'u1',
  email: 'client@example.com',
  role: UserRole.client,
  firstName: 'Test',
  lastName: 'Client',
);

/// A mutable auth notifier whose session can be flipped at runtime so the
/// favorite notifier's `ref.watch(authProvider)` re-runs `build()`.
class _MutableAuthNotifier extends AuthNotifier {
  _MutableAuthNotifier(this._initial);

  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;

  /// Flips the session, simulating logout → login. Riverpod re-runs every
  /// watcher's `build()`, clearing the favorite map.
  void setSession(AuthSession session) =>
      state = AsyncData<AuthSession>(session);
}

/// Builds a container with the favorite repo + auth overridden, with the async
/// [authProvider] already SETTLED to AsyncData.
///
/// Settling auth first is load-bearing: the favorite notifier `ref.watch`es
/// authProvider in its `build()`, so a loading→data transition mid-test would
/// re-run `build()` and wipe the optimistic map. We await the auth future once
/// here so every later `await` in a test sees a stable session.
Future<ProviderContainer> _makeContainer(FakeFavoriteRepository repo) async {
  final container = ProviderContainer(
    // List<Object> + .cast() mirrors test/helpers/golden_pump.dart — flutter_
    // riverpod 3.x does not re-export the sealed `Override` type.
    overrides: <Object>[
      favoriteRepositoryProvider.overrideWithValue(repo),
      authProvider.overrideWith(
        () => _MutableAuthNotifier(
          const AuthSession.authenticated(user: _user, accessToken: 'token'),
        ),
      ),
    ].cast(),
  );
  addTearDown(container.dispose);
  // Drive the async auth notifier to AsyncData before any toggle runs.
  await container.read(authProvider.future);
  return container;
}

void main() {
  group('FavoriteToggleNotifier.toggle — optimistic add', () {
    test(
      'flips flag + marks pending immediately, before the repo resolves',
      () async {
        final repo = FakeFavoriteRepository();
        final completer = Completer<void>();
        repo.addDelay = completer.future; // block the add until we release it.
        final container = await _makeContainer(repo);
        final notifier = container.read(favoriteToggleProvider.notifier);

        // Act — kick off the toggle but DON'T await it yet.
        final Future<Failure?> pending = notifier.toggle(_master);

        // Assert — optimistic flip is visible while the call is in flight.
        final entry = container.read(favoriteToggleProvider)[_master];
        expect(entry?.isFavorite, isTrue);
        expect(entry?.pending, isTrue);
        expect(notifier.isFavorite(_master), isTrue);

        // Release + settle.
        completer.complete();
        expect(await pending, isNull);
      },
    );

    test(
      'success keeps the flipped flag, clears pending, returns null',
      () async {
        final repo = FakeFavoriteRepository();
        final container = await _makeContainer(repo);
        final notifier = container.read(favoriteToggleProvider.notifier);

        final Failure? result = await notifier.toggle(_master);

        expect(result, isNull);
        final entry = container.read(favoriteToggleProvider)[_master];
        expect(entry?.isFavorite, isTrue);
        expect(entry?.pending, isFalse);
        expect(repo.addCalls, <FavoriteTarget>[_master]);
        expect(repo.removeCalls, isEmpty);
      },
    );
  });

  group('FavoriteToggleNotifier.toggle — revert on error', () {
    test(
      'repo Failure reverts the flag, clears pending, returns the Failure',
      () async {
        final repo = FakeFavoriteRepository()
          ..addResult = const NetworkFailure();
        final container = await _makeContainer(repo);
        final notifier = container.read(favoriteToggleProvider.notifier);

        final Failure? result = await notifier.toggle(_master);

        // The Failure is returned so the screen can show a snackbar.
        expect(result, isA<NetworkFailure>());
        // Flag reverted to its pre-toggle value (false) → entry pruned entirely.
        expect(
          container.read(favoriteToggleProvider).containsKey(_master),
          isFalse,
        );
        expect(notifier.isFavorite(_master), isFalse);
      },
    );

    test('un-favorite failure reverts the flag back to favorited', () async {
      final repo = FakeFavoriteRepository()
        ..removeResult = const ServerFailure();
      final container = await _makeContainer(repo);
      final notifier = container.read(favoriteToggleProvider.notifier);

      // Start favorited.
      notifier.primeIfAbsent(_master, isFavorite: true);
      expect(notifier.isFavorite(_master), isTrue);

      final Failure? result = await notifier.toggle(_master); // attempts remove

      expect(result, isA<ServerFailure>());
      // Reverted back to favorited after the failed un-favorite.
      expect(notifier.isFavorite(_master), isTrue);
      final entry = container.read(favoriteToggleProvider)[_master];
      expect(entry?.pending, isFalse);
      expect(repo.removeCalls, <FavoriteTarget>[_master]);
    });
  });

  group('FavoriteToggleNotifier.toggle — in-flight idempotency', () {
    test(
      'a second toggle while the first is pending is a no-op (no double-fire)',
      () async {
        final repo = FakeFavoriteRepository();
        final completer = Completer<void>();
        repo.addDelay = completer.future;
        final container = await _makeContainer(repo);
        final notifier = container.read(favoriteToggleProvider.notifier);

        // First toggle — left in flight.
        final Future<Failure?> first = notifier.toggle(_master);
        // Second toggle on the SAME target while pending → returns null, no call.
        final Failure? second = await notifier.toggle(_master);

        expect(second, isNull);
        // Still pending + flipped exactly once; only ONE add fired.
        final entry = container.read(favoriteToggleProvider)[_master];
        expect(entry?.isFavorite, isTrue);
        expect(entry?.pending, isTrue);
        expect(repo.addCalls.length, 1);

        completer.complete();
        expect(await first, isNull);
        // After settle: still exactly one add, flag stays favorited, pending clear.
        expect(repo.addCalls.length, 1);
        expect(
          container.read(favoriteToggleProvider)[_master]?.pending,
          isFalse,
        );
      },
    );
  });

  group('FavoriteToggleNotifier.primeIfAbsent', () {
    test('seeds a true flag and never grows the map for a false seed', () async {
      final repo = FakeFavoriteRepository();
      final container = await _makeContainer(repo);
      final notifier = container.read(favoriteToggleProvider.notifier);

      // false seed → not stored (prune-on-false keeps the keepAlive map small).
      notifier.primeIfAbsent(_salon, isFavorite: false);
      expect(
        container.read(favoriteToggleProvider).containsKey(_salon),
        isFalse,
      );
      expect(notifier.isFavorite(_salon), isFalse);

      // true seed → stored.
      notifier.primeIfAbsent(_master, isFavorite: true);
      expect(notifier.isFavorite(_master), isTrue);
      expect(container.read(favoriteToggleProvider).length, 1);
    });

    test('never overwrites an existing flag the user just toggled', () async {
      final repo = FakeFavoriteRepository();
      final container = await _makeContainer(repo);
      final notifier = container.read(favoriteToggleProvider.notifier);

      // User favorited the master.
      await notifier.toggle(_master);
      expect(notifier.isFavorite(_master), isTrue);

      // A late card re-seed must NOT stomp the toggled flag.
      notifier.primeIfAbsent(_master, isFavorite: false);
      expect(notifier.isFavorite(_master), isTrue);
    });
  });

  group('FavoriteToggleNotifier — session reset', () {
    test('changing the session (logout → login) clears the map', () async {
      final repo = FakeFavoriteRepository();
      final container = await _makeContainer(repo);
      final notifier = container.read(favoriteToggleProvider.notifier);

      await notifier.toggle(_master);
      expect(
        container.read(favoriteToggleProvider).containsKey(_master),
        isTrue,
      );

      // Flip the session — Riverpod re-runs build(), resetting the map to empty.
      final auth =
          container.read(authProvider.notifier) as _MutableAuthNotifier;
      auth.setSession(const AuthSession.unauthenticated());
      // Re-read the favorite provider after the dependency changed.
      expect(container.read(favoriteToggleProvider), isEmpty);
    });
  });
}
