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
import 'package:beautica_mobile/features/favorites/application/favorites_notifier.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_item.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes/fake_favorite_repository.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

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
    retry: beauticaProviderRetry,
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

    // ── The auth watch is NARROWED to the user id ─────────────────────────
    //
    // mobile-perf LOW (2026-09-01), and a CORRECTNESS fix, not only waste.
    // `AuthNotifier.setAccessToken` is called by `refresh_interceptor.dart`
    // on EVERY silent token refresh and re-emits `Authenticated` with the
    // SAME user and a new accessToken. Because rebuilding this notifier
    // RESETS the map to empty, the old bare `ref.watch(authProvider)` meant
    // every silent refresh silently dropped every optimistic heart the user
    // had just tapped — the hearts on screen fell back to their `.select`
    // default of `false`.
    //
    // The pair below is what makes that assertion meaningful: the token-only
    // re-emission must be INERT, and a real identity change must STILL clear
    // the map (that is the cross-account leak the watch exists for, and the
    // `logout → login` test directly above covers its null arm). A `.select`
    // returning a constant would pass the first test alone.
    test('a silent token refresh (same user, new accessToken) does NOT clear '
        'the map', () async {
      final repo = FakeFavoriteRepository();
      final container = await _makeContainer(repo);
      final notifier = container.read(favoriteToggleProvider.notifier);

      await notifier.toggle(_master);
      expect(
        container.read(favoriteToggleProvider).containsKey(_master),
        isTrue,
      );

      // Exactly what `refresh_interceptor.dart` does after a 401 → refresh.
      container.read(authProvider.notifier).setAccessToken('token-rotated-2');

      expect(
        container.read(favoriteToggleProvider).containsKey(_master),
        isTrue,
        reason:
            'a token rotation is not a session change — the optimistic '
            'favorite map must survive it',
      );
      expect(
        container.read(authProvider).value,
        isA<Authenticated>().having(
          (Authenticated a) => a.accessToken,
          'accessToken',
          'token-rotated-2',
        ),
        reason:
            'sanity: the session really did re-emit with a new token, so the '
            'assertion above is about the .select narrowing and not about '
            'setAccessToken having silently no-opped',
      );
    });

    test('logging in as a DIFFERENT user DOES clear the map', () async {
      final repo = FakeFavoriteRepository();
      final container = await _makeContainer(repo);
      final notifier = container.read(favoriteToggleProvider.notifier);

      await notifier.toggle(_master);
      expect(
        container.read(favoriteToggleProvider).containsKey(_master),
        isTrue,
      );

      final auth =
          container.read(authProvider.notifier) as _MutableAuthNotifier;
      auth.setSession(
        const AuthSession.authenticated(
          user: User(
            id: 'u2',
            email: 'other@example.com',
            role: UserRole.client,
          ),
          accessToken: 'token',
        ),
      );

      expect(
        container.read(favoriteToggleProvider),
        isEmpty,
        reason:
            'the next signed-in user must never inherit the previous one\'s '
            'favorite flags through this keepAlive map',
      );
    });
  });

  // Review-trust fix — a successful MASTER/SALON toggle refreshes a MOUNTED
  // «Улюблені» list (assigning refresh, never invalidate), and fetches nothing
  // when the list was never opened.
  group('FavoriteToggleNotifier.toggle — refreshes favoritesProvider', () {
    const FavoriteItem masterRow = FavoriteItem(
      id: 'master-1',
      kind: FavoriteKind.master,
      name: 'Master One',
      initials: 'MO',
    );

    /// Mounts `favoritesProvider` (a live listener, like the shell branch) and
    /// waits for its first load; returns the subscription.
    Future<ProviderSubscription<AsyncValue<List<FavoriteItem>>>> mountList(
      ProviderContainer container,
    ) async {
      final sub = container.listen<AsyncValue<List<FavoriteItem>>>(
        favoritesProvider,
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(favoritesProvider.future);
      return sub;
    }

    test('a master ADD refreshes a mounted list with the new row', () async {
      final repo = FakeFavoriteRepository();
      final container = await _makeContainer(repo);
      await mountList(container);
      expect(repo.mastersCalls, 1);
      expect(container.read(favoritesProvider).value, isEmpty);

      repo.masters = const <FavoriteItem>[masterRow];
      expect(
        await container.read(favoriteToggleProvider.notifier).toggle(_master),
        isNull,
      );
      await pumpEventQueue();

      expect(repo.mastersCalls, 2, reason: 'the add must refetch the list');
      expect(
        repo.salonsCalls,
        1,
        reason: 'a master toggle refetches masters only (refresh(only:))',
      );
      expect(
        container.read(favoritesProvider).value,
        equals(const <FavoriteItem>[masterRow]),
      );
    });

    test('a master REMOVE refreshes a mounted list without the row', () async {
      final repo = FakeFavoriteRepository()
        ..masters = const <FavoriteItem>[masterRow];
      final container = await _makeContainer(repo);
      await mountList(container);
      expect(container.read(favoritesProvider).value, hasLength(1));

      final notifier = container.read(favoriteToggleProvider.notifier);
      notifier.primeIfAbsent(_master, isFavorite: true);
      repo.masters = const <FavoriteItem>[];
      expect(await notifier.toggle(_master), isNull);
      await pumpEventQueue();

      expect(repo.removeCalls, equals(<FavoriteTarget>[_master]));
      expect(repo.mastersCalls, 2, reason: 'the remove must refetch the list');
      expect(container.read(favoritesProvider).value, isEmpty);
    });

    test('a salon toggle refreshes a mounted list too', () async {
      final repo = FakeFavoriteRepository();
      final container = await _makeContainer(repo);
      await mountList(container);

      await container.read(favoriteToggleProvider.notifier).toggle(_salon);
      await pumpEventQueue();

      expect(repo.salonsCalls, 2);
      expect(
        repo.mastersCalls,
        1,
        reason: 'a salon toggle refetches salons only',
      );
    });

    test('nothing is fetched when the list is NOT mounted', () async {
      final repo = FakeFavoriteRepository();
      final container = await _makeContainer(repo);
      final notifier = container.read(favoriteToggleProvider.notifier);

      await notifier.toggle(_master); // add
      await notifier.toggle(_master); // remove
      await pumpEventQueue();

      expect(repo.mastersCalls, 0);
      expect(repo.salonsCalls, 0);
      expect(container.exists(favoritesProvider), isFalse);
    });

    test('refreshFavorites: false suppresses the refetch', () async {
      final repo = FakeFavoriteRepository();
      final container = await _makeContainer(repo);
      await mountList(container);

      await container
          .read(favoriteToggleProvider.notifier)
          .toggle(_master, refreshFavorites: false);
      await pumpEventQueue();

      expect(repo.mastersCalls, 1);
    });

    test('a SERVICE toggle never refetches the list', () async {
      final repo = FakeFavoriteRepository();
      final container = await _makeContainer(repo);
      await mountList(container);

      await container
          .read(favoriteToggleProvider.notifier)
          .toggle(
            const FavoriteTarget(type: FavoriteTargetType.service, id: 's-1'),
            refreshWishlist: false,
          );
      await pumpEventQueue();

      expect(repo.mastersCalls, 1);
    });

    test('a FAILED toggle does not refetch the list', () async {
      final repo = FakeFavoriteRepository()..addResult = const NetworkFailure();
      final container = await _makeContainer(repo);
      await mountList(container);

      expect(
        await container.read(favoriteToggleProvider.notifier).toggle(_master),
        isNotNull,
      );
      await pumpEventQueue();

      expect(repo.mastersCalls, 1);
    });

    test('two toggles inside ONE refresh window both reach the list', () async {
      // RED WHEN `Favorites.refresh`'s trailing re-run is dropped: the second
      // toggle's refresh joins the in-flight GET (which predates it), so
      // master-2 never shows.
      const FavoriteItem secondRow = FavoriteItem(
        id: 'master-2',
        kind: FavoriteKind.master,
        name: 'Master Two',
        initials: 'MT',
      );
      const FavoriteTarget second = FavoriteTarget(
        type: FavoriteTargetType.master,
        id: 'master-2',
      );
      final Completer<void> gate = Completer<void>();
      final repo = FakeFavoriteRepository()..snapshotRowsAtCall = true;
      final container = await _makeContainer(repo);
      await mountList(container);
      final notifier = container.read(favoriteToggleProvider.notifier);

      repo
        ..mastersDelay = gate.future
        ..masters = const <FavoriteItem>[masterRow];
      expect(await notifier.toggle(_master), isNull);
      await pumpEventQueue();
      repo.masters = const <FavoriteItem>[masterRow, secondRow];
      expect(await notifier.toggle(second), isNull);

      gate.complete();
      await pumpEventQueue();

      expect(repo.mastersCalls, 3, reason: 'mount + in-flight + ONE re-run');
      expect(
        container.read(favoritesProvider).value,
        equals(const <FavoriteItem>[masterRow, secondRow]),
      );
    });

    test(
      'a session change mid-call: no heart write, no list refresh',
      () async {
        // RED WHEN the `if (!r.mounted) return null;` after the await in
        // `toggle` is dropped: the old user's heart lands in the new session's
        // map, and the old user's toggle refetches the list.
        final Completer<void> gate = Completer<void>();
        final repo = FakeFavoriteRepository()..addDelay = gate.future;
        final container = await _makeContainer(repo);
        await mountList(container);
        final notifier = container.read(favoriteToggleProvider.notifier);

        final Future<Failure?> pending = notifier.toggle(_master);
        expect(
          container.read(favoriteToggleProvider)[_master]?.pending,
          isTrue,
        );

        final auth =
            container.read(authProvider.notifier) as _MutableAuthNotifier;
        auth.setSession(
          const AuthSession.authenticated(
            user: User(
              id: 'u2',
              email: 'other@example.com',
              role: UserRole.client,
              firstName: 'Other',
              lastName: 'Client',
            ),
            accessToken: 'token-2',
          ),
        );
        expect(container.read(favoriteToggleProvider), isEmpty);

        gate.complete();
        expect(await pending, isNull);
        await pumpEventQueue();

        expect(
          container.read(favoriteToggleProvider),
          isEmpty,
          reason: "the old session's heart must not reach the new session",
        );
        expect(
          repo.mastersCalls,
          1,
          reason: 'no refresh for a retired session',
        );
      },
    );

    test('a session change mid-call skips the failure revert too', () async {
      final Completer<void> gate = Completer<void>();
      final repo = FakeFavoriteRepository()
        ..addDelay = gate.future
        ..addResult = const NetworkFailure();
      final container = await _makeContainer(repo);
      final notifier = container.read(favoriteToggleProvider.notifier);

      final Future<Failure?> pending = notifier.toggle(_master);
      final auth =
          container.read(authProvider.notifier) as _MutableAuthNotifier;
      auth.setSession(const AuthSession.unauthenticated());
      expect(container.read(favoriteToggleProvider), isEmpty);
      // The new session favourites the same target meanwhile.
      container
          .read(favoriteToggleProvider.notifier)
          .primeIfAbsent(_master, isFavorite: true);

      gate.complete();
      expect(await pending, isNull);

      expect(
        container.read(favoriteToggleProvider)[_master]?.isFavorite,
        isTrue,
        reason: "the old session's revert must not stomp the new session",
      );
    });
  });

  // Audit cycle 1 (heart priming) — server snapshots go through
  // `syncFromServer`, which can CLEAR a heart but never beats a pending toggle
  // or this session's own toggle.
  group('FavoriteToggleNotifier.syncFromServer', () {
    test('after a successful UNfavourite, a stale sync(true) leaves the heart '
        'empty', () async {
      // RED WHEN the per-session `_locallyToggled` check is dropped: a
      // 5-minute-old cached profile saying `true` re-fills the heart the user
      // just emptied.
      final repo = FakeFavoriteRepository();
      final container = await _makeContainer(repo);
      final notifier = container.read(favoriteToggleProvider.notifier);
      notifier.syncFromServer(_master, isFavorite: true);
      expect(notifier.isFavorite(_master), isTrue);

      expect(await notifier.toggle(_master), isNull); // unfavourite
      expect(repo.removeCalls, equals(<FavoriteTarget>[_master]));

      notifier.syncFromServer(_master, isFavorite: true); // stale snapshot
      expect(notifier.isFavorite(_master), isFalse);
    });

    test('a server FALSE after a refresh empties a filled heart', () async {
      // RED WHEN sync is add-only (the old `primeIfAbsent` semantics): the
      // heart stays filled although the server says the favourite is gone.
      final repo = FakeFavoriteRepository();
      final container = await _makeContainer(repo);
      final notifier = container.read(favoriteToggleProvider.notifier);

      notifier.syncFromServer(_master, isFavorite: true);
      expect(notifier.isFavorite(_master), isTrue);
      notifier.syncFromServer(_master, isFavorite: false);

      expect(notifier.isFavorite(_master), isFalse);
      expect(container.read(favoriteToggleProvider), isEmpty);
    });

    test('a PENDING toggle is never overwritten', () async {
      // RED WHEN the `pending` check is dropped: the snapshot replaces the
      // in-flight entry and the double-tap guard is lost.
      final gate = Completer<void>();
      final repo = FakeFavoriteRepository()..addDelay = gate.future;
      final container = await _makeContainer(repo);
      final notifier = container.read(favoriteToggleProvider.notifier);

      final Future<Failure?> pending = notifier.toggle(_master);
      notifier.syncFromServer(_master, isFavorite: false);

      final FavoriteEntry? entry = container.read(
        favoriteToggleProvider,
      )[_master];
      expect(entry?.isFavorite, isTrue);
      expect(entry?.pending, isTrue);

      gate.complete();
      expect(await pending, isNull);
      expect(notifier.isFavorite(_master), isTrue);
    });

    test(
      'a NEW session forgets the local decisions — sync applies again',
      () async {
        final repo = FakeFavoriteRepository();
        final container = await _makeContainer(repo);
        final notifier = container.read(favoriteToggleProvider.notifier);
        expect(await notifier.toggle(_master), isNull); // local: favourited
        notifier.syncFromServer(_master, isFavorite: false);
        expect(notifier.isFavorite(_master), isTrue, reason: 'local wins');

        final auth =
            container.read(authProvider.notifier) as _MutableAuthNotifier;
        auth.setSession(
          const AuthSession.authenticated(
            user: User(
              id: 'u3',
              email: 'third@example.com',
              role: UserRole.client,
              firstName: 'Third',
              lastName: 'Client',
            ),
            accessToken: 'token-3',
          ),
        );
        expect(container.read(favoriteToggleProvider), isEmpty);

        container
            .read(favoriteToggleProvider.notifier)
            .syncFromServer(_master, isFavorite: true);
        expect(
          container.read(favoriteToggleProvider.notifier).isFavorite(_master),
          isTrue,
        );
        container
            .read(favoriteToggleProvider.notifier)
            .syncFromServer(_master, isFavorite: false);
        expect(
          container.read(favoriteToggleProvider.notifier).isFavorite(_master),
          isFalse,
          reason: 'the previous session\'s toggle must not shield the target',
        );
      },
    );
  });
}
