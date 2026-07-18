// Phase 7.1 — masterBookingsProvider + bookedDaysProvider.
//
// The headline test here is the SERVER-ORDER guard: a `priceDesc` response is
// fed back in an order that is deliberately NOT the `startsAt` order, so any
// client-side re-sort creeping into the notifier shows up as a failure rather
// than as a plausible-looking wrong list in production.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/master_bookings_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/master_bookings_query.dart';
import 'package:beautica_mobile/features/booking/domain/master_bookings_state.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

Booking _booking({
  required String id,
  required double price,
  required DateTime startAt,
}) => Booking(
  id: id,
  masterId: 'master-1',
  masterFirstName: 'Оля',
  masterLastName: 'Коваль',
  masterType: 'INDEPENDENT_MASTER',
  serviceId: 'service-1',
  serviceName: 'Манікюр',
  durationMinutes: 60,
  price: price,
  startAt: startAt,
  endAt: startAt.add(const Duration(hours: 1)),
  status: BookingStatus.confirmed,
  canReview: false,
);

PageResponse<Booking> _page(
  List<Booking> items, {
  int page = 0,
  int totalPages = 1,
  int? totalElements,
}) => PageResponse<Booking>(
  items: items,
  page: page,
  totalPages: totalPages,
  totalElements: totalElements ?? items.length,
);

