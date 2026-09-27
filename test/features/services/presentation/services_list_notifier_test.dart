// Phase 5.2 — Unit tests for ServicesListNotifier.refresh() concurrent guard.
//
// Covers three cases:
//   1. refresh() happy path — emits AsyncLoading then AsyncData.
//   2. concurrent guard — second call while first is in-flight is dropped;
//      repository.listMyServices() called exactly once.
//   3. guard resets after first call completes — second call proceeds;
//      repository.listMyServices() called exactly twice.
//
// Strategy:
//   Pure Dart — ProviderContainer + mocktail mock for ServiceRepository.
//   No widget tree. Completer-based stubs control in-flight timing.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ---------------------------------------------------------------------------
// Stub data
// ---------------------------------------------------------------------------

const _stubService = MasterService(
  id: 'svc-001',
  serviceDefId: 'def-001',
  name: 'Стрижка',
  durationMinutes: 45,
  priceMin: 750,
  priceDisplay: '750 ₴',
);

const _stubServiceList = <MasterService>[_stubService];

// ---------------------------------------------------------------------------
// Container factory
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer(_MockServiceRepository repo) {
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    // cycle-stub-ok: servicesListProvider is the unit under test and watches serviceRepositoryProvider as its DIRECT leaf data dep — stubbing the repo here is overriding the leaf, not breaking a cycle. No auth/logout cascade is exercised.
    overrides: [serviceRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ServicesListNotifier.refresh', () {
    late _MockServiceRepository repo;

    setUp(() {
      repo = _MockServiceRepository();
    });

    // ── 1. Happy path ─────────────────────────────────────────────────────────
    //
    // Stub listMyServices() to complete after a short delay so we can inspect
    // the intermediate AsyncLoading state. After await refresh() the state must
    // be AsyncData containing the stub list.

    test('refresh happy path — emits AsyncLoading then AsyncData', () async {
      // Initial build also calls listMyServices; stub it for the first call
      // (build) and second call (refresh) with the same response.
      when(
        () => repo.listMyServices(),
      ).thenAnswer((_) async => _stubServiceList);

      final container = _makeContainer(repo);

      // Trigger the initial build by reading the provider.
      container.read(servicesListProvider);

      // Wait for the initial build to settle so we start from AsyncData.
      await Future<void>.delayed(Duration.zero);
      expect(container.read(servicesListProvider).hasValue, isTrue);

      // Now stub a slightly-delayed fetch for the refresh call.
      when(() => repo.listMyServices()).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return _stubServiceList;
      });

      // Call refresh but do not await yet — check loading state first.
      final refreshFuture = container
          .read(servicesListProvider.notifier)
          .refresh();

      // Immediately after calling refresh() the guard sets AsyncLoading.
      expect(container.read(servicesListProvider).isLoading, isTrue);

      // Await completion.
      await refreshFuture;

      final state = container.read(servicesListProvider);
      expect(state.hasValue, isTrue);
      expect(state.value, _stubServiceList);
    });

    // ── 2. Concurrent guard — second call dropped while first in-flight ───────
    //
    // Strategy: two sequential refreshes where the first completes before the
    // second starts — the second should fire. Then one more call where we verify
    // that calling refresh() a second time while the first is pending (Completer
    // never completes) does NOT call listMyServices again.
    //
    // Because Riverpod's ProviderContainer doesn't expose `_refreshing` directly,
    // the guard is tested via call counts: if the second refresh() is dropped,
    // listMyServices is called exactly once for the refresh round (not twice).

    test('concurrent guard drops second call while first is in-flight '
        '— listMyServices called exactly once for refresh', () async {
      // Completer for the in-flight refresh stub — never completes during test.
      final refreshCompleter = Completer<List<MasterService>>();

      // Initial build + first (completed) refresh both resolve immediately.
      when(
        () => repo.listMyServices(),
      ).thenAnswer((_) async => _stubServiceList);

      final container = _makeContainer(repo);

      // Trigger and settle the initial build.
      container.read(servicesListProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(servicesListProvider).hasValue, isTrue);

      // Drain the initial-build call so subsequent verifies count only refreshes.
      verify(() => repo.listMyServices()).called(1);

      // Now stub to a never-completing future to simulate an in-flight refresh.
      when(
        () => repo.listMyServices(),
      ).thenAnswer((_) => refreshCompleter.future);

      // Start first refresh — it will never complete (Completer is not resolved).
      // Do NOT await so _refreshing stays true throughout.
      final firstRefreshFuture = container
          .read(servicesListProvider.notifier)
          .refresh();

      // Start second refresh — must be dropped by the guard because _refreshing
      // is already true from the first call. This awaits immediately (early return).
      await container.read(servicesListProvider.notifier).refresh();

      // Resolve the first refresh for clean teardown.
      refreshCompleter.complete(_stubServiceList);
      await firstRefreshFuture;

      // listMyServices should have been called exactly once for the refresh round
      // (the second concurrent call was dropped by the _refreshing guard).
      verify(() => repo.listMyServices()).called(1);
    });

    // ── 3. Guard resets after first call completes — second call proceeds ─────
    //
    // After the first refresh() completes, the internal `_refreshing` flag
    // resets to false. A second refresh() call must go through and fire
    // listMyServices() again.

    test('guard resets after first call completes '
        '— second refresh fires listMyServices', () async {
      when(
        () => repo.listMyServices(),
      ).thenAnswer((_) async => _stubServiceList);

      final container = _makeContainer(repo);

      // Trigger the initial build and wait for it to settle.
      container.read(servicesListProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(servicesListProvider).hasValue, isTrue);

      // Consume the initial-build call so verify() below counts only refreshes.
      verify(() => repo.listMyServices()).called(1);

      // First refresh — completes successfully; guard resets in finally block.
      await container.read(servicesListProvider.notifier).refresh();

      // Second refresh — guard must have reset after the first completed, so
      // this call also goes through and fires listMyServices() again.
      await container.read(servicesListProvider.notifier).refresh();

      // Two separate refresh() calls should each fire listMyServices() once;
      // total post-build count = 2.
      verify(() => repo.listMyServices()).called(2);
    });
  });

  // ── build() error path ──────────────────────────────────────────────────────
  //
  // Since N2 (2026-09-10) build() no longer calls the repository itself — it
  // watches `masterServiceCatalogProvider.future`, the app's single
  // `GET /independent-masters/me/services`. A Failure thrown by the repository
  // must still arrive HERE as AsyncError carrying the ORIGINAL Failure: the
  // wrapper reads `.future` (never `.value`) precisely so an errored upstream
  // surfaces as an error rather than as retained previous-account data.
  //
  // These tests hold a LIVE SUBSCRIPTION, which the pre-N2 versions did not
  // need. That is not scaffolding — it is the contract. `_makeContainer`
  // installs `beauticaProviderRetry`, and an unlistened wrapper never observes
  // its upstream settling: the state stays AsyncLoading and `.future` stays
  // PENDING FOREVER. (Verified 2026-09-10 to be equally true of the direct-fetch
  // `masterServiceCatalogProvider` read the same way, so this is a Riverpod
  // retry-policy property and not something the wrap introduced. Every
  // production reader either watches the provider or reads it right after an
  // invalidation that marks it dirty.)

  group('ServicesList.build (error path)', () {
    late _MockServiceRepository repo;

    setUp(() {
      repo = _MockServiceRepository();
    });

    // MUTATION (2026-09-10): changed `ServicesList.build` to
    // `ref.watch(masterServiceCatalogProvider).value` (the `.value` read the
    // catalogue provider's header forbids) → this test FAILED: the wrapper
    // reported AsyncData(null-ish) instead of the failure, which is exactly the
    // retained-previous-account shape. Restored to `.future`.
    test('build surfaces the upstream Failure as AsyncError', () async {
      const failure = ServerFailure(statusCode: 400);
      when(() => repo.listMyServices()).thenThrow(failure);

      final container = _makeContainer(repo);
      container.listen<Object?>(
        servicesListProvider,
        (_, _) {},
        fireImmediately: true,
      );

      // A 400 is NOT transient (`isTransientFailure` only accepts 5xx), so the
      // retry policy declines and the error settles in one hop — no sleeping on
      // a backoff timer to make this deterministic.
      await pumpEventQueue();

      final state = container.read(servicesListProvider);
      expect(state.hasError, isTrue);
      expect(state.error, same(failure));
    });

    // The N2 behaviour change worth pinning on its own: a TRANSIENT failure is
    // retried by the UPSTREAM now, so the wrapper reports AsyncLoading while
    // that is in flight instead of flashing an error state that the retry is
    // about to replace. `services_list_screen.dart` renders `.when(error:)` for
    // any AsyncError, so pre-N2 a retried 500 painted the full error body for
    // one backoff window. The error must still arrive once retries are spent.
    test('a TRANSIENT upstream failure shows loading while it retries, then '
        'the error', () async {
      const failure = ServerFailure(statusCode: 500);
      when(() => repo.listMyServices()).thenThrow(failure);

      final container = _makeContainer(repo);
      container.listen<Object?>(
        servicesListProvider,
        (_, _) {},
        fireImmediately: true,
      );

      await pumpEventQueue();
      final mid = container.read(servicesListProvider);
      expect(
        mid.hasError,
        isFalse,
        reason:
            'the upstream is retrying — the list must not paint an error body '
            'that is about to be replaced',
      );
      expect(mid.isLoading, isTrue);

      // Retries exhaust (`_kMaxTransientRetries == 1`); the future then rejects
      // with the ORIGINAL failure. Awaiting the rejection is what makes this
      // deterministic — no fixed sleep on the backoff.
      await expectLater(
        container.read(servicesListProvider.future),
        throwsA(same(failure)),
      );
      expect(container.read(servicesListProvider).error, same(failure));
      verify(() => repo.listMyServices()).called(2);
    });
  });

  // ── refresh() error path ────────────────────────────────────────────────────
  //
  // refresh() wraps the re-fetch in AsyncValue.guard, so a thrown Failure becomes
  // AsyncError on the provider state and refresh() ITSELF never throws (callers
  // such as RefreshIndicator await it without a try/catch). The _refreshing guard
  // resets in the finally block even on failure, so a subsequent refresh proceeds.

  group('ServicesList.refresh (error path)', () {
    late _MockServiceRepository repo;

    setUp(() {
      repo = _MockServiceRepository();
    });

    test(
      'refresh maps a thrown Failure to AsyncError without rethrowing',
      () async {
        // Initial build succeeds so we start from AsyncData.
        when(
          () => repo.listMyServices(),
        ).thenAnswer((_) async => _stubServiceList);

        final container = _makeContainer(repo);
        container.read(servicesListProvider);
        await Future<void>.delayed(Duration.zero);
        expect(container.read(servicesListProvider).hasValue, isTrue);

        // Now the refresh fetch fails.
        const failure = NetworkFailure();
        when(() => repo.listMyServices()).thenThrow(failure);

        // refresh() must complete normally (AsyncValue.guard catches the throw);
        // expectLater on the returned future asserts it does NOT reject.
        await expectLater(
          container.read(servicesListProvider.notifier).refresh(),
          completes,
        );

        final state = container.read(servicesListProvider);
        expect(state.hasError, isTrue);
        expect(state.error, same(failure));
      },
    );

    test(
      'guard resets after a failed refresh so the next refresh proceeds',
      () async {
        // Initial build succeeds.
        when(
          () => repo.listMyServices(),
        ).thenAnswer((_) async => _stubServiceList);

        final container = _makeContainer(repo);
        container.read(servicesListProvider);
        await Future<void>.delayed(Duration.zero);
        expect(container.read(servicesListProvider).hasValue, isTrue);

        // Drain the initial-build call so verify() below counts only refreshes.
        verify(() => repo.listMyServices()).called(1);

        // First refresh fails — _refreshing must reset in the finally block.
        when(() => repo.listMyServices()).thenThrow(const ServerFailure());
        await container.read(servicesListProvider.notifier).refresh();
        expect(container.read(servicesListProvider).hasError, isTrue);

        // Second refresh now succeeds — proves the guard did NOT stay latched
        // after the failure (it would have been dropped if _refreshing were stuck).
        when(
          () => repo.listMyServices(),
        ).thenAnswer((_) async => _stubServiceList);
        await container.read(servicesListProvider.notifier).refresh();

        final state = container.read(servicesListProvider);
        expect(state.hasValue, isTrue);
        expect(state.value, _stubServiceList);

        // One failed + one successful refresh = two post-build calls.
        verify(() => repo.listMyServices()).called(2);
      },
    );
  });

  _identityWatchTests();
}

