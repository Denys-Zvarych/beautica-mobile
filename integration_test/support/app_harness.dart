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
  static Future<GoRouter> boot(
    WidgetTester tester,
    FakeBackend fakeBackend, {
    List<Object> extraOverrides = const <Object>[],
  }) async {
    installOverflowGuard();

    // RC1 — prime the splash-duration gate so the auth redirect is not stuck
    // on /splash. [AppStartTime.elapsed()] must return > [minSplashDuration]
    // (3 000 ms) on the very first frame. We set the recorded start to 5 s
    // ago — safely past the gate in every build mode. Without this call,
    // elapsed() returns Duration.zero (null _start → fallback) and the guard
    // loops back to /splash indefinitely.
    AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );

    final storage = FakeSecureStorage();

    await tester.pumpWidget(
      ProviderScope(
        // ProviderScope.overrides accepts List<Override>; we cast so callers
        // can pass a plain list without importing the internal Override type.
        // ignore: avoid_dynamic_calls
        overrides: <Object>[
          dioProvider.overrideWithValue(fakeBackend.dio),
          secureStorageProvider.overrideWithValue(storage),
          clockProvider.overrideWithValue(() => kFixedNow),
          ...extraOverrides,
        ].cast(),
        child: const _HarnessApp(),
      ),
    );

    // Allow the splash screen to resolve and the auth guard to redirect to
    // /login (unauthenticated cold start) or the role-appropriate home.
    await tester.pumpAndSettle();

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
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
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

  /// Resets [AppStartTime] to its pre-boot null state.
  ///
  /// Must be called in [tearDown] in every test file that uses [boot], so the
  /// splash-gate override does not leak into subsequent tests. Idempotent.
  static void tearDownHarness() => AppStartTime.resetForTest();

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

    // We should be on the login screen — fill the fields and submit.
    await tester.enterText(
      find.byKey(const ValueKey<String>('login_email')),
      email,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('login_password')),
      'Secret1234',
    );
    await tester.tap(find.byKey(const ValueKey<String>('login_submit')));

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
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
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
