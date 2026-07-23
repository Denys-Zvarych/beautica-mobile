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
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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
  // build() delegates straight to repository.listMyServices() with no guard.
  // When that future throws a Failure, the AsyncNotifier must surface the error
  // as AsyncError carrying the original Failure — NOT crash and NOT swallow it.

  group('ServicesList.build (error path)', () {
    late _MockServiceRepository repo;

    setUp(() {
      repo = _MockServiceRepository();
    });

    test('build surfaces AsyncError when listMyServices throws', () async {
      const failure = ServerFailure(statusCode: 500);
      when(() => repo.listMyServices()).thenThrow(failure);

      final container = _makeContainer(repo);

      // Trigger the build and let the (rejected) future settle.
      container.read(servicesListProvider);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(servicesListProvider);
      expect(state.hasError, isTrue);
      expect(state.error, same(failure));
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
}
