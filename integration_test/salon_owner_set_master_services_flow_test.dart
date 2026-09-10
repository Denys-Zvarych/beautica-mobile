// Phase 318 — E2E: the «Послуги» roster tile end to end, driven by a REAL
// tap chain, not a deep link.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — user-flow coverage)
// -----------------------------------------------------------
// Phase 317's own E2E (`salon_master_services_target_flow_test.dart`) proves
// the scoped `ShellRoute`'s GET/DELETE wiring via `router.go(...)` straight to
// the salon-target `/services` leaf — deliberately, because the tile to TAP
// into it did not exist yet. Phase 318 adds exactly that tile
// (`salon-staff-profile-services-row`), and the widget tier
// (`test/features/salon/presentation/salon_staff_profile_screen_test.dart`)
// proves its render/guard/nav/D4-refresh contract against a hand-built router
// and a lightweight marker screen — NOT the real `ServicesListScreen`, NOT a
// real roster, NOT a real bulk-create write.
//
// This file is the one place that drives the REAL journey: login → the real
// «Персонал» tab → a real roster card → the real `SettingsRow` this phase
// adds → a real push into the REAL `ServicesListScreen`/`ServiceSetupScreen`
// pair phase 317 wired → a real bulk POST → a real pop → the REAL D4
// invalidate → the REAL stat tile reading the refetched count.
//
// WHAT THE FOUR REQUIRED CASES PIN, AND WHY THEY CANNOT PASS VACUOUSLY
// ----------------------------------------------------------------------
//  1. THE READ REACHES THE RIGHT WIRE. Tapping «Послуги» on `master-removable`
//     (roster `userId` `user-master-removable`, DIFFERENT from its `masters`
//     row id — unlike `master-aaa`, whose two ids are identical and so cannot
//     catch a swap, `project_fixture_values_can_defang_assertions`) must land
//     on `ServicesListScreen` with a GET that carried the master ROW id, never
//     the roster userId.
//  2. THE FAB REACHES THE SALON BULK PATH. Selecting a type, filling
//     duration+price and saving must POST to
//     `/salons/{s}/masters/{m}/services/bulk` — the endpoint phase 315 D2
//     dispatches to for a `SalonMasterTarget` — never the independent-master
//     path, and the new card must render on return.
//  3. D4 END TO END. Popping back to the staff profile must show the
//     INCREASED count — a REFETCH, never a retained stale value
//     (`project_riverpod_seamless_invalidate_gotcha`; the widget tier already
//     mutation-probes the refetch mechanism against a fake provider — this is
//     that mechanism proven against the REAL wire).
//  4. THE CONTROL. An `INDEPENDENT_MASTER`'s IDENTICAL journey from
//     `/services` must still hit `/independent-masters/me/services` and
//     `…/me/services/bulk`. Without this arm a bug that pointed BOTH roles at
//     the salon path would pass case 1+2 above (a root-resolved repository
//     under a salon target would coincidentally 404, not silently succeed —
//     but a HARD-CODED salon target on the independent path would silently
//     wreck a real master's session, and only this arm would catch it).
//
// THE FIFTH CASE — closing the inherited MEDIUM (backlog row 802 / phase 317)
// -----------------------------------------------------------------------------
// `salonStaffMemberProfileProvider` resolves the roster member's services
// through the PUBLIC `GET /masters/{id}/services` — an endpoint
// `invalidateMasterServiceCatalogues` has never touched, and a DIFFERENT read
// path from the salon-scoped `GET /salons/{s}/masters/{m}/services` the
// `ServicesListScreen` subtree itself uses. D4's invalidate is what closes the
// gap: it does not depend on the subtree's own cache-eviction fan-out at
// all — it directly invalidates `salonStaffMemberProfileProvider` on every
// return from the subtree, add OR unassign alike. This file's fake backend
// was widened (mobile-qa) so the public per-master read mirrors the SAME
// live list the salon-scoped one serves — the exact pairing a real backend's
// two reads would share, and the pairing a static empty stub made
// structurally untestable. Chained onto the SAME journey as cases 1-3:
// unassign one of the two originally-seeded rows inside the subtree, pop, and
// assert the staff-profile count MOVED DOWN — the direct evidence the phase
// 318 doc asks for to close backlog row 802.
//
// TIMING: never bare `pumpAndSettle()` on this screen family —
// `salon_owner_edit_master_schedule_flow_test.dart`'s own header records it
// stalling reproducibly on the staff-profile screen's staggered
// `RevealTransition`s (bisected repeatedly, root cause not isolated). Every
// wait here is `AppHarness.pumpUntilFound`/`pumpUntilCondition` (bounded, real
// wall-clock) or a bounded fixed-count pump loop, mirroring that file and
// `service_append_flow_test.dart` (the FAB→setup→submit recipe).
//
// KEY POLICY: navigation taps use key-based finders only
// (`app_harness.dart`'s policy). No `find.text(cyrillic)` anywhere in this
// file — content is proven via widget/card KEYS and via wire-call counters,
// never localized copy.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_staff_profile_screen.dart';
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
/// A DIFFERENT string, which is the whole point (see file header, case 1).
const String _kMasterRowId = 'master-removable';

