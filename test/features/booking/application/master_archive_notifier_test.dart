// Phase 231 — unit suite for [MasterArchiveNotifier] (the master «Архів»
// page's request-shaping + client-side status predicate + pagination).
//
// Mirrors `my_bookings_notifier_test.dart`'s isolation discipline: a fresh
// [ProviderContainer] per test with a mocktail-backed [BookingRepository]
// override, disposed via addTearDown.
//
// This suite pins the load-bearing decisions from
// `master_archive_notifier.dart`'s file header:
//   * EVERY request sends `partition: BookingPartition.history`
//     UNCONDITIONALLY (never conditional on the filter selection) PLUS a
//     legacy `status` set — asserted on the CAPTURED request, not just "a
//     call happened".
//   * Ticking «Підтверджено» alone (no new UI) isolates exactly the
//     `awaitingClosure` rows — proven non-vacuous with a fixture containing
//     non-awaiting rows too.
//   * Select-all (all three `BookingStatusFilterGroup` rows) collapses to
//     "no predicate", keeping a legacy NOT_COMPLETED row visible.
//   * Ticking «Скасовано» against a HISTORY-partition fixture returns
//     EXACTLY the cancelled/declined rows — the 2026-08-16 HISTORY cutover
//     fix for the reported bug (a declined visit never appeared in the
//     archive, and this filter always came back empty under the old
//     `partition: PAST` fetch). This test used to assert the OLD, now-wrong
//     "always empty" behaviour; it is inverted here as the regression guard.
//   * `kArchiveFilterCoverage` stays in lockstep with
//     `BookingStatusFilterGroup`'s real coverage (the ONE cross-layer
//     assertion in this file — see that constant's own doc for why the
//     import is confined to a test).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/booking/application/master_archive_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/master_archive_query.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_filter_sheet.dart'
    show BookingStatusFilterGroup;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

