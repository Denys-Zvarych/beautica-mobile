// Phase 14.12/14.13 QA follow-up — E2E: CLIENT salon booking journey.
//
// WHY THIS FILE EXISTS
// --------------------
// This session shipped a brand-new user journey (public salon profile → book
// → select services → assign masters → coming-soon placeholder) AND fixed a
// real backend-crash bug: the booking CTA used to push [RouteNames.bookingNew]
// with `salon.id` misused as a `masterId`, 404ing server-side with
// `NotFoundException: Master not found` (see `public_salon_profile_screen.dart`'s
// `_BookingShelf`). The widget tier
// (salon_service_selection_screen_test.dart, salon_master_selection_screen_test.dart)
// proves each screen in isolation with EVERY provider stubbed — it cannot
// catch:
//   • the CTA actually reaching `SalonServiceSelectionScreen` over a REAL
//     route push, not the old buggy destination;
//   • [salonMasterServiceCoverageProvider]'s bounded fan-out actually
//     round-tripping `GET /masters/{id}/services` for the REAL salon roster
//     (8 masters) over the wire, correctly filtering ineligible masters and
//     surfacing only the ones who cover a selected service;
//   • the full click-through chain (services → masters → confirm) landing on
//     the coming-soon placeholder, never the independent-master
//     `SlotPickerScreen` (that screen assumes a single `masterId`, which a
//     salon booking never has).
//
// FIXTURE COHERENCE: reuses the SAME `salon-xyz` fixture + 8-master roster
// already seeded for `public_salon_profile_flow_test.dart`
// (`FakeBackend._salonMasters` / `_salonServiceCategories`). Reaches the
// salon profile via the SAME real UI chain that sibling file already proves
// (discovery search → results → tap the salon card), not a raw
// `router.push` — that keeps this test on the one navigation path already
// known to settle deterministically against the real ShellRoute/bottom-nav
// stack. Of the 8 roster masters, only `master-ccc` (covers
// `salon-svc-shared`) and `master-ddd` (covers `salon-svc-exclusive`) are
// eligible once both salon services are selected — see `fake_backend.dart`'s
// "GET /api/v1/masters/{masterId}/services" section for the full coverage
// split and why `master-aaa` is deliberately ineligible here (it reuses the
// UNRELATED Phase 13.5 public-profile fixture, which covers neither salon
// service).
//
// KEY POLICY: navigation taps are key-based (client-nav-search-center,
// search_show_masters_cta, salon_card_salon-xyz, salon-book-cta,
// salon-booking-category-BROWS, salon_booking_service_tile_<id>,
// booking-summary-cta, salon_booking_master_row_<id>,
// salon-assign-confirm-cta). Raw find.text(...) is used only for content
// assertions on fixture data, never for tapping.
//
// Step 2.7 Rule 3b: this is the real user journey (new screens + 3 new
// routes + a keepAlive provider fanning a real HTTP call out over a real
// roster) the widget tier cannot prove end to end. Also carries the ONLY
// real-app exercise of `BookingSummaryBar`'s expand toggle + per-item "×"
// remove affordance (mobile-qa audit, added alongside that feature) — see
// the "Per-item remove affordance" block below.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_booking_coming_soon_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_master_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_service_selection_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  void expectLocation(GoRouter router, String expected) {
    // `currentConfiguration.uri` deliberately EXCLUDES `ImperativeRouteMatch`
    // entries (see go_router's `RouteMatchList.uri` doc comment) — every
    // route this flow reaches after the initial `/search` tab (the salon
    // profile + all 3 salon-booking routes) is pushed imperatively via
    // `context.push`/`context.go` ON TOP OF the CLIENT `StatefulShellRoute`,
    // so `.uri` would keep reporting the shell branch's root ('/search')
    // instead of the actually-displayed screen. `matches.last.matchedLocation`
    // is what go_router's own `ImperativeRouteMatch` uses internally and is
    // always the full absolute path (see `match.dart`), so it reflects the
    // real current screen regardless of shell nesting.
    final String current =
        router.routerDelegate.currentConfiguration.matches.last.matchedLocation;
    expect(
      current,
      startsWith(expected),
      reason: 'Expected router location to start with $expected, got $current',
    );
  }

  testWidgets('CLIENT books a salon service end to end: profile CTA → service '
      'selection → master assignment (ineligible masters filtered, eligible '
      'masters auto-attached) → coming-soon placeholder', (tester) async {
    await mockNetworkImagesFor(() async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);

      // Reach the salon profile via the SAME real UI chain
      // `public_salon_profile_flow_test.dart` already proves (discovery →
      // search-results → tap the salon card) rather than a raw
      // `router.push` — this is the actual path a CLIENT takes, and it
      // exercises the real ShellRoute/bottom-nav navigation stack instead
      // of a programmatic jump.
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      // The shared `/search/masters` fixture unconditionally returns
      // `totalPages: 2` on page 0, so `masterHasMore` is already `true` the
      // instant page 0 lands — BEFORE any scroll. The results screen's
      // trailing `_LoadMoreSpinner` is not scroll-gated (it's laid out
      // eagerly whenever `hasMore` is true and the short 2-item list
      // undershoots the viewport), so its indeterminate spinner starts
      // ticking immediately and no `pumpAndSettle`/`AppHarness.settle` can
      // ever converge here — settling must wait until AFTER the scroll-drain
      // below resolves `masterHasMore` to `false`. Use bounded plain pumps to
      // let the route push + page-0 fetch land instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const Key('results_list')),
        findsOneWidget,
        reason: 'must land on the search results screen after the tap',
      );

      // Drain the shared fixture's forced second page so the trailing
      // `_LoadMoreSpinner` stops spinning and every subsequent settle can
      // converge.
      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('results_list')),
          matching: find.byType(Scrollable),
        ),
      );
      final ScrollPosition position = scrollable.position;
      // The 2-item first page (1 master + 1 salon) undershoots the
      // viewport, so `maxScrollExtent == pixels == 0` already — a bare
      // `jumpTo(maxScrollExtent)` is a genuine Flutter no-op (jumpTo only
      // notifies listeners when the target differs from the current
      // `pixels`) and would never fire the `_onScroll` listener that calls
      // `loadMore()`. Force a real pixel delta first so the final jumpTo is
      // guaranteed to notify.
      position.jumpTo(position.pixels + 1);
      position.jumpTo(position.maxScrollExtent);
      await AppHarness.settle(
        tester,
      ); // masters page 1 drains → masterHasMore=false

      final Finder salonCard = find.byKey(const Key('salon_card_salon-xyz'));
      expect(salonCard, findsOneWidget);
      await tester.tap(salonCard);
      await AppHarness.settle(tester);
      expectLocation(router, '/salons/salon-xyz');
      expect(find.byType(PublicSalonProfileScreen), findsOneWidget);

      // ── Tap "Записатись на послугу" → service selection (NOT a crash) ──
      final Finder bookCta = find.byKey(const Key('salon-book-cta'));
      expect(bookCta, findsOneWidget);
      await tester.tap(bookCta);
      await AppHarness.settle(tester);

      expectLocation(router, RouteNames.salonBookingServices);
      expect(find.byType(SalonServiceSelectionScreen), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'reaching the salon service-selection step must never throw '
            '— this is the regression proof for the old bookingNew '
            '(masterId-misuse) crash',
      );

      // NAILS category is expanded by default → its shared service tile is
      // immediately tappable.
      final Finder sharedTile = find.byKey(
        const Key('salon_booking_service_tile_salon-svc-shared'),
      );
      expect(sharedTile, findsOneWidget);
      await tester.tap(sharedTile);
      await AppHarness.settle(tester);

      // BROWS starts collapsed — expand it to reach the exclusive tile.
      await tester.tap(find.byKey(const Key('salon-booking-category-BROWS')));
      await AppHarness.settle(tester);
      final Finder exclusiveTile = find.byKey(
        const Key('salon_booking_service_tile_salon-svc-exclusive'),
      );
      expect(exclusiveTile, findsOneWidget);
      await tester.tap(exclusiveTile);
      await AppHarness.settle(tester);

      // ── Per-item "×" remove affordance (mobile-qa Rule 3b follow-up) ────
      // Widget tests already prove this SECOND deselection path converges to
      // the same state as unchecking the catalogue tile, but only against
      // fully-stubbed providers. This is the ONE place in the suite that
      // drives the real GestureDetector hit-test + Semantics node through a
      // real routed screen with the real ValueListenableBuilder toggle —
      // neither `salon_service_selection_screen_test.dart` nor this file
      // previously tapped the expand toggle or the remove icon at all.
      await tester.tap(find.byKey(const Key('booking-summary-expand-toggle')));
      await AppHarness.settle(tester);
      final Finder removeExclusive = find.byKey(
        const Key('booking-summary-remove-salon-svc-exclusive'),
      );
      expect(removeExclusive, findsOneWidget);
      await tester.tap(removeExclusive);
      await AppHarness.settle(tester);

      // The catalogue tile's own selection indicator reflects the removal —
      // the two paths land on identical state in the real app, not just in
      // an isolated widget test.
      expect(
        find.descendant(
          of: exclusiveTile,
          matching: find.byKey(const ValueKey<bool>(true)),
        ),
        findsNothing,
        reason:
            'removing salon-svc-exclusive via the shelf must deselect its '
            'catalogue tile too — both paths drive the same _toggleService',
      );

      // mobile-qa gap: the assertion above only proves the REMOVED tile
      // deselects — it can't distinguish that from a regression that wipes
      // the whole selection set (both look identical once only one service
      // was ever selected at a time). salon-svc-shared was also selected
      // going into this removal, so re-check it explicitly survives, and
      // that the CTA is still enabled off that lone survivor — in the REAL
      // app, not an isolated widget test.
      expect(
        find.descendant(
          of: sharedTile,
          matching: find.byKey(const ValueKey<bool>(true)),
        ),
        findsOneWidget,
        reason:
            'removing salon-svc-exclusive via the shelf must NOT deselect '
            'salon-svc-shared — a regression that clears the whole '
            'selection instead of just the tapped id would slip past a '
            'single-survivor-blind check',
      );
      expect(
        tester
            .widget<NeumorphicButton>(
              find.byKey(const Key('booking-summary-cta')),
            )
            .onPressed,
        isNotNull,
        reason:
            'salon-svc-shared remains selected — the "Далі" CTA must stay '
            'enabled through the shelf-driven removal of the other service',
      );

      // Re-select it via the catalogue tile (the flow below needs both
      // services selected) — this also proves the catalogue tap still works
      // after a shelf-driven removal, i.e. the two triggers do not desync.
      await tester.tap(exclusiveTile);
      await AppHarness.settle(tester);
      expect(
        find.descendant(
          of: exclusiveTile,
          matching: find.byKey(const ValueKey<bool>(true)),
        ),
        findsOneWidget,
      );

      // ── "Далі" → master assignment ──────────────────────────────────────
      final Finder nextCta = find.byKey(const Key('booking-summary-cta'));
      expect(nextCta, findsOneWidget);
      await tester.tap(nextCta);
      // Settles the real async route-push step after the tap AND the real
      // `salonMasterServiceCoverageProvider` fan-out over the 8-master roster.
      await AppHarness.settle(tester);

      expectLocation(router, RouteNames.salonBookingMasters);
      expect(find.byType(SalonMasterSelectionScreen), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'the bounded fan-out over the real 8-master roster must never '
            'throw — an unregistered roster master would fail the whole '
            '`Future.wait` batch and land here on the error state instead',
      );

      // The bounded fan-out reached EVERY roster master, not just the
      // first chunk — proves the chunk loop covers the full roster over
      // the real wire, not only `_kFetchChunkSize` (8) of the 8-master
      // roster's first (and only, here) chunk.
      expect(
        fb.requestedSalonRosterMasterIds,
        containsAll(<String>[
          'master-ccc',
          'master-ddd',
          'master-eee',
          'master-fff',
          'master-ggg',
          'master-hhh',
          'master-iii',
        ]),
        reason:
            'the coverage fan-out must query every roster master (except '
            'master-aaa, which reuses the pre-existing Phase 13.5 route)',
      );

      // ── Only the 2 ELIGIBLE masters render (of 8 on the roster) ────────
      expect(
        find.byKey(const Key('salon_booking_master_row_master-ccc')),
        findsOneWidget,
        reason: 'master-ccc covers salon-svc-shared — eligible',
      );
      expect(
        find.byKey(const Key('salon_booking_master_row_master-ddd')),
        findsOneWidget,
        reason: 'master-ddd covers salon-svc-exclusive — eligible',
      );
      for (final String ineligibleId in <String>[
        'master-aaa', // reuses the Phase 13.5 fixture — covers neither
        'master-eee',
        'master-fff',
        'master-ggg',
        'master-hhh',
        'master-iii',
      ]) {
        expect(
          find.byKey(Key('salon_booking_master_row_$ineligibleId')),
          findsNothing,
          reason:
              '$ineligibleId covers neither selected salon service and '
              'must never render on the master-assignment step',
        );
      }

      // ── Pick both eligible masters → each is the sole candidate for its
      // service → auto-attach → "Підтвердити" becomes enabled ────────────
      await tester.tap(
        find.byKey(const Key('salon_booking_master_row_master-ccc')),
      );
      await AppHarness.settle(tester);
      await tester.tap(
        find.byKey(const Key('salon_booking_master_row_master-ddd')),
      );
      await AppHarness.settle(tester);

      final Finder confirmCta = find.byKey(
        const Key('salon-assign-confirm-cta'),
      );
      expect(confirmCta, findsOneWidget);
      await tester.tap(confirmCta);
      await AppHarness.settle(tester);

      // ── Lands on the coming-soon placeholder — NEVER the
      // independent-master SlotPickerScreen (that flow assumes a single
      // masterId, which a salon booking never has) ───────────────────────
      expectLocation(router, RouteNames.salonBookingComingSoon);
      expect(find.byType(SalonBookingComingSoonScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }, timeout: const Timeout(Duration(seconds: 90)));
}
