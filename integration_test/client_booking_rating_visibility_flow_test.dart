// Phase 240 (rating visibility) — E2E: the master's rating is VISIBLE on the
// booking surfaces, and each one routes the client into that master's reviews.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// THE REPORTED BUG. A client left a review on a booking whose appointment had
// elapsed but whose status was still CONFIRMED, and then could not see the
// review or any rating change ANYWHERE. The backend was proven correct by
// integration test — the review persists and every read endpoint returns it.
// The review was invisible because ratings and reviews were barely surfaced in
// the client's journey at all: the ONE route to a master's reviews was
// «Профіль майстра» → «Відгуки» tile, which a client who booked from
// «Мої записи» never passes through.
//
// So the defect was not in any single widget — it was in the WIRING between
// the wire contract, two derivations, one shared card and two screens. That is
// precisely what the unit and widget tiers cannot see:
//
//   • `master_rating_x_test.dart` / `booking_display_x_test.dart` prove the
//     two folds return the right value. Neither proves a value reaches a
//     screen.
//   • `master_strip_rating_test.dart` proves a hand-constructed `Booking`
//     renders «4.9» or «—». It constructs that Booking IN DART — it never
//     crosses `BookingMapper`, so it cannot prove the Phase 240 wire fields
//     survive deserialization, and it cannot prove the tap target exists on a
//     real routed screen.
//   • `booking_detail_screen_test.dart` mocks the repository, so the wire
//     shape is never exercised and `context.push` has no real router tree to
//     land in.
//
// This flow drives all of it against a mutating fake HTTP backend:
//
//   Test 1 — RATING VISIBLE + BOTH ROUTES INTO REVIEWS
//     1. CLIENT logs in, opens Записи → Минулі, opens the COMPLETED booking.
//     2. «Деталі запису» shows the master's ★ 4.9 (24) — read off the WIRE,
//        through BookingMapper → Booking.masterDisplayRating → MasterStrip.
//     3. Tapping the master strip PUSHES the master's public reviews list, and
//        the real PUBLIC review endpoints fire for THAT master.
//     4. Back on the detail, «Залишити відгук» opens the leave-feedback screen,
//        which shows the SAME rating…
//     5. …and its master card taps through to the same reviews list.
//
//   Test 2 — THE STALE-ZERO NEGATIVE CONTROL (wire-level, unreachable elsewhere)
//     A pre-240 payload carrying `masterAvgRating: 0` with NO count must read
//     «—» on both screens, never «0.0». This is the exact artefact Phase 240
//     removed, it is a property of the WIRE, and only a fake-backed flow can
//     seed it. It doubles as the mutation control for Test 1: it proves those
//     assertions are pinned to the rating pipeline and not to some constant
//     that happens to be on screen.
//
// NO PATROL TIER. This is pure in-app navigation — `context.push` between
// three Flutter routes. There is no OS permission dialog, no deep link or app
// link, no notification, no WebView and no biometric, so nothing here needs
// `$.native.*` / `$.platform.*`. Adding a patrol case would be coverage
// theater; stating that explicitly is the required alternative.
//
// CLOCK: the seeded booking window comes from `FakeBackend`'s own
// `bookingStartsAt`/`bookingEndsAt`, and every assertion below is about a
// RATING, never a date — so this flow reads no clock of its own and cannot
// mix a pinned fixture clock with a live app clock (M15).
//
// KEY POLICY (AppHarness): all TAPS are key-based. The rating readout is a
// NUMBER/em-dash glyph rather than localized copy, so `find.text` is the
// correct finder for it; localized copy is asserted through l10n.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_review_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_tab_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_reviews_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The seeded booking's master strip on «Деталі запису».
const Key _kDetailStrip = Key('booking-detail-master-strip');

/// The master identity card on «Залишити відгук».
const Key _kFeedbackCard = Key('leave-review-master-card');

