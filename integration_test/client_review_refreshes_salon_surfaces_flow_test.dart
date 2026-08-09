// mobile-qa REGRESSION (E2E) — «залишив відгук, а профіль САЛОНУ не змінився».
//
// THE USER-REPORTED BUG
// ---------------------
// A client leaves a review on a COMPLETED booking made at a SALON and, WITHOUT
// killing the app, opens that salon's public profile: the average has not moved
// and their own review is absent. It self-heals after 5 minutes or a cold
// restart — the shape that makes a real bug look intermittent.
//
// Root cause: `LeaveReviewScreen._submit` fanned out to the MASTER triplet only
// (`848e8929`). The three providers behind the SALON's surfaces each hold
// `ref.keepAlive()` behind a 5-minute TTL: `publicSalonProfileProvider`,
// `salonReviewSummaryProvider` and `salonReviewsProvider(salonId, sort)`.
// Nothing refetched them. It could not be fixed until `Booking` carried a
// `salonId` to key the fan-out on — phase 232.
//
// The fix is `invalidateSalonReviewSurfaces(ref, salonId)`, called from the
// success branch of `LeaveReviewScreen._submit`, guarded on a non-null
// `booking.salonId`.
//
// WHY THIS FILE EXISTS ON TOP OF THE WIDGET TIER (Step 2.7 Rule 3b)
// -----------------------------------------------------------------
// `test/features/booking/presentation/leave_review_salon_surfaces_invalidation_test.dart`
// pins the invalidation EDGE with mocked repositories and container-level
// listeners: it proves each of the six cache entries refetches, and that an
// independent-master booking refetches none of them. What it cannot prove is
// the JOURNEY the user actually reported — that a client who VIEWED the salon's
// profile earlier in the same session, went off to the bookings branch, wrote a
// review, and came BACK, is shown MOVED numbers and their own review. That
// needs the real router, the real repositories, the real keepAlive caches
// surviving a route pop, and a backend whose answer genuinely CHANGES after the
// write.
//
// THE FIXTURE MUST MOVE THE NUMBER — the trap this flow was written around.
// The master flow was defanged in exactly this way once: `FakeBackend` seeded
// `reviewCount 24` on the detail against `2` on the summary, and one more 5★
// across 24 cannot shift a 1-decimal average (123/25 = 4.92 → still «4.9»), so
// the assertion could not tell a refetch from a cache hit. The salon aggregate
// is therefore seeded SMALL and RECONCILED — four reviews, (5+4+4+3)/4 = 4.0 on
// BOTH the detail and the summary endpoint — so the client's own 5★ moves it to
// (5+4+4+3+5)/5 = 4.2 EXACTLY. A full 0.2 at one decimal, no rounding boundary.
// If the caches were served stale the screens would render 4.0, so every
// assertion below discriminates "refetched" from "cache hit" by VALUE, not just
// by a call counter. `FakeBackend.salonReviewLanded` (flipped by `POST /reviews`
// when the seeded booking has a salon) is what makes the server's answer move.
//
// RIVERPOD PAUSE (project memory: "Riverpod offstage-pause invalidate gotcha"):
// with the review screen pushed over the salon profile, the profile's consumers
// are PAUSED, so the invalidation's REBUILD is deferred and the refetch lands on
// RESUME, not immediately. Every assertion here is therefore made AFTER
// returning to the profile, never straight after the submit.
//
// ⚠️ The observable above is right; the MECHANISM often quoted alongside it is
// not, and this file used to repeat it. At riverpod 3.1.0 `ref.invalidate` does
// NOT dispose a provider whose only listeners are paused: `_performDispose`
// skips it because `hasNonWeakListeners` counts paused subscriptions
// (`scheduler.dart:167`, `element.dart:407`) — mobile-perf measured `exists` →
// true straight after the invalidate. Here it could not dispose anyway: all
// three salon providers hold an OPEN `ref.keepAlive()` link for five minutes
// (`public_salon_profile_notifier.dart:57-58`), and this flow runs well inside
// that window. Nothing below depends on which of the two it is — every
// assertion is on the refetch that lands at resume — but the note is corrected
// so the next reader does not build on it.
//
// CLOCK (M15): the appended review row's `createdAt` is anchored to the
// harness's injected `kFixedNow`, the same clock the app renders it against —
// never the host clock.
//
// MUTATION-PROBED: with `invalidateSalonReviewSurfaces`'s body commented out,
// this flow goes red in § 3, on the salon-profile refetch counter —
// `Expected: a value greater than <1> / Actual: <1>`, i.e. the re-fetch that
// never happened. Relaxing that counter assertion and re-running the probe (so
// execution reaches the line after it) turns the BY-VALUE assertion red too:
// `Expected: '4.2' / Actual: '4.0'`. Both were checked, deliberately: a counter
// alone would still pass against a fixture that never moves its numbers, which
// is precisely how the master flow was once defanged.
//
// A THIRD probe (mobile-qa, 2026-08-06) shortened the per-sort loop to
// `[SalonReviewSort.newest]` — the partial-fix mutation. This flow goes red at
// § 5 with `Expected: 'HIGHEST' / Actual: 'NEWEST'`, NOT on the reviews call
// counter directly above it: that counter is satisfied by the NEWEST refetch
// alone. The counter's `reason` now says so rather than claiming a proof it
// does not carry.
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
import 'package:beautica_mobile/features/review/presentation/widgets/rating_summary_card.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

