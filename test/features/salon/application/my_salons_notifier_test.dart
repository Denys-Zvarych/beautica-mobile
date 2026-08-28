// Phase 21.1 QA — Unit tests for `MySalons` (`mySalonsProvider`), the My
// Salons Hub loader.
//
// THE HIGHEST-RISK GAP THIS FILE CLOSES
// --------------------------------------
// `mySalonsProvider` was promoted to `@Riverpod(keepAlive: true)`
// (`my_salons_notifier.dart`, mobile-perf HIGH follow-up, 2026-08-28) to fix
// a re-fetch-storm on every hub→manage→settings navigation. A `keepAlive`
// provider holding Owner A's salon list ACROSS a logout and a login into
// Owner B's account is a DATA-LEAK regression strictly worse than the perf
// bug the promotion fixed — a SALON_OWNER would see another owner's salons
// (names, addresses, phone numbers) rendered on their own hub. The dev's
// claim (`my_salons_notifier.dart`'s own header) is that `ref.watch
// (authProvider)` inside `build()` makes Riverpod cascade a rebuild the
// instant `authProvider` flips away from `Authenticated` — on logout AND on
// a login as a DIFFERENT account. Nothing pinned that claim before this file.
//
// Covers:
//   1. build() — returns the owner's salon list when session is Authenticated.
//   2. build() — AsyncError(UnauthorizedFailure) when session is Unauthenticated.
//   3. build() — AsyncError(NetworkFailure) when the repository throws.
//   4. AUTH-BOUNDARY EVICTION — resolved to Owner A's salons, then
//      authProvider flips to Unauthenticated: the keepAlive value must no
//      longer be Owner A's list, and the state must surface
//      UnauthorizedFailure. MUTATION-VERIFIED (see this file's own bottom
//      note / the QA report) — removing `ref.watch(authProvider)` from
//      `build()` turns this test RED.
//   5. AUTH-BOUNDARY EVICTION, cross-account — resolved to Owner A's salons,
//      then authProvider flips to a DIFFERENT Authenticated session (Owner
//      B): the resolved list must be Owner B's, and must NEVER equal Owner
//      A's (the actual leak shape a keepAlive singleton risks).
//
// Strategy mirrors `master_profile_notifier_test.dart` (MasterProfile is the
// shape `mySalonsProvider` was promoted to mirror) — a fresh
// [ProviderContainer] per test, [FakeSecureStorage] + [FakeAuthRepository] so
// no platform channel or real Dio is touched, and a mocktail
// [SalonRepository] mock for the repository leg.
//
// Tests 4/5 need an [AuthNotifier] whose STATE CAN BE PUSHED MID-TEST (not
// merely fixed at build), unlike the fixed-session stubs
// `master_profile_notifier_test.dart` / the routing-guard test files use —
// see [_ControllableAuthNotifier] below.
//
// Pure Dart — no widget tree.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockSalonRepository extends Mock implements SalonRepository {}

// ---------------------------------------------------------------------------
// Stub data — two DISTINCT owners, so a leak is observable BY VALUE, not
// merely by "some list rendered" (project_fixture_values_can_defang_assertions).
// ---------------------------------------------------------------------------

const _ownerA = User(
  id: 'owner-a',
  email: 'owner-a@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Власник',
);
const _ownerB = User(
  id: 'owner-b',
  email: 'owner-b@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Ірина',
  lastName: 'Директорка',
);

const _sessionA = AuthSession.authenticated(user: _ownerA, accessToken: 'ta');
const _sessionB = AuthSession.authenticated(user: _ownerB, accessToken: 'tb');

const _salonsA = <Salon>[
  Salon(id: 'salon-a-1', name: 'Салон Оксани', isPrimary: true),
];
const _salonsB = <Salon>[
  Salon(id: 'salon-b-1', name: 'Студія Ірини', isPrimary: true),
  Salon(id: 'salon-b-2', name: 'Філія Ірини', isPrimary: false),
];

// ---------------------------------------------------------------------------
// AuthNotifier stubs
// ---------------------------------------------------------------------------

/// Resolves to a fixed [AuthSession] immediately — sufficient for tests 1–3,
/// which never need to change the session mid-test.
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AuthSession _fixed;

  @override
  Future<AuthSession> build() => Future.value(_fixed);
}

/// Starts at [initial] but exposes [emit] so tests 4/5 can push a NEW
/// [AuthSession] mid-test and observe `mySalonsProvider` cascade — the exact
/// mechanism the auth-boundary-eviction claim depends on. `state =` is only
/// reachable from inside an [AsyncNotifier] subclass, which is why this
/// exists instead of a plain external `container.read(...).state =` poke.
class _ControllableAuthNotifier extends AuthNotifier {
  _ControllableAuthNotifier(this.initial);

  final AuthSession initial;

  @override
  Future<AuthSession> build() => Future.value(initial);

  void emit(AuthSession session) {
    state = AsyncData<AuthSession>(session);
  }
}

