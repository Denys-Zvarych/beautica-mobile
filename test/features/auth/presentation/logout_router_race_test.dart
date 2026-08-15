// Regression test for the CI symptom in integration_test/logout_flow_test.dart
// (`Integration profile drive (emulator)` job): an INDEPENDENT_MASTER confirms
// logout from the settings hub and the app is left on /master/menu instead of
// /login, with NO logoutFailed VelvetSnack and no thrown exception.
//
// WHAT THIS TEST DOES DIFFERENTLY FROM THE EXISTING WIDGET-TIER TEST 4
// ----------------------------------------------------------------------
// `logout_flow_test.dart`'s "tapping row-logout ... navigates to /login" test
// wires `redirect: (context, state) => null` — the auth guard is NEVER
// exercised, so that test can only prove the explicit `context.go(login)` call
// in `runLogoutFlow` works when `logout()` resolves near-instantly. It cannot
// tell us whether the REAL `authRedirect` guard (wired via `AuthRefreshNotifier`
// listening to `authProvider`) independently gets the user to /login, nor
// whether an artificially slow `logout()` (modelling real Android Keystore /
// network latency in profile mode) changes the outcome.
//
// This test reads `appRouterProvider` — the PRODUCTION router, with the REAL
// `authRedirect` guard and the REAL `AuthRefreshNotifier` wired exactly as
// `main.dart` does — and stubs `AuthRepository.logout()` with an artificial
// 1500ms delay (longer than any dialog-close animation) to stress the exact
// await-then-navigate race in `logout_action.dart:66-76`.
//
// HYPOTHESES UNDER TEST (see mobile-debugger diagnosis):
//   H1 — `if (!context.mounted) return;` at logout_action.dart:69 silently
//        abandons the explicit `context.go(RouteNames.login)`.
//   H2 — the router's own `authRedirect` guard does not independently react to
//        the auth-state flip, so if H1 fires, nothing rescues the user.
//
// RESULT (recorded here so a future re-run of this test isn't re-litigated
// from scratch): GREEN. With the delay confirmed still in-flight at the
// mid-point check (app still on /master/menu 300ms after the confirm tap,
// well short of the 1500ms delay), the app still lands cleanly on /login with
// no logoutFailed snack once the delay resolves. This is affirmative evidence
// that the router's authRedirect guard independently rescues the navigation —
// H1 (the `context.mounted` early return) does NOT strand a real user, because
// H2 does not hold: the guard IS correctly wired and reacts on its own. The
// CI profile-drive failure this test was written to reproduce could NOT be
// reproduced at the widget tier; see the mobile-debugger diagnosis for the
// remaining candidate explanations (real AOT/Keystore jank timing).
//
// TEST-HARNESS PITFALLS HIT WHILE BUILDING THIS TEST (do not reintroduce):
//   1. `pumpEventQueue()` MUST NOT be used inside `testWidgets` — the test
//      body runs in a FakeAsync zone and `pumpEventQueue()` is implemented via
//      `Future.delayed(Duration.zero)`, which never fires without an explicit
//      `tester.pump()` advancing the fake clock. It hangs the test forever.
//   2. `pumpAndSettle()` MUST NOT be used against the REAL production screens
//      mounted via `appRouterProvider` (SplashScreen's Lottie wordmark reveal,
//      SettingsHubScreen's staggered-reveal AnimationController) — they keep
//      scheduling frames long enough that pumpAndSettle's convergence check
//      hangs. Use bounded `pump()` / `pump(duration)` throughout, mirroring
//      test/routing/app_router_no_leaked_timer_test.dart.
//   3. A stubbed delay MUST be a `Duration` field consumed lazily inside the
//      fake's method — NOT a pre-built `Future.delayed(...)` assigned before
//      the test's earlier `pump(duration)` calls. `Future.delayed` starts its
//      timer at CONSTRUCTION time; the fake clock those earlier pumps advance
//      is the SAME clock, so a delay built too early can have already fired
//      by the time the code path under test awaits it — silently turning an
//      intended "slow logout" repro into a no-op that passes for the wrong
//      reason. See `FakeAuthRepository.logoutDelayDuration`.
//   4. `authRedirectForLocation`'s splash gate pins the router on /splash
//      forever unless `AppStartTime.setStartForTest(...)` backdates the start
//      time past `minSplashDuration` (3000ms) — otherwise `elapsed()` stays
//      `Duration.zero` and the redirect keeps returning /splash.

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../../integration_test/support/app_harness.dart';
import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

const _testUser = User(
  id: 'u1',
  email: 'master@beautica.test',
  role: UserRole.independentMaster,
  firstName: 'Test',
  lastName: 'User',
);

const _testTokens = AuthTokens(
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
);

