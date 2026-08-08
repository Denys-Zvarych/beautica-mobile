// PROVIDER-GRAPH CYCLE GUARD — the core safeguard against the class of
// "works in release/AOT, fails in debug/test" Riverpod bugs.
//
// THE BUG THIS GUARDS (2026-06-18 logout regression)
// --------------------------------------------------
// AuthNotifier.logout() used to `ref.invalidate(masterProfileProvider /
// serviceRepositoryProvider / servicesListProvider)`. Each of those
// transitively `ref.watch(authProvider)`:
//   servicesListProvider → serviceRepositoryProvider → masterProfileProvider
//   → authProvider.
// Invalidating them from INSIDE the auth notifier records a back-edge that
// closes a dependency cycle. Riverpod's `_debugAssertCanDependOn` then throws
// `CircularDependencyError` — but ONLY under `kDebugMode`. Release builds strip
// the assert, so logout "worked" in release/AOT and threw in debug / `flutter
// test` (surfacing the "Вихід не вдався" SnackBar to the user).
//
// WHY THE OLD TESTS MISSED IT
// ---------------------------
// The previous auth_notifier tests stubbed serviceRepositoryProvider /
// masterProfileProvider with mocks that BROKE the `→ authProvider` watch edge —
// i.e. they engineered the cycle away, so the debug assert had no back-edge to
// fire on. This guard does the OPPOSITE: it wires the PRODUCTION provider graph
// and overrides ONLY the leaf data dependencies (auth repo, secure storage,
// master repo), so every intermediate provider keeps its real
// `ref.watch(authProvider)` edge. The cyclic edge is therefore live, and a
// reverted logout() (or any future cross-provider self-invalidation) re-trips
// the assert here — in a plain `flutter test`, no emulator needed.
//
// ---------------------------------------------------------------------------
// HOW TO ADD A ROW (this is the whole point — make "other places" cheap)
// ---------------------------------------------------------------------------
// Any notifier method that does cross-provider mutation from inside the graph
// (`ref.invalidate(otherProvider)`, `ref.refresh(otherProvider)`, or
// `ref.read(otherProvider.notifier).mutate()`) can close a cycle the same way
// logout() did. To cover one, append a single [_TeardownEntrypoint] row to the
// `_entrypoints` list below:
//
//   _TeardownEntrypoint(
//     description: 'someProvider.notifier.someMethod()',
//     // Subscribe (via container.listen) to every provider whose live
//     // subscription closes the watch cycle through the entrypoint's provider.
//     // This registers the cyclic edge so the debug assert has something to
//     // fire on. Return the subscriptions so the harness closes them.
//     subscribeCycleClosers: (container) => [
//       container.listen<Object?>(masterProfileProvider, (_, _) {},
//           fireImmediately: true),
//       container.listen<Object?>(servicesListProvider, (_, _) {},
//           fireImmediately: true),
//     ],
//     // Drive the graph to the state the method expects (e.g. authenticate),
//     // then invoke the method. MUST complete WITHOUT throwing.
//     run: (container) async {
//       await container.read(authProvider.future);
//       await container.read(someProvider.notifier).someMethod();
//     },
//     // Assert the graph settled correctly after the entrypoint ran.
//     settle: (container) {
//       expect(container.read(someProvider).value, equals(/* ... */));
//     },
//   ),
//
// The harness automatically: builds the real container with only leaf deps
// faked, runs `subscribeCycleClosers` (so the cyclic edge is registered), runs
// the entrypoint inside `expectLater(..., completes)` to fail on a
// CircularDependencyError, then runs `settle`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';

import '../helpers/fakes/fake_favorite_repository.dart';
import '../helpers/fakes/fake_master_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/fakes/fake_wishlist_repository.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

const _testUser = User(
  id: 'u1',
  email: 'test@example.com',
  role: UserRole.independentMaster,
  firstName: 'Test',
  lastName: 'User',
);
const _testTokens = AuthTokens(
  accessToken: 'access-123',
  refreshToken: 'refresh-456',
);

// ===========================================================================
// REUSABLE HARNESS
// ===========================================================================

