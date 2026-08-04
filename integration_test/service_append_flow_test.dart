// E2E — APPEND: a master who ALREADY has services adds more through the same
// setup screen, and the types they already offer are inert throughout.
//
// WHY THIS FLOW EXISTS (Step 2.7 Rule 3b)
// ---------------------------------------
// APPEND is the whole point of the change that deleted `ServiceCreateScreen`:
// `/services/setup` became the ONE "add services" surface for BOTH the
// empty-catalogue master and the master with a populated menu, unlocked by
// `beautica-backend` c5e420f making the bulk endpoint additive.
//
// Neither of the two sibling flows covers it. `service_crud_flow_test.dart` and
// `service_duplicate_flow_test.dart` both `router.go(RouteNames.serviceSetup)`
// directly and both deliberately pick `type-nails-gel` — the NON-owned type —
// precisely so the exclusion stays out of the picture. So before this file the
// append journey had widget-tier coverage only, and the FAB→setup entry point
// (the change's other half) had none at the E2E tier at all.
//
// Journey (INDEPENDENT_MASTER with a pre-seeded catalogue):
//   1. Login → /master/profile.
//   2. Go to /services — the populated services list.
//   3. Tap the «Додати послугу» FAB (Key('btn-create-service')) → it now opens
//      /services/setup, not the deleted /services/create.
//   4. The screen renders in APPEND framing (serviceSetupTitleAppend), proving
//      the initState snapshot of `servicesListProvider` was warm and non-empty.
//   5. Expand NAILS. The fake backend seeds the master with `assign-typed`
//      (serviceTypeId `type-nails-classic`), so that row must render INERT — no
//      include toggle — while its sibling `type-nails-gel` keeps its toggle.
//   6. Configure and save the sibling.
//   7. The bulk POST carries EXACTLY the sibling's id, never the owned one (one
//      such item would 409 the whole all-or-nothing batch), and the screen POPS
//      back to /services.
//
// WHY THE ENTRY POINT IS THE FAB, NOT router.go
// ---------------------------------------------
// Because the FAB re-route IS half of the change under test: it used to open
// the now-deleted `/services/create`. Nothing else at the E2E tier exercises
// it — the two sibling flows both `router.go` straight to `/services/setup`.
//
// It is NOT needed to warm `servicesListProvider`. That was the initial theory
// (APPEND mode is decided by one `ref.read(servicesListProvider).value` in
// `initState`, a snapshot rather than a watch, so an unresolved provider reads
// null and drops the screen into SETUP with an EMPTY owned-id set). MEASURED
// 2026-08-04: rewriting this flow to jump straight to `/services/setup` still
// lands in APPEND mode and still passes — the master-home screen has already
// resolved that keepAlive provider by then. The theory is recorded here because
// it is the right shape of worry, just not the operative one; the APPEND-framing
// assertion below stays as a genuine precondition guard either way.
//
// THE NEGATIVE ASSERTION IS PROBED IN-TEST (playbook M14)
// -------------------------------------------------------
// "the owned row has no toggle" is an absence assertion, and an absence
// assertion passes just as happily when NOTHING renders a toggle. The control
// is asserted in the same breath: the sibling row's toggle must be present. One
// findsNothing plus one findsOneWidget over the same widget key shape, in the
// same category, in the same frame — so a blanket regression that stopped
// rendering toggles turns the flow red instead of green.
//
// KEY POLICY
// ----------
// All navigation/interaction finders are key-based (app_harness.dart policy).
// Content assertions read localized copy off a live context, never a hardcoded
// Cyrillic literal (`scripts/forbid_cyrillic_finder.sh`).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
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
    'INDEPENDENT_MASTER with an existing catalogue opens the setup screen from '
    'the services-list FAB, sees the already-owned type inert, and appends a '
    'new one',
    (tester) async {
      // Seeded into the master's catalogue by FakeBackend (`assign-typed`), so
      // the setup screen must render it un-includable.
      const String ownedTypeId = 'type-nails-classic';
      // The other NAILS type — not in the catalogue, so it stays selectable.
      const String freeTypeId = 'type-nails-gel';

      final fb = FakeBackend();
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      AppHarness.expectLocation(router, RouteNames.masterProfile);

      // ── 1. The populated services list ───────────────────────────────────
      // Entering through the list (rather than jumping straight to /setup) is
      // load-bearing — see the header note on the initState snapshot.
      router.go(RouteNames.services);

      final Finder fab = find.byKey(const Key('btn-create-service'));
      await tester.pumpUntilFound(fab.hitTestable());
      expect(
        fab,
        findsOneWidget,
        reason:
            'a master WITH services sees the FAB, not the empty-state CTA — if '
            'this is absent the catalogue never loaded and the APPEND '
            'precondition does not hold',
      );

      // ── 2. FAB → setup screen ────────────────────────────────────────────
      // The FAB used to open the deleted /services/create. It now opens the
      // multi-select setup screen through `_openAndRefresh`, which awaits the
      // `context.push` Future — so the destination MUST exit by popping.
      await tester.tap(fab);
      await tester.pumpUntilFound(find.byKey(const Key('btn-setup-close')));

      // go_router's currentConfiguration.uri does not update after an
      // imperative push, so the destination is proven by the setup screen's own
      // chrome key — the same convention master_home_add_services_flow_test.dart
      // uses.
      final Finder closeBtn = find.byKey(const Key('btn-setup-close'));
      expect(closeBtn, findsOneWidget);

      final l10n = AppLocalizations.of(tester.element(closeBtn));

      // ── 3. APPEND framing ────────────────────────────────────────────────
      // This is the assertion that proves the initState snapshot was warm. If
      // it were not, the screen would show the SETUP title and every exclusion
      // assertion below would be vacuous.
      expect(
        find.text(l10n.serviceSetupTitleAppend),
        findsOneWidget,
        reason:
            'a non-empty catalogue must reframe the screen as "add services"; '
            'seeing the SETUP title instead means `servicesListProvider` had '
            'not resolved when initState read it, which would also empty the '
            'owned-id set and make this whole flow prove nothing',
      );
      expect(find.text(l10n.serviceSetupTitle), findsNothing);

      // ── 4. Expand NAILS ──────────────────────────────────────────────────
      final Finder nailsChip = find.byKey(const ValueKey<String>('cat_NAILS'));
      await tester.pumpUntilFound(nailsChip.hitTestable());
      await tester.tap(nailsChip);

      final Finder ownedRow = find.byKey(const Key('setup_row_$ownedTypeId'));
      final Finder freeRow = find.byKey(const Key('setup_row_$freeTypeId'));
      await tester.pumpUntilFound(ownedRow);
      await tester.pumpUntilFound(freeRow);

      // ── 5. The exclusion, asserted WITH its control ──────────────────────
      // The owned type is RENDERED (not hidden — a master hunting for a service
      // they already offer must see why it is unselectable) but carries no
      // include switch at all.
      expect(
        ownedRow,
        findsOneWidget,
        reason:
            'an already-owned type must stay visible; hiding it reads as a '
            'broken catalogue',
      );
      expect(
        find.byKey(const Key('setup_row_toggle_$ownedTypeId')),
        findsNothing,
        reason:
            'the already-owned row must expose NO include switch — one such '
            'item in the all-or-nothing bulk payload rolls the WHOLE batch '
            'back with 409 DUPLICATE_SERVICE',
      );
      expect(
        find.descendant(
          of: ownedRow,
          matching: find.text(l10n.serviceSetupRowAlreadyAdded),
        ),
        findsOneWidget,
        reason: 'the row must say WHY it is inert',
      );

      // CONTROL for the findsNothing above — same key shape, same category,
      // same frame. Without this, a regression that stopped rendering include
      // switches entirely would leave the assertion above green.
      final Finder freeToggle = find.byKey(
        const Key('setup_row_toggle_$freeTypeId'),
      );
      expect(
        freeToggle,
        findsOneWidget,
        reason:
            'the NON-owned sibling must keep its switch — this is what proves '
            'the absence assertion above is about ownership and not about '
            'toggles having vanished',
      );

      // ── 6. Configure the free type ───────────────────────────────────────
      // `.hitTestable()` — the cards animate (AnimatedContainer, 220 ms) and
      // `hitTestWarningShouldBeFatal` is armed in AppHarness.boot, so tapping a
      // not-yet-hittable target is a hard failure rather than a silent miss.
      await tester.ensureVisible(freeToggle);
      await tester.pumpUntilFound(freeToggle.hitTestable());
      await tester.tap(freeToggle);

      // Both entries are SCOPED to this row — every included row renders the
      // same field keys.
      final Finder durationField = find.descendant(
        of: freeRow,
        matching: find.byKey(const Key('service-setup-duration')),
      );
      final Finder priceField = find.descendant(
        of: freeRow,
        matching: find.byKey(const Key('pricing-fixed-amount')),
      );
      await tester.pumpUntilFound(durationField);
      await tester.pumpUntilFound(priceField);
      await tester.enterText(durationField, '90');
      await tester.pump();
      await tester.enterText(priceField, '700');
      await tester.pump();

      // The CTA counts what the save would ADD (append copy), not what it would
      // create — the second half of the SETUP/APPEND copy switch, asserted here
      // at the E2E tier because it is what the master actually reads before
      // committing.
      expect(
        find.text(l10n.serviceSetupCtaAdd(1)),
        findsOneWidget,
        reason:
            'APPEND mode must count "add 1", never "create my menu of 1"; the '
            'owned row must also not be counted',
      );

      // ── 7. Save ──────────────────────────────────────────────────────────
      final Finder saveBtn = find.byKey(const Key('btn-setup-save'));
      await tester.pumpUntilFound(saveBtn.hitTestable());
      await tester.tap(saveBtn);

      // DIAGNOSE AT THE CAUSE — assert the POST fired before asserting on its
      // payload or on the route. A save blocked client-side (a swallowed toggle
      // tap, a row flagged by _assemble) looks identical downstream to "the
      // append is broken".
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.bulkCreateCalls >= 1,
        description:
            'the bulk POST to reach the fake backend — if it never does, the '
            'save was blocked CLIENT-SIDE (most likely the row was never '
            'actually included, or its duration/price failed _assemble)',
      );

      // ── 8. The payload is the real proof of the exclusion ────────────────
      // The rendered-toggle assertions are about what the master can DO; this
      // is about what actually went over the wire, which is what the backend
      // 409s on.
      final List<dynamic>? items = fb.lastBulkItems;
      expect(items, isNotNull);
      expect(
        items,
        hasLength(1),
        reason: 'exactly one row was included, so exactly one item may ship',
      );
      final Map<String, dynamic> item = (items!.single as Map<String, dynamic>);
      expect(item['serviceTypeId'], freeTypeId);
      expect(item['durationMinutes'], 90);
      expect(item['priceType'], 'FIXED');
      expect(item['price'], 700);

      final List<Object?> submittedIds = items
          .map((dynamic e) => (e as Map<String, dynamic>)['serviceTypeId'])
          .toList();
      expect(
        submittedIds,
        isNot(contains(ownedTypeId)),
        reason:
            'submitting an already-owned service type rolls the ENTIRE batch '
            'back — the append save would be impossible for any master who '
            'already offers one type in the category they are browsing',
      );

      // ── 9. Back on the list ──────────────────────────────────────────────
      // The screen POPS (never `go`) — the services list awaits that push
      // Future to re-fire its catalogue invalidation, so a `go` exit would leak
      // the await and leave the list stale.
      await tester.pumpUntilGone(find.byKey(const Key('btn-setup-close')));
      AppHarness.expectLocation(router, RouteNames.services);
      expect(
        find.byKey(const Key('btn-create-service')),
        findsOneWidget,
        reason:
            'a successful append returns to the services list, which is where '
            'the newly added service now lives',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
