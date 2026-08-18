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
import 'package:beautica_mobile/features/booking/presentation/salon_service_selection_screen.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
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

  testWidgets('CLIENT taps a salon result card → the public salon profile renders real '
      'data across all 4 tabs, tapping a master card navigates to the master '
      'profile, and the favourite heart POSTs a favorite', (tester) async {
    await mockNetworkImagesFor(() async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      // ── Log in as CLIENT → land on the client shell at /home ──────────────
      await AppHarness.loginAs(tester, fb, UserRole.client);
      // fixed-wait-ok: settles the real async login/route-transition step.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientHome);

      // ── Reach the real search-results screen (browse all, no filters) ─────
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      // fixed-wait-ok: settles the real async route-push step after the tap.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientSearch);

      // NOT `pumpAndSettle()`: FakeBackend's `/search/masters` fixture always
      // seeds `totalPages: 2`, so the results screen mounts a trailing
      // INDETERMINATE `_LoadMoreSpinner` the instant page 0 loads (its
      // `CircularProgressIndicator`'s repeating `AnimationController` keeps a
      // frame perpetually scheduled). `pumpAndSettle` can never observe
      // quiescence in that state and hangs until the test's own [Timeout]
      // kills it — pump-until-found instead (see [AppHarness.pumpUntilFound]).
      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('results_list')),
      );
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.clientSearchResults,
      );

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
      // `pumpUntilFound(results_list)` above returns when the DATA lands, which
      // is unrelated to the route transition: /search/results is a plain
      // MaterialPage (app_router.dart:441) and the app pins
      // CupertinoPageTransitionsBuilder for every platform (app_theme.dart:37),
      // so the page slides in from the right over 500 ms. Mid-slide the card is
      // in the TREE (the findsOneWidget above passes) but its global centre can
      // sit past the right edge of the 800x600 flutter-tester view, so tap()
      // hits NOTHING and the push never happens. Gate on the card being
      // genuinely hit-testable — a no-op once the page is home.
      await AppHarness.pumpUntilFound(tester, salonCard.hitTestable());
      await tester.tap(salonCard);
      // fixed-wait-ok: settles the real async route-push step after the tap.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      AppHarness.expectLocation(router, '/salons/salon-xyz');
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
      // → SalonMapper.fromDto → Salon → buildStreetLine), which the widget
      // tier's hand-built Salon fixtures cannot: a mapper that silently
      // dropped these fields (the actual pre-fix bug) would leave this text
      // absent/empty here even though the widget tests already passed.
      //
      // `locationNote` is NEVER folded onto this SAME string (the pre-223
      // bug this line used to pin the regression for) — it renders as its
      // own `ExpandableNote` on the hero card instead (Phase 223 (b) moved
      // it to the About tab; Phase 224 moved it back onto the hero card —
      // asserted right below); this line must carry ONLY the street +
      // building number.
      final Text addressText = tester.widget<Text>(
        find.byKey(const Key('salon-profile-address-text')),
      );
      expect(
        addressText.data,
        'вул. Хрещатик, 12',
        reason:
            'the taxonomy street/buildingNo must reach the rendered address '
            'line through the real mapper, not just a widget-level Salon '
            'fixture — and locationNote must NOT be folded onto it anymore',
      );

      // ── Hero card: locationNote (Phase 223 (b) / 224) ──────────────────────
      // Renders as its own `ExpandableNote` directly under the address lines
      // on the hero card — proves the REAL wire's `locationNote` field
      // (`'2 поверх'`, short — no overflow) survives `SalonMapper.fromDto`
      // all the way to THIS widget, a boundary the widget tier's fake
      // repository bypasses entirely (mobile-security LOW follow-up: the
      // widget tier had zero coverage of this render site before Phase 223;
      // see `public_salon_profile_screen_test.dart`'s "hero card — location
      // note" group for the isolated widget-level coverage of every case).
      expect(
        find.descendant(
          of: find.byKey(const Key('salon-profile-hero-card')),
          matching: find.byKey(const Key('salon-profile-location-note')),
        ),
        findsOneWidget,
        reason: 'a non-empty locationNote must render on the hero card',
      );
      // i18n-finder-ok: salon-xyz's real GET /salons/{id} locationNote fixture value, not UI copy.
      expect(find.text('2 поверх'), findsOneWidget);
      expect(
        find.byKey(const Key('expandable-note-toggle')),
        findsNothing,
        reason:
            'this short note fits within the 3-line clamp — no expand '
            'affordance should render for it',
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

      // ── Explicit relocation guard: the About tab is confirmed on-screen
      // above (this is the default tab, rendered simultaneously with the
      // hero card), so re-checking the note's key/text count here — after
      // the About tab body has fully rendered — makes the "not duplicated
      // onto the About tab" invariant an explicit, permanent assertion
      // rather than an accidental side effect of the unscoped `find.text`
      // check above (see the equivalent widget-tier guard in
      // `public_salon_profile_screen_test.dart`'s "hero card — location
      // note" group for the full rationale).
      expect(
        find.byKey(const Key('salon-profile-location-note')),
        findsOneWidget,
        reason:
            'the locationNote key must appear exactly once in the whole '
            'tree — once on the hero card, never again on the About tab',
      );
      // i18n-finder-ok: salon-xyz's real GET /salons/{id} locationNote fixture value, not UI copy.
      expect(find.text('2 поверх'), findsOneWidget);

      // ── About tab: real portfolio photo rail (previously an unwired
      // backend endpoint, `GET /salons/{salonId}/portfolio`) — proves the
      // GENERATED `MediaControllerApi` client + built_value deserialization
      // of Spring's default `Page<T>` envelope survive a real wire round
      // trip, a boundary `public_salon_profile_screen_test.dart`'s fake
      // repository bypasses entirely.
      expect(fb.getSalonPortfolioCalls, greaterThanOrEqualTo(1));
      expect(fb.lastGetSalonPortfolioId, 'salon-xyz');
      expect(
        find.byKey(const Key('salon-about-portfolio')),
        findsOneWidget,
        reason: 'the About tab must render the real portfolio photo rail',
      );
      expect(
        find.byKey(const Key('salon-portfolio-photo-media-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-portfolio-photo-media-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-portfolio-photo-media-3')),
        findsOneWidget,
      );

      // ── Tab 1 «Майстри» — the real 8-master roster from the wire, capped to
      // 6 up front (mobile-perf LOW fix, Phase 13.6 audit follow-up), with a
      // "show all" affordance revealing the rest. The widget tier
      // (public_salon_profile_screen_test.dart) already proves this cap logic
      // in isolation against a hand-built fixture list; what it CANNOT prove
      // is that the cap still holds against the REAL wire response — the
      // masters rail goes through a hand-rolled `page=0&size=50` Pageable
      // decode (`HttpSalonRepository`, see file header) that the widget
      // tier's fake repository bypasses entirely. A silent truncation or
      // off-by-one in that decode would be invisible there.
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
      // Master display names below are real-wire fixture data from
      // FakeBackend (proving the actual roster decode), not translated copy.
      // i18n-finder-ok: master display name is fixture data, not UI copy.
      expect(find.text('Софія'), findsOneWidget);
      // i18n-finder-ok: master display name is fixture data, not UI copy.
      expect(find.text('Марія'), findsOneWidget);

      // The 7th/8th masters (beyond the initial-6 cap) must stay unbuilt —
      // even though all 8 arrived in a single real response.
      expect(
        find.byKey(const Key('salon-master-card-master-hhh')),
        findsNothing,
        reason:
            'the 7th master must not be built until "show all" is tapped, '
            'proving the eager-build cap survives the real wire round trip',
      );
      expect(
        find.byKey(const Key('salon-master-card-master-iii')),
        findsNothing,
      );

      final Finder showAllMasters = find.byKey(
        const Key('salon-masters-show-all'),
      );
      expect(
        showAllMasters,
        findsOneWidget,
        reason: 'a real 8-master roster must render the reveal affordance',
      );

      // `-d flutter-tester`'s window is `Size(800, 600)` — short and wide,
      // unlike any phone. The masters grid (2-column, `shrinkWrap: true` +
      // `NeverScrollableScrollPhysics` inside the screen's single outer
      // `SingleChildScrollView` — see `_MastersTab._buildGrid`) is fully
      // BUILT regardless of scroll offset (shrink-wrapping forces eager
      // realization, unlike a lazy `ListView.builder`), so `find.byKey`
      // above already resolved it — but `tester.tap()` still hit-tests
      // against the real viewport, and this affordance sits well below the
      // 600px fold. `tester.ensureVisible` (not `scrollUntilVisible`) is the
      // right idiom here because the target Element already exists; it just
      // needs to be scrolled into the visible window, not built.
      await tester.ensureVisible(showAllMasters);
      await tester.tap(showAllMasters);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-master-card-master-hhh')),
        findsOneWidget,
        reason:
            'tapping "show all" must reveal the remaining real masters, not '
            'just a widget-level fixture',
      );
      // i18n-finder-ok: master display name is real-wire fixture data.
      expect(find.text('Вікторія'), findsOneWidget);
      expect(
        showAllMasters,
        findsNothing,
        reason: 'the affordance must disappear once everything is revealed',
      );

      // ── Tab 2 «Послуги» — the real service catalogue (2 categories) ───────
      // The masters grid we just expanded ("show all", 8 cards over 4 rows)
      // left the outer `SingleChildScrollView` scrolled well down; the fixed
      // `SalonTabBar` sits ABOVE that content, so it can now be off-screen
      // too. `ensureVisible` — same idiom as above — brings it back into the
      // 800x600 viewport before the tap (the tab bar itself is always built,
      // never lazy).
      final Finder tab2 = find.byKey(const Key('salon-tab-2'));
      await tester.ensureVisible(tab2);
      await tester.tap(tab2);
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
      // Service name + price below are real-wire catalogue fixture data
      // from FakeBackend, not translated UI copy.
      // i18n-finder-ok: service name is fixture data, not UI copy.
      expect(find.text('Манікюр класичний'), findsOneWidget);
      // i18n-finder-ok: price string is fixture data (priceDisplay), not UI copy.
      expect(find.text('400 ₴'), findsOneWidget);
      // BROWS starts collapsed — expand it to prove its (exclusive) service
      // genuinely came from the real catalogue response, not a stray render.
      expect(
        find.byKey(const Key('salon-service-category-BROWS')),
        findsOneWidget,
      );
      // i18n-finder-ok: service name is real-wire catalogue fixture data.
      expect(find.text('Корекція брів'), findsNothing);
      // Same fold issue as above — BROWS is the second (collapsed) category,
      // rendered below NAILS's already-expanded service row, and may sit
      // past the 600px viewport depending on the carried-over scroll offset
      // from the previous tab. Content is eagerly built (plain Column, not a
      // lazy list), so `ensureVisible` is enough.
      final Finder browsCategory = find.byKey(
        const Key('salon-service-category-BROWS'),
      );
      await tester.ensureVisible(browsCategory);
      await tester.tap(browsCategory);
      await tester.pumpAndSettle();
      // i18n-finder-ok: service name is real-wire catalogue fixture data.
      expect(find.text('Корекція брів'), findsOneWidget);
      // i18n-finder-ok: price string is fixture data (priceDisplay), not UI copy.
      expect(find.text('300 ₴'), findsOneWidget);

      // ── Tab 3 «Відгуки» — summary + 4 reviews (3 serviceName wire shapes) ──
      // Same reasoning as the tab-2 switch above — the tab bar can be
      // scrolled out of the 800x600 window by the previous tab's content.
      final Finder tab3 = find.byKey(const Key('salon-tab-3'));
      await tester.ensureVisible(tab3);
      await tester.tap(tab3);
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
      final Finder review1Card = find.byKey(
        const Key('salon-review-salon-review-1'),
      );
      expect(review1Card, findsOneWidget);
      expect(
        find.byKey(const Key('salon-review-salon-review-2')),
        findsOneWidget,
      );
      final Finder review3Card = find.byKey(
        const Key('salon-review-salon-review-3'),
      );
      expect(review3Card, findsOneWidget);
      final Finder review4Card = find.byKey(
        const Key('salon-review-salon-review-4'),
      );
      expect(review4Card, findsOneWidget);

      // The «послуга: » label was dropped from the service sub-line — it now
      // renders ONLY the raw name over the real wire (fake_backend.dart's
      // `_salonReviews` fixture). salon-review-1 carries a resolved
      // `serviceName`; salon-review-3 sends `null` and salon-review-4 sends an
      // explicit empty string — both must NOT show the spa icon/sub-line at
      // all (never a stray icon nor a leftover «послуга» label).
      expect(
        find.descendant(
          of: review1Card,
          // i18n-finder-ok: 'Манікюр класичний' is FakeBackend review fixture data, not UI copy.
          matching: find.text('Манікюр класичний'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: review1Card,
          matching: find.byIcon(Icons.spa_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: review1Card,
          matching: find.textContaining('послуга'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: review3Card,
          matching: find.byIcon(Icons.spa_outlined),
        ),
        findsNothing,
        reason:
            'salon-review-3 sends a null serviceName over the wire — no '
            'sub-line at all',
      );
      expect(
        find.descendant(
          of: review4Card,
          matching: find.byIcon(Icons.spa_outlined),
        ),
        findsNothing,
        reason:
            'salon-review-4 sends an explicit empty-string serviceName over '
            'the wire — must ALSO omit the sub-line, never a bare «послуга: »',
      );
      expect(
        find.descendant(
          of: review4Card,
          matching: find.textContaining('послуга'),
        ),
        findsNothing,
      );

      // ── Changing the sort re-fetches a server-sorted page ──────────────────
      // The sort button sits right under the rating-summary card, near the
      // top of the Відгуки tab's content — but the carried-over scroll
      // offset from switching tabs can still leave it below the fold.
      final Finder sortButton = find.byKey(
        const Key('salon-reviews-sort-button'),
      );
      await tester.ensureVisible(sortButton);
      await tester.tap(sortButton);
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
      final Finder tab1Again = find.byKey(const Key('salon-tab-1'));
      await tester.ensureVisible(tab1Again);
      await tester.tap(tab1Again);
      await tester.pumpAndSettle();

      final Finder masterAaaCardAgain = find.byKey(
        const Key('salon-master-card-master-aaa'),
      );
      await tester.ensureVisible(masterAaaCardAgain);
      await tester.tap(masterAaaCardAgain);
      // fixed-wait-ok: settles the real async route-push step after the tap.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      AppHarness.expectLocation(router, '/masters/master-aaa');
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
      // fixed-wait-ok: settles the real async route-pop (back navigation) step.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      AppHarness.expectLocation(router, '/salons/salon-xyz');
      expect(find.byType(PublicSalonProfileScreen), findsOneWidget);

      // ── Toggle the salon favourite heart → optimistic flip → POST ─────────
      // Lives in `_CoverAndHero`, at the very TOP of the same outer
      // scrollable — defensively brought into view in case the master-profile
      // round trip left the screen scrolled anywhere else.
      expect(fb.addFavoriteCalls, 0);
      final Finder favoriteToggle = find.byKey(
        const Key('salon-favorite-toggle'),
      );
      await tester.ensureVisible(favoriteToggle);
      await tester.tap(favoriteToggle);
      await tester.pumpAndSettle();

      expect(
        fb.addFavoriteCalls,
        1,
        reason: 'tapping the empty heart must POST exactly one favorite',
      );
      expect(fb.lastAddFavoriteBody?['targetType'], 'SALON');
      expect(fb.lastAddFavoriteBody?['targetId'], 'salon-xyz');

      // ── Tap the pinned booking-shelf CTA → push the salon booking flow ─────
      // UPDATED (Phase 14.12/14.13 QA follow-up): this CTA used to push
      // [RouteNames.bookingNew] with `salon.id` misused as a `masterId` — the
      // real bug behind the backend's `NotFoundException: Master not found`
      // crash (public_salon_profile_screen.dart's booking CTA). It now pushes
      // [RouteNames.salonBookingServices] (Phase 14.12 service-selection
      // step) with the salon id, never the single-master flow. Reaching
      // `SalonServiceSelectionScreen` (not a crash, not the old route) is the
      // regression proof for that fix; the full salon-booking journey from
      // here is exercised end to end by `salon_booking_flow_test.dart`.
      // Mirrors the existing coverage of the equivalent master-profile CTA in
      // public_master_profile_flow_test.dart:151-158.
      final Finder bookCta = find.byKey(const Key('salon-book-cta'));
      expect(bookCta, findsOneWidget);
      await tester.tap(bookCta);
      // fixed-wait-ok: settles the real async route-push step after the tap.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      AppHarness.expectLocation(router, RouteNames.salonBookingServices);
      expect(
        find.byType(SalonServiceSelectionScreen),
        findsOneWidget,
        reason:
            'the booking CTA must land on the salon service-selection step, '
            'never the independent-master flow (the old route misused '
            'salon.id as a masterId and crashed the backend with '
            'NotFoundException: Master not found)',
      );
      expect(tester.takeException(), isNull);
      router.pop();
      // fixed-wait-ok: settles the real async route-pop (back navigation) step.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, '/salons/salon-xyz');

      // ── CLIENT never touched a master-only or salon-owner-only endpoint ────
      expect(fb.getMasterCalls, 0);
    });
  }, timeout: const Timeout(Duration(seconds: 90)));

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
      // fixed-wait-ok: settles the real async login/route-transition step.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.masterProfile);

      unawaited(router.push(RouteNames.salonPublicProfile('salon-xyz')));
      // fixed-wait-ok: settles the real async route-push step (programmatic push).
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // clientOnlyGuard → roleHomePath(independentMaster) → /master/profile.
      AppHarness.expectLocation(router, RouteNames.masterProfile);
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

  // ──────────────────────────────────────────────────────────────────────────
  // Phase 223 (b) / 224 — locationNote address-eviction regression pin +
  // sanitize, and the hero card's fixed-overlap growth-goes-downward
  // contract.
  //
  // WHY THESE TESTS NAVIGATE VIA A DIRECT `router.push` (not through the real
  // search-results screen the main journey test above uses)
  // -------------------------------------------------------------------------
  // The two tests below deliberately reuse the CLIENT-only route guard test's
  // navigation shape (`router.push(RouteNames.salonPublicProfile(...))`
  // straight after login) instead of the main journey test's
  // search-screen-first path. Both reach the exact same destination
  // (`PublicSalonProfileScreen` backed by a real `GET /salons/salon-xyz`), so
  // nothing about THIS regression's coverage is weaker for skipping the
  // search leg — that leg is already proven once by the main journey test.
  //
  // Step 2.7 Rule 3b — this is a real user journey (salon profile screen +
  // locationNote wiring), so E2E coverage is mandatory; it just does not need
  // to be re-derived through search every time.
  // ──────────────────────────────────────────────────────────────────────────

  /// A ~1000-char note (the backend's `@Size(max = 1000)` ceiling) — long
  /// enough that, under the OLD pre-Phase-223(b) hero layout (locationNote
  /// appended onto the SAME `maxLines: 2` line as the street address), it
  /// would have evicted the address text off the hero card entirely. Since
  /// Phase 224 it also doubles as the case that would have pushed the hero
  /// card's top edge over the back/favourite buttons under the OLD
  /// content-driven overlap formula (see `_CoverAndHero`'s class doc) — the
  /// EXPANDED note adds several hundred px of card height. Built by
  /// repeating a realistic entrance-instructions sentence and trimming to
  /// exactly 1000 chars.
  String buildRegressionNote() {
    const String sentence =
        "Вхід у двір з боку вулиці Хрещатик, повз кав'ярню на розі, минаєте "
        'дитячий майданчик, підіймаєтесь трьома сходинками до скляних дверей. ';
    final StringBuffer buffer = StringBuffer();
    while (buffer.length < 1000) {
      buffer.write(sentence);
    }
    return buffer.toString().substring(0, 1000);
  }

  testWidgets(
    'Phase 223 (b) / 224 regression pin: a 1000-char locationNote never '
    'evicts the hero address, and renders — collapsed, then expanded — as '
    'its own ExpandableNote on the hero card, through a REAL GET '
    '/salons/{id} response',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final String longNote = buildRegressionNote();
        final fb = FakeBackend()
          ..currentRole = UserRole.client
          ..salonLocationNote = longNote;
        final GoRouter router = await AppHarness.boot(tester, fb);

        await AppHarness.loginAs(tester, fb, UserRole.client);
        // fixed-wait-ok: settles the real async login/route-transition step.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        unawaited(router.push(RouteNames.salonPublicProfile('salon-xyz')));
        // fixed-wait-ok: settles the real async route-push step.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        AppHarness.expectLocation(router, '/salons/salon-xyz');
        expect(find.byType(PublicSalonProfileScreen), findsOneWidget);

        // ── The regression itself: the hero address must survive ────────────
        // Pre-Phase-223(b), this SAME 1000-char note appended onto the SAME
        // clamped hero line pushed the street address clean off the visible
        // `maxLines: 2` budget — losing the address, not just the note.
        final Finder addressFinder = find.byKey(
          const Key('salon-profile-address-text'),
        );
        expect(
          addressFinder,
          findsOneWidget,
          reason:
              'the street address must survive on the hero card no matter '
              'how long the locationNote is — the note renders as its OWN '
              'ExpandableNote below the address lines, never concatenated '
              "onto them, so it can no longer compete for the address's "
              'fixed line budget',
        );
        final Text addressText = tester.widget<Text>(addressFinder);
        expect(addressText.data, 'вул. Хрещатик, 12');

        // ── The note itself lives on the hero card, clamped with a toggle ───
        final Finder heroCard = find.byKey(
          const Key('salon-profile-hero-card'),
        );
        expect(
          find.descendant(
            of: heroCard,
            matching: find.byKey(const Key('salon-profile-location-note')),
          ),
          findsOneWidget,
          reason: 'a non-empty locationNote must render on the hero card',
        );
        final Finder toggle = find.byKey(const Key('expandable-note-toggle'));
        await tester.ensureVisible(toggle);
        expect(
          toggle,
          findsOneWidget,
          reason:
              'a 1000-char note must overflow the 3-line clamp and show the '
              'expand affordance',
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(PublicSalonProfileScreen)),
        );
        expect(find.text(l10n.expandableNoteShowMore), findsOneWidget);

        // ── Back button is never obscured by the hero card, BOTH collapsed
        // and expanded (Phase 224's hard layout constraint) ────────────────
        //
        // The pre-224 bug: the hero card was `Positioned(bottom: 0)` inside
        // a Stack sized to a FIXED `coverHeight + heroProtrusion`, painted
        // AFTER (i.e. visually on top of) the back/favourite buttons. A
        // card taller than the `heroProtrusion` budget pushed its own top
        // edge higher — past the buttons' fixed `Positioned(top: ...)`
        // coordinates — and, being painted last, silently painted OVER
        // them; Stack also hit-tests children in reverse paint order, so
        // the card (not the button) would have caught the tap too. The
        // invariant to pin is therefore "the button's Rect and the card's
        // Rect never overlap", not "the button hasn't moved" (Phase 224's
        // fix makes the button's OWN position fixed by construction — see
        // `_CoverAndHero` — so a bare position check would hold trivially
        // even under a partial regression that reintroduced overlap without
        // moving the button itself, e.g. a card painted on top without
        // affecting layout order elsewhere). Mirrors the widget tier's
        // "cover edit pill layout" / "hero card overlap band hit-testing"
        // groups, which pin the identical invariant for the edit pill and
        // via a real hit-test respectively.
        final Finder backButton = find.byKey(const Key('salon-profile-back'));
        expect(backButton, findsOneWidget);
        expect(
          tester.getRect(backButton).overlaps(tester.getRect(heroCard)),
          isFalse,
          reason:
              'the back button must not be overlapped by the hero card '
              'while the note is collapsed',
        );

        final Size collapsedSize = tester.getSize(find.text(longNote));
        await tester.tap(toggle);
        await tester.pumpAndSettle();

        expect(find.text(l10n.expandableNoteShowLess), findsOneWidget);
        final Size expandedSize = tester.getSize(find.text(longNote));
        expect(
          expandedSize.height,
          greaterThan(collapsedSize.height),
          reason: 'tapping the toggle must reveal the FULL 1000-char note',
        );

        // Expanding the note grows the card by several hundred px — the
        // back button must still not be overlapped by it.
        expect(backButton, findsOneWidget);
        expect(
          tester.getRect(backButton).overlaps(tester.getRect(heroCard)),
          isFalse,
          reason:
              'expanding a 1000-char locationNote must not grow the hero '
              'card into the back button — the cover (and everything '
              "positioned on it) is laid out independently of the card's "
              'content height',
        );
      });
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'a locationNote containing an RLO (U+202E) override renders SANITIZED '
    'on the hero card through a REAL GET /salons/{id} response',
    (tester) async {
      await mockNetworkImagesFor(() async {
        // U+202E = Right-to-Left Override. Backend validation on
        // `locationNote` is `@Size(max = 1000)` only — no character-class
        // check — so a hostile salon owner could push this into a
        // client-facing note. Built via `String.fromCharCode` (never a
        // literal control byte in this source file).
        final String rlo = String.fromCharCode(0x202E);
        final String rawNote = 'кв. 3$rlo, 2 поверх';
        const String sanitizedNote = 'кв. 3, 2 поверх';

        final fb = FakeBackend()
          ..currentRole = UserRole.client
          ..salonLocationNote = rawNote;
        final GoRouter router = await AppHarness.boot(tester, fb);

        await AppHarness.loginAs(tester, fb, UserRole.client);
        // fixed-wait-ok: settles the real async login/route-transition step.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        unawaited(router.push(RouteNames.salonPublicProfile('salon-xyz')));
        // fixed-wait-ok: settles the real async route-push step.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        expect(find.byType(PublicSalonProfileScreen), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('salon-profile-hero-card')),
            matching: find.byKey(const Key('salon-profile-location-note')),
          ),
          findsOneWidget,
        );
        expect(
          find.text(sanitizedNote),
          findsOneWidget,
          reason:
              'the rendered note must carry the SANITIZED string, proven '
              'through a REAL wire round trip (SalonMapper.fromDto → Salon '
              '→ ExpandableNote), not just a widget-tier fixture',
        );
        expect(
          find.text(rawNote),
          findsNothing,
          reason: 'the raw control character must never reach a real render',
        );
      });
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
