// Mobile-qa (Step 2.7 Rule 3b) — pure-Dart proof that
// `FakeBackend.seedManyBookingsDataset` / `_slicedBookingsPageEnvelope`
// (`integration_test/support/fake_backend.dart`) actually implements a REAL
// (statuses, sort, page) slice over a whole in-memory table, rather than
// returning a hand-picked bucket per call — the exact fake-dishonesty
// pattern that let Bug A (per-status fan-out+merge) and Bug B (dropped
// `sort` param) ship green in the first place.
//
// WHY THIS FILE EXISTS SEPARATELY FROM THE INTEGRATION FLOW
// -----------------------------------------------------------
// `integration_test/client_my_bookings_pagination_sort_flow_test.dart` is the
// Step 2.7 Rule 3b gate: it drives the REAL widget tree (screen → notifier →
// repository → this fake) end-to-end and is the authoritative regression
// test. It requires a connected device/emulator to run (the VM-service
// websocket the `integration_test` binding drives over) — infra this
// sandboxed session could not reach (no drivable Android device — see the
// project's host-only-adapter notes on driving integration tests from this
// VM). This file hits the SAME fake directly via its own `Dio` instance — no
// widget tree, no device — as an offline proof the slicing algorithm itself
// is correct, so the integration flow's fixtures are validated even where
// the full E2E could not be executed in this environment. It does NOT
// replace the integration flow — it has no go_router, no screen, no
// Riverpod notifier in the loop, so it cannot catch a UI-wiring regression
// the way the real flow can.

import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/fake_backend.dart';

Future<Map<String, dynamic>> _fetch(
  FakeBackend fb, {
  required List<String> statuses,
  String? sort,
  required int page,
}) async {
  final response = await fb.dio.get<Map<String, dynamic>>(
    '/api/v1/bookings/me',
    queryParameters: <String, dynamic>{
      'page': page,
      'size': 20,
      'sort': ?sort,
      if (statuses.isNotEmpty) 'status': statuses,
    },
  );
  return response.data!;
}

List<String> _ids(Map<String, dynamic> envelope) {
  final data = envelope['data'] as Map<String, dynamic>;
  final rows = data['data'] as List<dynamic>;
  return rows
      .map((dynamic r) => (r as Map<String, dynamic>)['id'] as String)
      .toList(growable: false);
}