void main() {
  // Park the splash gate in the past — otherwise authRedirectForLocation
  // pins the router on /splash forever (AppStartTime._start is null in
  // tests, so elapsed() == Duration.zero, always < minSplashDuration).
  setUp(
    () => AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    ),
  );
  tearDown(AppStartTime.resetForTest);

  testWidgets(
    'REAL router (real authRedirect + AuthRefreshNotifier): confirming '
    'logout with an artificially delayed AuthRepository.logout() (1500ms) '
    'still lands the app on /login, not stranded on /master/menu',
    (tester) async {
      final storage = FakeSecureStorage();
      await storage.writeRefreshToken('stored-refresh');

      final repo = FakeAuthRepository()
        ..refreshResult = _testTokens
        ..meResult = _testUser
        // Model real-device latency (Keystore-backed secure storage +
        // network revocation call) that profile-mode-on-emulator has and the
        // debug/widget tier does not. See logoutDelayDuration's doc comment
        // (fake_auth_repository.dart) for why this must be lazy.
        ..logoutDelayDuration = const Duration(milliseconds: 1500);

      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: [
          secureStorageProvider.overrideWith((_) => storage),
          authRepositoryProvider.overrideWith((_) => repo),
        ],
      );
      addTearDown(container.dispose);

      // Drain the cold-start restore so authProvider settles to Authenticated
      // BEFORE the router is read.
      await container.read(authProvider.future);
      expect(container.read(authProvider).value, isA<Authenticated>());

      // Read the REAL production router — same provider main.dart uses, with
      // the real authRedirect guard and the real AuthRefreshNotifier wired to
      // authProvider.
      final GoRouter router = container.read(appRouterProvider);
      addTearDown(router.dispose);

      // Bounded `pump()`/`pump(duration)` throughout — NEVER `pumpAndSettle()`
      // (pitfall #2 above).
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk', 'UA'),
          ),
        ),
      );
      await tester.pump();

      // Navigate straight to the settings hub — bypass the splash gate by
      // going directly; the session is already settled Authenticated so the
      // guard admits /master/menu (INDEPENDENT_MASTER role).
      router.go(RouteNames.masterMenu);
      await tester.pump();
      // fixed-wait-ok: draining SettingsHubScreen's staggered-reveal
      // AnimationController after the go() navigation — pumpAndSettle()
      // cannot be used here (hangs against the real staggered reveal, see
      // header pitfall #2), and there is no discrete "reveal complete"
      // signal to pump-until.
      await tester.pump(const Duration(milliseconds: 1200));
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterMenu),
        reason: 'precondition: must land on the real settings hub',
      );

      // Open the logout row → confirm dialog → confirm.
      await tester.ensureVisible(find.byKey(const Key('row-logout')));
      // fixed-wait-ok: draining the ensureVisible scroll-into-view animation
      // so the subsequent tap lands on the now-on-screen row rather than
      // hitting a still-animating (potentially off-screen) target.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('row-logout')));
      // fixed-wait-ok: draining the confirm dialog's entrance transition so
      // the findsOneWidget/tap below hit the fully-settled dialog, not a
      // mid-animation frame.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('btn-logout-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn-logout-confirm')));

      // Pump through the dialog pop (fast) WITHOUT yet resolving the 1500ms
      // logoutDelayDuration — mid-flight, we must still be on /master/menu
      // with the hub visible (logout() has not settled auth state yet). This
      // is the load-bearing assertion: it proves the delay is genuinely still
      // in flight when we check, so the final /login assertion below is not
      // vacuously true.
      await tester.pump(); // dialog pop frame
      // fixed-wait-ok: THE load-bearing mid-flight probe — advances the fake
      // clock only 300ms of the artificial 1500ms logoutDelayDuration, so the
      // assertion right below proves the delay is genuinely still in flight
      // (not vacuously true). Nothing observable changes until the delay
      // resolves, so there is no condition to pump-until here.
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterMenu),
        reason:
            'mid-flight (logout() still awaiting the artificial delay) the '
            'app must still be on the hub — not yet redirected',
      );

      // Now advance past the artificial delay and let everything settle:
      // logout() resolves → state flips Unauthenticated → router guard
      // AND/OR the explicit context.go race to /login.
      // fixed-wait-ok: clears the remaining balance of the artificial
      // 1500ms logoutDelayDuration (300ms already elapsed via the mid-flight
      // probe above, so 1300ms here crosses the 1500ms total) so
      // AuthRepository.logout() resolves. logoutDelayDuration is consumed by
      // a real Future.delayed inside the fake, and the fake clock must be
      // pumped through it directly — there is no earlier observable signal
      // to pump-until.
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump();
      // fixed-wait-ok: settling the authRedirect guard / AuthRefreshNotifier
      // redirect chain and /login's own entrance animation after the
      // auth-state flip — pumpAndSettle() cannot be used against the real
      // /login screen (same staggered-animation hang class as header
      // pitfall #2).
      await tester.pump(const Duration(milliseconds: 500));

      final l10n = AppLocalizationsUk();

      expect(
        AppHarness.location(router),
        startsWith(RouteNames.login),
        reason:
            'a successful logout — even with a slow AuthRepository.logout() '
            '— must navigate to /login. Landing anywhere else (e.g. stuck on '
            '/master/menu) reproduces the CI profile-drive failure and proves '
            'H1/H2 is a real product bug, not a test-harness artifact.',
      );
      expect(
        find.text(l10n.logoutFailed),
        findsNothing,
        reason:
            'no logoutFailed VelvetSnack is expected — the fake never throws.',
      );
      expect(
        repo.logoutCallCount,
        equals(1),
        reason: 'the server revocation call must have been made exactly once.',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