// ── build() session-identity watch ──────────────────────────────────────────
//
// mobile-security MEDIUM (2026-09-10), regression guard for the weakening the
// N2 wrap introduced.
//
// Post-N2 `build()` reaches the repository only through
// `masterServiceCatalogProvider.future`. That channel COALESCES: riverpod
// publishes a new future only `if (_futureCompleter == null)`
// (riverpod-3.1.0 `element.dart:81`). So while an upstream fetch is IN FLIGHT
// an identity change rebuilds the upstream and publishes NO new future — and
// without an explicit auth watch in `build()` the wrapper would never re-run,
// leaving a `refresh()`-written `AsyncData` of the PREVIOUS account's list
// live and renderable into the NEW session. Pre-N2 this was unreachable
// because `build()` watched `serviceRepositoryProvider`, which IS rebuilt on
// the auth boundary.
//
// The test is deliberately built so the upstream future is still PENDING at
// the moment the identity changes (`upstream` is a Completer this test never
// completes before asserting) — otherwise the settle would repair the state on
// its own and the assertion would prove nothing.

class _MutableAuthNotifier extends AuthNotifier {
  _MutableAuthNotifier(this._initial);

  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;

  void setSession(AuthSession session) =>
      state = AsyncData<AuthSession>(session);
}

const User _master1 = User(
  id: 'master-1',
  email: 'master1@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Оля',
  lastName: 'Коваль',
);

