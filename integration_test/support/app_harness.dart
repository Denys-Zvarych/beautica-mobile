// Phase 17.3 — Shared app harness for integration tests.
//
// WHAT
// ----
// Single boot path for ALL E2E journeys. Boots the REAL app (real Scaffold,
// real go_router, real Riverpod notifiers) via a [ProviderScope] with:
//   • dioProvider           → FakeBackend.dio (no real socket)
//   • clockProvider         → fixed DateTime (2026-06-14 12:00 UTC)
//   • secureStorageProvider → FakeSecureStorage (no platform channel)
//
// The [AuthNotifier] is NOT overridden — the real build() runs but hits the
// fake SecureStorage (no refresh token → Unauthenticated on cold start). Tests
// that need an authenticated session call [AppHarness.loginAs] after boot to
// drive through the real login flow against the fake backend.
//
// OVERFLOW GUARD
// --------------
// Wires the Phase 17.2 overflow guard via [installOverflowGuard] in [setUp],
// matching the unit-test suite. Any RenderFlex overflow in the E2E tree fails
// the test at tearDown, surfacing it as a clean test failure rather than a
// yellow stripe.
//
// SPLASH GATE (RC1 FIX)
// ---------------------
// [AppStartTime._start] is null when the harness boots (main() is never called
// in tests). A null _start causes [AppStartTime.elapsed()] to return
// Duration.zero, which is always < _minSplashDuration (3 000 ms).
// [authRedirectForLocation] therefore keeps re-routing to /splash forever,
// so /login never mounts and find.byKey('login_email') finds nothing.
//
// Fix: [boot()] calls [AppStartTime.setStartForTest] with a timestamp 5 s in
// the past, making elapsed() ≈ 5 s > 3 s. This unblocks the auth redirect on
// the first pumpAndSettle(). [tearDownHarness()] resets it so state does not
// bleed between tests. Tests that call [boot()] MUST register tearDownHarness
// in their tearDown:
//
//   setUp(installOverflowGuard);
//   tearDown(AppHarness.tearDownHarness);
//
// KEY-BASED NAVIGATION POLICY (ENFORCED)
// ----------------------------------------
// ALL navigation taps in integration_test/ MUST use key-based finders:
//
//   ALLOWED:
//     await tester.tap(find.byKey(const Key('login_submit')));
//     await tester.tap(find.byKey(const ValueKey('step1_submit')));
//
//   FORBIDDEN for tapping (raw-text tap driver = flake source):
//     await tester.tap(find.text('Увійти'));   // ← BAN: text tap driver
//
//   ALLOWED for content assertions:
//     expect(find.text('Вітаємо!'), findsOneWidget);  // ← OK: assertion
//
// RATIONALE: Ukrainian string literals change with l10n updates and differ
// across locales; key-based finders are locale-invariant and rename-proof.
// This convention is enforced by convention (not a lint gate) because
// flutter_test has no cheap custom lint for integration_test/ paths.
//
// ROUTER REFERENCE (RC2 FIX)
// --------------------------
// [boot()] returns the live [GoRouter] instance that was wired into the
// [MaterialApp.router]. Tests that need to assert the current route or navigate
// programmatically MUST hold this reference:
//
//   final GoRouter router = await AppHarness.boot(tester, fb);
//
// Use [router.routerDelegate.currentConfiguration.uri.toString()] to read the
// current location — this is locale-invariant and does NOT depend on
// [GoRouter.of(context)], which would require a context that is a DESCENDANT of
// [InheritedGoRouter] (i.e., inside the router's subtree, not at the MaterialApp
// level). The helper [expectLocation(tester, router, expected)] in each test
// file uses this pattern.
//
// USAGE
// -----
//   setUp(installOverflowGuard);
//   tearDown(AppHarness.tearDownHarness);
//
//   testWidgets('login flow', (tester) async {
//     final fb = FakeBackend();
//     final router = await AppHarness.boot(tester, fb);
//     await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
//     // assert route
//     expect(
//       router.routerDelegate.currentConfiguration.uri.toString(),
//       startsWith('/master/profile'),
//     );
//   });

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/theme/app_theme.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../test/helpers/fakes/fake_secure_storage.dart';
import '../../test/helpers/overflow_guard.dart';
import 'fake_backend.dart';

export 'fake_backend.dart' show FakeBackend, kFixedNow;

