// QA (track 14.x booking) — unit suite for [MyBookingsNotifier].
//
// Rewritten for backend Phase 26.1 (repeatable `status` query param, unioned
// server-side into ONE globally-paginated stream) + Phase 26.3 (honoured
// `sort` param) — mobile-debugger findings A + B. Each tab now issues exactly
// ONE `getMyBookings` call carrying its whole status set + the tab's sort
// direction; there is no more client-side fan-out/merge/re-sort to pin, so
// this suite instead pins: the exact `statuses`/`sort` args per tab
// (single call, not one-per-status), that the server response is used
// as-is (no re-sort), pagination cursor advance, and the existing
// load-more/refresh/error guards.
//
// The PREVIOUS version of this suite asserted the fan-out/merge architecture
// directly (verifying N separate per-status `getMyBookings` calls, a
// client-side merge of two independently-paginated streams, and independent
// per-status page cursors advancing on `loadMore`) — that architecture is
// exactly what mobile-debugger flagged as unsound (finding A) and is now
// deleted from `my_bookings_notifier.dart`. Those assertions are NOT ported
// forward as "weakened" versions; they are replaced by single-request
// equivalents below. See the mobile-dev handoff notes for the exact list of
// old assertions that no longer apply.
//
// Isolation: a fresh [ProviderContainer] per test with a mocktail-backed
// [BookingRepository] override; disposed via addTearDown.

import 'dart:async';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/application/my_bookings_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

Booking _booking({
  required String id,
  required BookingStatus status,
  required DateTime startAt,
}) => Booking(
  id: id,
  masterId: 'm-$id',
  masterFirstName: 'Марія',
  masterLastName: 'Іванюк',
  masterAvatarUrl: null,
  masterType: 'INDEPENDENT_MASTER',
  salonName: null,
  serviceId: 's-$id',
  serviceName: 'Манікюр',
  categoryName: 'Манікюр',
  cityLabel: 'Львів',
  districtLabel: null,
  street: null,
  buildingNo: null,
  durationMinutes: 60,
  price: 500,
  startAt: startAt,
  endAt: startAt.add(const Duration(hours: 1)),
  status: status,
  canReview: false,
  clientComment: null,
  providerComment: null,
  clientCancellationNote: null,
  masterProfessionalTitle: null,
  locationNote: null,
);

PageResponse<Booking> _page(
  List<Booking> items, {
  int page = 0,
  int totalPages = 1,
}) => PageResponse<Booking>(
  items: items,
  page: page,
  totalPages: totalPages,
  totalElements: items.length,
);

ProviderContainer _container(_MockBookingRepository repo) {
  final ProviderContainer c = ProviderContainer(
    // ignore: avoid_dynamic_calls
    overrides: <Object>[
      bookingRepositoryProvider.overrideWithValue(repo),
    ].cast(),
  );
  addTearDown(c.dispose);
  return c;
}

/// Stubs the ONE `getMyBookings` call [tab] issues at [page] to answer with
/// [response]. `sort` is derived from the tab (Майбутні only).
void _stubTab(
  _MockBookingRepository repo,
  BookingTab tab, {
  required int page,
  required PageResponse<Booking> response,
}) {
  when(
    () => repo.getMyBookings(
      statuses: tab.statuses,
      sort: tab == BookingTab.upcoming
          ? BookingSort.oldest
          : BookingSort.newest,
      page: page,
      size: any(named: 'size'),
    ),
  ).thenAnswer((_) async => response);
}

