// Mobile phase 319 — E2E: the salon-target UNASSIGN journey, both outcomes,
// against a real app boot.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — user-flow coverage)
// -----------------------------------------------------------
// Phase 316/317 wired the salon-target UNASSIGN dispatch and its routes;
// `salon_master_services_target_flow_test.dart` already proves the happy
// path end to end (arm 1 below mirrors it, unchanged, as the anchor the
// refusal arm contrasts against). What neither that file nor any unit test
// covers is what phase 319 actually adds: the REACTIVE 409 refusal —
// `DeleteServiceDialog(blocked: true)` re-shown, no optimistic removal, no
// navigation to the blocking bookings — and the INDEPENDENT_MASTER control
// arm proving the blocked dialog can never appear on a path that can never
// receive this 409 in the first place (backend phase 307 D4: the refusal
// only exists on the salon-scoped endpoint).
//
// WHAT THE THREE FLOWS PIN
// ------------------------
//  1. HAPPY PATH — owner opens a master's services, deletes one, confirms:
//     the wire carries DELETE /api/v1/salons/{S}/masters/{M}/services/{defId}
//     (never DELETE /services/{defId} — the phase 316 guarantee), the screen
//     pops, and the service is gone from the refreshed list.
//  2. THE REFUSAL — the identical journey against a fake backend answering
//     409: the blocked dialog renders with `deleteServiceBlockedTitle`, the
//     edit screen stays open, and the service is STILL IN THE LIST after
//     dismissing (asserted on the LIST's contents, not merely "no crash").
//  3. CONTROL — an INDEPENDENT_MASTER deleting their own service still hits
//     DELETE /api/v1/services/{defId} and never renders the blocked dialog —
//     this 409 has no route to that persona at all.
//
// FIXTURES REUSED FROM salon_master_services_target_flow_test.dart
// ------------------------------------------------------------------
// Same salon (`salon-xyz`), same roster member (`user-master-removable` /
// `master-removable`), same seeded rows (`salon-assign-1` / `salon-def-1`,
// surviving sibling `salon-assign-2`) — deliberately reused rather than
// re-invented, so this file measures ONLY the outcome split (204 vs 409),
// not a different fixture shape.
//
// TIMING: never `pumpAndSettle`/`AppHarness.settle` after a deep link or a
// dialog action — the list screen runs staggered card entrance animations
// and the edit screen a 1000 ms entrance. Every wait is
// `AppHarness.pumpUntilFound` / `pumpUntilCondition` (bounded, real wall
// clock).
//
// KEY POLICY: navigation taps use key-based finders only (see app_harness.dart).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
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

/// The `masters` ROW id the route builder resolves from [_kMemberUserId].
const String _kMasterRowId = 'master-removable';