void main() {
  group('FakeBackend.seedManyBookingsDataset — real (statuses, sort, page) '
      'slice, not hand-picked buckets', () {
    late FakeBackend fb;

    setUp(() {
      fb = FakeBackend();
    });

    test('ascending sort returns the soonest N first, from a SCRAMBLED '
        'insertion-order dataset — proves the fake actually sorts (insertion '
        'order could not accidentally pass)', () async {
      const List<int> scrambled = <int>[
        13, 1, 22, 7, 18, 3, 25, 10, 5, 20, //
        2, 16, 9, 24, 4, 19, 11, 6, 23, 8, //
        15, 21, 12, 17, 14,
      ];
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        for (final int offset in scrambled)
          fb.datasetBookingRow(
            id: 'u$offset',
            status: 'CONFIRMED',
            startsAt: kFixedNow.add(Duration(days: offset)),
          ),
      ]);

      final Map<String, dynamic> page0 = await _fetch(
        fb,
        statuses: const <String>['CONFIRMED'],
        sort: 'startsAt,asc',
        page: 0,
      );

      expect(_ids(page0), <String>[for (int i = 1; i <= 20; i++) 'u$i']);
      final data = page0['data'] as Map<String, dynamic>;
      expect(data['totalElements'], 25);
      expect(data['totalPages'], 2);
    });

    test('Bug B reproduction: NO `sort` param at all → the fake falls back to '
        'the REAL backend\'s documented default (startsAt,DESC) → page 0 '
        'starts with the FARTHEST-future booking — exactly the pre-fix '
        'symptom (soonest appointment invisible)', () async {
      const List<int> scrambled = <int>[
        13, 1, 22, 7, 18, 3, 25, 10, 5, 20, //
        2, 16, 9, 24, 4, 19, 11, 6, 23, 8, //
        15, 21, 12, 17, 14,
      ];
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        for (final int offset in scrambled)
          fb.datasetBookingRow(
            id: 'u$offset',
            status: 'CONFIRMED',
            startsAt: kFixedNow.add(Duration(days: offset)),
          ),
      ]);

      final Map<String, dynamic> noSortSent = await _fetch(
        fb,
        statuses: const <String>['CONFIRMED'],
        sort: null, // simulates the repository dropping the `sort` param
        page: 0,
      );

      expect(
        _ids(noSortSent).first,
        'u25',
        reason:
            'no `sort` param → fake defaults to desc (mirrors the real '
            'backend) → page 0 leads with the farthest-future booking',
      );
    });

    test(
      'multi-status descending sort unions BOTH statuses and pages to '
      'exhaustion with no drop, no duplicate, no reshuffle across pages — '
      'the exact property Bug A (per-status fan-out+merge) violated',
      () async {
        const List<int> pastOffsets = <int>[
          31, 4, 17, 40, 9, 22, 45, 2, 28, 13, //
          36, 7, 19, 44, 1, 25, 38, 11, 30, 5, //
          16, 41, 8, 23, 34, 3, 27, 42, 14, 20, //
          6, 33, 10, 29, 39, 18, 43, 15, 26, 35, //
          12, 21, 37, 24, 32,
        ];
        fb.seedManyBookingsDataset(<Map<String, dynamic>>[
          for (final int offset in pastOffsets)
            fb.datasetBookingRow(
              id: 'p$offset',
              status: offset.isOdd ? 'COMPLETED' : 'NOT_COMPLETED',
              startsAt: kFixedNow.subtract(Duration(days: offset)),
            ),
        ]);

        // Mirrors [MyBookingsNotifier]'s own stopping condition: stop once
        // `page + 1 >= totalPages` (the server-reported `hasMore`), NEVER by
        // probing an extra page past exhaustion — an extra probe call would
        // misattribute a call this loop itself made as a "fan-out", muddying
        // the very count this test pins.
        final List<String> collected = <String>[];
        int pagesFetched = 0;
        int page = 0;
        while (true) {
          final Map<String, dynamic> envelope = await _fetch(
            fb,
            statuses: const <String>['COMPLETED', 'NOT_COMPLETED'],
            sort: 'startsAt,desc',
            page: page,
          );
          pagesFetched++;
          collected.addAll(_ids(envelope));
          final data = envelope['data'] as Map<String, dynamic>;
          final bool hasMore =
              (data['page'] as int) + 1 < (data['totalPages'] as int);
          if (!hasMore) break;
          page++;
        }

        expect(
          collected,
          <String>[for (int i = 1; i <= 45; i++) 'p$i'],
          reason:
              'exact global descending order across ALL pages — the union '
              'of two >20-count statuses, correctly interleaved, with no '
              'drop and no reshuffle',
        );
        expect(collected.toSet(), hasLength(45), reason: 'no duplicates');
        expect(pagesFetched, 3, reason: '20+20+5 = 3 pages to exhaustion');
        expect(
          fb.getMyBookingsCalls,
          pagesFetched,
          reason:
              'ONE HTTP call per page fetched by THIS loop — proves the '
              'fake itself does no hidden fan-out either',
        );
      },
    );

    test('an empty statuses filter omits the status param — mirrors the '
        'real repository sending no filter for "all statuses"', () async {
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'a1',
          status: 'CONFIRMED',
          startsAt: kFixedNow.add(const Duration(days: 1)),
        ),
        fb.datasetBookingRow(
          id: 'a2',
          status: 'CANCELLED',
          startsAt: kFixedNow.subtract(const Duration(days: 1)),
        ),
      ]);

      final Map<String, dynamic> envelope = await _fetch(
        fb,
        statuses: const <String>[],
        sort: 'startsAt,desc',
        page: 0,
      );

      expect(_ids(envelope).toSet(), <String>{'a1', 'a2'});
    });

    test(
      'totalPages/hasMore derive correctly from the sliced dataset size',
      () async {
        fb.seedManyBookingsDataset(<Map<String, dynamic>>[
          for (int i = 1; i <= 21; i++)
            fb.datasetBookingRow(
              id: 'h$i',
              status: 'CONFIRMED',
              startsAt: kFixedNow.add(Duration(days: i)),
            ),
        ]);

        final Map<String, dynamic> page0 = await _fetch(
          fb,
          statuses: const <String>['CONFIRMED'],
          sort: 'startsAt,asc',
          page: 0,
        );
        final data0 = page0['data'] as Map<String, dynamic>;
        expect(data0['totalPages'], 2);
        expect(data0['totalElements'], 21);
        expect(_ids(page0), hasLength(20));

        final Map<String, dynamic> page1 = await _fetch(
          fb,
          statuses: const <String>['CONFIRMED'],
          sort: 'startsAt,asc',
          page: 1,
        );
        expect(_ids(page1), <String>['h21']);
        final data1 = page1['data'] as Map<String, dynamic>;
        expect(data1['totalPages'], 2);
        // page 1 IS the last page (index 1 of 2 total, zero-based).
        expect((data1['page'] as int) + 1, data1['totalPages']);
      },
    );

    // ══════════════════════════════════════════════════════════════════════
    // DAY WINDOW (`from`/`to`) — 2026-08-17
    // ══════════════════════════════════════════════════════════════════════
    // The slice used to filter by `partition`/`status` ONLY and silently
    // ignore `from`/`to`, so a day-scoped request (what `bookingsDayProvider`
    // sends for the master's «Мої записи» timeline) got the WHOLE dataset.
    // That is the same class of fake-dishonesty as Bug A/Bug B above, and it
    // was not harmless: it made `master_archive_flow_test.dart` scenario 2
    // hang UNBOUNDEDLY, because a 2020 fixture row reaching a single-day
    // timeline drove `BookingsTimelineGrid` to build ~56 500 hour rows —
    // a synchronous loop that starves the event loop, so no timer-based
    // deadline anywhere in the harness could fire.
    group('the inclusive [from, to] local-day window', () {
      // `kyivDayOf` below reads `beauticaZone`, which throws until the IANA
      // database is loaded — the app boots it in `main`, a pure-Dart suite has
      // to do it itself (same `setUpAll` as
      // `test/features/booking/presentation/bookings_timeline_grid_test.dart`).
      setUpAll(initBeauticaTimeZones);

      Future<Map<String, dynamic>> fetchDays(
        FakeBackend fb, {
        String? from,
        String? to,
      }) async {
        final response = await fb.dio.get<Map<String, dynamic>>(
          '/api/v1/bookings/me',
          queryParameters: <String, dynamic>{
            'page': 0,
            'size': 20,
            'sort': 'startsAt,asc',
            'from': ?from,
            'to': ?to,
          },
        );
        return response.data!;
      }

      // Kyiv days, derived from the injected clock — never absolute literals
      // (`scripts/forbid_stale_future_date_fixture.sh` rule (c)).
      String apiDay(DateTime instant) =>
          kyivDayOf(instant).toIso8601String().substring(0, 10);

      final DateTime today = kFixedNow;
      final DateTime tomorrow = kFixedNow.add(const Duration(days: 1));
      final DateTime longAgo = kFixedNow.subtract(const Duration(days: 2000));

      void seedThreeDays(FakeBackend fb) {
        fb.seedManyBookingsDataset(<Map<String, dynamic>>[
          fb.datasetBookingRow(
            id: 'today-1',
            status: 'CONFIRMED',
            startsAt: today,
          ),
          fb.datasetBookingRow(
            id: 'tomorrow-1',
            status: 'CONFIRMED',
            startsAt: tomorrow,
          ),
          fb.datasetBookingRow(
            id: 'long-ago-1',
            status: 'COMPLETED',
            startsAt: longAgo,
          ),
        ]);
      }

      test('a single-day request returns ONLY that Kyiv day — a row years '
          'outside the window can never come back', () async {
        seedThreeDays(fb);

        final Map<String, dynamic> envelope = await fetchDays(
          fb,
          from: apiDay(today),
          to: apiDay(today),
        );

        expect(
          _ids(envelope),
          <String>['today-1'],
          reason:
              'the day-scoped request asked for ONE Kyiv day; returning the '
              'far-past row too is the divergence that hung '
              'master_archive_flow_test scenario 2',
        );
        final data = envelope['data'] as Map<String, dynamic>;
        expect(
          data['totalElements'],
          1,
          reason:
              'the count must be the WINDOWED count, not the whole table — '
              'a caller that trusts totalElements would otherwise page into '
              'rows the window excludes',
        );
      });

      test('the window is INCLUSIVE on both ends', () async {
        seedThreeDays(fb);

        final Map<String, dynamic> envelope = await fetchDays(
          fb,
          from: apiDay(today),
          to: apiDay(tomorrow),
        );

        expect(_ids(envelope), <String>['today-1', 'tomorrow-1']);
      });

      test('an ABSENT window still returns the whole table — the pre-existing '
          'behaviour every non-day-scoped caller depends on', () async {
        seedThreeDays(fb);

        final Map<String, dynamic> envelope = await fetchDays(fb);

        expect(_ids(envelope), <String>[
          'long-ago-1',
          'today-1',
          'tomorrow-1',
        ], reason: 'ascending by startsAt, unfiltered');
      });

      test('`from` alone is an open-ended FORWARD window, `to` alone an '
          'open-ended BACKWARD one — the two params are independently '
          'optional on the real endpoint', () async {
        seedThreeDays(fb);

        expect(await fetchDays(fb, from: apiDay(today)).then(_ids), <String>[
          'today-1',
          'tomorrow-1',
        ]);
        expect(await fetchDays(fb, to: apiDay(today)).then(_ids), <String>[
          'long-ago-1',
          'today-1',
        ]);
      });
    });
  });

  group('FakeBackend.lastMyBookingsQuery — recorded unconditionally, not '
      'only on the seeded-dataset path', () {
    // Regression test for the bug that failed `master_bookings_flow_test`
    // (`:139-144`, `:406-407`): the assignment used to live INSIDE
    // `_slicedBookingsPageEnvelope`, which only runs once
    // `seedManyBookingsDataset` has been called. Every flow that never seeds
    // a dataset — the master-bookings flow included — took the
    // `_bookingsPageEnvelope` fallback branch and `lastMyBookingsQuery`
    // stayed `null` forever, even though the request genuinely reached the
    // fake and the screen rendered real data. This test exercises exactly
    // that fallback path — no `seedManyBookingsDataset` call anywhere.
    test('a GET /bookings/me hit records lastMyBookingsQuery even when '
        'seedManyBookingsDataset was NEVER called', () async {
      final fb = FakeBackend();

      expect(
        fb.lastMyBookingsQuery,
        isNull,
        reason: 'no /bookings/me request has been made yet',
      );

      await fb.dio.get<Map<String, dynamic>>(
        '/api/v1/bookings/me',
        queryParameters: <String, dynamic>{
          'from': '2026-07-20',
          'to': '2026-07-20',
        },
      );

      expect(
        fb.lastMyBookingsQuery,
        isNotNull,
        reason:
            'the fallback (non-dataset) branch must record the query too '
            '— a last*Query telemetry field that only populates on an '
            'opt-in path is a silent-null footgun',
      );
      expect(fb.lastMyBookingsQuery!['from'], '2026-07-20');
      expect(fb.lastMyBookingsQuery!['to'], '2026-07-20');
    });
  });

  // Phase 345 D3/D6 — the salon-archive slice and the auto-continue
  // measurement. Kept in a separate top-level function purely so the two
  // concerns read apart; it runs in the SAME suite.
  mainPhase345();
}

