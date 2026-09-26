// Phase 351 gave the SALON_MASTER's own profile a tab bar (D15); user
// decision 2026-09-26 made the stat cards display-only. E2E: the
// SALON_MASTER's own profile cards do nothing, and the tab bar is the only
// way to switch.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// Sibling of `master_own_profile_reviews_tab_flow_test.dart` (the
// INDEPENDENT_MASTER's equivalent journey), for the SALON_MASTER's own
// profile: `SalonMasterProfileScreen` renders 3 stat cards (rating / reviews
// / services — no «Досвід», D9) that are display-only (user decision
// 2026-09-26) — only the «Про майстра» / «Послуги» / «Відгуки» tab bar
// switches the screen's own tab. The dense widget-tier coverage
// (`salon_master_profile_screen_test.dart`) proves this against a stubbed
// provider; this flow drives the REAL post-login landing dispatch
// (`roleHomePath` → `/staff/profile`), the REAL `salonMasterOwnProfileProvider`
// fan-out (`GET /masters/me` + the salon-scoped services read + the salon
// read) and a REAL tap on the REAL rendered cards AND tab bar, against a
// real (fake) HTTP backend.
//
// FIXTURE REUSE (REUSE-FIRST): reuses the exact `salon-xyz` /
// `master-removable` fixture `salon_master_services_read_only_flow_test.dart`
// already wires (`FakeBackend(masterRowId: 'master-removable', masterSalonId:
// 'salon-xyz')`) — no new backend fixture added. The «Відгуки» tab's content
// comes from the SAME `mr-1`/`mr-2`/`mr-3` fixture
// `master_own_profile_reviews_tab_flow_test.dart` already exercises — that
// review fixture is keyed on `masterRowId` generically, not hardcoded to the
// INDEPENDENT_MASTER's default id.
//
// NO PATROL FLOW: a pure screen / route / provider / GET journey — Step 2.7
// Rule 3b's `integration_test/patrol/` requirement does not apply.
//
// FINDERS: widget Keys and widget TYPES only — never a Cyrillic UI string
// (`forbid_cyrillic_finder.sh`).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/presentation/salon_master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/master_reviews_body.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/service_category_cards.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The salon whose roster carries the driven SALON_MASTER's own row —
/// reused from `_wireSalonMasterServices`'s fixed fixture.
const String _kSalonId = 'salon-xyz';

/// The `masters` ROW id `GET /masters/me` must report for this flow's
/// SALON_MASTER session, paired with [_kSalonId] via `masterSalonId` —
/// deliberately the SAME id the sibling «Послуги» flow already wires
/// (REUSE-FIRST, no new backend fixture).
const String _kMasterRowId = 'master-removable';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'SALON_MASTER lands on /staff/profile with 3 stat cards (no «Досвід»); '
    'tapping the rating/reviews/services cards does nothing, and the tab bar '
    '(tapped directly) switches to «Відгуки» / «Послуги»',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend(
          masterRowId: _kMasterRowId,
          masterSalonId: _kSalonId,
        );
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.salonMaster);
        await AppHarness.settle(tester);

        // ── Landing ──────────────────────────────────────────────────────
        expect(find.byType(SalonMasterProfileScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.salonMasterProfile);

        // ── D9 — no «Досвід» card anywhere on the screen ────────────────
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(SalonMasterProfileScreen)),
        );
        expect(find.text(l10n.publicMasterExperienceLabel), findsNothing);

        // Default tab is «Про майстра» — neither tab's body is mounted yet.
        expect(find.byType(MasterReviewsBody), findsNothing);
        expect(find.byType(ServiceCategoryCardList), findsNothing);

        // ── The stat cards are DISPLAY-ONLY (user decision 2026-09-26) —
        //    tapping the REAL rendered rating/reviews/services cards must do
        //    nothing. ────────────────────────────────────────────────────
        final Finder ratingTile = find.byKey(
          const Key('salon-master-profile-rating-tile'),
        );
        expect(ratingTile, findsOneWidget);
        await tester.ensureVisible(ratingTile);
        await tester.tap(ratingTile, warnIfMissed: false);
        await AppHarness.settle(tester);
        expect(find.byType(MasterReviewsBody), findsNothing);

        final Finder reviewsTile = find.byKey(
          const Key('salon-master-profile-reviews-tile'),
        );
        expect(reviewsTile, findsOneWidget);
        await tester.ensureVisible(reviewsTile);
        await tester.tap(reviewsTile, warnIfMissed: false);
        await AppHarness.settle(tester);
        expect(find.byType(MasterReviewsBody), findsNothing);

        final Finder servicesTile = find.byKey(
          const Key('salon-master-profile-services-tile'),
        );
        expect(servicesTile, findsOneWidget);
        await tester.ensureVisible(servicesTile);
        await tester.tap(servicesTile, warnIfMissed: false);
        await AppHarness.settle(tester);
        expect(find.byType(MasterReviewsBody), findsNothing);
        expect(find.byType(ServiceCategoryCardList), findsNothing);
        expect(find.byType(SalonMasterProfileScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.salonMasterProfile);

        // ── Tap the «Відгуки» TAB directly — the only way to switch. ─────
        final Finder reviewsTab = find.byKey(
          const Key('salon-master-profile-tab-2'),
        );
        await AppHarness.tapVisible(tester, reviewsTab);
        await AppHarness.settle(tester);

        expect(find.byType(MasterReviewsBody), findsOneWidget);
        expect(find.byType(SalonMasterProfileScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.salonMasterProfile);

        // The seeded reviews render — proves the REAL provider fan-out
        // (GET /masters/master-removable/reviews[/summary]) resolved, not a
        // stub.
        expect(find.byKey(const Key('master-review-mr-1')), findsOneWidget);

        // ── Tap the «Послуги» TAB directly. ───────────────────────────────
        final Finder servicesTab = find.byKey(
          const Key('salon-master-profile-tab-1'),
        );
        await AppHarness.tapVisible(tester, servicesTab);
        await AppHarness.settle(tester);

        expect(find.byType(MasterReviewsBody), findsNothing);
        expect(
          find.byKey(const Key('salon-master-profile-service-categories')),
          findsOneWidget,
          reason:
              'the REAL salon-scoped services read (GET /salons/$_kSalonId/'
              'masters/$_kMasterRowId/services) must have resolved a '
              'non-empty catalogue for the category section to render',
        );
        expect(find.byType(SalonMasterProfileScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.salonMasterProfile);
      });
    },
  );

  testWidgets(
    'SALON_MASTER with no assigned services sees the "ask the owner/admin" '
    'hint on «Послуги», not the category list',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend(
          masterRowId: _kMasterRowId,
          masterSalonId: _kSalonId,
        )..salonMasterOwnServicesEmpty = true;
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.salonMaster);
        await AppHarness.settle(tester);

        expect(find.byType(SalonMasterProfileScreen), findsOneWidget);

        final Finder servicesTab = find.byKey(
          const Key('salon-master-profile-tab-1'),
        );
        await AppHarness.tapVisible(tester, servicesTab);
        await AppHarness.settle(tester);

        expect(
          find.byKey(const Key('salon-master-profile-service-categories')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('salon-master-profile-services-empty')),
          findsOneWidget,
          reason:
              'the REAL salon-scoped services read (GET /salons/$_kSalonId/'
              'masters/$_kMasterRowId/services) resolved an EMPTY catalogue, '
              'so the "ask the owner/admin" empty state must render',
        );
        expect(find.byType(SalonMasterProfileScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.salonMasterProfile);
      });
    },
  );
}
