// 2026-08-16 follow-up to Phase 231 — E2E: the master «Архів» page's
// «Відгук» entry point (Track 7.x Wave B's leave-client-feedback screen,
// reached from an archive COMPLETED row) AND the cross-screen cache
// invalidation the archive/detail pair must share (Step 2.7 Rule 3b).
//
// WHY THIS FILE EXISTS
// --------------------
// `master_archive_flow_test.dart` proves the archive's own list mechanics
// (elapsed-CONFIRMED inclusion, filter narrowing, «Виконано» closing IN
// PLACE, auto-continue, terminal empty). None of those three scenarios ever
// leave the archive screen. This file covers the three journeys that DO:
//
//   1. INVALIDATION REGRESSION (the reported bug) — a master opens the
//      archive, taps a row (NOT the archive's own «Виконано» button) to
//      reach `BookingDetailScreen`, declines from THERE, and returns. The
//      archive must reflect the change on resume, not keep serving the
//      stale pre-decline row. `invalidateBookingViewsAfterProviderClose`
//      (`booking_calendar_invalidation.dart`) is the shared fan-out point
//      both `BookingDetailScreen` and `MasterArchiveScreen` now route
//      through; before the 2026-08-16 fix, `BookingDetailScreen` hand-rolled
//      its own invalidation and never touched `masterArchiveProvider` at
//      all. This is the regression guard for exactly that gap, driven
//      through the REAL navigation path (archive → pushed detail → back),
//      not a synthetic `ref.invalidate` poke a unit test could fake.
//
//      ⚠ Riverpod 3 PAUSES a covered (offstage) consumer — the archive
//      screen sits underneath the pushed detail screen on the SAME flat
//      `/master/*` navigator (this surface is not a `StatefulShellRoute`;
//      see `route_names.dart`'s `masterBookings` doc), so
//      `invalidateBookingViewsAfterProviderClose`'s
//      `ref.invalidate(masterArchiveProvider)` call — fired while the
//      archive's own listener is paused — DISPOSES the autoDispose provider
//      rather than eagerly refetching it. The refetch only happens once the
//      archive resumes (the pop lands and its `ref.watch` reattaches), so
//      every assertion below runs AFTER popping back and settling, never
//      between the decline and the pop.
//
//      2026-08-16 HISTORY cutover update: `masterArchiveProvider` now
//      requests `partition: BookingPartition.history` (`PAST ∪ CANCELLED`),
//      not the old `PAST`-only fetch — DECLINED rows are now genuinely
//      included, not dropped. So the row staying visible in the UNFILTERED
//      list after decline no longer distinguishes "genuinely refetched" from
//      "stale cache" by itself (either way the card would render). The
//      distinguishing signal is now the «Скасовано» filter
//      (`BookingStatusFilterGroup.cancelled`, CANCELLED/DECLINED): a
//      pre-decline CONFIRMED row can never match it, so booking-1 appearing
//      there proves the resumed archive genuinely re-fetched and
//      reclassified the row server-side. A sibling PAST row that was never
//      touched stays visible unfiltered and drops out of the «Скасовано»
//      filter, proving this is a genuine per-row reclassification, not the
//      whole list quietly going empty or a stale cache being replayed.
//
//      `FakeBackend`'s `/bookings/booking-1/decline` route was extended
//      (2026-08-16, this same pass) to ALSO mutate the seeded dataset row's
//      `status` to `DECLINED`, mirroring the pre-existing `/complete` route's
//      identical dataset mutation — without it the dataset would keep
//      reporting the pre-decline CONFIRMED row forever, and this test could
//      never tell "the cache never dropped" apart from "the fake never
//      learned about the write" regardless of how correct the invalidation
//      fix is.
//
//   2. THE «ВІДГУК» ENTRY POINT — tapping «Відгук» on an archive COMPLETED
//      row lands on `LeaveClientFeedbackScreen` with the real form (not the
//      pre-gate, since `providerCanReviewClient` is seeded `true`); popping
//      returns to the ARCHIVE, not the detail screen (this entry never
//      visited detail — see `route_names.dart`'s `clientReview` doc on why
//      pop returns to whatever the caller actually had on the stack). Also
//      pins `MasterBookingCard.onReview`'s gate — which is the LIST row's own
//      server-computed `providerCanReviewClient` since 2026-08-17, no longer
//      `status == COMPLETED`: a reviewable COMPLETED row offers the button, a
//      PAST-but-not-COMPLETED sibling (`NOT_COMPLETED`, for which the backend
//      computes `false`) does not — the one behavioural claim
//      `master_archive_screen.dart`'s file header makes about this button
//      that no existing E2E asserts.
//      Also proves `_openReview`'s `listenManual` warmup fetches the booking
//      EXACTLY ONCE end-to-end (the archive's own prefetch and the pushed
//      screen's `ref.watch` sharing one subscription) — the real-HTTP-tier
//      counterpart of `master_archive_screen_test.dart`'s mocked-repository
//      "exactly 1 fetch" proof.
//
//   3. THE PRE-GATE — the STALE-LIST race. The archive row is seeded
//      `providerCanReviewClient: true` (so the card offers «Відгук» at all)
//      while `GET /bookings/{id}` answers `false` (this client was already
//      reviewed, from another device or since the page was loaded). Opening
//      the screen must render `_NotReviewable` immediately, from the DETAIL
//      value, with the form NEVER built — not merely disabled. That the two
//      sources disagree is the whole point: it proves the screen reads the
//      real flag off its own round trip rather than trusting the list row it
//      was navigated from. A mocked-repository widget test can prove the
//      branch; only a real `GET /bookings/{id}` proves the source.
//      EXTENDED 2026-08-17: backing out of `_NotReviewable` must ALSO clear
//      the stale row's CTA — every pop site reports the `bool` "no longer
//      reviewable", so a master who never submitted anything still stops
//      seeing a button that can only ever land on the pre-gate again. That
//      half is the reported bug's second face (pull-to-refresh did not clear
//      it either), and nothing at any tier pinned it before.
//
//   4. THE REPORTED BUG, END TO END (2026-08-17) — submit → pop → the CTA is
//      GONE. `MasterArchiveScreen._openReview` awaits `context.push<bool>`,
//      `LeaveClientFeedbackScreen._submit` pops `true`, and the archive calls
//      `MasterArchiveNotifier.markClientReviewed(id)`, rewriting ONLY that
//      row's `providerCanReviewClient`. Three properties no other tier pins:
//
//        * ZERO NETWORK. `fb.getMyBookingsCalls` must be IDENTICAL either
//          side of the round trip — the whole reason the mechanism is a
//          surgical row patch rather than the `ref.invalidate(
//          masterArchiveProvider)` it replaced (mobile-perf MEDIUM,
//          2026-08-17; an invalidate arriving while the archive is COVERED
//          would DISPOSE the autoDispose element and restart pagination from
//          page 0 on resume). `fb.getBookingDetailCalls` must land on exactly
//          +1 too: from `ClientReviewEntry.masterArchive` the success path
//          deliberately does NOT invalidate `bookingDetailProvider`.
//
//        * THE PATCH IS LOCAL, PROVABLY. `POST /client-reviews` flips only
//          `FakeBackend.bookingProviderCanReviewClient` (the DETAIL field,
//          `fake_backend.dart:4893`) and NEVER the dataset row `GET
//          /bookings/me` is sliced from. So the fake still reports this row
//          as reviewable — a refetch would put the CTA straight BACK, and the
//          only way it can be gone is the in-memory rewrite. The fixture
//          cannot accidentally pass this scenario through a server round trip.
//
//        * SIBLING IMMUTABILITY. A second, never-reviewed row seeded
//          `providerCanReviewClient: true` must keep its own CTA — the patch
//          rewrites one row, not the list.
//
//   6. THE SECOND ENTRY PATH (2026-08-17 cycle 2) — the SAME user-reported
//      defect on a DIFFERENT journey, which scenario 4's pop-result mechanism
//      structurally cannot reach:
//
//        archive → tap the ROW → `BookingDetailScreen` → its footer «Залишити
//        відгук про клієнта» → form → submit → back to detail → back to archive
//
//      `MasterArchiveScreen._openDetail` is fire-and-forget, and the review
//      screen pops onto the DETAIL screen, not the archive — so no `bool` ever
//      reaches `_openReview`'s `await`, and chaining one down through
//      `BookingDetailScreen` would still be lost the moment the master leaves
//      via a system/predictive back gesture (which pops `null`). The fix is
//      `clientReviewSignalProvider`: a `keepAlive`, session-scoped, ADD-ONLY set
//      of booking ids the review screen deposits into UNCONDITIONALLY on a
//      successful submit, which `MasterArchiveScreen.build` `ref.watch`es and
//      applies via the same `markClientReviewed` row patch. Because the archive
//      is COVERED (and therefore PAUSED — Riverpod 3) for the whole excursion,
//      delivery lands on RESUME; the scenario therefore asserts only after
//      popping all the way back, via `pumpUntilGone`. The zero-network property
//      is asserted here too: `getMyBookingsCalls` must be IDENTICAL across the
//      entire two-route round trip, exactly as in scenario 4.
//
//   7. THE SESSION BOUNDARY (2026-08-17 cycle 2) — `clientReviewSignalProvider`
//      is `keepAlive`, so it outlives every screen and holds USER-SCOPED booking
//      ids. `build()` watches the authenticated identity
//      (`authProvider.select(… user.id …)`), so a logout must empty it. Driven
//      here through the REAL logout → login round trip against a fake that still
//      reports the row reviewable: the CTA must come BACK on the fresh session.
//      The unit tier (`client_review_signal_provider_test.dart`) pins the
//      provider's own reset with a stubbed auth notifier; only this tier proves
//      the reset actually reaches a rebuilt `MasterArchiveScreen` through the
//      real auth cascade, with a real `keepAlive` element that genuinely
//      survived the logout.
//
//   8. THE «ВІДГУК» ENTRY WHEN THE DETAIL FETCH FAILS (2026-08-17, closing
//      mobile-qa's own cycle-1 INFO) — `LeaveClientFeedbackScreen` renders its
//      entire body out of `bookingDetailProvider(id)`, so a failing
//      `GET /bookings/{id}` must reach `_ErrorState` (a retry affordance), NOT
//      `_NotReviewable`. The distinction is the whole point: "we could not ask"
//      and "the answer was no" look identical to a careless implementation and
//      are opposites to the master. Backing out of the error state therefore
//      pops `false` (`async.value` is null, so nothing was learned) and the
//      archive row KEEPS its «Відгук» CTA — fail-OPEN on an unknown answer,
//      the mirror image of the fail-CLOSED direction the signal set enforces.
//      Needs `FakeBackend.bookingDetailFailStatus`, added in this same pass;
//      see that field's doc for the `DioAdapter` registration-time-status trap
//      and for why `404` (deterministic) rather than a `5xx` (which
//      `beauticaProviderRetry` feeds into a ~38 s backoff curve).
//
// KEY POLICY (AppHarness): all taps are key-based; Ukrainian text appears
// only via `l10n.<key>` (unused directly here — every assertion in this file
// is by key or call count).
//
// Runs headless — `flutter test
// integration_test/master_archive_review_flow_test.dart -d flutter-tester`
// needs no emulator. Run this file ALONE, per the harness convention.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_client_feedback_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_archive_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // A far-past instant, deterministic regardless of the runner's wall clock
  // or `TZ` — identical reasoning to `master_archive_flow_test.dart`'s own
  // `elapsedStart`: `FakeBackend._partitionOf` compares against `serverNow`
  // (defaults to the harness's injected `kFixedNow`), so only a genuinely
  // far-past instant is safe regardless of when this suite actually runs.
  DateTime elapsedStart(int daysBeforeFixedNow) =>
      kFixedNow.subtract(Duration(days: daysBeforeFixedNow, hours: 2));

  /// Drives: cold start → login as the fixture INDEPENDENT_MASTER → «Мої
  /// записи» → tap the header archive button → lands on
  /// [MasterArchiveScreen]. Duplicated from `master_archive_flow_test.dart`'s
  /// private helper of the same shape rather than shared — that file's
  /// version is `private` to it, and a third occurrence would be the point
  /// to promote a shared one (`ARCHITECTURE-mobile.md`'s DRY-on-third-
  /// repetition rule).
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

  // ==========================================================================
  // 1. INVALIDATION REGRESSION — the reported bug
  // ==========================================================================
  testWidgets(
    'archive → tap a row → detail → decline → back to archive: the archive '
    'reflects the decline on RESUME (Riverpod pauses the covered consumer, '
    'so the refetch lands after the pop, never immediately) — a sibling PAST '
    'row proves this is a genuine per-row reclassification, not a stale or '
    'fully-emptied list',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      final DateTime start = elapsedStart(2);
      final DateTime end = start.add(const Duration(minutes: 90));

      // `booking-1` reuses the pre-registered literal detail/decline routes
      // (mirrors `master_archive_flow_test.dart`'s identical choice for its
      // own «Виконано» scenario) — GET/PATCH `/bookings/booking-1` are the
      // ONLY concrete routes `FakeBackend` wires for a single-booking fetch.
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-1',
          status: 'CONFIRMED',
          startsAt: start,
          duration: const Duration(minutes: 90),
        ),
        fb.datasetBookingRow(
          id: 'past-anchor-1',
          status: 'COMPLETED',
          startsAt: elapsedStart(5),
        ),
      ]);
      // The pushed DETAIL screen reads `GET /bookings/booking-1`, which is
      // served from the fake's TOP-LEVEL mutable fields
      // (`_seededBookingJson`), NOT the dataset row above — the two must be
      // seeded to agree so the detail screen shows the SAME booking the
      // archive card represents.
      fb.bookingStatus = 'CONFIRMED';
      fb.bookingStartsAt = start.toIso8601String();
      fb.bookingEndsAt = end.toIso8601String();

      final GoRouter router = await openArchive(tester, fb);

      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
        reason:
            'the elapsed CONFIRMED booking starts in the archive\'s '
            'unfiltered PAST list',
      );
      expect(
        find.byKey(const Key('master-booking-card-past-anchor-1')),
        findsOneWidget,
      );

      // ── Reach the detail screen via a plain row tap — NOT the archive's
      //    own «Виконано» slot, which already has its own regression cover
      //    in `master_archive_flow_test.dart`. ─────────────────────────────
      await tester.tap(find.byKey(const Key('master-booking-card-booking-1')));
      await AppHarness.settle(tester);
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.masterBookingDetail('booking-1'),
      );

      final int callsBeforeDecline = fb.getMyBookingsCalls;

      await tester.tap(find.byKey(const Key('booking-detail-decline')));
      await AppHarness.settle(tester);
      expect(find.byKey(const Key('decline-booking-dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'No-show, could not reach the client.',
      );
      await tester.tap(find.byKey(const Key('decline-booking-confirm')));
      await AppHarness.settle(tester);

      expect(
        fb.declineBookingCalls,
        1,
        reason:
            'the real PATCH /bookings/booking-1/decline must have '
            'reached the fake',
      );
      expect(find.byKey(const Key('decline-booking-dialog')), findsNothing);

      // ── Return to the archive. The pre-pop provider state is deliberately
      //    NOT asserted here — see this test's own doc header on why the
      //    invalidated `masterArchiveProvider` is DISPOSED (paused consumer),
      //    not eagerly refetched, until the pop lands and the screen
      //    resumes. ───────────────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('booking-detail-back')));
      await AppHarness.settle(tester);

      expect(find.byType(MasterArchiveScreen), findsOneWidget);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.masterBookingsArchive,
      );

      expect(
        fb.getMyBookingsCalls,
        greaterThan(callsBeforeDecline),
        reason:
            'popping back onto the archive must trigger a genuine new '
            'GET /bookings/me on resume, not silently keep serving the '
            'pre-decline page',
      );
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
        reason:
            'HISTORY (`partition: BookingPartition.history`, the archive '
            'HISTORY cutover) includes DECLINED rows — booking-1 stays '
            'served, reclassified, rather than dropped from the archive '
            'entirely. This alone does not yet prove a genuine refetch (a '
            'stale cache would also still render this card) — see the '
            '«Скасовано» filter check below for the signal that does.',
      );
      expect(
        find.byKey(const Key('master-booking-card-past-anchor-1')),
        findsOneWidget,
        reason: 'the untouched sibling PAST row must still render',
      );

      // ── Filtering to «Скасовано» is the signal a stale cache cannot fake:
      //    a pre-decline CONFIRMED row could never match it, so booking-1
      //    appearing here proves the resumed archive genuinely re-fetched
      //    and reclassified the row server-side, not merely kept rendering
      //    the pre-decline card. ────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('master-bookings-filter-button')));
      await AppHarness.settle(tester);
      await tester.tap(
        find.byKey(const Key('master-bookings-filter-status-cancelled')),
      );
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('master-bookings-filter-apply')));
      await AppHarness.settle(tester);

      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
        reason:
            'booking-1 is now DECLINED — only a genuinely refetched, '
            'correctly reclassified row can match the «Скасовано» filter',
      );
      expect(
        find.byKey(const Key('master-booking-card-past-anchor-1')),
        findsNothing,
        reason:
            'the untouched sibling is COMPLETED — it must not survive the '
            '«Скасовано» filter, proving this is a genuine per-row '
            'reclassification, not the whole list going empty or a stale '
            'cache being replayed',
      );
    },
  );

  // ==========================================================================
  // 2. THE «ВІДГУК» ENTRY POINT (+ the COMPLETED-only gate)
  // ==========================================================================
  testWidgets(
    'archive «Відгук» on a COMPLETED row lands on the real leave-client-'
    'feedback form in exactly one GET /bookings/{id} round trip; popping '
    'returns to the ARCHIVE; a PAST-but-not-COMPLETED sibling never offers '
    'the button at all',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      final DateTime start = elapsedStart(2);
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-1',
          status: 'COMPLETED',
          startsAt: start,
          // The LIST row's own server-computed flag — the archive card's ONLY
          // «Відгук» gate since 2026-08-17.
          providerCanReviewClient: true,
        ),
        // PAST (NOT_COMPLETED classifies straight into PAST — see
        // `FakeBackend._partitionOf`) but NOT completed — the negative
        // control. The real backend computes `providerCanReviewClient: false`
        // for a NOT_COMPLETED booking (`isReviewEligible` admits only
        // COMPLETED or CONFIRMED-and-elapsed), which is this row's default.
        fb.datasetBookingRow(
          id: 'no-show-1',
          status: 'NOT_COMPLETED',
          startsAt: elapsedStart(4),
        ),
      ]);
      fb.bookingStatus = 'COMPLETED';
      fb.bookingStartsAt = start.toIso8601String();
      fb.bookingEndsAt = start
          .add(const Duration(minutes: 60))
          .toIso8601String();
      // The REAL server-computed value on the single-booking fetch this
      // screen pre-gates on — explicit even though it is already the fake's
      // default, so this test does not silently depend on that default.
      fb.bookingProviderCanReviewClient = true;

      final GoRouter router = await openArchive(tester, fb);

      expect(
        find.byKey(const Key('master-booking-card-review-booking-1')),
        findsOneWidget,
        reason: 'a COMPLETED row must offer «Відгук»',
      );
      expect(
        find.byKey(const Key('master-booking-card-review-no-show-1')),
        findsNothing,
        reason:
            'a PAST-but-not-COMPLETED (NOT_COMPLETED) row must NEVER '
            'offer «Відгук» — `MasterBookingCard.onReview` is gated on the '
            "row's own server-computed providerCanReviewClient, which the "
            'backend leaves false for a NOT_COMPLETED booking; membership in '
            'the archive is not enough',
      );

      final int callsBeforeTap = fb.getBookingDetailCalls;

      await tester.tap(
        find.byKey(const Key('master-booking-card-review-booking-1')),
      );
      await AppHarness.settle(tester);

      expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.clientReview('booking-1'),
      );
      expect(
        find.byKey(const Key('leave-client-feedback-submit')),
        findsOneWidget,
        reason:
            'providerCanReviewClient:true on the real GET must render '
            'the actual form, not the pre-gate',
      );
      expect(
        find.byKey(const Key('leave-client-feedback-unavailable-back')),
        findsNothing,
      );
      expect(
        fb.getBookingDetailCalls,
        callsBeforeTap + 1,
        reason:
            '_openReview\'s listenManual warmup + the destination '
            'screen\'s own ref.watch must share the SAME subscription — '
            'exactly one real GET /bookings/booking-1, not two independent '
            'ones',
      );

      // ── Pop returns to the ARCHIVE — this entry never visited the detail
      //    screen, so there is nothing else on the stack to land on. ───────
      await tester.tap(find.byKey(const Key('leave-client-feedback-back')));
      await AppHarness.settle(tester);

      expect(find.byType(MasterArchiveScreen), findsOneWidget);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.masterBookingsArchive,
      );
    },
  );

  // ==========================================================================
  // 3. THE PRE-GATE
  // ==========================================================================
  testWidgets(
    'opening «Відгук» for a booking whose REAL providerCanReviewClient is '
    'false renders the not-reviewable state immediately — the form is never '
    'built, not merely disabled — and backing out of it still clears that '
    'row\'s stale CTA (and only that row\'s) with ZERO refetch',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      final DateTime start = elapsedStart(3);
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-1',
          status: 'COMPLETED',
          startsAt: start,
          // STALE LIST. Since 2026-08-17 the card only offers «Відгук» when
          // the LIST row says reviewable, so this must be `true` for the tap
          // to exist at all — and seeding it `true` while the detail fetch
          // below says `false` is precisely the race the pre-gate defends
          // against (the review landed from another device, or the master's
          // page has been open a while). The old "list is always false"
          // version of this test could not express that distinction.
          providerCanReviewClient: true,
        ),
        // SIBLING IMMUTABILITY control — never opened, never reviewed, and
        // ALSO seeded reviewable. `markClientReviewed` must rewrite exactly
        // the tapped row; a patch that rebuilt the list with a blanket `false`
        // (or that dropped/refetched pages) would take this CTA with it.
        fb.datasetBookingRow(
          id: 'sibling-1',
          status: 'COMPLETED',
          startsAt: elapsedStart(6),
          providerCanReviewClient: true,
        ),
      ]);
      fb.bookingStatus = 'COMPLETED';
      fb.bookingStartsAt = start.toIso8601String();
      fb.bookingEndsAt = start
          .add(const Duration(minutes: 60))
          .toIso8601String();
      // This client was already reviewed — the REAL, server-computed value on
      // `GET /bookings/{id}`, which is what the pre-gate must read off the
      // wire and prefer over the stale list row above.
      fb.bookingProviderCanReviewClient = false;

      final GoRouter router = await openArchive(tester, fb);

      expect(
        find.byKey(const Key('master-booking-card-review-sibling-1')),
        findsOneWidget,
        reason: 'the never-touched sibling starts out reviewable too',
      );
      final int listCallsBeforeTap = fb.getMyBookingsCalls;

      await tester.tap(
        find.byKey(const Key('master-booking-card-review-booking-1')),
      );
      await AppHarness.settle(tester);

      expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
      expect(
        find.byKey(const Key('leave-client-feedback-unavailable-back')),
        findsOneWidget,
        reason:
            'the pre-gate must render on open, from the real fetched '
            'providerCanReviewClient:false — not only after a failed submit',
      );
      expect(
        find.byKey(const Key('leave-client-feedback-submit')),
        findsNothing,
        reason:
            'the form must never be BUILT when the booking is not '
            'reviewable — this is a pre-gate, not a disabled control',
      );
      expect(
        find.byKey(const Key('leave-client-feedback-comment')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('leave-client-feedback-stars')),
        findsNothing,
      );
      expect(
        fb.createClientReviewCalls,
        0,
        reason:
            'no submit was ever possible, so no POST /client-reviews '
            'can have fired',
      );

      // ── Backing out of `_NotReviewable` pops `true` — "no longer
      //    reviewable" — so the archive clears the STALE row's CTA even though
      //    nothing was submitted. This is the reported bug's second face: the
      //    master saw a button that could only ever land back on this same
      //    dead end, and pull-to-refresh did not clear it either. ───────────
      await tester.tap(
        find.byKey(const Key('leave-client-feedback-unavailable-back')),
      );
      await AppHarness.settle(tester);
      expect(find.byType(MasterArchiveScreen), findsOneWidget);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.masterBookingsArchive,
      );

      await AppHarness.pumpUntilGone(
        tester,
        find.byKey(const Key('master-booking-card-review-booking-1')),
      );
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
        reason:
            'the ROW itself must survive — only its «Відгук» slot is gone. '
            'A patch that dropped the row would also satisfy the CTA-gone '
            'assertion above, so this is what tells the two apart',
      );
      expect(
        find.byKey(const Key('master-booking-card-review-sibling-1')),
        findsOneWidget,
        reason:
            'markClientReviewed rewrites ONE row — the never-opened sibling '
            'keeps its own CTA',
      );
      expect(
        fb.getMyBookingsCalls,
        listCallsBeforeTap,
        reason:
            'the row patch is in-memory: not one extra GET /bookings/me may '
            'fire across the push→pre-gate→pop round trip',
      );
      expect(
        fb.createClientReviewCalls,
        0,
        reason: 'still nothing submitted — the CTA cleared on the pop result',
      );
    },
  );

  // ==========================================================================
  // 4. THE REPORTED BUG, END TO END — submit → pop → CTA gone, ZERO network
  // ==========================================================================
  testWidgets(
    'archive «Відгук» → form → 5★ submit → pop: the reviewed row loses its '
    '«Відгук» CTA while KEEPING the row, a never-reviewed sibling keeps its '
    'own CTA, and the round trip fires NO extra GET /bookings/me and NO '
    'second GET /bookings/{id}',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      final DateTime start = elapsedStart(2);
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-1',
          status: 'COMPLETED',
          startsAt: start,
          // The LIST flag — the card's only «Відгук» gate.
          providerCanReviewClient: true,
        ),
        // The sibling-immutability control. Also reviewable, never opened.
        fb.datasetBookingRow(
          id: 'sibling-1',
          status: 'COMPLETED',
          startsAt: elapsedStart(5),
          providerCanReviewClient: true,
        ),
      ]);
      fb.bookingStatus = 'COMPLETED';
      fb.bookingStartsAt = start.toIso8601String();
      fb.bookingEndsAt = start
          .add(const Duration(minutes: 60))
          .toIso8601String();
      // The DETAIL flag the destination pre-gates on: reviewable, so the real
      // form renders and a genuine submit is reachable.
      fb.bookingProviderCanReviewClient = true;

      final GoRouter router = await openArchive(tester, fb);

      expect(
        find.byKey(const Key('master-booking-card-review-booking-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('master-booking-card-review-sibling-1')),
        findsOneWidget,
      );

      final int listCallsBefore = fb.getMyBookingsCalls;
      final int detailCallsBefore = fb.getBookingDetailCalls;

      // ── Tap «Відгук» → the REAL form (not the pre-gate). ─────────────────
      await tester.tap(
        find.byKey(const Key('master-booking-card-review-booking-1')),
      );
      await AppHarness.settle(tester);
      expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
      expect(
        find.byKey(const Key('leave-client-feedback-submit')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('leave-client-feedback-unavailable-back')),
        findsNothing,
      );

      // ── Rate, comment, submit — a real POST /client-reviews. ─────────────
      await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
      await AppHarness.settle(tester);
      await tester.enterText(
        find.byKey(const Key('leave-client-feedback-comment')),
        'Пунктуальна, приємна клієнтка.',
      );
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('leave-client-feedback-submit')));
      await AppHarness.settle(tester);

      expect(
        fb.createClientReviewCalls,
        1,
        reason: 'exactly one real POST /client-reviews reached the fake',
      );
      expect(fb.lastClientReviewBookingId, 'booking-1');
      expect(fb.lastClientReviewRating, 5);
      expect(fb.lastClientReviewComment, 'Пунктуальна, приємна клієнтка.');

      // ── The success path pops back onto the ARCHIVE. ─────────────────────
      expect(
        find.byType(LeaveClientFeedbackScreen),
        findsNothing,
        reason: 'a successful submit pops',
      );
      expect(find.byType(MasterArchiveScreen), findsOneWidget);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.masterBookingsArchive,
      );

      // ── THE REPORTED BUG. Before the fix the CTA stayed here, re-tappable
      //    into the "already reviewed" screen, and pull-to-refresh did not
      //    clear it. The fake still reports this row as reviewable on
      //    `GET /bookings/me` (the POST flips only the DETAIL field —
      //    `fake_backend.dart:4893`), so a refetch would put the button
      //    straight back: its absence can ONLY come from
      //    `markClientReviewed`'s in-memory rewrite. ──────────────────────
      await AppHarness.pumpUntilGone(
        tester,
        find.byKey(const Key('master-booking-card-review-booking-1')),
      );
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
        reason:
            'the ROW must survive the patch — only its «Відгук» slot is gone. '
            'A patch that dropped the row (or emptied the list) would satisfy '
            'the CTA-gone assertion above just as well; this is the assertion '
            'that tells them apart',
      );
      expect(
        find.byKey(const Key('master-booking-card-review-sibling-1')),
        findsOneWidget,
        reason:
            'SIBLING IMMUTABILITY — the never-reviewed row keeps its own '
            'server-granted CTA; the patch rewrites one row, not the list',
      );

      // ── ZERO NETWORK — the entire point of replacing the cross-screen
      //    `ref.invalidate(masterArchiveProvider)` with the row patch. ─────
      expect(
        fb.getMyBookingsCalls,
        listCallsBefore,
        reason:
            'not one extra GET /bookings/me across push → submit → pop. An '
            'invalidate here would refetch page 0 (and, arriving while the '
            'archive is COVERED, DISPOSE the autoDispose element first — '
            'losing every accumulated page and the scroll position)',
      );
      expect(
        fb.getBookingDetailCalls,
        detailCallsBefore + 1,
        reason:
            'exactly ONE GET /bookings/booking-1: the _openReview warmup and '
            'the destination\'s own ref.watch share one subscription, and the '
            'ClientReviewEntry.masterArchive success path deliberately does '
            'NOT invalidate bookingDetailProvider (nothing on this stack '
            'watches it)',
      );

      // Drain the success snack's dwell Timer so none is pending at teardown.
      await pumpPastVelvetSnack(tester);
    },
  );

  // ==========================================================================
  // 5. THE 409 RACE — a review that landed between the pre-gate and the submit
  // ==========================================================================
  testWidgets(
    'a submit that 409s (feedback already left elsewhere) does NOT pop, swaps '
    'the form for the not-reviewable state, and backing out of THAT still '
    'reports «no longer reviewable» — so the archive drops the same row\'s '
    'CTA, keeps the sibling\'s, and never refetches the list',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.independentMaster
        // The race: the pre-gate's own fetch says reviewable, the WRITE says
        // otherwise. Note the 409 route deliberately leaves
        // `bookingProviderCanReviewClient` TRUE (see its doc in
        // `fake_backend.dart`), so `_NotReviewable` below can only come from
        // the screen's `_alreadyReviewed` flag — never from a server that
        // conveniently changed its mind.
        ..clientReviewRejectDuplicate = true;

      final DateTime start = elapsedStart(2);
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-1',
          status: 'COMPLETED',
          startsAt: start,
          providerCanReviewClient: true,
        ),
        fb.datasetBookingRow(
          id: 'sibling-1',
          status: 'COMPLETED',
          startsAt: elapsedStart(5),
          providerCanReviewClient: true,
        ),
      ]);
      fb.bookingStatus = 'COMPLETED';
      fb.bookingStartsAt = start.toIso8601String();
      fb.bookingEndsAt = start
          .add(const Duration(minutes: 60))
          .toIso8601String();
      fb.bookingProviderCanReviewClient = true;

      final GoRouter router = await openArchive(tester, fb);
      final int listCallsBefore = fb.getMyBookingsCalls;

      await tester.tap(
        find.byKey(const Key('master-booking-card-review-booking-1')),
      );
      await AppHarness.settle(tester);
      expect(
        find.byKey(const Key('leave-client-feedback-submit')),
        findsOneWidget,
        reason: 'the pre-gate saw a reviewable booking, so the form renders',
      );

      await tester.tap(find.byKey(const ValueKey<String>('review-star-4')));
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('leave-client-feedback-submit')));
      await AppHarness.settle(tester);

      expect(fb.createClientReviewCalls, 1);
      expect(
        find.byType(LeaveClientFeedbackScreen),
        findsOneWidget,
        reason:
            'a 409 must NOT pop — the screen swaps in place, so the master '
            'reads why their submit did not take',
      );
      expect(
        find.byKey(const Key('leave-client-feedback-unavailable-back')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('leave-client-feedback-submit')),
        findsNothing,
      );

      // ── Backing out of the 409 state reports `true` all the same. ────────
      await tester.tap(
        find.byKey(const Key('leave-client-feedback-unavailable-back')),
      );
      await AppHarness.settle(tester);
      expect(find.byType(MasterArchiveScreen), findsOneWidget);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.masterBookingsArchive,
      );

      await AppHarness.pumpUntilGone(
        tester,
        find.byKey(const Key('master-booking-card-review-booking-1')),
      );
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
        reason: 'the row survives; only its «Відгук» slot is gone',
      );
      expect(
        find.byKey(const Key('master-booking-card-review-sibling-1')),
        findsOneWidget,
        reason: 'the untouched sibling keeps its own CTA',
      );
      expect(
        fb.getMyBookingsCalls,
        listCallsBefore,
        reason:
            'the 409 path patches the row locally too — no GET /bookings/me '
            'anywhere in this round trip',
      );
    },
  );

  // ==========================================================================
  // 6. THE SECOND ENTRY PATH — archive → ROW → detail → footer CTA → submit →
  //    back → back. No pop result can reach the archive here; the SIGNAL does.
  // ==========================================================================
  testWidgets(
    'archive → tap the ROW → BookingDetailScreen → its footer «Залишити відгук '
    'про клієнта» → 5★ submit → back to detail → back to archive: that row\'s '
    '«Відгук» CTA is GONE even though nothing ever popped a result to the '
    'archive, the row and a never-reviewed sibling both survive, and the '
    'archive fires NO extra GET /bookings/me across the whole excursion',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      final DateTime start = elapsedStart(2);
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-1',
          status: 'COMPLETED',
          startsAt: start,
          providerCanReviewClient: true,
        ),
        // Sibling immutability control — reviewable, never opened, never
        // signalled. `_scheduleClientReviewSignalPatch` filters on set
        // membership, so a patch that rewrote the whole list would take this
        // CTA with it and the assertion above would pass for the wrong reason.
        fb.datasetBookingRow(
          id: 'sibling-1',
          status: 'COMPLETED',
          startsAt: elapsedStart(5),
          providerCanReviewClient: true,
        ),
      ]);
      // `GET /bookings/booking-1` — what BOTH the detail screen and, after it,
      // the review screen's pre-gate read. COMPLETED + reviewable is what makes
      // `_DetailBody._providerActions` render the footer CTA at all.
      fb.bookingStatus = 'COMPLETED';
      fb.bookingStartsAt = start.toIso8601String();
      fb.bookingEndsAt = start
          .add(const Duration(minutes: 60))
          .toIso8601String();
      fb.bookingProviderCanReviewClient = true;

      final GoRouter router = await openArchive(tester, fb);

      expect(
        find.byKey(const Key('master-booking-card-review-booking-1')),
        findsOneWidget,
        reason: 'precondition — the server marks this row reviewable',
      );
      expect(
        find.byKey(const Key('master-booking-card-review-sibling-1')),
        findsOneWidget,
      );

      final int listCallsBefore = fb.getMyBookingsCalls;
      final int detailCallsBefore = fb.getBookingDetailCalls;

      // ── 1. Tap the ROW, not the «Відгук» slot. This is `_openDetail`:
      //    fire-and-forget, no `await`, no result. From here on the archive is
      //    COVERED and its consumers are PAUSED. ───────────────────────────
      await tester.tap(find.byKey(const Key('master-booking-card-booking-1')));
      await AppHarness.settle(tester);
      expect(
        find.byType(BookingDetailScreen),
        findsOneWidget,
        reason:
            'precondition — this journey genuinely goes THROUGH the detail '
            'screen, which is what puts the archive two routes down with no '
            'pop result coming its way',
      );
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.masterBookingDetail('booking-1'),
      );

      // ── 2. The DETAIL screen's own provider footer CTA. Deliberately not the
      //    archive's slot: `_openReview` never runs on this path, so no
      //    `ClientReviewEntry.masterArchive` extra is attached and the
      //    destination takes its default `bookingDetail` entry. ─────────────
      expect(
        find.byKey(const Key('booking-detail-leave-client-feedback')),
        findsOneWidget,
        reason:
            'a COMPLETED + providerCanReviewClient booking offers the footer '
            'CTA — see `_DetailBody._providerActions`',
      );
      await tester.tap(
        find.byKey(const Key('booking-detail-leave-client-feedback')),
      );
      await AppHarness.settle(tester);

      expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.clientReview('booking-1'),
      );
      expect(
        find.byKey(const Key('leave-client-feedback-submit')),
        findsOneWidget,
        reason:
            'the pre-gate read providerCanReviewClient:true, so the real '
            'form renders',
      );

      // ── 3. A real POST /client-reviews. ────────────────────────────────
      await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
      await AppHarness.settle(tester);
      await tester.enterText(
        find.byKey(const Key('leave-client-feedback-comment')),
        'Прийшла вчасно, все чудово.',
      );
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('leave-client-feedback-submit')));
      await AppHarness.settle(tester);

      expect(fb.createClientReviewCalls, 1);
      expect(fb.lastClientReviewBookingId, 'booking-1');
      expect(fb.lastClientReviewRating, 5);

      // ── 4. The success path pops back onto the DETAIL screen — NOT the
      //    archive. This is exactly why a pop result cannot fix this journey.
      expect(
        find.byType(BookingDetailScreen),
        findsOneWidget,
        reason:
            'a successful submit pops onto whatever pushed it, which here is '
            'the DETAIL screen — the archive is still one route further down '
            'and receives nothing',
      );
      expect(
        find.byKey(const Key('booking-detail-leave-client-feedback')),
        findsNothing,
        reason:
            'ClientReviewEntry.bookingDetail invalidates '
            'bookingDetailProvider on success, and the fake flipped '
            'providerCanReviewClient false — the detail footer re-resolves '
            'its own CTA away (pre-existing behaviour, asserted here as the '
            'precondition that the excursion really did complete)',
      );

      // ── 5. Back to the archive, via the detail screen's OWN back
      //    affordance. Deliberately not a synthetic pop-with-result: nothing
      //    on this path can carry a `bool` down, which is the point. ───────
      await tester.tap(find.byKey(const Key('booking-detail-back')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterArchiveScreen), findsOneWidget);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.masterBookingsArchive,
      );

      // ── THE CYCLE-2 REGRESSION. The archive was PAUSED for the whole
      //    excursion, so the deposited id can only land once it RESUMES —
      //    `pumpUntilGone` waits for that rather than asserting on the first
      //    post-pop frame. The fake still reports this row reviewable on
      //    `GET /bookings/me` (the POST flips only the DETAIL field), so a
      //    refetch would put the CTA straight back: its absence can ONLY come
      //    from the signal-driven `markClientReviewed` rewrite. ─────────────
      await AppHarness.pumpUntilGone(
        tester,
        find.byKey(const Key('master-booking-card-review-booking-1')),
      );
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
        reason:
            'the ROW must survive — leaving a client review changes no booking '
            'status. A patch that dropped the row would satisfy the CTA-gone '
            'assertion above just as well; this tells them apart',
      );
      expect(
        find.byKey(const Key('master-booking-card-review-sibling-1')),
        findsOneWidget,
        reason:
            'SIBLING IMMUTABILITY — only the SIGNALLED id is patched; a '
            'blanket rewrite would take this CTA too',
      );

      // ── ZERO NETWORK, the same property scenario 4 pins for the adjacent
      //    path. The signal is an in-memory row patch, not an invalidate. ───
      expect(
        fb.getMyBookingsCalls,
        listCallsBefore,
        reason:
            'not one extra GET /bookings/me across archive → detail → review '
            '→ submit → pop → pop. The cross-screen '
            'ref.invalidate(masterArchiveProvider) this signal replaced would '
            'have DISPOSED the covered autoDispose element and refetched page '
            '0 on resume',
      );
      expect(
        fb.getBookingDetailCalls,
        detailCallsBefore + 2,
        reason:
            'exactly TWO GET /bookings/booking-1: the detail screen\'s own '
            'initial load, and the post-submit invalidate on the '
            'ClientReviewEntry.bookingDetail path. The review screen shares '
            'the still-mounted detail screen\'s family element, so it must NOT '
            'add a third, independent fetch of its own',
      );

      await pumpPastVelvetSnack(tester);
    },
  );

  // ==========================================================================
  // 7. THE SESSION BOUNDARY — a keepAlive, user-scoped set must not survive a
  //    logout. Driven through the REAL logout → login round trip.
  // ==========================================================================
  testWidgets(
    'the session-scoped review signal does NOT survive a logout: after '
    'submitting a review, logging out and logging back in, the archive shows '
    'that row\'s «Відгук» CTA again — the keepAlive set was emptied by the '
    'auth cascade, not carried into the new session',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      final DateTime start = elapsedStart(2);
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-1',
          status: 'COMPLETED',
          startsAt: start,
          providerCanReviewClient: true,
        ),
      ]);
      fb.bookingStatus = 'COMPLETED';
      fb.bookingStartsAt = start.toIso8601String();
      fb.bookingEndsAt = start
          .add(const Duration(minutes: 60))
          .toIso8601String();
      fb.bookingProviderCanReviewClient = true;

      final GoRouter router = await openArchive(tester, fb);

      // ── Session 1: review the booking through the DETAIL entry, and watch
      //    the CTA go.
      //
      //    THE ENTRY PATH HERE IS LOAD-BEARING — deliberately the long way
      //    round rather than the archive's own «Відгук» slot. On the adjacent
      //    path the CTA also disappears via `_openReview`'s pop result, so
      //    "the CTA is gone" would be satisfied without a single id ever
      //    reaching `clientReviewSignalProvider` — and the post-login
      //    assertion below would then be vacuously green against an empty set,
      //    proving nothing about a session boundary. Mutation-verified
      //    2026-08-17: with the deposit in `_submit` deleted, the archive-entry
      //    version of this scenario stayed GREEN; this detail-entry version
      //    goes RED at the `pumpUntilGone` below, because the signal is now the
      //    ONLY thing that can clear the CTA.
      await tester.tap(find.byKey(const Key('master-booking-card-booking-1')));
      await AppHarness.settle(tester);
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('booking-detail-leave-client-feedback')),
      );
      await AppHarness.settle(tester);
      expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('leave-client-feedback-submit')));
      await AppHarness.settle(tester);
      expect(fb.createClientReviewCalls, 1);

      expect(find.byType(BookingDetailScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('booking-detail-back')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterArchiveScreen), findsOneWidget);

      await AppHarness.pumpUntilGone(
        tester,
        find.byKey(const Key('master-booking-card-review-booking-1')),
      );
      await pumpPastVelvetSnack(tester);

      // ── Log out, for real: archive → «Мої записи» → the master nav bar's
      //    Профіль tile → the settings hub → the logout row → confirm. ──────
      await tester.tap(find.byKey(const Key('master-archive-back')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('master-nav-tile-3')));
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('btn-menu-master')));
      await AppHarness.settle(tester);
      await tester.ensureVisible(find.byKey(const Key('row-logout')));
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('row-logout')));
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('btn-logout-confirm')));
      // BOUNDED POLL, not a bare settle: `runLogoutFlow`'s in-flight
      // `authProvider.logout()` schedules no frames of its own, so a
      // `pumpAndSettle` can return BEFORE `context.go(login)` runs — the CI
      // race `logout_flow_test.dart`'s own `_pumpUntilLoggedOut` documents.
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('login_email')),
      );

      // ── Session 2: same account, brand-new session. The signal provider is
      //    `keepAlive`, so the ELEMENT survived; only the `authProvider` watch
      //    in its `build()` can have emptied its set. ──────────────────────
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('master-bookings-open-archive')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterArchiveScreen), findsOneWidget);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.masterBookingsArchive,
      );

      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('master-booking-card-booking-1')),
      );
      expect(
        find.byKey(const Key('master-booking-card-review-booking-1')),
        findsOneWidget,
        reason:
            'SEC — the fake still reports this row reviewable on '
            'GET /bookings/me, so the freshly-built archive must offer the CTA '
            'again. If `clientReviewSignalProvider.build()` did not watch the '
            'authenticated identity, the previous session\'s id would still be '
            'in the keepAlive set and would suppress this row for whoever logs '
            'in next — user-scoped data leaking across a session boundary',
      );
    },
  );

  // ==========================================================================
  // 8. THE DETAIL FETCH FAILS ON THE «ВІДГУК» ENTRY — error, not "not
  //    reviewable"; and an unknown answer must never cost the row its CTA.
  // ==========================================================================
  testWidgets(
    'when GET /bookings/{id} FAILS, «Відгук» lands on the retry error state — '
    'never the not-reviewable pre-gate — the retry genuinely re-issues the '
    'request, and backing out leaves the row\'s CTA intact so the master can '
    'try again once the fetch recovers',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.independentMaster
        // 404 → NotFoundFailure → `beauticaProviderRetry` stops on the first
        // attempt, so the error branch renders at once and the call counter
        // below stays deterministic. See `bookingDetailFailStatus`'s doc for
        // why a 5xx would instead be fed into a ~38 s backoff curve.
        ..bookingDetailFailStatus = 404;

      final DateTime start = elapsedStart(2);
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-1',
          status: 'COMPLETED',
          startsAt: start,
          providerCanReviewClient: true,
        ),
        fb.datasetBookingRow(
          id: 'sibling-1',
          status: 'COMPLETED',
          startsAt: elapsedStart(5),
          providerCanReviewClient: true,
        ),
      ]);
      fb.bookingStatus = 'COMPLETED';
      fb.bookingStartsAt = start.toIso8601String();
      fb.bookingEndsAt = start
          .add(const Duration(minutes: 60))
          .toIso8601String();
      // Would render the real form — if the fetch ever succeeded. It does not,
      // until the knob is cleared at the end of this scenario.
      fb.bookingProviderCanReviewClient = true;

      final GoRouter router = await openArchive(tester, fb);

      expect(
        find.byKey(const Key('master-booking-card-review-booking-1')),
        findsOneWidget,
      );
      final int listCallsBefore = fb.getMyBookingsCalls;
      final int detailCallsBefore = fb.getBookingDetailCalls;

      await tester.tap(
        find.byKey(const Key('master-booking-card-review-booking-1')),
      );
      await AppHarness.settle(tester);

      expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.clientReview('booking-1'),
      );
      expect(
        find.byKey(const Key('leave-client-feedback-error-retry')),
        findsOneWidget,
        reason:
            'a failing detail fetch must reach `_ErrorState` with its retry '
            'affordance — the only E2E-reachable path to that branch',
      );
      expect(
        find.byKey(const Key('leave-client-feedback-unavailable-back')),
        findsNothing,
        reason:
            'THE DISTINCTION THAT MATTERS — "we could not ask" must NEVER be '
            'rendered as "the answer was no". `_NotReviewable` is terminal and '
            'offers no retry; showing it here would strand the master',
      );
      expect(
        find.byKey(const Key('leave-client-feedback-submit')),
        findsNothing,
        reason: 'no booking loaded, so no form may be built',
      );
      expect(
        fb.getBookingDetailCalls,
        detailCallsBefore + 1,
        reason:
            'exactly one failing GET — a deterministic 404 is not auto-'
            'retried, so the error is terminal on the first attempt',
      );

      // ── The retry affordance must genuinely RE-ISSUE the request, not just
      //    rebuild the widget. Still failing, so the state must not change. ──
      await tester.tap(
        find.byKey(const Key('leave-client-feedback-error-retry')),
      );
      await AppHarness.settle(tester);
      expect(
        fb.getBookingDetailCalls,
        detailCallsBefore + 2,
        reason:
            '«Повторити» invalidates bookingDetailProvider — a real second '
            'GET reached the fake, not a silent no-op rebuild',
      );
      expect(
        find.byKey(const Key('leave-client-feedback-error-retry')),
        findsOneWidget,
        reason: 'the fetch still fails, so the error state stands',
      );

      // ── Backing out of the ERROR state reports `false`: `async.value` is
      //    null, so nothing about reviewability was ever learned. FAIL-OPEN —
      //    the mirror image of the signal set's fail-CLOSED direction. ──────
      await tester.tap(find.byKey(const Key('leave-client-feedback-back')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterArchiveScreen), findsOneWidget);

      expect(
        find.byKey(const Key('master-booking-card-review-booking-1')),
        findsOneWidget,
        reason:
            'THE FAIL-OPEN PROPERTY — a network failure must not cost the row '
            'its CTA. The list flag still says reviewable and the master '
            'learned nothing to the contrary, so hiding the button here would '
            'silently strip a capability the server still grants',
      );
      expect(
        find.byKey(const Key('master-booking-card-review-sibling-1')),
        findsOneWidget,
      );
      expect(
        fb.getMyBookingsCalls,
        listCallsBefore,
        reason: 'a failed detail fetch must not make the archive refetch',
      );
      expect(
        fb.createClientReviewCalls,
        0,
        reason: 'nothing was ever submittable',
      );

      // ── And the CTA that survived is genuinely USABLE: clear the fault and
      //    walk the same journey again to a real form. Without this, "the CTA
      //    is still there" would be an assertion about a button, not about a
      //    recoverable journey. ──────────────────────────────────────────────
      //
      //    THE RE-ENTRY BELOW IS LOAD-BEARING, and is the regression guard for
      //    mobile-qa LOW (2026-08-17 cycle 3). `bookingDetailProvider` is
      //    autoDispose, but Riverpod DEFERS the disposal of an element whose
      //    last listener just went away — long enough that a master who backs
      //    out and IMMEDIATELY re-taps «Відгук» used to re-attach to the SAME
      //    cached element and be served its stored value with no new
      //    `GET /bookings/{id}` fired at all (measured 2026-08-17: the re-entry
      //    left `getBookingDetailCalls` flat and re-rendered `_ErrorState`, and
      //    only ~10 s of idle pumping let the element go). On a FAILED first
      //    attempt that stranded the master on an error state they had to tap
      //    «Повторити» to leave; on a SUCCESSFUL one the same mechanism would
      //    replay a STALE `providerCanReviewClient` — this screen's entire job
      //    being to gate on the freshest answer to that one flag.
      //
      //    `MasterArchiveScreen._openReview` now invalidates
      //    `bookingDetailProvider(id)` immediately before pushing, so the
      //    re-entry ALWAYS fetches fresh. The scenario therefore no longer taps
      //    «Повторити» to recover: the form must appear from the re-entry
      //    ALONE. That is strictly stronger than the previous shape — it pins
      //    that the fast re-entry itself issues a request (the bug), where
      //    tapping retry first would have masked a re-entry that fired none.
      fb.bookingDetailFailStatus = null;
      await tester.tap(
        find.byKey(const Key('master-booking-card-review-booking-1')),
      );
      await AppHarness.settle(tester);
      expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);

      expect(
        find.byKey(const Key('leave-client-feedback-submit')),
        findsOneWidget,
        reason:
            'THE FAST RE-ENTRY REFETCHES — the recovered fetch renders the real '
            'form with no «Повторити» tap in between, proving the push '
            'invalidated the deferred-disposal element instead of replaying its '
            'cached AsyncError. It also proves the surviving CTA leads '
            'somewhere, and that the error state above came from the seeded '
            'fault rather than from anything structurally broken',
      );
      expect(
        find.byKey(const Key('leave-client-feedback-error-retry')),
        findsNothing,
      );
      expect(
        fb.getBookingDetailCalls,
        detailCallsBefore + 3,
        reason:
            'exactly one more GET — the re-entry is a genuine round trip that '
            'now answers 200, not a cached value the screen happened to keep. '
            'The count is unchanged from the pre-fix shape (initial + retry + '
            'recovery); what moved is WHICH action issues the third request, '
            'and a re-entry that fired none would now land here as +2',
      );
    },
  );
}
