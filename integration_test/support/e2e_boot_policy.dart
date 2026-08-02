// SHARED E2E BOOT POLICY — the ONE place every E2E tier's boot rules live.
//
// WHY THIS FILE EXISTS
// --------------------
// There are two E2E tiers, and each has its own harness:
//
//   • `integration_test/support/app_harness.dart`        (flutter_test tier,
//     `WidgetTester`, the fast headless job)
//   • `integration_test/patrol/support/patrol_harness.dart` (patrol native
//     tier, `PatrolIntegrationTester`, the emulator job)
//
// Those two used to MIRROR each other: two hand-copied boot sequences that were
// meant to stay identical and were kept honest only by a
// "Mirrors integration_test/support/app_harness.dart" comment at the top of the
// patrol one. A comment is not executable, so the mirror drifted — once, and
// expensively:
//
//   `WidgetController.hitTestWarningShouldBeFatal` — the off-screen-tap guard
//   that turns a SILENTLY-SWALLOWED tap into an immediate failure naming the
//   real cause ("would not hit test … outside the bounds of the root of the
//   render tree") instead of an unrelated `pumpUntilFound` timeout 10 s
//   downstream — was added to `AppHarness.boot` only. The entire patrol tier
//   kept booting with the guard OFF, so every patrol flow retained the exact
//   flake class the guard exists to kill, and nothing anywhere said so.
//
// The lesson is structural, not incidental: a mirrored harness is GUARANTEED to
// drift, because the mirror is maintained by human diligence and the drift is
// invisible to `flutter analyze`, to the linter, and to a green test run. So the
// shared rules now live HERE, in exactly one function that both harnesses call.
//
// WHAT BELONGS HERE vs. IN A HARNESS
// ----------------------------------
// HERE: anything that must be true for EVERY E2E boot on EITHER tier — global
// test-framework flags, binding registrations, one-shot app-global priming.
// Adding a rule to [applyE2eBootPolicy] arms it on both tiers automatically;
// that is the whole point, and it is the only way a future policy cannot be
// half-applied.
//
// IN THE HARNESS: anything genuinely tier-specific — patrol's
// `$.pumpWidgetAndSettle` / `$.platform.mobile.*` native automation, and
// `AppHarness`'s `ProviderScope.retry` / injectable `FakeSecureStorage` /
// bounded-settle helpers, none of which the patrol tier has or wants.
//
// STRUCTURAL GUARD
// ----------------
// `scripts/forbid_missing_test_text_input.sh` gates this file directly: it
// asserts [applyE2eBootPolicy] still calls `testTextInput.register()`, AND that
// BOTH harnesses' `boot(...)` bodies still call [applyE2eBootPolicy]. Deleting
// the call from either end fails CI rather than silently reintroducing the
// mirror.

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/theme/app_theme.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/fakes/fake_secure_storage.dart';
import '../../test/helpers/overflow_guard.dart';
import 'fake_backend.dart';

/// How far in the past [applyE2eBootPolicy] backdates [AppStartTime].
///
/// Must exceed the splash gate's `minSplashDuration` (3 000 ms) with margin —
/// see [applyE2eBootPolicy]'s SPLASH GATE note.
const Duration kE2eSplashPrimeOffset = Duration(seconds: 5);

/// How long [resetE2eBootPolicy] waits after a harness unmount.
///
/// See [resetE2eBootPolicy] for why a REAL delay (not a pump) is the correct
/// tool here.
const Duration kE2eTearDownSettleDelay = Duration(seconds: 2);

