// Phase 13.5 — Unit tests for publicMasterProfileProvider (the parallel loader).
//
// The widget + E2E tiers prove the rendered profile; this tier pins the
// provider's CONTRACT in isolation: it loads the master detail + active services
// in PARALLEL through the two CLIENT-safe repositories, returns them as a record
// keyed on the masterId, and surfaces a repository failure as an AsyncError
// (mapped Failure) — never a raw error.
//
// Isolation: both reads are mocktail mocks injected via the public providers
// ([masterRepositoryProvider] + [publicServiceRepositoryProvider]); a fresh
// [ProviderContainer] is disposed per test (which also cancels the keepAlive TTL
// timer the provider arms, so no Timer leaks across tests).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockMasterRepository extends Mock implements MasterRepository {}

class _MockServiceRepository extends Mock implements ServiceRepository {}

/// Stub [AuthNotifier] — an authenticated CLIENT, no storage/network. The
/// provider under test `ref.watch(authProvider)` for auth-boundary eviction, so
/// the container must supply a settled session (otherwise the real notifier
/// would hit secure storage).
class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(
      id: 'client-1',
      email: 'client@beautica.ua',
      role: UserRole.client,
    ),
    accessToken: 'test-token',
  );
}

/// Same settled session as [_StubAuthNotifier], but a test can push a NEW
/// [AuthSession] afterwards — needed by the narrowed-watch pair at the bottom
/// of this file, which must tell a token-only re-emission apart from a real
/// identity change. `state =` is only reachable from inside an [AsyncNotifier]
/// subclass, hence this stub rather than an external poke.
class _ControllableAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(
      id: 'client-1',
      email: 'client@beautica.ua',
      role: UserRole.client,
    ),
    accessToken: 'test-token',
  );

  void emit(AuthSession session) => state = AsyncData<AuthSession>(session);
}

const String _kMasterId = 'master-1';

const _master = Master(
  id: _kMasterId,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  city: 'Київ',
  avgRating: 4.8,
  reviewCount: 47,
  type: MasterType.independentMaster,
  instagram: '@olena_nails',
);

const _services = <MasterService>[
  MasterService(
    id: 'svc-1',
    serviceDefId: 'def-1',
    name: 'Манікюр з покриттям',
    durationMinutes: 90,
    priceMin: 500,
    priceDisplay: '500 ₴',
    category: 'NAILS',
  ),
  MasterService(
    id: 'svc-2',
    serviceDefId: 'def-2',
    name: 'Дизайн нігтів',
    durationMinutes: 60,
    priceMin: 300,
    priceDisplay: 'від 300 ₴',
    category: 'NAILS',
  ),
];