/// Shared boot path and convenience helpers for Phase 17.3 E2E tests.
abstract final class AppHarness {
  AppHarness._(); // non-instantiable

  // ── Cascade guard (Fix #2) ─────────────────────────────────────────────────

  /// Bounded settle window for EVERY [pumpAndSettle] on the shared boot/login
  /// path. The flutter_test default [pumpAndSettle] timeout is 10 MINUTES,
  /// which is far longer than the per-test [Timeout(Duration(seconds: 45))] used
  /// by the aggregated suite (integration_test/all_tests.dart, one isolate for
  /// 17 flows). When a flow hangs in an unbounded pumpAndSettle, the test-level
  /// Timeout completes the test future WHILE a pump is still in flight, leaving
  /// the single per-isolate [IntegrationTestWidgetsFlutterBinding] mid-frame —
  /// corrupting it for EVERY subsequent test (1 hang → ~50 cascade failures).
  ///
  /// Capping pumpAndSettle at 20 s (< the 45 s test Timeout) makes a hang throw
  /// `FlutterError("pumpAndSettle timed out")` SYNCHRONOUSLY inside the test
  /// body BEFORE the harness-level abort fires: the test fails as exactly ONE
  /// clean failure, [addTearDown] unmounts normally, and the next test boots
  /// from a clean tree.
  static const Duration settleTimeout = Duration(seconds: 20);

  /// [pumpAndSettle] bounded by [settleTimeout]. Preserves the default
  /// 100 ms interval / [EnginePhase.sendSemanticsUpdate] phase semantics —
  /// only the timeout is constrained. Use on the shared boot/login path so a
  /// single hang cannot cascade across the aggregated isolate (see [settleTimeout]).
  static Future<void> settle(
    WidgetTester tester, {
    Duration interval = const Duration(milliseconds: 100),
  }) {
    return tester.pumpAndSettle(
      interval,
      EnginePhase.sendSemanticsUpdate,
      settleTimeout,
    );
  }

  // ── Boot ──────────────────────────────────────────────────────────────────

  /// Pumps the REAL app with the fake backend and fixed-clock overrides.
  ///
  /// Returns the live [GoRouter] instance wired into [MaterialApp.router] so
  /// tests can assert [router.routerDelegate.currentConfiguration.uri] and
  /// navigate programmatically without relying on [GoRouter.of(context)],
  /// which fails at the [MaterialApp] level (requires a descendant context).
  ///
  /// After this call the app is sitting on /login (the fake [SecureStorage] has
  /// no stored refresh token → [AuthNotifier] settles to Unauthenticated →
  /// redirect to /login). Call [loginAs] to advance to an authenticated home.
  ///
  /// RC1 fix: sets [AppStartTime] to 5 s ago so the splash-duration gate
  /// (3 000 ms) is already satisfied when the first [pumpAndSettle] runs.
  /// Call [tearDownHarness] in [tearDown] to reset this state between tests.
  /// [storage] lets a caller inject its OWN [FakeSecureStorage] so it can read
  /// the refresh token before/after a flow (e.g. the logout-wipe assertion).
  /// When omitted, boot constructs a fresh one. Either way the harness installs
  /// EXACTLY ONE [secureStorageProvider] override — passing a storage via
  /// [extraOverrides] would override the provider twice (Riverpod 3.x throws
  /// "Tried to override a provider twice within the same container"). The caller
  /// already holds the instance it passed in, so the storage is reachable for
  /// assertions without a separate accessor.
  static Future<GoRouter> boot(
    WidgetTester tester,
    FakeBackend fakeBackend, {
    FakeSecureStorage? storage,
    List<Object> extraOverrides = const <Object>[],
  }) async {
    installOverflowGuard();

    // Load the IANA timezone database so booking/slot formatters can convert to
    // the pinned Europe/Kyiv wall-clock. The E2E harness boots the real app tree
    // via `_HarnessApp` (NOT `main()`), so main.dart's initBeauticaTimeZones()
    // never runs here — do it explicitly. Idempotent across the aggregated
    // per-test re-boots.
    initBeauticaTimeZones();

    // RC1 — prime the splash-duration gate so the auth redirect is not stuck
    // on /splash. [AppStartTime.elapsed()] must return > [minSplashDuration]
    // (3 000 ms) on the very first frame. We set the recorded start to 5 s
    // ago — safely past the gate in every build mode. Without this call,
    // elapsed() returns Duration.zero (null _start → fallback) and the guard
    // loops back to /splash indefinitely.
    AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );

