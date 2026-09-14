// Mobile phase 317 — E2E: the SALON-TARGET services subtree, driven by DEEP
// LINK against a real app boot.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — user-flow coverage)
// -----------------------------------------------------------
// Phase 317 registers three routes
// (`/salons/:salonId/manage/staff/:memberId/services{,/setup,/:id/edit}`)
// under a `ShellRoute` whose builder installs ONE `ProviderScope` overriding
// `serviceTargetProvider`, and declares `dependencies:` on SEVEN providers so
// that override actually reaches `HttpServiceRepository`. That cascade is the
// phase's entire central claim, and until this file it was proven only by
// widget-level pumps (`test/routing/salon_manage_staff_services_route_test
// .dart`) against a hand-built container.
//
// Phase 317's own "Test scope" section argued the salon journey "needs the
// tile from phase 318 to be tappable and is authored there". That reasoning
// does NOT hold: a tile is needed to TAP, not to NAVIGATE. All three routes
// are live and reachable by URL the moment this phase lands, so the scoping
// they install is reachable today — and if the cascade is missing in a RELEASE
// build, riverpod's "may be scoped" assert is `kDebugMode`-gated
// (`riverpod-3.1.0/.../element.dart:922`) and `riverpod_lint` was removed on
// 2026-08-18, so the failure is SILENT: the salon screens quietly render the
// OPERATOR's own catalogue and a delete destroys the SHARED salon definition
// (`DELETE /services/{id}`) instead of unassigning one master from it. That is
// the exact data-loss bug phase 316 exists to prevent.
//
// WHAT THE TWO FLOWS PIN
// ----------------------
//  1. THE READ REACHES THE RIGHT WIRE. A deep link to
//     `/salons/salon-xyz/manage/staff/user-master-removable/services` as a
//     SALON_OWNER must emit
//     `GET /api/v1/salons/salon-xyz/masters/master-removable/services` —
//     the master ROW id, resolved from the roster entry's USER id by
//     `_SalonManageStaffServicesShell` — and must NOT emit
//     `GET /api/v1/independent-masters/me/services`, which is what a
//     root-resolved repository would have called.
//  2. THE DELETE UNASSIGNS, NEVER DEACTIVATES. Opening a card's edit screen
//     INSIDE the subtree and deleting must issue
//     `DELETE /api/v1/salons/salon-xyz/masters/master-removable/services/
//     salon-def-1` and leave `DELETE /api/v1/services/{defId}` — the
//     shared-definition destroy — at ZERO. The refreshed list then renders
//     without the removed card while its sibling survives, which is D2's
//     "one scope, not three" claim end to end: the invalidation fired on the
//     EDIT leaf reaches the LIST leaf's `keepAlive` provider.
//
// WHY THESE ASSERTIONS CANNOT PASS VACUOUSLY
// ------------------------------------------
//   • DIFFERING IDS. The roster row driven here is `user-master-removable` /
//     `master-removable` — a userId that DIFFERS from its `masters` row id
//     (unlike `master-aaa`, whose two ids are identical and so cannot catch a
//     swap). The emitted path is asserted to contain `/masters/master-removable
//     /services` AND `isNot(contains('user-master-removable'))`
//     (`project_fixture_values_can_defang_assertions`).
//   • DISJOINT CATALOGUES. `FakeBackend._salonMasterServices` shares no id,
//     name or price with `_services` (the operator's own menu), so a
//     wrong-target render is assertable rather than indistinguishable: the
//     flow pins the salon card key PRESENT and the operator's own card key
//     ABSENT.
//   • BOTH DIRECTIONS ON EVERY COUNTER. Each "the right endpoint fired" is
//     paired with "the wrong endpoint did not" — a fixture that answers
//     nothing at all fails the first half, and a fixture that answers both
//     fails the second.
//   • MUTATION-PROVED, OBSERVED (2026-09-10, mobile-qa). Two mutations of
//     `lib/routing/app_router.dart`, each restored from a `cp` backup (never
//     `git checkout` — the chain's work is uncommitted):
//       A. `_SalonManageStaffServicesShell._resolved` returns `child` with NO
//          `ProviderScope` — the release-mode silent failure, which trips no
//          riverpod assert. Result: BOTH tests RED (`+0 -2`).
//       B. the override carries `masterId: memberId` (the roster USER id)
//          instead of the resolved `masters` row id. Result: BOTH tests RED
//          (`+0 -2`) — the salon endpoint is never matched at all.
//     Restored: `+2 All tests passed`. Neither mutation is one this file can
//     pass through, which is the property a flow that "proves the scoping"
//     has to have.
//
// RUNTIME-BLOCKED, DELIBERATELY FAKE-BACKED. The two salon-scoped endpoints
// exist only on `beautica-backend@feat/salon-owned-master-services` (backend
// phases 307 + 309), so this flow drives `FakeBackend` — which is how every
// flow in this repo works. It is NOT skip-marked: the mobile dispatch, the
// route builder's userId→masterId resolution and the `dependencies:` cascade
// are all fully exercised against the wire shape the backend branch ships.
//
// TIMING: never `pumpAndSettle`/`AppHarness.settle` after the deep link — the
// list screen runs staggered card entrance animations and the edit screen a
// 1000 ms entrance, so "no frames scheduled" is never observed. Every wait is
// `AppHarness.pumpUntilFound` / `pumpUntilCondition` (bounded, real wall
// clock).
//
// KEY POLICY: navigation taps use key-based finders only (see app_harness.dart).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The salon whose roster carries the driven master.
const String _kSalonId = 'salon-xyz';

