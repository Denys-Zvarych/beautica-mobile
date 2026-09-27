// Mobile phase 316 — E2E: the INDEPENDENT-MASTER service DELETE journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — user-flow coverage)
// -----------------------------------------------------------
// Phase 316 dispatches `HttpServiceRepository.deactivate()` on the
// `serviceTarget`: with a `SalonMasterTarget` in scope it now issues the
// per-master UNASSIGN (`DELETE /salons/{s}/masters/{m}/services/{defId}`)
// instead of deactivating the shared salon definition. Its CENTRAL CLAIM is
// the other arm — that with a `null` target the shipped independent-master
// journey still fires `DELETE /api/v1/services/{serviceDefId}`, byte-identical
// to before, and that `service_edit_screen.dart` needed no edit for the
// retarget.
//
// Until this file, that claim rested on unit tests alone: verified by
// `grep -a -rn "deactivate" integration_test/`, NO integration flow exercised
// service delete at all, and `support/fake_backend.dart` had no
// `DELETE /services/{id}` handler. Phase 316's own "Test scope" section named
// `integration_test/services_flow_test.dart` as the proof — a file that does
// not exist. This closes that gap.
//
// THE SALON ARM HAS NO E2E COUNTERPART YET, DELIBERATELY
// ------------------------------------------------------
// No salon service UI exists before phase 317, and `serviceTargetProvider` is
// never overridden anywhere in `lib/` — `serviceTarget(Ref) => null` is the
// only value production ever produces (verified by grep, not assumed). There
// is no screen to drive and no route that would put a `SalonMasterTarget` in
// scope, so a salon E2E here could only be a skip-marked placeholder pinning
// nothing. The salon unassign journey is authored in phase 319, where the
// blocked-delete dialog gives it something to drive.
//
// WHAT THE THREE FLOWS PIN
// ------------------------
//  1. HAPPY PATH — open the list, open a service, delete it, confirm. Asserts
//     the DELETE reached the fake backend on the NULL-TARGET path keyed on the
//     DEFINITION id (`svc-1`, never the assignment id `assign-1`), that the
//     screen popped, and that the refreshed list no longer renders the card
//     while its category siblings still do.
//  2. DOUBLE-TAP GUARD — `_ServiceEditScreenState._deleting` (phase 316,
//     mobile-perf LOW). A second tap while the DELETE is in flight must issue
//     NO second DELETE and open NO second dialog: the second call would 404
//     ("already gone") and raise an error snackbar for an operation that
//     SUCCEEDED.
//  3. TRIMMED INVALIDATION FAN-OUT — `ref.invalidate(masterProfileProvider)`
//     was removed from BOTH the delete and the save path (phase 316,
//     mobile-perf MEDIUM + LOW). Neither write may produce a
//     `GET /api/v1/masters/me`, while the services catalogue re-fetch it
//     REPLACES must still fire.
//
// HARNESS
// -------
// Reuses the shared AppHarness + FakeBackend. FakeBackend gained (additively)
// a stateful `DELETE /api/v1/services/{serviceDefId}` handler following the
// `DELETE /salons/salon-xyz` precedent — it counts the call, records the id,
// and REMOVES the row from `_services` so the follow-up GET reflects it.
// Without that removal a post-delete "the card is gone" assertion could not
// distinguish a correct refresh from a broken one.
//
// KEY POLICY: navigation taps use key-based finders only (see app_harness.dart).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Waits for the /services list, expands the NAILS section if needed, and
  /// returns once [card] is in the tree.
  ///
  /// Sections start COLLAPSED (`initiallyExpanded` is false with no target
  /// slug), so no card is in the tree until its section is expanded — AND the
  /// expansion does NOT survive a catalogue invalidation: the list drops
  /// through `AsyncLoading` into the skeleton, which unmounts every
  /// `CategorySection`, so the rebuilt ones come back collapsed. Hence the
  /// conditional tap rather than an unconditional one, which would toggle a
  /// still-expanded section shut.
  Future<void> expandNailsUntil(WidgetTester tester, Finder card) async {
    final Finder nailsSection = find.byKey(const Key('category_section_NAILS'));
    await AppHarness.pumpUntilFound(tester, nailsSection);
    if (card.evaluate().isEmpty) {
      await AppHarness.tapVisible(tester, nailsSection);
    }
    await AppHarness.pumpUntilFound(tester, card);
  }

  /// Drives /services → expand NAILS → open one seeded service's edit screen.
  ///
  /// Goes through the LIST rather than `router.go(serviceEdit(...))` on
  /// purpose: `_openAndRefresh` uses `context.push`, so the delete's
  /// `_popServiceEditScreen` has a real route to POP (its `canPop()` branch —
  /// the shipped path). A `router.go` entry leaves nothing to pop and
  /// `Navigator.maybePop` would silently no-op, so the flow would assert the
  /// pop against a code path users never take.
  Future<void> openSeededServiceEdit(
    WidgetTester tester,
    GoRouter router, {
    String assignmentId = 'assign-1',
  }) async {
    router.go(RouteNames.services);
    final Finder card = find.byKey(Key('service_card_$assignmentId'));
    await expandNailsUntil(tester, card);
    await AppHarness.tapVisible(tester, card);
    // Pump UNTIL the edit form mounts rather than for a guessed duration: the
    // screen runs a 1000 ms entrance animation and its category picker holds
    // an infinite CircularProgressIndicator while loading, so `pumpAndSettle`
    // can never observe "no frames scheduled" — but the form key IS a real
    // state to wait for.
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(Key('service-edit-form-$assignmentId')),
    );
  }

  // ── 1. Happy path — the DELETE fires on the null-target definition path ───

  testWidgets(
    'INDEPENDENT_MASTER deletes a service: DELETE /services/{serviceDefId} '
    'fires on the null-target path, the screen pops, and the refreshed list '
    'no longer renders the card',
    (tester) async {
      final fb = FakeBackend();
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      await openSeededServiceEdit(tester, router);
      AppHarness.expectLocation(router, '/services/assign-1/edit');
      expect(
        find.byKey(const Key('service-edit-form-assign-1')),
        findsOneWidget,
        reason: 'the edit form must be mounted before the delete is driven',
      );

      // Baselines captured immediately BEFORE the write, so login/profile
      // traffic cannot be mistaken for fan-out (see flow 3's assertions).
      final int servicesCallsBefore = fb.getServicesCalls;
      final int masterCallsBefore = fb.getMasterCalls;
      expect(fb.deleteServiceCalls, 0, reason: 'nothing deleted yet');

      // Delete icon → confirmation dialog → confirm.
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

      // THE phase-316 assertion. `deactivate()` dispatched on a NULL target,
      // so the shipped definition-scoped endpoint fired — exactly once.
      expect(
        fb.deleteServiceCalls,
        1,
        reason:
            'a null target must still hit DELETE /api/v1/services/{defId}; '
            'a SalonMasterTarget dispatch here would have gone to '
            '/salons/{s}/masters/{m}/services/{defId} and this route would '
            'never have matched, leaving the counter at 0',
      );
      // The id on the wire is the DEFINITION id. The fixture's assignment id
      // (`assign-1`) DIFFERS from its definition id (`svc-1`) — with equal ids
      // this pair of expectations would pass on either, which is precisely how
      // the bug ships (`project_fixture_values_can_defang_assertions`).
      expect(fb.lastDeletedServiceDefId, 'svc-1');
      expect(
        fb.lastDeletedServiceDefId,
        isNot('assign-1'),
        reason:
            'the assignment id must never key the delete — the backend '
            'resolves this endpoint on the service definition',
      );

      // The screen popped back to the list…
      await AppHarness.pumpUntilCondition(
        tester,
        () => AppHarness.location(router) == RouteNames.services,
        description:
            'the edit screen to pop back to /services after the '
            'successful delete',
      );

      // …and the catalogue re-fetch the pop schedules actually fired.
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.getServicesCalls > servicesCallsBefore,
        description:
            'invalidateMasterServiceCatalogues to re-fetch the services list',
      );

      // Phase 316 trimmed `ref.invalidate(masterProfileProvider)` from the
      // delete path: [Master] carries no service-derived field, so the profile
      // refetch was pure waste (and, under a salon target, would have read the
      // OPERATOR's profile rather than the unassigned master's).
      expect(
        fb.getMasterCalls,
        masterCallsBefore,
        reason:
            'the delete path must NOT invalidate masterProfileProvider — no '
            'GET /api/v1/masters/me may follow a service delete',
      );

      // The refreshed list no longer renders the deleted card, while its
      // NAILS siblings still do. Asserting the siblings is what makes this a
      // "this one row went away" check rather than a "the section failed to
      // render at all" false pass.
      //
      // ORDER MATTERS. Wait for a SIBLING first: the invalidation puts the
      // list back through `AsyncLoading` and the screen renders its skeleton,
      // during which NEITHER card is in the tree — so a bare
      // `findsNothing` on the deleted card would pass on the loading frame
      // and prove nothing. Gating on the sibling means the section is
      // rendered AND still expanded when the absence is asserted.
      final Finder survivingCard = find.byKey(
        const Key('service_card_assign-typed'),
      );
      await expandNailsUntil(tester, survivingCard);
      expect(
        survivingCard,
        findsOneWidget,
        reason:
            'the other NAILS services must survive — a definition-scoped '
            'delete removes ONE row, not the section',
      );
      expect(
        find.byKey(const Key('service_card_assign-1')),
        findsNothing,
        reason:
            'the deleted service must be gone from the re-fetched list; the '
            'fake backend removes the row on DELETE, so a card still here '
            'means the list was never re-fetched',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ── 2. Double-tap guard — one tap, one DELETE, no error snackbar ─────────

  testWidgets(
    'a second delete tap while the first DELETE is in flight issues no second '
    'DELETE and opens no second dialog',
    (tester) async {
      // The race exists only WHILE the DELETE is in flight: once the dialog
      // pops the delete icon behind it is hit-testable again, but the screen
      // has not popped yet. With an immediate reply that window is sub-frame.
      final fb = FakeBackend(
        deleteServiceDelay: const Duration(milliseconds: 1500),
      );
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      await openSeededServiceEdit(tester, router);
      AppHarness.expectLocation(router, '/services/assign-1/edit');

      final Finder deleteButton = find.byKey(const Key('btn-delete-service'));
      final Finder dialog = find.byKey(const Key('delete-service-dialog'));

      await AppHarness.tapVisible(tester, deleteButton);
      await AppHarness.pumpUntilFound(tester, dialog);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('btn-confirm-delete-service')),
      );

      // The dialog leaves; the DELETE is still in flight behind it.
      await AppHarness.pumpUntilGone(tester, dialog);
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.deleteServiceCalls == 1,
        description: 'the first DELETE to be dispatched',
      );
      expect(
        AppHarness.location(router),
        '/services/assign-1/edit',
        reason:
            'the screen must still be mounted mid-flight — otherwise the '
            'second tap below could not reach the delete icon and this flow '
            'would prove nothing about the guard',
      );

      // SECOND TAP, mid-flight. `_deleting` must swallow it: no second dialog.
      await tester.tap(deleteButton);
      // fixed-wait-ok: a NEGATIVE assertion — there is no state to pump UNTIL,
      // so a second dialog must be given real time to mount before its absence
      // can mean anything. 300 ms comfortably exceeds the dialog route's
      // entrance (its keyed AlertDialog is in the tree from the first frame of
      // the push) and stays well inside the 1500 ms in-flight DELETE window
      // this flow deliberately opens.
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        dialog,
        findsNothing,
        reason:
            'the _deleting re-entrancy guard must swallow the second tap '
            'before it can even open a confirmation dialog',
      );

      // Let the in-flight DELETE land and the screen pop.
      await AppHarness.pumpUntilCondition(
        tester,
        () => AppHarness.location(router) == RouteNames.services,
        description: 'the delete to complete and the edit screen to pop',
        timeout: const Duration(seconds: 20),
      );

      expect(
        fb.deleteServiceCalls,
        1,
        reason:
            'exactly ONE DELETE — a second would 404 ("already gone") and '
            'raise an error snackbar for an operation that SUCCEEDED',
      );
      // No error snackbar surfaced. A second DELETE would have produced one
      // via _showServiceEditFailureSnackbar → NotFoundFailure.
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'a successful delete must raise no error snackbar',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ── 3. Save path — the same trimmed fan-out as delete ────────────────────

  testWidgets('saving a service edit re-fetches the catalogue but issues no '
      'GET /masters/me', (tester) async {
    final fb = FakeBackend();
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

    // `assign-typed` is the seeded service whose PATCH is wired at the REAL
    // `/api/v1/services/{serviceDefId}` endpoint (200), so a submit actually
    // reaches the wire.
    //
    // Entered through the LIST, not `router.go`, for the same reason the
    // delete flows are: `servicesListProvider` is autoDispose, so with no
    // /services screen underneath, invalidating it after the save schedules
    // NO re-fetch and the catalogue assertion below would be unfalsifiable.
    await openSeededServiceEdit(tester, router, assignmentId: 'assign-typed');
    AppHarness.expectLocation(router, '/services/assign-typed/edit');

    final int servicesCallsBefore = fb.getServicesCalls;
    final int masterCallsBefore = fb.getMasterCalls;

    final Finder submit = find.byKey(const Key('btn-submit-service'));
    expect(submit, findsOneWidget);
    await AppHarness.tapVisible(tester, submit);

    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.patchServiceCalls >= 1,
      description: 'the save PATCH to reach the wire',
    );
    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.getServicesCalls > servicesCallsBefore,
      description:
          'invalidateMasterServiceCatalogues to re-fetch the services list '
          'after the save',
    );

    // Phase 316 removed `ref.invalidate(masterProfileProvider)` from the
    // SAVE path too (mobile-perf LOW) — a rename / reprice / recategorize
    // moves no field on [Master], and leaving it in made the two writes on
    // this screen fan out asymmetrically.
    expect(
      fb.getMasterCalls,
      masterCallsBefore,
      reason:
          'the save path must NOT invalidate masterProfileProvider — no '
          'GET /api/v1/masters/me may follow a service save',
    );

    // The success VelvetSnack lives on the app's ROOT Overlay and survives
    // the pop — drain its dwell Timer so none is pending at teardown.
    await pumpPastVelvetSnack(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
