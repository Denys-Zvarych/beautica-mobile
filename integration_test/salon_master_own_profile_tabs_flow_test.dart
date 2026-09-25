// Phase 351 — E2E: the SALON_MASTER's own profile cards → tabs (D15).
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// Sibling of `master_own_profile_reviews_tab_flow_test.dart` (the
// INDEPENDENT_MASTER's equivalent journey), for the SALON_MASTER's own
// profile: `SalonMasterProfileScreen` now renders 3 stat cards (rating /
// reviews / services — no «Досвід», D9) that SWITCH the screen's own tab in
// place instead of pushing a route. The dense widget-tier coverage
// (`salon_master_profile_screen_test.dart`) proves this against a stubbed
// provider; this flow drives the REAL post-login landing dispatch
// (`roleHomePath` → `/staff/profile`), the REAL `salonMasterOwnProfileProvider`
// fan-out (`GET /masters/me` + the salon-scoped services read + the salon
// read) and a REAL tap on the REAL rendered cards, against a real (fake) HTTP
// backend.
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
    'tapping the rating/reviews cards switches to the «Відгуки» tab in '
    'place, and tapping the services card switches to the «Послуги» tab',
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

        // ── Tap the REAL rendered rating card → switches to «Відгуки», no
        //    navigation (D15). ───────────────────────────────────────────
        final Finder ratingTile = find.byKey(
          const Key('salon-master-profile-rating-tile'),
        );
        expect(ratingTile, findsOneWidget);
        await AppHarness.tapVisible(tester, ratingTile);
        await AppHarness.settle(tester);

        expect(find.byType(MasterReviewsBody), findsOneWidget);
        expect(find.byType(SalonMasterProfileScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.salonMasterProfile);

        // The seeded reviews render — proves the REAL provider fan-out
        // (GET /masters/master-removable/reviews[/summary]) resolved, not a
        // stub.
        expect(find.byKey(const Key('master-review-mr-1')), findsOneWidget);

        // ── Tap the REAL rendered reviews card → same tab, still no nav ──
        final Finder reviewsTile = find.byKey(
          const Key('salon-master-profile-reviews-tile'),
        );
        expect(reviewsTile, findsOneWidget);
        await AppHarness.tapVisible(tester, reviewsTile);
        await AppHarness.settle(tester);
        expect(find.byType(MasterReviewsBody), findsOneWidget);

        // ── Tap the REAL rendered services card → switches to «Послуги» ──
        final Finder servicesTile = find.byKey(
          const Key('salon-master-profile-services-tile'),
        );
        expect(servicesTile, findsOneWidget);
        await AppHarness.tapVisible(tester, servicesTile);
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
}
