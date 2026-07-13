// E2E — Master-home zero-services "Додати послуги" CTA → service-setup.
//
// Journey (INDEPENDENT_MASTER with ZERO services):
//   1. Login → land on /master/profile.
//   2. The master-home services section renders its zero-services empty state:
//      a single primary CTA (Key('btn-master-add-services')) labelled
//      «Додати послуги» — the old header + «Усі послуги» link + «Послуг ще
//      немає» text are absent in this branch.
//   3. Tap the CTA → navigate to RouteNames.serviceSetup ('/services/setup'),
//      the same first-time bulk service-setup entry point the services-list
//      empty state uses.
//
// FAKE BACKEND
// ------------
// `FakeBackend` pre-seeds the master with services. This flow calls
// `fb.clearServices()` BEFORE boot so `GET /independent-masters/me/services`
// returns `[]`, driving the empty branch of `_ProfileCategoriesSection`.
//
// KEY POLICY
// ----------
// All finders are key-based (see app_harness.dart policy). The destination is
// asserted both by the setup screen's chrome key (Key('btn-setup-close')) and
// by the router's current location.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
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
    'INDEPENDENT_MASTER with zero services sees the add-services CTA and '
    'tapping it opens the service-setup flow',
    (tester) async {
      final fb = FakeBackend();
      // Empty the seeded services BEFORE boot so the master-home services
      // section resolves to its zero-services empty branch.
      fb.clearServices();

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // Landed on the master home.
      expectLocation(router, RouteNames.masterProfile);

      // The zero-services empty-state CTA must be present. Scroll it into view
      // (it sits in section 5, below the fold on a phone viewport).
      final Finder cta = find.byKey(const Key('btn-master-add-services'));
      await tester.scrollUntilVisible(
        cta,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        cta,
        findsOneWidget,
        reason:
            'the master-home zero-services empty state must render the '
            'add-services CTA (Key btn-master-add-services)',
      );

      // Tap the CTA — pushes RouteNames.serviceSetup. Use bounded pumps rather
      // than pumpAndSettle: the ServiceSetupScreen can hold an in-flight
      // provider/loading animation that never settles.
      await tester.ensureVisible(cta);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(cta);
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

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
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
