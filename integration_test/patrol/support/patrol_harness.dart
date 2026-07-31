// Phase 17.5 — patrol harness helpers.
//
// WHAT
// ----
// The patrol-tier boot path. Adapts `PatrolIntegrationTester` ($) to the SAME
// shared boot policy the flutter_test tier uses — fake Dio transport, fixed
// clock, fake SecureStorage, primed splash gate, overflow guard, off-screen-tap
// guard, text-input mock — with only patrol's own pump/native surface differing.
//
// THIS FILE NO LONGER MIRRORS app_harness.dart — IT DELEGATES (2026-07-31)
// -----------------------------------------------------------------------
// It used to say "Mirrors integration_test/support/app_harness.dart" and then
// hand-copy that boot sequence. That mirror drifted exactly as a mirror always
// does: `WidgetController.hitTestWarningShouldBeFatal` was added to
// `AppHarness.boot` and never here, so the ENTIRE patrol tier kept booting with
// the off-screen-tap guard off — silently swallowing mis-aimed taps and failing
// later, elsewhere, with the wrong diagnosis. Nothing flagged it: not
// `flutter analyze`, not a lint, not a green run.
//
// The shared rules now live in ONE place —
// `integration_test/support/e2e_boot_policy.dart` — and both harnesses call
// [applyE2eBootPolicy]. Anything added there is inherited by BOTH tiers
// automatically. Do NOT re-inline a rule here "just for patrol", and do NOT
// special-case one off (in particular the tap guard, whose patrol-tier
// interaction is documented at its definition): that is how the mirror comes
// back, with a rationale attached.
//
// WHY A SEPARATE HARNESS AT ALL
// -----------------------------
// `AppHarness.boot(tester, ...)` takes a `WidgetTester` and pumps via
// `tester.pumpWidget` + a bounded `pumpAndSettle`; patrol needs
// `$.pumpWidgetAndSettle` so patrol's finders, settle policy and
// `$.platform.*` automation share the tree. That pump call — and patrol's
// native-only concerns — is genuinely tier-specific and is ALL that remains
// tier-specific here.
//
// SCOPE
// -----
// Used by the PORTED TEMPLATE flow (auth_login_patrol_test.dart), which runs
// the deterministic fake-backend tree under patrol to demonstrate the
// patrolTest(...) binding. The native-only DEEP-LINK flow
// (deep_link_patrol_test.dart) does NOT use this harness — it drives the REAL
// launched app via `$.platform.mobile.openUrl(...)` and a deep-link intent — but
// it DOES apply the same [applyE2eBootPolicy], so no patrol entry point boots
// unguarded.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:patrol/patrol.dart';

import '../../../test/helpers/fakes/fake_secure_storage.dart';
import '../../support/e2e_boot_policy.dart';
import '../../support/fake_backend.dart';

export '../../support/fake_backend.dart' show FakeBackend, kFixedNow;

/// Shared boot path for patrol-bound flows that run against the fake backend.
abstract final class PatrolHarness {
  PatrolHarness._();

  /// Pumps the REAL app (real go_router + real Riverpod notifiers) with the
  /// fake Dio transport + fixed clock + fake SecureStorage, through patrol's
  /// tester. Returns the live [GoRouter] so tests can assert the current route.
  ///
  /// Applies the SAME [applyE2eBootPolicy] as `AppHarness.boot` — including the
  /// splash-gate priming that lets the auth redirect settle to /login on the
  /// first settle — then pumps through patrol's tester.
  static Future<GoRouter> boot(
    PatrolIntegrationTester $,
    FakeBackend fakeBackend,
  ) async {
    // ── SHARED BOOT POLICY — ONE definition, BOTH E2E tiers ─────────────────
    //
    // Overflow guard, off-screen-tap guard
    // (`WidgetController.hitTestWarningShouldBeFatal`), text-input mock
    // registration (`tester.binding.testTextInput.register()` — without it
    // `enterText` is a SILENT no-op in the `--profile` / `--release` modes
    // patrol_cli 4.4.0 exposes), timezone database, and the splash-gate
    // priming. Every one of those is defined ONCE, in
    // `integration_test/support/e2e_boot_policy.dart`, and applied here by this
    // single call. Patrol wraps the standard `WidgetTester`, so the policy
    // applies verbatim — `$.tester` IS a `WidgetTester`.
    //
    // Do not re-inline any of it here. This file's header explains what the
    // hand-mirrored version cost.
    applyE2eBootPolicy($.tester);

    final storage = FakeSecureStorage();

    await $.pumpWidgetAndSettle(
      ProviderScope(
        // Cast a plain Object list so this file need not import Riverpod's
        // Override type — same shape as AppHarness.boot.
        // ignore: avoid_dynamic_calls
        overrides: e2eProviderOverrides(
          fakeBackend: fakeBackend,
          storage: storage,
        ).cast(),
        child: const E2eHarnessApp(),
      ),
    );

    final container = ProviderScope.containerOf(
      $.tester.element(find.byType(E2eHarnessApp)),
    );
    return container.read(appRouterProvider);
  }

  /// Undoes the per-test half of the shared boot policy. Call in tearDown.
  ///
  /// Delegates to [resetE2eBootPolicy], the SAME function
  /// `AppHarness.tearDownHarness` calls — splash-gate reset plus the host-side
  /// GL settle delay. The patrol job relaunches the app across native tests on
  /// the same headless goldfish-opengl emulator, so it is exposed to the
  /// identical `Failed to find ColorBuffer` -> `adb: device offline` crash class
  /// that delay exists for (see [resetE2eBootPolicy]).
  static Future<void> tearDownHarness() => resetE2eBootPolicy();

  /// Drives the real login form for [role] and taps Submit (key-based).
  static Future<void> loginAs(
    PatrolIntegrationTester $,
    FakeBackend fakeBackend,
    UserRole role,
  ) async {
    fakeBackend.currentRole = role;

    final email = switch (role) {
      UserRole.client => 'client@beautica.ua',
      UserRole.salonOwner => 'owner@beautica.ua',
      UserRole.independentMaster => 'master@beautica.ua',
      _ => 'master@beautica.ua',
    };

    await $.enterText(find.byKey(const ValueKey<String>('login_email')), email);
    await $.enterText(
      find.byKey(const ValueKey<String>('login_password')),
      'Secret1234',
    );
    await $.tap(find.byKey(const ValueKey<String>('login_submit')));
    await $.pumpAndSettle();
  }
}

// The real MaterialApp.router this harness pumps is [E2eHarnessApp], in
// `../../support/e2e_boot_policy.dart`. It used to be a private
// `_PatrolHarnessApp` here, byte-identical to app_harness.dart's private
// `_HarnessApp` — one more strand of the mirror this file no longer maintains.