void main() {
  group('build — single request per tab (backend Phase 26.1)', () {
    test(
      'Майбутні sends statuses={CONFIRMED}, sort: BookingSort.oldest, in ONE call',
      (() async {
        final repo = _MockBookingRepository();
        _stubTab(
          repo,
          BookingTab.upcoming,
          page: 0,
          response: _page(<Booking>[
            _booking(
              id: 'c1',
              status: BookingStatus.confirmed,
              startAt: DateTime.utc(2026, 8, 1, 10),
            ),
          ]),
        );
        final c = _container(repo);

        final MyBookingsState state = await c.read(
          myBookingsProvider(BookingTab.upcoming).future,
        );

        expect(state.items.map((Booking b) => b.id), <String>['c1']);
        verify(
          () => repo.getMyBookings(
            statuses: const <BookingStatus>{BookingStatus.confirmed},
            sort: BookingSort.oldest,
            page: 0,
            size: any(named: 'size'),
          ),
        ).called(1);
      }),
    );

    test('Минулі sends BOTH statuses={COMPLETED, NOT_COMPLETED} in ONE call — '
        'no per-status fan-out', () async {
      final repo = _MockBookingRepository();
      _stubTab(
        repo,
        BookingTab.past,
        page: 0,
        response: _page(<Booking>[
          _booking(
            id: 'x1',
            status: BookingStatus.completed,
            startAt: DateTime.utc(2026, 7, 10),
          ),
          _booking(
            id: 'd1',
            status: BookingStatus.notCompleted,
            startAt: DateTime.utc(2026, 7, 12),
          ),
        ]),
      );
      final c = _container(repo);

      final MyBookingsState state = await c.read(
        myBookingsProvider(BookingTab.past).future,
      );

      expect(state.items.map((Booking b) => b.id).toSet(), <String>{
        'x1',
        'd1',
      });
      // Exactly ONE getMyBookings call total for this tab — the whole point
      // of the fix (mobile-debugger finding A): no separate fetch per
      // status to merge client-side.
      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).called(1);
    });

    test(
      'Скасовані sends BOTH statuses={CANCELLED, DECLINED} in ONE call',
      (() async {
        final repo = _MockBookingRepository();
        _stubTab(
          repo,
          BookingTab.cancelled,
          page: 0,
          response: _page(<Booking>[
            _booking(
              id: 'x1',
              status: BookingStatus.cancelled,
              startAt: DateTime.utc(2026, 7, 10),
            ),
            _booking(
              id: 'd1',
              status: BookingStatus.declined,
              startAt: DateTime.utc(2026, 7, 12),
            ),
          ]),
        );
        final c = _container(repo);

        final MyBookingsState state = await c.read(
          myBookingsProvider(BookingTab.cancelled).future,
        );

        expect(state.items.map((Booking b) => b.id).toSet(), <String>{
          'x1',
          'd1',
        });
        verify(
          () => repo.getMyBookings(
            statuses: const <BookingStatus>{
              BookingStatus.cancelled,
              BookingStatus.declined,
            },
            sort: BookingSort.newest,
            page: 0,
            size: any(named: 'size'),
          ),
        ).called(1);
      }),
    );

    test(
      'the server response order is used AS-IS — no client-side re-sort',
      () async {
        // Deliberately hand the notifier a server response that is NOT
        // chronologically sorted — if the notifier still re-sorted
        // client-side (the old, now-deleted `_merge`), this would pass by
        // accident. It must not: the union+global-pagination+sort is now the
        // server's job (backend Phase 26.1/26.3).
        final repo = _MockBookingRepository();
        _stubTab(
          repo,
          BookingTab.upcoming,
          page: 0,
          response: _page(<Booking>[
            _booking(
              id: 'late',
              status: BookingStatus.confirmed,
              startAt: DateTime.utc(2026, 8, 5),
            ),
            _booking(
              id: 'soon',
              status: BookingStatus.confirmed,
              startAt: DateTime.utc(2026, 8, 1),
            ),
          ]),
        );
        final c = _container(repo);

        final MyBookingsState state = await c.read(
          myBookingsProvider(BookingTab.upcoming).future,
        );

        expect(state.items.map((Booking b) => b.id), <String>['late', 'soon']);
      },
    );
  });

  group('sort direction argument per tab', () {
    test(
      'Майбутні requests sort: BookingSort.oldest (soonest-first)',
      () async {
        final repo = _MockBookingRepository();
        _stubTab(
          repo,
          BookingTab.upcoming,
          page: 0,
          response: _page(const <Booking>[]),
        );
        final c = _container(repo);

        await c.read(myBookingsProvider(BookingTab.upcoming).future);

        verify(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            sort: BookingSort.oldest,
            page: 0,
            size: any(named: 'size'),
          ),
        ).called(1);
      },
    );

    test(
      'Минулі requests sort: BookingSort.newest (most-recent-first)',
      () async {
        final repo = _MockBookingRepository();
        _stubTab(
          repo,
          BookingTab.past,
          page: 0,
          response: _page(const <Booking>[]),
        );
        final c = _container(repo);

        await c.read(myBookingsProvider(BookingTab.past).future);

        verify(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            sort: BookingSort.newest,
            page: 0,
            size: any(named: 'size'),
          ),
        ).called(1);
      },
    );
  });

  group('loadMore', () {
    test('appends the next page and advances the page cursor', () async {
      final repo = _MockBookingRepository();
      _stubTab(
        repo,
        BookingTab.cancelled,
        page: 0,
        response: _page(
          <Booking>[
            _booking(
              id: 'x0',
              status: BookingStatus.cancelled,
              startAt: DateTime.utc(2026, 7, 10),
            ),
          ],
          page: 0,
          totalPages: 2,
        ),
      );
      _stubTab(
        repo,
        BookingTab.cancelled,
        page: 1,
        response: _page(
          <Booking>[
            _booking(
              id: 'x1',
              status: BookingStatus.cancelled,
              startAt: DateTime.utc(2026, 7, 9),
            ),
          ],
          page: 1,
          totalPages: 2,
        ),
      );
      final c = _container(repo);

      await c.read(myBookingsProvider(BookingTab.cancelled).future);
      expect(
        c.read(myBookingsProvider(BookingTab.cancelled)).value!.hasMore,
        isTrue,
      );

      await c
          .read(myBookingsProvider(BookingTab.cancelled).notifier)
          .loadMore();

      final MyBookingsState after = c
          .read(myBookingsProvider(BookingTab.cancelled))
          .value!;
      expect(after.items.map((Booking b) => b.id), <String>['x0', 'x1']);
      expect(after.page, 1);
      expect(after.hasMore, isFalse);
      verify(
        () => repo.getMyBookings(
          statuses: BookingTab.cancelled.statuses,
          sort: BookingSort.newest,
          page: 1,
          size: any(named: 'size'),
        ),
      ).called(1);
    });

    test('is a no-op when the stream is already exhausted', () async {
      final repo = _MockBookingRepository();
      _stubTab(
        repo,
        BookingTab.upcoming,
        page: 0,
        response: _page(<Booking>[
          _booking(
            id: 'c1',
            status: BookingStatus.confirmed,
            startAt: DateTime.utc(2026, 8, 1),
          ),
        ]),
      );
      final c = _container(repo);

      await c.read(myBookingsProvider(BookingTab.upcoming).future);
      await c.read(myBookingsProvider(BookingTab.upcoming).notifier).loadMore();

      // Exactly ONE page-0 fetch — the no-op loadMore issued no second call.
      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).called(1);
    });

    test('a second loadMore fired before the first settles is a no-op '
        '(pins the isLoadingMore in-flight guard, not the hasMore guard '
        'covered above)', () async {
      final repo = _MockBookingRepository();
      _stubTab(
        repo,
        BookingTab.cancelled,
        page: 0,
        response: _page(
          <Booking>[
            _booking(
              id: 'x0',
              status: BookingStatus.cancelled,
              startAt: DateTime.utc(2026, 7, 10),
            ),
          ],
          page: 0,
          totalPages: 2,
        ),
      );
      // A Completer (not an immediately-resolved future) so the first
      // loadMore() is genuinely still in-flight — not just "not yet
      // awaited" — when the second loadMore() call reads `state.value`.
      final Completer<PageResponse<Booking>> pendingPage1 =
          Completer<PageResponse<Booking>>();
      when(
        () => repo.getMyBookings(
          statuses: BookingTab.cancelled.statuses,
          sort: BookingSort.newest,
          page: 1,
          size: any(named: 'size'),
        ),
      ).thenAnswer((_) => pendingPage1.future);
      final c = _container(repo);

      await c.read(myBookingsProvider(BookingTab.cancelled).future);
      final MyBookingsNotifier notifier = c.read(
        myBookingsProvider(BookingTab.cancelled).notifier,
      );

      // Fire two loadMore() calls back-to-back WITHOUT awaiting the
      // first. `loadMore()` runs synchronously up to its
      // `await repo.getMyBookings(...)` — which sets
      // `state = AsyncData(current.copyWith(isLoadingMore: true))`
      // BEFORE that await suspends — so by the time this second call
      // reads `state.value`, it observes `isLoadingMore == true` from
      // the still-pending first call.
      final Future<void> first = notifier.loadMore();
      final Future<void> second = notifier.loadMore();

      // Let the first (genuinely in-flight) fetch resolve.
      pendingPage1.complete(
        _page(
          <Booking>[
            _booking(
              id: 'x1',
              status: BookingStatus.cancelled,
              startAt: DateTime.utc(2026, 7, 9),
            ),
          ],
          page: 1,
          totalPages: 2,
        ),
      );
      await first;
      await second;

      // DISCRIMINATING ASSERTION: exactly ONE page-1 fetch happened, not
      // two. If the `if (current.isLoadingMore) return;` guard in
      // `loadMore()` were deleted, the second call would still observe
      // `hasMore == true` (page 0's value — the first fetch hadn't
      // landed yet) and issue its OWN page-1 request, turning this
      // `.called(1)` into `.called(2)` and failing the test.
      verify(
        () => repo.getMyBookings(
          statuses: BookingTab.cancelled.statuses,
          sort: BookingSort.newest,
          page: 1,
          size: any(named: 'size'),
        ),
      ).called(1);

      final MyBookingsState after = c
          .read(myBookingsProvider(BookingTab.cancelled))
          .value!;
      expect(after.items.map((Booking b) => b.id), <String>['x0', 'x1']);
      expect(after.isLoadingMore, isFalse);
    });

    test(
      'a failed load-more keeps the current list and clears the spinner',
      () async {
        final repo = _MockBookingRepository();
        _stubTab(
          repo,
          BookingTab.upcoming,
          page: 0,
          response: _page(
            <Booking>[
              _booking(
                id: 'c1',
                status: BookingStatus.confirmed,
                startAt: DateTime.utc(2026, 8, 1),
              ),
            ],
            page: 0,
            totalPages: 2,
          ),
        );
        when(
          () => repo.getMyBookings(
            statuses: BookingTab.upcoming.statuses,
            sort: BookingSort.oldest,
            page: 1,
            size: any(named: 'size'),
          ),
        ).thenThrow(Exception('network'));
        final c = _container(repo);

        await c.read(myBookingsProvider(BookingTab.upcoming).future);
        await c
            .read(myBookingsProvider(BookingTab.upcoming).notifier)
            .loadMore();

        final MyBookingsState after = c
            .read(myBookingsProvider(BookingTab.upcoming))
            .value!;
        // List survived the failed append — still AsyncData, not AsyncError.
        expect(
          c.read(myBookingsProvider(BookingTab.upcoming)).hasError,
          isFalse,
        );
        expect(after.items.map((Booking b) => b.id), <String>['c1']);
        expect(after.isLoadingMore, isFalse);
      },
    );
  });

  group('refresh', () {
    test('re-fetches page 0 for the tab', () async {
      final repo = _MockBookingRepository();
      _stubTab(
        repo,
        BookingTab.upcoming,
        page: 0,
        response: _page(<Booking>[
          _booking(
            id: 'c1',
            status: BookingStatus.confirmed,
            startAt: DateTime.utc(2026, 8, 1),
          ),
        ]),
      );
      final c = _container(repo);

      await c.read(myBookingsProvider(BookingTab.upcoming).future);
      await c.read(myBookingsProvider(BookingTab.upcoming).notifier).refresh();

      verify(
        () => repo.getMyBookings(
          statuses: BookingTab.upcoming.statuses,
          sort: BookingSort.oldest,
          page: 0,
          size: any(named: 'size'),
        ),
      ).called(2);
    });
  });

  // Product rule (decided 2026-07-16): a booking moves to «Минулі»/Past ONLY
  // when the PROVIDER marks it completed — NEVER by elapsed time. The tab
  // partition is status-driven (see `BookingTabX.statuses`), with no
  // DateTime.now() predicate anywhere. These guards pin that so a future edit
  // that (wrongly) adds a time-based rule — or moves CONFIRMED into the past
  // set — breaks the suite. Mirrors the backend state machine 1:1.
  group('past-by-status-not-by-time (elapsed CONFIRMED stays Майбутні)', () {
    // The user's exact case: «Майстер Демо» / «Експрес нарощення»,
    // 16.07.2026 10:00–10:45. Elapsed same-day appointment, now ~11:54.
    // Local (not UTC) — this is a wall-clock appointment.
    final DateTime elapsedStart = DateTime(2026, 7, 16, 10, 0);
    final DateTime elapsedEnd = DateTime(2026, 7, 16, 10, 45);

    test(
      'an elapsed CONFIRMED booking is classified UPCOMING, not PAST',
      () async {
        // Precondition: the appointment window is genuinely in the past —
        // monotonically true for any run on/after 2026-07-16 10:45.
        expect(
          elapsedEnd.isBefore(DateTime.now()),
          isTrue,
          reason:
              'fixture must be an ALREADY-elapsed appointment for the guard '
              'to mean anything',
        );

        final repo = _MockBookingRepository();
        final Booking elapsed = _booking(
          id: 'elapsed-confirmed',
          status: BookingStatus.confirmed,
          startAt: elapsedStart,
        );
        _stubTab(
          repo,
          BookingTab.upcoming,
          page: 0,
          response: _page(<Booking>[elapsed]),
        );
        _stubTab(
          repo,
          BookingTab.past,
          page: 0,
          response: _page(const <Booking>[]),
        );
        final c = _container(repo);

        // The Майбутні tab surfaces the elapsed CONFIRMED booking...
        final MyBookingsState upcoming = await c.read(
          myBookingsProvider(BookingTab.upcoming).future,
        );
        expect(
          upcoming.items.map((Booking b) => b.id),
          <String>['elapsed-confirmed'],
          reason: 'CONFIRMED belongs to Майбутні regardless of elapsed time',
        );

        // ...and the Минулі tab does NOT — elapsed time alone never moves it.
        final MyBookingsState past = await c.read(
          myBookingsProvider(BookingTab.past).future,
        );
        expect(
          past.items.where((Booking b) => b.id == 'elapsed-confirmed'),
          isEmpty,
          reason:
              'only a provider COMPLETED transition moves a booking to Past',
        );

        // The booking's own status is in the upcoming partition, not the past.
        expect(BookingTab.upcoming.statuses, contains(elapsed.status));
        expect(BookingTab.past.statuses, isNot(contains(elapsed.status)));
      },
    );

    test('a COMPLETED booking IS classified PAST', () async {
      final repo = _MockBookingRepository();
      final Booking completed = _booking(
        id: 'completed-1',
        status: BookingStatus.completed,
        startAt: elapsedStart,
      );
      _stubTab(
        repo,
        BookingTab.past,
        page: 0,
        response: _page(<Booking>[completed]),
      );
      final c = _container(repo);

      final MyBookingsState past = await c.read(
        myBookingsProvider(BookingTab.past).future,
      );
      expect(past.items.map((Booking b) => b.id), <String>['completed-1']);
      expect(BookingTab.past.statuses, contains(completed.status));
    });

    test('the partition sets are pinned — no time-based rule may creep in', () {
      // Pin the EXACT status membership. A future edit that adds a time
      // predicate, moves CONFIRMED into Past, or repartitions the tabs will
      // fail here first.
      expect(BookingTab.upcoming.statuses, <BookingStatus>{
        BookingStatus.confirmed,
      });
      expect(BookingTab.past.statuses, <BookingStatus>{
        BookingStatus.completed,
        BookingStatus.notCompleted,
      });
      // CONFIRMED must never be a Past status — the whole point of the rule.
      expect(
        BookingTab.past.statuses,
        isNot(contains(BookingStatus.confirmed)),
      );
    });
  });

  group('build error', () {
    test('propagates a repository failure as AsyncError', () async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
        ),
      ).thenAnswer((_) async => throw Exception('boom'));
      final c = _container(repo);

      // Keep the autoDispose provider alive across the async gap, then trigger
      // the build and let the rejected fetch settle.
      c.listen(myBookingsProvider(BookingTab.upcoming), (_, _) {});
      c.read(myBookingsProvider(BookingTab.upcoming));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(c.read(myBookingsProvider(BookingTab.upcoming)).hasError, isTrue);
    });
  });

  // ==========================================================================
  // Perf P1 — refresh() coalescing (the same pre-existing gap fixed on
  // MasterBookingsNotifier). `loadMore` guards re-entry via `isLoadingMore`;
  // `refresh` had no guard, so a pull-to-refresh gesture storm fired
  // concurrent page-0 requests and the last to RESOLVE won — which is not the
  // last to be SENT, so a stale response could overwrite a fresher one.
  //
  // This is the ONLY behavioural change to the shipped client notifier.
  // ==========================================================================
  group('refresh — coalesces concurrent calls (perf P1)', () {
    test('three rapid refreshes issue ONE page-0 request, not three', () async {
      final repo = _MockBookingRepository();
      _stubTab(
        repo,
        BookingTab.upcoming,
        page: 0,
        response: _page(const <Booking>[]),
      );

      final c = _container(repo);
      await c.read(myBookingsProvider(BookingTab.upcoming).future);

      // Re-stub page 0 behind a gate so the first refresh stays in flight
      // while the next two are issued.
      final Completer<PageResponse<Booking>> gate =
          Completer<PageResponse<Booking>>();
      int refreshCalls = 0;
      when(
        () => repo.getMyBookings(
          statuses: BookingTab.upcoming.statuses,
          sort: BookingSort.oldest,
          page: 0,
          size: any(named: 'size'),
        ),
      ).thenAnswer((_) {
        refreshCalls++;
        return gate.future;
      });

      final notifier = c.read(myBookingsProvider(BookingTab.upcoming).notifier);
      final List<Future<void>> gestures = <Future<void>>[
        notifier.refresh(),
        notifier.refresh(),
        notifier.refresh(),
      ];

      gate.complete(_page(const <Booking>[]));
      await Future.wait(gestures);

      expect(
        refreshCalls,
        1,
        reason: 'the 2nd and 3rd gestures must be dropped, not stacked',
      );
    });

    test('the guard RELEASES — two SEQUENTIAL refreshes both fetch (it is a '
        'coalesce, not a latch)', () async {
      final repo = _MockBookingRepository();
      _stubTab(
        repo,
        BookingTab.upcoming,
        page: 0,
        response: _page(const <Booking>[]),
      );

      final c = _container(repo);
      await c.read(myBookingsProvider(BookingTab.upcoming).future);

      final notifier = c.read(myBookingsProvider(BookingTab.upcoming).notifier);
      await notifier.refresh();
      await notifier.refresh();

      // build() + two refreshes. A guard left set (outside a `finally`, or
      // after a throw) would stop at 1 and kill pull-to-refresh for good.
      verify(
        () => repo.getMyBookings(
          statuses: BookingTab.upcoming.statuses,
          sort: BookingSort.oldest,
          page: 0,
          size: any(named: 'size'),
        ),
      ).called(3);
    });
  });
}
