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
// `l10n.logoutFailed` SnackBar ("Вихід не вдався. Спробуйте ще раз.") to the
// user — logout appearing to fail even though the local token wipe ran.
//
// That assert fires ONLY in debug builds. Unit/widget tests that override
// authProvider with a stub do NOT reproduce it because the stub has no real
// masterProfile→authProvider back-edge. `integration_test/` runs in a DEBUG
// build AND drives the REAL provider graph, so it is the only tier that
// reproduces — and now regression-guards — the cyclic-invalidation bug.
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
// SnackBar is NOT shown AND the server revocation endpoint was hit once.
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // Locale-pinned UK strings used ONLY for absence assertions (the harness
  // pins the app to uk_UA). We must NOT see the logout-failure SnackBar.
  final AppLocalizationsUk l10n = AppLocalizationsUk();

  testWidgets(
    'INDEPENDENT_MASTER logout from settings hub lands on /login without the '
    'logoutFailed SnackBar (regression: cyclic masterProfile→auth invalidation)',
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
        router.routerDelegate.currentConfiguration.uri.toString(),
        startsWith(RouteNames.masterProfile),
        reason:
            'login must land on the real /master/profile screen so the '
            'masterProfile→auth provider cascade is mounted before logout',
      );

      // Open the settings hub (the screen that owns the logout row).
      await tester.tap(find.byKey(const Key('btn-menu-master')));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
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
      await tester.pumpAndSettle();

      // 1) Landed back on /login. If the cyclic-invalidation bug were present,
      //    logout() would have thrown CircularDependencyError, context.go(login)
      //    would never run, and we'd still be on /master/menu.
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        startsWith(RouteNames.login),
        reason: 'a successful logout must navigate to /login',
      );
      expect(
        find.byKey(const ValueKey<String>('login_email')),
        findsOneWidget,
        reason: 'the login form must be rendered after logout',
      );

      // 2) The failure SnackBar must NOT be shown. This is the direct symptom
      //    the cyclic-invalidation bug produced for the user.
      expect(
        find.text(l10n.logoutFailed),
        findsNothing,
        reason:
            'logout must succeed end-to-end — the "${l10n.logoutFailed}" '
            'SnackBar means logout() threw (the cyclic-invalidation regression)',
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
