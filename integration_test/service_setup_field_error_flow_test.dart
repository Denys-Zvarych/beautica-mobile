// E2E — first-time service-setup: a per-field 400 lands INLINE on the offending
// row, never as the generic snackbar (Step 2.7 Rule 3b end-to-end coverage for
// the per-field validation-error display fix).
//
// Journey (INDEPENDENT_MASTER with ZERO services):
//   1. Login → land on /master/profile.
//   2. Tap the zero-services «Додати послуги» CTA → /services/setup.
//   3. Expand the NAILS category → its service-type rows load.
//   4. Include the first row, give it a VALID duration (60) + price (500) so the
//      client-side guards pass and the payload actually reaches the network.
//   5. Arm the fake backend to reject the bulk POST with the backend's per-field
//      envelope (`errors: {"items[0].durationMinutes": …}`).
//   6. Tap Save → the 400 is mapped back onto the row: the localized
//      `serviceSetupDurationMax` message renders INLINE on that row, and the
//      generic `errValidation` snackbar is NOT shown.
//
// FAKE BACKEND
// ------------
// `FakeBackend.bulkRejectDurationField` flips the
// `POST /independent-masters/me/services/bulk` route to a 400 per-field reply
// (default is a clean 201). This exercises the SERVER-mapping path — the
// client-side `> 480` guard is deliberately NOT tripped (duration is 60), so the
// only way the row can be flagged is the backend field-error round-trip.
//
// KEY POLICY
// ----------
// All navigation/interaction finders are key-based (app_harness.dart policy).
// Content assertions use the localized copy read from a live context (locale-
// invariant), NOT hardcoded strings.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
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

  // Bounded pumps — the ServiceSetupScreen can hold an in-flight provider /
  // loading animation that never settles, so pumpAndSettle would hang.
  Future<void> pumpFor(WidgetTester tester, {int frames = 12}) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Taps a setup row's include switch — the GestureDetector nested in the row's
  /// `Semantics(toggled: …)` (the only toggled Semantics in the card).
  Future<void> tapIncludeSwitch(WidgetTester tester, String typeId) async {
    final toggled = find.descendant(
      of: find.byKey(Key('setup_row_$typeId')),
      matching: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.toggled != null,
      ),
    );
    final switchFinder = find
        .descendant(of: toggled, matching: find.byType(GestureDetector))
        .last;
    await tester.tap(switchFinder);
    await pumpFor(tester);
  }

  testWidgets(
    'a bulk-save per-field 400 shows the duration error INLINE on the row and '
    'suppresses the generic validation snackbar',
    (tester) async {
      final fb = FakeBackend();
      // Zero services so the master-home empty state renders the add-services CTA.
      fb.clearServices();

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        startsWith(RouteNames.masterProfile),
      );

      // Open the service-setup flow via the zero-services CTA.
      final Finder cta = find.byKey(const Key('btn-master-add-services'));
      await tester.scrollUntilVisible(
        cta,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(cta);
      await tester.tap(cta);
      await pumpFor(tester, frames: 20);

      // On the setup screen.
      expect(find.byKey(const Key('btn-setup-close')), findsOneWidget);

      // Expand the NAILS category → its service-type rows load.
      await tester.tap(find.byKey(const ValueKey<String>('cat_NAILS')));
      await pumpFor(tester, frames: 16);

      const rowId = 'type-nails-classic';
      expect(find.byKey(const Key('setup_row_$rowId')), findsOneWidget);

      // Include the row + fill a VALID duration (60) and price (500) so the
      // client guards pass and the payload reaches the network.
      await tapIncludeSwitch(tester, rowId);
      await tester.enterText(
        find
            .descendant(
              of: find.byKey(const Key('setup_row_$rowId')),
              matching: find.byType(TextField),
            )
            .first,
        '60',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('setup_row_$rowId')),
          matching: find.byKey(const Key('pricing-fixed-amount')),
        ),
        '500',
      );
      await pumpFor(tester);

      // Arm the backend to reject items[0].durationMinutes with the per-field
      // envelope.
      fb.bulkRejectDurationField = true;
      fb.bulkRejectItemIndex = 0;

      // Save → bulk POST → 400 → inline row error.
      await tester.tap(find.byKey(const Key('btn-setup-save')));
      await pumpFor(tester, frames: 20);

      // The bulk save genuinely reached the network (not blocked client-side).
      expect(
        fb.bulkCreateCalls,
        1,
        reason: 'the valid payload must POST to the bulk endpoint',
      );

      // Read localized copy from a live context (locale-invariant).
      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('btn-setup-save'))),
      );

      // The backend duration error is rendered INLINE on the offending row.
      expect(
        find.descendant(
          of: find.byKey(const Key('setup_row_$rowId')),
          matching: find.text(l10n.serviceSetupDurationMax),
        ),
        findsOneWidget,
        reason:
            'the items[0].durationMinutes 400 must surface as the localized '
            'duration-max message inline on the row',
      );

      // The generic validation snackbar must NOT fire (the regressed behaviour).
      expect(
        find.text(l10n.errValidation),
        findsNothing,
        reason:
            'a per-field 400 that maps to a row must NOT fall through to the '
            'generic errValidation snackbar',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
