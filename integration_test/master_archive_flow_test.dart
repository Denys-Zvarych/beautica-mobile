// Phase 231 — E2E: the master «Архів» page (`/master/bookings/archive`).
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// The widget/unit tier proves the mechanism in isolation:
// `master_archive_notifier_test.dart` (request shaping — `partition` ALWAYS
// sent PLUS the legacy `status` rollout valve, client-side predicate
// resolution, pagination) and `master_archive_screen_test.dart` (all 4 async
// states, the auto-continue branch, the «Виконано» close action) — both
// against a MOCKED `BookingRepository` that returns whatever page a `when()`
// stub was told to return, regardless of what `partition`/`status` actually
// reached it.
//
// A mock cannot prove the one thing this whole page exists for: that an
// elapsed CONFIRMED booking a partition-aware BACKEND classifies as PAST
// genuinely reaches the master's Архів, and that a filter-empty raw page
// with `hasMore: true` genuinely continues past it to a later match — not
// merely that the SCREEN renders whatever a stub was told to hand it. This
// file closes that gap the same way
// `client_my_bookings_partition_flow_test.dart` did for the client side:
// against `FakeBackend`'s own implementation of the backend Phase 28.1/28.2
// partition predicate (`FakeBackend._partitionOf` — CONFIRMED classifies as
// PAST only once `endsAt` has elapsed against `serverNow`).
//
// Four scenarios:
//   1. PRIMARY JOURNEY — master logs in, opens «Мої записи», taps the header
//      archive button, sees past bookings INCLUDING an elapsed-unclosed
//      (`awaitingClosure`) one, filters to «Підтверджено», closes it via
//      «Виконано» — the write lands on the real HTTP boundary and the row
//      leaves the still-active filter on the very next re-fetch (a sibling
//      `awaitingClosure` row stays, proving this is a genuine per-row
//      reclassification, not the whole list going empty).
//   2. AUTO-CONTINUE — mobile-perf HIGH-1/2's fix, pinned end-to-end: a raw
//      first page (20 rows) with ZERO rows matching the active
//      «Підтверджено» filter, `hasMore: true`, and the one matching row
//      sitting on raw page 2. The screen must not settle on the terminal
//      empty state — it auto-continues and surfaces the later-page match.
//   3. TERMINAL EMPTY — a raw page with zero matches AND `hasMore: false`
//      renders `_ArchiveEmptyState`. Without this as its own case, the
//      auto-continue fix could regress into "never shows an empty state at
//      all" and nothing above would catch it (both other scenarios always
//      end on a non-empty list).
//   4. DATE-GROUP HEADERS (Phase 231 amendment) — the archive is a flat list
//      spanning arbitrary past days, so rows are grouped under Kyiv-day
//      headers (`archive_day_groups.dart`). `archive_day_groups_test.dart`
//      (pure function) and `master_archive_screen_test.dart` (mocked
//      repository) already pin the grouping mechanism in isolation; this
//      scenario is the mobile-qa-mandated end-to-end check that the REAL
//      screen, fed by the REAL fake-backed HTTP boundary, renders the
//      correct headers for real server rows — not merely that it renders
//      whatever a mock was told to hand it.
//
// KEY POLICY (AppHarness): all TAPS are key-based; Ukrainian text appears
// only via `l10n.<key>` content assertions, never a raw literal.
//
// This runs headless — `flutter test integration_test/master_archive_flow_
// test.dart -d flutter-tester` needs no emulator. Per the harness
// convention, run this file ALONE — batching two integration files in one
// `flutter test` invocation kills the second with a bogus "log reader
// failed".

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/master_archive_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  AppLocalizations l10nOf(WidgetTester tester, Type screen) =>
      AppLocalizations.of(tester.element(find.byType(screen)));

  // A far-past instant, deterministic regardless of the runner's wall clock
  // or `TZ` — mirrors `client_my_bookings_partition_flow_test.dart`'s
  // identical reasoning: `FakeBackend._partitionOf` compares `endsAt`
  // against `serverNow` (which defaults to the harness's injected
  // `kFixedNow`, 2026-06-14), so only a genuinely far-past instant is safe
  // on the "elapsed" side regardless of when this suite actually runs.
  DateTime elapsedStart(int daysBeforeFixedNow) =>
      kFixedNow.subtract(Duration(days: daysBeforeFixedNow, hours: 2));

  /// Drives: cold start → login as the fixture INDEPENDENT_MASTER → «Мої
  /// записи» → tap the header archive button → lands on
  /// [MasterArchiveScreen]. Shared by every scenario below.
  Future<GoRouter> openArchive(WidgetTester tester, FakeBackend fb) async {
    final GoRouter router = await AppHarness.boot(tester, fb);
    expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

    await tester.tap(find.byKey(const Key('master-nav-tile-1')));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.masterBookings);
    expect(find.byType(MasterBookingsScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('master-bookings-open-archive')));
    await AppHarness.settle(tester);
    AppHarness.expectNestedPushLocation(
      router,
      RouteNames.masterBookingsArchive,
    );
    expect(find.byType(MasterArchiveScreen), findsOneWidget);
    return router;
  }

  /// Applies the «Підтверджено» row of the reused `BookingsFilterSheet` —
  /// which, within the archive's fixed `partition: HISTORY` scope, IS the
  /// «Потребують закриття» filter with no bespoke UI (see
  /// `master_archive_notifier.dart`'s file header). Deliberately NOT
  /// `AppHarness.settle` after the apply tap — the filtered request's own
  /// `hasMore` can stay `true` across the auto-continue branch, whose
  /// spinner wraps an INDETERMINATE `CircularProgressIndicator` that never
  /// stops rescheduling frames on its own (mirrors
  /// `master_archive_screen_test.dart`'s identical `pumpAndSettle` ban for
  /// this exact tap sequence — see that file's comment). Callers that know
  /// their own scenario resolves onto a page with `hasMore: false` settle
  /// themselves afterward.
  Future<void> applyConfirmedFilter(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('master-bookings-filter-button')));
    await AppHarness.settle(tester);
    await tester.tap(
      find.byKey(const Key('master-bookings-filter-status-confirmed')),
    );
    await AppHarness.settle(tester);
    await tester.tap(find.byKey(const Key('master-bookings-filter-apply')));
    await tester.pump();
  }

  // ==========================================================================
  // 1. PRIMARY JOURNEY
  // ==========================================================================
  testWidgets(
    'MASTER «Архів»: past bookings include an elapsed-unclosed CONFIRMED '
    'row; filtering to «Підтверджено» narrows to it; closing it via '
    '«Виконано» succeeds on the real HTTP boundary and the row leaves the '
    'still-active filter, while a sibling awaitingClosure row stays',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      // `booking-1` reuses the pre-registered literal detail/complete routes
      // (`GET`/`PATCH /api/v1/bookings/booking-1...`) — the established
      // convention this codebase already uses whenever a dataset-seeded row
      // also needs a WRITE endpoint (mirrors
      // `client_my_bookings_partition_flow_test.dart`'s identical choice for
      // its own elapsed row).
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        <String, dynamic>{
          ...fb.datasetBookingRow(
            id: 'booking-1',
            status: 'CONFIRMED',
            startsAt: elapsedStart(2),
            duration: const Duration(minutes: 90),
          ),
          // Server-computed (Phase 29.1/29.2) — `BookingMapper` reads this
          // straight off the wire (`dto.awaitingClosure ?? false`), so a
          // dataset row that omits it never trips the card's «Виконано»
          // slot however elapsed/CONFIRMED it is. See
          // `Booking.awaitingClosure`'s own doc.
          'awaitingClosure': true,
        },
        <String, dynamic>{
          ...fb.datasetBookingRow(
            id: 'booking-9',
            status: 'CONFIRMED',
            startsAt: elapsedStart(1),
            duration: const Duration(minutes: 60),
          ),
          'awaitingClosure': true,
        },
        fb.datasetBookingRow(
          id: 'past-completed-1',
          status: 'COMPLETED',
          startsAt: elapsedStart(3),
        ),
      ]);

      final GoRouter router = await openArchive(tester, fb);

      // ── Unfiltered landing: every HISTORY row, including the
      //    elapsed-unclosed one. Anti-vacuity for the filter step below — if
      //    this card were never rendered unfiltered, "absent after
      //    completing" would prove nothing. ─────────────────────────────
      //
      // DEFENSIVE HARDENING, NOT A BUG FIX (mobile-debugger INFO, 2026-08-17).
      // `openArchive` ends on `AppHarness.settle`, and quiescence is not a
      // safe proxy for "the landing fetch landed": the archive's own reloads
      // are SEAMLESS invalidates (`_reloadArchive`, master_archive_screen.dart
      // — `AsyncValue.when` skips the loading branch on refresh and RETAINS
      // the previous value), so a reload paints no spinner and schedules no
      // frame while its GET is still in flight. `settle` returns on "no
      // scheduled frame" and a bare `settle` there can read pre-fetch state.
      // Today the landing is a COLD load whose skeleton keeps frames coming,
      // so `settle` happens to be safe — that safety is emergent, one
      // seamless-reload change away from silently going stale. Wait on the
      // specific row the assertions below target instead. Load-bearing: the
      // row is genuinely absent (skeleton) before the fetch resolves.
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('master-booking-card-booking-1')),
      );

      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
        reason:
            'the elapsed-unclosed CONFIRMED booking must be served under '
            'the archive\'s fixed partition:HISTORY scope',
      );
      expect(
        find.byKey(const Key('master-booking-card-booking-9')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('master-booking-card-past-completed-1')),
        findsOneWidget,
      );

      // ── Filter to «Підтверджено» — narrows to the two CONFIRMED/
      //    awaitingClosure rows, client-side, on top of the fixed HISTORY
      //    fetch. ────────────────────────────────────────────────────────
      await applyConfirmedFilter(tester);
      // `settle` here only drains the filter sheet's pop animation — it is NOT
      // the gate for "the filtered fetch landed". See the wait below.
      await AppHarness.settle(tester);

      // DEFENSIVE HARDENING, NOT A BUG FIX (mobile-debugger LOW, 2026-08-17).
      // Same reasoning as the landing wait above: quiescence is not a safe
      // proxy for "the reload landed" when a seamless invalidate paints no
      // spinner and therefore schedules no frame while its GET is in flight.
      // This apply happens to be safe today only because it swaps the notifier
      // FAMILY KEY, so the new provider starts at a valueless `AsyncLoading`
      // whose skeleton keeps frames scheduled — an emergent property of a
      // different branch, one `skipLoadingOnRefresh`-style change away from
      // silently reading the pre-filter list.
      //
      // The condition is deliberately COMPOSITE, and neither half alone would
      // be load-bearing:
      //   * `booking-1` present is satisfied by the STALE pre-filter list (it
      //     is on screen both before and after the filter), so waiting on it
      //     alone would be inert;
      //   * `past-completed-1` absent is satisfied by the intervening
      //     `master-archive-skeleton` (the loading branch renders no cards at
      //     all), so waiting on it alone would return mid-load and the
      //     assertions below would read an empty list.
      // Together they describe exactly one state: the FILTERED page rendered.
      await AppHarness.pumpUntilCondition(
        tester,
        () =>
            find
                .byKey(const Key('master-booking-card-booking-1'))
                .evaluate()
                .isNotEmpty &&
            find
                .byKey(const Key('master-booking-card-past-completed-1'))
                .evaluate()
                .isEmpty,
        description:
            'the «Підтверджено» page to render: booking-1 present AND '
            'past-completed-1 filtered out (neither half alone distinguishes '
            'the filtered list from the stale one or the loading skeleton)',
      );

      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('master-booking-card-booking-9')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('master-booking-card-past-completed-1')),
        findsNothing,
        reason: 'COMPLETED must not survive the «Підтверджено» filter',
      );

      // ── Close `booking-1` via «Виконано». ───────────────────────────────
      expect(fb.completeBookingCalls, 0);
      await tester.tap(
        find.byKey(const Key('master-booking-card-complete-booking-1')),
      );
      await AppHarness.settle(tester);
      expect(
        find.byKey(const Key('complete-booking-dialog')),
        findsOneWidget,
        reason:
            'the SAME CompleteBookingDialog the booking-detail screen '
            'uses — no bespoke dialog for this phase',
      );

      await tester.tap(find.byKey(const Key('complete-booking-confirm')));
      await AppHarness.settle(tester);

      // Same settle-after-provider-close shape as the booking-detail decline/
      // complete flow (`master_booking_provider_actions_flow_test.dart`):
      // [AppHarness.settle] can return in the lull between the PATCH
      // resolving and the follow-up re-fetch landing, reading a stale
      // pre-write card. Wait for the closed row to genuinely leave this
      // still-active «Підтверджено» filter before asserting below.
      await AppHarness.pumpUntilGone(
        tester,
        find.byKey(const Key('master-booking-card-booking-1')),
      );

      expect(
        fb.completeBookingCalls,
        1,
        reason:
            'the write reached the real PATCH /bookings/{id}/complete '
            'HTTP boundary',
      );
      expect(
        find.byKey(const Key('complete-booking-dialog')),
        findsNothing,
        reason: 'the dialog closed on confirm',
      );

      // ── The closed row leaves the STILL-ACTIVE «Підтверджено» filter on
      //    the post-close re-fetch; the sibling CONFIRMED row survives —
      //    proving this is a genuine per-row reclassification (COMPLETED no
      //    longer matches), not the whole list going empty or the filter
      //    silently resetting. ─────────────────────────────────────────────
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsNothing,
        reason:
            'booking-1 is now COMPLETED — it must leave the «Підтверджено» '
            'filter it was just closed from',
      );
      expect(
        find.byKey(const Key('master-booking-card-booking-9')),
        findsOneWidget,
        reason:
            'booking-9 was never touched — it must still be CONFIRMED and '
            'still visible under the SAME active filter',
      );

      // Sanity: still on the archive route, not bounced anywhere.
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.masterBookingsArchive,
      );
    },
  );

  // ==========================================================================
  // 2. AUTO-CONTINUE — mobile-perf HIGH-1/2, pinned end-to-end
  // ==========================================================================
  testWidgets('a first raw page with ZERO rows matching «Підтверджено» plus '
      'hasMore:true is NOT the terminal empty state — the archive '
      'auto-continues and surfaces the match sitting on raw page 2', (
    tester,
  ) async {
    final fb = FakeBackend()..currentRole = UserRole.independentMaster;

    // Page 0 (20 rows, server page size): every row COMPLETED — PAST by
    // definition regardless of elapsed time, and excluded outright by the
    // «Підтверджено» predicate. Page 1 (1 row): the CONFIRMED/
    // awaitingClosure match. Sort is `startsAt,desc` (newest-first), so the
    // filler rows get RECENT dates and the match gets a far-older one to
    // guarantee it lands on the second raw page, not scrambled into the
    // first.
    //
    // `elapsedStart(40)` — NOT an absolute `DateTime.utc(2020, …)` literal.
    // The literal that used to sit here hung this scenario UNBOUNDEDLY (see
    // `scripts/forbid_stale_future_date_fixture.sh`'s far-past rule for the
    // full write-up): the day-scoped `bookingsDayProvider` fetch that
    // `MasterBookingsScreen` fires on the way to the archive was handed the
    // 2020 row by a fake that ignored `from`/`to`, and the single-day
    // timeline then tried to build ~56 500 hour rows — a synchronous
    // allocating loop that starves the Dart event loop, so no `Timer`-based
    // deadline in the whole harness can ever fire.
    //
    // The ONLY constraint the scenario needs is that the match sort BELOW
    // every filler under `startsAt,desc`. The oldest filler is
    // `elapsedStart(3) − 19d` ≡ `elapsedStart(22)`, so `elapsedStart(40)` is
    // 18 days clear of it — comfortably page 2, and still `kFixedNow`-
    // anchored like every other instant in this file.
    final List<Map<String, dynamic>> dataset = <Map<String, dynamic>>[
      for (int i = 0; i < 20; i++)
        fb.datasetBookingRow(
          id: 'filler-$i',
          status: 'COMPLETED',
          startsAt: elapsedStart(3).subtract(Duration(days: i)),
        ),
      <String, dynamic>{
        ...fb.datasetBookingRow(
          id: 'late-match',
          status: 'CONFIRMED',
          startsAt: elapsedStart(40),
          duration: const Duration(minutes: 60),
        ),
        'awaitingClosure': true,
      },
    ];
    fb.seedManyBookingsDataset(dataset);

    await openArchive(tester, fb);

    // Baseline taken AFTER the landing fetches (the master-bookings day fetch
    // + the archive's own unfiltered fetch) so the delta asserted below is
    // attributable to the filter apply alone — see that assertion.
    final int callsBeforeFilter = fb.getMyBookingsCalls;

    await applyConfirmedFilter(tester);

    // Deliberately `pumpUntilFound`, NOT `settle` — see
    // [applyConfirmedFilter]'s doc. The auto-continue branch's spinner is
    // indeterminate and would hang a plain `pumpAndSettle` for however
    // long the (bounded, here single-attempt) continuation takes.
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('master-booking-card-late-match')),
    );

    // `FakeBackend.lastMyBookingsQuery` is a LAST-WRITE-WINS global: every
    // `GET /bookings/me` from ANY provider overwrites it. Captured HERE, at the
    // moment the continuation's match has just rendered, rather than read off
    // the fake after the assertions below — none of which pump today, but any
    // future `await` inserted between would silently retarget the `page`
    // assertion at some later, unrelated fetch. Capturing pins it to the
    // moment of interest without changing what is asserted. (A fully
    // hazard-free version needs `FakeBackend` to record a LIST of queries;
    // out of scope for an INFO — flagged here instead.)
    final Map<String, dynamic>? continuationQuery = fb.lastMyBookingsQuery;

    expect(
      find.byKey(const Key('master-booking-card-late-match')),
      findsOneWidget,
      reason:
          'the match on the SECOND raw page must render — the '
          'headline mobile-perf HIGH-1 fix, proven against a REAL '
          'partition-classifying backend (a mocked repository cannot '
          'distinguish this from a stub that was simply told to return '
          'this row)',
    );
    expect(
      find.byKey(const Key('master-archive-empty')),
      findsNothing,
      reason:
          'the terminal empty state must never have shown while a raw '
          'page with a potential match was still unfetched',
    );
    expect(
      find.byKey(const Key('master-archive-auto-continue')),
      findsNothing,
      reason:
          'the auto-continue branch must have resolved by now — the '
          'match is showing under the real list, not the interim branch',
    );
    expect(
      fb.getMyBookingsCalls,
      greaterThanOrEqualTo(3),
      reason:
          'at least: the unfiltered landing fetch + the filtered '
          'page-0 fetch + the auto-continued page-1 fetch — proving the '
          'continuation genuinely round-tripped the HTTP boundary a '
          'second time rather than the UI silently keeping page 0\'s '
          'stale (empty) result',
    );

    // ── ANTI-VACUITY for the count above ───────────────────────────────────
    // `getMyBookingsCalls >= 3` is a WHOLE-FLOW total, so it can be satisfied
    // by landing fetches that have nothing to do with the continuation. These
    // two pin the count to the right reason:
    //   * the filter apply alone cost at least TWO round trips (raw page 0,
    //     then the auto-continued raw page 1);
    //   * the LAST of them genuinely asked the server for `page=1` — the
    //     second raw page — rather than re-requesting page 0 or serving the
    //     match out of an already-held buffer.
    expect(
      fb.getMyBookingsCalls - callsBeforeFilter,
      greaterThanOrEqualTo(2),
      reason:
          'the «Підтверджено» apply must have cost a page-0 fetch AND an '
          'auto-continued page-1 fetch — a single fetch here would mean the '
          'match came from somewhere other than the continuation',
    );
    expect(
      '${continuationQuery?['page']}',
      '1',
      reason:
          'the continuation must have requested the SECOND raw page; '
          'stringified because the transport hands `page` back as either an '
          'int or its decimal string depending on the DioAdapter path',
    );
  });

  // ==========================================================================
  // 3. TERMINAL EMPTY STATE
  // ==========================================================================
  testWidgets(
    'a raw page with zero «Підтверджено» matches AND hasMore:false renders '
    'the terminal empty state — the auto-continue fix must not regress '
    'into never showing an empty state at all',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      // A small, single-page dataset — every row COMPLETED, so
      // «Підтверджено» matches nothing, and `totalPages: 1` means `hasMore`
      // is `false` from the very first (and only) fetch. No auto-continue
      // branch is ever reachable here.
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'done-1',
          status: 'COMPLETED',
          startsAt: elapsedStart(1),
        ),
        fb.datasetBookingRow(
          id: 'done-2',
          status: 'COMPLETED',
          startsAt: elapsedStart(2),
        ),
      ]);

      await openArchive(tester, fb);
      await applyConfirmedFilter(tester);
      await AppHarness.settle(tester);

      expect(
        find.byKey(const Key('master-archive-empty')),
        findsOneWidget,
        reason:
            'hasMore is false from the first fetch — this must resolve '
            'straight to the terminal empty state, not hang on the '
            'auto-continue branch',
      );
      expect(
        find.byKey(const Key('master-archive-auto-continue')),
        findsNothing,
      );
      expect(find.byKey(const Key('master-booking-card-done-1')), findsNothing);
      expect(find.byKey(const Key('master-booking-card-done-2')), findsNothing);

      final AppLocalizations l10n = l10nOf(tester, MasterArchiveScreen);
      expect(
        find.text(l10n.masterBookingsNoResultsTitle),
        findsOneWidget,
        reason:
            'the filter-empty (not true-empty) copy — bookings exist, '
            'none match the active filter',
      );
      expect(
        find.byKey(const Key('master-archive-clear-filters')),
        findsOneWidget,
      );

      // Clearing the filter returns to the unfiltered, non-empty list.
      await tester.tap(find.byKey(const Key('master-archive-clear-filters')));
      await AppHarness.settle(tester);
      expect(find.byKey(const Key('master-archive-empty')), findsNothing);
      expect(
        find.byKey(const Key('master-booking-card-done-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('master-booking-card-done-2')),
        findsOneWidget,
      );
    },
  );

  // ==========================================================================
  // 4. DATE-GROUP HEADERS — Phase 231 amendment, pinned end-to-end
  // ==========================================================================
  testWidgets(
    'archive rows render grouped under Kyiv date headers end-to-end: two '
    'bookings on the SAME Kyiv day collapse under exactly ONE header, a '
    'booking on a genuinely DIFFERENT Kyiv day gets its own, and the newer '
    'day\'s header renders ABOVE the older one — against the REAL '
    'fake-backed screen and a real HTTP round trip, not a mocked repository',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      // hdr-a/hdr-b share a Kyiv calendar day (different hours, same day);
      // hdr-c sits 3 days earlier — a genuinely different Kyiv day. All
      // COMPLETED so partition classification (PAST) never depends on
      // elapsed-time precision. Anchored to `kFixedNow` throughout — never
      // `DateTime.now()`.
      final DateTime sameDayLater = elapsedStart(2);
      final DateTime sameDayEarlier = elapsedStart(
        2,
      ).subtract(const Duration(hours: 4));
      final DateTime otherDay = elapsedStart(5);

      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'hdr-a',
          status: 'COMPLETED',
          startsAt: sameDayLater,
        ),
        fb.datasetBookingRow(
          id: 'hdr-b',
          status: 'COMPLETED',
          startsAt: sameDayEarlier,
        ),
        fb.datasetBookingRow(
          id: 'hdr-c',
          status: 'COMPLETED',
          startsAt: otherDay,
        ),
      ]);

      await openArchive(tester, fb);

      Key headerKeyFor(DateTime instant) => ValueKey<String>(
        'master-archive-day-header-${kyivDayOf(instant).toIso8601String()}',
      );

      // All three cards genuinely arrived over the real HTTP boundary.
      expect(
        find.byKey(const Key('master-booking-card-hdr-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('master-booking-card-hdr-b')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('master-booking-card-hdr-c')),
        findsOneWidget,
      );

      // hdr-a/hdr-b share a Kyiv day -> the SAME derived header key — two
      // distinct header widgets could never both satisfy a single-key
      // findsOneWidget lookup, so this alone proves the merge.
      expect(find.byKey(headerKeyFor(sameDayLater)), findsOneWidget);
      expect(headerKeyFor(sameDayLater), headerKeyFor(sameDayEarlier));

      // hdr-c sits on a genuinely different Kyiv day -> its own, DIFFERENT
      // header key.
      expect(find.byKey(headerKeyFor(otherDay)), findsOneWidget);
      expect(headerKeyFor(sameDayLater), isNot(headerKeyFor(otherDay)));

      // Exactly TWO day-header widgets total for three bookings across two
      // Kyiv days — not zero (feature reverted / grouping dropped) and not
      // three (a per-row-header regression that would still individually
      // satisfy the specific-key checks above).
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'master-archive-day-header-',
              ),
        ),
        findsNWidgets(2),
        reason:
            'three bookings across two Kyiv days must yield exactly two '
            'header widgets — never one-per-row, never zero',
      );

      // Ordering: newest-first, matching the underlying list — the header
      // for the more recent Kyiv day (hdr-a/hdr-b) must paint ABOVE the
      // header for the older one (hdr-c).
      final double newerHeaderY = tester
          .getTopLeft(find.byKey(headerKeyFor(sameDayLater)))
          .dy;
      final double olderHeaderY = tester
          .getTopLeft(find.byKey(headerKeyFor(otherDay)))
          .dy;
      expect(
        newerHeaderY,
        lessThan(olderHeaderY),
        reason:
            'the newer Kyiv day\'s header must render ABOVE the older '
            'one — newest-first, matching the server-ordered list',
      );
    },
  );
}
