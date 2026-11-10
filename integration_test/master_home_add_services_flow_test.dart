// E2E — Master-home zero-services "Додати послуги" CTA → service-setup.
//
// Journey (INDEPENDENT_MASTER with ZERO services):
//   1. Login → land on /master/profile (opens on tab 0 «Про майстра»).
//   2. Select the «Послуги» tab (index 1, Key('master-profile-tab-1')) —
//      Phase 351 moved the services section (and its CTA) behind this tab;
//      it no longer renders on the default-open tab.
//   3. The master-home services section renders its zero-services empty state:
//      a single primary CTA (Key('btn-master-add-services')) labelled
//      «Додати послуги» — the old header + «Усі послуги» link + «Послуг ще
//      немає» text are absent in this branch.
//   4. Tap the CTA → navigate to RouteNames.serviceSetup ('/services/setup'),
//      the same first-time bulk service-setup entry point the services-list
//      empty state uses.
//
// FAKE BACKEND
// ------------
// `FakeBackend` pre-seeds the master with services. This flow calls
// `fb.clearServices()` BEFORE boot so `GET /independent-masters/me/services`
// returns `[]`, driving the empty branch of `_ProfileCategoriesSection`.
//
// PHASE 467 — BODY_MASSAGE category icon
// ---------------------------------------
// The fake catalog (`fb.approvedCategories`) also serves a `BODY_MASSAGE`
// category. On the setup screen its chip (Key cat_BODY_MASSAGE) and, once
// expanded, its group header (Key group_BODY_MASSAGE) must render the
// `category_body_massage.svg` asset — asserted by asset key, and explicitly
// NOT the cosmetology fallback an unmapped slug would resolve to.
//
// KEY POLICY
// ----------
// All finders are key-based (see app_harness.dart policy). The destination is
// asserted both by the setup screen's chrome key (Key('btn-setup-close')) and
// by the router's current location.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
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

  testWidgets(
    'INDEPENDENT_MASTER with zero services sees the add-services CTA and '
    'tapping it opens the service-setup flow',
    (tester) async {
      final fb = FakeBackend();
      // Empty the seeded services BEFORE boot so the master-home services
      // section resolves to its zero-services empty branch.
      fb.clearServices();
      // Phase 467 — a BODY_MASSAGE category in the live catalog.
      fb.approvedCategories.add(<String, dynamic>{
        'name': 'BODY_MASSAGE',
        'displayName': 'Масаж і догляд за тілом',
      });

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // Landed on the master home.
      AppHarness.expectLocation(router, RouteNames.masterProfile);

      // Phase 351 moved the add-services CTA behind the «Послуги» tab
      // (index 1) — the profile opens on tab 0 («Про майстра») by default,
      // so select the tab before looking for the CTA.
      final Finder servicesTab = find.byKey(const Key('master-profile-tab-1'));
      await tester.ensureVisible(servicesTab);
      await tester.tap(servicesTab);
      await tester.pumpAndSettle();

      // The zero-services empty-state CTA must be present. Scroll it into view
      // (it sits below the fold on a phone viewport).
      final Finder cta = find.byKey(const Key('btn-master-add-services'));
      await tester.scrollUntilVisible(
        cta,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpUntilFound(cta);
      expect(
        cta,
        findsOneWidget,
        reason:
            'the master-home zero-services empty state must render the '
            'add-services CTA (Key btn-master-add-services)',
      );

      // Tap the CTA — pushes RouteNames.serviceSetup. Pump UNTIL the setup
      // screen's chrome mounts rather than pumpAndSettle: the ServiceSetupScreen
      // can hold an in-flight provider/loading animation that never settles.
      // pumpUntilFound pumps in fixed steps (not to quiescence), so it waits
      // exactly until the destination appears without hanging on that animation.
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpUntilFound(find.byKey(const Key('btn-setup-close')));

      // Destination reached. NOTE: go_router's currentConfiguration.uri does
      // not update after an imperative context.push, so the destination is
      // proven by the ServiceSetupScreen chrome (Key('btn-setup-close')) — that
      // widget only mounts on the /services/setup route.
      expect(
        find.byKey(const Key('btn-setup-close')),
        findsOneWidget,
        reason:
            'tapping the CTA must open the ServiceSetupScreen '
            '(${RouteNames.serviceSetup})',
      );

      // Phase 467 — the BODY_MASSAGE chip resolves to its own icon.
      final Finder massageChip = find.byKey(
        const ValueKey<String>('cat_BODY_MASSAGE'),
      );
      await tester.pumpUntilFound(massageChip);
      _expectCategoryIcon(tester, massageChip, 'chip');

      // Expand it — the group header must carry the same icon.
      await tester.ensureVisible(massageChip);
      await tester.pump();
      await tester.tap(massageChip);
      final Finder massageHeader = find.byKey(
        const ValueKey<String>('group_BODY_MASSAGE'),
      );
      await tester.pumpUntilFound(massageHeader);
      _expectCategoryIcon(tester, massageHeader, 'group header');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

/// Asserts the single [AppIcon] under [owner] is the BODY_MASSAGE asset, not
/// the cosmetology fallback an unmapped slug resolves to.
void _expectCategoryIcon(WidgetTester tester, Finder owner, String what) {
  final AppIcon icon = tester.widget<AppIcon>(
    find.descendant(of: owner, matching: find.byType(AppIcon)),
  );
  expect(
    icon.asset,
    BeauticaAssetIcons.categoryBodyMassage,
    reason: 'the BODY_MASSAGE $what must render category_body_massage.svg',
  );
  expect(icon.asset, endsWith('category_body_massage.svg'));
  expect(icon.asset, isNot(BeauticaAssetIcons.categoryCosmetology));
}