/// Builds a REAL [ProviderContainer] with ONLY the leaf data dependencies
/// faked. Every intermediate provider (masterProfile → serviceRepository →
/// servicesList) stays production-real so its `ref.watch(authProvider)` edge is
/// registered — that edge is what closes the cycle the bug depended on.
///
/// [authRepo] / [storage] are the auth leaf deps; the master-repo leaf is faked
/// so masterProfileProvider builds for real (and thus watches authProvider)
/// without touching Dio or a platform channel.
ProviderContainer _buildRealGraph({
  required AuthRepository authRepo,
  required FakeSecureStorage storage,
  // Additional LEAF overrides a specific entrypoint needs (e.g. a favorite/
  // wishlist repository fake) — never an intermediate provider that carries a
  // watch edge, or the cyclic edge under test would be engineered away (see
  // the file header's "WHY THE OLD TESTS MISSED IT").
  List<Object> extraOverrides = const <Object>[],
}) {
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      // Leaf data deps only — break NO intermediate watch edge.
      authRepositoryProvider.overrideWith((_) => authRepo),
      secureStorageProvider.overrideWith((_) => storage),
      masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
      ...extraOverrides,
    ].cast(),
  );
  addTearDown(container.dispose);
  return container;
}

/// A teardown / cross-provider-mutation entrypoint to guard. See the file
/// header for how to add one.
class _TeardownEntrypoint {
  const _TeardownEntrypoint({
    required this.description,
    required this.subscribeCycleClosers,
    required this.run,
    required this.settle,
    this.extraOverrides = const <Object>[],
  });

  /// Human label for the test name.
  final String description;

  /// Extra LEAF overrides this entrypoint's graph needs (e.g. a repository
  /// fake) beyond the shared auth/master leaves `_buildRealGraph` always
  /// applies. Must never override an INTERMEDIATE provider that carries the
  /// watch edge under test.
  final List<Object> extraOverrides;

  /// Subscribes (via `container.listen`) to every provider whose live
  /// subscription closes the watch cycle through the entrypoint's provider, so
  /// the cyclic edge is registered before the entrypoint runs. Returns the
  /// subscriptions so the harness can close them on teardown.
  ///
  /// A closure (rather than a typed provider list) keeps this version-proof:
  /// `ProviderListenable` is not re-exported through `flutter_riverpod`'s
  /// public barrel, but `container.listen` is.
  final List<ProviderSubscription<Object?>> Function(
    ProviderContainer container,
  )
  subscribeCycleClosers;

  /// Drives the graph to the expected pre-state, then invokes the entrypoint.
  /// Must complete WITHOUT throwing (no CircularDependencyError).
  final Future<void> Function(ProviderContainer container) run;

  /// Asserts the graph settled to the correct state after [run].
  final void Function(ProviderContainer container) settle;
}

// ===========================================================================
// REGISTRY — one row per teardown / cross-provider-mutation entrypoint.
// ===========================================================================

