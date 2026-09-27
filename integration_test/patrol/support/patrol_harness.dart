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
// without the shared GUARDS.
//
// THAT SENTENCE COVERS GUARDS, NOT PROVIDERS — READ IT NARROWLY (2026-08-04)
// -------------------------------------------------------------------------
// [applyE2eBootPolicy] installs the overflow guard, the off-screen-tap guard,
// the text-input mock, the timezone database and the splash-gate priming. It
// does NOT install any provider override. Those come from
// `e2eProviderOverrides(...)`, which [boot] below passes and which
// `deep_link_patrol_test.dart` deliberately does not — it pumps
// `ProviderScope(child: BeauticaApp())` bare, so that ONE flow runs on the REAL
// device clock, the REAL Dio and the REAL SecureStorage, while every other E2E
// entry point (both tiers) runs on `kFixedNow`.
//
// That is correct for what it tests (an OS-level App Link intent reaching the
// real app) and there is no defect there today: a mobile-qa audit on
// 2026-08-04 found the whole patrol tier contains ZERO `DateTime` references of
// any kind, and neither live flow asserts on a date, a slot, a calendar cell or
// any other clock-derived value. But the asymmetry is REAL and it is invisible
// to every gate: `scripts/forbid_host_local_instant_anchor.sh` RULE 3 flags a
// `DateTime.now` READ in an integration test, and RULE 4 flags a fixture/pin
// mismatch inside one test body — neither can see "this flow's APP is on the
// live clock while the tier's shared fixtures are pinned to kFixedNow".
//
// SO: anything added to `deep_link_patrol_test.dart` that touches a date must
// either derive it from the REAL clock (`kyivToday(DateTime.now)` — correct
// there, wrong everywhere else in this tier) or that flow must start passing
// `e2eProviderOverrides(...)` like every other entry point. Do not copy a
// `kFixedNow`-anchored fixture into it from a sibling E2E file; it will be
// comparing against a clock that flow does not share.

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
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

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
        retry: beauticaProviderRetry,
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
      // Kept in step with `AppHarness.loginAs` — the two tiers' login drivers
      // are hand-mirrored copies and drift silently (see app_harness.dart's
      // SHARED BOOT POLICY note). Without this arm an admin login submits the
      // master persona's address.
      UserRole.salonAdmin => 'admin@beautica.ua',
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
