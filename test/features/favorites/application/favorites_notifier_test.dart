// Phase 111 (mobile-qa) — unit tests for [Favorites] + [FavoritesCategoryFilter].
//
// WHY THIS FILE EXISTS
// --------------------
// The perf auditor's finding on this chain was that every fix it prescribed was
// unpinned — "delete the `_refreshing` guard and all 16 stay green". The
// single-flight group below is the red-on-delete evidence for that guard, and
// the `unfavorite` groups are the evidence for the optimistic-removal state
// machine (restore AT INDEX, prime-before-toggle, no-op on an unknown id) that
// no test above the fake repository could observe.
//
// Drives the notifier through a [ProviderContainer] with
// `favoriteRepositoryProvider` overridden by [FakeFavoriteRepository]. No Dio,
// no widget tree.
//
// ── ASYNC-THROW, NOT `thenThrow` (M13) ──────────────────────────────────────
//
// [FakeFavoriteRepository.getFavoriteMasters] is an `async` method that throws
// from its body, so the rejection lands ASYNCHRONOUSLY — the shape a real
// Dio-backed repository always produces. A synchronous throw during a provider
// build short-circuits Riverpod's retry machinery entirely and would let an
// "error state" test assert a state a real user never reaches that way.
//
// The failure fixture is [NotFoundFailure] — DETERMINISTIC per
// `failure_retry_policy.dart:217`, so it terminates at attempt 1 under the
// PRODUCTION retry predicate this container installs. A transient failure
// (NetworkFailure) would burn the real ~38 s curve here for no added signal;
// the mid-retry shape is pinned at the WIDGET tier instead, where it is
// actually rendered.
//
// ── `isA<AsyncError>` IS NOT OPTIONAL (M12) ─────────────────────────────────
//
// `AsyncLoading(error: …, retrying: true)` satisfies `hasError` and carries the
// real `error`, so an assertion on `hasError`/`error` alone cannot distinguish
// the terminal error from the mid-retry loading state. Every error assertion
// below therefore also pins the runtime TYPE.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
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

import '../../../helpers/fakes/fake_favorite_repository.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

FavoriteItem _master(String id, {String? name}) => FavoriteItem(
  id: id,
  kind: FavoriteKind.master,
  name: name ?? 'Master $id',
  initials: 'M',
);

FavoriteItem _salon(String id) => FavoriteItem(
  id: id,
  kind: FavoriteKind.salon,
  name: 'Salon $id',
  initials: 'S',
);

const User _user = User(
  id: 'u1',
  email: 'client@example.com',
  role: UserRole.client,
  firstName: 'Test',
  lastName: 'Client',
);

/// A settled auth session so `favoriteToggleProvider`'s `ref.watch(authProvider)`
/// never reaches the real repository — and never re-runs `build()` mid-test,
/// which would wipe the optimistic flag map. Same device as
/// `favorite_toggle_notifier_test.dart`.
class _SettledAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _user, accessToken: 'token');
}

/// Fresh container per test, disposed in a tearDown (M1).
///
/// The two `container.listen` calls are LOAD-BEARING, not decoration. Both
/// providers are `autoDispose` (plain `@riverpod`), and a bare
/// `container.read(...)` leaves them with NO listener — so Riverpod disposes
/// them the moment the read returns and the very next read rebuilds from
/// scratch. Without these subscriptions an optimistic `unfavorite` reads back
/// as an empty list and `refresh()` reads back as `AsyncLoading`, which looks
/// exactly like the state machine being broken. In the app the screen's
/// `ref.watch` is that listener; here it has to be stated.
ProviderContainer _container(FakeFavoriteRepository repo) {
  final ProviderContainer container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: <Object>[
      favoriteRepositoryProvider.overrideWithValue(repo),
      authProvider.overrideWith(_SettledAuthNotifier.new),
    ].cast(),
  );
  addTearDown(container.dispose);
  container.listen(favoritesProvider, (_, _) {});
  container.listen(favoritesCategoryFilterProvider, (_, _) {});
  return container;
}

List<String> _ids(ProviderContainer c) =>
    (c.read(favoritesProvider).value ?? const <FavoriteItem>[])
        .map((FavoriteItem i) => i.id)
        .toList(growable: false);