final List<_TeardownEntrypoint> _entrypoints = <_TeardownEntrypoint>[
  // -------------------------------------------------------------------------
  // authProvider.notifier.logout() — the original offender.
  //
  // logout() flips auth → Unauthenticated. masterProfile / serviceRepository /
  // servicesList all watch authProvider, so subscribing to them here registers
  // the exact cyclic edge a reverted `ref.invalidate(...)` would close. The
  // method must complete WITHOUT throwing CircularDependencyError, and the
  // watch cascade must settle the session to Unauthenticated.
  // -------------------------------------------------------------------------
  _TeardownEntrypoint(
    description: 'authProvider.notifier.logout()',
    subscribeCycleClosers: (container) => <ProviderSubscription<Object?>>[
      container.listen<Object?>(
        masterProfileProvider,
        (_, _) {},
        fireImmediately: true,
      ),
      container.listen<Object?>(
        serviceRepositoryProvider,
        (_, _) {},
        fireImmediately: true,
      ),
      container.listen<Object?>(
        servicesListProvider,
        (_, _) {},
        fireImmediately: true,
      ),
    ],
    run: (container) async {
      // Authenticate first so the cycle-closer providers build around a real
      // session (masterProfile resolves a non-empty id → serviceRepository →
      // servicesList all watch authProvider).
      await container.read(authProvider.future);
      await container.read(authProvider.notifier).logout();
    },
    settle: (container) {
      expect(
        container.read(authProvider).value,
        equals(const AuthSession.unauthenticated()),
        reason:
            'logout() must settle the session to Unauthenticated via the '
            'auth-watch cascade — no manual invalidation, no cycle.',
      );
    },
  ),

  // -------------------------------------------------------------------------
  // favoriteToggleProvider.notifier.toggle() — Phase 240 fix.
  //
  // A successful SERVICE *add* now `ref.invalidate(wishlistProvider)`s (see
  // `favorite_toggle_notifier.dart`'s file header). `wishlistProvider` never
  // watches `favoriteToggleProvider` back (its `build()` only watches
  // `wishlistRepositoryProvider`; `removeService()` only `ref.read`s the
  // toggle notifier, which records no watch edge) — so there is no back-edge
  // and no cycle. This entrypoint proves that on the REAL graph rather than
  // by code-reading alone: subscribing to `wishlistProvider` registers it as
  // a live listener, then `toggle()` must complete without
  // `CircularDependencyError`.
  // -------------------------------------------------------------------------
  _TeardownEntrypoint(
    description:
        'favoriteToggleProvider.notifier.toggle() (SERVICE add → '
        'wishlistProvider invalidate)',
    extraOverrides: <Object>[
      favoriteRepositoryProvider.overrideWithValue(FakeFavoriteRepository()),
      wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
    ],
    subscribeCycleClosers: (container) => <ProviderSubscription<Object?>>[
      container.listen<Object?>(
        wishlistProvider,
        (_, _) {},
        fireImmediately: true,
      ),
    ],
    run: (container) async {
      await container.read(authProvider.future);
      await container
          .read(favoriteToggleProvider.notifier)
          .toggle(
            const FavoriteTarget(type: FavoriteTargetType.service, id: 'svc-1'),
          );
    },
    settle: (container) {
      final FavoriteEntry? entry = container.read(
        favoriteToggleProvider,
      )[const FavoriteTarget(type: FavoriteTargetType.service, id: 'svc-1')];
      expect(
        entry?.isFavorite,
        isTrue,
        reason:
            'toggle() must settle the target favorited via the normal '
            'optimistic-success path — no manual invalidation of ITSELF, no '
            'cycle.',
      );
    },
  ),
];

void main() {
  setUpAll(() {
    registerFallbackValue(UserRole.independentMaster);
  });

  // A pre-authenticated auth repo + storage: cold-start restore succeeds so the
  // graph lands Authenticated before each entrypoint runs.
  ({_MockAuthRepository repo, FakeSecureStorage storage}) freshAuthDeps() {
    final repo = _MockAuthRepository();
    final storage = FakeSecureStorage();
    storage.writeRefreshToken('stored-refresh'); // sync under the hood
    when(
      () => repo.refresh('stored-refresh'),
    ).thenAnswer((_) async => _testTokens);
    when(() => repo.me()).thenAnswer((_) async => _testUser);
    when(() => repo.logout()).thenAnswer((_) async {});
    return (repo: repo, storage: storage);
  }

  group('provider-graph cycle guard', () {
    for (final entry in _entrypoints) {
      test(
        '${entry.description}: completes without CircularDependencyError on the '
        'real cyclic graph',
        () async {
          final deps = freshAuthDeps();
          final container = _buildRealGraph(
            authRepo: deps.repo,
            storage: deps.storage,
            extraOverrides: entry.extraOverrides,
          );

          // Subscribe to every cycle-closing provider so its real
          // `ref.watch(authProvider)` edge is registered BEFORE the entrypoint
          // runs. Without these live subscriptions the intermediate providers
          // are never built, the back-edge never exists, and the assert can't
          // fire — exactly the hole the old stubbed tests fell into.
          for (final sub in entry.subscribeCycleClosers(container)) {
            addTearDown(sub.close);
          }

          // The entrypoint MUST complete without throwing. A reverted
          // logout() (cross-provider self-invalidation re-introduced) throws
          // CircularDependencyError here in the debug `flutter test` VM.
          await expectLater(
            entry.run(container),
            completes,
            reason:
                '${entry.description} must not throw CircularDependencyError '
                'on the real provider graph (release strips the assert, debug '
                'throws — this is the divergence we guard).',
          );

          entry.settle(container);
        },
      );
    }
  });
}
