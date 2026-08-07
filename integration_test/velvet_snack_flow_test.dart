// END-TO-END coverage for VelvetSnack (`lib/shared/feedback/`) AS A FEATURE
// IN ITS OWN RIGHT — mobile-qa, 2026-08-06.
//
// WHY THIS FILE EXISTS
// ---------------------
// The VelvetSnack migration (63 raw `ScaffoldMessenger` call sites → the
// unified snack, five waves) left every CONSUMING screen well covered — each
// wave updated its own widget/integration tests to assert the new surface
// instead of the old one. But no test anywhere exercised the component's OWN
// contract against a REAL running app: a snack raised off a genuine
// repository/HTTP failure, a snack surviving the real route change that
// follows it, and the single-slot pre-emption guarantee holding for a real,
// non-synchronous second trigger (not just the same-tick race
// `velvet_snack_host_race_test.dart` already guards at the widget tier).
// This file closes exactly that gap, reusing REAL screens already wired to
// VelvetSnack rather than a synthetic harness widget.
//
// SCOPE SPLIT WITH THE WIDGET TIER
// ---------------------------------
// The deep, precisely-timed, mutation-proven mechanics (dwell 4s vs 6s,
// bottomInset positioning, swipe-to-dismiss, the async-gap pre-empt branch
// with distinguishable content) live at `test/shared/feedback/
// velvet_snack_host_test.dart`, where a controlled harness can pump exact
// virtual-time deltas. This file cannot match that precision — a real screen
// carries a real category-chip fetch, a real bulk POST, a real notifier
// state machine — so its job is narrower and complementary: prove the SAME
// invariants hold when raised by genuine production code, not a test
// double.
//
// KEY POLICY (app_harness.dart) — all navigation/interaction finders are
// key-based. Content assertions read localized copy off a live context.

import 'dart:async';

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

/// The service type this flow configures on the setup screen. Deliberately
/// NOT `type-nails-classic`: the fake backend seeds that one into the
/// master's existing catalogue, so its row renders inert (no toggle) — see
/// `service_duplicate_flow_test.dart` for the same choice and rationale.
const String _typeId = 'type-nails-gel';