Booking _booking({
  required String id,
  required BookingStatus status,
  bool awaitingClosure = false,
  // The server-computed «Відгук» gate (`MasterBookingCard.onReview`) — the ONE
  // field `MasterArchiveNotifier.markClientReviewed` rewrites. Defaults to
  // `false`, matching both the domain default and the mapper's fail-closed
  // coalesce, so only the tests that exercise the patch opt in.
  bool providerCanReviewClient = false,
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
  startAt: DateTime.utc(2000, 1, 1, 10),
  endAt: DateTime.utc(2000, 1, 1, 11),
  status: status,
  canReview: false,
  providerCanReviewClient: providerCanReviewClient,
  clientComment: null,
  providerComment: null,
  clientCancellationNote: null,
  masterProfessionalTitle: null,
  locationNote: null,
  awaitingClosure: awaitingClosure,
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
    retry: beauticaProviderRetry,
    // ignore: avoid_dynamic_calls
    overrides: <Object>[
      bookingRepositoryProvider.overrideWithValue(repo),
    ].cast(),
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group(
    'request shaping — partition is ALWAYS BookingPartition.history, PLUS a '
    'legacy status set, on EVERY request regardless of filter selection',
    () {
      test('default (no filter): partition=HISTORY + legacy statuses='
          '{COMPLETED, NOT_COMPLETED, CANCELLED, DECLINED} — asserted on the '
          'CAPTURED request', () async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            partition: any(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: 0,
          ),
        ).thenAnswer((_) async => _page(const <Booking>[]));
        final c = _container(repo);

        await c.read(masterArchiveProvider(MasterArchiveQuery.of()).future);

        final captured = verify(
          () => repo.getMyBookings(
            statuses: captureAny(named: 'statuses'),
            partition: captureAny(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: 0,
          ),
        ).captured;
        final Set<BookingStatus>? sentStatuses =
            captured[0] as Set<BookingStatus>?;
        final BookingPartition? sentPartition =
            captured[1] as BookingPartition?;

        expect(
          sentPartition,
          BookingPartition.history,
          reason: 'the archive is scoped to the HISTORY partition, always',
        );
        expect(
          sentPartition?.wireValue,
          'HISTORY',
          reason:
              'asserts the WIRE STRING, not just the enum member — a '
              'wireValue swap would pass an enum-only assertion',
        );
        expect(
          sentStatuses,
          const <BookingStatus>{
            BookingStatus.completed,
            BookingStatus.notCompleted,
            BookingStatus.cancelled,
            BookingStatus.declined,
          },
          reason:
              'the legacy status set must still travel on every request '
              '— best-effort HISTORY approximation for a backend old enough '
              'to have no `partition` param at all (mirrors '
              '`_legacyStatusesFor`\'s own doc for why this can never be full '
              'parity)',
        );
      });

      test('a NON-EMPTY filter selection still sends partition=HISTORY — it '
          'is never conditional on the filter', () async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            partition: any(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: 0,
          ),
        ).thenAnswer((_) async => _page(const <Booking>[]));
        final c = _container(repo);

        await c.read(
          masterArchiveProvider(
            MasterArchiveQuery.of(
              statuses: const <BookingStatus>{BookingStatus.completed},
            ),
          ).future,
        );

        verify(
          () => repo.getMyBookings(
            statuses: const <BookingStatus>{BookingStatus.completed},
            partition: BookingPartition.history,
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: 0,
          ),
        ).called(1);
      });

      test('newest-first sort is requested', () async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            partition: any(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: 0,
          ),
        ).thenAnswer((_) async => _page(const <Booking>[]));
        final c = _container(repo);

        await c.read(masterArchiveProvider(MasterArchiveQuery.of()).future);

        verify(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            partition: any(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: BookingSort.newest,
            page: 0,
          ),
        ).called(1);
      });
    },
  );

  group(
    'client-side status predicate — «Потребують закриття» is «Підтверджено» '
    'ticked alone, no new UI',
    () {
      test(
        'ticking ONLY confirmed isolates exactly the awaitingClosure rows — '
        'a fixture with non-awaiting rows proves this is not vacuous',
        () async {
          final repo = _MockBookingRepository();
          when(
            () => repo.getMyBookings(
              statuses: any(named: 'statuses'),
              partition: any(named: 'partition'),
              serviceIds: any(named: 'serviceIds'),
              sort: any(named: 'sort'),
              page: 0,
            ),
          ).thenAnswer(
            (_) async => _page(<Booking>[
              _booking(
                id: 'awaiting-1',
                status: BookingStatus.confirmed,
                awaitingClosure: true,
              ),
              _booking(id: 'completed-1', status: BookingStatus.completed),
              _booking(id: 'no-show-1', status: BookingStatus.notCompleted),
            ]),
          );
          final c = _container(repo);

          final MasterArchiveState state = await c.read(
            masterArchiveProvider(
              MasterArchiveQuery.of(
                statuses: const <BookingStatus>{BookingStatus.confirmed},
              ),
            ).future,
          );

          expect(state.items.map((Booking b) => b.id), <String>['awaiting-1']);
          expect(state.items.every((Booking b) => b.awaitingClosure), isTrue);
        },
      );

      test(
        'select-all (every BookingStatusFilterGroup row ticked) collapses to '
        '"no predicate" — a legacy NOT_COMPLETED row (which no row can '
        'individually select) STAYS visible',
        () async {
          final repo = _MockBookingRepository();
          when(
            () => repo.getMyBookings(
              statuses: any(named: 'statuses'),
              partition: any(named: 'partition'),
              serviceIds: any(named: 'serviceIds'),
              sort: any(named: 'sort'),
              page: 0,
            ),
          ).thenAnswer(
            (_) async => _page(<Booking>[
              _booking(
                id: 'a1',
                status: BookingStatus.confirmed,
                awaitingClosure: true,
              ),
              _booking(id: 'c1', status: BookingStatus.completed),
              _booking(id: 'ns1', status: BookingStatus.notCompleted),
            ]),
          );
          final c = _container(repo);

          final Set<BookingStatus> allRows = BookingStatusFilterGroup.values
              .expand((BookingStatusFilterGroup g) => g.statuses)
              .toSet();

          final MasterArchiveState state = await c.read(
            masterArchiveProvider(
              MasterArchiveQuery.of(statuses: allRows),
            ).future,
          );

          expect(state.items.map((Booking b) => b.id).toSet(), <String>{
            'a1',
            'c1',
            'ns1',
          });
        },
      );

      test('ticking ONLY cancelled against a HISTORY-partition fixture returns '
          'EXACTLY the cancelled AND declined rows — the 2026-08-16 HISTORY '
          'cutover fix (this test previously asserted the OLD, now-wrong '
          '"always empty" behaviour against a `PAST`-partition fixture; '
          'inverted here as the regression guard for the reported bug: a '
          'declined visit never appeared in the archive, and this filter '
          'always came back empty)', () async {
        final repo = _MockBookingRepository();
        // Partition-SENSITIVE stub — deliberately NOT a fixed `thenAnswer`
        // fixture. A stub that ignores which `partition` was actually
        // requested cannot fail if the notifier regresses to requesting
        // `BookingPartition.past` (the mock would keep handing back the
        // same union fixture regardless) — that gap was caught by the
        // sanity-check RED run (see the notifier's own doc / this file's
        // handoff notes) and is exactly what this stub closes: it
        // simulates what a REAL backend would actually return for each
        // partition value, so this test can only pass against a genuine
        // `partition: HISTORY` request.
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            partition: any(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: 0,
          ),
        ).thenAnswer((Invocation invocation) async {
          final BookingPartition? partition =
              invocation.namedArguments[#partition] as BookingPartition?;
          final List<Booking> pastEligible = <Booking>[
            _booking(id: 'c1', status: BookingStatus.completed),
            _booking(
              id: 'a1',
              status: BookingStatus.confirmed,
              awaitingClosure: true,
            ),
          ];
          if (partition == BookingPartition.history) {
            return _page(<Booking>[
              ...pastEligible,
              _booking(id: 'cancelled-1', status: BookingStatus.cancelled),
              _booking(id: 'declined-1', status: BookingStatus.declined),
            ]);
          }
          // A real `partition: PAST` backend response structurally never
          // contains a CANCELLED/DECLINED row — mirrors
          // `FakeBackend._partitionOf`'s own classification.
          return _page(pastEligible);
        });
        final c = _container(repo);

        final MasterArchiveState state = await c.read(
          masterArchiveProvider(
            MasterArchiveQuery.of(
              statuses: const <BookingStatus>{
                BookingStatus.cancelled,
                BookingStatus.declined,
              },
            ),
          ).future,
        );

        expect(
          state.items.map((Booking b) => b.id).toSet(),
          <String>{'cancelled-1', 'declined-1'},
          reason:
              'both statuses share the ONE «Скасовано» filter row — '
              'neither COMPLETED nor the awaitingClosure CONFIRMED row '
              'must survive it',
        );
      });

      test('a declined booking appears in the archive AT ALL with NO filter '
          'applied — the user-reported bug this cutover fixes', () async {
        final repo = _MockBookingRepository();
        // Same partition-sensitive stub shape as the test above — see its
        // comment for why a fixed fixture cannot prove this.
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            partition: any(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: 0,
          ),
        ).thenAnswer((Invocation invocation) async {
          final BookingPartition? partition =
              invocation.namedArguments[#partition] as BookingPartition?;
          final List<Booking> pastEligible = <Booking>[
            _booking(id: 'c1', status: BookingStatus.completed),
          ];
          if (partition == BookingPartition.history) {
            return _page(<Booking>[
              _booking(id: 'declined-1', status: BookingStatus.declined),
              ...pastEligible,
            ]);
          }
          return _page(pastEligible);
        });
        final c = _container(repo);

        final MasterArchiveState state = await c.read(
          masterArchiveProvider(MasterArchiveQuery.of()).future,
        );

        expect(
          state.items.map((Booking b) => b.id),
          containsAll(<String>['declined-1', 'c1']),
        );
      });

      test('an elapsed unclosed CONFIRMED (awaiting-closure) row still appears '
          'under HISTORY — the cutover must not regress the archive\'s '
          'original purpose', () async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            partition: any(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: 0,
          ),
        ).thenAnswer(
          (_) async => _page(<Booking>[
            _booking(
              id: 'awaiting-1',
              status: BookingStatus.confirmed,
              awaitingClosure: true,
            ),
          ]),
        );
        final c = _container(repo);

        final MasterArchiveState state = await c.read(
          masterArchiveProvider(MasterArchiveQuery.of()).future,
        );

        expect(state.items.map((Booking b) => b.id), <String>['awaiting-1']);
      });
    },
  );

  group('kArchiveFilterCoverage — lockstep with BookingStatusFilterGroup', () {
    test('equals the union of every BookingStatusFilterGroup row\'s statuses — '
        'a future 4th row added to the sheet MUST also update the hand-listed '
        'constant, or the select-all collapse silently stops covering it', () {
      final Set<BookingStatus> sheetCoverage = BookingStatusFilterGroup.values
          .expand((BookingStatusFilterGroup g) => g.statuses)
          .toSet();
      expect(kArchiveFilterCoverage, sheetCoverage);
    });
  });

  group('loadMore', () {
    test('appends the next RAW page\'s FILTERED subset and advances the page '
        'cursor', () async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: 0,
        ),
      ).thenAnswer(
        (_) async => _page(
          <Booking>[_booking(id: 'p0', status: BookingStatus.completed)],
          page: 0,
          totalPages: 2,
        ),
      );
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: 1,
        ),
      ).thenAnswer(
        (_) async => _page(
          <Booking>[_booking(id: 'p1', status: BookingStatus.completed)],
          page: 1,
          totalPages: 2,
        ),
      );
      final c = _container(repo);

      await c.read(masterArchiveProvider(MasterArchiveQuery.of()).future);
      await c
          .read(masterArchiveProvider(MasterArchiveQuery.of()).notifier)
          .loadMore();

      final MasterArchiveState after = c
          .read(masterArchiveProvider(MasterArchiveQuery.of()))
          .value!;
      expect(after.items.map((Booking b) => b.id), <String>['p0', 'p1']);
      expect(after.page, 1);
      expect(after.hasMore, isFalse);
      // Every raw page ALSO carries partition=HISTORY — the second call site,
      // not just `_fetchFirstPage`.
      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: BookingPartition.history,
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: 1,
        ),
      ).called(1);
    });

    test(
      'is a no-op when the raw server stream is already exhausted',
      () async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            partition: any(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: 0,
          ),
        ).thenAnswer(
          (_) async => _page(<Booking>[
            _booking(id: 'c1', status: BookingStatus.completed),
          ]),
        );
        final c = _container(repo);

        await c.read(masterArchiveProvider(MasterArchiveQuery.of()).future);
        await c
            .read(masterArchiveProvider(MasterArchiveQuery.of()).notifier)
            .loadMore();

        verify(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            partition: any(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: any(named: 'page'),
          ),
        ).called(1);
      },
    );

    test('a second loadMore fired before the first settles is a no-op (pins '
        'the isLoadingMore in-flight guard)', () async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: 0,
        ),
      ).thenAnswer(
        (_) async => _page(
          <Booking>[_booking(id: 'p0', status: BookingStatus.completed)],
          page: 0,
          totalPages: 2,
        ),
      );
      final Completer<PageResponse<Booking>> pendingPage1 =
          Completer<PageResponse<Booking>>();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: 1,
        ),
      ).thenAnswer((_) => pendingPage1.future);
      final c = _container(repo);

      await c.read(masterArchiveProvider(MasterArchiveQuery.of()).future);
      final MasterArchiveNotifier notifier = c.read(
        masterArchiveProvider(MasterArchiveQuery.of()).notifier,
      );

      final Future<void> first = notifier.loadMore();
      final Future<void> second = notifier.loadMore();

      pendingPage1.complete(
        _page(
          <Booking>[_booking(id: 'p1', status: BookingStatus.completed)],
          page: 1,
          totalPages: 2,
        ),
      );
      await first;
      await second;

      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: 1,
        ),
      ).called(1);
    });

    test(
      'a failed load-more keeps the current list and clears the spinner',
      () async {
        final repo = _MockBookingRepository();
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            partition: any(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: 0,
          ),
        ).thenAnswer(
          (_) async => _page(
            <Booking>[_booking(id: 'c1', status: BookingStatus.completed)],
            page: 0,
            totalPages: 2,
          ),
        );
        when(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            partition: any(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: 1,
          ),
        ).thenThrow(Exception('network'));
        final c = _container(repo);

        await c.read(masterArchiveProvider(MasterArchiveQuery.of()).future);
        await c
            .read(masterArchiveProvider(MasterArchiveQuery.of()).notifier)
            .loadMore();

        final MasterArchiveState after = c
            .read(masterArchiveProvider(MasterArchiveQuery.of()))
            .value!;
        expect(
          c.read(masterArchiveProvider(MasterArchiveQuery.of())).hasError,
          isFalse,
        );
        expect(after.items.map((Booking b) => b.id), <String>['c1']);
        expect(after.isLoadingMore, isFalse);
      },
    );

    // -------------------------------------------------------------------------
    // 2026-08-17 cycle 3 (mobile-perf LOW) — `loadMore` used to rebuild state
    // from the snapshot it captured BEFORE its await, so any row patch landing
    // during the round trip was silently reverted when the page arrived.
    // -------------------------------------------------------------------------
    test('a markClientReviewed landing WHILE a load-more is in flight SURVIVES '
        'the page landing — the fetched page is merged into the state as it is '
        'AFTER the await, never into the pre-await snapshot', () async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: 0,
        ),
      ).thenAnswer(
        (_) async => _page(
          <Booking>[
            _booking(
              id: 'p0',
              status: BookingStatus.completed,
              providerCanReviewClient: true,
            ),
          ],
          page: 0,
          totalPages: 2,
        ),
      );
      final Completer<PageResponse<Booking>> pendingPage1 =
          Completer<PageResponse<Booking>>();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: 1,
        ),
      ).thenAnswer((_) => pendingPage1.future);
      final c = _container(repo);
      c.listen(masterArchiveProvider(MasterArchiveQuery.of()), (_, _) {});
      await c.read(masterArchiveProvider(MasterArchiveQuery.of()).future);
      final MasterArchiveNotifier notifier = c.read(
        masterArchiveProvider(MasterArchiveQuery.of()).notifier,
      );

      final Future<void> inFlight = notifier.loadMore();
      // The user's whole journey happens inside this window: «Відгук» →
      // pre-gate/submit → pop `true` → patch, while page 1 is still on the
      // wire.
      notifier.markClientReviewed('p0');
      expect(
        c
            .read(masterArchiveProvider(MasterArchiveQuery.of()))
            .requireValue
            .items
            .single
            .providerCanReviewClient,
        isFalse,
        reason: 'precondition — the patch really did land mid-flight',
      );

      pendingPage1.complete(
        _page(
          <Booking>[
            _booking(
              id: 'p1',
              status: BookingStatus.completed,
              providerCanReviewClient: true,
            ),
          ],
          page: 1,
          totalPages: 2,
        ),
      );
      await inFlight;

      final MasterArchiveState after = c
          .read(masterArchiveProvider(MasterArchiveQuery.of()))
          .requireValue;
      expect(
        after.items.map((Booking b) => b.id).toList(),
        <String>['p0', 'p1'],
        reason:
            'the page still appends exactly once — no dropped page and no '
            'duplicated row',
      );
      expect(
        after.items.first.providerCanReviewClient,
        isFalse,
        reason:
            'THE REGRESSION — rebuilding from the pre-await snapshot would '
            'resurrect the «Відгук» CTA on a row the master just reviewed. '
            'The signal-set path would re-arm and heal it, but the '
            'pop-result-only path (backing out of an already-reviewed '
            'pre-gate, nothing submitted, nothing deposited) would not',
      );
      expect(
        after.items.last.providerCanReviewClient,
        isTrue,
        reason:
            'the appended row keeps its OWN server flag — the merge must not '
            'smear the patch across the page',
      );
      expect(after.page, 1, reason: 'the cursor still advances');
      expect(
        after.hasMore,
        isFalse,
        reason:
            'hasMore still comes from the '
            'fetched page, not from the stale snapshot',
      );
      expect(after.isLoadingMore, isFalse);
    });

    test('a load-more page that lands AFTER a refresh reset the cursor is '
        'DISCARDED — never appended onto the fresh page 0, which would leave a '
        'hole in the list and push the cursor past it', () async {
      final repo = _MockBookingRepository();
      int page0Calls = 0;
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: 0,
        ),
      ).thenAnswer((_) async {
        page0Calls++;
        return _page(
          <Booking>[
            _booking(id: 'fresh-$page0Calls', status: BookingStatus.completed),
          ],
          page: 0,
          totalPages: 2,
        );
      });
      final Completer<PageResponse<Booking>> pendingPage1 =
          Completer<PageResponse<Booking>>();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: 1,
        ),
      ).thenAnswer((_) => pendingPage1.future);
      final c = _container(repo);
      c.listen(masterArchiveProvider(MasterArchiveQuery.of()), (_, _) {});
      await c.read(masterArchiveProvider(MasterArchiveQuery.of()).future);
      final MasterArchiveNotifier notifier = c.read(
        masterArchiveProvider(MasterArchiveQuery.of()).notifier,
      );

      final Future<void> inFlight = notifier.loadMore();
      await notifier.refresh();
      pendingPage1.complete(
        _page(
          <Booking>[_booking(id: 'p1', status: BookingStatus.completed)],
          page: 1,
          totalPages: 2,
        ),
      );
      await inFlight;

      final MasterArchiveState after = c
          .read(masterArchiveProvider(MasterArchiveQuery.of()))
          .requireValue;
      expect(
        after.items.map((Booking b) => b.id).toList(),
        <String>['fresh-2'],
        reason:
            'the refresh is the authoritative answer — the in-flight page '
            'belonged to a pagination generation that no longer exists',
      );
      expect(
        after.page,
        0,
        reason:
            'the cursor must stay on the refreshed page 0; advancing it to 1 '
            'would make the NEXT load-more fetch page 2 and skip page 1 '
            'entirely',
      );
      expect(after.hasMore, isTrue);
      expect(after.isLoadingMore, isFalse);
    });
  });

  group('refresh', () {
    test('re-fetches page 0 for the SAME query', () async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: 0,
        ),
      ).thenAnswer(
        (_) async => _page(<Booking>[
          _booking(id: 'c1', status: BookingStatus.completed),
        ]),
      );
      final c = _container(repo);

      await c.read(masterArchiveProvider(MasterArchiveQuery.of()).future);
      await c
          .read(masterArchiveProvider(MasterArchiveQuery.of()).notifier)
          .refresh();

      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: BookingPartition.history,
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: 0,
        ),
      ).called(2);
    });
  });

  group('build error', () {
    test('propagates a MAPPED repository Failure as an AsyncError carrying '
        'that exact type', () async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
        ),
      ).thenAnswer((_) async => throw const NetworkFailure());
      final c = _container(repo);

      c.listen(masterArchiveProvider(MasterArchiveQuery.of()), (_, _) {});
      c.read(masterArchiveProvider(MasterArchiveQuery.of()));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final AsyncValue<MasterArchiveState> state = c.read(
        masterArchiveProvider(MasterArchiveQuery.of()),
      );
      expect(state.hasError, isTrue);
      expect(state.error, isA<NetworkFailure>());
    });
  });

  // ---------------------------------------------------------------------------
  // 2026-08-17 (mobile-perf MEDIUM) — `markClientReviewed`, the surgical
  // replacement for the bare `ref.invalidate(masterArchiveProvider)`
  // `LeaveClientFeedbackScreen` used to fire after a successful submit. The
  // whole point of the method is that it does NOT refetch, so every test here
  // asserts BOTH halves: the row changed, and the repository was never called
  // again.
  // ---------------------------------------------------------------------------
  group('markClientReviewed', () {
    /// Loads a first page of [items] and hands back the resolved container.
    Future<ProviderContainer> loaded(
      _MockBookingRepository repo,
      List<Booking> items,
    ) async {
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
        ),
      ).thenAnswer((_) async => _page(items));
      final ProviderContainer c = _container(repo);
      c.listen(masterArchiveProvider(MasterArchiveQuery.of()), (_, _) {});
      await c.read(masterArchiveProvider(MasterArchiveQuery.of()).future);
      return c;
    }

    test('flips providerCanReviewClient to false on the MATCHING row only, '
        'leaves every sibling and the paging cursor untouched, and fires NO '
        'network call', () async {
      final repo = _MockBookingRepository();
      final ProviderContainer c = await loaded(repo, <Booking>[
        _booking(
          id: 'a',
          status: BookingStatus.completed,
          providerCanReviewClient: true,
        ),
        _booking(
          id: 'b',
          status: BookingStatus.completed,
          providerCanReviewClient: true,
        ),
      ]);
      final MasterArchiveState before = c
          .read(masterArchiveProvider(MasterArchiveQuery.of()))
          .requireValue;

      c
          .read(masterArchiveProvider(MasterArchiveQuery.of()).notifier)
          .markClientReviewed('a');

      final MasterArchiveState after = c
          .read(masterArchiveProvider(MasterArchiveQuery.of()))
          .requireValue;
      expect(
        after.items.map((Booking b) => b.id).toList(),
        <String>['a', 'b'],
        reason: 'the patch must not reorder or drop rows',
      );
      expect(
        after.items.first.providerCanReviewClient,
        isFalse,
        reason: 'the reviewed row loses its «Відгук» gate',
      );
      expect(
        after.items.last.providerCanReviewClient,
        isTrue,
        reason:
            'the SIBLING row is still reviewable — proves the rewrite is '
            'row-scoped, not a blanket sweep, and keeps the assertion above '
            'non-vacuous',
      );
      expect(
        after.items.first.status,
        BookingStatus.completed,
        reason: 'no other field of the patched row may move',
      );
      expect(after.page, before.page);
      expect(after.hasMore, before.hasMore);
      // The whole reason this method exists instead of an invalidate: ONE
      // fetch total, the initial page load.
      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
        ),
      ).called(1);
    });

    test(
      'an id no loaded row carries is a NO-OP that keeps the SAME items '
      'list instance — the screen\'s day-grouping memo is identity-keyed on '
      'it, so a defensive re-allocation would silently cost an O(n) regroup',
      () async {
        final repo = _MockBookingRepository();
        final ProviderContainer c = await loaded(repo, <Booking>[
          _booking(
            id: 'a',
            status: BookingStatus.completed,
            providerCanReviewClient: true,
          ),
        ]);
        final MasterArchiveState before = c
            .read(masterArchiveProvider(MasterArchiveQuery.of()))
            .requireValue;

        c
            .read(masterArchiveProvider(MasterArchiveQuery.of()).notifier)
            .markClientReviewed('not-in-this-page');

        final MasterArchiveState after = c
            .read(masterArchiveProvider(MasterArchiveQuery.of()))
            .requireValue;
        expect(
          identical(before.items, after.items),
          isTrue,
          reason:
              'a miss must not allocate a new items list — '
              '`_MasterArchiveScreenState._groupedEntries` caches on '
              '`identical(items)`',
        );
        expect(after.items.single.providerCanReviewClient, isTrue);
      },
    );

    test('FAIL-CLOSED — the ONLY direction is true → false. Calling it on a '
        'row the server already reports as not reviewable leaves it false; '
        'nothing in this mechanism can hand a «Відгук» CTA back', () async {
      // The consumer half of the invariant documented in
      // `client_review_signal_provider.dart`'s fail-closed section (whose own
      // half — an add-only, unmodifiable set — is pinned in
      // `client_review_signal_provider_test.dart`). This method is the single
      // `copyWith(providerCanReviewClient:)` call site in `lib/`, and the
      // value it writes is a hardcoded `false`; a regression to
      // `!b.providerCanReviewClient` or to a caller-supplied bool would show
      // up here as a resurrected `true`.
      final repo = _MockBookingRepository();
      final ProviderContainer c = await loaded(repo, <Booking>[
        _booking(id: 'a', status: BookingStatus.completed),
      ]);
      expect(
        c
            .read(masterArchiveProvider(MasterArchiveQuery.of()))
            .requireValue
            .items
            .single
            .providerCanReviewClient,
        isFalse,
        reason: 'precondition — the fixture row starts NOT reviewable',
      );

      bool flagNow() => c
          .read(masterArchiveProvider(MasterArchiveQuery.of()))
          .requireValue
          .items
          .single
          .providerCanReviewClient;

      c
          .read(masterArchiveProvider(MasterArchiveQuery.of()).notifier)
          .markClientReviewed('a');
      expect(
        flagNow(),
        isFalse,
        reason:
            'a toggle-shaped regression (`!b.providerCanReviewClient`) shows '
            'up HERE, on the first call — asserting only after an even number '
            'of calls would let it pass',
      );

      // And again, because an idempotence-shaped regression would only show
      // up on a repeat.
      c
          .read(masterArchiveProvider(MasterArchiveQuery.of()).notifier)
          .markClientReviewed('a');
      expect(flagNow(), isFalse);
      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
        ),
      ).called(1);
    });

    test(
      'a REPEAT call on a row already patched to false keeps the SAME items '
      'list instance — the guard tests the FLAG, not merely id presence',
      () async {
        // 2026-08-17 cycle 3 (mobile-perf LOW). Both patch paths can fire for
        // the same booking (the pop result AND the signal set — see
        // `leave_client_feedback_screen.dart`'s `_submit`), and the second
        // arrival must be a genuine no-op rather than a no-op-by-frame-
        // ordering. An id-presence-only guard passes every OTHER test in this
        // group while still re-allocating `items` here, busting
        // `_MasterArchiveScreenState._groupedEntries`' identity memo and
        // forcing an O(n) regroup + full `ListView` rebuild for no visible
        // change.
        final repo = _MockBookingRepository();
        final ProviderContainer c = await loaded(repo, <Booking>[
          _booking(
            id: 'a',
            status: BookingStatus.completed,
            providerCanReviewClient: true,
          ),
          _booking(
            id: 'b',
            status: BookingStatus.completed,
            providerCanReviewClient: true,
          ),
        ]);
        final MasterArchiveNotifier notifier = c.read(
          masterArchiveProvider(MasterArchiveQuery.of()).notifier,
        );

        notifier.markClientReviewed('a');
        final MasterArchiveState patched = c
            .read(masterArchiveProvider(MasterArchiveQuery.of()))
            .requireValue;
        expect(
          patched.items.first.providerCanReviewClient,
          isFalse,
          reason: 'precondition — the FIRST call must genuinely patch',
        );

        notifier.markClientReviewed('a');

        final MasterArchiveState again = c
            .read(masterArchiveProvider(MasterArchiveQuery.of()))
            .requireValue;
        expect(
          identical(patched.items, again.items),
          isTrue,
          reason:
              'the second call found nothing patchable and must not allocate '
              'a new list',
        );
        expect(
          identical(patched, again),
          isTrue,
          reason:
              'and must not emit a new state at all — a fresh AsyncData here '
              'rebuilds every consumer of this provider',
        );
        expect(
          again.items.last.providerCanReviewClient,
          isTrue,
          reason:
              'keeps the identity assertions non-vacuous: a still-reviewable '
              'sibling exists, so "nothing to patch" is about the FLAG on row '
              'a, not about an all-false list',
        );
      },
    );

    test('is a NO-OP while the notifier holds an ERROR — never launders the '
        'failure into AsyncData', () async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
        ),
      ).thenAnswer((_) async => throw const NetworkFailure());
      final ProviderContainer c = _container(repo);
      c.listen(masterArchiveProvider(MasterArchiveQuery.of()), (_, _) {});
      c.read(masterArchiveProvider(MasterArchiveQuery.of()));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        c.read(masterArchiveProvider(MasterArchiveQuery.of())).hasError,
        isTrue,
        reason: 'precondition — the fixture must really be in the error state',
      );

      c
          .read(masterArchiveProvider(MasterArchiveQuery.of()).notifier)
          .markClientReviewed('a');

      final AsyncValue<MasterArchiveState> state = c.read(
        masterArchiveProvider(MasterArchiveQuery.of()),
      );
      expect(state.hasError, isTrue);
      expect(state.error, isA<NetworkFailure>());
      expect(
        state.hasValue,
        isFalse,
        reason:
            'writing an AsyncData here would fabricate an empty archive out '
            'of a failed fetch',
      );
    });
  });

  group('MasterArchiveQuery — family key canonicalisation', () {
    test('two Sets built in different insertion order canonicalise to the '
        'SAME query — hits the SAME cached provider instance, no duplicate '
        'fetch', () async {
      final repo = _MockBookingRepository();
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: 0,
        ),
      ).thenAnswer((_) async => _page(const <Booking>[]));
      final c = _container(repo);

      final MasterArchiveQuery a = MasterArchiveQuery.of(
        statuses: const <BookingStatus>{
          BookingStatus.completed,
          BookingStatus.confirmed,
        },
      );
      final MasterArchiveQuery b = MasterArchiveQuery.of(
        statuses: const <BookingStatus>{
          BookingStatus.confirmed,
          BookingStatus.completed,
        },
      );
      expect(a, b);

      await c.read(masterArchiveProvider(a).future);
      await c.read(masterArchiveProvider(b).future);

      // ONE fetch, not two — `a` and `b` are the same family member.
      verify(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: 0,
        ),
      ).called(1);
    });
  });
}