/// The roster entry's `userId` — what the `:memberId` path segment carries.
const String _kMemberUserId = 'user-master-removable';

/// The `masters` ROW id the route builder must resolve from [_kMemberUserId].
/// A DIFFERENT string, which is the whole point.
const String _kMasterRowId = 'master-removable';

/// The salon-scoped list endpoint the repository must emit under the target.
const String _kSalonServicesUri =
    '/api/v1/salons/$_kSalonId/masters/$_kMasterRowId/services';

/// The SECOND master on the same salon (`master-aaa`) — the phase-317 VICTIM.
/// Their roster `userId` and `masters` row id are identical, so one constant
/// serves both the `:memberId` path segment and the fake's row lookups.
const String _kMasterAaaMemberId = 'master-aaa';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Boots as a SALON_OWNER who owns [_kSalonId] and lands on the salon shell.
  ///
  /// `salon-xyz` is not in the owner persona's default `mySalons`
  /// (`salon-owner-1` only), so it is seeded BEFORE boot — otherwise
  /// `salonManageGuard`'s owner arm bounces the deep link and the flow would
  /// measure the guard instead of the scoping. Same seeding the phase-312
  /// schedule flows do.
  Future<GoRouter> bootAsOwnerOfSalonXyz(
    WidgetTester tester,
    FakeBackend fb,
  ) async {
    fb.mySalons.add(<String, dynamic>{
      'id': _kSalonId,
      'ownerId': 'user-owner-1',
      'name': 'Студія Краси «Камелія»',
      'city': 'Київ',
      'cityId': 'city-kyiv',
      'oblastId': 'oblast-kyiv',
      'street': 'вул. Хрещатик',
      'buildingNo': '12',
      'isActive': true,
      'isPrimary': false,
    });
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
    await AppHarness.pumpUntilFound(
      tester,
      find.byType(SalonShellScreen),
      timeout: const Duration(seconds: 20),
    );
    return router;
  }

  /// Deep-links to the master's «Послуги» leaf and waits for the list to
  /// render its cards.
  ///
  /// Expands the NAILS section if needed: sections start COLLAPSED when
  /// `initialExpandCategory` is null (the default on this route), so no card
  /// is in the tree until its section is expanded. Conditional rather than
  /// unconditional — an unconditional tap would toggle a still-expanded
  /// section shut.
  Future<void> deepLinkToSalonMasterServices(
    WidgetTester tester,
    GoRouter router, {
    required Finder card,
  }) async {
    router.go(RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId));
    await AppHarness.pumpUntilFound(
      tester,
      find.byType(ServicesListScreen),
      timeout: const Duration(seconds: 20),
    );
    final Finder nails = find.byKey(const Key('category_section_NAILS'));
    await AppHarness.pumpUntilFound(
      tester,
      nails,
      timeout: const Duration(seconds: 20),
    );
    if (card.evaluate().isEmpty) {
      await AppHarness.tapVisible(tester, nails);
    }
    await AppHarness.pumpUntilFound(
      tester,
      card,
      timeout: const Duration(seconds: 20),
    );
  }

  // ── 1. The READ reaches /salons/{s}/masters/{m}/services ─────────────────

  testWidgets(
    'SALON_OWNER deep-links to a master\'s services: the wire carries '
    '/salons/S/masters/M/services with the master ROW id, and '
    '/independent-masters/me/services is never touched',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend();
        final GoRouter router = await bootAsOwnerOfSalonXyz(tester, fb);

        // Baseline captured immediately BEFORE the deep link, so nothing the
        // login/landing path happens to fetch can be mistaken for the
        // wrong-target read this flow exists to catch.
        final int ownCallsBefore = fb.getServicesCalls;
        expect(
          fb.getSalonMasterServicesCalls,
          0,
          reason: 'precondition — nothing salon-scoped fetched yet',
        );

        final Finder salonCard = find.byKey(
          const Key('service_card_salon-assign-1'),
        );
        await deepLinkToSalonMasterServices(tester, router, card: salonCard);

        // THE phase-317 assertion. The `dependencies:` cascade carried the
        // scoped `SalonMasterTarget` all the way to `HttpServiceRepository`,
        // which dispatched `listMyServices()` to `_listForSalonMaster`.
        expect(
          fb.getSalonMasterServicesCalls,
          greaterThanOrEqualTo(1),
          reason:
              'the scoped target must reach the repository through a real app '
              'boot — not merely through a hand-built ProviderContainer',
        );
        expect(fb.lastSalonMasterServicesPath, _kSalonServicesUri);
        expect(
          fb.lastSalonMasterServicesPath,
          isNot(contains(_kMemberUserId)),
          reason:
              'the `:memberId` segment is a USER id; the route builder must '
              'resolve the `masters` ROW id off the roster. A userId on '
              '/salons/{s}/masters/{m}/... yields 404, not 403.',
        );

        // The other half: the endpoint a ROOT-resolved repository would have
        // called never fired. Without this a fixture answering BOTH would pass
        // the assertion above while the operator's own menu was on screen.
        expect(
          fb.getServicesCalls,
          ownCallsBefore,
          reason:
              'GET /independent-masters/me/services is what a repository '
              'resolved against the ROOT container emits — the silent '
              'release-mode failure mode of a missing `dependencies:` '
              'declaration',
        );

        // …and the rendered rows are the SALON MASTER's, not the operator's.
        // The two catalogues share no id, so this cannot pass on either.
        expect(salonCard, findsOneWidget);
        expect(
          find.byKey(const Key('service_card_salon-assign-2')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('service_card_assign-1')),
          findsNothing,
          reason:
              "the OPERATOR's own seeded service must not be on a salon "
              "master's «Послуги» screen",
        );
      });
    },
  );

  // ── 2. The DELETE unassigns; it never destroys the shared definition ─────

  testWidgets(
    'a delete inside the subtree UNASSIGNS the master from the shared salon '
    'definition — DELETE /services/{defId} never fires, and the list leaf '
    'refreshes without the removed card',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend();
        final GoRouter router = await bootAsOwnerOfSalonXyz(tester, fb);

        final Finder salonCard = find.byKey(
          const Key('service_card_salon-assign-1'),
        );
        await deepLinkToSalonMasterServices(tester, router, card: salonCard);

        // Through the CARD, not `router.go(...edit)`: the card's «Редагувати»
        // uses `context.push` (`_openAndRefresh`), so the delete's
        // `_popServiceEditScreen` has a real route to POP — the shipped path.
        // A `go` entry leaves nothing to pop and `Navigator.maybePop` silently
        // no-ops, so the flow would assert against a path users never take
        // (`project_gorouter_imperative_match_fullpath`).
        await AppHarness.tapVisible(tester, salonCard);
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('service-edit-form-salon-assign-1')),
          timeout: const Duration(seconds: 20),
        );
        // `expectNestedPushLocation`, NOT `expectLocation`: the push nests
        // INTO the subtree's already-active `ShellRouteMatch` rather than
        // appending a top-level entry, so `configuration.uri` stays on the
        // LIST leaf and the plain resolver reads stale — measured, and the
        // exact shape `AppHarness.nestedPushLocation` documents.
        AppHarness.expectNestedPushLocation(
          router,
          RouteNames.salonManageStaffServiceEdit(
            _kSalonId,
            _kMemberUserId,
            'salon-assign-1',
          ),
        );

        expect(fb.unassignServiceCalls, 0, reason: 'nothing unassigned yet');
        expect(fb.deleteServiceCalls, 0, reason: 'nothing deactivated yet');

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('btn-delete-service')),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('delete-service-dialog')),
          timeout: const Duration(seconds: 20),
        );
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('btn-confirm-delete-service')),
        );
        await AppHarness.pumpUntilCondition(
          tester,
          () => fb.unassignServiceCalls >= 1,
          description:
              'DELETE /salons/S/masters/M/services/{defId} to reach the wire',
          timeout: const Duration(seconds: 20),
        );

        expect(fb.unassignServiceCalls, 1);
        expect(
          fb.lastUnassignPath,
          '$_kSalonServicesUri/salon-def-1',
          reason:
              'phase 316 — with a SalonMasterTarget in scope `deactivate()` '
              'must dispatch to the per-master UNASSIGN',
        );
        // The id on the wire is the DEFINITION id. The fixture gives this row
        // an assignment id (`salon-assign-1`) that DIFFERS from its definition
        // id (`salon-def-1`); with equal ids both expectations would pass on
        // either, which is precisely how the bug ships.
        expect(fb.lastUnassignedServiceDefId, 'salon-def-1');
        expect(fb.lastUnassignedServiceDefId, isNot('salon-assign-1'));

        // THE data-loss assertion. `DELETE /api/v1/services/{defId}` destroys
        // the definition for EVERY master in the salon who performs it. Under
        // a salon target it must never fire.
        expect(
          fb.deleteServiceCalls,
          0,
          reason:
              'a root-resolved repository would have deactivated the SHARED '
              'salon definition here — the exact data-loss bug phase 316 '
              'exists to prevent',
        );

        // Back on the LIST leaf, refreshed. This is D2 end to end: the
        // invalidation fired from the EDIT leaf reached the LIST leaf's
        // `keepAlive` provider. With three per-route scopes it lands in a
        // different chain and the deleted card is still rendered.
        await AppHarness.pumpUntilCondition(
          tester,
          () =>
              AppHarness.nestedPushLocation(router) ==
              RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId),
          description: 'the edit screen to pop back to the salon list leaf',
          timeout: const Duration(seconds: 20),
        );
        // Pumped, not asserted outright: the pop runs a page transition, so
        // the edit form is still mounted for a few frames after the location
        // flips. This is the "genuinely popped, not merely re-located" pin.
        await AppHarness.pumpUntilCondition(
          tester,
          () => find
              .byKey(const Key('service-edit-form-salon-assign-1'))
              .evaluate()
              .isEmpty,
          description: 'the edit form to leave the tree after the pop',
          timeout: const Duration(seconds: 20),
        );
        final Finder survivor = find.byKey(
          const Key('service_card_salon-assign-2'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          survivor,
          timeout: const Duration(seconds: 20),
        );

        expect(
          find.byKey(const Key('service_card_salon-assign-1')),
          findsNothing,
          reason: 'the unassigned service must be gone from the refreshed list',
        );
        expect(
          survivor,
          findsOneWidget,
          reason:
              'anti-vacuity — the sibling row is still rendered, so the '
              'assertion above is a REFRESH and not an unmounted/empty screen',
        );
        expect(
          fb.getSalonMasterServicesCalls,
          greaterThanOrEqualTo(2),
          reason:
              'the list re-fetched through the SCOPED repository after the '
              'unassign — not through the root one',
        );
      });
    },
  );

  // ── 3. A SAVE writes the PER-MASTER band, never the shared definition ────
  //
  // THE DEFECT (phase 317). `update` used to PATCH the SHARED definition with
  // the price AND the duration under a salon target, silently re-pricing and
  // re-timing every OTHER master in the salon who performs that service. Both
  // endpoints answer 200, so nothing on screen said anything was wrong — the
  // harm was on someone else's screen.
  //
  // THIS IS THE TIER WHOSE ABSENCE LET IT SHIP. The salon edit-screen cases
  // above OPEN the screen; none of them SAVED. The unit and contract tiers pin
  // the request shape, but only a flow can pin the CONSEQUENCE, and only
  // because `FakeBackend` models the shared semantics: a definition PATCH
  // carrying money or time cascades onto every master row resolving against
  // that definition with no per-master override. So the "master A is
  // untouched" assertion below is a state that genuinely MOVES when the bug is
  // present — not a fixture that could never have changed.

  /// Types [text] into the field inside the keyed wrapper.
  ///
  /// `pricing-fixed-amount` / `field-service-duration` sit on the neumorphic
  /// INSET wrapper, not on the field, so the [TextField] is one level down.
  Future<void> enterFieldText(
    WidgetTester tester,
    Key wrapper,
    String text,
  ) async {
    final Finder field = find.descendant(
      of: find.byKey(wrapper),
      matching: find.byType(TextField),
    );
    await AppHarness.pumpUntilFound(
      tester,
      field,
      timeout: const Duration(seconds: 20),
    );
    // `ensureVisible` jumps (Duration.zero) rather than animating, so ONE
    // plain frame is enough to lay the well out at its final offset before
    // typing — no fixed sleep to guess at (see the TIMING note at the top).
    await tester.ensureVisible(field);
    await tester.pump();
    await tester.enterText(field, text);
    // Deterministic settle: pump until [text] is genuinely readable INSIDE
    // this wrapper. Stronger than a sleep — it also proves the entry landed
    // on the intended well and not on a sibling field.
    await AppHarness.pumpUntilFound(
      tester,
      find.descendant(of: find.byKey(wrapper), matching: find.text(text)),
      timeout: const Duration(seconds: 20),
    );
  }

  testWidgets(
    'saving a salon master\'s new price + duration PATCHes the PER-MASTER '
    'band only — the shared definition receives no money or time, and a '
    'SECOND master performing the same service keeps their own 750 ₴ / 90 хв',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend();
        final GoRouter router = await bootAsOwnerOfSalonXyz(tester, fb);

        // PRECONDITION, read off the fake: BOTH masters resolve against the
        // same shared definition `salon-def-1` at the same 750 ₴ / 90 min, and
        // neither carries a per-master override. A fixture that drifted apart
        // fails HERE rather than silently defanging the harm assertion below.
        expect(fb.salonResolvedPrice('master-removable', 'salon-def-1'), 750);
        expect(fb.salonResolvedPrice('master-aaa', 'salon-def-1'), 750);
        expect(fb.salonResolvedDuration('master-aaa', 'salon-def-1'), 90);
        expect(fb.updateMasterBandCalls, 0);
        expect(fb.patchSharedDefinitionPricedCalls, 0);

        final Finder salonCard = find.byKey(
          const Key('service_card_salon-assign-1'),
        );
        await deepLinkToSalonMasterServices(tester, router, card: salonCard);

        // Through the CARD (`context.push`), the shipped path — same reasoning
        // as the delete flow above.
        await AppHarness.tapVisible(tester, salonCard);
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('service-edit-form-salon-assign-1')),
          timeout: const Duration(seconds: 20),
        );

        // 750 → 990 ₴ and 90 → 120 хв. BOTH halves are changed on purpose:
        // the duration had the identical defect (it landed on the shared
        // definition's `baseDurationMinutes`), so a flow that moved only the
        // price would leave that half unpinned.
        await enterFieldText(tester, const Key('pricing-fixed-amount'), '990');
        await enterFieldText(
          tester,
          const Key('field-service-duration'),
          '120',
        );

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('btn-submit-service')),
        );
        // Waits for the SAVE to complete (the edit screen pops), NOT for the
        // band counter: a regression that saves through the wrong endpoint
        // then fails on an assertion that NAMES the endpoint instead of on an
        // opaque 20-second timeout.
        await AppHarness.pumpUntilCondition(
          tester,
          () => find
              .byKey(const Key('service-edit-form-salon-assign-1'))
              .evaluate()
              .isEmpty,
          description: 'the edit screen to pop after a successful save',
          timeout: const Duration(seconds: 20),
        );

        // ── The write went to the PER-MASTER band ──────────────────────────
        expect(
          fb.updateMasterBandCalls,
          1,
          reason:
              'a salon master\'s price/duration is per-master state and must '
              'be written through PATCH /salons/{s}/masters/{m}/services/{d}',
        );
        expect(
          fb.lastBandPatchPath,
          '$_kSalonServicesUri/salon-def-1',
          reason: 'keyed on the DEFINITION id, never the assignment id',
        );
        expect(fb.lastBandPatchedServiceDefId, isNot('salon-assign-1'));

        final Map<String, dynamic> band = fb.lastBandPatchBody!;
        expect(band['price'], 990);
        expect(
          band['durationOverrideMinutes'],
          120,
          reason:
              'THE DURATION HALF — it must be the per-master OVERRIDE; '
              '`baseDurationMinutes` is the SHARED definition\'s duration and '
              'carried the identical cross-master defect',
        );
        expect(
          band.containsKey('baseDurationMinutes'),
          isFalse,
          reason: 'the shared duration key must not appear on the band body',
        );
        expect(
          band.containsKey('priceMin'),
          isFalse,
          reason:
              'the band endpoint has no `priceMin` field; a floor sent under '
              'that name is dropped and the master keeps their old price',
        );

        // ── The SHARED definition received identity ONLY ───────────────────
        expect(
          fb.patchSharedDefinitionPricedCalls,
          0,
          reason:
              'THE DATA-INTEGRITY ASSERTION — any money or time key on '
              'PATCH /api/v1/services/{defId} re-prices every other master '
              'in the salon',
        );
        expect(
          fb.patchSharedDefinitionCalls,
          greaterThanOrEqualTo(1),
          reason:
              'anti-vacuity — the identity half DID fire, so the zero above '
              'is "carried no price", not "never ran"',
        );
        final Map<String, dynamic> identity = fb.lastSharedDefinitionPatchBody!;
        expect(identity['name'], 'Нарощення нігтів');

        // ── The edit actually took effect for THIS master ──────────────────
        expect(
          fb.salonResolvedPrice('master-removable', 'salon-def-1'),
          990,
          reason:
              'anti-vacuity — a save that wrote nothing at all would satisfy '
              'every "untouched" assertion below',
        );
        expect(
          fb.salonResolvedDuration('master-removable', 'salon-def-1'),
          120,
        );

        // ── THE HARM: the other master is untouched ────────────────────────
        expect(
          fb.salonResolvedPrice('master-aaa', 'salon-def-1'),
          750,
          reason:
              'master A performs the SAME salon-owned service. Editing master '
              'B\'s band must not move A\'s price — the user-visible harm the '
              'phase-317 split exists to prevent',
        );
        expect(
          fb.salonResolvedDuration('master-aaa', 'salon-def-1'),
          90,
          reason: 'the same harm, through the duration half',
        );
        expect(
          fb.salonSharedDefinitionPrice('salon-def-1'),
          750,
          reason:
              'and the SHARED definition row itself is unchanged — the band '
              'write is per-master state, so the salon-wide band a future '
              'master would inherit must not have moved either',
        );

        // …and on A's own SCREEN, which is where a salon owner would see it.
        router.go(
          RouteNames.salonManageStaffServices(_kSalonId, _kMasterAaaMemberId),
        );
        await AppHarness.pumpUntilCondition(
          tester,
          () => fb.getSalonMasterAaaServicesCalls >= 1,
          description: 'master A\'s scoped list read to reach the wire',
          timeout: const Duration(seconds: 20),
        );
        final Finder nails = find.byKey(const Key('category_section_NAILS'));
        await AppHarness.pumpUntilFound(
          tester,
          nails,
          timeout: const Duration(seconds: 20),
        );
        final Finder sharedCard = find.byKey(
          const Key('service_card_salon-aaa-assign-shared'),
        );
        if (sharedCard.evaluate().isEmpty) {
          await AppHarness.tapVisible(tester, nails);
        }
        await AppHarness.pumpUntilFound(
          tester,
          sharedCard,
          timeout: const Duration(seconds: 20),
        );
        expect(
          find.descendant(of: sharedCard, matching: find.text('750 ₴')),
          findsOneWidget,
          reason:
              'master A\'s card still renders A\'s own price — the server-'
              'formatted priceDisplay, not a localised string',
        );
        expect(
          find.descendant(of: sharedCard, matching: find.text('990 ₴')),
          findsNothing,
          reason: 'master B\'s new price must never appear on A\'s card',
        );
      });
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
