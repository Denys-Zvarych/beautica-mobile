// mobile-qa REGRESSION (E2E) — «залишив відгук, а профіль майстра не змінився».
//
// THE USER-REPORTED BUG
// ---------------------
// A client leaves a review on a COMPLETED booking and, WITHOUT killing the app,
// re-opens the master's public profile: the new review is absent and the rating
// / review-count are stale. It self-heals after 5 minutes or a cold restart —
// the shape that makes a real bug look intermittent.
//
// Root cause: `leave_review_notifier.dart` invalidated ONLY
// `bookingDetailProvider(bookingId)`. The three providers behind the master's
// public surfaces each hold `ref.keepAlive()` behind a 5-minute TTL:
// `publicMasterProfileProvider`, `masterReviewSummaryProvider` and
// `masterReviewsProvider(masterId, sort)`. Nothing refetched them.
//
// The fix is `invalidateMasterReviewSurfaces(ref, masterId)`, called from the
// success branch of `LeaveReviewScreen._submit`.
//
// WHY THIS FILE EXISTS ON TOP OF THE WIDGET TIER (Step 2.7 Rule 3b)
// -----------------------------------------------------------------
// `test/features/booking/presentation/leave_review_master_surfaces_invalidation_test.dart`
// pins the invalidation EDGE with mocked repositories and container-level
// listeners: it proves each of the six cache entries refetches. What it cannot
// prove is the JOURNEY the user actually reported — that a client who VIEWED
// the master's profile earlier in the same session, then went off to the
// bookings branch, wrote a review, and came BACK, is shown MOVED numbers and
// their own review. That needs: the real router, the real repositories, the real
// keepAlive caches surviving a route pop, and a backend whose answer genuinely
// CHANGES after the write.
//
// The last part is what makes this flow load-bearing rather than decorative:
// `FakeBackend.publicMasterReviewLanded` (flipped by `POST /reviews`) moves the
// public detail's rating 4.5 → 4.7 and count 2 → 3, moves the summary
// aggregate identically (ONE reconciled number per field across both
// endpoints), and appends the client's own review row. If the caches were served
// stale, the screens would still render the BEFORE numbers — so every assertion
// below discriminates "refetched" from "cache hit" by VALUE, not just by a call
// counter.
//
// CLOCK (M15): the review row's `createdAt` is anchored to the harness's
// injected `kFixedNow`, the same clock the app renders it against — never the
// host clock.
//
// MUTATION-PROBED: with `invalidateMasterReviewSurfaces(ref, booking.masterId)`
// commented out at `leave_review_screen.dart:119`, this flow fails on the first
// post-review profile assertion (the re-fetch that never happened). See the QA
// report for the verbatim red.
//
// KEY POLICY (AppHarness): all taps are key-based; Ukrainian text appears in
// CONTENT ASSERTIONS only.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_review_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_tab_bar.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_reviews_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

/// The review row the client's own `POST /reviews` adds to master-aaa's public
/// list — keyed `master-review-<id>` by `MasterReviewsBody`.
final Finder _ownReviewCard = find.byKey(
  const Key('master-review-${FakeBackend.kClientReviewId}'),
);

Finder get _ratingValue =>
    find.byKey(const Key('public-master-profile-rating-value'));
Finder get _reviewsValue =>
    find.byKey(const Key('public-master-profile-reviews-value'));
Finder get _summaryAverage =>
    find.byKey(const Key('master-review-summary-average'));