/// Expands the NAILS category, toggles [_typeId] ON, and fills it with a
/// valid duration + FIXED price — the shared "get a submittable row" setup
/// every test in this file needs before it can drive a real Save. Identical
/// sequence to `service_duplicate_flow_test.dart` (kept in lockstep with it
/// deliberately — this is the proven way to reach a real bulk POST on this
/// screen without a stray unrelated failure).
Future<void> _configureOneRow(WidgetTester tester) async {
  final Finder nailsChip = find.byKey(const ValueKey<String>('cat_NAILS'));
  await tester.pumpUntilFound(nailsChip.hitTestable());
  await tester.tap(nailsChip);

  final Finder row = find.byKey(const Key('setup_row_$_typeId'));
  await tester.pumpUntilFound(row);

  final Finder toggle = find.byKey(const Key('setup_row_toggle_$_typeId'));
  await tester.ensureVisible(toggle);
  await tester.pumpUntilFound(toggle.hitTestable());
  await tester.tap(toggle);
  await tester.pump();

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
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'a real 409 duplicate-service failure raises an error VelvetSnack, '
    'which auto-retires and frees the Save CTA underneath it',
    (tester) async {
      final fb = FakeBackend();
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      AppHarness.expectLocation(router, RouteNames.masterProfile);
      unawaited(router.push(RouteNames.serviceSetup));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.serviceSetup);

      await _configureOneRow(tester);

      // Arm the REAL failure path — a genuine HTTP 409 through
      // HttpServiceRepository.bulkCreate, not a mocked repository.
      fb.bulkRejectDuplicate = true;

      final Finder saveBtn = find.byKey(const Key('btn-setup-save'));
      await tester.pumpUntilFound(saveBtn.hitTestable());
      final l10n = AppLocalizations.of(tester.element(saveBtn));

      await tester.tap(saveBtn);

      // Diagnose at the cause — the POST must actually reach the fake
      // before we look for its rendered consequence (see
      // `service_duplicate_flow_test.dart` for why this ordering matters).
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.bulkCreateCalls >= 1,
        description:
            'the bulk POST to reach the fake backend for the FIRST save '
            'attempt',
      );

      // ── 1) Raised: a real failure path shows the error VelvetSnack ───────
      final Finder duplicateText = find.text(l10n.serviceErrDuplicate);
      await tester.pumpUntilFound(duplicateText);
      expectVelvetSnack(
        l10n.serviceErrDuplicate,
        variant: VelvetSnackVariant.error,
      );

      // ── 2) Auto-retires ────────────────────────────────────────────────
      // Drains the dwell Timer AND removes the OverlayEntry — the mechanism
      // itself (why 4s, why the timer fires deterministically) is
      // mutation-proven at the widget tier
      // (`velvet_snack_host_test.dart`'s dwell test); this assertion is
      // "merely asserted" at this tier — it re-checks the same outcome
      // against a REAL trigger, not the mechanism's timing.
      await pumpPastVelvetSnack(tester);
      expect(find.byType(VelvetSnack), findsNothing);

      // ── 3) The CTA underneath is interactive again ────────────────────
      // Proof, not assumption: the snack is bottom-anchored and this screen's
      // Save CTA is a fixed bottom bar (`_SaveBar`/`btn-setup-save`) — the
      // exact geometry that made a still-showing snack silently swallow a
      // tap on `weekly_template_editor_screen_test.dart`'s second Save
      // button during this migration (see
      // `test/helpers/velvet_snack_matchers.dart`'s file header). Re-tapping
      // Save (duplicate is STILL armed — only the call count matters) and
      // observing a SECOND real POST is the only way to prove the overlay
      // actually released the hit-test region, not merely that the widget
      // left the tree.
      await tester.pumpUntilFound(saveBtn.hitTestable());
      await tester.tap(saveBtn);
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.bulkCreateCalls >= 2,
        description:
            'a SECOND real POST after the first snack auto-retired — if the '
            'overlay still intercepted the hit-test region under the Save '
            'CTA, this tap would silently miss and the count would stay at 1',
      );

      // Drain the second snack too so nothing is pending at teardown.
      await pumpPastVelvetSnack(tester);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'a real success VelvetSnack survives the context.pop() route change '
    'that immediately follows it, then auto-retires on the screen behind',
    (tester) async {
      final fb = FakeBackend();
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      AppHarness.expectLocation(router, RouteNames.masterProfile);
      // A PUSH (not `router.go`) so the setup screen's own `_leave()` can
      // `context.pop()` back to THIS already-loaded master-profile screen —
      // deliberately avoids landing back on the services LIST, whose loading
      // skeleton runs a perpetual shimmer that stalls `pumpAndSettle`
      // (see `service_duplicate_flow_test.dart`'s identical navigation note).
      unawaited(router.push(RouteNames.serviceSetup));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.serviceSetup);

      await _configureOneRow(tester);

      final Finder saveBtn = find.byKey(const Key('btn-setup-save'));
      await tester.pumpUntilFound(saveBtn.hitTestable());
      final l10n = AppLocalizations.of(tester.element(saveBtn));

      await tester.tap(saveBtn);

      // `_save()`'s success branch calls `showSuccessSnack(...)` and
      // `_leave()` (→ `context.pop()`) back-to-back, synchronously, in the
      // SAME continuation once the bulk POST resolves — there is no widget
      // to pump-until for the moment in between, so this is the one place in
      // this file that cannot avoid pumping a little past the network call
      // and inspecting a transient window. `pumpUntilCondition` gets us to
      // "the POST landed"; one more `pump()` runs the synchronous
      // continuation (snack shown + pop) without also draining the snack's
      // own dwell Timer.
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.bulkCreateCalls >= 1,
        description: 'the bulk POST to reach the fake backend',
      );
      await tester.pump();

      // ── The pop already happened … ────────────────────────────────────
      AppHarness.expectLocation(router, RouteNames.masterProfile);

      // ── … and the snack raised BEFORE it is STILL showing ─────────────
      // Unscoped finder by construction — VelvetSnack lives on the app's
      // ROOT `Overlay` (`rootOverlay: true`), a SIBLING of the pushed
      // `/services/setup` route's own subtree, never a descendant of it —
      // see `velvet_snack_host.dart`'s file-level doc, "Why the snack
      // survives a route pop fired right after it".
      //
      // MUTATION NOTE: flipping `rootOverlay: true` → the default `false` in
      // `velvet_snack_host.dart` does NOT turn this assertion red, because
      // `/services/setup` is a plain top-level `GoRoute` pushed directly onto
      // the app's one and only `Navigator` — there is no NESTED Overlay on
      // this particular path for the non-root lookup to walk into, so both
      // resolve to the same Overlay here. `rootOverlay: true` only earns its
      // keep on a route nested inside a `ShellRoute`/`StatefulShellRoute`
      // branch (the CLIENT 5-tab shell) or a `showDialog`/
      // `showModalBottomSheet` builder, neither of which this flow reaches.
      // What IS mutation-proven below is that this assertion is load-bearing
      // for the POP itself: commenting out `_leave()` in
      // `service_setup_screen.dart`'s success branch turns the
      // `AppHarness.expectLocation(router, RouteNames.masterProfile)` line
      // above red (still on `/services/setup`) — confirmed, then reverted.
      expectVelvetSnack(
        l10n.serviceSetupSuccess,
        variant: VelvetSnackVariant.success,
      );

      // ── Then auto-retires on the screen it survived onto ──────────────
      await pumpPastVelvetSnack(tester);
      expect(find.byType(VelvetSnack), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'two real showInfoSnack triggers separated by a genuine async gap (NOT '
    'the same synchronous tick) keep exactly one VelvetSnack mounted',
    (tester) async {
      // account/settings ("Мова" row → showInfoSnack) needs no bulk-service
      // setup at all — the leanest real, production trigger available, and
      // (unlike the setup screen's Save CTA) the account screen has no
      // pinned bottom footer (`SectionScaffold(footer: null)` there), so the
      // row itself can never be the thing a lingering snack swallows a tap
      // on — isolating "did pre-emption work" from "did the tap even land".
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      AppHarness.expectLocation(router, RouteNames.masterProfile);
      unawaited(router.push(RouteNames.settings));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.settings);

      final Finder languageRow = find.byKey(const Key('row-language'));
      await tester.pumpUntilFound(languageRow.hitTestable());

      // First real trigger — let its entrance fully settle before the
      // second, so this is unambiguously NOT the same-tick race
      // `velvet_snack_host_race_test.dart` already covers at the widget
      // tier (two `showVelvetSnack` calls from ONE synchronous handler).
      await tester.tap(languageRow);
      await tester.pumpAndSettle();
      expect(find.byType(VelvetSnack), findsOneWidget);

      // Second real trigger — a whole extra user tap, well inside the first
      // snack's 4s dwell, so it is still genuinely showing when this fires.
      // This exercises the OTHER pre-empt branch in
      // `_VelvetSnackOverlay.show` (`previous.retireAndClear(...).then(...
      // insert())`) — the same-tick race test can only ever reach the
      // synchronous same-tick-claim branch, never this one.
      await tester.tap(languageRow);
      await tester.pumpAndSettle();

      // Single-slot holds against a real production trigger fired twice
      // across a genuine async gap, not just the synthetic same-tick
      // scenario. (Both snacks carry identical copy — "Мова" has one
      // message — so this test cannot also show which call "won" the way
      // the same-tick race test's two-different-messages case does; that
      // distinguishing assertion is covered with precise timing control at
      // the widget tier instead — see `velvet_snack_host_test.dart`'s
      // async-gap pre-emption test.)
      expect(find.byType(VelvetSnack), findsOneWidget);

      await pumpPastVelvetSnack(tester);
      expect(find.byType(VelvetSnack), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
