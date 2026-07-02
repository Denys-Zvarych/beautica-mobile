// Phase 13.6 — E2E: CLIENT public salon-profile journey.
//
// WHY THIS FILE EXISTS
// --------------------
// The widget tier (test/features/salon/presentation/public_salon_profile_screen_test.dart)
// proves PublicSalonProfileScreen in isolation with [salonRepositoryProvider]
// STUBBED — every tab's data comes from an in-memory fake repository, never a
// real HTTP round trip. It cannot catch:
//   • the search-results card actually pushing `/salons/:salonId` (already
//     covered separately by salon_result_card_test.dart, but NOT chained into
//     a real navigation from a real results screen);
//   • the real [salonRepositoryProvider] → [HttpSalonRepository] → the 5
//     public salon endpoints wired against a real (fake) HTTP backend, split
//     across MIXED transports — 3 through the generated `SalonControllerApi` /
//     `ServiceControllerApi` / `ReviewControllerApi` (built_value) and 2
//     (`/masters`, `/reviews`) through a raw authenticated [Dio] call with a
//     hand-rolled `standardSerializers` decode (see the file header of
//     `salon_repository.dart` — the Pageable wire-format workaround). A
//     contract drift on ANY of the 5 would be invisible to the widget/unit
//     tiers, which never touch a real (de)serializer;
//   • the cross-feature navigation OUT of the salon profile into the ALREADY
//     shipped public master profile (Phase 13.5) — tapping a `SalonMasterCard`
//     pushes `/masters/:masterId`, and the destination route's own guard +
//     provider stack must actually admit + load real data;
//   • the CLIENT-only route guard on `/salons/:salonId` end to end.
//
// This boots the REAL app via AppHarness (FakeBackend socket, FakeSecureStorage,
// fixed clock, overflow guard) and drives the WHOLE journey: login → the real
// discovery search screen → the real search-results screen (which itself
// fires `/search/masters` + `/search/salons`) → tap the rendered salon card →
// land on the public salon profile → switch through all 4 tabs, each backed
// by its own real provider/repository/endpoint → tap a master card → land on
// the (already-fixtured) public master profile → navigate back → toggle the
// salon favourite heart.
//
// FIXTURE COHERENCE: the salon (`salon-xyz`) and its FIRST rail master
// (`master-aaa`) are the SAME ids the discovery search-results fixture
// (`FakeBackend._searchSalonsPage0` / `_searchMastersPage0`) and the public
// master-profile fixture already seed — so this flow chains through fixtures
// that other flows in the suite already exercise, rather than inventing a
// second, disconnected salon/master pair. See `fake_backend.dart`'s "Public
// salon profile fixtures (Phase 13.6)" section for the full fixture.
//
// KEY POLICY: navigation taps are key-based (client-nav-search-center,
// search_show_masters_cta, salon_card_salon-xyz, salon-tab-N,
// salon-master-card-master-aaa, salon-favorite-toggle). Raw find.text(...) is
// used only for content assertions (salon/master/review data is backend
// fixture data). See integration_test/support/app_harness.dart.
//
// Step 2.7 Rule 3b: this is the real user journey (new screen + new route +
// provider→repository wiring + a 5-endpoint API contract) the widget tier
// cannot prove end to end.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
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

  void expectLocation(GoRouter router, String expected) {
    final String current = router.routerDelegate.currentConfiguration.uri
        .toString();
    expect(
      current,
      startsWith(expected),
      reason: 'Expected router location to start with $expected, got $current',
    );
  }

  testWidgets(
    'CLIENT taps a salon result card → the public salon profile renders real '
    'data across all 4 tabs, tapping a master card navigates to the master '
    'profile, and the favourite heart POSTs a favorite',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      // ── Log in as CLIENT → land on the client shell at /home ──────────────
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientHome);

      // ── Reach the real search-results screen (browse all, no filters) ─────
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientSearch);

      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientSearchResults);

      expect(find.byKey(const Key('results_list')), findsOneWidget);
      expect(
        fb.searchSalonsCalls,
        greaterThanOrEqualTo(1),
        reason: 'the results screen must query /search/salons',
      );
      // The seeded salon-xyz card rendered (key = backend id — proves the
      // search→card wiring reached the real fixture, not a stub).
      final Finder salonCard = find.byKey(const Key('salon_card_salon-xyz'));
      expect(salonCard, findsOneWidget);

      // ── Tap the salon card → push /salons/salon-xyz ────────────────────────
      await tester.tap(salonCard);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expectLocation(router, '/salons/salon-xyz');
      expect(
        find.byType(PublicSalonProfileScreen),
        findsOneWidget,
        reason:
            'the CLIENT guard must ADMIT a CLIENT to the public salon profile',
      );

      // ── The real repository fired the salon-detail + masters-rail reads ────
      // (publicSalonProfileProvider loads BOTH in parallel — see the notifier).
      expect(fb.getSalonByIdCalls, greaterThanOrEqualTo(1));
      expect(fb.lastGetSalonId, 'salon-xyz');
      expect(fb.getSalonMastersCalls, greaterThanOrEqualTo(1));
      expect(fb.lastGetSalonMastersId, 'salon-xyz');

      // ── Hero card: name + ★ rating rendered from the response ─────────────
      expect(find.byKey(const Key('salon-profile-name')), findsOneWidget);
      // i18n-finder-ok: the salon's display name is fixture data, not UI copy.
      expect(find.text('Студія Краси «Камелія»'), findsOneWidget);
      final Text ratingText = tester.widget<Text>(
        find.byKey(const Key('salon-profile-rating')),
      );
      expect(
        ratingText.data,
        '4.0',
        reason: 'the hero ★ rating must reflect PublicSalonResponse.avgRating',
      );
      // Regression (two-layered, alongside backend commit `ef96845`): the
      // fixture above carries ONLY the Phase 10.6+ taxonomy locality fields
      // (no legacy city/address) — the real shape of every salon
      // created/edited since Phase 10.6. This proves the taxonomy fields
      // survive the REAL wire round trip (JSON → generated PublicSalonResponse
      // → SalonMapper.fromDto → Salon → _buildLocationLine), which the widget
      // tier's hand-built Salon fixtures cannot: a mapper that silently
      // dropped these fields (the actual pre-fix bug) would leave this text
      // absent/empty here even though the widget tests already passed.
      final Text addressText = tester.widget<Text>(
        find.byKey(const Key('salon-profile-address-text')),
      );
      expect(
        addressText.data,
        'вул. Хрещатик, 12, 2 поверх',
        reason:
            'the taxonomy street/buildingNo/locationNote must reach the '
            'rendered address line through the real mapper, not just a '
            'widget-level Salon fixture',
      );

      // ── Tab 0 «Про салон» — default tab, description + Instagram contact ──
      expect(find.byKey(const Key('salon-about-text')), findsOneWidget);
      expect(
        find.text(
          'Затишна студія краси у центрі Києва. Манікюр, догляд за бровами '
          'та стрижки — довірливий сервіс з 2018 року.',
        ),
        findsOneWidget,
        reason:
            'the About tab must render the real PublicSalonResponse.description',
      );
      expect(
        find.byKey(const Key('salon-contact-instagram')),
        findsOneWidget,
        reason: 'a non-empty instagramUrl must render the contact tile',
      );

      // ── Tab 1 «Майстри» — both rail masters render from the real response ─
      await tester.tap(find.byKey(const Key('salon-tab-1')));
      await tester.pumpAndSettle();

      final Finder masterAaaCard = find.byKey(
        const Key('salon-master-card-master-aaa'),
      );
      expect(masterAaaCard, findsOneWidget);
      expect(
        find.byKey(const Key('salon-master-card-master-ccc')),
        findsOneWidget,
      );
      expect(find.text('Софія Бондар'), findsOneWidget);
      expect(find.text('Марія Гриценко'), findsOneWidget);

      // ── Tab 2 «Послуги» — the real service catalogue (2 categories) ───────
      await tester.tap(find.byKey(const Key('salon-tab-2')));
      await tester.pumpAndSettle();

      expect(
        fb.getSalonServiceCatalogCalls,
        greaterThanOrEqualTo(1),
        reason: 'the Послуги tab must query GET /salons/{id}/services',
      );
      expect(fb.lastGetSalonServiceCatalogId, 'salon-xyz');
      // NAILS is the first category → initially expanded → its service row is
      // visible without an extra tap.
      expect(
        find.byKey(const Key('salon-service-category-NAILS')),
        findsOneWidget,
      );
      expect(find.text('Манікюр класичний'), findsOneWidget);
      expect(find.text('400 грн'), findsOneWidget);
      // BROWS starts collapsed — expand it to prove its (exclusive) service
      // genuinely came from the real catalogue response, not a stray render.
      expect(
        find.byKey(const Key('salon-service-category-BROWS')),
        findsOneWidget,
      );
      expect(find.text('Корекція брів'), findsNothing);
      await tester.tap(find.byKey(const Key('salon-service-category-BROWS')));
      await tester.pumpAndSettle();
      expect(find.text('Корекція брів'), findsOneWidget);
      expect(find.text('300 грн'), findsOneWidget);

      // ── Tab 3 «Відгуки» — summary + 3 reviews across 3 distinct ratings ────
      await tester.tap(find.byKey(const Key('salon-tab-3')));
      await tester.pumpAndSettle();

      expect(fb.getSalonReviewSummaryCalls, greaterThanOrEqualTo(1));
      expect(fb.lastGetSalonReviewSummaryId, 'salon-xyz');
      expect(fb.getSalonReviewsCalls, greaterThanOrEqualTo(1));
      expect(
        fb.lastGetSalonReviewsSort,
        'NEWEST',
        reason: 'the default sort must reach the wire as the NEWEST enum value',
      );

      final Text avgText = tester.widget<Text>(
        find.byKey(const Key('salon-review-summary-average')),
      );
      expect(avgText.data, '4.0');
      expect(
        find.byKey(const Key('salon-review-salon-review-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-review-salon-review-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-review-salon-review-3')),
        findsOneWidget,
      );

      // ── Changing the sort re-fetches a server-sorted page ──────────────────
      await tester.tap(find.byKey(const Key('salon-reviews-sort-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('salon-review-sort-option-oldest')),
      );
      await tester.pumpAndSettle();
      expect(
        fb.lastGetSalonReviewsSort,
        'OLDEST',
        reason:
            'picking a new sort option must re-fetch with the new wire value',
      );

      // ── Tab 1 again → tap a master card → navigate to its public profile ──
      await tester.tap(find.byKey(const Key('salon-tab-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-master-card-master-aaa')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expectLocation(router, '/masters/master-aaa');
      expect(
        find.byType(PublicMasterProfileScreen),
        findsOneWidget,
        reason:
            'tapping a salon master card must push the real public master '
            'profile route (Phase 13.5)',
      );
      expect(
        fb.getPublicMasterCalls,
        greaterThanOrEqualTo(1),
        reason:
            'the destination route must resolve through its own real provider',
      );

      // ── Navigate back to the salon profile ─────────────────────────────────
      // PublicMasterProfileScreen has no keyed back-button widget (its chrome
      // is a bare ProfileScaffold header with an un-keyed icon) — pop the
      // router directly, mirroring the programmatic-navigation precedent in
      // public_master_profile_flow_test.dart.
      router.pop();
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expectLocation(router, '/salons/salon-xyz');
      expect(find.byType(PublicSalonProfileScreen), findsOneWidget);

      // ── Toggle the salon favourite heart → optimistic flip → POST ─────────
      expect(fb.addFavoriteCalls, 0);
      await tester.tap(find.byKey(const Key('salon-favorite-toggle')));
      await tester.pumpAndSettle();

      expect(
        fb.addFavoriteCalls,
        1,
        reason: 'tapping the empty heart must POST exactly one favorite',
      );
      expect(fb.lastAddFavoriteBody?['targetType'], 'SALON');
      expect(fb.lastAddFavoriteBody?['targetId'], 'salon-xyz');

      // ── CLIENT never touched a master-only or salon-owner-only endpoint ────
      expect(fb.getMasterCalls, 0);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Route guard — a non-CLIENT reaching /salons/:salonId is redirected before
  // the public salon endpoints are ever touched. Mirrors the identical guard
  // pin in public_master_profile_flow_test.dart for the master route.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets(
    'INDEPENDENT_MASTER reaching /salons/:id is redirected to /master/profile '
    '(CLIENT-only route guard)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.masterProfile);

      unawaited(router.push(RouteNames.salonPublicProfile('salon-xyz')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // clientOnlyGuard → roleHomePath(independentMaster) → /master/profile.
      expectLocation(router, RouteNames.masterProfile);
      expect(find.byType(PublicSalonProfileScreen), findsNothing);
      expect(
        fb.getSalonByIdCalls,
        0,
        reason:
            'the redirect must fire BEFORE the public salon detail is fetched',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