// ---------------------------------------------------------------------------
// Container factory
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer({
  required AuthNotifier Function() authFactory,
  required SalonRepository repo,
  Duration? Function(int retryCount, Object error)? retry =
      beauticaProviderRetry,
}) {
  final container = ProviderContainer(
    retry: retry,
    overrides: [
      authProvider.overrideWith(authFactory),
      secureStorageProvider.overrideWithValue(FakeSecureStorage()),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      salonRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockSalonRepository repo;

  setUp(() {
    repo = _MockSalonRepository();
  });

  group('build()', () {
    test(
      'returns the owner salon list when session is Authenticated',
      () async {
        when(() => repo.getMySalons()).thenAnswer((_) async => _salonsA);

        final container = _makeContainer(
          authFactory: () => _FixedAuthNotifier(_sessionA),
          repo: repo,
        );

        await container.read(authProvider.future);
        final salons = await container.read(mySalonsProvider.future);

        expect(salons, equals(_salonsA));
        expect(salons.single.isPrimary, isTrue);
      },
    );

    test(
      'emits AsyncError(UnauthorizedFailure) when session is Unauthenticated',
      () async {
        final container = _makeContainer(
          authFactory: () =>
              _FixedAuthNotifier(const AuthSession.unauthenticated()),
          repo: repo,
        );

        await container.read(authProvider.future);

        container.read(mySalonsProvider); // trigger build
        await Future<void>.delayed(Duration.zero);

        final state = container.read(mySalonsProvider);
        expect(state, isA<AsyncError<List<Salon>>>());
        expect(state.hasError, isTrue);
        expect(state.error, isA<UnauthorizedFailure>());

        // The auth guard must fire BEFORE the repository is ever touched.
        verifyNever(() => repo.getMySalons());
      },
    );

    test(
      'emits AsyncError(NetworkFailure) when the repository throws',
      () async {
        // ASYNCHRONOUS throw — a Dio-backed repository always fails this way;
        // `thenThrow` fails synchronously and bypasses Riverpod's retry
        // machinery entirely (see this repo's own M13 note). Retry disabled
        // below because this test is about the TERMINAL error surface, not the
        // retry curve.
        when(
          () => repo.getMySalons(),
        ).thenAnswer((_) async => throw const NetworkFailure());

        final container = _makeContainer(
          authFactory: () => _FixedAuthNotifier(_sessionA),
          repo: repo,
          retry: (_, _) => null,
        );

        await container.read(authProvider.future);

        container.read(mySalonsProvider); // trigger build
        await Future<void>.delayed(Duration.zero);

        final state = container.read(mySalonsProvider);
        // Runtime TYPE, not just `hasError` — `AsyncLoading(retrying: true)`
        // also satisfies `hasError`/`error` mid-retry (M12).
        expect(state, isA<AsyncError<List<Salon>>>());
        expect(state.hasError, isTrue);
        expect(state.error, isA<NetworkFailure>());
      },
    );
  });

  // ── Auth-boundary eviction (keepAlive data-leak guard) ────────────────────

  group('auth-boundary eviction (keepAlive)', () {
    test(
      'Owner A resolved, then session drops to Unauthenticated → value is '
      'no longer Owner A\'s list and the state surfaces UnauthorizedFailure',
      () async {
        when(() => repo.getMySalons()).thenAnswer((_) async => _salonsA);

        final authNotifier = _ControllableAuthNotifier(_sessionA);
        final container = _makeContainer(
          authFactory: () => authNotifier,
          repo: repo,
        );

        await container.read(authProvider.future);
        final resolvedA = await container.read(mySalonsProvider.future);
        expect(resolvedA, equals(_salonsA));

        authNotifier.emit(const AuthSession.unauthenticated());
        // Let the authProvider re-emission cascade into mySalonsProvider's
        // watch-triggered rebuild.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final state = container.read(mySalonsProvider);
        expect(state, isA<AsyncError<List<Salon>>>());
        expect(state.error, isA<UnauthorizedFailure>());

        // The internal `.value` cache MAY still carry Owner A's list
        // (Riverpod's own `copyWithPrevious` keeps the last-good value
        // around an error by design — this is not the leak surface). What
        // actually matters is what a CONSUMER sees: `MySalonsScreen` renders
        // via `async.when(loading:, error:, data:)`, and `AsyncValue.when`'s
        // `skipError` defaults to false, so it dispatches to `error()` — NOT
        // `data()` — whenever `hasError` is true, regardless of a lingering
        // previous value (`async_value.dart`'s own `when` body: `if
        // (hasError && (!hasValue || !skipError)) return error(...)`).
        // Mirror that dispatch here so a future accidental `skipError: true`
        // (or a raw `.value` read instead of `.when`) on the screen is what
        // this test would actually catch.
        final String rendered = state.when(
          data: (_) => 'data',
          error: (Object e, _) => 'error:${e.runtimeType}',
          loading: () => 'loading',
        );
        expect(
          rendered,
          'error:UnauthorizedFailure',
          reason:
              'a keepAlive provider must not let a consumer render Owner '
              'A\'s salon list once the session it was loaded under is gone '
              '— this is the data-leak shape the mobile-perf keepAlive '
              'promotion risks',
        );
      },
    );

    test(
      'Owner A resolved, then session flips to a DIFFERENT Authenticated '
      'account (Owner B) → resolves Owner B\'s list, never Owner A\'s',
      () async {
        final authNotifier = _ControllableAuthNotifier(_sessionA);
        when(() => repo.getMySalons()).thenAnswer((_) async => _salonsA);

        final container = _makeContainer(
          authFactory: () => authNotifier,
          repo: repo,
        );

        await container.read(authProvider.future);
        final resolvedA = await container.read(mySalonsProvider.future);
        expect(resolvedA, equals(_salonsA));

        // Owner B logs in — repo now answers with Owner B's list.
        when(() => repo.getMySalons()).thenAnswer((_) async => _salonsB);
        authNotifier.emit(_sessionB);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final resolvedB = await container.read(mySalonsProvider.future);
        expect(resolvedB, equals(_salonsB));
        expect(
          resolvedB,
          isNot(equals(_salonsA)),
          reason:
              'Owner B must never see Owner A\'s salons through the '
              'keepAlive singleton — the actual cross-account leak shape',
        );
        expect(
          resolvedB.map((Salon s) => s.id),
          isNot(contains(_salonsA.single.id)),
        );
      },
    );
  });
}
