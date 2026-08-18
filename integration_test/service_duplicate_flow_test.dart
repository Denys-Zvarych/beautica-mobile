// E2E — a bulk-save 409 DUPLICATE_SERVICE surfaces as the localized duplicate
// copy, never the generic errServer, and leaves the master ON the setup screen
// with their selection intact (Step 2.7 Rule 3b end-to-end coverage for the
// DUPLICATE_SERVICE catalogue fix).
//
// THE BUG THIS GUARDS
// -------------------
// Adding a service that is already in the master's menu returns a backend 409
// with the typed `{ data: { code: "DUPLICATE_SERVICE", … } }` envelope. Before
// the fix that fell through to the generic `errServer` "server error, try again"
// message — the master could only re-tap Save and re-hit the same 409 forever.
// After the fix the repository decodes the envelope into [ServiceDuplicateFailure]
// and the screen shows the localized `serviceErrDuplicate` copy while KEEPING
// the master where they are, so they can deselect the offender and re-save.
//
// WHY THE SETUP SCREEN (not a single-create form)
// -----------------------------------------------
// `/services/create` and its form are DELETED. `/services/setup` is now the ONE
// "add services" surface — reached from both the services-list empty state and
// the «Додати послугу» FAB — and it writes through
// `POST /independent-masters/me/services/bulk`, which `beautica-backend`
// c5e420f made ADDITIVE. That makes this the flow where a real master actually
// meets DUPLICATE_SERVICE: the APPEND path. The bulk endpoint is
// all-or-nothing, so ONE clashing item rolls the WHOLE batch back and nothing
// is written — which is exactly why the screen must not throw the selection
// away.
//
// Journey (INDEPENDENT_MASTER):
//   1. Login → /master/profile.
//   2. Navigate to /services/setup.
//   3. Tap the NAILS category chip → its service-type rows load inline.
//   4. Toggle ON one service type, then fill its duration + FIXED price so the
//      client-side assemble passes and the payload reaches the network.
//   5. Arm the fake backend to reject the BULK POST with the 409
//      DUPLICATE_SERVICE envelope.
//   6. Tap Save → the bulk POST fires → the localized duplicate copy renders in
//      a VelvetSnack; the generic errServer copy is NOT shown; the route stays
//      on /services/setup (no pop / no forced navigation away).
//
// VELVETSNACK, NOT AN INLINE ROW ERROR
// -------------------------------------
// This flow used to assert an inline `error-service-type` row AND
// `find.byType(SnackBar) == findsNothing`, because the deleted single-create
// form had a service-type field to flag. The setup screen has no such field —
// the duplicate is a WHOLE-BATCH verdict, not a per-row one (the backend does
// not even name the offender: `serviceName` is null on the bulk envelope). So
// `_ServiceSetupScreenState._save` routes `ServiceDuplicateFailure` to
// `_showErrorSnack(error.userMessage(context))` and RETURNS — no pop, no
// `_leave()`. The old "no snackbar" assertion therefore inverts here: a
// VelvetSnack carrying the duplicate copy is the CORRECT surface, and its
// absence is the regression.
//
// WHAT THIS COVERS (and what it does NOT)
// ---------------------------------------
// This exercises the real repository + HTTP path: in the harness `dioProvider`
// is the FakeBackend's Dio, so `HttpServiceRepository.bulkCreate` issues a real
// request, gets the fake 409 back as a `DioException`, and its
// `_mapBulkCreateException` decodes the typed envelope off the RAW response
// body — end-to-end through the screen and notifier, not a unit mock.
//
// It does NOT cover the interceptor chain. FakeBackend's Dio installs no
// interceptors at all (only a `DioAdapter` — see fake_backend.dart), so the
// production `ErrorMapperInterceptor` never runs here and no generic
// `ServerFailure(409)` is ever attached to the exception. The precedence
// property — that the typed duplicate decode wins over the interceptor's
// generic fallthrough, which holds because `_isDuplicateService` inspects the
// raw body BEFORE the `e.error is Failure` check — is covered only by the
// repository unit tests, not by this flow.
//
// It also does NOT cover the already-owned exclusion (rows for types the master
// already offers render inert, with no toggle). That guard is what makes this
// 409 rare in practice; it is asserted in the widget tests. This flow
// deliberately picks a NON-owned type (`type-nails-gel`) so the exclusion is
// out of the picture and the error mapping is the only thing under test.
//
// KEY POLICY
// ----------
// All navigation/interaction finders are key-based (app_harness.dart policy).
// Content assertions read the localized copy off a live context (locale-
// invariant), never a hardcoded Cyrillic literal (i18n-finder gate compliant).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'a bulk-save 409 DUPLICATE_SERVICE shows the localized duplicate copy in a '
    'snackbar, keeps the master on the setup screen, and never shows errServer',
    (tester) async {
      // The service type this flow configures. Deliberately NOT
      // `type-nails-classic`: the fake backend seeds that one into the master's
      // existing catalogue, so its row renders inert (no toggle at all, sub-
      // label «Вже додано») — which would make the toggle tap below fail for a
      // reason that has nothing to do with the 409 mapping under test.
      //
      // Not a hedge: `servicesListProvider` has ALWAYS resolved by the time the
      // setup screen's initState reads it, because the services list is the
      // entry point this flow navigates FROM, and it awaits its own data before
      // rendering the FAB that opens this screen. Measured, not assumed. The
      // earlier "whenever … has already resolved" wording invited a future
      // author to weaken the exclusion assertion on the theory that the
      // exclusion might not have applied — it always does.
      const String typeId = 'type-nails-gel';

      final fb = FakeBackend();
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // Navigate straight to the setup screen (skips the /services list, whose
      // loading skeleton runs an infinite shimmer that stalls pumpAndSettle).
      AppHarness.expectLocation(router, RouteNames.masterProfile);
      router.go(RouteNames.serviceSetup);

      // ── Expand the NAILS category ────────────────────────────────────────
      // The category Wrap only mounts once `approvedCategoriesProvider`
      // resolves; until then the body is a CircularProgressIndicator whose
      // repeating animation would hang pumpAndSettle. pump-until (not a fixed
      // wait) throughout this file for that reason.
      final Finder nailsChip = find.byKey(const ValueKey<String>('cat_NAILS'));
      await tester.pumpUntilFound(nailsChip.hitTestable());
      AppHarness.expectLocation(router, RouteNames.serviceSetup);
      await tester.tap(nailsChip);

      // Tapping the chip kicks off the per-category service-type fetch, which
      // renders its own spinner until the rows arrive. Wait for the ROW, not a
      // pump count.
      final Finder row = find.byKey(const Key('setup_row_$typeId'));
      await tester.pumpUntilFound(row);

      // ── Toggle the row ON ────────────────────────────────────────────────
      // `.hitTestable()` — NOT bare existence. The row list is emitted by a
      // lazy SliverList and each card animates (AnimatedContainer, 220 ms), so
      // a bare `pumpUntilFound` can return while the toggle is still not a
      // valid hit target. Tapping then either aims outside the render tree —
      // which `hitTestWarningShouldBeFatal` (armed in AppHarness.boot) turns
      // into a hard failure — or is silently swallowed, which would show up
      // much later as "the duplicate copy never rendered" and read as a bug in
      // the code under test. Waiting for hit-testability waits out the
      // animation by OBSERVING it rather than guessing a pump count.
      final Finder toggle = find.byKey(const Key('setup_row_toggle_$typeId'));
      await tester.ensureVisible(toggle);
      await tester.pumpUntilFound(toggle.hitTestable());
      await tester.tap(toggle);

      // ── Fill duration + FIXED price ──────────────────────────────────────
      // Both entries are SCOPED to this row's card: every included row renders
      // the same `service-setup-duration` / `pricing-fixed-amount` keys, so an
      // unscoped finder would be ambiguous the moment a second row is included.
      //
      // The fields live inside the card's AnimatedSize + AnimatedSwitcher, which
      // cross-fade in over ~240 ms once the row is included — so wait for them
      // to actually exist before typing.
      final Finder durationField = find.descendant(
        of: row,
        matching: find.byKey(const Key('service-setup-duration')),
      );
      final Finder priceField = find.descendant(
        of: row,
        matching: find.byKey(const Key('pricing-fixed-amount')),
      );
      await tester.pumpUntilFound(durationField);
      await tester.pumpUntilFound(priceField);
      await tester.enterText(durationField, '60');
      await tester.pump();
      await tester.enterText(priceField, '400');
      await tester.pump();

      // Arm the backend to reject the BULK POST with the 409 DUPLICATE_SERVICE
      // envelope. This is a re-wiring setter — see FakeBackend.bulkRejectDuplicate
      // for why a plain bool field would silently leave the status at 200.
      fb.bulkRejectDuplicate = true;

      // ── Save → bulk POST → 409 → duplicate snackbar (no pop) ─────────────
      final Finder saveBtn = find.byKey(const Key('btn-setup-save'));
      await tester.pumpUntilFound(saveBtn.hitTestable());

      // Read localized copy off a live context (locale-invariant) before the tap
      // rebuilds the tree.
      final l10n = AppLocalizations.of(tester.element(saveBtn));

      await tester.tap(saveBtn);

      // DIAGNOSE AT THE CAUSE — assert the POST fired BEFORE waiting for the
      // duplicate copy. Everything upstream of the network (a swallowed toggle
      // tap, an unfilled duration/price flagging the row, the CTA still
      // disabled at total == 0) shows up identically at the copy finder: "the
      // duplicate error never rendered", which reads as a bug in the ERROR-
      // MAPPING code under test when it is really a bug in the JOURNEY.
      // Checking the counter first splits those two failure modes apart.
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.bulkCreateCalls >= 1,
        description:
            'the bulk POST to reach the fake backend — if it never does, the '
            'save was blocked CLIENT-SIDE (most likely the row was never '
            'actually included because the toggle tap was swallowed, or its '
            'duration/price failed _assemble and flagged the row instead), so '
            'the 409 mapping under test was never exercised at all',
      );

      // The duplicate copy renders in a VelvetSnack — the setup screen has no
      // service-type field to flag inline, and the bulk envelope names no
      // offending service, so the whole-batch verdict is surfaced as a
      // transient message. See the header note on why this INVERTS the old
      // `findsNothing` snackbar assertion.
      //
      // Unscoped by construction: VelvetSnack lives on the app's ROOT
      // `Overlay`, a SIBLING of the routed screen subtree, never a descendant
      // of it — see `test/helpers/velvet_snack_matchers.dart`'s file header.
      final Finder duplicateSnackText = find.text(l10n.serviceErrDuplicate);
      await tester.pumpUntilFound(duplicateSnackText);
      expectVelvetSnack(
        l10n.serviceErrDuplicate,
        variant: VelvetSnackVariant.error,
      );

      // The screen did NOT pop and did NOT navigate away — the master stays on
      // the setup screen with their whole selection intact so they can deselect
      // the offender and re-save (the anti-"stuck re-hitting the same 409"
      // guarantee, and the anti-"lose everything I just configured" one).
      AppHarness.expectLocation(router, RouteNames.serviceSetup);
      expect(
        find.byKey(const Key('setup_row_$typeId')),
        findsOneWidget,
        reason:
            'the configured row must still be on screen — a duplicate 409 rolls '
            'the whole batch back, so discarding the selection would destroy '
            'work the master can still salvage',
      );

      // The generic errServer copy must NOT fire — the whole point of the fix.
      expect(
        find.text(l10n.errServer),
        findsNothing,
        reason: 'the generic "server error, try again" copy must never show',
      );

      // Drain the dwell Timer so none is pending at teardown (mirrors
      // `master_bookings_flow_test.dart`'s identical drain).
      await pumpPastVelvetSnack(tester);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