/// The reviews route the two cards must both reach.
const String _kReviewsRoute = '/masters/master-aaa/reviews';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  AppLocalizations l10nOf(WidgetTester tester, Type screen) =>
      AppLocalizations.of(tester.element(find.byType(screen)));

  /// Logs a CLIENT in and lands on «Деталі запису» for the seeded COMPLETED,
  /// still-reviewable `booking-1`. Shared by both tests so each one's body is
  /// only the part it is actually about.
  Future<GoRouter> openBookingDetail(
    WidgetTester tester,
    FakeBackend fb,
  ) async {
    final GoRouter router = await AppHarness.boot(tester, fb);
    expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
    await AppHarness.loginAs(tester, fb, UserRole.client);

    await tester.tap(find.byKey(const Key('client-nav-tile-3')));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.clientBookings);

    final AppLocalizations tabsL10n = l10nOf(tester, MyBookingsScreen);
    await tester.tap(
      find.descendant(
        of: find.byType(MyBookingsTabBar),
        matching: find.text(tabsL10n.myBookingsTabPast),
      ),
    );
    await AppHarness.settle(tester);

    await tester.tap(find.byType(BookingCard));
    await AppHarness.settle(tester);
    // `/bookings/:bookingId` is a child GoRoute INSIDE the client shell's
    // bookings branch, so `matches.last` stays a ShellRouteMatch and plain
    // `expectLocation` would read the stale branch root — only the drill-down
    // resolver sees the pushed leaf.
    AppHarness.expectNestedPushLocation(
      router,
      RouteNames.bookingDetail('booking-1'),
    );
    expect(find.byType(BookingDetailScreen), findsOneWidget);
    return router;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Test 1 — the rating is visible, and BOTH booking surfaces route into the
  // master's reviews.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets(
    'CLIENT sees the master\'s rating on «Деталі запису» and on «Залишити '
    'відгук», and EITHER card taps through to that master\'s public reviews',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..bookingStatus = 'COMPLETED'
        ..bookingCanReview = true
        // The Phase 240 wire fields — the whole point of the contract change.
        // 4.9 / 24 are DISTINCT from every other number these screens render
        // (price 650, duration 90) so a passing assertion cannot be some other
        // value's coincidence.
        ..bookingMasterAvgRating = 4.9
        ..bookingMasterReviewCount = 24;

      final GoRouter router = await openBookingDetail(tester, fb);

      // ── 1. The rating rendered on «Деталі запису». ──────────────────────
      //
      // Scoped to the strip, not the whole screen: an unscoped `find.text` on
      // a busy detail screen could match a stray glyph elsewhere and pass for
      // the wrong reason.
      final Finder strip = find.byKey(_kDetailStrip);
      expect(
        strip,
        findsOneWidget,
        reason:
            'the client-side counterparty header must render the master strip '
            '— it is the surface the rating rides on.',
      );
      expect(
        find.descendant(of: strip, matching: find.text('4.9')),
        findsOneWidget,
        reason:
            'the WIRE masterAvgRating must survive BookingMapper → '
            'Booking.masterDisplayRating → MasterStrip.fromBooking and reach '
            'the screen. This is the visibility half of the reported bug.',
      );
      expect(
        find.descendant(of: strip, matching: find.text('(24)')),
        findsOneWidget,
        reason: 'the wire masterReviewCount must reach the muted suffix',
      );
      expect(
        find.descendant(
          of: strip,
          matching: find.text(MasterStrip.noRatingLabel),
        ),
        findsNothing,
        reason: 'a rated master must not fall through to the em-dash',
      );

      // ── 2. Tapping the strip opens THAT master's public reviews. ────────
      //
      // Tapped on the REAL rendered card — not a `router.push` stand-in. A
      // `router.go`/`router.push` shortcut here would prove nothing about the
      // affordance, which is the entire fix.
      await tester.tap(strip);
      await AppHarness.settle(tester);

      // `/masters/:masterId/reviews` is a TOP-LEVEL route (above the client
      // shell), so the plain resolver — not the nested-push one — is correct.
      AppHarness.expectLocation(router, _kReviewsRoute);
      expect(find.byType(PublicMasterReviewsScreen), findsOneWidget);
      expect(
        fb.getPublicMasterReviewsCalls,
        greaterThanOrEqualTo(1),
        reason:
            'the PUBLIC GET /masters/master-aaa/reviews route must have fired '
            '— landing on the screen without loading the list would be a '
            'half-fix.',
      );
      // Landing on the ROUTE is not landing on the CONTENT: the list key is
      // only mounted on the non-empty data branch (the empty state uses
      // `master-reviews-empty`), so this is the assertion that the client
      // actually SEES the reviews that were invisible to them.
      expect(
        find.byKey(const Key('master-reviews-list')),
        findsOneWidget,
        reason:
            'the reported bug was reviews being unreachable — reaching an '
            'empty or still-loading screen would not fix it.',
      );
      expect(
        fb.getMasterReviewsCalls,
        0,
        reason:
            'a CLIENT must never resolve the AUTHENTICATED-master self route',
      );

      // ── 3. Back to the detail — `push`, so the state is intact. ─────────
      router.pop();
      await AppHarness.settle(tester);
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.bookingDetail('booking-1'),
      );

      // ── 4. «Залишити відгук» shows the SAME rating. ─────────────────────
      await tester.tap(find.byKey(const Key('booking-detail-leave-review')));
      await AppHarness.settle(tester);
      expect(find.byType(LeaveReviewScreen), findsOneWidget);

      final Finder feedbackCard = find.byKey(_kFeedbackCard);
      expect(feedbackCard, findsOneWidget);
      expect(
        find.descendant(of: feedbackCard, matching: find.text('4.9')),
        findsOneWidget,
        reason:
            'the leave-feedback screen was the other dead end for ratings — a '
            'client about to write a review could not see what others had '
            'said, nor reach them.',
      );
      expect(
        find.descendant(of: feedbackCard, matching: find.text('(24)')),
        findsOneWidget,
      );

      // ── 5. …and taps through to the same reviews list. ──────────────────
      await tester.tap(feedbackCard);
      await AppHarness.settle(tester);

      AppHarness.expectLocation(router, _kReviewsRoute);
      expect(find.byType(PublicMasterReviewsScreen), findsOneWidget);
      // Rendered CONTENT again, not the call count. Deliberately not
      // `getPublicMasterReviewsCalls > before`: the reviews provider is cached
      // and legitimately serves the second entry point without a re-fetch (it
      // was measured at exactly 1 call across both landings). Asserting a
      // second HTTP call would pin this test to a caching implementation
      // detail and fail on correct code — the thing that matters, and the
      // thing the bug was about, is that the client SEES the reviews.
      expect(
        find.byKey(const Key('master-reviews-list')),
        findsOneWidget,
        reason:
            'the second entry point must reach the real, populated list — not '
            'merely match a route string.',
      );

      // Popping returns to the half-written review, not to the detail — the
      // reason this card uses `push` rather than `go`.
      router.pop();
      await AppHarness.settle(tester);
      expect(
        find.byType(LeaveReviewScreen),
        findsOneWidget,
        reason:
            'reading other reviews must be a DETOUR: the client comes back to '
            'the screen they left, with it still mounted.',
      );
    },
  );

  // ═══════════════════════════════════════════════════════════════════════
  // Test 2 — the stale-zero negative control, at the wire.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets(
    'a PRE-240 payload carrying masterAvgRating 0 with NO review count renders '
    'the em-dash on both booking surfaces, never «0.0»',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..bookingStatus = 'COMPLETED'
        ..bookingCanReview = true
        // The stale storage artefact: `masters.avg_rating` is NOT NULL
        // DEFAULT 0.00, so a pre-240 backend (or an older cached response)
        // sends a literal 0 and OMITS the count entirely. Guarding on the
        // count alone lets this through as «0.0» — a damning zero stars on a
        // master nobody has reviewed. Only a fake-backed flow can seed the
        // "absent count" half of this shape.
        ..bookingMasterAvgRating = 0
        ..bookingMasterReviewCount = null;

      await openBookingDetail(tester, fb);

      final Finder strip = find.byKey(_kDetailStrip);
      expect(
        find.descendant(
          of: strip,
          matching: find.text(MasterStrip.noRatingLabel),
        ),
        findsOneWidget,
        reason:
            'a stale 0.0 with an absent count is a storage artefact, not a '
            'score — it must fold to «—».',
      );
      expect(
        find.descendant(of: strip, matching: find.text('0.0')),
        findsNothing,
        reason: 'the exact artefact Phase 240 exists to remove',
      );
      expect(
        find.descendant(of: strip, matching: find.text('(0)')),
        findsNothing,
        reason: 'an UNKNOWN count must never be printed as «(0)»',
      );

      // The same fold on «Залишити відгук» — the two screens derive the label
      // separately (`_Form` composes its own `ratingLabel`), so agreeing here
      // is a real assertion, not a restatement.
      await tester.tap(find.byKey(const Key('booking-detail-leave-review')));
      await AppHarness.settle(tester);
      expect(find.byType(LeaveReviewScreen), findsOneWidget);

      final Finder feedbackCard = find.byKey(_kFeedbackCard);
      expect(
        find.descendant(
          of: feedbackCard,
          matching: find.text(MasterStrip.noRatingLabel),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: feedbackCard, matching: find.text('0.0')),
        findsNothing,
      );
    },
  );
}