const User _master2 = User(
  id: 'master-2',
  email: 'master2@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Ірина',
  lastName: 'Бондар',
);

const _master1Service = MasterService(
  id: 'svc-m1',
  serviceDefId: 'def-m1',
  name: 'Манікюр майстра 1',
  durationMinutes: 60,
  priceMin: 500,
);

void _identityWatchTests() {
  group('ServicesList.build (session identity)', () {
    late _MockServiceRepository repo;

    setUp(() {
      repo = _MockServiceRepository();
    });

    test('an identity change during an IN-FLIGHT upstream fetch discards the '
        'previous account\'s refresh()-written list', () async {
      // 1. The upstream's very first fetch never settles during this test.
      //    This is what keeps `masterServiceCatalogProvider`'s completer
      //    outstanding, so a later rebuild publishes NO new `.future`.
      final upstream = Completer<List<MasterService>>();
      when(repo.listMyServices).thenAnswer((_) => upstream.future);

      final auth = _MutableAuthNotifier(
        const AuthSession.authenticated(user: _master1, accessToken: 'token-1'),
      );
      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: <Object>[
          // cycle-stub-ok: servicesListProvider is the unit under test and the repository is its LEAF data dep; authProvider is overridden with a real AuthNotifier subclass, so the auth -> repository -> catalogue -> list edge this test exercises is the REAL graph, not a stubbed-out cycle.
          serviceRepositoryProvider.overrideWithValue(repo),
          authProvider.overrideWith(() => auth),
        ].cast(),
      );
      addTearDown(container.dispose);
      await container.read(authProvider.future);

      // A live subscription is the contract for this wrapper — an unlistened
      // wrapper never observes its upstream at all (see the build() error-path
      // group's header).
      container.listen<Object?>(servicesListProvider, (_, _) {});
      await pumpEventQueue();
      expect(
        container.read(servicesListProvider).isLoading,
        isTrue,
        reason: 'the upstream fetch is in flight, so the wrapper is loading',
      );

      // 2. Pull-to-refresh lands master-1's list by hand while that upstream
      //    fetch is STILL pending. This is the state the hazard hides in.
      when(
        repo.listMyServices,
      ).thenAnswer((_) async => const <MasterService>[_master1Service]);
      await container.read(servicesListProvider.notifier).refresh();
      expect(
        container.read(servicesListProvider).asData?.value,
        const <MasterService>[_master1Service],
        reason: 'precondition: master-1\'s list is renderable',
      );

      // 3. NON-VACUITY: the upstream future the wrapper's build() is awaiting
      //    must still be pending, or the identity change would be repaired by
      //    the settle rather than by the watch under test.
      expect(
        upstream.isCompleted,
        isFalse,
        reason:
            'the coalescing window only exists while the upstream completer '
            'is outstanding — if this future has settled the test proves '
            'nothing',
      );

      // 4. Log out, log in as master-2. Keep every subsequent fetch pending
      //    too, so nothing can settle master-2 data into place and mask a
      //    surviving master-1 list.
      final afterIdentity = Completer<List<MasterService>>();
      when(repo.listMyServices).thenAnswer((_) => afterIdentity.future);
      auth.setSession(const AuthSession.unauthenticated());
      auth.setSession(
        const AuthSession.authenticated(user: _master2, accessToken: 'token-2'),
      );
      await pumpEventQueue();

      // Still pending — the window never closed on its own.
      expect(upstream.isCompleted, isFalse);
      expect(afterIdentity.isCompleted, isFalse);

      // 5. Master-1's catalogue must no longer be renderable. `asData` is the
      //    right probe: `.value` deliberately still carries the retained list
      //    in AsyncLoading/AsyncError (riverpod re-attaches it in
      //    `copyWithPrevious`), which is exactly why every consumer reads
      //    `asData?.value` / `.when`.
      final state = container.read(servicesListProvider);
      expect(
        state.asData,
        isNull,
        reason:
            'the auth boundary must re-run build(); a hand-set AsyncData from '
            'master-1 surviving into master-2\'s session is the leak',
      );
      expect(
        state.asData?.value.any(
          (MasterService s) => s.name == _master1Service.name,
        ),
        isNot(isTrue),
        reason: 'master-1 service names must not be renderable for master-2',
      );

      // Drain for a clean teardown.
      upstream.complete(const <MasterService>[]);
      afterIdentity.complete(const <MasterService>[]);
      await pumpEventQueue();
    });

    // Counterpart to the test above: the identity watch must be NARROWED.
    // `Authenticated`'s freezed equality includes `accessToken`, so a bare
    // `ref.watch(authProvider)` re-runs `build()` on every silent token
    // refresh — and re-running `build()` re-enters `handleFuture`, which
    // publishes a transient `AsyncLoading` before the (already-complete)
    // future resolves. On «Мої послуги» that is a spinner flash over a
    // populated list, for the screen's whole session lifetime. Asserting only
    // `verifyNever(listMyServices)` would NOT catch it (the refetch is deduped
    // by the untouched upstream cache), so this test asserts on the EMISSIONS.
    test(
      'a silent token refresh for the SAME account emits nothing at all '
      '— the identity watch is narrowed to the user id, not the session',
      () async {
        when(
          repo.listMyServices,
        ).thenAnswer((_) async => const <MasterService>[_master1Service]);

        final auth = _MutableAuthNotifier(
          const AuthSession.authenticated(
            user: _master1,
            accessToken: 'token-1',
          ),
        );
        final container = ProviderContainer(
          retry: beauticaProviderRetry,
          overrides: <Object>[
            // cycle-stub-ok: servicesListProvider is the unit under test and the repository is its LEAF data dep; authProvider is overridden with a real AuthNotifier subclass, so the auth -> repository -> catalogue -> list edge this test exercises is the REAL graph, not a stubbed-out cycle.
            serviceRepositoryProvider.overrideWithValue(repo),
            authProvider.overrideWith(() => auth),
          ].cast(),
        );
        addTearDown(container.dispose);
        await container.read(authProvider.future);

        final emissions = <AsyncValue<List<MasterService>>>[];
        container.listen<AsyncValue<List<MasterService>>>(
          servicesListProvider,
          (_, AsyncValue<List<MasterService>> next) => emissions.add(next),
        );
        await pumpEventQueue();
        expect(container.read(servicesListProvider).hasValue, isTrue);
        verify(repo.listMyServices).called(1);

        // Everything up to here is setup; only what follows the token refresh
        // is under test.
        emissions.clear();

        // Same user, new access token — `AuthNotifier.setAccessToken`'s shape.
        auth.setSession(
          const AuthSession.authenticated(
            user: _master1,
            accessToken: 'token-2',
          ),
        );
        await pumpEventQueue();

        expect(
          emissions,
          isEmpty,
          reason:
              'a same-id session change must not re-run build(); an un-narrowed '
              'watch republishes AsyncLoading and flashes the spinner over a '
              'populated list on every silent token refresh',
        );
        verifyNever(repo.listMyServices);
        expect(
          container.read(servicesListProvider).asData?.value,
          const <MasterService>[_master1Service],
        );
      },
    );
  });
}