const String _salonId = 'salon-xyz';

/// The review row the client's own `POST /reviews` adds to salon-xyz's public
/// list — keyed `salon-review-<id>` by the reviews section.
final Finder _ownReviewCard = find.byKey(
  const Key('salon-review-${FakeBackend.kSalonClientReviewId}'),
);

Finder get _heroRating => find.byKey(const Key('salon-profile-rating'));
Finder get _heroReviewCount =>
    find.byKey(const Key('salon-profile-review-count'));
Finder get _summaryAverage =>
    find.byKey(const Key('salon-review-summary-average'));

String _textOf(WidgetTester tester, Finder f) => tester.widget<Text>(f).data!;

/// The COUNT half of the aggregate as the review-summary card actually holds
/// it — read off the widget instead of a localised string, so the assertion is
/// locale-proof (M2) and reads the same value the plural label is built from.
RatingSummaryCard _summaryCard(WidgetTester tester) =>
    tester.widget<RatingSummaryCard>(find.byType(RatingSummaryCard));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Opens the «Відгуки» tab (index 3) on the already-mounted salon profile.
  /// `ensureVisible` first: the tab bar can be scrolled out of the 800x600
  /// flutter-tester window by the previous tab's content.
  Future<void> openReviewsTab(WidgetTester tester) async {
    final Finder tab = find.byKey(const Key('salon-tab-3'));
    expect(tab, findsOneWidget);
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    // fixed-wait-ok: settles the real async tab switch + review-provider loads.
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  /// Switches the reviews list to the HIGHEST sort through the real sort sheet.
  /// This warms/reads a SECOND `salonReviewsProvider(salonId, sort)` family
  /// entry — the per-sort loop in `invalidateSalonReviewSurfaces` exists
  /// precisely because each `(salonId, sort)` pair is its own cache.
  Future<void> switchToHighestSort(WidgetTester tester) async {
    final Finder button = find.byKey(const Key('salon-reviews-sort-button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('salon-review-sort-option-highest')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'CLIENT views a salon public profile, leaves a review on a COMPLETED '
    'booking made AT that salon, and RE-OPENS the profile in the SAME session '
    '→ the hero rating, the summary aggregate and every sort bucket of the '
    'review list all reflect the new review (previously stale for 5 minutes)',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..bookingStatus = 'COMPLETED'
        ..bookingCanReview = true
        // The booking must be AT a salon — this is what phase 232 added and
        // what the fan-out keys on. Without `bookingSalonId` the guard at the
        // call site correctly skips the salon half and this whole flow would
        // be asserting against a code path it never entered.
        ..bookingMasterType = 'SALON_MASTER'
        ..bookingSalonId = _salonId
        ..bookingSalonName = 'Студія Краси «Камелія»';
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      // fixed-wait-ok: settles the real async login/route-transition step.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientHome);

      // ── 1. WARM the salon's public surfaces — the precondition the bug
      //       report describes ("I had just been looking at the salon"). ─────
      unawaited(router.push(RouteNames.salonPublicProfile(_salonId)));
      // fixed-wait-ok: settles the real async route-push + provider-load step.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, '/salons/$_salonId');
      expect(find.byType(PublicSalonProfileScreen), findsOneWidget);

      expect(
        _textOf(tester, _heroRating),
        FakeBackend.kSalonAvgRatingBeforeReview.toStringAsFixed(1),
        reason: 'the pre-review hero ★, straight off GET /salons/salon-xyz',
      );
      // The COUNT half of the same snapshot. Pinned alongside the average
      // because the two are what the fixture reconciliation is ABOUT: the
      // detail endpoint used to say `reviewCount: 3` while the summary said 4,
      // and an audit that only ever checks the average cannot see that class of
      // defanging return.
      final AppLocalizations salonL10n = AppLocalizations.of(
        tester.element(find.byType(PublicSalonProfileScreen)),
      );
      expect(
        _textOf(tester, _heroReviewCount),
        contains(
          salonL10n.salonReviewCountLabel(
            FakeBackend.kSalonReviewCountBeforeReview,
          ),
        ),
      );
      final int profileCallsWarm = fb.getSalonByIdCalls;
      expect(profileCallsWarm, greaterThanOrEqualTo(1));

      // The summary + the NEWEST review bucket …
      await openReviewsTab(tester);
      expect(
        _textOf(tester, _summaryAverage),
        FakeBackend.kSalonAvgRatingBeforeReview.toStringAsFixed(1),
      );
      // The SUMMARY endpoint's own count + distribution, pre-review. Pinning
      // them here is what makes the post-review pair below a MOVE rather than
      // an isolated value, and it pins the reconciliation the fixture rewrite
      // performed: the detail's count (asserted above) and the summary's count
      // must be the SAME number, which is exactly what 3-vs-4 was not.
      expect(
        _summaryCard(tester).reviewCount,
        FakeBackend.kSalonReviewCountBeforeReview,
        reason:
            'summary count must agree with the detail count — one aggregate',
      );
      expect(
        _summaryCard(tester).distribution.first,
        1,
        reason: 'one 5★ among the four seeded rows',
      );
      expect(
        find.byKey(const Key('salon-review-salon-review-1')),
        findsOneWidget,
        reason: 'a seeded row proves the list really rendered from the wire',
      );
      expect(
        _ownReviewCard,
        findsNothing,
        reason: 'the client has not written their review yet',
      );
      expect(fb.lastGetSalonReviewsSort, 'NEWEST');

      // … and a SECOND family entry, the HIGHEST bucket. Warming two distinct
      // sorts is what lets the post-review half below prove the per-sort LOOP,
      // not just its first iteration.
      await switchToHighestSort(tester);
      expect(_ownReviewCard, findsNothing);
      expect(
        fb.lastGetSalonReviewsSort,
        'HIGHEST',
        reason: 'the sort sheet must really re-key the family and re-fetch',
      );

      final int summaryCallsWarm = fb.getSalonReviewSummaryCalls;
      final int reviewsCallsWarm = fb.getSalonReviewsCalls;
      expect(
        reviewsCallsWarm,
        greaterThanOrEqualTo(2),
        reason: 'NEWEST and HIGHEST are two independent cache entries',
      );

      // ── 2. Leave the salon and go write the review. ──────────────────────
      router.pop(); // salon profile → /home
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
        fb.salonReviewLanded,
        isTrue,
        reason:
            'the server now serves MOVED salon numbers — the precondition '
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

      // ── 3. RE-OPEN the salon's public profile in the SAME session — no app
      //       restart, well inside the 5-minute keepAlive window. This is the
      //       exact step the bug report describes, and the point at which the
      //       PAUSED consumers resume and the refetch actually lands. ────────
      unawaited(router.push(RouteNames.salonPublicProfile(_salonId)));
      // fixed-wait-ok: settles the real async route-push + provider-load step.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(PublicSalonProfileScreen), findsOneWidget);

      expect(
        fb.getSalonByIdCalls,
        greaterThan(profileCallsWarm),
        reason:
            'the salon profile must have been RE-FETCHED — a keepAlive cache '
            'hit would leave this counter untouched',
      );
      expect(
        _textOf(tester, _heroRating),
        FakeBackend.kSalonAvgRatingAfterReview.toStringAsFixed(1),
        reason:
            'THE REPORTED BUG: the salon hero ★ still read the pre-review '
            'value after the client had just reviewed one of its masters',
      );
      expect(
        _textOf(tester, _heroReviewCount),
        contains(
          salonL10n.salonReviewCountLabel(
            FakeBackend.kSalonReviewCountAfterReview,
          ),
        ),
        reason:
            'the COUNT moved too (4 → 5). Asserted separately from the ★ '
            'because a refresh that carried one field and not the other is '
            'exactly the half-stale shape a single-field assertion cannot see.',
      );

      // ── 4. The summary aggregate and the NEWEST review bucket. ───────────
      await openReviewsTab(tester);
      expect(
        fb.getSalonReviewSummaryCalls,
        greaterThan(summaryCallsWarm),
        reason: 'the summary is its own keepAlive cache and must refetch too',
      );
      expect(
        _textOf(tester, _summaryAverage),
        FakeBackend.kSalonAvgRatingAfterReview.toStringAsFixed(1),
      );
      expect(
        _summaryCard(tester).reviewCount,
        FakeBackend.kSalonReviewCountAfterReview,
        reason:
            'the summary is a SEPARATE endpoint from the detail — its count '
            'must land on the same 5, or the two aggregates have drifted apart '
            'again the way 3-vs-4 once did',
      );
      expect(
        _summaryCard(tester).distribution.first,
        2,
        reason:
            'the 5★ bucket absorbed the client\'s own 5★ (1 → 2) — the '
            'distribution is rendered from the same refetched payload and a '
            'stale one would still draw a single 5★',
      );
      expect(
        _ownReviewCard,
        findsOneWidget,
        reason:
            'THE REPORTED BUG: the client\'s own review was missing from the '
            'salon\'s list until the 5-minute TTL expired',
      );

      // ── 5. The HIGHEST bucket — a DIFFERENT family entry, warmed in step 1.
      //       A loop shortened to `[SalonReviewSort.newest]` passes step 4 and
      //       fails here. ───────────────────────────────────────────────────
      await switchToHighestSort(tester);
      expect(
        fb.getSalonReviewsCalls,
        greaterThan(reviewsCallsWarm),
        reason:
            'at least one bucket re-fetched. Weak ON ITS OWN — mutation-probed '
            'on 2026-08-06: shortening the loop to `[newest]` still satisfies '
            'this, because the NEWEST refetch alone bumps the total. The two '
            'assertions below are what actually pin the loop.',
      );
      expect(
        fb.lastGetSalonReviewsSort,
        'HIGHEST',
        reason:
            'THE PER-SORT LOOP: the HIGHEST entry must have been invalidated '
            'too, so re-selecting that sort goes to the WIRE. Under a '
            '`[newest]`-only loop it is still keepAlive-cached and this reads '
            '«NEWEST» — the measured failure of that probe.',
      );
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