// ════════════════════════════════════════════════════════════════════════════
// Phase 345 D3 / D6 — the SALON ARCHIVE slice, and the auto-continue
// measurement phase 343 D6 deferred to this phase's fixture.
//
// WHY THIS LIVES HERE AND NOT ONLY IN THE E2E ARM
// -----------------------------------------------
// D2's hazard is that a fake which IGNORES `partition` makes every archive
// assertion in `integration_test/salon_archive_flow_test.dart` pass while the
// app could be sending anything at all. That is a property of the FAKE, and
// the cheapest honest place to pin a property of the fake is against the fake
// itself, with no widget tree in the loop to hide behind. The E2E arm then
// gets to be about the app.
//
// It is also the measurement instrument for D6. The number D6 wants — how many
// `_kMaxAutoContinueAttempts` a filtered salon archive actually burns — is
// determined entirely by WHERE the first matching row sits in the newest-first
// HISTORY stream. Simulating the walk against the real slice answers that
// exactly, deterministically, and in milliseconds; driving 36 raw pages
// through the widget tree would answer the same question slower and with more
// ways to be wrong.
// ════════════════════════════════════════════════════════════════════════════

/// One `GET /bookings/salon/{id}` as the ARCHIVE sends it (`partition`, `sort`,
/// `page`, no `from`/`to`) — or, with [partition] null, as the BOARD does.
Future<Map<String, dynamic>> _salonFetch(
  FakeBackend fb, {
  String? partition,
  int page = 0,
  List<String> statuses = const <String>[],
  String? from,
  String? to,
  String salonId = FakeBackend.kOwnerSalonId,
}) async {
  final response = await fb.dio.get<Map<String, dynamic>>(
    '/api/v1/bookings/salon/$salonId',
    queryParameters: <String, dynamic>{
      'page': page,
      'size': 20,
      'sort': 'startsAt,desc',
      'partition': ?partition,
      if (statuses.isNotEmpty) 'status': statuses,
      'from': ?from,
      'to': ?to,
    },
  );
  return response.data!;
}

