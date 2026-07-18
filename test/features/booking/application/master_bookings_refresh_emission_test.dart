// Phase 7.1/7.6 — perf P3: `MasterBookingsNotifier.refresh()` must NOT emit a
// value-less `AsyncLoading`.
//
// WHY THIS FILE EXISTS (mobile-qa, G2 of the Phase 7.2/7.6 audit)
// ---------------------------------------------------------------
// `master_bookings_notifier_test.dart`'s `refresh re-fetches page 0` asserts a
// CALL COUNT and nothing else. Every emission-level property of the P3 fix is
// therefore unpinned — the fix is one line from regressing, and the regression
// is invisible to every existing test:
//
//   Re-adding `state = const AsyncLoading();` at the top of `refresh()` makes
//   the screen's `async.when(loading: …)` swap the populated card list for
//   `BookingsSkeleton` mid-gesture, underneath a `RefreshIndicator` whose whole
//   purpose is keeping the content on screen. Call counts do not move. The
//   existing suite stays green.
//
// This file pins the four properties the P3 fix actually claims, each stated as
// an observable emission rather than as an implementation detail:
//
//   (a) a refresh never emits a state that has lost its value;
//   (b) a FAILED refresh still surfaces `hasError` — "keep the content" must
//       not become "swallow the failure";
//   (c) the FIRST load DOES emit a value-less loading state (the fix must not
//       have broken genuine initial loading — the skeleton is correct there);
//   (d) while a refresh is IN FLIGHT the state is still `AsyncData` carrying
//       the OLD list — this is the exact property `RefreshIndicator` relies on,
//       and it is not implied by (a).
//
// The repository is driven by an explicit `Completer` rather than by
// `Future.value`, so the in-flight window in (d) is genuinely observable
// instead of being collapsed by the microtask queue.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/application/master_bookings_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/master_bookings_query.dart';
import 'package:beautica_mobile/features/booking/domain/master_bookings_state.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

Booking _booking(String id) => Booking(
  id: id,
  masterId: 'master-1',
  masterFirstName: 'Оля',
  masterLastName: 'Коваль',
  masterType: 'INDEPENDENT_MASTER',
  clientId: 'c-$id',
  clientFirstName: 'Олена',
  clientLastName: 'Ковальчук',
  serviceId: 'service-1',
  serviceName: 'Манікюр',
  durationMinutes: 60,
  price: 500,
  startAt: DateTime.utc(2026, 7, 20, 12),
  endAt: DateTime.utc(2026, 7, 20, 13),
  status: BookingStatus.confirmed,
  canReview: false,
);

PageResponse<Booking> _page(List<Booking> items) => PageResponse<Booking>(
  items: items,
  page: 0,
  totalPages: 1,
  totalElements: items.length,
);

