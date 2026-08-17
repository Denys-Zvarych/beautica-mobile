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
//      pins `MasterBookingCard.onReview`'s status gate: a COMPLETED row
//      offers the button, a PAST-but-not-COMPLETED sibling (`NOT_COMPLETED`)
//      does not — the one behavioural claim `master_archive_screen.dart`'s
//      file header makes about this button that no existing E2E asserts.
//      Also proves `_openReview`'s `listenManual` warmup fetches the booking
//      EXACTLY ONCE end-to-end (the archive's own prefetch and the pushed
//      screen's `ref.watch` sharing one subscription) — the real-HTTP-tier
//      counterpart of `master_archive_screen_test.dart`'s mocked-repository
//      "exactly 1 fetch" proof.
//
//   3. THE PRE-GATE — opening «Відгук» for a booking whose REAL, server-
//      computed `providerCanReviewClient` is `false` (this client was
//      already reviewed) renders `_NotReviewable` immediately and the form
//      is NEVER built — not merely disabled. A mocked-repository widget test
//      can prove the branch; only a real `GET /bookings/{id}` round trip
//      proves the SCREEN actually read the real flag off the wire rather
//      than a value a stub was told to hand it.
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
        ),
        // PAST (NOT_COMPLETED classifies straight into PAST — see
        // `FakeBackend._partitionOf`) but NOT completed — the negative
        // control for `MasterBookingCard.onReview`'s status gate.
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
            'offer «Відгук» — `MasterBookingCard.onReview` is gated on '
            'status == completed, not on membership in the archive',
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
    'built, not merely disabled',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      final DateTime start = elapsedStart(3);
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-1',
          status: 'COMPLETED',
          startsAt: start,
        ),
      ]);
      fb.bookingStatus = 'COMPLETED';
      fb.bookingStartsAt = start.toIso8601String();
      fb.bookingEndsAt = start
          .add(const Duration(minutes: 60))
          .toIso8601String();
      // This client was already reviewed — the REAL, server-computed value
      // the pre-gate must read off the wire.
      fb.bookingProviderCanReviewClient = false;

      await openArchive(tester, fb);

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
    },
  );
}