/// Applies every rule that must hold for an E2E boot on EITHER tier.
///
/// Call this FIRST in a harness `boot(...)`, before pumping the app tree. It is
/// idempotent, so a flow that boots twice (or a harness that also arms the
/// overflow guard in `setUp`) is fine.
///
/// Pair it with [resetE2eBootPolicy] in `tearDown`.
void applyE2eBootPolicy(WidgetTester tester) {
  // ── OVERFLOW GUARD ────────────────────────────────────────────────────────
  //
  // Records the first "RenderFlex overflowed by N pixels" Flutter reports and
  // fails the test in tearDown (never inline — throwing during a layout flush
  // re-dirties layout and hangs pumpAndSettle forever; see overflow_guard.dart).
  // Idempotent and re-wrap aware, so calling it here as well as in a flow's own
  // `setUp` is harmless.
  installOverflowGuard();

  // ── OFF-SCREEN TAP GUARD ──────────────────────────────────────────────────
  //
  // `WidgetController.hitTestWarningShouldBeFatal` is a static flag that
  // defaults to FALSE, and was used nowhere in this repo before 2026-07-31.
  // With it false, `tester.tap(finder)` on a widget whose global centre lies
  // OUTSIDE the render tree (or under something else) prints a WARNING and taps
  // nothing: `onTap` never runs and the test carries on, only failing much later
  // and somewhere else — typically as an unrelated `pumpUntilFound` timeout 10 s
  // downstream, pointing at the wrong cause entirely.
  //
  // That is exactly how the /search/results heart-tap flake hid for so long:
  // that route is a plain `MaterialPage` (app_router.dart:441) while the app
  // pins `CupertinoPageTransitionsBuilder` for every platform (app_theme.dart:37),
  // so the page slides in from the right over 500 ms and a tap fired mid-slide
  // can land past the right edge of the 800×600 flutter-tester view. Turning the
  // flag on makes that fail INSTANTLY, at the tap, saying "would not hit test …
  // outside the bounds of the root of the render tree" — the actual diagnosis.
  //
  // NOTE FOR THE PATROL TIER: patrol's `$.tap()` auto-scrolls
  // (`waitUntilVisible`) before tapping, so a target that is merely off-screen
  // is normally scrolled into view rather than mis-tapped. Arming the flag there
  // therefore surfaces the residue — a target patrol could NOT bring on-screen —
  // which is a real defect in the flow, not noise. Do NOT special-case the flag
  // off for patrol: that is precisely the divergence this file exists to
  // prevent, and it would re-open the drift with a rationale attached.
  //
  // Set here rather than in `installOverflowGuard`, which is also used by the
  // widget-tier suite under `test/` — this guard is an E2E-tier policy.
  WidgetController.hitTestWarningShouldBeFatal = true;

  // ── TEXT-INPUT MOCK REGISTRATION — DO NOT DELETE ──────────────────────────
  //
  // WITHOUT THIS LINE, `tester.enterText(...)` IS A SILENT NO-OP IN ANY
  // NON-DEBUG BUILD (`flutter drive --profile` / `--release`, and
  // `patrol test --profile` / `--release`, which patrol_cli 4.4.0 exposes).
  // Every field stays empty, the form's own "required" validation correctly
  // bails, and the failure surfaces far downstream as a confusing
  // tap/navigation assertion. It looks redundant in a debug run — it is not.
  //
  // MECHANISM
  // ---------
  //  1. `WidgetTester.enterText` ultimately posts a
  //     `TextInputClient.updateEditingState` platform message carrying the
  //     connection id `TestTextInput._client ?? -1`.
  //  2. `IntegrationTestWidgetsFlutterBinding` AND `PatrolBinding` (patrol
  //     4.6.1, `lib/src/binding.dart` line 136 — byte-identical) both override
  //     `registerTestTextInput => false`, so the binding never registers the
  //     `TestTextInput` mock handler, `_client` is never assigned, and the id
  //     posted is ALWAYS `-1`.
  //  3. In `TextInput._handleTextInputInvocation`, the escape hatch that
  //     accepts `-1` ("the framework is in a test") lives INSIDE an
  //     `assert(() { ... }())` block.
  //  4. Asserts are stripped in profile/release. The `-1` message therefore
  //     falls through and the injected value is DISCARDED WITHOUT ERROR.
  //
  // Registering the mock assigns a real `_client` id, so the message routes
  // through the normal (non-assert) path and the text actually lands in the
  // field — identically in debug and profile.
  //
  // WHY PER-BOOT, AND WHY UNCONDITIONAL
  // -----------------------------------
  // The binding's `reset()` between tests clears `_client`, but it only
  // re-registers when `registerTestTextInput` is true — which it never is here.
  // So registration has to happen on every boot, not once per isolate. Keeping
  // it unconditional (rather than `if (!kDebugMode)`) means debug and profile
  // exercise ONE code path, so the debug suite actually covers what the profile
  // drive runs. `register()` is idempotent.
  //
  // Regression-guarded by the post-`enterText` assertion in `AppHarness.loginAs`
  // (which turns a silent drop into a one-line diagnosis) and structurally by
  // `scripts/forbid_missing_test_text_input.sh`.
  tester.binding.testTextInput.register();

  // ── TIMEZONE DATABASE ─────────────────────────────────────────────────────
  //
  // Load the IANA timezone database so booking/slot formatters can convert to
  // the pinned Europe/Kyiv wall-clock. Both harnesses boot the real app tree
  // WITHOUT calling `main()`, so main.dart's `initBeauticaTimeZones()` never
  // runs — do it explicitly. Idempotent across aggregated per-test re-boots.
  initBeauticaTimeZones();

  // ── SPLASH GATE ───────────────────────────────────────────────────────────
  //
  // `AppStartTime._start` is null when a harness boots (again: `main()` is never
  // called). A null `_start` makes `AppStartTime.elapsed()` return
  // `Duration.zero`, which is always < `minSplashDuration` (3 000 ms), so
  // `authRedirectForLocation` keeps re-routing to /splash forever and the target
  // screen never mounts (`find.byKey('login_email')` finds nothing).
  //
  // Backdating the recorded start by [kE2eSplashPrimeOffset] makes `elapsed()`
  // ≈ 5 s > 3 s, unblocking the auth redirect on the very first settle.
  // [resetE2eBootPolicy] undoes it so the state cannot bleed between tests.
  AppStartTime.setStartForTest(DateTime.now().subtract(kE2eSplashPrimeOffset));
}