void main() {
  late _MockMasterRepository masterRepo;
  late _MockServiceRepository serviceRepo;

  setUp(() {
    masterRepo = _MockMasterRepository();
    serviceRepo = _MockServiceRepository();
  });

  // [retry] defaults to the PRODUCTION predicate [beauticaProviderRetry] so
  // the container resolves error paths as the shipped app does; pass
  // `(_, _) => null` to disable retry outright.
  ProviderContainer makeContainer({
    Duration? Function(int, Object)? retry = beauticaProviderRetry,
  }) {
    final container = ProviderContainer(
      retry: retry,
      overrides: [
        authProvider.overrideWith(_StubAuthNotifier.new),
        masterRepositoryProvider.overrideWithValue(masterRepo),
        publicServiceRepositoryProvider.overrideWithValue(serviceRepo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Resolves the stubbed [authProvider] BEFORE the loader first builds so the
  /// auth-boundary `ref.watch(authProvider)` sees a settled session — otherwise
  /// the AsyncLoading→AsyncData transition would mark the loader dirty and
  /// re-run the parallel reads mid-flight (breaking the `.called(1)` assertion).
  Future<void> primeAuth(ProviderContainer container) =>
      container.read(authProvider.future);

  group('publicMasterProfile — happy path', () {
    test(
      'returns the (master, services) record keyed on the masterId',
      () async {
        when(
          () => masterRepo.getMasterById(_kMasterId),
        ).thenAnswer((_) async => _master);
        when(
          () => serviceRepo.getMasterServices(_kMasterId),
        ).thenAnswer((_) async => _services);

        final container = makeContainer();
        await primeAuth(container);

        final result = await container.read(
          publicMasterProfileProvider(_kMasterId).future,
        );

        expect(result.$1, _master);
        expect(result.$2, _services);
        expect(result.$2, hasLength(2));
      },
    );

    test(
      'reads BOTH the master detail and the services for the masterId',
      () async {
        when(
          () => masterRepo.getMasterById(_kMasterId),
        ).thenAnswer((_) async => _master);
        when(
          () => serviceRepo.getMasterServices(_kMasterId),
        ).thenAnswer((_) async => _services);

        final container = makeContainer();
        await primeAuth(container);
        await container.read(publicMasterProfileProvider(_kMasterId).future);

        verify(() => masterRepo.getMasterById(_kMasterId)).called(1);
        verify(() => serviceRepo.getMasterServices(_kMasterId)).called(1);
      },
    );
  });

  group('publicMasterProfile — failure propagation', () {
    // The provider loads both reads via the records `.wait` extension, which
    // wraps ANY failing future in a [ParallelWaitError]. The provider UNWRAPS
    // that wrapper and rethrows the underlying typed [Failure] (mobile-qa MEDIUM
    // fix), so PublicMasterProfileScreen's `e is Failure ? e : UnknownFailure`
    // branch renders the network-/server-SPECIFIC copy — never a generic
    // UnknownFailure. These tests pin that the TYPED failure propagates through
    // `.wait`, exactly what the screen's error branch receives at runtime.

    test('a failing master read propagates the typed NetworkFailure '
        '(unwrapped from ParallelWaitError)', () async {
      when(
        () => masterRepo.getMasterById(_kMasterId),
      ).thenAnswer((_) async => throw const NetworkFailure());
      when(
        () => serviceRepo.getMasterServices(_kMasterId),
      ).thenAnswer((_) async => _services);

      // retry disabled so the AsyncError settles deterministically (Riverpod 3.x
      // auto-retry would otherwise re-run the failing build).
      final container = makeContainer(retry: (_, _) => null);
      await primeAuth(container);

      await expectLater(
        container.read(publicMasterProfileProvider(_kMasterId).future),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test(
      'a failing services read propagates the typed ServerFailure',
      () async {
        when(
          () => masterRepo.getMasterById(_kMasterId),
        ).thenAnswer((_) async => _master);
        when(
          () => serviceRepo.getMasterServices(_kMasterId),
        ).thenAnswer((_) async => throw const ServerFailure(statusCode: 500));

        final container = makeContainer(retry: (_, _) => null);
        await primeAuth(container);

        await expectLater(
          container.read(publicMasterProfileProvider(_kMasterId).future),
          throwsA(isA<ServerFailure>()),
        );
      },
    );
  });

  // ── The authProvider watch is NARROWED to the user id ────────────────────
  //
  // mobile-perf LOW (2026-09-01). The auth-boundary watch at the top of this
  // loader used to be a bare `ref.watch(authProvider)`. Because the loader
  // holds a 5-minute `ref.keepAlive()` window, and
  // `AuthNotifier.setAccessToken` re-emits `Authenticated` with the SAME user
  // and a new accessToken on EVERY silent token refresh, an un-narrowed watch
  // threw away a live cache entry and refetched `GET /masters/{id}` +
  // `GET /masters/{id}/services` mid-scroll on each refresh.
  //
  // The pair: the token-only re-emission must be INERT, and a real identity
  // change must STILL rebuild — the session-flip eviction is the entire reason
  // this watch exists, and a `.select` returning a constant would silently
  // remove it while passing the first test.
  group('publicMasterProfile — narrowed authProvider watch', () {
    ProviderContainer makeControllableContainer(
      _ControllableAuthNotifier auth,
    ) {
      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: [
          authProvider.overrideWith(() => auth),
          masterRepositoryProvider.overrideWithValue(masterRepo),
          publicServiceRepositoryProvider.overrideWithValue(serviceRepo),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a silent token refresh (same user id, new accessToken) does NOT '
        'refetch the master or the services', () async {
      when(
        () => masterRepo.getMasterById(_kMasterId),
      ).thenAnswer((_) async => _master);
      when(
        () => serviceRepo.getMasterServices(_kMasterId),
      ).thenAnswer((_) async => _services);

      final auth = _ControllableAuthNotifier();
      final container = makeControllableContainer(auth);
      await container.read(authProvider.future);
      final sub = container.listen(
        publicMasterProfileProvider(_kMasterId),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(publicMasterProfileProvider(_kMasterId).future);
      verify(() => masterRepo.getMasterById(_kMasterId)).called(1);
      verify(() => serviceRepo.getMasterServices(_kMasterId)).called(1);

      // Exactly what `refresh_interceptor.dart` does after a 401 → refresh.
      container.read(authProvider.notifier).setAccessToken('token-rotated-2');
      await pumpEventQueue();

      verifyNever(() => masterRepo.getMasterById(any()));
      verifyNever(() => serviceRepo.getMasterServices(any()));
      expect(
        container.read(authProvider).value,
        isA<Authenticated>()
            .having(
              (Authenticated a) => a.accessToken,
              'accessToken',
              'token-rotated-2',
            )
            .having((Authenticated a) => a.user.id, 'user.id', 'client-1'),
        reason:
            'sanity: the session really did re-emit, with a NEW token and the '
            'SAME user — so the no-refetch assertions above are about the '
            '.select narrowing, not about setAccessToken having no-opped',
      );
    });

    test('a real identity change (different user id) DOES rebuild', () async {
      when(
        () => masterRepo.getMasterById(_kMasterId),
      ).thenAnswer((_) async => _master);
      when(
        () => serviceRepo.getMasterServices(_kMasterId),
      ).thenAnswer((_) async => _services);

      final auth = _ControllableAuthNotifier();
      final container = makeControllableContainer(auth);
      await container.read(authProvider.future);
      final sub = container.listen(
        publicMasterProfileProvider(_kMasterId),
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(publicMasterProfileProvider(_kMasterId).future);
      verify(() => masterRepo.getMasterById(_kMasterId)).called(1);
      verify(() => serviceRepo.getMasterServices(_kMasterId)).called(1);

      auth.emit(
        const AuthSession.authenticated(
          user: User(
            id: 'client-2',
            email: 'other@beautica.ua',
            role: UserRole.client,
          ),
          accessToken: 'test-token',
        ),
      );
      await pumpEventQueue();
      await container.read(publicMasterProfileProvider(_kMasterId).future);

      verify(() => masterRepo.getMasterById(_kMasterId)).called(1);
      verify(() => serviceRepo.getMasterServices(_kMasterId)).called(1);
    });
  });
}