/// The salon-scoped list endpoint the repository emits under the target.
const String _kSalonServicesUri =
    '/api/v1/salons/$_kSalonId/masters/$_kMasterRowId/services';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Boots as a SALON_OWNER who owns [_kSalonId] and lands on the salon shell.
  ///
  /// `salon-xyz` is not in the owner persona's default `mySalons`, so it is
  /// seeded BEFORE boot — otherwise `salonManageGuard`'s owner arm bounces
  /// the deep link.
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

  /// Deep-links to the master's «Послуги» leaf and waits for [card] to render.
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

  /// Opens the salon-master's «Послуги» list and pushes `salon-assign-1`'s
  /// edit screen through the CARD (not `router.go(...edit)`): the card's
  /// «Редагувати» uses `context.push`, which is what gives the delete's
  /// `_popServiceEditScreen` a real route to pop.
  Future<void> openSalonMasterServiceEdit(
    WidgetTester tester,
    GoRouter router,
  ) async {
    final Finder salonCard = find.byKey(
      const Key('service_card_salon-assign-1'),
    );
    await deepLinkToSalonMasterServices(tester, router, card: salonCard);
    await AppHarness.tapVisible(tester, salonCard);
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('service-edit-form-salon-assign-1')),
      timeout: const Duration(seconds: 20),
    );
  }

  // ── 1. Happy path — DELETE unassigns on the salon-scoped wire ────────────

  testWidgets(
    'owner opens a master\'s services, deletes one, confirms: the wire '
    'carries /salons/S/masters/M/services/{defId}, the screen pops, and the '
    'service is gone from the list',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend();
        final GoRouter router = await bootAsOwnerOfSalonXyz(tester, fb);

        await openSalonMasterServiceEdit(tester, router);

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
          description: 'DELETE /salons/S/masters/M/services/{defId}',
          timeout: const Duration(seconds: 20),
        );

        expect(fb.unassignServiceCalls, 1);
        expect(fb.lastUnassignPath, '$_kSalonServicesUri/salon-def-1');
        // THE phase-316 guarantee this flow's success arm anchors: the
        // shared-definition destroy never fires under a salon target.
        expect(
          fb.deleteServiceCalls,
          0,
          reason:
              'a salon-target unassign must never fire DELETE '
              '/api/v1/services/{defId} — that destroys the SHARED '
              'definition for every master who performs it',
        );

        // Screen pops back to the list leaf, refreshed.
        await AppHarness.pumpUntilCondition(
          tester,
          () =>
              AppHarness.nestedPushLocation(router) ==
              RouteNames.salonManageStaffServices(_kSalonId, _kMemberUserId),
          description: 'the edit screen to pop back to the salon list leaf',
          timeout: const Duration(seconds: 20),
        );
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
        expect(survivor, findsOneWidget);
      });
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ── 2. The refusal — 409 re-shows the dialog blocked, nothing is removed ──

  testWidgets(
    'a 409 on unassign re-shows the dialog blocked, keeps the edit screen '
    'open, and the service is STILL in the list after dismissing',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..unassignServiceBlocked = true;
        final GoRouter router = await bootAsOwnerOfSalonXyz(tester, fb);

        await openSalonMasterServiceEdit(tester, router);

        // Resolved from the EDIT FORM's own context — it stays mounted for
        // the whole test (a refusal never pops it) — rather than from the
        // dialog, whose Key transiently matches TWO widgets while the
        // confirmation dialog animates out as the blocked one animates in.
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(
            find.byKey(const Key('service-edit-form-salon-assign-1')),
          ),
        );

        expect(fb.unassignServiceCalls, 0);

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
          description: 'the 409 unassign attempt to reach the wire',
          timeout: const Duration(seconds: 20),
        );
        expect(fb.unassignServiceCalls, 1);

        // The blocked dialog re-appears with the blocked title — waited for
        // via the (unambiguous) TEXT rather than the dialog Key, which
        // transiently matches BOTH the outgoing confirmation dialog and the
        // incoming blocked one while the route transition animates.
        await AppHarness.pumpUntilFound(
          tester,
          find.text(l10n.deleteServiceBlockedTitle),
          timeout: const Duration(seconds: 20),
        );
        // Let the route transition finish settling to exactly ONE dialog in
        // the tree before asserting the absence of its confirm button — mid
        // transition the outgoing dialog's own confirm button can still be
        // present for a few frames.
        await AppHarness.pumpUntilCondition(
          tester,
          () =>
              find
                  .byKey(const Key('delete-service-dialog'))
                  .evaluate()
                  .length ==
              1,
          description:
              'the dialog route transition to finish (one dialog left)',
          timeout: const Duration(seconds: 20),
        );
        expect(
          find.byKey(const Key('btn-confirm-delete-service')),
          findsNothing,
          reason: 'the blocked variant offers nothing to confirm',
        );

        // Nothing was written: no shared-definition destroy either.
        expect(fb.deleteServiceCalls, 0);

        // The edit screen never popped — still mounted underneath the dialog.
        expect(
          find.byKey(const Key('service-edit-form-salon-assign-1')),
          findsOneWidget,
          reason: 'a refusal must not pop the edit screen',
        );

        // Dismiss the blocked dialog via its sole action (the shared cancel
        // key) and confirm the row SURVIVES in the list — asserted on the
        // list's actual contents, not merely "no crash".
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('btn-cancel-delete-service')),
        );
        await AppHarness.pumpUntilGone(
          tester,
          find.byKey(const Key('delete-service-dialog')),
        );
        expect(
          find.byKey(const Key('service-edit-form-salon-assign-1')),
          findsOneWidget,
          reason:
              'the edit screen is still there — the refusal is final, '
              'not a retry prompt',
        );

        // Back on the list leaf via the top bar's own cancel affordance (the
        // same route users actually take — not a programmatic router.pop()):
        // the row is STILL there — no optimistic removal happened anywhere
        // in the refusal path.
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('btn-cancel-service-edit')),
        );
        final Finder untouchedCard = find.byKey(
          const Key('service_card_salon-assign-1'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          untouchedCard,
          timeout: const Duration(seconds: 20),
        );
        expect(untouchedCard, findsOneWidget);
        expect(
          find.byKey(const Key('service_card_salon-assign-2')),
          findsOneWidget,
          reason: 'anti-vacuity — the sibling row still renders too',
        );
      });
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ── 3. CONTROL — INDEPENDENT_MASTER never receives this 409 at all ───────

  testWidgets('CONTROL: an INDEPENDENT_MASTER deleting their own service hits '
      'DELETE /services/{defId} and never renders the blocked dialog', (
    tester,
  ) async {
    // unassignServiceBlocked has NO effect on the independent-master path
    // — it only guards the salon-scoped endpoint — but set it anyway so a
    // future regression that accidentally routed this persona through the
    // salon dispatch would trip this control, not silently pass.
    final fb = FakeBackend()..unassignServiceBlocked = true;
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

    router.go(RouteNames.services);
    final Finder card = find.byKey(const Key('service_card_assign-1'));
    final Finder nails = find.byKey(const Key('category_section_NAILS'));
    await AppHarness.pumpUntilFound(tester, nails);
    if (card.evaluate().isEmpty) {
      await AppHarness.tapVisible(tester, nails);
    }
    await AppHarness.pumpUntilFound(tester, card);
    await AppHarness.tapVisible(tester, card);
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('service-edit-form-assign-1')),
    );

    expect(fb.deleteServiceCalls, 0);
    expect(fb.unassignServiceCalls, 0);

    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('btn-delete-service')),
    );
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('delete-service-dialog')),
    );
    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('btn-confirm-delete-service')),
    );
    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.deleteServiceCalls >= 1,
      description: 'DELETE /api/v1/services/{serviceDefId} to reach the wire',
    );

    expect(
      fb.deleteServiceCalls,
      1,
      reason:
          'the null-target path must still hit the definition-scoped '
          'DELETE, never the salon-scoped unassign',
    );
    expect(
      fb.unassignServiceCalls,
      0,
      reason:
          'the salon-scoped endpoint carrying the 409 flag was never even '
          'reachable from this persona',
    );

    // The screen popped on the plain 204 success — no blocked dialog was
    // ever shown (it would still be here, blocking the pop, if it had).
    await AppHarness.pumpUntilCondition(
      tester,
      () => AppHarness.location(router) == RouteNames.services,
      description: 'the edit screen to pop back to /services',
    );
    expect(find.byKey(const Key('delete-service-dialog')), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
