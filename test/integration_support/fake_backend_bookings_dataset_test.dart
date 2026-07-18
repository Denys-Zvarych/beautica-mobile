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
  });
}