/// Undoes the per-test parts of [applyE2eBootPolicy]. Call in `tearDown`.
///
/// Resets [AppStartTime] to its pre-boot null state, then waits briefly for the
/// just-unmounted GL rendering surface to release host-side.
///
/// SETTLE DELAY (2026-07-07 — see docs/ci_investigation_notes.md in the
/// Beautifier monorepo for the full investigation). GitHub's headless CI
/// emulator (goldfish-opengl / swiftshader_indirect) crashes the WHOLE emulator
/// process (`Failed to find ColorBuffer` -> `adb: device offline`,
/// unrecoverable) when a 2nd+ boot starts immediately after the previous test's
/// own unmount. Confirmed by isolating flows down to exactly one relaunch
/// (always clean, 0 crashes) vs. two-or-more back-to-back relaunches (crashed on
/// every one of 9+ CI samples, independent of flow content, API level 33/34, or
/// test ordering) — the crash fires specifically on the transition INTO the 2nd
/// relaunch, not on rendering itself. This pause gives the driver's async
/// ColorBuffer cleanup time to actually complete host-side before the next
/// relaunch allocates new buffers.
///
/// This is a REAL-TIME delay, not a `pump` — it is waiting on the host graphics
/// driver, which the test clock does not drive. `scripts/forbid_fixed_wait.sh`
/// targets `pump(const Duration(...))` for exactly that reason and does not
/// apply here. E2E-tier only; no production effect.
///
/// Idempotent.
Future<void> resetE2eBootPolicy() async {
  AppStartTime.resetForTest();
  await Future<void>.delayed(kE2eTearDownSettleDelay);
}

/// The provider overrides every fake-backend E2E boot installs, on either tier.
///
/// Returns a `List<Object>` (not `List<Override>`) so callers need not import
/// Riverpod's `Override` type; each harness `.cast()`s it into
/// `ProviderScope.overrides`, optionally after appending its own extras.
///
/// EXACTLY ONE override per provider. `secureStorageProvider` in particular must
/// not be overridden a second time by a caller's extras — Riverpod 3.x throws
/// "Tried to override a provider twice within the same container". Pass the
/// instance in via [storage] instead; the caller already holds it, so it stays
/// reachable for assertions without a separate accessor.
///
/// [clock] optionally overrides the injected `clockProvider` instant —
/// defaults to [kFixedNow] (unchanged behaviour for every existing caller).
/// mobile-qa (2026-08-02, backlog :226 audit): a Kyiv-day-boundary flow
/// (`kyiv_day_boundary_flow_test.dart`) needs an instant where the Kyiv
/// calendar day disagrees with the UTC one — [kFixedNow] (noon UTC) sits
/// nowhere near that boundary by design (see its own doc comment), so it
/// cannot serve that case.
List<Object> e2eProviderOverrides({
  required FakeBackend fakeBackend,
  required FakeSecureStorage storage,
  DateTime Function()? clock,
}) {
  return <Object>[
    dioProvider.overrideWithValue(fakeBackend.dio),
    secureStorageProvider.overrideWithValue(storage),
    clockProvider.overrideWithValue(clock ?? () => kFixedNow),
  ];
}

/// The real `MaterialApp.router` without `main()`'s platform-channel
/// side-effects, shared by BOTH E2E tiers.
///
/// Bypasses the `main()` entry-point work that flutter_test's binding cannot
/// route (cert-pinning, FlutterNativeSplash, SystemChrome). The router, theme,
/// and localisation delegates are identical to production.
///
/// Public (not `_HarnessApp`-private) because each harness locates its
/// `ProviderScope` container via `find.byType(E2eHarnessApp)` after pumping.
/// This used to be two private, byte-identical copies — one per harness — which
/// is the same mirror-drift hazard this file exists to remove.
class E2eHarnessApp extends ConsumerWidget {
  const E2eHarnessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: velvetTheme(),
      themeMode: ThemeMode.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk', 'UA'),
      routerConfig: router,
    );
  }
}