void main() {
  group('Favorites.build — the merged load', () {
    test('fetches BOTH endpoints and merges masters-then-salons', () async {
      final FakeFavoriteRepository repo = FakeFavoriteRepository()
        ..masters = <FavoriteItem>[_master('m1'), _master('m2')]
        ..salons = <FavoriteItem>[_salon('s1')];
      final ProviderContainer container = _container(repo);

      final List<FavoriteItem> items = await container.read(
        favoritesProvider.future,
      );

      // Merge ORDER is a contract, not an accident: neither DTO carries the
      // `favorites.created_at` the backend sorts by, so a cross-kind interleave
      // is not derivable client-side and the notifier must not invent one.
      expect(items.map((FavoriteItem i) => i.id).toList(), <String>[
        'm1',
        'm2',
        's1',
      ]);
      // Exactly one call each — `Future.wait` over two independent futures,
      // not two sequential awaits and not a double subscription.
      expect(repo.mastersCalls, 1);
      expect(repo.salonsCalls, 1);
    });

    test('both calls are IN FLIGHT together, not serialised', () async {
      // RED WHEN `_load` is rewritten as two sequential `await`s: the salons
      // call would not have been made while the masters call is still blocked.
      final Completer<void> gate = Completer<void>();
      final FakeFavoriteRepository repo = FakeFavoriteRepository()
        ..mastersDelay = gate.future;
      final ProviderContainer container = _container(repo);

      final Future<List<FavoriteItem>> pending = container.read(
        favoritesProvider.future,
      );
      await Future<void>.delayed(Duration.zero);

      expect(repo.salonsCalls, 1, reason: 'salons must not wait on masters');
      gate.complete();
      await pending;
    });

    test('a failing endpoint surfaces as a TERMINAL AsyncError', () async {
      final FakeFavoriteRepository repo = FakeFavoriteRepository()
        ..salonsResult = const NotFoundFailure();
      final ProviderContainer container = _container(repo);

      await expectLater(
        container.read(favoritesProvider.future),
        throwsA(isA<NotFoundFailure>()),
      );

      final AsyncValue<List<FavoriteItem>> state = container.read(
        favoritesProvider,
      );
      // The TYPE, not just `hasError` — see the file header (M12).
      expect(state, isA<AsyncError<List<FavoriteItem>>>());
      expect(state.error, isA<NotFoundFailure>());
    });
  });

  group('Favorites.unfavorite — optimistic removal', () {
    test('drops the row from the model BEFORE the DELETE resolves', () async {
      final Completer<void> gate = Completer<void>();
      final FakeFavoriteRepository repo = FakeFavoriteRepository()
        ..masters = <FavoriteItem>[_master('m1'), _master('m2')]
        ..removeDelay = gate.future;
      final ProviderContainer container = _container(repo);
      await container.read(authProvider.future);
      final List<FavoriteItem> items = await container.read(
        favoritesProvider.future,
      );

      final Future<Failure?> pending = container
          .read(favoritesProvider.notifier)
          .unfavorite(items.first);
      await Future<void>.delayed(Duration.zero);

      expect(_ids(container), <String>['m2']);
      gate.complete();
      expect(await pending, isNull);
      expect(_ids(container), <String>['m2']);
    });

    test(
      'routes the DELETE through the toggle notifier, PRIMED to true',
      () async {
        // RED WHEN `notifier.primeIfAbsent(item.target, isFavorite: true)` is
        // deleted from `favorites_notifier.dart:129`. The toggle map only knows
        // targets the user has touched, and an UNSEEDED target reads `false` —
        // so an unprimed toggle sends an ADD for the favourite the client just
        // asked to remove. Both assertions are load-bearing: `removeCalls` alone
        // would pass on an implementation that fired BOTH.
        final FakeFavoriteRepository repo = FakeFavoriteRepository()
          ..masters = <FavoriteItem>[_master('m1')];
        final ProviderContainer container = _container(repo);
        await container.read(authProvider.future);
        final List<FavoriteItem> items = await container.read(
          favoritesProvider.future,
        );

        await container
            .read(favoritesProvider.notifier)
            .unfavorite(items.single);

        expect(repo.removeCalls, <FavoriteTarget>[items.single.target]);
        expect(repo.addCalls, isEmpty);
        // And the shared session flag is now false, so the heart on the search
        // card and the public profile for the same provider agree.
        expect(
          container
              .read(favoriteToggleProvider.notifier)
              .isFavorite(items.single.target),
          isFalse,
        );
      },
    );

    test('restores a failed removal AT ITS ORIGINAL INDEX', () async {
      // RED WHEN the restore appends instead of inserting at `index` — the end
      // state is "three rows" either way, so only the ORDER can catch it.
      final FakeFavoriteRepository repo = FakeFavoriteRepository()
        ..masters = <FavoriteItem>[_master('m1'), _master('m2'), _master('m3')]
        ..removeResult = const ServerFailure();
      final ProviderContainer container = _container(repo);
      await container.read(authProvider.future);
      final List<FavoriteItem> items = await container.read(
        favoritesProvider.future,
      );

      final Failure? failure = await container
          .read(favoritesProvider.notifier)
          .unfavorite(items[1]);

      expect(failure, isA<ServerFailure>());
      expect(_ids(container), <String>['m1', 'm2', 'm3']);
    });

    test('an id no longer in the list is a no-op — no round trip', () async {
      final FakeFavoriteRepository repo = FakeFavoriteRepository()
        ..masters = <FavoriteItem>[_master('m1')];
      final ProviderContainer container = _container(repo);
      await container.read(authProvider.future);
      await container.read(favoritesProvider.future);

      final Failure? failure = await container
          .read(favoritesProvider.notifier)
          .unfavorite(_master('gone'));

      expect(failure, isNull);
      expect(repo.removeCalls, isEmpty);
      expect(_ids(container), <String>['m1']);
    });
  });

  group('Favorites.refresh — SINGLE FLIGHT (perf MEDIUM pin)', () {
    test('two concurrent refreshes produce ONE fetch and the SAME future', () async {
      // RED WHEN the `_refreshing` guard at favorites_notifier.dart:179-185 is
      // deleted: `mastersCalls` becomes 3 and the two futures stop being
      // identical. The error screen's retry button routes here directly and is
      // tappable as fast as a finger moves, so two `_load()`s racing means the
      // client can end up looking at the OLDER of two responses with no signal.
      final Completer<void> gate = Completer<void>();
      final FakeFavoriteRepository repo = FakeFavoriteRepository()
        ..masters = <FavoriteItem>[_master('m1')];
      final ProviderContainer container = _container(repo);
      await container.read(favoritesProvider.future);
      expect(repo.mastersCalls, 1);

      repo.mastersDelay = gate.future;
      final Favorites notifier = container.read(favoritesProvider.notifier);
      final Future<void> first = notifier.refresh();
      final Future<void> second = notifier.refresh();

      expect(identical(first, second), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(repo.mastersCalls, 2);
      expect(repo.salonsCalls, 2);

      gate.complete();
      await first;
      await second;
    });

    test('a SEQUENTIAL third refresh does fetch again', () async {
      // The negative control. Without it, a `refresh()` that simply never
      // refetched after the first call would satisfy the test above.
      final FakeFavoriteRepository repo = FakeFavoriteRepository()
        ..masters = <FavoriteItem>[_master('m1')];
      final ProviderContainer container = _container(repo);
      await container.read(favoritesProvider.future);
      final Favorites notifier = container.read(favoritesProvider.notifier);

      await notifier.refresh();
      await notifier.refresh();

      expect(repo.mastersCalls, 3);
      expect(repo.salonsCalls, 3);
    });

    test('the guard is cleared even when the load FAILS', () async {
      // RED WHEN the `finally` in `_run` is dropped: the screen would wedge
      // into a permanently-refreshing state and the second refresh would be
      // swallowed forever.
      final FakeFavoriteRepository repo = FakeFavoriteRepository()
        ..masters = <FavoriteItem>[_master('m1')];
      final ProviderContainer container = _container(repo);
      await container.read(favoritesProvider.future);
      final Favorites notifier = container.read(favoritesProvider.notifier);

      repo.mastersResult = const NotFoundFailure();
      await notifier.refresh();
      expect(
        container.read(favoritesProvider),
        isA<AsyncError<List<FavoriteItem>>>(),
      );

      repo.mastersResult = null;
      await notifier.refresh();

      expect(repo.mastersCalls, 3);
      expect(_ids(container), <String>['m1']);
    });

    test(
      'refresh does NOT blank the list to AsyncLoading while in flight',
      () async {
        // RED WHEN `state = const AsyncLoading()` is added before the guard call:
        // the rows would flash away and back under the RefreshIndicator on every
        // pull.
        final Completer<void> gate = Completer<void>();
        final FakeFavoriteRepository repo = FakeFavoriteRepository()
          ..masters = <FavoriteItem>[_master('m1')];
        final ProviderContainer container = _container(repo);
        await container.read(favoritesProvider.future);

        repo.mastersDelay = gate.future;
        final Future<void> pending = container
            .read(favoritesProvider.notifier)
            .refresh();
        await Future<void>.delayed(Duration.zero);

        expect(
          container.read(favoritesProvider),
          isA<AsyncData<List<FavoriteItem>>>(),
        );
        expect(_ids(container), <String>['m1']);

        gate.complete();
        await pending;
      },
    );
  });

  group('FavoritesCategoryFilter', () {
    test('starts cleared and round-trips a selection', () {
      final ProviderContainer container = _container(FakeFavoriteRepository());

      expect(container.read(favoritesCategoryFilterProvider), isNull);

      container.read(favoritesCategoryFilterProvider.notifier).select('cat-1');
      expect(container.read(favoritesCategoryFilterProvider), 'cat-1');

      container.read(favoritesCategoryFilterProvider.notifier).select(null);
      expect(container.read(favoritesCategoryFilterProvider), isNull);
    });

    test('selecting a category does NOT refetch the list', () async {
      // The whole reason the two providers are split — a chip tap must never
      // touch the network.
      final FakeFavoriteRepository repo = FakeFavoriteRepository()
        ..masters = <FavoriteItem>[_master('m1')];
      final ProviderContainer container = _container(repo);
      await container.read(favoritesProvider.future);

      container.read(favoritesCategoryFilterProvider.notifier).select('cat-1');
      await Future<void>.delayed(Duration.zero);

      expect(repo.mastersCalls, 1);
      expect(repo.salonsCalls, 1);
    });
  });
}