void main() {
  setUpAll(() {
    registerFallbackValue(<BookingStatus>{});
    registerFallbackValue(BookingSort.newest);
  });

  late _MockBookingRepository repo;
  final MasterBookingsQuery query = MasterBookingsQuery.of();

  setUp(() {
    repo = _MockBookingRepository();
  });

  /// Every `getMyBookings` call is answered by the NEXT completer handed out by
  /// the returned factory, so a test controls exactly when each fetch resolves.
  ///
  /// The factory AWAITS the call rather than assuming it has already happened —
  /// `AsyncValue.guard` reaches the repository a variable number of microtasks
  /// in, and a fixed `delayed(Duration.zero)` was a race.
  Future<Completer<PageResponse<Booking>>> Function() gatedRepo() {
    final List<Completer<PageResponse<Booking>>> gates =
        <Completer<PageResponse<Booking>>>[];
    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        sort: any(named: 'sort'),
        page: any(named: 'page'),
      ),
    ).thenAnswer((_) {
      final Completer<PageResponse<Booking>> c =
          Completer<PageResponse<Booking>>();
      gates.add(c);
      return c.future;
    });
    return () async {
      for (int i = 0; gates.isEmpty && i < 100; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        gates,
        isNotEmpty,
        reason: 'expected a getMyBookings call that never arrived',
      );
      return gates.removeAt(0);
    };
  }

  ProviderContainer newContainer() {
    final ProviderContainer container = ProviderContainer(
      overrides: [bookingRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Subscribes to the provider and records every emission in order.
  List<AsyncValue<MasterBookingsState>> record(ProviderContainer container) {
    final List<AsyncValue<MasterBookingsState>> log =
        <AsyncValue<MasterBookingsState>>[];
    container.listen<AsyncValue<MasterBookingsState>>(
      masterBookingsProvider(query),
      (
        AsyncValue<MasterBookingsState>? _,
        AsyncValue<MasterBookingsState> next,
      ) => log.add(next),
      fireImmediately: true,
    );
    return log;
  }

  // -------------------------------------------------------------------------
  // (c) The FIRST load still shows the skeleton.
  // -------------------------------------------------------------------------

  test('the FIRST load emits a value-less AsyncLoading — the skeleton is '
      'correct there and the P3 fix must not have removed it', () async {
    final Future<Completer<PageResponse<Booking>>> Function() next =
        gatedRepo();
    final ProviderContainer container = newContainer();
    final List<AsyncValue<MasterBookingsState>> log = record(container);

    // Nothing has resolved yet.
    expect(
      log.first.isLoading,
      isTrue,
      reason: 'the initial build must be a loading state',
    );
    expect(
      log.first.hasValue,
      isFalse,
      reason:
          'the first load has no previous value to retain — the screen MUST '
          'render BookingsSkeleton here, not an empty list',
    );

    (await next()).complete(_page(<Booking>[_booking('b1')]));
    await container.read(masterBookingsProvider(query).future);

    expect(container.read(masterBookingsProvider(query)).hasValue, isTrue);
  });

  // -------------------------------------------------------------------------
  // (a) + (d) refresh keeps the content on screen.
  // -------------------------------------------------------------------------

  test('refresh() emits NO value-less loading state — the list stays mounted '
      'for the whole gesture', () async {
    final Future<Completer<PageResponse<Booking>>> Function() next =
        gatedRepo();
    final ProviderContainer container = newContainer();
    final List<AsyncValue<MasterBookingsState>> log = record(container);

    (await next()).complete(_page(<Booking>[_booking('b1')]));
    await container.read(masterBookingsProvider(query).future);

    // Everything from here on belongs to the refresh.
    final int afterFirstLoad = log.length;

    final Future<void> refreshing = container
        .read(masterBookingsProvider(query).notifier)
        .refresh();

    // (d) IN FLIGHT: still AsyncData, still carrying the OLD row. This is the
    // exact state RefreshIndicator renders its spinner over.
    await Future<void>.delayed(Duration.zero);
    final AsyncValue<MasterBookingsState> inFlight = container.read(
      masterBookingsProvider(query),
    );
    expect(
      inFlight.hasValue,
      isTrue,
      reason: 'the populated list must survive the whole refresh',
    );
    expect(
      inFlight.isLoading,
      isFalse,
      reason:
          'an isLoading state drives `async.when(loading:)` → the skeleton '
          'replaces the cards mid-gesture (perf P3)',
    );
    expect(
      inFlight.value!.items.single.id,
      'b1',
      reason: 'the OLD page must still be the rendered one',
    );

    (await next()).complete(_page(<Booking>[_booking('b2')]));
    await refreshing;

    // (a) NOT ONE emission during the refresh lost its value.
    final List<AsyncValue<MasterBookingsState>> duringRefresh = log.sublist(
      afterFirstLoad,
    );
    expect(
      duringRefresh.where((AsyncValue<MasterBookingsState> v) => !v.hasValue),
      isEmpty,
      reason:
          'refresh() must never emit a value-less state; emissions were: '
          '$duringRefresh',
    );
    expect(
      container.read(masterBookingsProvider(query)).value!.items.single.id,
      'b2',
      reason: 'the refresh must actually have swapped in the new page',
    );
  });

  // -------------------------------------------------------------------------
  // (b) A failed refresh must still surface the failure.
  // -------------------------------------------------------------------------

  test('a FAILED refresh surfaces hasError — "keep the content" must not '
      'become "swallow the failure"', () async {
    final Future<Completer<PageResponse<Booking>>> Function() next =
        gatedRepo();
    final ProviderContainer container = newContainer();

    // Kick the build BEFORE awaiting a gate — `next()` waits for a call, and
    // nothing calls the repository until the provider is actually read.
    final Future<MasterBookingsState> firstLoad = container.read(
      masterBookingsProvider(query).future,
    );
    (await next()).complete(_page(<Booking>[_booking('b1')]));
    await firstLoad;

    final Future<void> refreshing = container
        .read(masterBookingsProvider(query).notifier)
        .refresh();
    (await next()).completeError(const NetworkFailure());
    await refreshing;

    final AsyncValue<MasterBookingsState> after = container.read(
      masterBookingsProvider(query),
    );
    expect(
      after.hasError,
      isTrue,
      reason:
          'a silently-stale list after a failed pull-to-refresh is the worst '
          'outcome — the master would trust data that never arrived',
    );
    expect(after.error, isA<NetworkFailure>());
  });

  // -------------------------------------------------------------------------
  // Concurrency, stated at the emission level.
  // -------------------------------------------------------------------------

  test('a refresh issued while one is in flight does not double-fetch and '
      'does not emit a value-less state either', () async {
    final Future<Completer<PageResponse<Booking>>> Function() next =
        gatedRepo();
    final ProviderContainer container = newContainer();
    final List<AsyncValue<MasterBookingsState>> log = record(container);

    (await next()).complete(_page(<Booking>[_booking('b1')]));
    await container.read(masterBookingsProvider(query).future);
    final int afterFirstLoad = log.length;

    final MasterBookingsNotifier notifier = container.read(
      masterBookingsProvider(query).notifier,
    );
    final Future<void> a = notifier.refresh();
    final Future<void> b = notifier.refresh();
    final Future<void> c = notifier.refresh();

    await Future<void>.delayed(Duration.zero);
    (await next()).complete(_page(<Booking>[_booking('b2')]));
    await Future.wait(<Future<void>>[a, b, c]);

    verify(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        sort: any(named: 'sort'),
        page: 0,
      ),
    ).called(2); // the build's page 0 + exactly ONE refresh

    expect(
      log
          .sublist(afterFirstLoad)
          .where((AsyncValue<MasterBookingsState> v) => !v.hasValue),
      isEmpty,
    );
  });
}