const String _kSalonServicesUri =
    '/api/v1/salons/$_kSalonId/masters/$_kMasterRowId/services';
const String _kSalonBulkUri = '$_kSalonServicesUri/bulk';

/// A NAILS-category service type. Neither seeded row on `master-removable`
/// (`salon-def-1`/`salon-def-2`) carries a `serviceTypeId`, so this type
/// renders selectable with no ownership exclusion in play.
const String _kFreeTypeId = 'type-nails-gel';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Bounded lockstep pump standing in for `pumpAndSettle`/`AppHarness.settle`
  /// on this screen family — see file header TIMING note.
  Future<void> lockstepPump(
    WidgetTester tester, {
    int times = 3,
    Duration step = const Duration(milliseconds: 300),
  }) async {
    for (var i = 0; i < times; i++) {
      // fixed-wait-ok: bounded lockstep pump — see file header TIMING note
      // and `salon_owner_edit_master_schedule_flow_test.dart`'s identical
      // precedent for this exact screen family.
      await tester.pump(step);
    }
  }

  Future<void> tapWhenReady(WidgetTester tester, Finder finder) async {
    try {
      await tester.ensureVisible(finder);
    } catch (_) {
      // Not yet laid out — pumpUntilFound below still gates on readiness.
    }
    await AppHarness.pumpUntilFound(
      tester,
      finder.hitTestable(),
      timeout: const Duration(seconds: 20),
    );
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets(
    'SALON_OWNER: roster -> «Послуги» -> the real salon-scoped list -> FAB '
    'add -> D4 refresh -> unassign -> D4 refresh again (backlog row 802)',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend();
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

        router.go(RouteNames.salonShell(_kSalonId));
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('salon-nav-tile-2')),
          timeout: const Duration(seconds: 20),
        );

        // ── «Персонал» tab -> the real roster grid ──────────────────────
        await tapWhenReady(tester, find.byKey(const Key('salon-nav-tile-2')));

        final Finder masterCard = find.byKey(
          const Key('salon-manage-staff-card-$_kMemberUserId'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          masterCard,
          timeout: const Duration(seconds: 20),
        );
        await tapWhenReady(tester, masterCard);

        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonStaffProfileScreen),
          timeout: const Duration(seconds: 20),
        );

        // ── 1. THE PHASE 318 ROW -> the real salon-scoped list ──────────
        final Finder servicesRow = find.byKey(
          const Key('salon-staff-profile-services-row'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          servicesRow,
          timeout: const Duration(seconds: 20),
        );
        // Drain the six staggered RevealTransitions off this screen's one
        // 950ms AnimationController — see file header TIMING note.
        await lockstepPump(tester);
        await tapWhenReady(tester, servicesRow);

        await AppHarness.pumpUntilFound(
          tester,
          find.byType(ServicesListScreen),
          timeout: const Duration(seconds: 20),
        );

        final int ownCallsBefore = fb.getServicesCalls;
        expect(
          fb.getSalonMasterServicesCalls,
          greaterThanOrEqualTo(1),
          reason:
              'the tap must reach the scoped salon-target read, not merely '
              'render an empty/loading screen',
        );
        expect(
          fb.lastSalonMasterServicesPath,
          _kSalonServicesUri,
          reason:
              'the master ROW id must be on the wire, never the roster '
              'userId — the whole point of using master-removable here',
        );
        expect(
          fb.getServicesCalls,
          ownCallsBefore,
          reason:
              'GET /independent-masters/me/services is what a ROOT-resolved '
              'repository would have called — the silent release-mode '
              'failure mode phase 317 exists to prevent',
        );

        final Finder nails = find.byKey(const Key('category_section_NAILS'));
        await AppHarness.pumpUntilFound(
          tester,
          nails,
          timeout: const Duration(seconds: 20),
        );
        final Finder card1 = find.byKey(
          const Key('service_card_salon-assign-1'),
        );
        if (card1.evaluate().isEmpty) {
          await tapWhenReady(tester, nails);
        }
        await AppHarness.pumpUntilFound(
          tester,
          card1,
          timeout: const Duration(seconds: 20),
        );
        expect(card1, findsOneWidget);
        expect(
          find.byKey(const Key('service_card_salon-assign-2')),
          findsOneWidget,
        );

        // ── 2. FAB -> ServiceSetupScreen -> pick a type -> submit ────────
        final Finder fab = find.byKey(const Key('btn-create-service'));
        await AppHarness.pumpUntilFound(
          tester,
          fab,
          timeout: const Duration(seconds: 20),
        );
        await tapWhenReady(tester, fab);
        await lockstepPump(tester);

        final Finder setupClose = find.byKey(const Key('btn-setup-close'));
        await AppHarness.pumpUntilFound(
          tester,
          setupClose,
          timeout: const Duration(seconds: 20),
        );

        final Finder nailsChip = find.byKey(
          const ValueKey<String>('cat_NAILS'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          nailsChip,
          timeout: const Duration(seconds: 20),
        );
        await tapWhenReady(tester, nailsChip);

        final Finder freeRow = find.byKey(const Key('setup_row_$_kFreeTypeId'));
        await AppHarness.pumpUntilFound(
          tester,
          freeRow,
          timeout: const Duration(seconds: 20),
        );
        final Finder freeToggle = find.byKey(
          const Key('setup_row_toggle_$_kFreeTypeId'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          freeToggle,
          timeout: const Duration(seconds: 20),
        );
        await tapWhenReady(tester, freeToggle);

        final Finder durationField = find.descendant(
          of: freeRow,
          matching: find.byKey(const Key('service-setup-duration')),
        );
        final Finder priceField = find.descendant(
          of: freeRow,
          matching: find.byKey(const Key('pricing-fixed-amount')),
        );
        await AppHarness.pumpUntilFound(
          tester,
          durationField,
          timeout: const Duration(seconds: 20),
        );
        await AppHarness.pumpUntilFound(
          tester,
          priceField,
          timeout: const Duration(seconds: 20),
        );
        await tester.enterText(durationField, '45');
        await tester.pump();
        await tester.enterText(priceField, '350');
        await tester.pump();

        final Finder saveBtn = find.byKey(const Key('btn-setup-save'));
        await tapWhenReady(tester, saveBtn);

        // DIAGNOSE AT THE CAUSE — the POST reaching the wire before its path.
        await AppHarness.pumpUntilCondition(
          tester,
          () => fb.salonBulkCreateCalls >= 1,
          description:
              'the salon-scoped bulk POST to reach the fake backend — if it '
              'never does, the save was blocked client-side',
          timeout: const Duration(seconds: 20),
        );
        expect(
          fb.lastSalonBulkPath,
          _kSalonBulkUri,
          reason:
              'phase 315 D2 — a SalonMasterTarget must dispatch bulkCreate '
              'to /salons/{s}/masters/{m}/services/bulk, never the '
              'independent-master path',
        );
        expect(
          fb.bulkCreateCalls,
          0,
          reason:
              'the independent-master bulk endpoint must NEVER fire for a '
              'salon-scoped save — that is what a root-resolved repository '
              'would have called',
        );

        // Screen pops (awaits the push), landing back on the list WITH the
        // new card.
        await AppHarness.pumpUntilGone(
          tester,
          find.byKey(const Key('btn-setup-close')),
          timeout: const Duration(seconds: 20),
        );
        final Finder newCard = find.byKey(
          const Key('service_card_salon-assign-bulk-1'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          newCard,
          timeout: const Duration(seconds: 20),
        );
        expect(newCard, findsOneWidget);

        // ── 3. Pop back to the staff profile -> D4 refresh (count UP) ────
        final int getSalonCallsBeforePop = fb.getSalonMasterServicesCalls;
        final int getPublicCallsBeforePop = fb.getPublicMasterServicesCalls;
        router.pop();
        await lockstepPump(tester);

        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonStaffProfileScreen),
          timeout: const Duration(seconds: 20),
        );
        final Finder statValue = find.byKey(
          const Key('salon-staff-profile-services-value'),
        );
        await AppHarness.pumpUntilCondition(
          tester,
          () =>
              statValue.evaluate().isNotEmpty &&
              (tester.widget<Text>(statValue).data == '3'),
          description:
              'the stat tile to show the REFETCHED count (3) after D4\'s '
              'invalidate — the public /masters/{id}/services read must have '
              'fired again',
          timeout: const Duration(seconds: 20),
        );
        expect(
          fb.getPublicMasterServicesCalls,
          greaterThan(getPublicCallsBeforePop),
          reason:
              'D4 — popping the subtree must trigger a genuine REFETCH of '
              'salonStaffMemberProfileProvider, never merely retain the '
              'stale .value (project_riverpod_seamless_invalidate_gotcha)',
        );
        // Anti-vacuity for the salon-scoped counter: it must NOT have been
        // touched again by the pop itself — only the PUBLIC read backs this
        // screen (D3/D4's own doc — no second fetch of the salon-scoped
        // list here).
        expect(fb.getSalonMasterServicesCalls, getSalonCallsBeforePop);

        // ── 4. Back into the subtree -> unassign -> pop -> D4 (count DOWN)
        // Closes the inherited MEDIUM, backlog row 802: the staff-profile
        // read is a DIFFERENT endpoint from the one the subtree unassign
        // itself invalidates, so this is the direct "count moved" evidence
        // the phase 318 doc asks for.
        await tapWhenReady(tester, servicesRow);
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(ServicesListScreen),
          timeout: const Duration(seconds: 20),
        );

        // Re-entering pushes a FRESH ShellRoute match (phase 317 D2 — "scope
        // unwinds on pop"), so the NAILS section is COLLAPSED again — expand
        // it before looking for either card.
        final Finder nailsAgain = find.byKey(
          const Key('category_section_NAILS'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          nailsAgain,
          timeout: const Duration(seconds: 20),
        );
        final Finder survivorCard = find.byKey(
          const Key('service_card_salon-assign-1'),
        );
        if (survivorCard.evaluate().isEmpty) {
          await tapWhenReady(tester, nailsAgain);
        }
        await AppHarness.pumpUntilFound(
          tester,
          survivorCard,
          timeout: const Duration(seconds: 20),
        );

        final Finder toUnassign = find.byKey(
          const Key('service_card_salon-assign-2'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          toUnassign,
          timeout: const Duration(seconds: 20),
        );
        await tapWhenReady(tester, toUnassign);
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('service-edit-form-salon-assign-2')),
          timeout: const Duration(seconds: 20),
        );

        await tapWhenReady(tester, find.byKey(const Key('btn-delete-service')));
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('delete-service-dialog')),
          timeout: const Duration(seconds: 20),
        );
        final int unassignCallsBefore = fb.unassignServiceCalls;
        await tapWhenReady(
          tester,
          find.byKey(const Key('btn-confirm-delete-service')),
        );
        await AppHarness.pumpUntilCondition(
          tester,
          () => fb.unassignServiceCalls > unassignCallsBefore,
          description: 'the unassign DELETE to reach the fake backend',
          timeout: const Duration(seconds: 20),
        );
        expect(fb.lastUnassignedServiceDefId, 'salon-def-2');

        // Back to the list leaf, then all the way out to the staff profile.
        await AppHarness.pumpUntilGone(
          tester,
          find.byKey(const Key('service-edit-form-salon-assign-2')),
          timeout: const Duration(seconds: 20),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(ServicesListScreen),
          timeout: const Duration(seconds: 20),
        );

        final int getPublicCallsBeforeSecondPop =
            fb.getPublicMasterServicesCalls;
        router.pop();
        await lockstepPump(tester);
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonStaffProfileScreen),
          timeout: const Duration(seconds: 20),
        );

        await AppHarness.pumpUntilCondition(
          tester,
          () =>
              statValue.evaluate().isNotEmpty &&
              (tester.widget<Text>(statValue).data == '2'),
          description:
              'THE BACKLOG-802 ASSERTION — the staff-profile count must move '
              'DOWN from 3 to 2 after an unassign performed inside the '
              'subtree, proving D4\'s invalidate reaches the PUBLIC read '
              'this screen renders from, not merely the salon-scoped one the '
              'subtree itself evicts',
          timeout: const Duration(seconds: 20),
        );
        expect(
          fb.getPublicMasterServicesCalls,
          greaterThan(getPublicCallsBeforeSecondPop),
          reason: 'anti-vacuity — the count moved BECAUSE of a real refetch',
        );
      });
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // ── CONTROL: an INDEPENDENT_MASTER's own /services journey is unchanged ──

  testWidgets(
    'CONTROL — INDEPENDENT_MASTER: the identical FAB->setup->submit journey '
    'still hits /independent-masters/me/services and …/me/services/bulk, '
    'never the salon path',
    (tester) async {
      final fb = FakeBackend();
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      AppHarness.expectLocation(router, RouteNames.masterProfile);

      router.go(RouteNames.services);
      final Finder fab = find.byKey(const Key('btn-create-service'));
      await AppHarness.pumpUntilFound(
        tester,
        fab,
        timeout: const Duration(seconds: 20),
      );

      final int ownCallsBefore = fb.getServicesCalls;
      expect(
        fb.getSalonMasterServicesCalls,
        0,
        reason: 'no salon target is in play for this persona at all',
      );
      expect(ownCallsBefore, greaterThanOrEqualTo(1));

      await tapWhenReady(tester, fab);
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('btn-setup-close')),
        timeout: const Duration(seconds: 20),
      );

      final Finder nailsChip = find.byKey(const ValueKey<String>('cat_NAILS'));
      await AppHarness.pumpUntilFound(
        tester,
        nailsChip,
        timeout: const Duration(seconds: 20),
      );
      await tapWhenReady(tester, nailsChip);

      // `type-nails-gel` is the NON-owned type for the independent master's
      // OWN seeded catalogue too (see `service_append_flow_test.dart`), so
      // the same type id is reusable as this control's row.
      final Finder freeRow = find.byKey(const Key('setup_row_$_kFreeTypeId'));
      await AppHarness.pumpUntilFound(
        tester,
        freeRow,
        timeout: const Duration(seconds: 20),
      );
      final Finder freeToggle = find.byKey(
        const Key('setup_row_toggle_$_kFreeTypeId'),
      );
      await AppHarness.pumpUntilFound(
        tester,
        freeToggle,
        timeout: const Duration(seconds: 20),
      );
      await tapWhenReady(tester, freeToggle);

      final Finder durationField = find.descendant(
        of: freeRow,
        matching: find.byKey(const Key('service-setup-duration')),
      );
      final Finder priceField = find.descendant(
        of: freeRow,
        matching: find.byKey(const Key('pricing-fixed-amount')),
      );
      await AppHarness.pumpUntilFound(
        tester,
        durationField,
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.pumpUntilFound(
        tester,
        priceField,
        timeout: const Duration(seconds: 20),
      );
      await tester.enterText(durationField, '30');
      await tester.pump();
      await tester.enterText(priceField, '200');
      await tester.pump();

      await tapWhenReady(tester, find.byKey(const Key('btn-setup-save')));

      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.bulkCreateCalls >= 1,
        description: 'the INDEPENDENT-MASTER bulk POST to reach the wire',
        timeout: const Duration(seconds: 20),
      );

      expect(
        fb.salonBulkCreateCalls,
        0,
        reason:
            'THE CONTROL ASSERTION — a bug pointing BOTH roles at the salon '
            'bulk path would pass every salon-owner assertion in this file '
            'and only show up here',
      );
      expect(
        fb.getSalonMasterServicesCalls,
        0,
        reason: 'the salon-scoped read must never fire for this persona',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