    final effectiveStorage = storage ?? FakeSecureStorage();

    await tester.pumpWidget(
      ProviderScope(
        // ProviderScope.overrides accepts List<Override>; we cast so callers
        // can pass a plain list without importing the internal Override type.
        // ignore: avoid_dynamic_calls
        overrides: <Object>[
          dioProvider.overrideWithValue(fakeBackend.dio),
          secureStorageProvider.overrideWithValue(effectiveStorage),
          clockProvider.overrideWithValue(() => kFixedNow),
          ...extraOverrides,
        ].cast(),
        child: const _HarnessApp(),
      ),
    );

    // Allow the splash screen to resolve and the auth guard to redirect to
    // /login (unauthenticated cold start) or the role-appropriate home.
    // Bounded by [settleTimeout] (Fix #2) so a hang here cannot wedge the
    // shared aggregated isolate.
    await settle(tester);

    // AGGREGATION FIX (Phase 17.3) — unmount the app tree at tearDown.
    //
    // all_tests.dart runs all 5 E2E flows in ONE isolate via
    // group('<flow>', <flow>.main). flutter_test does NOT fully reset the
    // persistent overlay between testWidgets in a shared isolate (the suites
    // used to run as 5 separate processes). Without an explicit unmount, the
    // prior test's MaterialApp.router / Navigator / overlay entries survive
    // into the next test, overlaying the fresh /login screen — the
    // login_submit button ends up under RenderOffstage/RenderAbsorbPointer,
    // tester.tap() "would not hit test", _submit() never runs, and
    // fb.loginCalls stays 0 (failing the 2nd/3rd login flow).
    //
    // addTearDown runs LIFO, BEFORE the flow's own
    // tearDown(AppHarness.tearDownHarness), so it fully unmounts the current
    // MaterialApp.router (Navigator + all overlay entries) and disposes the
    // ProviderScope/keepAlive router container before the next test boots.
    addTearDown(() async {
      // RESILIENT UNMOUNT (Phase 17.3 cascade guard) — when a test TIMES OUT,
      // its in-flight pump is interrupted and the shared LiveTest binding can be
      // left mid-frame. An unguarded pumpWidget/pumpAndSettle here then collides
      // with that interrupted pump and corrupts the binding for EVERY subsequent
      // test in the isolate — one per-test timeout cascades into 50 failures.
      // Guarding the unmount localises the blast radius: a single timed-out test
      // fails exactly ONE test, and the next test still boots from a clean tree.
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } catch (_) {
        // Binding was left in a bad state by an interrupted/timed-out test —
        // swallow so this teardown cannot turn one failure into a suite wipe.
      }
    });

    // RC2 — read the live GoRouter from the ProviderScope container. The
    // container is accessible from the ProviderScope element's context.
    // appRouterProvider is keepAlive: true and is guaranteed to be
    // initialized after pumpAndSettle() because _HarnessApp calls
    // ref.watch(appRouterProvider) in its build().
    final container = ProviderScope.containerOf(
      tester.element(find.byType(_HarnessApp)),
    );
    return container.read(appRouterProvider);
  }

  // ── Tear-down ─────────────────────────────────────────────────────────────

  /// Resets [AppStartTime] to its pre-boot null state, then waits briefly
  /// for the just-unmounted GL rendering surface to release host-side.
  ///
  /// Must be called in [tearDown] in every test file that uses [boot], so the
  /// splash-gate override does not leak into subsequent tests. Idempotent.
  ///
  /// SETTLE DELAY (2026-07-07 — see docs/ci_investigation_notes.md in the
  /// Beautifier monorepo for the full investigation). GitHub's headless CI
  /// emulator (goldfish-opengl / swiftshader_indirect) crashes the WHOLE
  /// emulator process (`Failed to find ColorBuffer` -> `adb: device
  /// offline`, unrecoverable) when a 2nd+ [boot] starts immediately after
  /// the previous test's own unmount. Confirmed by isolating flows down to
  /// exactly one relaunch (always clean, 0 crashes) vs. two-or-more
  /// back-to-back relaunches (crashed on every one of 9+ CI samples,
  /// independent of flow content, API level 33/34, or test ordering) — the
  /// crash fires specifically on the transition INTO the 2nd relaunch, not
  /// on rendering itself. This pause gives the driver's async ColorBuffer
  /// cleanup time to actually complete host-side before the next relaunch
  /// allocates new buffers. `integration_test/`-only; no production effect.
  static Future<void> tearDownHarness() async {
    AppStartTime.resetForTest();
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  // ── Convenience: drive the login flow to completion ───────────────────────

  /// Drives the real login form with the fixture email for [role], taps Submit,
  /// and waits for the app to settle on the authenticated home screen.
  ///
  /// Navigation is key-driven (no raw-text tap drivers per policy).
  static Future<void> loginAs(
    WidgetTester tester,
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

    // Drain any in-flight splash→login redirect / route transition BEFORE
    // touching the form. Flake guard (phase 17.1): boot()'s single pumpAndSettle
    // can return just before the auth-resolution microtask fires the
    // /splash→/login redirect, so without this the form is mid-transition. A tap
    // during a transition lands on the route barrier (RenderAbsorbPointer /
    // RenderOffstage / RenderIgnorePointer in the hit path) and is SWALLOWED, so
    // _submit() never runs (loginCalls stays 0 → "Expected 1, Actual 0").
    // Bounded by [settleTimeout] (Fix #2): a hang here fails ONE test cleanly
    // instead of corrupting the shared isolate's binding mid-frame.
    await settle(tester);

    // We should be on the login screen — fill the fields and submit.
    await tester.enterText(
      find.byKey(const ValueKey<String>('login_email')),
      email,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login_password')),
      'Secret1234',
    );
    await settle(tester);

    // Ensure the submit button is on-screen + interactive before tapping
    // (best-effort: only scrolls if the form has a Scrollable ancestor).
    final Finder submit = find.byKey(const ValueKey<String>('login_submit'));
    try {
      await tester.ensureVisible(submit);
      await settle(tester);
    } catch (_) {
      // No scrollable ancestor / already fully visible — nothing to do.
    }

    // Tap submit and confirm it actually triggered _submit(). If the tap was
    // absorbed (loginCalls did not advance), settle and retry ONCE, then fail
    // loudly AT THE CAUSE rather than as a confusing downstream navigation
    // assertion. loginCalls is captured relative to its prior value so repeat
    // loginAs() calls within one test stay correct.
    final int callsBefore = fakeBackend.loginCalls;
    await tester.tap(submit);
    await tester.pump();
    await tester.pump();
    if (fakeBackend.loginCalls == callsBefore) {
      await settle(tester);
      await tester.tap(submit);
      await tester.pump();
      await tester.pump();
    }
    expect(
      fakeBackend.loginCalls,
      greaterThan(callsBefore),
      reason:
          'login_submit tap did not trigger _submit() — the button was absorbed '
          'by an in-flight overlay/route transition (see app_harness flake guard)',
    );

    // Pump until all auth microtasks and router redirects settle:
    //   1. pump()     — tap event is processed; _submit() suspends at await login()
    //   2. pump()     — login() HTTP fake-backend call resolves (microtask),
    //                    authProvider → AsyncData(Authenticated), AuthRefreshNotifier
    //                    fires, GoRouter redirect runs, router navigates
    //   3. pump()     — Router widget rebuilds with new route; new screen mounts;
    //                    masterProfileProvider fetch fires (for INDEPENDENT_MASTER)
    //   4–5. pump()   — masterProfileProvider resolves; AnimationController.forward()
    //                    starts the 1100 ms entrance animation
    //   pumpAndSettle — advances the fake clock through the full animation duration
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await settle(tester);
  }
}

// ---------------------------------------------------------------------------
// _HarnessApp — the real MaterialApp.router without main()'s side-effects
// ---------------------------------------------------------------------------

/// Boots the real app using [appRouterProvider] from the enclosing ProviderScope.
///
/// Bypasses the main() entry-point side-effects that are incompatible with
/// flutter_test (cert-pinning, FlutterNativeSplash, SystemChrome). All of
/// those are platform-channel calls that flutter_test's binding does not route.
/// The router, theme, and localisation delegates are identical to production.
class _HarnessApp extends ConsumerWidget {
  const _HarnessApp();

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
