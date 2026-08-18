// Phase 237 — [Wishlist] notifier: the optimistic un-favourite and its revert.
//
// TWO THINGS THIS FILE DELIBERATELY DOES NOT DO
// -----------------------------------------------------------------------
// 1. It never asserts on `hasError` alone. `AsyncLoading(retrying: true)`
//    ALREADY satisfies `hasError`, so such an assertion can pass for the wrong
//    reason. Every error assertion here names the failure TYPE.
// 2. It never uses a synchronous `thenThrow`. `FakeWishlistRepository` always
//    yields a microtask before raising, and the toggle repository fake does the
//    same, because a synchronous throw bypasses the async machinery entirely
//    and would exercise a shape the real transport cannot produce.
//
// The un-favourite goes through the SHARED `favoriteToggleProvider`, so these
// cases also pin that the two stores move together — the whole reason the list
// mutates in place rather than invalidating.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_favorite_repository.dart';
import '../../../helpers/fakes/fake_wishlist_repository.dart';

const User _user = User(
  id: 'u1',
  email: 'client@example.com',
  role: UserRole.client,
  firstName: 'Test',
  lastName: 'Client',
);

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _user, accessToken: 'token');
}

/// A REALISTIC RANGE row (phase 239).
///
/// The three price fields are set together on purpose: the backend never sends
/// «від 600 до 900 ₴» without also sending `priceType: RANGE` + the bounds, and
/// a fixture that carried only the long string would be a row the wire cannot
/// produce — it would render the backend's long form on both surfaces and quietly
/// stop exercising the band path these entries actually take.
WishlistService _svc(String id) => WishlistService(
  masterServiceId: id,
  masterId: 'm-$id',
  serviceName: 'Послуга $id',
  masterName: 'Олена Ковальчук',
  durationMinutes: 60,
  priceDisplay: 'від 600 до 900 ₴',
  isRangePrice: true,
  priceMin: 600,
  priceMax: 900,
);

final List<WishlistService> _three = <WishlistService>[
  _svc('a'),
  _svc('b'),
  _svc('c'),
];

Future<ProviderContainer> _makeContainer({
  required FakeWishlistRepository wishlistRepo,
  required FakeFavoriteRepository favoriteRepo,
}) async {
  final ProviderContainer container = ProviderContainer(
    retry: beauticaProviderRetry,
    // List<Object> + .cast() mirrors test/helpers/golden_pump.dart —
    // flutter_riverpod 3.x does not re-export the sealed `Override` type.
    overrides: <Object>[
      wishlistRepositoryProvider.overrideWithValue(wishlistRepo),
      favoriteRepositoryProvider.overrideWithValue(favoriteRepo),
      authProvider.overrideWith(_StubAuthNotifier.new),
    ].cast(),
  );
  addTearDown(container.dispose);
  // Settle auth first: the favorite toggle notifier `ref.watch`es it, so a
  // loading→data transition mid-test would re-run its build() and wipe the map.
  await container.read(authProvider.future);
  return container;
}

List<String> _ids(ProviderContainer c) =>
    (c.read(wishlistProvider).value ?? const <WishlistService>[])
        .map((WishlistService s) => s.favoriteTargetId)
        .toList();

