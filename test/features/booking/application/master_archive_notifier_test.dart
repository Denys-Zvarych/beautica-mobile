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