ProviderContainer _containerWith(BookingRepository repo) {
  final container = ProviderContainer(
    overrides: [bookingRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUpAll(() {
    registerFallbackValue(<BookingStatus>{});
    registerFallbackValue(BookingSort.newest);
  });

  late _MockBookingRepository repo;

  setUp(() {
    repo = _MockBookingRepository();
  });

  void stubBookings(PageResponse<Booking> response, {int? page}) {
    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        sort: any(named: 'sort'),
        page: page ?? any(named: 'page'),
      ),
    ).thenAnswer((_) async => response);
  }

  group('masterBookingsProvider — the query reaches the repository intact', () {
    test('forwards every filter + sort from the query object', () async {
      stubBookings(_page(const <Booking>[]));

      final query = MasterBookingsQuery.of(
        statuses: <BookingStatus>{
          BookingStatus.confirmed,
          BookingStatus.completed,
        },
        serviceIds: <String>{'svc-a', 'svc-b'},
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 31),
        sort: BookingSort.priceDesc,
      );

      await _containerWith(repo).read(masterBookingsProvider(query).future);

      // Perf P5 — the notifier now forwards the query's CANONICAL LISTS
      // verbatim rather than round-tripping each through a throwaway `.toSet()`
      // on every fetch, so what the repository receives is `.of()`'s sorted,
      // unmodifiable List (statuses by enum index, serviceIds lexicographic).
      verify(
        () => repo.getMyBookings(
          statuses: <BookingStatus>[
            BookingStatus.confirmed,
            BookingStatus.completed,
          ],
          serviceIds: <String>['svc-a', 'svc-b'],
          from: DateTime(2026, 7, 1),
          to: DateTime(2026, 7, 31),
          sort: BookingSort.priceDesc,
          page: 0,
        ),
      ).called(1);
    });

    test(
      'exposes the server\'s totalElements, not items.length — the toolbar '
      'count must describe the whole result set, not the first page',
      () async {
        stubBookings(
          _page(
            <Booking>[
              _booking(id: 'b1', price: 100, startAt: DateTime(2026, 7, 10)),
            ],
            totalPages: 9,
            totalElements: 173,
          ),
        );

        final MasterBookingsState state = await _containerWith(
          repo,
        ).read(masterBookingsProvider(MasterBookingsQuery.of()).future);

        expect(state.items, hasLength(1));
        expect(state.totalElements, 173);
        expect(state.hasMore, isTrue);
      },
    );

    test('two identical queries resolve to ONE family member — one fetch, not '
        'two (the provider-leak guard)', () async {
      stubBookings(_page(const <Booking>[]));
      final container = _containerWith(repo);

      // Built independently, and with a stray time component on the bounds —
      // exactly what a date picker hands back.
      final a = MasterBookingsQuery.of(from: DateTime(2026, 7, 18, 9, 14));
      final b = MasterBookingsQuery.of(from: DateTime(2026, 7, 18, 17, 2));

      await container.read(masterBookingsProvider(a).future);
      await container.read(masterBookingsProvider(b).future);

      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: 0,
        ),
      ).called(1);
    });

    test('a failing first page surfaces as an AsyncError', () async {
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
        ),
      ).thenAnswer((_) async => throw const NetworkFailure());

      final container = _containerWith(repo);
      final query = MasterBookingsQuery.of();

      // Keep the autoDispose family member alive across the async gap, then
      // trigger the build and let the rejected fetch settle — mirrors the
      // `build error` idiom in `my_bookings_notifier_test.dart`. Awaiting
      // `.future` directly would race provider disposal and surface a
      // StateError instead of the repository's own Failure.
      container.listen(masterBookingsProvider(query), (_, _) {});
      container.read(masterBookingsProvider(query));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final AsyncValue<MasterBookingsState> state = container.read(
        masterBookingsProvider(query),
      );
      expect(state.hasError, isTrue);
      expect(state.error, isA<NetworkFailure>());
    });
  });

  group('masterBookingsProvider — SERVER ORDER IS PRESERVED', () {
    test('a priceDesc page reaches the consumer in the server\'s order, NOT '
        're-sorted by startsAt', () async {
      // Price-descending, and deliberately scrambled relative to startsAt: if
      // anything re-sorts by date, the ids come back in a different order.
      final List<Booking> serverOrder = <Booking>[
        _booking(id: 'expensive', price: 900, startAt: DateTime(2026, 7, 20)),
        _booking(id: 'mid', price: 500, startAt: DateTime(2026, 7, 10)),
        _booking(id: 'cheap', price: 100, startAt: DateTime(2026, 7, 30)),
      ];
      stubBookings(_page(serverOrder));

      final MasterBookingsState state = await _containerWith(repo).read(
        masterBookingsProvider(
          MasterBookingsQuery.of(sort: BookingSort.priceDesc),
        ).future,
      );

      expect(state.items.map((Booking b) => b.id), <String>[
        'expensive',
        'mid',
        'cheap',
      ]);
    });

    test('loadMore APPENDS the next page verbatim — no merge-sort across the '
        'page boundary', () async {
      final query = MasterBookingsQuery.of(sort: BookingSort.priceDesc);

      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: 0,
        ),
      ).thenAnswer(
        (_) async => _page(
          <Booking>[
            _booking(id: 'p0-a', price: 900, startAt: DateTime(2026, 7, 20)),
            _booking(id: 'p0-b', price: 800, startAt: DateTime(2026, 7, 2)),
          ],
          totalPages: 2,
          totalElements: 4,
        ),
      );
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: 1,
        ),
      ).thenAnswer(
        (_) async => _page(
          <Booking>[
            // Page 1's rows are EARLIER in time than page 0's — a startsAt
            // re-sort would interleave them into the accumulated list.
            _booking(id: 'p1-a', price: 300, startAt: DateTime(2026, 7, 1)),
            _booking(id: 'p1-b', price: 100, startAt: DateTime(2026, 7, 5)),
          ],
          page: 1,
          totalPages: 2,
          totalElements: 4,
        ),
      );

      final container = _containerWith(repo);
      await container.read(masterBookingsProvider(query).future);
      await container.read(masterBookingsProvider(query).notifier).loadMore();

      final MasterBookingsState state = container
          .read(masterBookingsProvider(query))
          .requireValue;

      expect(state.items.map((Booking b) => b.id), <String>[
        'p0-a',
        'p0-b',
        'p1-a',
        'p1-b',
      ]);
      expect(state.page, 1);
      expect(state.hasMore, isFalse);
      expect(state.isLoadingMore, isFalse);
    });
  });

  group('masterBookingsProvider — paging guards', () {
    test('loadMore is a no-op on the last page', () async {
      stubBookings(
        _page(<Booking>[
          _booking(id: 'only', price: 100, startAt: DateTime(2026, 7, 1)),
        ]),
      );
      final query = MasterBookingsQuery.of();
      final container = _containerWith(repo);

      await container.read(masterBookingsProvider(query).future);
      await container.read(masterBookingsProvider(query).notifier).loadMore();

      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: 0,
        ),
      ).called(1);
      verifyNoMoreInteractions(repo);
    });

    test(
      'a failed loadMore keeps the rendered list and clears the spinner',
      () async {
        final query = MasterBookingsQuery.of();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
            sort: any(named: 'sort'),
            page: 0,
          ),
        ).thenAnswer(
          (_) async => _page(
            <Booking>[
              _booking(id: 'kept', price: 100, startAt: DateTime(2026, 7, 1)),
            ],
            totalPages: 2,
            totalElements: 2,
          ),
        );
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
            sort: any(named: 'sort'),
            page: 1,
          ),
        ).thenThrow(const NetworkFailure());

        final container = _containerWith(repo);
        await container.read(masterBookingsProvider(query).future);
        await container.read(masterBookingsProvider(query).notifier).loadMore();

        final MasterBookingsState state = container
            .read(masterBookingsProvider(query))
            .requireValue;

        expect(state.items.map((Booking b) => b.id), <String>['kept']);
        expect(state.isLoadingMore, isFalse);
        expect(state.hasMore, isTrue);
      },
    );

    test('refresh re-fetches page 0', () async {
      stubBookings(_page(const <Booking>[]));
      final query = MasterBookingsQuery.of();
      final container = _containerWith(repo);

      await container.read(masterBookingsProvider(query).future);
      await container.read(masterBookingsProvider(query).notifier).refresh();

      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: 0,
        ),
      ).called(2);
    });
  });

  group('bookedDaysProvider — filter-independent dot set', () {
    test('requests a 361-day window centred on today, inside the backend\'s '
        '366-day cap', () async {
      late DateTime capturedFrom;
      late DateTime capturedTo;
      when(
        () => repo.getMyBookedDays(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((Invocation i) async {
        capturedFrom = i.namedArguments[#from] as DateTime;
        capturedTo = i.namedArguments[#to] as DateTime;
        return const <DateTime>[];
      });

      await _containerWith(repo).read(bookedDaysProvider.future);

      final int spanDays = capturedTo.difference(capturedFrom).inDays;
      // Inclusive of both endpoints → 361 calendar days. Must stay < 366.
      expect(spanDays + 1, lessThanOrEqualTo(366));
      expect(spanDays + 1, 361);

      final DateTime today = dateOnly(DateTime.now());
      expect(capturedFrom.isBefore(today), isTrue);
      expect(capturedTo.isAfter(today), isTrue);
      // Both bounds are local midnight, so `toApiDate` cannot shift a day.
      expect(capturedFrom.hour, 0);
      expect(capturedTo.hour, 0);
    });

    test('returns a date-only Set for O(1) membership', () async {
      when(
        () => repo.getMyBookedDays(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(
        (_) async => <DateTime>[DateTime(2026, 7, 18), DateTime(2026, 7, 20)],
      );

      final Set<DateTime> days = await _containerWith(
        repo,
      ).read(bookedDaysProvider.future);

      expect(days, containsAll(<DateTime>[DateTime(2026, 7, 18)]));
      expect(days.contains(DateTime(2026, 7, 19)), isFalse);
    });

    test('duplicate days from the server collapse into one dot', () async {
      when(
        () => repo.getMyBookedDays(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(
        (_) async => <DateTime>[
          DateTime(2026, 7, 18),
          DateTime(2026, 7, 18),
          DateTime(2026, 7, 18),
        ],
      );

      expect(
        await _containerWith(repo).read(bookedDaysProvider.future),
        hasLength(1),
      );
    });

    test('is NOT keyed by a query — it takes no filter argument at all, so '
        'narrowing the list can never narrow the rail', () async {
      when(
        () => repo.getMyBookedDays(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) async => <DateTime>[DateTime(2026, 7, 18)]);

      final container = _containerWith(repo);

      // Reading it repeatedly while "filters change" hits the same single
      // provider instance — one fetch, one unfiltered dot set.
      await container.read(bookedDaysProvider.future);
      await container.read(bookedDaysProvider.future);

      verify(
        () => repo.getMyBookedDays(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).called(1);
    });
  });

  // ==========================================================================
  // Perf P1 — refresh() coalescing.
  //
  // `loadMore` has always guarded re-entry via `isLoadingMore`; `refresh` had
  // NO guard, so three rapid pull-to-refresh gestures fired three concurrent
  // `GET /bookings/me?page=0`. The bug is not the wasted requests — it is that
  // the last to RESOLVE wins, and that is not the last to be SENT, so a stale
  // response could overwrite a fresher one.
  // ==========================================================================
  group('masterBookingsProvider — refresh() coalesces concurrent calls', () {
    test('three rapid refreshes issue ONE page-0 request, not three', () async {
      // A completer-gated stub keeps the first refresh in flight while the
      // other two are issued — reproducing the pull-to-refresh gesture storm
      // without any fixed wait.
      final Completer<PageResponse<Booking>> gate =
          Completer<PageResponse<Booking>>();
      int calls = 0;
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
        calls++;
        return gate.future;
      });

      final container = _containerWith(repo);
      final query = MasterBookingsQuery.of();
      // Let build()'s own page-0 fetch settle first.
      gate.complete(_page(const <Booking>[]));
      await container.read(masterBookingsProvider(query).future);
      expect(calls, 1, reason: 'build() fetched page 0');

      final Completer<PageResponse<Booking>> refreshGate =
          Completer<PageResponse<Booking>>();
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
        calls++;
        return refreshGate.future;
      });

      final notifier = container.read(masterBookingsProvider(query).notifier);

      // Three gestures, none awaited — all three land while the first is in
      // flight, which is exactly the storm the guard exists for.
      final List<Future<void>> gestures = <Future<void>>[
        notifier.refresh(),
        notifier.refresh(),
        notifier.refresh(),
      ];

      refreshGate.complete(_page(const <Booking>[]));
      await Future.wait(gestures);

      expect(
        calls,
        2,
        reason:
            'build()\'s fetch + exactly ONE refresh; the 2nd and 3rd '
            'gestures must be dropped, not stacked',
      );
    });

    test('the guard RELEASES — a refresh after an in-flight one completes '
        'still fetches (it is a coalesce, not a latch)', () async {
      stubBookings(_page(const <Booking>[]));

      final container = _containerWith(repo);
      final query = MasterBookingsQuery.of();
      await container.read(masterBookingsProvider(query).future);

      final notifier = container.read(masterBookingsProvider(query).notifier);
      await notifier.refresh();
      await notifier.refresh();

      // build() + two SEQUENTIAL refreshes = 3. A guard that never cleared
      // (e.g. one set outside a `finally`, or left set after a throw) would
      // stop at 2 and pull-to-refresh would be dead for the rest of the
      // screen's life.
      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: 0,
        ),
      ).called(3);
    });

    test('the guard releases even when the refresh FAILS — a transient '
        'network error must not permanently disable pull-to-refresh', () async {
      stubBookings(_page(const <Booking>[]));
      final container = _containerWith(repo);
      final query = MasterBookingsQuery.of();
      await container.read(masterBookingsProvider(query).future);

      final notifier = container.read(masterBookingsProvider(query).notifier);

      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
        ),
      ).thenThrow(const NetworkFailure());

      await notifier.refresh();
      expect(container.read(masterBookingsProvider(query)).hasError, isTrue);

      // Recovery: the next refresh must actually reach the repository.
      stubBookings(_page(const <Booking>[]));
      await notifier.refresh();
      expect(container.read(masterBookingsProvider(query)).hasValue, isTrue);
    });
  });
}