List<Map<String, dynamic>> _rows(Map<String, dynamic> envelope) {
  final data = envelope['data'] as Map<String, dynamic>;
  return (data['data'] as List<dynamic>).cast<Map<String, dynamic>>().toList(
    growable: false,
  );
}

int _totalPages(Map<String, dynamic> envelope) =>
    (envelope['data'] as Map<String, dynamic>)['totalPages'] as int;

/// Replays `_MasterArchiveScreenState`'s auto-continue walk against the real
/// slice and returns the number of EXTRA `loadMore` round trips it took before
/// a raw page yielded at least one row matching [predicate] — i.e. the raw
/// page index of the first match.
///
/// Returns `-1` when the server is exhausted with no match at all (which is
/// the TERMINAL EMPTY state, not a budget problem — the walk stops on
/// `hasMore == false` and the screen renders `_ArchiveEmptyState`).
///
/// This is the quantity `_kMaxAutoContinueAttempts` bounds: the counter starts
/// at 0, the page-0 fetch is not an attempt, and attempts 1..N fetch raw pages
/// 1..N. So the budget is exhausted — and `_ArchiveContinueState` renders —
/// exactly when this returns a value strictly greater than the constant.
Future<int> _attemptsUntilFirstMatch(
  FakeBackend fb,
  Set<String> predicate,
) async {
  int page = 0;
  while (true) {
    final Map<String, dynamic> envelope = await _salonFetch(
      fb,
      partition: 'HISTORY',
      page: page,
    );
    final bool matched = _rows(
      envelope,
    ).any((Map<String, dynamic> r) => predicate.contains(r['status']));
    if (matched) return page;
    if (page >= _totalPages(envelope) - 1) return -1;
    page++;
  }
}

