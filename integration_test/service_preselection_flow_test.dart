// Search service-filter → booking PRE-SELECTION — E2E (fake-backed).
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ---------------------------------------
// The unit tier pins the one-shot targetId-guarded provider
// (pending_service_preselection_provider_test.dart), the discovery widget tier
// pins the card recording the payload on tap
// (result_card_preselection_test.dart), and the booking widget tier pins the
// catalogue pre-checking a SEEDED payload (booking_preselection_seed_test.dart)
// — all three against stubs. NONE of them proves the real journey composes: a
// CLIENT applying a service filter in search, tapping a REAL result card (which
// fires the REAL keepAlive provider set), navigating the REAL router into the
// booking flow, and the REAL booking Step-1 catalogue — loaded over the REAL
// Dio boundary from the REAL master/salon services response carrying
// serviceTypeSlug — pre-checking EXACTLY the matching service(s).
//
// FIXTURE COHERENCE — reuses the SAME master-aaa / salon-xyz fixtures the
// discovery + public-profile flows already exercise. The fake now returns
// serviceTypeSlug on those service responses:
//   • master-aaa: pub-assign-1 (CLASSIC_MANICURE) + pub-assign-2 (GEL_MANICURE),
//     both NAILS — filtering CLASSIC_MANICURE must pre-check pub-assign-1 ONLY.
//   • salon-xyz catalogue: salon-svc-shared (NAILS / CLASSIC_MANICURE) +
//     salon-svc-exclusive (BROWS / BROW_CORRECTION) — the same filter must
//     pre-check salon-svc-shared ONLY.
//
// KEY POLICY: navigation/interaction taps are key-based (client-nav-search-center,
// search_service_type_NAILS, search_service_chip_CLASSIC_MANICURE,
// search_show_masters_cta, salon_card_salon-xyz, public-master-book-cta,
// salon-book-cta, booking_service_tile_*, salon_booking_service_tile_*,
// salon-booking-category-BROWS). Raw find.text is NOT used for taps.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_service_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/service_selector_sheet.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/master_result_card.dart';
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

  /// Reaches the search results screen with an ACTIVE service filter
  /// (NAILS → CLASSIC_MANICURE), then drains the shared fixture's forced second
  /// master page so the trailing load-more spinner stops and later settles
  /// converge. Leaves the tree on the results list with master-aaa + salon-xyz
  /// cards, both carrying the {CLASSIC_MANICURE} filter.
  Future<void> reachFilteredResults(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('client-nav-search-center')));
    await AppHarness.settle(tester);

    // Select the NAILS category → its service-chip drawer reveals, then pick
    // the CLASSIC_MANICURE chip so the applied filter carries that slug.
    await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
    await AppHarness.settle(tester);
    await tester.tap(
      find.byKey(const Key('search_service_chip_CLASSIC_MANICURE')),
    );
    await AppHarness.settle(tester);

    await tester.tap(find.byKey(const Key('search_show_masters_cta')));
    // The shared /search/masters fixture returns totalPages:2, so the trailing
    // _LoadMoreSpinner ticks immediately and no settle can converge until page
    // 1 drains. Pump-until-results (microtask-resolved fake — bare pump()).
    await tester.pump();
    for (
      int i = 0;
      i < 30 && find.byKey(const Key('results_list')).evaluate().isEmpty;
      i++
    ) {
      await tester.pump();
    }
    expect(find.byKey(const Key('results_list')), findsOneWidget);

    // Force a real scroll delta so the final jumpTo notifies _onScroll →
    // loadMore(), draining master page 1 → masterHasMore=false.
    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('results_list')),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(scrollable.position.pixels + 1);
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await AppHarness.settle(tester);
  }

  testWidgets(
    'CLIENT filters search by a service → taps a MASTER result → the booking '
    'catalogue pre-checks ONLY the matching service (exact serviceTypeSlug)',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        final GoRouter router = await AppHarness.boot(tester, fb);

        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        await reachFilteredResults(tester);

        // ── Tap master-aaa's card → records the pre-selection + navigates ────
        final Finder masterCard = find.ancestor(
          of: find.byKey(const Key('favorite_master_master-aaa')),
          matching: find.byType(MasterResultCard),
        );
        expect(masterCard, findsOneWidget);
        await tester.tap(masterCard);
        await AppHarness.settle(tester);
        AppHarness.expectShellLocation(
          router,
          RouteNames.masterPublicProfile('master-aaa'),
        );

        // ── «Записатись до майстра» → the master-scoped booking Step 1 ────────
        await tester.tap(find.byKey(const Key('public-master-book-cta')));
        await AppHarness.settle(tester);
        AppHarness.expectShellLocation(router, RouteNames.bookingNew);
        expect(find.byType(ServiceSelectorSheet), findsOneWidget);

        // ── PROOF: exact-slug pre-selection HOISTS + auto-expands the matched
        // service's CATEGORY (the pinned top section was removed) ────────────
        // pub-assign-1 (CLASSIC_MANICURE) matched → its NAILS category is
        // hoisted to the top and auto-expanded, so the tile renders IN its
        // category, pre-checked, WITHOUT a manual tap. pub-assign-2
        // (GEL_MANICURE) did not match → it renders in the SAME auto-expanded
        // NAILS category (a sibling of the match) but stays unchecked.
        final Finder nailsCategory = find.byKey(
          const Key('booking_category_NAILS'),
        );
        final Finder matched = find.byKey(
          const Key('booking_service_tile_pub-assign-1'),
        );
        final Finder unmatched = find.byKey(
          const Key('booking_service_tile_pub-assign-2'),
        );
        // The matched category is auto-expanded — both tiles render with no tap.
        expect(nailsCategory, findsOneWidget);
        expect(
          matched,
          findsOneWidget,
          reason:
              'the searched service-type (CLASSIC_MANICURE) must arrive in its '
              'hoisted, auto-expanded NAILS category',
        );
        expect(
          find.descendant(
            of: matched,
            matching: find.byKey(const ValueKey<bool>(true)),
          ),
          findsOneWidget,
          reason:
              'the searched service-type (CLASSIC_MANICURE) must arrive '
              'pre-checked on the booking catalogue',
        );
        // The non-matching sibling renders in the same auto-expanded category
        // (proving the whole category is shown, not just the match) and was NOT
        // falsely pre-checked.
        expect(
          unmatched,
          findsOneWidget,
          reason:
              'pub-assign-2 is a NAILS sibling → it renders in the '
              'auto-expanded category alongside the match, no manual tap',
        );
        expect(
          find.descendant(
            of: unmatched,
            matching: find.byKey(const ValueKey<bool>(true)),
          ),
          findsNothing,
          reason:
              'the master\'s other service (GEL_MANICURE) did not match the '
              'filter → it must stay unchecked (exact-slug, no false positive)',
        );

        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  testWidgets(
    'CLIENT filters search by a service → taps a SALON result → the salon '
    'booking catalogue pre-checks ONLY the matching service (exact '
    'serviceTypeSlug)',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        final GoRouter router = await AppHarness.boot(tester, fb);

        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        await reachFilteredResults(tester);

        // ── Tap the salon card → records the pre-selection + navigates ───────
        final Finder salonCard = find.byKey(const Key('salon_card_salon-xyz'));
        expect(salonCard, findsOneWidget);
        await tester.tap(salonCard);
        await AppHarness.settle(tester);
        AppHarness.expectShellLocation(
          router,
          RouteNames.salonPublicProfile('salon-xyz'),
        );
        expect(find.byType(PublicSalonProfileScreen), findsOneWidget);

        // ── «Записатись на послугу» → the salon booking Step 1 ───────────────
        await tester.tap(find.byKey(const Key('salon-book-cta')));
        await AppHarness.settle(tester);
        AppHarness.expectShellLocation(router, RouteNames.salonBookingServices);
        expect(find.byType(SalonServiceSelectionScreen), findsOneWidget);

        // ── PROOF: exact-slug pre-selection HOISTS + auto-expands the matched
        // service's CATEGORY (the pinned top section was removed) ────────────
        // salon-svc-shared is NAILS/CLASSIC_MANICURE → its NAILS category is
        // hoisted to the top and auto-expanded, so the tile renders IN its
        // category, pre-checked, without a manual tap.
        final Finder nailsCategory = find.byKey(
          const Key('salon_booking_category_NAILS'),
        );
        final Finder browsCategory = find.byKey(
          const Key('salon_booking_category_BROWS'),
        );
        final Finder sharedTile = find.byKey(
          const Key('salon_booking_service_tile_salon-svc-shared'),
        );
        // The matched NAILS category is hoisted above the non-matched BROWS.
        expect(nailsCategory, findsOneWidget);
        expect(browsCategory, findsOneWidget);
        expect(
          tester.getTopLeft(nailsCategory).dy <
              tester.getTopLeft(browsCategory).dy,
          isTrue,
          reason:
              'the matched NAILS category must be hoisted above the non-matched '
              'BROWS category',
        );
        expect(
          sharedTile,
          findsOneWidget,
          reason:
              'the searched service-type (CLASSIC_MANICURE) must arrive in its '
              'hoisted, auto-expanded NAILS category',
        );
        expect(
          find.descendant(
            of: sharedTile,
            matching: find.byKey(const ValueKey<bool>(true)),
          ),
          findsOneWidget,
          reason:
              'the searched service-type (CLASSIC_MANICURE) must arrive '
              'pre-checked on the salon booking catalogue',
        );

        // REGRESSION (salon-prefill label-fallback bug): salon-svc-namefallback
        // has NO serviceTypeSlug — it can only match via its serviceTypeNameUk
        // ('Класичний манікюр'), NOT its custom name ('Манікюр класичний VIP').
        // The pre-fix code compared the custom name and never checked it. It is
        // a NAILS sibling of the match, so it renders in the SAME auto-expanded
        // category and must now ALSO be pre-checked.
        final Finder nameFallbackTile = find.byKey(
          const Key('salon_booking_service_tile_salon-svc-namefallback'),
        );
        expect(
          nameFallbackTile,
          findsOneWidget,
          reason:
              'the slug-null NAILS service renders in the auto-expanded '
              'hoisted category',
        );
        expect(
          find.descendant(
            of: nameFallbackTile,
            matching: find.byKey(const ValueKey<bool>(true)),
          ),
          findsOneWidget,
          reason:
              'the slug-null service must match via serviceTypeNameUk (the '
              'fixed label fallback), NOT its custom display name, and arrive '
              'pre-checked end-to-end',
        );

        // salon-svc-exclusive is BROWS/BROW_CORRECTION → its category is NOT
        // matched, so it stays collapsed. Expand it and confirm it is UN-checked.
        await tester.tap(find.byKey(const Key('salon-booking-category-BROWS')));
        await AppHarness.settle(tester);
        final Finder exclusiveTile = find.byKey(
          const Key('salon_booking_service_tile_salon-svc-exclusive'),
        );
        expect(exclusiveTile, findsOneWidget);
        expect(
          find.descendant(
            of: exclusiveTile,
            matching: find.byKey(const ValueKey<bool>(true)),
          ),
          findsNothing,
          reason:
              'the salon\'s BROW_CORRECTION service did not match the filter → '
              'it must stay unchecked',
        );

        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
