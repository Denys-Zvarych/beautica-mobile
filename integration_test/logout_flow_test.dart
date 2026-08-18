// END-TO-END integration test for the LOGOUT flow.
//
// WHY THIS FILE EXISTS (the bug it guards)
// ----------------------------------------
// AuthNotifier.logout() used to `ref.invalidate(...)` the masterProfile /
// serviceRepository / servicesList providers. Each of those transitively
// `ref.watch(authProvider)` (masterProfileProvider directly; serviceRepository
// and servicesList through it), so invalidating them from INSIDE the auth
// notifier records a back-edge that closes a dependency cycle. Riverpod's
// CircularDependencyError assert (kDebugMode ONLY) then throws, escapes the
// state transition, and the settings-hub catch-block surfaces the
// `l10n.logoutFailed` VelvetSnack ("Вихід не вдався. Спробуйте ще раз.") to the
// user — logout appearing to fail even though the local token wipe ran.
//
// That assert fires ONLY in debug builds. Unit/widget tests that override
// authProvider with a stub do NOT reproduce it because the stub has no real
// masterProfile→authProvider back-edge. `flutter test integration_test/` runs
// in a DEBUG build AND drives the REAL provider graph, so it is the only tier
// that reproduces — and now regression-guards — the cyclic-invalidation bug.
//
// CAVEAT — THE PROFILE DRIVE DOES NOT RE-GUARD THIS (noted 2026-07-22). This
// same file is ALSO run by the `integration-profile` CI job via
// `flutter drive --profile`, where asserts are STRIPPED. There,
// `_debugAssertCanDependOn` cannot fire at all, so this test can never fail
// for the reason documented above — it degrades to a plain "the auth flow
// still works with asserts off" smoke test. That is still worth running (it is
// how the silently-dropped `enterText` bug was found), but the DEBUG run is
// the only one that guards the cyclic-invalidation regression. Do not treat a
// green profile drive as coverage for it.
//
// HOW THIS TEST EXERCISES THE REAL CASCADE (no auth stub)
// -------------------------------------------------------
// Rather than override authProvider with a stub session, it drives the REAL
// login flow via AppHarness.loginAs() against the FakeBackend. That:
//   • runs the real AuthNotifier.build()/login(),
//   • lands on the REAL MasterProfileScreen at /master/profile, which MOUNTS
//     the real masterProfileProvider (→ serviceRepository → servicesList),
//   • so by the time logout() runs, the exact watcher graph that closed the
//     cycle is live. This is the whole point — the bug only manifests when
//     those providers are actually mounted and watching authProvider.
//
// Only the network SOCKET is faked (Phase 17.3 FakeBackend / DioAdapter).
//
// FLOW: login as INDEPENDENT_MASTER → land on /master/profile → open the
// settings hub (btn-menu-master → /master/menu) → tap the logout row →
// confirm the dialog → assert the app lands on /login AND the logoutFailed
// VelvetSnack is NOT shown AND the server revocation endpoint was hit once.
//
// KEY-BASED NAVIGATION POLICY (enforced, see app_harness.dart): all taps use
// find.byKey(); Ukrainian strings appear ONLY in absence-assertions.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// Bounded poll for the router settling on [RouteNames.login] after the
/// logout confirm tap.
///
/// WHY NOT `pumpAndSettle()` (confirmed flaky in CI — diagnosed, not
/// hypothesized): `_loggingOut` in `settings_hub_screen.dart` is a bare
/// `ValueNotifier<bool>` with no `ValueListenableBuilder`/`AnimatedBuilder`
/// consumer anywhere, so nothing schedules frames while
/// `runLogoutFlow`'s `await ref.read(authProvider.notifier).logout()`
/// (`logout_action.dart`) is in flight — a real Keystore wipe. A plain
/// unfinished `Future` with no frame-scheduling work does not hold
/// `pumpAndSettle()` open, so once the confirm dialog's pop animation
/// settles, `pumpAndSettle()` can return BEFORE `logout()` resolves and
/// `context.go(RouteNames.login)` runs. CI evidence: failing run landed on
/// `/master/menu` with 32 skipped frames / 396.59 ms avg frame; the passing
/// run (34 skipped frames / 303.09 ms avg) simply outran the same race.
///
/// WHY NOT [AppHarness.pumpUntilCondition]: that helper deliberately THROWS
/// a `TestFailure` on timeout so a genuine hang fails fast — exactly right
/// for boot/login. Here we want the OPPOSITE on timeout: fall through
/// silently so the `expect(AppHarness.location(router), ...)` a few lines
/// below still runs and reports the real location plus this test's own
/// `reason:`, rather than a generic "timed out waiting for X" message. That
/// is a different contract from the shared helper, so it stays local rather
/// than becoming a second exported variant.
///
/// Still bites a genuine regression: if `logout()` never navigates, this
/// loop simply exhausts its timeout and returns — the assertion below then
/// fails with the real (stale) location, exactly as it would have with a
/// hung `pumpAndSettle()`, just without the false negative on a slow frame.
Future<void> _pumpUntilLoggedOut(
  WidgetTester tester,
  GoRouter router, {
  Duration timeout = const Duration(seconds: 10),
  Duration step = const Duration(milliseconds: 100),
}) async {
  // instant-ok: elapsed-wall-time poll deadline, mirrors AppHarness.pumpUntilFound/pumpUntilCondition
  final DateTime deadline = DateTime.now().add(timeout);
  while (!AppHarness.location(router).startsWith(RouteNames.login)) {
    // instant-ok: elapsed-wall-time poll deadline, paired with the read above
    if (DateTime.now().isAfter(deadline)) break;
    await tester.pump(step);
  }
  // One extra frame so a condition that just went true is fully built before
  // the caller inspects it (mirrors AppHarness.pumpUntilFound/Condition).
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // Locale-pinned UK strings used ONLY for absence assertions (the harness
  // pins the app to uk_UA). We must NOT see the logout-failure VelvetSnack.
  final AppLocalizationsUk l10n = AppLocalizationsUk();

  testWidgets(
    'INDEPENDENT_MASTER logout from settings hub lands on /login without the '
    'logoutFailed VelvetSnack (regression: cyclic masterProfile→auth invalidation)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);

      // Cold start → /login. Drive the REAL login flow so the REAL
      // masterProfileProvider (and its serviceRepository/servicesList watchers)
      // mount on the master profile screen — this is what closes the cycle.
      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // Authenticated → on the real master profile screen.
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterProfile),
        reason:
            'login must land on the real /master/profile screen so the '
            'masterProfile→auth provider cascade is mounted before logout',
      );

      // Open the settings hub (the screen that owns the logout row).
      await tester.tap(find.byKey(const Key('btn-menu-master')));
      await tester.pumpAndSettle();
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterMenu),
        reason: 'menu icon must push the settings hub at /master/menu',
      );

      // Tap the terminal logout row → raises the confirm dialog. The row sits
      // at the bottom of the hub Column; ensureVisible guards against an
      // off-screen hit-test miss (matches the settings-hub widget test).
      expect(find.byKey(const Key('row-logout')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('row-logout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('row-logout')));
      await tester.pumpAndSettle();

      // Confirm the dialog → runLogoutFlow → REAL authProvider.logout().
      expect(
        find.byKey(const Key('btn-logout-confirm')),
        findsOneWidget,
        reason: 'logout row must raise the confirm dialog',
      );
      await tester.tap(find.byKey(const Key('btn-logout-confirm')));
      // Pump through: dialog pop → logout() server call (fake) → secure-storage
      // wipe → state flips Unauthenticated → masterProfile/services watchers
      // rebuild (the cascade) → context.go(/login) → router redirect settles.
      //
      // BOUNDED POLL, NOT pumpAndSettle() — see _pumpUntilLoggedOut's doc
      // comment for the confirmed CI race this replaces.
      await _pumpUntilLoggedOut(tester, router);

      // 1) Landed back on /login. If the cyclic-invalidation bug were present,
      //    logout() would have thrown CircularDependencyError, context.go(login)
      //    would never run, and we'd still be on /master/menu.
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.login),
        reason: 'a successful logout must navigate to /login',
      );
      expect(
        find.byKey(const ValueKey<String>('login_email')),
        findsOneWidget,
        reason: 'the login form must be rendered after logout',
      );

      // 2) The failure VelvetSnack must NOT be shown. This is the direct symptom
      //    the cyclic-invalidation bug produced for the user.
      expect(
        find.text(l10n.logoutFailed),
        findsNothing,
        reason:
            'logout must succeed end-to-end — the "${l10n.logoutFailed}" '
            'VelvetSnack means logout() threw (the cyclic-invalidation regression)',
      );

      // 3) The server-side revocation endpoint was hit exactly once (best-effort
      //    revoke runs before the local wipe).
      expect(
        fb.logoutCalls,
        equals(1),
        reason:
            'logout() must call POST /auth/logout once before wiping local '
            'state',
      );
    },
  );
}
