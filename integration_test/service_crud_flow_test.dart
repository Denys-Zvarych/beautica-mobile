// Phase 17.3 — E2E: Service CRUD Flow
//
// Two independent journeys (INDEPENDENT_MASTER):
//
// Test 1 — CREATE, via the setup screen's bulk write:
//   1. Login → /master/profile
//   2. Navigate to /services/setup
//   3. Tap the NAILS category chip → its service-type rows load inline
//   4. Toggle one type ON, fill its duration + FIXED price
//   5. Save → assert the BULK POST fired, that its PAYLOAD carries the expected
//      serviceTypeId / duration / price, and that the screen returns to /services
//
// Test 2 — EDIT (independent of test 1):
//   1. Login → /master/profile
//   2. Navigate straight to /services/assign-2/edit
//   3. Assert the RANGE pricing fields rendered from the seeded backend data
//
// WHY TEST 1 GOES THROUGH /services/setup
// ---------------------------------------
// `/services/create` and its single-service form are DELETED. `/services/setup`
// is now the ONE "add services" surface — reached from both the services-list
// empty state and the «Додати послугу» FAB — and it writes through
// `POST /independent-masters/me/services/bulk`, which `beautica-backend`
// c5e420f made ADDITIVE (it used to 409 whenever the catalogue was non-empty,
// which is why a separate create form existed at all). So "a master can create
// a service end-to-end over the real HTTP path" is now proved against the bulk
// endpoint, asserted on `bulkCreateCalls` + `lastBulkItems` rather than on the
// retired `createServiceCalls`.
//
// NOTE ON SERVICE REPOSITORY
// --------------------------
// The setup and edit screens call ServiceRepository.bulkCreate / .update
// directly (not via Dio) only when serviceRepositoryProvider is backed by the
// real HttpServiceRepository. In the harness the dioProvider is the
// FakeBackend's Dio, so the real Http repositories hit the fake endpoints
// wired in fake_backend.dart. This proves the REAL HTTP path (not a mocked
// repository).
//
// KEY POLICY
// ----------
// All navigation taps use key-based finders. See app_harness.dart for policy.

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

  // ── Test 1 — Create a service (FIXED pricing) via the bulk setup screen ───

  testWidgets(
    'INDEPENDENT_MASTER can create a FIXED-price service',
    (tester) async {
      // The service type this flow configures. Deliberately NOT
      // `type-nails-classic`: the fake backend seeds that one into the master's
      // existing catalogue, so its row renders inert (a static check glyph
      // instead of a toggle, sub-label «Вже додано») — an already-owned type
      // can never be included, which would block this flow for a reason
      // unrelated to what it proves.
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

      // Should land on /master/profile. Navigate directly to /services/setup via
      // the router reference — skipping the services list, whose loading
      // skeleton runs an infinite shimmer (and which would add a second
      // Scrollable to the tree during the GoRouter transition).
      //
      // pump-until, never pumpAndSettle: the setup screen shows a
      // CircularProgressIndicator (an infinite animation) while
      // approvedCategoriesProvider resolves, and again per-category while the
      // service types load. pumpAndSettle can never observe "no frames
      // scheduled" with one of those in the tree.
      AppHarness.expectLocation(router, RouteNames.masterProfile);
      router.go(RouteNames.serviceSetup);

      // ── Expand the NAILS category ────────────────────────────────────────
      // The fake backend seeds two approved categories
      // ({name:'NAILS', displayName:'Нігті'} and BROWS). Selecting a chip
      // expands it INLINE — there is no bottom sheet on this screen — and lazily
      // fetches that category's service types.
      final Finder nailsChip = find.byKey(const ValueKey<String>('cat_NAILS'));
      await tester.pumpUntilFound(nailsChip.hitTestable());
      AppHarness.expectLocation(router, RouteNames.serviceSetup);
      await tester.tap(nailsChip);

      // Wait for the ROW itself (not a pump count) — the per-category fetch
      // renders its own spinner until the types arrive.
      final Finder row = find.byKey(const Key('setup_row_$typeId'));
      await tester.pumpUntilFound(row);

      // ── Toggle the row ON ────────────────────────────────────────────────
      // `.hitTestable()` — NOT bare existence. Rows are emitted by a lazy
      // SliverList and each card animates (AnimatedContainer, 220 ms), so a
      // bare `pumpUntilFound` can return while the toggle is not yet a valid
      // hit target; the tap would then either be swallowed or trip
      // `hitTestWarningShouldBeFatal` (armed in AppHarness.boot). Waiting on
      // hit-testability OBSERVES the animation instead of guessing at it.
      final Finder toggle = find.byKey(const Key('setup_row_toggle_$typeId'));
      await tester.ensureVisible(toggle);
      await tester.pumpUntilFound(toggle.hitTestable());
      await tester.tap(toggle);

      // ── Fill duration + FIXED price ──────────────────────────────────────
      // Both entries are SCOPED to this row's card: every included row renders
      // the same `service-setup-duration` / `pricing-fixed-amount` keys, so an
      // unscoped finder would be ambiguous as soon as a second row is included.
      // The fields ride the card's AnimatedSize + AnimatedSwitcher (~240 ms
      // cross-fade), so wait for them to exist before typing.
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

      // ── Save ─────────────────────────────────────────────────────────────
      // The CTA is pinned in the footer and is disabled (onPressed == null)
      // while nothing is included, so hit-testability here also implies the
      // toggle above actually took.
      final Finder saveBtn = find.byKey(const Key('btn-setup-save'));
      await tester.pumpUntilFound(saveBtn.hitTestable());
      await tester.tap(saveBtn);

      // DIAGNOSE AT THE CAUSE — assert the POST fired before asserting on the
      // route. A save blocked client-side (swallowed toggle tap, a row flagged
      // by _assemble for a missing duration/price) leaves the app sitting on
      // /services/setup, which reads as "navigation is broken" when it is
      // really "the request never happened".
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.bulkCreateCalls >= 1,
        description:
            'the bulk POST to reach the fake backend — if it never does, the '
            'save was blocked CLIENT-SIDE (most likely the row was never '
            'actually included, or its duration/price failed _assemble and '
            'flagged the row instead of assembling a payload)',
      );

      // PAYLOAD assertion — proves the screen submitted the RIGHT thing, not
      // merely that a call happened. `lastBulkItems` is the decoded `items`
      // list exactly as it went over the wire.
      final List<dynamic>? items = fb.lastBulkItems;
      expect(
        items,
        isNotNull,
        reason: 'the bulk POST body must carry an `items` list',
      );
      expect(
        items,
        hasLength(1),
        reason: 'exactly one row was included, so exactly one item must ship',
      );
      final Map<String, dynamic> item = (items!.first as Map)
          .cast<String, dynamic>();
      expect(
        item['serviceTypeId'],
        typeId,
        reason:
            'the submitted item must name the service type that was toggled',
      );
      expect(
        item['durationMinutes'],
        60,
        reason: 'the entered duration must reach the wire as an int',
      );
      expect(
        item['priceType'],
        'FIXED',
        reason: 'the row was left in the default FIXED pricing mode',
      );
      expect(
        item['price'],
        400,
        reason: 'the entered fixed price must reach the wire',
      );
      expect(
        item.containsKey('priceMin'),
        isFalse,
        reason:
            'FIXED items must omit (not null) the RANGE-only price fields — see '
            'HttpServiceRepository._bulkItemToJson',
      );

      // After a successful bulk save the screen leaves back to /services.
      // `router.go` gave this route no stack to pop, so `_leave()` takes its
      // `context.go(RouteNames.services)` fallback; from the FAB the same call
      // pops instead. Both land here.
      await AppHarness.pumpUntilCondition(
        tester,
        () => AppHarness.location(router) == RouteNames.services,
        description:
            'the setup screen to leave back to /services after the successful '
            'bulk save',
      );
      AppHarness.expectLocation(router, RouteNames.services);
    },
    // Timeout extension — the setup screen loads categories then service types.
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── Test 2 — Service edit form renders RANGE pricing fields ─────────────
  //
  // RC3 STRENGTHENED: previous version only asserted the form wrapper widget
  // was present (a route check, not a content assertion). This version
  // additionally verifies that:
  //   (a) the RANGE-specific price fields rendered (proving the service data
  //       was fetched from the fake backend and deserialized into the form), and
  //   (b) the name and duration fields are pre-populated from the seeded data.
  //
  // NOTE: a full submit (PATCH) for svc-2 is not exercised here because the
  // fake backend only wires PATCH for svc-1 — adding svc-2 PATCH coverage is
  // tracked in the backlog. The content-assertion layer here closes the
  // "no-op render check" gap flagged in the Rule-3 audit.

  testWidgets(
    'INDEPENDENT_MASTER service edit form renders RANGE pricing fields with seeded data',
    (tester) async {
      final fb = FakeBackend();
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // Navigate directly to the RANGE service edit screen via the router
      // reference. Skipping the /services list avoids the pumpAndSettle timeout
      // caused by _ServiceSkeletonCard._shimmer.repeat() (an infinite animation
      // in the loading skeleton that prevents pumpAndSettle from ever settling).
      const String kRangeServiceEditFormKey = 'service-edit-form-assign-2';
      router.go(RouteNames.serviceEdit('assign-2'));
      // Pump manually to advance past the 1000 ms entrance animation in
      // _EditBodyState rather than using pumpAndSettle — which would loop until
      // all animations complete but may time out if any animation runs longer.
      // 12 × 100 ms = 1200 ms of fake-clock time → past the 1000 ms entrance.
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // The route path uses the assignment id (MasterService.id).
      AppHarness.expectLocation(router, '/services/assign-2/edit');

      // Assert the form wrapper is rendered.
      expect(
        find.byKey(const Key(kRangeServiceEditFormKey)),
        findsOneWidget,
        reason:
            'ServiceEditForm must be rendered with the pre-seeded service assignmentId',
      );

      // RC3 CONTENT ASSERTIONS — prove the fake backend data was fetched and
      // deserialized into the form. The seeded assign-2 service is:
      //   name='Брови корекція', priceType=RANGE, priceMin=200, priceMax=350,
      //   effectiveDurationMinutes=45.

      // (a) RANGE-specific price fields must be visible (not the FIXED field).
      // These are rendered by PricingField when priceType == RANGE.
      expect(
        find.byKey(const Key('pricing-range-min')),
        findsOneWidget,
        reason:
            'RANGE service must render the min-price field (pricing-range-min); '
            'if missing the form is showing FIXED fields or data was not fetched',
      );
      expect(
        find.byKey(const Key('pricing-range-max')),
        findsOneWidget,
        reason:
            'RANGE service must render the max-price field (pricing-range-max)',
      );

      // (b) FIXED-price field must NOT be visible for a RANGE service.
      expect(
        find.byKey(const Key('pricing-fixed-amount')),
        findsNothing,
        reason:
            'FIXED price field must not be rendered when priceType is RANGE',
      );

      // (c) Fake backend must have served the service data (GET fired).
      expect(
        fb.getServicesCalls,
        greaterThanOrEqualTo(1),
        reason:
            'GET /independent-masters/me/services or /services/svc-2 must be '
            'called to populate the edit form',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
