// Track 7.x Wave B (PROVIDER leave-client-feedback) — E2E: the «Деталі
// запису» → «ВІДГУК ПРО КЛІЄНТА» → submit journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// `leave_client_feedback_screen_test.dart` (widget tier) proves the rating
// gate, the star fill, the submit call args against a MOCKED
// `ClientReviewRepository`, the success pop + VelvetSnack, the 409/400
// failure handling, and the private-chip/privacy-note rendering.
// `booking_detail_client_feedback_cta_test.dart` proves the footer CTA's
// presence + push in isolation. NEITHER proves the REAL journey wired
// together against a mutating backend:
//
//   1. An INDEPENDENT_MASTER logs in and opens the seeded COMPLETED booking's
//      «Деталі запису» directly (mirrors `master_booking_provider_actions_
//      flow_test.dart`'s established idiom of reaching the detail via
//      `router.push` — re-deriving the rail→card→detail navigation here would
//      just re-prove navigation already covered by `master_bookings_flow_
//      test.dart`).
//   2. The COMPLETED footer offers «Залишити відгук про клієнта».
//   3. Tapping it PUSHES «ВІДГУК ПРО КЛІЄНТА» onto the master's own stack.
//   4. Rating 5 + a comment + submit fires a REAL `POST /client-reviews`
//      carrying the exact bookingId/rating/comment through the generated
//      `built_value` client — a mocked-repository widget test proves the
//      DART call site is right; it cannot prove the WIRE body is.
//   5. The screen thanks the provider («Відгук збережено») and pops back to
//      the detail.
//
// KEY POLICY (AppHarness): all TAPS are key-based; Ukrainian text appears in
// CONTENT ASSERTIONS only, and status copy is asserted through l10n.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/application/pending_booking_actions_count.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_archive_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_client_feedback_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  AppLocalizations l10nOf(WidgetTester tester, Type screen) =>
      AppLocalizations.of(tester.element(find.byType(screen)));

  testWidgets(
    'PROVIDER opens a COMPLETED booking, leaves 5★ feedback about the client '
    'with a comment, and a real POST /client-reviews reaches FakeBackend',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.independentMaster
        // Seed the booking as a finished visit — the client-feedback footer
        // CTA is COMPLETED-only (see `_DetailBody._providerActions`) — AND
        // still reviewable, so the CTA is present on the first fetch below.
        ..bookingStatus = 'COMPLETED'
        ..bookingProviderCanReviewClient = true;
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // ── 1. Open «Деталі запису» for the seeded COMPLETED booking. ─────────
      unawaited(router.push(RouteNames.masterBookingDetail('booking-1')));
      await AppHarness.settle(tester);
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(
        find.byKey(const Key('booking-detail-leave-client-feedback')),
        findsOneWidget,
        reason:
            'a COMPLETED provider booking must offer «Залишити відгук про '
            'клієнта»',
      );
      final int detailFetchesBeforeSubmit = fb.getBookingDetailCalls;

      // ── 2. Tap it → «ВІДГУК ПРО КЛІЄНТА» is pushed. ────────────────────────
      await tester.tap(
        find.byKey(const Key('booking-detail-leave-client-feedback')),
      );
      await AppHarness.settle(tester);
      expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);

      // ── 3. Rate 5, write a comment, submit. ────────────────────────────────
      await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
      await AppHarness.settle(tester);
      final AppLocalizations feedbackL10n = l10nOf(
        tester,
        LeaveClientFeedbackScreen,
      );
      expect(find.text(feedbackL10n.clientReviewRatingLabel5), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('leave-client-feedback-comment')),
        'Пунктуальна, приємна клієнтка.',
      );
      await AppHarness.settle(tester);

      await tester.tap(find.byKey(const Key('leave-client-feedback-submit')));
      await AppHarness.settle(tester);

      // ── 4. The REAL wire body — not a Dart-level mock argument. ───────────
      expect(
        fb.createClientReviewCalls,
        1,
        reason: 'exactly one POST /client-reviews',
      );
      expect(fb.lastClientReviewBookingId, 'booking-1');
      expect(fb.lastClientReviewRating, 5);
      expect(fb.lastClientReviewComment, 'Пунктуальна, приємна клієнтка.');

      // The thank-you VelvetSnack surfaced…
      expectVelvetSnack(
        feedbackL10n.clientReviewSubmitSuccess,
        variant: VelvetSnackVariant.success,
      );

      // ── 5. Popped back to the detail. ──────────────────────────────────────
      expect(
        find.byType(LeaveClientFeedbackScreen),
        findsNothing,
        reason: 'a successful submit pops back to the detail',
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);

      // ── 6. REGRESSION PIN — the CTA must be gone, not re-tappable. ─────────
      // Before the fix, `LeaveClientFeedbackScreen._submit`'s success branch
      // popped straight back WITHOUT invalidating `bookingDetailProvider`, so
      // the underlying `BookingDetailScreen` kept serving its stale cached
      // booking (`providerCanReviewClient: true`) and the CTA stayed visible
      // and re-tappable — a second tap re-submitted and the backend answered
      // with a 409. The fix invalidates the provider right before the pop, so
      // returning here must show a real re-fetch (FakeBackend now answers
      // `providerCanReviewClient: false`, flipped by the POST above) and the
      // CTA must be gone as a result.
      expect(
        fb.getBookingDetailCalls,
        greaterThan(detailFetchesBeforeSubmit),
        reason:
            'popping back must trigger a REAL re-fetch of the booking detail '
            '— the whole point of the `ref.invalidate(bookingDetailProvider(…))` '
            'fix — not just reuse the stale cached value',
      );
      expect(
        find.byKey(const Key('booking-detail-leave-client-feedback')),
        findsNothing,
        reason:
            'once the client has been reviewed, the CTA must disappear so it '
            'cannot be re-tapped into a 409 — this is the regression the fix '
            'closes',
      );

      // Drain the dwell Timer so none is pending at teardown.
      await pumpPastVelvetSnack(tester);
    },
  );

  // Phase 394 (24.7b) — the pending-actions count stays fresh across the
  // archive's own mutations: complete (row CTA) → leave client feedback →
  // pull-to-refresh each re-request it, and the value goes 2 → 2 → 1.
  testWidgets(
    'archive: complete, client feedback and pull-to-refresh each refetch the '
    'pending-actions count (2 → 2 → 1)',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.independentMaster
        ..clientReviewClearsDatasetFlag = true;
      final DateTime ended = kFixedNow.subtract(
        const Duration(days: 2, hours: 2),
      );
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        // Leg (a): ended CONFIRMED. The list flag is ignored while CONFIRMED
        // (the card ANDs it with COMPLETED) and is what makes the row count
        // under leg (b) once «Виконано» flips it.
        <String, dynamic>{
          ...fb.datasetBookingRow(
            id: 'booking-1',
            status: 'CONFIRMED',
            startsAt: ended,
            providerCanReviewClient: true,
          ),
          // Server-computed; without it the card never offers «Виконано».
          'awaitingClosure': true,
        },
        // Leg (b): COMPLETED, client not yet rated.
        fb.datasetBookingRow(
          id: 'booking-2',
          status: 'COMPLETED',
          startsAt: ended.subtract(const Duration(days: 1)),
          providerCanReviewClient: true,
        ),
      ]);
      fb.bookingStartsAt = ended.toIso8601String();
      fb.bookingEndsAt = ended
          .add(const Duration(minutes: 60))
          .toIso8601String();
      fb.bookingProviderCanReviewClient = true;

      await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('master-bookings-open-archive')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterArchiveScreen), findsOneWidget);

      // The «Записи» screen (395) watches the count; also hold it live here, as the
      // archive test needs a handle on it.
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MasterArchiveScreen)),
      );
      const PendingActionsScope scope = PendingActionsScope.me(asMaster: false);
      final sub = container.listen(
        pendingBookingActionsCountProvider(scope),
        (_, _) {},
      );
      addTearDown(sub.close);
      int value() => sub.read().value ?? -1;

      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.getPendingActionsCountCalls >= 1 && value() == 2,
        description: 'initial pending-actions count == 2',
      );

      // ── 1. Complete booking-1 via the row CTA: still 2 (a → b). ──────────
      int calls = fb.getPendingActionsCountCalls;
      await tester.tap(
        find.byKey(const Key('master-booking-card-complete-booking-1')),
      );
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('complete-booking-confirm')));
      await AppHarness.settle(tester);
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.getPendingActionsCountCalls > calls,
        description: 'count re-requested after «Виконано»',
      );
      expect(fb.completeBookingCalls, 1);
      await AppHarness.pumpUntilCondition(
        tester,
        () => value() == 2,
        description: 'count still 2 after complete',
      );

      // ── 2. Leave client feedback on booking-1: 2 → 1. ────────────────────
      calls = fb.getPendingActionsCountCalls;
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('master-booking-card-review-booking-1')),
      );
      await tester.tap(
        find.byKey(const Key('master-booking-card-review-booking-1')),
      );
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('leave-client-feedback-submit')));
      await AppHarness.settle(tester);
      expect(fb.createClientReviewCalls, 1);
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.getPendingActionsCountCalls > calls && value() == 1,
        description: 'count re-requested and dropped to 1 after the review',
      );
      await pumpPastVelvetSnack(tester);

      // ── 3. Pull-to-refresh on the archive: re-requested, still 1. ────────
      calls = fb.getPendingActionsCountCalls;
      // `RefreshIndicatorState.show()` is the deterministic way to run the
      // indicator's `onRefresh` (`_refresh`); a synthetic drag does not reliably
      // cross its trigger distance on a two-row list. Not awaited: the Future
      // completes with the refresh.
      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await tester.pump();
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.getPendingActionsCountCalls > calls,
        description: 'count re-requested after archive pull-to-refresh',
      );
      expect(value(), 1);
    },
  );
}