String _textOf(WidgetTester tester, Finder f) => tester.widget<Text>(f).data!;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Opens the reviews screen from the already-mounted public profile by
  /// tapping the REAL «Відгуки» stat tile, then switches the sort to
  /// «Найвищий рейтинг» and back is NOT needed — the caller decides.
  Future<void> openReviews(WidgetTester tester) async {
    final Finder tile = find.byKey(
      const Key('public-master-profile-reviews-tile'),
    );
    expect(tile, findsOneWidget);
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    // fixed-wait-ok: settles the real async route-push + review-provider loads.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(PublicMasterReviewsScreen), findsOneWidget);
  }

  /// Switches the reviews list to the HIGHEST sort through the real sort sheet.
  /// This warms/reads a SECOND `masterReviewsProvider(masterId, sort)` family
  /// entry — the per-sort loop in `invalidateMasterReviewSurfaces` exists
  /// precisely because each `(masterId, sort)` pair is its own cache.
  Future<void> switchToHighestSort(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('master-reviews-sort-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('master-review-sort-option-highest')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'CLIENT views a master public profile, leaves a review on a COMPLETED '
    'booking, and RE-OPENS the profile in the SAME session → the rating, the '
    'review count, the summary aggregate and every sort bucket of the review '
    'list all reflect the new review (previously stale for 5 minutes)',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..bookingStatus = 'COMPLETED'
        ..bookingCanReview = true;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      // fixed-wait-ok: settles the real async login/route-transition step.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientHome);

      // ── 1. WARM the master's public surfaces — the precondition the bug
      //       report describes ("I had just been looking at the master"). ────
      unawaited(router.push(RouteNames.masterPublicProfile('master-aaa')));
      // fixed-wait-ok: settles the real async route-push + provider-load step.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, '/masters/master-aaa');
      expect(find.byType(PublicMasterProfileScreen), findsOneWidget);

      expect(
        _textOf(tester, _ratingValue),
        FakeBackend.kPublicMasterAvgRatingBeforeReview.toStringAsFixed(1),
        reason: 'the pre-review rating, straight off GET /masters/master-aaa',
      );
      expect(
        _textOf(tester, _reviewsValue),
        '${FakeBackend.kPublicMasterReviewCountBeforeReview}',
      );
      final int profileCallsWarm = fb.getPublicMasterCalls;
      expect(profileCallsWarm, greaterThanOrEqualTo(1));

      // The summary + the NEWEST review bucket …
      await openReviews(tester);
      expect(
        _textOf(tester, _summaryAverage),
        FakeBackend.kPublicMasterAvgRatingBeforeReview.toStringAsFixed(1),
      );
      expect(find.byKey(const Key('master-review-pub-r1')), findsOneWidget);
      expect(
        _ownReviewCard,
        findsNothing,
        reason: 'the client has not written their review yet',
      );

      // … and a SECOND family entry, the HIGHEST bucket. Warming two distinct
      // sorts is what lets the post-review half below prove the per-sort LOOP,
      // not just its first iteration.
      await switchToHighestSort(tester);
      expect(find.byKey(const Key('master-review-pub-r1')), findsOneWidget);
      expect(_ownReviewCard, findsNothing);
      expect(
        fb.lastGetPublicMasterReviewsSort,
        'HIGHEST',
        reason: 'the sort sheet must really re-key the family and re-fetch',
      );

      final int summaryCallsWarm = fb.getPublicMasterReviewSummaryCalls;
      final int reviewsCallsWarm = fb.getPublicMasterReviewsCalls;
      expect(
        reviewsCallsWarm,
        greaterThanOrEqualTo(2),
        reason: 'NEWEST and HIGHEST are two independent cache entries',
      );

      // ── 2. Leave the profile and go write the review. ────────────────────
      router.pop(); // reviews → profile
      await AppHarness.settle(tester);
      router.pop(); // profile → /home
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientHome);

      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientBookings);
      expect(find.byType(MyBookingsScreen), findsOneWidget);

      final AppLocalizations tabsL10n = AppLocalizations.of(
        tester.element(find.byType(MyBookingsScreen)),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(MyBookingsTabBar),
          matching: find.text(tabsL10n.myBookingsTabPast),
        ),
      );
      await AppHarness.settle(tester);

      await tester.tap(find.byType(BookingCard));
      await AppHarness.settle(tester);
      expect(find.byType(BookingDetailScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('booking-detail-leave-review')));
      await AppHarness.settle(tester);
      expect(find.byType(LeaveReviewScreen), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
      await AppHarness.settle(tester);
      await tester.enterText(
        find.byKey(const Key('leave-review-comment')),
        'Дуже задоволена, дякую!',
      );
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('leave-review-submit')));
      await AppHarness.settle(tester);

      expect(fb.createReviewCalls, 1, reason: 'exactly one POST /reviews');
      expect(fb.lastReviewBookingId, 'booking-1');
      expect(
        fb.publicMasterReviewLanded,
        isTrue,
        reason:
            'the server now serves MOVED public numbers — the precondition '
            'that makes every assertion below discriminate refetch from cache',
      );
      expect(
        find.byType(LeaveReviewScreen),
        findsNothing,
        reason: 'a successful submit pops back to the detail',
      );

      final AppLocalizations detailL10n = AppLocalizations.of(
        tester.element(find.byType(BookingDetailScreen)),
      );
      await tester.pumpUntilGone(find.text(detailL10n.reviewSubmitSuccess));

      // ── 3. RE-OPEN the master's public profile in the SAME session — no
      //       app restart, well inside the 5-minute keepAlive window. This is
      //       the exact step the bug report describes. ────────────────────────
      unawaited(router.push(RouteNames.masterPublicProfile('master-aaa')));
      // fixed-wait-ok: settles the real async route-push + provider-load step.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(PublicMasterProfileScreen), findsOneWidget);

      expect(
        fb.getPublicMasterCalls,
        greaterThan(profileCallsWarm),
        reason:
            'the profile must have been RE-FETCHED — a keepAlive cache hit '
            'would leave this counter untouched',
      );
      expect(
        _textOf(tester, _ratingValue),
        FakeBackend.kPublicMasterAvgRatingAfterReview.toStringAsFixed(1),
        reason:
            'THE REPORTED BUG: the rating still read the pre-review value after '
            'the client had just rated this master',
      );
      expect(
        _textOf(tester, _reviewsValue),
        '${FakeBackend.kPublicMasterReviewCountAfterReview}',
        reason: 'the review count must include the review just written',
      );

      // ── 4. The summary aggregate and the NEWEST review bucket. ───────────
      await openReviews(tester);
      expect(
        fb.getPublicMasterReviewSummaryCalls,
        greaterThan(summaryCallsWarm),
        reason: 'the summary is its own keepAlive cache and must refetch too',
      );
      expect(
        _textOf(tester, _summaryAverage),
        FakeBackend.kPublicMasterAvgRatingAfterReview.toStringAsFixed(1),
      );
      expect(
        _ownReviewCard,
        findsOneWidget,
        reason:
            'THE REPORTED BUG: the client\'s own review was missing from the '
            'list until the 5-minute TTL expired',
      );

      // ── 5. The HIGHEST bucket — a DIFFERENT family entry, warmed in step 1.
      //       A loop shortened to `[MasterReviewSort.newest]` passes step 4
      //       and fails here. ────────────────────────────────────────────────
      await switchToHighestSort(tester);
      expect(
        fb.getPublicMasterReviewsCalls,
        greaterThan(reviewsCallsWarm),
        reason: 'both warmed sort buckets must have been re-fetched',
      );
      expect(fb.lastGetPublicMasterReviewsSort, 'HIGHEST');
      expect(
        _ownReviewCard,
        findsOneWidget,
        reason:
            'a client who had switched to «Найвищий рейтинг» must not be left '
            'looking at a page that predates their own review',
      );
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );
}