void mainPhase345() {
  group('Phase 345 — GET /bookings/salon/{id} branches on `partition`', () {
    late FakeBackend fb;
    // A far-past anchor, pinned — never a host-clock read. `FakeBackend
    // .serverNow` defaults to `kFixedNow`, and `_partitionOf` classifies
    // CONFIRMED against it, so "elapsed" has to be measured from the same
    // instant the fake will measure it from.
    final DateTime anchor = kFixedNow;

    setUp(() {
      fb = FakeBackend();
    });

    test('WITHOUT `partition` the board branch is byte-identical to pre-345: '
        'the whole salonBoardBookings list, one page, archive counters '
        'untouched', () async {
      fb.salonBoardBookings = <Map<String, dynamic>>[
        fb.salonBoardBookingRow(
          id: 'board-1',
          masterId: 'master-aaa',
          masterFirstName: 'Софія',
          masterLastName: 'Бондар',
          startsAt: anchor.add(const Duration(hours: 2)),
        ),
      ];
      fb.salonArchiveBookings = <Map<String, dynamic>>[
        fb.salonBoardBookingRow(
          id: 'hist-1',
          masterId: 'master-bbb',
          masterFirstName: 'Олена',
          masterLastName: 'Ткаченко',
          startsAt: anchor.subtract(const Duration(days: 3)),
          status: 'COMPLETED',
        ),
      ];

      final Map<String, dynamic> envelope = await _salonFetch(
        fb,
        from: '2026-06-14',
        to: '2026-06-14',
      );

      expect(
        _rows(envelope).map((Map<String, dynamic> r) => r['id']),
        <String>['board-1'],
        reason:
            'the board branch must keep serving salonBoardBookings — the '
            'archive list is a different list and must not leak into it',
      );
      expect(fb.getSalonBookingsCalls, 1);
      expect(
        fb.getSalonArchiveCalls,
        0,
        reason: 'no `partition` was sent, so this was not an archive read',
      );
      expect(fb.lastSalonArchiveQuery, isNull);
    });

    test('WITH `partition=HISTORY` the archive branch serves '
        'salonArchiveBookings — NOT the board list. This is the D2 '
        'discriminator: a handler that stopped reading `partition` would '
        'serve the board\'s rows here', () async {
      fb.salonBoardBookings = <Map<String, dynamic>>[
        fb.salonBoardBookingRow(
          id: 'board-1',
          masterId: 'master-aaa',
          masterFirstName: 'Софія',
          masterLastName: 'Бондар',
          startsAt: anchor.add(const Duration(hours: 2)),
        ),
      ];
      fb.salonArchiveBookings = <Map<String, dynamic>>[
        fb.salonBoardBookingRow(
          id: 'hist-1',
          masterId: 'master-bbb',
          masterFirstName: 'Олена',
          masterLastName: 'Ткаченко',
          startsAt: anchor.subtract(const Duration(days: 3)),
          status: 'COMPLETED',
        ),
      ];

      final Map<String, dynamic> envelope = await _salonFetch(
        fb,
        partition: 'HISTORY',
      );

      expect(_rows(envelope).map((Map<String, dynamic> r) => r['id']), <String>[
        'hist-1',
      ]);
      expect(fb.getSalonArchiveCalls, 1);
      expect(fb.lastSalonArchiveQuery!['partition'], 'HISTORY');
    });

    test('HISTORY is `everything except UPCOMING`: an elapsed unclosed '
        'CONFIRMED row IS returned and a future CONFIRMED row is NOT — the '
        'one row `_legacyStatusesFor`\'s status-only fallback structurally '
        'cannot reach (D3 axis 3)', () async {
      fb.salonArchiveBookings = <Map<String, dynamic>>[
        fb.salonBoardBookingRow(
          id: 'elapsed-open',
          masterId: 'master-aaa',
          masterFirstName: 'Софія',
          masterLastName: 'Бондар',
          startsAt: anchor.subtract(const Duration(days: 2)),
          status: 'CONFIRMED',
          awaitingClosure: true,
        ),
        fb.salonBoardBookingRow(
          id: 'still-upcoming',
          masterId: 'master-bbb',
          masterFirstName: 'Олена',
          masterLastName: 'Ткаченко',
          startsAt: anchor.add(const Duration(days: 2)),
          status: 'CONFIRMED',
        ),
        fb.salonBoardBookingRow(
          id: 'done',
          masterId: 'master-ccc',
          masterFirstName: 'Марія',
          masterLastName: 'Гриценко',
          startsAt: anchor.subtract(const Duration(days: 4)),
          status: 'COMPLETED',
        ),
        fb.salonBoardBookingRow(
          id: 'gone',
          masterId: 'master-ddd',
          masterFirstName: 'Ірина',
          masterLastName: 'Мельник',
          startsAt: anchor.subtract(const Duration(days: 5)),
          status: 'CANCELLED',
        ),
        fb.salonBoardBookingRow(
          id: 'refused',
          masterId: 'master-eee',
          masterFirstName: 'Наталія',
          masterLastName: 'Савченко',
          startsAt: anchor.subtract(const Duration(days: 6)),
          status: 'DECLINED',
        ),
        fb.salonBoardBookingRow(
          id: 'no-show',
          masterId: 'master-fff',
          masterFirstName: 'Дарина',
          masterLastName: 'Кравець',
          startsAt: anchor.subtract(const Duration(days: 7)),
          status: 'NOT_COMPLETED',
        ),
      ];

      final Map<String, dynamic> envelope = await _salonFetch(
        fb,
        partition: 'HISTORY',
      );
      final List<Object?> ids = _rows(
        envelope,
      ).map((Map<String, dynamic> r) => r['id']).toList();

      expect(
        ids,
        containsAll(<String>[
          'elapsed-open',
          'done',
          'gone',
          'refused',
          'no-show',
        ]),
        reason: 'HISTORY = PAST ∪ CANCELLED = everything except UPCOMING',
      );
      expect(
        ids,
        isNot(contains('still-upcoming')),
        reason:
            'a CONFIRMED row that has NOT elapsed is UPCOMING — serving it '
            'here would make the fixture unable to tell a partition read '
            'from an unfiltered dump',
      );
      // Newest-first, which is what the archive's `sort: newest` asks for.
      expect(ids.first, 'elapsed-open');
    });

    test('`status` is IGNORED when `partition` is present — backend 322 D2\'s '
        'precedence rule, which is the WHOLE reason the outcome filter is '
        'client-side and the auto-continue walk exists at all', () async {
      fb.salonArchiveBookings = <Map<String, dynamic>>[
        fb.salonBoardBookingRow(
          id: 'done',
          masterId: 'master-aaa',
          masterFirstName: 'Софія',
          masterLastName: 'Бондар',
          startsAt: anchor.subtract(const Duration(days: 1)),
          status: 'COMPLETED',
        ),
        fb.salonBoardBookingRow(
          id: 'gone',
          masterId: 'master-bbb',
          masterFirstName: 'Олена',
          masterLastName: 'Ткаченко',
          startsAt: anchor.subtract(const Duration(days: 2)),
          status: 'CANCELLED',
        ),
      ];

      final Map<String, dynamic> envelope = await _salonFetch(
        fb,
        partition: 'HISTORY',
        // The legacy rollout-valve set the notifier always sends alongside.
        statuses: const <String>['COMPLETED'],
      );

      expect(
        _rows(envelope).length,
        2,
        reason:
            'if `status` narrowed this to 1 row, the fake would be modelling '
            'a backend that does not exist and the client-side filter would '
            'look free',
      );
    });

    test(
      'the archive branch PAGES for real: 25 HISTORY rows come back as '
      '20 + 5 across two pages, newest-first, with no row served twice',
      () async {
        fb.salonArchiveBookings = <Map<String, dynamic>>[
          for (int i = 0; i < 25; i++)
            fb.salonBoardBookingRow(
              id: 'h-$i',
              masterId: 'master-aaa',
              masterFirstName: 'Софія',
              masterLastName: 'Бондар',
              startsAt: anchor.subtract(Duration(days: i + 1)),
              status: 'COMPLETED',
            ),
        ];

        final Map<String, dynamic> p0 = await _salonFetch(
          fb,
          partition: 'HISTORY',
        );
        final Map<String, dynamic> p1 = await _salonFetch(
          fb,
          partition: 'HISTORY',
          page: 1,
        );

        expect(_rows(p0).length, 20);
        expect(_rows(p1).length, 5);
        expect(_totalPages(p0), 2);
        expect(
          _rows(p0).first['id'],
          'h-0',
          reason: 'newest-first — h-0 is one day before the anchor',
        );
        expect(_rows(p1).first['id'], 'h-20');
        final Set<Object?> allIds = <Object?>{
          ..._rows(p0).map((Map<String, dynamic> r) => r['id']),
          ..._rows(p1).map((Map<String, dynamic> r) => r['id']),
        };
        expect(allIds.length, 25, reason: 'no row served on both pages');
        expect(fb.getSalonArchiveCalls, 2);
      },
    );

    test('the SALON_ADMIN salon id shares the SAME branching body — the two '
        'registrations cannot drift on what `partition` means', () async {
      fb.salonArchiveBookings = <Map<String, dynamic>>[
        fb.salonBoardBookingRow(
          id: 'hist-admin',
          masterId: 'master-aaa',
          masterFirstName: 'Софія',
          masterLastName: 'Бондар',
          startsAt: anchor.subtract(const Duration(days: 3)),
          status: 'COMPLETED',
        ),
      ];

      final Map<String, dynamic> envelope = await _salonFetch(
        fb,
        partition: 'HISTORY',
        salonId: FakeBackend.kAdminSalonId,
      );

      expect(_rows(envelope).map((Map<String, dynamic> r) => r['id']), <String>[
        'hist-admin',
      ]);
      expect(fb.getSalonArchiveCalls, 1);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // D6 / D10 — THE MEASUREMENT
  // ══════════════════════════════════════════════════════════════════════════
  group('Phase 345 D6 — `_kMaxAutoContinueAttempts` measured against the '
      'roster-scale salon fixture', () {
    late FakeBackend fb;
    final DateTime anchor = kFixedNow;

    // Kept in lockstep with `_MasterArchiveScreenState._kMaxAutoContinueAttempts`
    // by the assertions below reading as "budget", not as a bare 3. If that
    // constant ever moves, these cases state what moving it would buy.
    const int budget = 3;

    setUp(() {
      fb = FakeBackend();
      fb.salonArchiveBookings = FakeBackend.salonArchiveRosterScaleFixture(
        fb,
        anchor: anchor,
      );
    });

    test('the fixture is genuinely roster-scale: 8 masters × 90 days = 720 '
        'HISTORY rows across 36 raw pages, all five outcomes present', () async {
      expect(fb.salonArchiveBookings.length, 720);
      final Map<String, dynamic> p0 = await _salonFetch(
        fb,
        partition: 'HISTORY',
      );
      expect(
        _totalPages(p0),
        36,
        reason:
            'every row is HISTORY — a fixture that lost rows to the partition '
            'filter would make every attempt count below an understatement',
      );
      final Set<Object?> statuses = fb.salonArchiveBookings
          .map((Map<String, dynamic> r) => r['status'])
          .toSet();
      expect(statuses, <String>{
        'COMPLETED',
        'CANCELLED',
        'DECLINED',
        'NOT_COMPLETED',
        'CONFIRMED',
      });
      expect(
        fb.salonArchiveBookings.where(
          (Map<String, dynamic> r) => r['awaitingClosure'] == true,
        ),
        isNotEmpty,
        reason: 'the elapsed-unclosed rows are what «Підтверджено» selects',
      );
      expect(
        fb.salonArchiveBookings.where(
          (Map<String, dynamic> r) => r['providerCanReviewClient'] == true,
        ),
        isNotEmpty,
        reason: 'D3 axis 2 — the fixture must carry BOTH flag values',
      );
    });

    test('MEASUREMENT: every filter the sheet can express finds its first '
        'match INSIDE the budget — the walk terminates, so phase 342 D10 does '
        'NOT reopen', () async {
      final Map<String, Set<String>> filters = <String, Set<String>>{
        'Виконано': <String>{'COMPLETED'},
        'Скасовано': <String>{'CANCELLED', 'DECLINED'},
        'Підтверджено': <String>{'CONFIRMED'},
      };

      final Map<String, int> measured = <String, int>{};
      for (final MapEntry<String, Set<String>> f in filters.entries) {
        measured[f.key] = await _attemptsUntilFirstMatch(fb, f.value);
      }

      // The numbers, pinned rather than merely asserted to be small — a
      // fixture change that moved them would be a measurement change and
      // should have to say so.
      expect(measured['Виконано'], 0);
      expect(measured['Скасовано'], 0);
      expect(
        measured['Підтверджено'],
        1,
        reason:
            'the sparsest outcome in the fixture (4 %) — one extra round trip '
            'out of a budget of 3',
      );
      for (final MapEntry<String, int> m in measured.entries) {
        expect(
          m.value,
          lessThanOrEqualTo(budget),
          reason:
              '${m.key} exhausted the auto-continue budget — that is phase '
              '342 D10\'s named reopen condition',
        );
      }
    });

    test('THE BOUNDARY, probed rather than reasoned about: the budget is '
        'exhausted at exactly 4 leading matchless raw pages (80 rows). 9 '
        'quiet days still resolve; 10 do not', () async {
      Future<int> attemptsWithGap(int gapDays) async {
        final FakeBackend probe = FakeBackend();
        probe.salonArchiveBookings = FakeBackend.salonArchiveRosterScaleFixture(
          probe,
          anchor: anchor,
          leadingMatchlessDays: gapDays,
        );
        return _attemptsUntilFirstMatch(probe, <String>{
          'CANCELLED',
          'DECLINED',
        });
      }

      // 9 quiet days = 72 leading COMPLETED rows; the first cancel lands at
      // index 79, still inside raw page 3 — the LAST page the budget reaches.
      expect(
        await attemptsWithGap(9),
        budget,
        reason: 'the budget is spent exactly, and the list still fills',
      );
      // 10 quiet days = 80 leading rows; the first cancel moves to index 87,
      // raw page 4 — one page past the budget.
      expect(
        await attemptsWithGap(10),
        budget + 1,
        reason:
            'this is the shape that renders `_ArchiveContinueState` with '
            '«Завантажити ще» — short, with hasMore still true',
      );
    });
  });
}
