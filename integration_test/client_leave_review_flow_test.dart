// Phase 14.6 (CLIENT leave-review) — E2E: the «МОЇ ЗАПИСИ» → «Деталі запису»
// → «ВІДГУК ПРО МАЙСТРА» → submit journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// leave_review_screen_test.dart proves each surface in isolation: the rating
// gate, the star fill, the createReview call args, the success pop + SnackBar,
// the `!canReview` info state, and the booking-detail entry CTA's presence +
// push. NONE of them proves the REAL journey wired together against a mutating
// backend:
//
//   1. CLIENT logs in and opens the Записи branch.
//   2. A COMPLETED, still-reviewable booking is visible in Минулі («Виконано»).
//   3. Opening it lands on «Деталі запису» with the «Залишити відгук» CTA.
//   4. Tapping it PUSHES «ВІДГУК ПРО МАЙСТРА» onto the Записи branch.
//   5. Rating 5 + a comment + submit fires POST /reviews carrying the exact
//      bookingId/rating/comment, and the server flips the booking's canReview
//      false.
//   6. The screen thanks the client («Дякуємо за відгук!») and pops back to the
//      detail, whose invalidated re-fetch now HIDES the leave-review CTA (a
//      second review is no longer offered).
//
// The FakeBackend seeds `booking-1` COMPLETED + canReview:true and flips
// canReview false on the review POST, so the detail re-fetch reflects the move.
//
// KEY POLICY (AppHarness): all TAPS are key-based; Ukrainian text appears in
// CONTENT ASSERTIONS only, and status copy is asserted through l10n.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_review_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_tab_bar.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  AppLocalizations l10nOf(WidgetTester tester, Type screen) =>
      AppLocalizations.of(tester.element(find.byType(screen)));

  testWidgets(
    'CLIENT opens a COMPLETED booking, leaves a 5★ review with a comment, and '
    'the detail hides the leave-review CTA afterwards',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        // Seed the booking as a finished, still-reviewable visit.
        ..bookingStatus = 'COMPLETED'
        ..bookingCanReview = true;
      final GoRouter router = await AppHarness.boot(tester, fb);

      // Cold start → /login.
      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
      await AppHarness.loginAs(tester, fb, UserRole.client);

      // ── 1. Open the Записи branch (bottom-nav tile 3). ────────────────────
      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientBookings);
      expect(find.byType(MyBookingsScreen), findsOneWidget);

      // ── 2. Switch to Минулі — the COMPLETED booking lives there. ──────────
      final AppLocalizations tabsL10n = l10nOf(tester, MyBookingsScreen);
      await tester.tap(
        find.descendant(
          of: find.byType(MyBookingsTabBar),
          matching: find.text(tabsL10n.myBookingsTabPast),
        ),
      );
      await AppHarness.settle(tester);

      expect(
        find.byKey(const ValueKey<String>('service-booking-1')),
        findsOneWidget,
        reason: 'the COMPLETED booking must appear under Минулі',
      );
      expect(
        find.text(tabsL10n.bookingStatusCompleted),
        findsOneWidget,
        reason: 'the card must carry the «Виконано» status badge',
      );

      // ── 3. Open «Деталі запису» → the leave-review CTA is offered. ────────
      await tester.tap(find.byType(BookingCard));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.bookingDetail('booking-1'));
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(
        find.byKey(const Key('booking-detail-leave-review')),
        findsOneWidget,
        reason: 'a reviewable COMPLETED booking must offer «Залишити відгук»',
      );

      // ── 4. Tap it → «ВІДГУК ПРО МАЙСТРА» is pushed. ───────────────────────
      await tester.tap(find.byKey(const Key('booking-detail-leave-review')));
      await AppHarness.settle(tester);
      expect(find.byType(LeaveReviewScreen), findsOneWidget);

      // ── 5. Rate 5, write a comment, submit. ───────────────────────────────
      await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
      await AppHarness.settle(tester);
      // The live readout confirms the 5★ selection registered.
      final AppLocalizations reviewL10n = l10nOf(tester, LeaveReviewScreen);
      expect(find.text(reviewL10n.reviewRatingLabel5), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('leave-review-comment')),
        'Дуже задоволена, дякую!',
      );
      await AppHarness.settle(tester);

      await tester.tap(find.byKey(const Key('leave-review-submit')));
      await AppHarness.settle(tester);

      // ── 6. POST /reviews fired with the exact payload; canReview flipped. ─
      expect(fb.createReviewCalls, 1, reason: 'exactly one POST /reviews');
      expect(fb.lastReviewBookingId, 'booking-1');
      expect(fb.lastReviewRating, 5);
      expect(fb.lastReviewComment, 'Дуже задоволена, дякую!');
      expect(
        fb.bookingCanReview,
        isFalse,
        reason: 'the server marks the booking no longer reviewable',
      );

      // The thank-you SnackBar surfaced…
      expect(
        find.text(reviewL10n.reviewSubmitSuccess),
        findsOneWidget,
        reason: 'the client must be thanked on success',
      );

      // ── 7. Popped back to the detail, which now HIDES the entry CTA. ──────
      expect(
        find.byType(LeaveReviewScreen),
        findsNothing,
        reason: 'a successful submit pops back to the detail',
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(
        find.byKey(const Key('booking-detail-leave-review')),
        findsNothing,
        reason:
            'the invalidated detail re-fetch re-resolved canReview:false — a '
            'second review is no longer offered',
      );

      // Drain the SnackBar's auto-dismiss timer so none is pending at teardown.
      await tester.pumpUntilGone(find.text(reviewL10n.reviewSubmitSuccess));
    },
  );
}
