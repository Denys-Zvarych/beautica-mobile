// Mobile-qa (Step 2.7 Rule 3b) — E2E regression for TWO live «Мої записи»
// bugs fixed together: Bug B (HIGH, sort) + Bug A (MEDIUM, per-status
// fan-out+merge).
//
// WHY THIS FILE EXISTS
// --------------------
// The widget/unit tier (`my_bookings_notifier_test.dart`,
// `booking_repository_test.dart`) already pins the FIXED code's shape: one
// `getMyBookings` call per tab, carrying the whole status set and the right
// `ascending` argument, with the repository rendering `sort=startsAt,<asc|
// desc>` on the wire. What NEITHER layer proves is the REAL journey wired
// together against a backend that behaves like the actual server: a fake
// that hands back a HAND-PICKED bucket per call (the `_bookingsPageEnvelope`
// single-seeded-booking model every other My-Bookings flow in this suite
// uses) cannot fail when `sort` is silently dropped or the client reverts to
// per-status fan-out — it never sorts or globally paginates anything, so it
// would return the same canned rows either way. See
// `docs/mobile-phases/mobile-backlog.md` for the pattern this file guards
// against recurring.
//
// [FakeBackend.seedManyBookingsDataset] (`integration_test/support/
// fake_backend.dart`) opts THIS flow into a REAL (statuses, sort, page)
// slice over a whole in-memory table — filtering, sorting, and paginating
// the FULL dataset on every `GET /bookings/me` call, the same shape of work
// the real backend does server-side (backend Phase 26.1 status union + Phase
// 26.3 sort). Every other flow in this suite is UNAFFECTED — the dataset is
// opt-in per [FakeBackend] instance and this file's `fb` is never shared.
//
//   Bug B — the repository used to send NO `sort` param. The real
//     `GET /bookings/me` defaults to `startsAt,DESC` with no `sort`, so a
//     client with >20 upcoming CONFIRMED bookings got the 20 FARTHEST-future
//     rows on page 0 — their very next appointment was invisible. This flow
//     seeds 25 upcoming CONFIRMED bookings (in SCRAMBLED insertion order —
//     never already ascending or descending) and asserts page 0 is the 20
//     SOONEST, in order, with the wire `sort=startsAt,asc` pinned directly.
//
//   Bug A — Минулі/Скасовані used to fan out ONE `getMyBookings` call PER
//     status, merging two independently-paginated streams client-side —
//     correct only as a prefix. This flow seeds 45 past bookings split
//     23 COMPLETED / 22 NOT_COMPLETED (both >20, interleaved 1:1 across the
//     WHOLE sorted range so no accidental single-status ordering could pass),
//     and pages Минулі to exhaustion (3 loads), asserting: exactly ONE HTTP
//     call per page (not 2), the full 45-item union with no drop, and a
//     strictly non-increasing `startAt` across the WHOLE concatenated list —
//     the direct proof nothing reshuffled on load-more.
//
// KEY POLICY (AppHarness): all TAPS are key-based; Ukrainian text is not
// asserted here (this flow is about ordering/pagination, not copy).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/application/my_bookings_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'CLIENT with >20 upcoming bookings sees the SOONEST first (Bug B), and '
    'Минулі pages a >40-item two-status dataset to exhaustion with no drop '
    'or reshuffle (Bug A)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;

      // ── Seed a REAL, globally-ordered dataset — NOT hand-picked buckets ──

      // Майбутні: 25 CONFIRMED bookings, one per day-offset 1..25 from
      // kFixedNow, inserted in SCRAMBLED order — neither already ascending
      // nor descending — so a passing "soonest 20 first" assertion below can
      // only be explained by the fake actually sorting, not by insertion
      // order happening to agree.
      const List<int> upcomingOffsets = <int>[
        13, 1, 22, 7, 18, 3, 25, 10, 5, 20, //
        2, 16, 9, 24, 4, 19, 11, 6, 23, 8, //
        15, 21, 12, 17, 14,
      ];
      final List<Map<String, dynamic>> dataset = <Map<String, dynamic>>[
        for (final int offset in upcomingOffsets)
          fb.datasetBookingRow(
            id: 'upcoming-$offset',
            status: 'CONFIRMED',
            startsAt: kFixedNow.add(Duration(days: offset)),
          ),
      ];

      // Минулі: day-offsets 1..45 in the past — ODD → COMPLETED (23 rows),
      // EVEN → NOT_COMPLETED (22 rows). Both comfortably >20, and
      // interleaved 1:1 through the ENTIRE sorted range (never clustered by
      // status), so a client-side per-status fan-out+merge could not
      // accidentally reproduce the correct global order even by luck.
      // Inserted in a SEPARATE scramble from the upcoming set.
      const List<int> pastOffsets = <int>[
        31, 4, 17, 40, 9, 22, 45, 2, 28, 13, //
        36, 7, 19, 44, 1, 25, 38, 11, 30, 5, //
        16, 41, 8, 23, 34, 3, 27, 42, 14, 20, //
        6, 33, 10, 29, 39, 18, 43, 15, 26, 35, //
        12, 21, 37, 24, 32,
      ];
      dataset.addAll(<Map<String, dynamic>>[
        for (final int offset in pastOffsets)
          fb.datasetBookingRow(
            id: 'past-$offset',
            status: offset.isOdd ? 'COMPLETED' : 'NOT_COMPLETED',
            startsAt: kFixedNow.subtract(Duration(days: offset)),
          ),
      ]);

      fb.seedManyBookingsDataset(dataset);

      final GoRouter router = await AppHarness.boot(tester, fb);

      // Cold start → /login.
      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
      await AppHarness.loginAs(tester, fb, UserRole.client);

      // Open the Записи branch (bottom-nav tile 3).
      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientBookings);
      expect(find.byType(MyBookingsScreen), findsOneWidget);

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MyBookingsScreen)),
      );
      MyBookingsState upcomingState() =>
          container.read(myBookingsProvider(BookingTab.upcoming)).value!;
      MyBookingsState pastState() =>
          container.read(myBookingsProvider(BookingTab.past)).value!;

      // ── Bug B — Майбутні page 0 is the 20 SOONEST bookings, in order ─────
      final MyBookingsState upcomingPage0 = upcomingState();
      expect(
        upcomingPage0.items.map((b) => b.id).toList(),
        <String>[for (int i = 1; i <= 20; i++) 'upcoming-$i'],
        reason:
            'ascending by startAt — day-offset 1 (soonest) first, offset 20 '
            'last. Pre-fix (no `sort` param → server default DESC) this page '
            'would instead be offsets 25..6 — the farthest-future rows — '
            'hiding the client\'s very next appointment.',
      );
      expect(upcomingPage0.hasMore, isTrue, reason: '25 seeded > 20 page size');
      expect(
        fb.lastMyBookingsQuery?['sort'],
        'startsAt,asc',
        reason:
            'pins the exact wire param the repository must send for '
            'Майбутні — a dropped `sort` send leaves this absent and the '
            'fake would fall back to its desc default (mirroring the real '
            'backend), which the assertion above would then fail on',
      );

      // The soonest booking is genuinely ON SCREEN — the literal user-facing
      // symptom of Bug B — not just correct in provider state.
      expect(find.byKey(const ValueKey<String>('upcoming-1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('upcoming-25')), findsNothing);

      // ── Bug A — Минулі pages the full 45-item, 2-status dataset ──────────
      await tester.tap(find.byKey(const ValueKey<BookingTab>(BookingTab.past)));
      await AppHarness.settle(tester);

      final int callsBeforePast = fb.getMyBookingsCalls;

      // Page 0.
      expect(
        pastState().items.map((b) => b.id).toList(),
        <String>[for (int i = 1; i <= 20; i++) 'past-$i'],
        reason: 'descending by startAt — day-offset 1 (yesterday) first',
      );
      expect(
        fb.getMyBookingsCalls - callsBeforePast,
        1,
        reason:
            'ONE HTTP request for the whole {COMPLETED, NOT_COMPLETED} set. '
            'A reverted per-status fan-out would fire 2 calls for this '
            'single page fetch.',
      );
      expect(fb.lastMyBookingsQuery?['sort'], 'startsAt,desc');

      // Page 1 — drag to the list foot to cross the load-more threshold.
      await tester.drag(
        find.byKey(const ValueKey<String>('my-bookings-list-past')),
        const Offset(0, -4000),
      );
      await AppHarness.settle(tester);
      expect(
        pastState().items.map((b) => b.id).toList(),
        <String>[for (int i = 1; i <= 40; i++) 'past-$i'],
        reason: 'page 1 appended in order — page 0 untouched/unreshuffled',
      );
      expect(fb.getMyBookingsCalls - callsBeforePast, 2);

      // Page 2 — the final 5, exhausting the stream.
      await tester.drag(
        find.byKey(const ValueKey<String>('my-bookings-list-past')),
        const Offset(0, -4000),
      );
      await AppHarness.settle(tester);
      final MyBookingsState pastFinal = pastState();
      expect(
        pastFinal.items.map((b) => b.id).toSet(),
        <String>{for (int i = 1; i <= 45; i++) 'past-$i'},
        reason: 'the FULL 45-item dataset — no item dropped across 3 pages',
      );
      expect(pastFinal.items, hasLength(45), reason: 'no duplicate rows');
      expect(pastFinal.hasMore, isFalse);
      expect(fb.getMyBookingsCalls - callsBeforePast, 3);

      // Strictly non-increasing startAt across the WHOLE concatenated
      // 45-item list — the direct proof load-more never reshuffled an
      // already-rendered row. This is exactly the defect a reverted
      // per-status fan-out+merge reintroduces once either status spans more
      // than one page (mobile-debugger finding A).
      for (int i = 1; i < pastFinal.items.length; i++) {
        expect(
          pastFinal.items[i].startAt.isAfter(pastFinal.items[i - 1].startAt),
          isFalse,
          reason:
              'item $i (${pastFinal.items[i].id}) must not be more recent '
              'than item ${i - 1} (${pastFinal.items[i - 1].id})',
        );
      }
    },
  );
}