void main() {
  group('build', () {
    test('resolves the repository page', () async {
      final ProviderContainer c = await _makeContainer(
        wishlistRepo: FakeWishlistRepository(services: _three),
        favoriteRepo: FakeFavoriteRepository(),
      );

      expect(await c.read(wishlistProvider.future), hasLength(3));
      expect(_ids(c), <String>['a', 'b', 'c']);
    });

    test('a repository Failure surfaces as that Failure TYPE', () async {
      // NOT `hasError` — see the file header. The fake throws asynchronously.
      //
      // A NON-TRANSIENT failure on purpose: `beauticaProviderRetry` retries
      // NetworkFailure, so a network fixture here would leave the provider in
      // `AsyncLoading(retrying: true)` — which ALREADY satisfies `hasError`,
      // i.e. the exact trap this file refuses to fall into. `ServerFailure`
      // with a null status is what the mapper raises for a broken payload and
      // is classified non-transient, so the error is terminal and observable.
      final ProviderContainer c = await _makeContainer(
        wishlistRepo: FakeWishlistRepository(
          failure: const ServerFailure(statusCode: null),
        ),
        favoriteRepo: FakeFavoriteRepository(),
      );
      // Hold a listener so the autoDispose provider is not torn down between
      // the read and the assertion.
      final ProviderSubscription<AsyncValue<List<WishlistService>>> sub = c
          .listen(wishlistProvider, (_, _) {});
      addTearDown(sub.close);

      await expectLater(
        c.read(wishlistProvider.future),
        throwsA(isA<ServerFailure>()),
      );
      expect(c.read(wishlistProvider).error, isA<ServerFailure>());
      expect(
        c.read(wishlistProvider).isLoading,
        isFalse,
        reason:
            'a terminal failure must settle, not sit in AsyncLoading(retrying)',
      );
    });
  });

  group('should_removeEntryOptimistically_when_unfavourited', () {
    test('the entry disappears BEFORE the wire call resolves', () async {
      final FakeFavoriteRepository favoriteRepo = FakeFavoriteRepository();
      final Completer<void> gate = Completer<void>();
      favoriteRepo.removeDelay = gate.future;

      final ProviderContainer c = await _makeContainer(
        wishlistRepo: FakeWishlistRepository(services: _three),
        favoriteRepo: favoriteRepo,
      );
      await c.read(wishlistProvider.future);

      // The transition is captured as a SEQUENCE. A post-hoc `isLoading` read
      // cannot see an `AsyncLoading` written and overwritten inside the same
      // synchronous block — verified by mutation: inserting a loading state
      // left such an assertion green.
      final List<AsyncValue<List<WishlistService>>> seen =
          <AsyncValue<List<WishlistService>>>[];
      final ProviderSubscription<AsyncValue<List<WishlistService>>> sub = c
          .listen(
            wishlistProvider,
            (
              AsyncValue<List<WishlistService>>? _,
              AsyncValue<List<WishlistService>> next,
            ) => seen.add(next),
          );
      addTearDown(sub.close);

      final Future<Failure?> pending = c
          .read(wishlistProvider.notifier)
          .removeService('b');

      // The list has already dropped it while the call is in flight.
      expect(_ids(c), <String>['a', 'c']);

      gate.complete();
      expect(await pending, isNull);
      expect(_ids(c), <String>['a', 'c']);

      // A loaded list on screen must never flash a spinner on a local removal.
      expect(
        seen.where((AsyncValue<List<WishlistService>> v) => v.isLoading),
        isEmpty,
        reason:
            'the optimistic removal passed through AsyncLoading — the list '
            'would blink its skeleton on every un-favourite',
      );
      expect(seen, isNotEmpty, reason: 'the listener must have observed it');
    });

    test('it calls REMOVE, keyed on the masterServiceId', () async {
      final FakeFavoriteRepository favoriteRepo = FakeFavoriteRepository();
      final ProviderContainer c = await _makeContainer(
        wishlistRepo: FakeWishlistRepository(services: _three),
        favoriteRepo: favoriteRepo,
      );
      await c.read(wishlistProvider.future);

      await c.read(wishlistProvider.notifier).removeService('b');

      // ADD would be the failure mode if the toggle map had not been primed:
      // an unseen target reads as `false`, and toggling `false` is an ADD.
      expect(favoriteRepo.addCalls, isEmpty);
      expect(favoriteRepo.removeCalls, hasLength(1));
      expect(
        favoriteRepo.removeCalls.single,
        const FavoriteTarget(type: FavoriteTargetType.service, id: 'b'),
      );
    });

    test('a successful removal does NOT refetch the list', () async {
      // Re-fetching would be the natural but wrong fix here: the full-list page
      // covers the passport page, Riverpod 3 pauses covered consumers, and an
      // invalidate would dispose the provider instead of reloading it.
      final FakeWishlistRepository wishlistRepo = FakeWishlistRepository(
        services: _three,
      );
      final ProviderContainer c = await _makeContainer(
        wishlistRepo: wishlistRepo,
        favoriteRepo: FakeFavoriteRepository(),
      );
      // A LISTENER MUST BE HELD for this to be able to fail: an invalidate on a
      // provider with no listeners disposes it instead of rebuilding, so the
      // call count would not move and the assertion would be vacuous. Verified
      // by mutation — without this subscription, swapping the in-place mutation
      // for `ref.invalidateSelf()` left the test green.
      final ProviderSubscription<AsyncValue<List<WishlistService>>> sub = c
          .listen(wishlistProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(wishlistProvider.future);
      expect(wishlistRepo.getCallCount, 1);

      await c.read(wishlistProvider.notifier).removeService('b');
      // Let any queued rebuild actually run before counting.
      await Future<void>.delayed(Duration.zero);

      expect(
        wishlistRepo.getCallCount,
        1,
        reason:
            'the removal triggered a refetch — on a covered route Riverpod 3 '
            'would dispose this provider instead of reloading it',
      );
      expect(_ids(c), <String>['a', 'c']);
    });

    test('an unknown id is a no-op — no request, no state change', () async {
      final FakeFavoriteRepository favoriteRepo = FakeFavoriteRepository();
      final ProviderContainer c = await _makeContainer(
        wishlistRepo: FakeWishlistRepository(services: _three),
        favoriteRepo: favoriteRepo,
      );
      await c.read(wishlistProvider.future);

      expect(
        await c.read(wishlistProvider.notifier).removeService('nope'),
        isNull,
      );
      expect(_ids(c), <String>['a', 'b', 'c']);
      expect(favoriteRepo.removeCalls, isEmpty);
    });
  });

  group('should_restoreEntry_when_removeFails', () {
    test('the entry comes back AT ITS ORIGINAL INDEX', () async {
      final FakeFavoriteRepository favoriteRepo = FakeFavoriteRepository()
        ..removeResult = const NetworkFailure();

      final ProviderContainer c = await _makeContainer(
        wishlistRepo: FakeWishlistRepository(services: _three),
        favoriteRepo: favoriteRepo,
      );
      await c.read(wishlistProvider.future);

      final Failure? failure = await c
          .read(wishlistProvider.notifier)
          .removeService('b');

      expect(failure, isA<NetworkFailure>());
      // Restored in place — appending would silently reorder a list the
      // backend ranks, a second invisible bug riding on the first.
      expect(_ids(c), <String>['a', 'b', 'c']);
      // …and restored WHOLE. The notifier re-inserts the captured entry rather
      // than rebuilding one, so the phase-239 price fields must survive the
      // round trip: a restored row that lost its bounds would silently fall
      // back to the backend's long «від 600 до 900 ₴» form on both surfaces.
      final WishlistService restored = c
          .read(wishlistProvider)
          .value!
          .firstWhere((WishlistService s) => s.masterServiceId == 'b');
      expect(restored, _svc('b'));
      expect(restored.priceLabel, '600–900 ₴');
    });

    test('the FIRST entry restores to index 0, not to the end', () async {
      final FakeFavoriteRepository favoriteRepo = FakeFavoriteRepository()
        ..removeResult = const NetworkFailure();
      final ProviderContainer c = await _makeContainer(
        wishlistRepo: FakeWishlistRepository(services: _three),
        favoriteRepo: favoriteRepo,
      );
      await c.read(wishlistProvider.future);

      await c.read(wishlistProvider.notifier).removeService('a');

      expect(_ids(c), <String>['a', 'b', 'c']);
    });

    test('the toggle store reverts in step with the list', () async {
      // If these two disagree, the heart on a master profile says "not saved"
      // while the wish list still lists the service.
      final FakeFavoriteRepository favoriteRepo = FakeFavoriteRepository()
        ..removeResult = const NetworkFailure();
      final ProviderContainer c = await _makeContainer(
        wishlistRepo: FakeWishlistRepository(services: _three),
        favoriteRepo: favoriteRepo,
      );
      await c.read(wishlistProvider.future);

      await c.read(wishlistProvider.notifier).removeService('b');

      const FavoriteTarget target = FavoriteTarget(
        type: FavoriteTargetType.service,
        id: 'b',
      );
      expect(
        c.read(favoriteToggleProvider.notifier).isFavorite(target),
        isTrue,
        reason: 'a failed un-favourite must leave the heart filled',
      );
      expect(_ids(c), contains('b'));
    });

    test(
      'a failure leaves the list in AsyncData, never in an error state',
      () async {
        // The removal failed, not the LIST. Dropping the whole page into an
        // error state would replace a working screen with a retry panel.
        final FakeFavoriteRepository favoriteRepo = FakeFavoriteRepository()
          ..removeResult = const NetworkFailure();
        final ProviderContainer c = await _makeContainer(
          wishlistRepo: FakeWishlistRepository(services: _three),
          favoriteRepo: favoriteRepo,
        );
        await c.read(wishlistProvider.future);

        await c.read(wishlistProvider.notifier).removeService('b');

        expect(c.read(wishlistProvider).error, isNull);
        expect(c.read(wishlistProvider).value, hasLength(3));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Phase F — SALON-arm removal. Every fixture and assertion above this point
  // is MASTER-arm only (`_svc`/`_three`), so none of it can catch a
  // regression in the SALON row's own removal path: the target-type dispatch
  // (`FavoriteTargetType.salonService`, never `.service`) and the
  // `favoriteTargetId` re-key (`serviceDefId`, not the null `masterServiceId`
  // every salon row shares) that `wishlist_notifier.dart` and
  // `wishlist_section.dart` both added specifically so multiple salon rows
  // cannot collide onto one `ValueKey<String>('null')`.
  // ---------------------------------------------------------------------------
  WishlistService salonSvc(String id, {String salonName = 'Салон краси'}) =>
      WishlistService(
        sourceType: WishlistSourceType.salon,
        salonId: 'salon-$id',
        salonName: salonName,
        serviceDefId: id,
        serviceName: 'Послуга $id',
        durationMinutes: 60,
        priceDisplay: '600 ₴',
      );

  group('should_removeSalonEntry_when_unfavourited', () {
    test(
      'it calls REMOVE with FavoriteTargetType.salonService, never .service',
      () async {
        // `.service` is scoped to a MASTER's own service assignment — sending
        // a SALON row's `service_definitions.id` through it would ask the
        // backend to remove a `master_services` row that does not exist.
        final FakeFavoriteRepository favoriteRepo = FakeFavoriteRepository();
        final ProviderContainer c = await _makeContainer(
          wishlistRepo: FakeWishlistRepository(
            services: <WishlistService>[salonSvc('sx')],
          ),
          favoriteRepo: favoriteRepo,
        );
        await c.read(wishlistProvider.future);

        await c.read(wishlistProvider.notifier).removeService('sx');

        expect(favoriteRepo.addCalls, isEmpty);
        expect(favoriteRepo.removeCalls, hasLength(1));
        expect(
          favoriteRepo.removeCalls.single,
          const FavoriteTarget(type: FavoriteTargetType.salonService, id: 'sx'),
        );
      },
    );

    test('two DISTINCT salon rows keyed by favoriteTargetId — removing one '
        'leaves the other, keyed and targeted correctly', () async {
      // Before the favoriteTargetId re-key, a key (or a removal lookup)
      // built off `masterServiceId` would read null on EVERY salon row —
      // this is the fixture shape that collision would actually manifest
      // on: two rows that share nothing but both being SALON-sourced.
      final FakeFavoriteRepository favoriteRepo = FakeFavoriteRepository();
      final ProviderContainer c = await _makeContainer(
        wishlistRepo: FakeWishlistRepository(
          services: <WishlistService>[
            salonSvc('salon-a', salonName: 'Салон А'),
            salonSvc('salon-b', salonName: 'Салон Б'),
          ],
        ),
        favoriteRepo: favoriteRepo,
      );
      await c.read(wishlistProvider.future);
      expect(_ids(c), <String>['salon-a', 'salon-b']);

      await c.read(wishlistProvider.notifier).removeService('salon-a');

      // ONLY salon-a left the list.
      expect(_ids(c), <String>['salon-b']);
      // ONLY salon-a's id was ever sent to the wire, never salon-b's and
      // never the shared `null` a masterServiceId-keyed lookup would have
      // produced for either row.
      expect(favoriteRepo.removeCalls, hasLength(1));
      expect(
        favoriteRepo.removeCalls.single,
        const FavoriteTarget(
          type: FavoriteTargetType.salonService,
          id: 'salon-a',
        ),
      );
    });

    test(
      'a failed salon removal restores it at its original index, whole',
      () async {
        final FakeFavoriteRepository favoriteRepo = FakeFavoriteRepository()
          ..removeResult = const NetworkFailure();
        final ProviderContainer c = await _makeContainer(
          wishlistRepo: FakeWishlistRepository(
            services: <WishlistService>[
              salonSvc('salon-a', salonName: 'Салон А'),
              salonSvc('salon-b', salonName: 'Салон Б'),
            ],
          ),
          favoriteRepo: favoriteRepo,
        );
        await c.read(wishlistProvider.future);

        final Failure? failure = await c
            .read(wishlistProvider.notifier)
            .removeService('salon-a');

        expect(failure, isA<NetworkFailure>());
        expect(_ids(c), <String>['salon-a', 'salon-b']);
        final WishlistService restored = c
            .read(wishlistProvider)
            .value!
            .firstWhere((WishlistService s) => s.favoriteTargetId == 'salon-a');
        expect(restored.sourceType, WishlistSourceType.salon);
        expect(restored.salonName, 'Салон А');
      },
    );
  });

  group('the two surfaces share one provider', () {
    test('a removal is visible to every reader at once', () async {
      // Two independent reads of the SAME provider — what the passport page's
      // take(2) and the full-list page each do.
      final ProviderContainer c = await _makeContainer(
        wishlistRepo: FakeWishlistRepository(services: _three),
        favoriteRepo: FakeFavoriteRepository(),
      );
      await c.read(wishlistProvider.future);

      final List<List<String>> observed = <List<String>>[];
      final ProviderSubscription<AsyncValue<List<WishlistService>>> sub = c
          .listen(wishlistProvider, (
            AsyncValue<List<WishlistService>>? _,
            AsyncValue<List<WishlistService>> next,
          ) {
            observed.add(
              (next.value ?? const <WishlistService>[])
                  .map((WishlistService s) => s.favoriteTargetId)
                  .toList(),
            );
          });
      addTearDown(sub.close);

      await c.read(wishlistProvider.notifier).removeService('c');

      expect(observed.last, <String>['a', 'b']);
      expect(_ids(c), <String>['a', 'b']);
    });
  });
}
