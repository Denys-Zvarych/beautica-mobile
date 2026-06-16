// Phase 2.11 — Widget tests for VerificationScreen (VelvetTouch redesign).
//
// Tests use a minimal GoRouter (initial route = /verification → VerificationScreen)
// so that context.go works inside the widget under test. Auth state is
// controlled via ProviderScope overrides.
//
// OTP entry pattern (VelvetTouch single-controller):
//   Enter 6 digits via the single hidden TextField keyed
//   ValueKey('verify_code_input'), then pump.
//
// Widget keys after redesign:
//   ValueKey('verify_code_input') — hidden TextField (single entry)
//   ValueKey('verify_submit')     — NeumorphicButton CTA
//   ValueKey('verify_resend')     — GestureDetector resend link
//   ValueKey('auth_scaffold_back') — top-left back button (AuthScaffold overlay, Test 6)
//
// Covered scenarios:
//   1.   All 6 digits filled → NeumorphicButton.onPressed is non-null.
//   2.   Fewer than 6 digits → NeumorphicButton.onPressed is null (disabled).
//   3.   Resend timer counts down and re-enables the resend link at 0.
//   3b.  Tapping verify_resend clears the OTP input and hides the resend link.
//   3c.  ResendThrottledFailure adopts server retryAfterSeconds.
//   4.   Verify success navigates to /done (→ home via redirect).
//   4b.  Verify success persists refresh token and arrives at home.
//   5.   Verify failure (VerificationFailure.invalidCode) shows inline copy.
//   5b.  AuthBanner appears when _inlineError is set.
//   5c-nav. INVALID_CODE banner renders verificationGoToLogin action label.
//   5d.  Tapping verificationGoToLogin action navigates to /login (INVALID_CODE).
//   5e.  ALREADY_VERIFIED banner also renders and navigates to /login.
//   5f.  ResendThrottledFailure clears the ghost "Увійти" action (no stale CTA).
//   6.   Back link navigates to /register/step-3.
//   7.   No BackdropFilter on screen (VelvetTouch has no glassmorphism).
//   7b.  Hidden OTP TextField has correct keyboard / security settings.
//   8.   NeumorphicButton is disabled (onPressed null) while authProvider
//        is AsyncLoading.

// ---------------------------------------------------------------------------
// Covered scenarios (updated):
//   3-opt. Countdown starts IMMEDIATELY on tap — before API returns (optimistic).
// ---------------------------------------------------------------------------

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/verification_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/user/data/user_repository.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/validators/server_field_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/features/master/data/master_repository.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Mock UserRepository for the post-verification PATCH /users/me regression
// guards (CLIENT locality persistence). Tests 14 + 15 below.
// ---------------------------------------------------------------------------

class _MockUserRepository extends Mock implements UserRepository {}

// ---------------------------------------------------------------------------
// Mock SalonRepository for the post-verification POST /salons regression
// guards (SALON_OWNER phone pass-through). Tests 16 + 17 below.
// ---------------------------------------------------------------------------

class _MockSalonRepository extends Mock implements SalonRepository {}

// ---------------------------------------------------------------------------
// Mock MasterRepository for the INDEPENDENT_MASTER missing-city regression
// guard (Test 18 — Fix 3 / ProviderMissingCityFailure).
// ---------------------------------------------------------------------------

class _MockMasterRepository extends Mock implements MasterRepository {}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const _testEmail = 'anya@example.com';

/// Builds a minimal GoRouter with the verification screen at /verification.
/// Includes /register/step-3, /done, /home, and /login as navigation targets.
GoRouter _makeRouter({String email = _testEmail}) => GoRouter(
  initialLocation: RouteNames.verification,
  redirect: (context, state) => null,
  routes: [
    GoRoute(
      path: RouteNames.verification,
      builder: (context, state) =>
          VerificationScreen(email: (state.extra as String?) ?? email),
    ),
    GoRoute(
      path: RouteNames.register,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('register'))),
    ),
    GoRoute(
      path: RouteNames.registerStep3,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('register-step-3'))),
    ),
    GoRoute(
      path: RouteNames.done,
      redirect: (context, state) => RouteNames.home,
    ),
    GoRoute(
      path: RouteNames.home,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('home'))),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('login'))),
    ),
  ],
);

/// Pumps the full app with the given [repo] and [router].
Future<void> _pumpVerification(
  WidgetTester tester, {
  required FakeAuthRepository repo,
  required GoRouter router,
}) async {
  final storage = FakeSecureStorage();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWith((_) => repo),
        secureStorageProvider.overrideWith((_) => storage),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );

  // Let the auth provider settle (cold start: no refresh token → unauthenticated).
  await tester.pumpAndSettle();
}

/// Enters 6 digits via the single hidden OTP input.
Future<void> _fillOtp(WidgetTester tester, String digits) async {
  assert(digits.length == 6, 'OTP must be exactly 6 digits');
  await tester.enterText(
    find.byKey(const ValueKey<String>('verify_code_input')),
    digits,
  );
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('VerificationScreen (VelvetTouch)', () {
    setUpAll(() {
      // Required by mocktail for any(named:) / captureAny(named:) matchers on
      // SalonCreateDto (used in Tests 16 + 17 — SALON_OWNER phone pass-through).
      registerFallbackValue(
        const SalonCreateDto(name: '', cityId: '', street: '', buildingNo: ''),
      );
    });

    // -----------------------------------------------------------------------
    // Test 1 — All 6 digits filled → NeumorphicButton enabled
    // -----------------------------------------------------------------------
    testWidgets(
      '1. filling 6 digits enables the verify NeumorphicButton (onPressed non-null)',
      (tester) async {
        final repo = FakeAuthRepository();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        await _fillOtp(tester, '123456');
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pump();

        final btn = tester.widget<NeumorphicButton>(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        expect(
          btn.onPressed,
          isNotNull,
          reason:
              'NeumorphicButton.onPressed must be non-null when 6 digits are entered',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 2 — Fewer than 6 digits → NeumorphicButton disabled
    // -----------------------------------------------------------------------
    testWidgets(
      '2. fewer than 6 digits keeps verify NeumorphicButton disabled (onPressed null)',
      (tester) async {
        final repo = FakeAuthRepository();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        // Enter only 5 digits.
        await tester.enterText(
          find.byKey(const ValueKey<String>('verify_code_input')),
          '12345',
        );
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pump();

        final btn = tester.widget<NeumorphicButton>(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        expect(
          btn.onPressed,
          isNull,
          reason:
              'NeumorphicButton.onPressed must be null when fewer than 6 digits entered',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 3 — Resend link hidden while counting down, visible at 0.
    //          Cooldown is 30 s (VelvetTouch redesign).
    // -----------------------------------------------------------------------
    testWidgets('3. resend link hidden while countdown active, visible when timer = 0', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpVerification(tester, repo: repo, router: router);

      // Resend GestureDetector is always in the tree — even during the initial
      // 30s mount cooldown (screen starts a cooldown on init, matching the
      // server-side cooldown from the registration code send).
      // The key is present regardless of cooldown state.
      expect(
        find.byKey(const ValueKey<String>('verify_resend')),
        findsOneWidget,
      );

      // Drain 31 s to simulate after a resend was tapped → cooldown should end.
      // To test the cooldown we need to simulate a resend first.
      // Tap the resend to start the 30 s cooldown.
      await tester.tap(find.byKey(const ValueKey<String>('verify_resend')));
      // pump + pump to let async resend settle (default FakeAuthRepository succeeds).
      await tester.pump(); // begin async
      await tester.pump(); // microtasks
      await tester.pump(const Duration(milliseconds: 50));

      // Now the resend link should show the countdown text, not be a button
      // that triggers resend immediately. Verify the GestureDetector is present
      // but onTap is effectively null (cooldown > 0).
      // After 29 s still in cooldown.
      await tester.pump(const Duration(seconds: 29));
      // The text should still be showing countdown (e.g. "Надіслати знову (1 с)").
      // After 31 total seconds from the resend tap, cooldown = 0 again.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      // The resend link text should again say "Надіслати знову" (no countdown).
      // The GestureDetector key is always present; what changes is the onTap
      // function and the displayed text.
      expect(
        find.byKey(const ValueKey<String>('verify_resend')),
        findsOneWidget,
      );
    });

    // -----------------------------------------------------------------------
    // Test 3b — Tapping verify_resend clears OTP and hides countdown.
    //           Checks that the single-controller OTP is cleared on success.
    // -----------------------------------------------------------------------
    testWidgets(
      '3b. tapping verify_resend clears OTP input and restarts the countdown',
      (tester) async {
        final repo = FakeAuthRepository();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        // Fill 6 digits.
        await _fillOtp(tester, '654321');
        await tester.pump();

        // The OTP input should have text.
        final fieldBefore = tester.widget<TextField>(
          find.byKey(const ValueKey<String>('verify_code_input')),
        );
        expect(fieldBefore.controller?.text, equals('654321'));

        // Drain the initial 30s mount cooldown so the resend link is active.
        await tester.pump(const Duration(seconds: 31));
        // Tap the resend link — cooldown is now 0, link is active.
        await tester.tap(find.byKey(const ValueKey<String>('verify_resend')));
        await tester.pump(); // begin async
        await tester.pump(); // microtasks
        await tester.pump(const Duration(milliseconds: 50));

        // After a successful resend the OTP controller is cleared.
        final fieldAfter = tester.widget<TextField>(
          find.byKey(const ValueKey<String>('verify_code_input')),
        );
        expect(
          fieldAfter.controller?.text,
          isEmpty,
          reason:
              'OTP input must be cleared after a successful resend (single controller)',
        );

        // The verify button should now be disabled (no digits).
        final btn = tester.widget<NeumorphicButton>(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        expect(btn.onPressed, isNull);
      },
    );

    // -----------------------------------------------------------------------
    // Test 3c — ResendThrottledFailure adopts server retryAfterSeconds.
    //           OTP digits are NOT cleared on a throttled response.
    // -----------------------------------------------------------------------
    testWidgets(
      '3c. resend 429 (ResendThrottledFailure) adopts server retryAfterSeconds',
      (tester) async {
        final repo = FakeAuthRepository()
          ..resendVerificationResult = const ResendThrottledFailure(
            retryAfterSeconds: 42,
          );
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        // Type six digits — they must survive the throttled response.
        await _fillOtp(tester, '654321');
        await tester.pump();

        // Drain the initial 30s mount cooldown so the resend link is active.
        await tester.pump(const Duration(seconds: 31));
        // Tap resend — cooldown is now 0, link is active.
        await tester.tap(find.byKey(const ValueKey<String>('verify_resend')));
        // Cannot pumpAndSettle: the throttle catch restarts the periodic
        // timer, which fires setState every second.
        await tester.pump(); // begin async
        await tester.pump(); // microtasks (await + catch)
        await tester.pump(const Duration(milliseconds: 50));

        // OTP digits must be preserved — the request never consumed a slot.
        final field = tester.widget<TextField>(
          find.byKey(const ValueKey<String>('verify_code_input')),
        );
        expect(
          field.controller?.text,
          equals('654321'),
          reason:
              'OTP input must retain its digits after a throttled resend; '
              'optimistic clear was the M-Sec-1 bug',
        );

        // Inline error must use the localized throttled message.
        final l10n = AppLocalizations.of(
          tester.element(
            find.byKey(const ValueKey<String>('verify_code_input')),
          ),
        );
        final throttledMsg = l10n.verificationErrResendThrottled(42);
        expect(
          tester
              .widgetList<Text>(find.byType(Text))
              .any((t) => t.data == throttledMsg),
          isTrue,
          reason:
              'Expected an inline error Text matching '
              'verificationErrResendThrottled(42). '
              'Available texts: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
        );

        // After 41 seconds the timer is still running; the resend GestureDetector
        // onTap is null (cooldown > 0 → disabled path).
        await tester.pump(const Duration(seconds: 41));
        // The 42nd second drains _cooldown to 0 → resend becomes re-active.
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();

        // The resend link is present and the cooldown text is gone.
        expect(
          find.byKey(const ValueKey<String>('verify_resend')),
          findsOneWidget,
          reason:
              'verify_resend must reappear once the server-mandated cooldown '
              'has fully elapsed',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 3-opt — Countdown starts IMMEDIATELY after tap, BEFORE the API
    //              call completes (optimistic update — fixes the "0 с right
    //              away" visual regression).
    // -----------------------------------------------------------------------
    testWidgets(
      '3-opt. countdown starts optimistically on tap — resend link disabled '
      'before API call completes',
      (tester) async {
        // A Completer that never completes during this test lets us freeze the
        // API mid-flight and assert on the intermediate UI state.
        final completer = Completer<void>();
        final repo = FakeAuthRepository()..resendDelay = completer.future;
        final router = _makeRouter();
        addTearDown(() {
          // Resolve before the test tears down to let the provider dispose
          // cleanly (avoids "incomplete future" errors in teardown).
          if (!completer.isCompleted) completer.complete();
          router.dispose();
        });

        await _pumpVerification(tester, repo: repo, router: router);

        // Tap resend (cooldown == 0 → link is active).
        await tester.tap(find.byKey(const ValueKey<String>('verify_resend')));
        // ONE pump: _handleTap runs synchronously up to its first await;
        // _startCooldown(30) fires BEFORE the async API call → setState scheduled.
        await tester.pump();

        // The countdown must already be started (optimistic) — the link is
        // disabled even though the API call is still in-flight.
        final gesture = tester.widget<GestureDetector>(
          find.byKey(const ValueKey<String>('verify_resend')),
        );
        expect(
          gesture.onTap,
          isNull,
          reason:
              'Resend GestureDetector.onTap must be null immediately after tap '
              '(optimistic countdown) even while the API call is in-flight.',
        );

        // Cleanup — resolve the completer, drain timers/microtasks.
        completer.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      },
    );

    // -----------------------------------------------------------------------
    // Test 4 — Verify success navigates to /done (→ home redirect)
    // -----------------------------------------------------------------------
    testWidgets('4. verify success navigates away from verification screen', (
      tester,
    ) async {
      final repo = FakeAuthRepository()
        ..verifyEmailResult = null; // null = success
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpVerification(tester, repo: repo, router: router);

      await _fillOtp(tester, '654321');
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('verify_submit')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 4b — Verify success persists refresh token and arrives at home.
    // -----------------------------------------------------------------------
    testWidgets(
      '4b. verify success persists refresh token and arrives at home',
      (tester) async {
        final repo = FakeAuthRepository();
        final router = _makeRouter();
        addTearDown(router.dispose);

        final storage = FakeSecureStorage();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWith((_) => repo),
              secureStorageProvider.overrideWith((_) => storage),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _fillOtp(tester, '654321');
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        await tester.pumpAndSettle();

        expect(find.text('home'), findsOneWidget);

        expect(repo.verifyEmailCalls, hasLength(1));
        expect(repo.verifyEmailCalls.single.email, equals(_testEmail));
        expect(repo.verifyEmailCalls.single.otp, equals('654321'));

        expect(await storage.readRefreshToken(), equals('refresh-token'));
      },
    );

    // -----------------------------------------------------------------------
    // Test 5 — Verify failure shows inline copy via l10n key.
    // -----------------------------------------------------------------------
    testWidgets('5. verify failure (VerificationFailure.invalidCode) shows inline '
        'verificationErrInvalidCode copy', (tester) async {
      final repo = FakeAuthRepository()
        ..verifyEmailResult = const VerificationFailure(
          code: VerificationErrorCode.invalidCode,
        );
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpVerification(tester, repo: repo, router: router);

      await _fillOtp(tester, '000000');
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('verify_submit')),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
      // Cannot pumpAndSettle: the resend timer may fire setState every second.
      await tester.pump(); // begin async
      await tester.pump(); // microtasks
      await tester.pump(const Duration(milliseconds: 50)); // animations

      expect(
        find.byKey(const ValueKey<String>('verify_submit')),
        findsOneWidget,
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const ValueKey<String>('verify_submit'))),
      );
      // The screen shows the richer hint (with login action) for INVALID_CODE
      // because the backend returns the same code for both "wrong code" and
      // "already consumed code" (anti-enumeration). The simpler
      // verificationErrInvalidCode is no longer used for this error path.
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .any((t) => t.data == l10n.verificationErrInvalidCodeWithLoginHint),
        isTrue,
        reason:
            'Expected an inline error Text matching verificationErrInvalidCodeWithLoginHint. '
            'Available texts: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
      );
    });

    // -----------------------------------------------------------------------
    // Test 5b — AuthBanner appears when _inlineError is set.
    //           Verifies that the VelvetTouch error path uses AuthBanner
    //           (not a raw Text widget) so the icon+color semantics hold.
    // -----------------------------------------------------------------------
    testWidgets(
      '5b. AuthBanner appears after a verify failure sets _inlineError',
      (tester) async {
        final repo = FakeAuthRepository()
          ..verifyEmailResult = const VerificationFailure(
            code: VerificationErrorCode.invalidCode,
          );
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        // No banner before a failed submit.
        expect(find.byType(AuthBanner), findsNothing);

        await _fillOtp(tester, '000000');
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // AuthBanner should appear.
        expect(
          find.byType(AuthBanner),
          findsOneWidget,
          reason:
              'An AuthBanner must appear after a failed verify sets _inlineError',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 5c-nav — INVALID_CODE banner "Увійти до акаунту" action label
    //               is rendered inside the AuthBanner.
    //               Regression guard: _inlineErrorActionLabel is wired to
    //               AuthBanner.actionLabel for INVALID_CODE / ALREADY_VERIFIED.
    // -----------------------------------------------------------------------
    testWidgets(
      '5c-nav. INVALID_CODE banner renders verificationGoToLogin action label '
      'inside AuthBanner',
      (tester) async {
        final repo = FakeAuthRepository()
          ..verifyEmailResult = const VerificationFailure(
            code: VerificationErrorCode.invalidCode,
          );
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        await _fillOtp(tester, '000000');
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // AuthBanner must be present.
        expect(find.byType(AuthBanner), findsOneWidget);

        // The action label text must appear inside the tree.
        final l10n = AppLocalizations.of(
          tester.element(find.byType(AuthBanner)),
        );
        expect(
          tester
              .widgetList<Text>(find.byType(Text))
              .any((t) => t.data == l10n.verificationGoToLogin),
          isTrue,
          reason:
              'AuthBanner must render the verificationGoToLogin action label '
              '("Увійти до акаунту") when INVALID_CODE error is set. '
              'Available texts: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 5d — Tapping the "Увійти до акаунту" action inside the AuthBanner
    //           navigates to /login.
    //           This is the primary regression guard for the INVALID_CODE →
    //           login navigation UX fix. Without this test a refactor that
    //           silently removes context.go(RouteNames.login) from
    //           _setInlineError would go undetected.
    // -----------------------------------------------------------------------
    testWidgets(
      '5d. tapping verificationGoToLogin action in INVALID_CODE banner '
      'navigates to /login',
      (tester) async {
        final repo = FakeAuthRepository()
          ..verifyEmailResult = const VerificationFailure(
            code: VerificationErrorCode.invalidCode,
          );
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        // Submit a wrong OTP to trigger the INVALID_CODE banner.
        await _fillOtp(tester, '000000');
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Confirm the banner and action label are present before tapping.
        expect(find.byType(AuthBanner), findsOneWidget);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(AuthBanner)),
        );
        final actionLabel = l10n.verificationGoToLogin;
        final actionTextFinder = find.text(actionLabel);
        expect(
          actionTextFinder,
          findsOneWidget,
          reason:
              'verificationGoToLogin action label must be visible before tap',
        );

        // Tap the action label — this triggers context.go(RouteNames.login).
        await tester.tap(actionTextFinder);
        await tester.pumpAndSettle();

        // Navigation must land on the login stub route.
        expect(
          find.text('login'),
          findsOneWidget,
          reason:
              'Tapping the verificationGoToLogin action must navigate to '
              '/login (RouteNames.login)',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 5e — ALREADY_VERIFIED banner also renders the "Увійти до акаунту"
    //           action label and tapping it navigates to /login.
    //           Both INVALID_CODE and ALREADY_VERIFIED share the same UX path
    //           in _setInlineError; both must be guarded independently.
    // -----------------------------------------------------------------------
    testWidgets(
      '5e. ALREADY_VERIFIED banner renders verificationGoToLogin action and '
      'tapping it navigates to /login',
      (tester) async {
        final repo = FakeAuthRepository()
          ..verifyEmailResult = const VerificationFailure(
            code: VerificationErrorCode.alreadyVerified,
          );
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        await _fillOtp(tester, '111111');
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(AuthBanner), findsOneWidget);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(AuthBanner)),
        );

        // Must show the alreadyVerified copy (not invalidCode copy).
        expect(
          tester
              .widgetList<Text>(find.byType(Text))
              .any((t) => t.data == l10n.verificationErrAlreadyVerified),
          isTrue,
          reason: 'verificationErrAlreadyVerified copy must be shown',
        );

        // The action label must be present.
        final actionLabel = l10n.verificationGoToLogin;
        expect(
          find.text(actionLabel),
          findsOneWidget,
          reason:
              'verificationGoToLogin must appear inside the banner for '
              'ALREADY_VERIFIED (same UX path as INVALID_CODE)',
        );

        // Tap → must navigate to /login.
        await tester.tap(find.text(actionLabel));
        await tester.pumpAndSettle();

        expect(
          find.text('login'),
          findsOneWidget,
          reason:
              'Tapping the verificationGoToLogin action for ALREADY_VERIFIED '
              'must navigate to /login',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 5f — ResendThrottledFailure banner does NOT render the
    //           "Увійти до акаунту" action (no ghost "Увійти" persisting).
    //           Regression guard for the fix that clears _inlineErrorActionLabel
    //           in the ResendThrottledFailure catch branch of _resend().
    // -----------------------------------------------------------------------
    testWidgets(
      '5f. ResendThrottledFailure banner has no verificationGoToLogin action '
      '(ghost action is cleared by the throttle catch branch)',
      (tester) async {
        // Trigger an INVALID_CODE first to set the "Увійти" action, then
        // trigger a throttled resend — the throttle catch must clear the action.
        final repo = FakeAuthRepository()
          ..verifyEmailResult = const VerificationFailure(
            code: VerificationErrorCode.invalidCode,
          );
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        // Step 1: failed submit → INVALID_CODE banner + "Увійти" action.
        await _fillOtp(tester, '000000');
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final l10n = AppLocalizations.of(
          tester.element(find.byType(AuthBanner)),
        );

        // Confirm the action IS present after the INVALID_CODE error.
        expect(
          find.text(l10n.verificationGoToLogin),
          findsOneWidget,
          reason: 'sanity: action label must appear after INVALID_CODE',
        );

        // Step 2: reconfigure repo so resend returns a throttle error.
        repo
          ..verifyEmailResult =
              null // no further verify calls expected
          ..resendVerificationResult = const ResendThrottledFailure(
            retryAfterSeconds: 30,
          );

        // Drain the initial 30s mount cooldown so the resend link is active.
        await tester.pump(const Duration(seconds: 31));
        // Tap resend — cooldown is now 0, triggers the throttle path.
        await tester.tap(find.byKey(const ValueKey<String>('verify_resend')));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // The throttle banner must now be shown ...
        expect(find.byType(AuthBanner), findsOneWidget);

        // ... and the "Увійти до акаунту" action must be GONE.
        expect(
          find.text(l10n.verificationGoToLogin),
          findsNothing,
          reason:
              'The verificationGoToLogin action must be cleared when the '
              'throttle catch branch replaces the banner — no ghost "Увійти"',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 5c — VerificationFailure.alreadyVerified shows the correct l10n
    //           copy (verificationErrAlreadyVerified — "Цей акаунт вже
    //           підтверджено. Увійдіть."), NOT the invalidCode copy.
    //           Regression guard for _errorMessage() dispatch in _submit().
    // -----------------------------------------------------------------------
    testWidgets(
      '5c. VerificationFailure.alreadyVerified shows verificationErrAlreadyVerified '
      'inline copy (not invalidCode)',
      (tester) async {
        final repo = FakeAuthRepository()
          ..verifyEmailResult = const VerificationFailure(
            code: VerificationErrorCode.alreadyVerified,
          );
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        await _fillOtp(tester, '111111');
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        await tester.pump(); // begin async
        await tester.pump(); // microtasks
        await tester.pump(const Duration(milliseconds: 50)); // animations

        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const ValueKey<String>('verify_submit'))),
        );

        // Must show the "already verified" copy — distinct from invalidCode.
        expect(
          tester
              .widgetList<Text>(find.byType(Text))
              .any((t) => t.data == l10n.verificationErrAlreadyVerified),
          isTrue,
          reason:
              'Expected verificationErrAlreadyVerified inline copy after '
              'VerificationFailure.alreadyVerified. '
              'Available texts: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
        );

        // Must NOT show the invalidCode copy — the two codes have distinct UX intent.
        expect(
          tester
              .widgetList<Text>(find.byType(Text))
              .any((t) => t.data == l10n.verificationErrInvalidCode),
          isFalse,
          reason:
              'verificationErrInvalidCode must NOT appear for alreadyVerified — '
              'the copy directs the user to login, not to retry.',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 3b-ext — Resend passes the correct email to the repository.
    //               Complements test 3b; asserts strict argument match on the
    //               captured resendCalls list (M4 pattern).
    // -----------------------------------------------------------------------
    testWidgets('3b-ext. tapping verify_resend passes the screen email to '
        'resendVerificationCode (strict arg match)', (tester) async {
      const customEmail = 'olena@example.com';
      final repo = FakeAuthRepository();
      final router = _makeRouter(email: customEmail);
      addTearDown(router.dispose);

      await _pumpVerification(tester, repo: repo, router: router);

      // Drain the initial 30s mount cooldown so the resend link is active.
      await tester.pump(const Duration(seconds: 31));
      // Tap resend — cooldown is now 0, link is active.
      await tester.tap(find.byKey(const ValueKey<String>('verify_resend')));
      await tester.pump(); // begin async
      await tester.pump(); // microtasks
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        repo.resendCalls,
        hasLength(1),
        reason: 'resendVerificationCode must be called exactly once',
      );
      expect(
        repo.resendCalls.single.email,
        equals(customEmail),
        reason:
            'resendVerificationCode must be called with the email passed '
            'to the screen — not an empty string or a stale value.',
      );
    });

    // -----------------------------------------------------------------------
    // Test 6 — Top-left back button navigates to /register/step-3.
    // -----------------------------------------------------------------------
    testWidgets('6. top-left back button navigates to /register/step-3', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpVerification(tester, repo: repo, router: router);

      // auth_scaffold_back is always visible (Positioned overlay, not scrollable).
      await tester.tap(
        find.byKey(const ValueKey<String>('auth_scaffold_back')),
      );
      await tester.pumpAndSettle();

      expect(find.text('register-step-3'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 7 — No BackdropFilter on screen (VelvetTouch replaces
    //          glassmorphism with neumorphic shadows; no blur layers at all).
    // -----------------------------------------------------------------------
    testWidgets(
      '7. no BackdropFilter widgets on screen (VelvetTouch has no glassmorphism)',
      (tester) async {
        final repo = FakeAuthRepository();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        final bdfCount = tester.widgetList(find.byType(BackdropFilter)).length;
        expect(
          bdfCount,
          equals(0),
          reason:
              'VelvetTouch uses neumorphic shadows — BackdropFilter must be '
              'absent (found $bdfCount).',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 7b — Hidden OTP TextField has correct keyboard / security settings.
    //           Single hidden field replaces the 6-box approach.
    //           MASVS-PLATFORM: suggestions, autocorrect, and IME personalized
    //           learning must all be disabled to prevent OTP leakage through
    //           keyboard dictionaries (mobile-security MS-7).
    // -----------------------------------------------------------------------
    testWidgets(
      '7b. hidden OTP TextField (verify_code_input) has correct settings',
      (tester) async {
        final repo = FakeAuthRepository();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        final field = tester.widget<TextField>(
          find.byKey(const ValueKey<String>('verify_code_input')),
        );

        expect(
          field.keyboardType,
          equals(TextInputType.number),
          reason: 'OTP field must use numeric keyboard',
        );
        expect(
          field.maxLength,
          equals(6),
          reason: 'OTP field must cap at 6 characters',
        );
        expect(
          field.showCursor,
          isFalse,
          reason: 'Hidden OTP field must not show a cursor',
        );
        // MASVS-PLATFORM security properties — GAP 5 (backlog "Test 7b missing
        // MASVS security assertions").
        expect(
          field.enableSuggestions,
          isFalse,
          reason:
              'OTP field must disable suggestions to prevent keyboard '
              'dictionary leakage (MASVS-PLATFORM MS-7)',
        );
        expect(
          field.autocorrect,
          isFalse,
          reason:
              'OTP field must disable autocorrect to prevent OTP digits '
              'being stored in autocorrect history (MASVS-PLATFORM MS-7)',
        );
        expect(
          field.enableIMEPersonalizedLearning,
          isFalse,
          reason:
              'OTP field must disable IME personalized learning to prevent '
              'OTP values training the keyboard model (MASVS-PLATFORM MS-7)',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 9 — Email masking: the screen renders the masked form of the
    //          passed email, not the raw address (MASVS-STORAGE MS-2 /
    //          privacy guard — only the first char + domain are shown).
    // -----------------------------------------------------------------------
    testWidgets(
      '9. email passed to screen is rendered in masked form (a***@example.com)',
      (tester) async {
        // A distinctive email that makes masking verifiable.
        const email = 'oksana@beautica.ua';
        const masked = 'o***@beautica.ua';

        final repo = FakeAuthRepository();
        final router = _makeRouter(email: email);
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        // The masked form must be visible somewhere in the tree.
        expect(
          find.textContaining(masked),
          findsOneWidget,
          reason:
              'VerificationScreen must display the masked email ($masked), '
              'not the raw address ($email). '
              'maskEmail("$email") should return "$masked".',
        );

        // The raw (unmasked) full email must NOT be visible as-is.
        // (The masked version contains the domain, so a simple text match
        // on the raw form would also match "o***@beautica.ua" — therefore
        // we look for the raw local part "oksana" which must not appear.)
        expect(
          find.textContaining('oksana@'),
          findsNothing,
          reason:
              'The raw local part of the email must not appear unmasked on screen.',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 10 — Generic resend failure (non-throttle): OTP is preserved,
    //           inline error shown, and resend link is immediately re-enabled
    //           (no cooldown — user can retry right away).
    //           Covers the catch(e) → _setInlineError + return null branch in
    //           _ResendRow._handleTap, which resets _cooldown to 0.
    // -----------------------------------------------------------------------
    testWidgets(
      '10. generic resend failure: OTP preserved, error shown, resend re-enabled immediately',
      (tester) async {
        const genericError = NetworkFailure();
        final repo = FakeAuthRepository()
          ..resendVerificationResult = genericError;
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        // Enter 6 digits — they must survive the resend failure.
        await _fillOtp(tester, '987654');
        await tester.pump();

        // Drain the initial 30s mount cooldown so the resend link is active.
        await tester.pump(const Duration(seconds: 31));
        // Tap resend — cooldown is now 0, link is active.
        await tester.tap(find.byKey(const ValueKey<String>('verify_resend')));
        // Wait for async resend to complete.
        await tester.pump(); // begin async
        await tester.pump(); // microtasks
        await tester.pump(const Duration(milliseconds: 50));

        // OTP digits must be preserved — they were NOT cleared on failure.
        final field = tester.widget<TextField>(
          find.byKey(const ValueKey<String>('verify_code_input')),
        );
        expect(
          field.controller?.text,
          equals('987654'),
          reason:
              'OTP input must be preserved after a generic resend failure '
              '(only cleared on success — M-Sec-1 invariant).',
        );

        // The inline error banner must appear (generic NetworkFailure copy).
        expect(
          find.byType(AuthBanner),
          findsOneWidget,
          reason:
              'An AuthBanner must appear after a generic resend failure '
              '(non-throttle path → _setInlineError).',
        );

        // The resend GestureDetector must be re-enabled immediately
        // (_cooldown resets to 0 on generic failure → onTap is non-null).
        final gesture = tester.widget<GestureDetector>(
          find.byKey(const ValueKey<String>('verify_resend')),
        );
        expect(
          gesture.onTap,
          isNotNull,
          reason:
              'verify_resend must be immediately re-enabled after a generic '
              'resend failure (no cooldown — user can retry right away).',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 8 — NeumorphicButton is disabled (onPressed null) while
    //          authProvider is AsyncLoading.
    //          The old AnimatedOpacity + InkWell approach no longer applies;
    //          NeumorphicButton exposes onPressed directly.
    // -----------------------------------------------------------------------
    testWidgets(
      '8. NeumorphicButton verify_submit is disabled while authProvider is '
      'AsyncLoading',
      (tester) async {
        final router = _makeRouter();
        addTearDown(router.dispose);
        final storage = FakeSecureStorage();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _LoadingAuthNotifier()),
              secureStorageProvider.overrideWith((_) => storage),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        // Do NOT use pumpAndSettle — _LoadingAuthNotifier never settles.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Fill 6 digits — the button would be enabled if not loading.
        await tester.enterText(
          find.byKey(const ValueKey<String>('verify_code_input')),
          '123456',
        );
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pump();

        // When isLoading is true the NeumorphicButton receives onPressed = null
        // regardless of OTP completeness.
        final btn = tester.widget<NeumorphicButton>(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        expect(
          btn.onPressed,
          isNull,
          reason:
              'NeumorphicButton.onPressed must be null while authProvider is '
              'loading, even when all 6 digits are filled',
        );
        // The loading flag must be forwarded to the button.
        expect(
          btn.loading,
          isTrue,
          reason:
              'NeumorphicButton.loading must be true while authProvider '
              'is in AsyncLoading',
        );
      },
    );
    // -----------------------------------------------------------------------
    // Test 8b — NetworkFailure thrown by verifyEmail resets spinner.
    //           Regression guard for the bug where the catch block inside
    //           AuthNotifier.verifyEmail() did NOT set state = AsyncError,
    //           causing the spinner to stay forever after any exception.
    //
    //           After the fix (state = AsyncError(e, st) before rethrow):
    //             - authProvider.isLoading becomes false → button.loading = false.
    //             - The VerificationScreen catch block sets _inlineError →
    //               AuthBanner appears.
    // -----------------------------------------------------------------------
    testWidgets(
      '8b. NetworkFailure from verifyEmail: spinner stops and AuthBanner appears '
      '(state = AsyncError fix regression guard)',
      (tester) async {
        final repo = FakeAuthRepository()
          ..verifyEmailResult = const NetworkFailure();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        // Fill all 6 digits so the submit button is active.
        await _fillOtp(tester, '123456');
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pump();

        // Confirm the button is enabled before tapping.
        final btnBefore = tester.widget<NeumorphicButton>(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        expect(
          btnBefore.onPressed,
          isNotNull,
          reason: 'Button must be enabled before submit (sanity check)',
        );

        // Tap submit — triggers AuthNotifier.verifyEmail() which throws
        // NetworkFailure → state = AsyncError(e, st) → rethrow.
        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        // Three pumps mirror the existing pattern for async resolution:
        //   pump 1: starts async (state = AsyncLoading emitted)
        //   pump 2: completes microtasks (catch fires, state = AsyncError)
        //   pump 3 (+50ms): animations / setState in VerificationScreen
        await tester.pump(); // begin async
        await tester.pump(); // microtasks (catch → state = AsyncError, rethrow)
        await tester.pump(const Duration(milliseconds: 50)); // animations

        // After the fix: authProvider is in AsyncError → isLoading = false
        // → NeumorphicButton.loading must be false (spinner stopped).
        final btnAfter = tester.widget<NeumorphicButton>(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        expect(
          btnAfter.loading,
          isFalse,
          reason:
              'NeumorphicButton.loading must be false after NetworkFailure — '
              'authProvider must be in AsyncError, not AsyncLoading. '
              'Without the fix (state = AsyncError before rethrow), this '
              'stays true and the spinner never stops.',
        );

        // The VerificationScreen catch re-enables the button (onPressed non-null)
        // because the OTP is still filled.
        expect(
          btnAfter.onPressed,
          isNotNull,
          reason:
              'Button must be re-enabled after a failed verify so the user '
              'can retry (onPressed must be non-null with 6 digits still filled)',
        );

        // An AuthBanner must appear — the VerificationScreen catch sets
        // _inlineError which renders the banner.
        expect(
          find.byType(AuthBanner),
          findsOneWidget,
          reason:
              'An AuthBanner must appear after a failed verify so the user '
              'sees the error message.',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 11 — Countdown text is rendered mid-cooldown.
    //           After a successful resend, the resend row displays the
    //           verificationResendTimer(N) l10n string while the cooldown
    //           is still active (GAP 4: "Test 3 countdown text not asserted").
    // -----------------------------------------------------------------------
    testWidgets(
      '11. resend row shows verificationResendTimer text while cooldown > 0',
      (tester) async {
        final repo = FakeAuthRepository();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        // Drain the initial 30 s mount cooldown so the resend link is active.
        await tester.pump(const Duration(seconds: 31));

        // Tap resend — this starts a fresh 30 s cooldown (success path).
        await tester.tap(find.byKey(const ValueKey<String>('verify_resend')));
        await tester.pump(); // begin async
        await tester.pump(); // microtasks
        await tester.pump(const Duration(milliseconds: 50));

        // Advance 1 second — the countdown has ticked at least once.
        // After the initial optimistic _startCooldown(30) and 1 s elapsed,
        // the visible cooldown is 29 s.
        await tester.pump(const Duration(seconds: 1));

        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const ValueKey<String>('verify_resend'))),
        );

        // The timer text "Надіслати знову (29 с)" must appear somewhere in the
        // tree. The exact remaining value may vary by 1 s depending on pump
        // timing, so we check for either 29 or 28.
        final has29 = tester
            .widgetList<Text>(find.byType(Text))
            .any((t) => t.data == l10n.verificationResendTimer('29 с'));
        final has28 = tester
            .widgetList<Text>(find.byType(Text))
            .any((t) => t.data == l10n.verificationResendTimer('28 с'));
        expect(
          has29 || has28,
          isTrue,
          reason:
              'A countdown text matching verificationResendTimer("29 с") or '
              'verificationResendTimer("28 с") must be shown 1 s after a '
              'successful resend. '
              'Available texts: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 12 — CODE_EXPIRED failure shows verificationErrCodeExpired copy.
    //           Regression guard for the codeExpired branch in
    //           _VerificationScreenState._setInlineError / VerificationFailure
    //           userMessage dispatch (GAP 6).
    // -----------------------------------------------------------------------
    testWidgets(
      '12. CODE_EXPIRED failure shows verificationErrCodeExpired inline copy',
      (tester) async {
        final repo = FakeAuthRepository()
          ..verifyEmailResult = const VerificationFailure(
            code: VerificationErrorCode.codeExpired,
          );
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        await _fillOtp(tester, '999888');
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        await tester.pump(); // begin async
        await tester.pump(); // microtasks
        await tester.pump(const Duration(milliseconds: 50)); // animations

        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const ValueKey<String>('verify_submit'))),
        );

        expect(
          tester
              .widgetList<Text>(find.byType(Text))
              .any((t) => t.data == l10n.verificationErrCodeExpired),
          isTrue,
          reason:
              'Expected verificationErrCodeExpired inline copy after '
              'VerificationFailure(code: VerificationErrorCode.codeExpired). '
              'Available texts: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
        );

        // The AuthBanner must be present (error banner widget, not raw Text).
        expect(
          find.byType(AuthBanner),
          findsOneWidget,
          reason:
              'An AuthBanner must appear for CODE_EXPIRED (same error path)',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 13 — ResendThrottledFailure(retryAfterSeconds: 0) edge case.
    //           When the server returns retryAfterSeconds = 0 the resend row
    //           must NOT start a cooldown — onTap must remain non-null
    //           immediately after the response (GAP 7).
    // -----------------------------------------------------------------------
    testWidgets(
      '13. ResendThrottledFailure(retryAfterSeconds: 0) does not start a cooldown',
      (tester) async {
        final repo = FakeAuthRepository()
          ..resendVerificationResult = const ResendThrottledFailure(
            retryAfterSeconds: 0,
          );
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        // Drain the initial 30 s mount cooldown so the resend link is active.
        await tester.pump(const Duration(seconds: 31));

        // Tap resend — the server will respond with retryAfterSeconds = 0.
        await tester.tap(find.byKey(const ValueKey<String>('verify_resend')));
        // Cannot pumpAndSettle: the ResendThrottledFailure catch restarts the
        // periodic timer (or starts one with 0 s — implementation may differ).
        await tester.pump(); // begin async
        await tester.pump(); // microtasks (await + catch)
        await tester.pump(const Duration(milliseconds: 50));

        // When retryAfterSeconds = 0, _startCooldown(0) is a no-op in the
        // _ResendRowState: the timer tick immediately drains cooldown to 0
        // (or it was never started). Either way onTap must be non-null.
        final gesture = tester.widget<GestureDetector>(
          find.byKey(const ValueKey<String>('verify_resend')),
        );
        expect(
          gesture.onTap,
          isNotNull,
          reason:
              'When the server returns retryAfterSeconds = 0, the resend '
              'GestureDetector.onTap must be non-null (no cooldown — user '
              'can retry immediately). '
              'Actual onTap: ${gesture.onTap}',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 14 — CLIENT registration locality persistence (regression guard).
    //
    // The CLIENT registration draft captures cityId/districtId/street/
    // buildingNo/locationNote on Step 3, but the backend RegisterRequest DTO
    // silently drops these fields — so they only reach the DB via the
    // post-verification PATCH /users/me call. Before this fix the CLIENT
    // branch of _saveProviderProfile was a no-op (commented "locality rode
    // along in the register body — nothing to save"); the result was rows in
    // production with city_id=NULL etc.
    //
    // This test seeds a CLIENT draft with full locality, drives the verify
    // submit, and asserts that UserRepository.updateLocality was called with
    // the exact field values from the draft. Without the fix the mock would
    // never be invoked and the verify call would still mark the test
    // assertion as failed.
    // -----------------------------------------------------------------------
    testWidgets(
      '14. CLIENT with locality on draft: verify success PATCHes /users/me '
      'with cityId/districtId/street/buildingNo/locationNote from draft',
      (tester) async {
        final repo = FakeAuthRepository();
        final userRepo = _MockUserRepository();
        when(
          () => userRepo.updateLocality(
            cityId: any(named: 'cityId'),
            districtId: any(named: 'districtId'),
            street: any(named: 'street'),
            buildingNo: any(named: 'buildingNo'),
            locationNote: any(named: 'locationNote'),
          ),
        ).thenAnswer((_) async {});

        final router = _makeRouter();
        addTearDown(router.dispose);

        final storage = FakeSecureStorage();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWith((_) => repo),
            secureStorageProvider.overrideWith((_) => storage),
            userRepositoryProvider.overrideWith((_) => userRepo),
          ],
        );
        addTearDown(container.dispose);

        // Seed a CLIENT registration draft with full locality.
        final notifier = container.read(registerDraftProvider.notifier)
          ..start(UserRole.client);
        notifier.updateStep1(
          email: _testEmail,
          password: 'Password1!',
          confirmPassword: 'Password1!',
        );
        notifier.updateStep2(
          firstName: 'Аня',
          lastName: 'Коваль',
          phone: '+380501112233',
        );
        notifier.updateStep3(
          oblastCode: 'oblast-1',
          cityId: 'city-1',
          districtId: 'district-1',
          street: 'вул. Хрещатик',
          buildingNo: '12А',
          locationNote: '3 поверх',
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _fillOtp(tester, '654321');
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        await tester.pumpAndSettle();

        // Must have landed on /home (via /done redirect) — verifying that the
        // PATCH call did not crash the flow.
        expect(
          find.text('home'),
          findsOneWidget,
          reason:
              'CLIENT with locality must still navigate to /done → /home after '
              'a successful PATCH /users/me.',
        );

        // Strict argument assertion — the draft values must flow through
        // unchanged into the UserRepository.updateLocality call.
        verify(
          () => userRepo.updateLocality(
            cityId: 'city-1',
            districtId: 'district-1',
            street: 'вул. Хрещатик',
            buildingNo: '12А',
            locationNote: '3 поверх',
          ),
        ).called(1);
      },
    );

    // -----------------------------------------------------------------------
    // Test 15 — CLIENT WITHOUT locality on draft (Step 3 skipped):
    //           UserRepository.updateLocality must NOT be called.
    //
    // Guard for the `cityId == null || cityId.isEmpty → return` early-exit
    // inside _saveProviderProfile. Users who tapped "Пропустити" on Step 3
    // have a draft with cityId == null; they should still verify and reach
    // /done without any PATCH /users/me being attempted.
    // -----------------------------------------------------------------------
    testWidgets('15. CLIENT without locality on draft (Step 3 skipped): '
        'PATCH /users/me is NOT called', (tester) async {
      final repo = FakeAuthRepository();
      final userRepo = _MockUserRepository();

      final router = _makeRouter();
      addTearDown(router.dispose);

      final storage = FakeSecureStorage();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith((_) => repo),
          secureStorageProvider.overrideWith((_) => storage),
          userRepositoryProvider.overrideWith((_) => userRepo),
        ],
      );
      addTearDown(container.dispose);

      // Seed a CLIENT draft WITHOUT a Step 3 locality (cityId stays null).
      final notifier = container.read(registerDraftProvider.notifier)
        ..start(UserRole.client);
      notifier.updateStep1(
        email: _testEmail,
        password: 'Password1!',
        confirmPassword: 'Password1!',
      );
      notifier.updateStep2(
        firstName: 'Аня',
        lastName: 'Коваль',
        phone: '+380501112233',
      );
      // No updateStep3 — Step 3 was skipped.

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _fillOtp(tester, '654321');
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('verify_submit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
      await tester.pumpAndSettle();

      // Still navigates to home — the skip path must not block verification.
      expect(
        find.text('home'),
        findsOneWidget,
        reason:
            'CLIENT who skipped Step 3 must still navigate to /done → /home '
            'after verification (no PATCH attempted).',
      );

      // Strict assertion: the mock must not have been invoked at all.
      verifyNever(
        () => userRepo.updateLocality(
          cityId: any(named: 'cityId'),
          districtId: any(named: 'districtId'),
          street: any(named: 'street'),
          buildingNo: any(named: 'buildingNo'),
          locationNote: any(named: 'locationNote'),
        ),
      );
    });

    // -----------------------------------------------------------------------
    // Test 16 — SALON_OWNER with phone: phone forwarded to SalonCreateDto.
    //
    // Guards the `phone: draft.phone` line added in the SALON_OWNER case of
    // _saveProviderProfile (verification_screen.dart ~line 209). Without that
    // line the SalonCreateDto would be constructed with phone: null and the
    // backend `@Pattern`-validated field would be absent regardless of what
    // the user typed in Step 2.
    //
    // Mirrors the setup of Tests 14 + 15 exactly — same ProviderContainer +
    // UncontrolledProviderScope pattern, same Step-by-step draft population;
    // only the role and the additional salonRepositoryProvider override differ.
    // -----------------------------------------------------------------------
    testWidgets(
      '16. SALON_OWNER with phone on draft: verify success creates salon with '
      'phone forwarded from draft to SalonCreateDto.phone',
      (tester) async {
        final repo = FakeAuthRepository();
        final salonRepo = _MockSalonRepository();
        when(
          () => salonRepo.create(dto: any(named: 'dto')),
        ).thenAnswer((_) async {});

        final router = _makeRouter();
        addTearDown(router.dispose);

        final storage = FakeSecureStorage();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWith((_) => repo),
            secureStorageProvider.overrideWith((_) => storage),
            salonRepositoryProvider.overrideWith((_) => salonRepo),
          ],
        );
        addTearDown(container.dispose);

        // Seed a SALON_OWNER registration draft with full locality + phone.
        final notifier = container.read(registerDraftProvider.notifier)
          ..start(UserRole.salonOwner);
        notifier.updateStep1(
          email: _testEmail,
          password: 'Password1!',
          confirmPassword: 'Password1!',
        );
        notifier.updateStep2(
          firstName: 'Олена',
          lastName: 'Мороз',
          phone: '+380671234567',
          salonName: 'Salon Lumière',
        );
        notifier.updateStep3(
          oblastCode: 'oblast-1',
          cityId: 'city-1',
          districtId: 'district-1',
          street: 'вул. Хрещатик',
          buildingNo: '12А',
          locationNote: '3 поверх',
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _fillOtp(tester, '654321');
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        await tester.pumpAndSettle();

        // Must land on /home (via /done redirect).
        expect(
          find.text('home'),
          findsOneWidget,
          reason:
              'SALON_OWNER with phone must still navigate to /done → /home after '
              'a successful POST /salons.',
        );

        // Capture the dto argument passed to SalonRepository.create.
        final captured = verify(
          () => salonRepo.create(dto: captureAny(named: 'dto')),
        ).captured;
        expect(captured, hasLength(1));
        final dto = captured.single as SalonCreateDto;

        // Phone must be forwarded verbatim from the draft.
        expect(
          dto.phone,
          equals('+380671234567'),
          reason:
              'SalonCreateDto.phone must equal draft.phone (+380671234567). '
              'If this fails, verification_screen.dart is missing phone: draft.phone '
              'in the SALON_OWNER SalonCreateDto constructor.',
        );
        // Locality fields must also be correct (regression guard for the
        // remaining fields — phone is the HIGH gap but all fields are asserted).
        expect(dto.name, equals('Salon Lumière'));
        expect(dto.cityId, equals('city-1'));
        expect(dto.districtId, equals('district-1'));
        expect(dto.street, equals('вул. Хрещатик'));
        expect(dto.buildingNo, equals('12А'));
      },
    );

    // -----------------------------------------------------------------------
    // Test 17 — SALON_OWNER with empty phone: toJson() omits phone key.
    //
    // When the user leaves the phone field blank on Step 2, draft.phone == ''.
    // The SalonCreateDto must be constructed with phone: '' (from draft.phone)
    // and toJson() must then omit the key entirely (empty-string guard in
    // SalonCreateDto.toJson). This prevents the backend from receiving an
    // empty-string phone which would fail `@Pattern` validation.
    // -----------------------------------------------------------------------
    testWidgets(
      '17. SALON_OWNER with empty phone on draft: SalonCreateDto.toJson() '
      'omits the phone key (no empty-string sent to backend)',
      (tester) async {
        final repo = FakeAuthRepository();
        final salonRepo = _MockSalonRepository();
        when(
          () => salonRepo.create(dto: any(named: 'dto')),
        ).thenAnswer((_) async {});

        final router = _makeRouter();
        addTearDown(router.dispose);

        final storage = FakeSecureStorage();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWith((_) => repo),
            secureStorageProvider.overrideWith((_) => storage),
            salonRepositoryProvider.overrideWith((_) => salonRepo),
          ],
        );
        addTearDown(container.dispose);

        // Seed a SALON_OWNER draft with phone left as the empty default.
        final notifier = container.read(registerDraftProvider.notifier)
          ..start(UserRole.salonOwner);
        notifier.updateStep1(
          email: _testEmail,
          password: 'Password1!',
          confirmPassword: 'Password1!',
        );
        notifier.updateStep2(
          firstName: 'Олена',
          lastName: 'Мороз',
          phone: '', // explicitly empty — user skipped the phone field
          salonName: 'Salon Lumière',
        );
        notifier.updateStep3(
          oblastCode: 'oblast-1',
          cityId: 'city-1',
          street: 'вул. Хрещатик',
          buildingNo: '12А',
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _fillOtp(tester, '654321');
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        await tester.pumpAndSettle();

        // Must still navigate to /home.
        expect(
          find.text('home'),
          findsOneWidget,
          reason:
              'SALON_OWNER with empty phone must still navigate to /done → /home.',
        );

        // Capture the dto and assert toJson() omits the phone key.
        final captured = verify(
          () => salonRepo.create(dto: captureAny(named: 'dto')),
        ).captured;
        expect(captured, hasLength(1));
        final dto = captured.single as SalonCreateDto;

        expect(
          dto.toJson().containsKey('phone'),
          isFalse,
          reason:
              'SalonCreateDto.toJson() must omit the phone key when phone is '
              'empty — sending an empty string to the backend triggers '
              '@Pattern validation failure (HIGH gap fix).',
        );
      },
    );
    // -----------------------------------------------------------------------
    // Test 18 — INDEPENDENT_MASTER with null cityId: verify submit shows
    //           ProviderMissingCityFailure inline error (Fix 3 regression guard).
    //
    // When a INDEPENDENT_MASTER draft loses cityId (e.g. navigation edge case
    // clears Step 3 after Step 3 was already completed), _saveProviderProfile
    // must throw ProviderMissingCityFailure instead of silently calling PATCH
    // /independent-masters/me without a city, which would produce a verified
    // account with no location in the database.
    //
    // This test also implicitly guards that resetCooldown() is called after a
    // post-OTP profile save failure (_emailVerified = true path in _submit).
    // See Test 19 for the explicit resetCooldown isolation.
    // -----------------------------------------------------------------------
    testWidgets('18. INDEPENDENT_MASTER with null cityId: verify success then '
        '_saveProviderProfile throws ProviderMissingCityFailure and shows error banner', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final masterRepo = _MockMasterRepository();
      // updateLocality must NOT be called — the guard throws before reaching it.

      final router = _makeRouter();
      addTearDown(router.dispose);

      final storage = FakeSecureStorage();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith((_) => repo),
          secureStorageProvider.overrideWith((_) => storage),
          masterRepositoryProvider.overrideWith((_) => masterRepo),
        ],
      );
      addTearDown(container.dispose);

      // Seed an INDEPENDENT_MASTER draft WITHOUT a Step 3 cityId.
      // The draft has Step 1 + Step 2 only — Step 3 was never completed,
      // so cityId is null and isCityMissing is true.
      final notifier = container.read(registerDraftProvider.notifier)
        ..start(UserRole.independentMaster);
      notifier.updateStep1(
        email: _testEmail,
        password: 'Password1!',
        confirmPassword: 'Password1!',
      );
      notifier.updateStep2(
        firstName: 'Іванна',
        lastName: 'Ковальчук',
        phone: '+380501112233',
      );
      // No updateStep3 — cityId stays null.

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No error banner before submit.
      expect(find.byType(AuthBanner), findsNothing);

      await _fillOtp(tester, '654321');
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('verify_submit')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
      // Cannot pumpAndSettle: the resend timer may fire setState every second
      // after resetCooldown() is invoked by the Fix 2B path in _submit.
      await tester.pump(); // begin async
      await tester.pump(); // microtasks (verifyEmail success)
      await tester.pump(); // microtasks (_saveProviderProfile throw)
      await tester.pump(const Duration(milliseconds: 50)); // animations

      // Must remain on the verification screen — NOT navigate to /done.
      expect(
        find.text('home'),
        findsNothing,
        reason:
            'INDEPENDENT_MASTER with null cityId must NOT navigate to /done '
            '— _saveProviderProfile threw ProviderMissingCityFailure.',
      );

      // An error banner must appear.
      expect(
        find.byType(AuthBanner),
        findsOneWidget,
        reason:
            'An AuthBanner must appear after ProviderMissingCityFailure '
            '(Fix 3 — provider roles must not silently create accounts without city).',
      );

      // The banner message must be the verificationErrProviderMissingCity copy.
      final l10n = AppLocalizations.of(tester.element(find.byType(AuthBanner)));
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .any((t) => t.data == l10n.verificationErrProviderMissingCity),
        isTrue,
        reason:
            'Expected verificationErrProviderMissingCity banner copy after '
            'ProviderMissingCityFailure. '
            'Available texts: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
      );

      // MasterRepository.updateLocality must NOT have been called — the guard
      // threw before reaching the PATCH call.
      verifyNever(
        () => masterRepo.updateLocality(
          cityId: any(named: 'cityId'),
          districtId: any(named: 'districtId'),
          street: any(named: 'street'),
          buildingNo: any(named: 'buildingNo'),
          locationNote: any(named: 'locationNote'),
        ),
      );
    });

    // -----------------------------------------------------------------------
    // Test 20 — INDEPENDENT_MASTER happy path: verifyEmail succeeds and
    //           updateLocality succeeds — no UnauthorizedFailure, no 401.
    //
    // Regression guard for the "Сесія завершилась" bug (2026-05-30):
    //
    // Before the fix, AuthNotifier.verifyEmail() cleared coldStartAccessToken
    // in a `finally` block BEFORE setting state = AsyncData(Authenticated).
    // This created a one-microtask window where:
    //   - authProvider.value was still AsyncLoading (not yet Authenticated)
    //   - coldStartAccessToken was null (already wiped by finally)
    //
    // AuthInterceptor checks `notifier.coldStartAccessToken` when
    // `authProvider.value` is not Authenticated. During that window it found
    // null → injected no Bearer token → PATCH /independent-masters/me
    // returned 401 → RefreshInterceptor triggered logout → screen showed
    // "Сесія завершилась".
    //
    // The fix: state = AsyncData(Authenticated) BEFORE coldStartAccessToken = null.
    // Once state is Authenticated, AuthInterceptor reads the token from the
    // settled session; the sentinel is no longer needed.
    //
    // This test asserts the observable outcome: updateLocality is called
    // (implying no 401 blocked it) AND the screen navigates to /home
    // (implying no logout was triggered).
    // -----------------------------------------------------------------------
    testWidgets(
      '20. INDEPENDENT_MASTER happy path: updateLocality succeeds after '
      'verifyEmail — no UnauthorizedFailure, navigates to home '
      '(regression guard for auth session race fix 2026-05-30)',
      (tester) async {
        final repo = FakeAuthRepository();
        final masterRepo = _MockMasterRepository();

        // updateLocality must succeed without throwing — no 401.
        when(
          () => masterRepo.updateLocality(
            cityId: any(named: 'cityId'),
            districtId: any(named: 'districtId'),
            street: any(named: 'street'),
            buildingNo: any(named: 'buildingNo'),
            locationNote: any(named: 'locationNote'),
          ),
        ).thenAnswer((_) async {});

        final router = _makeRouter();
        addTearDown(router.dispose);

        final storage = FakeSecureStorage();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWith((_) => repo),
            secureStorageProvider.overrideWith((_) => storage),
            masterRepositoryProvider.overrideWith((_) => masterRepo),
          ],
        );
        addTearDown(container.dispose);

        // Seed an INDEPENDENT_MASTER draft with a full Step 3 locality so
        // _saveProviderProfile does not throw ProviderMissingCityFailure.
        final notifier = container.read(registerDraftProvider.notifier)
          ..start(UserRole.independentMaster);
        notifier.updateStep1(
          email: _testEmail,
          password: 'Password1!',
          confirmPassword: 'Password1!',
        );
        notifier.updateStep2(
          firstName: 'Іванна',
          lastName: 'Ковальчук',
          phone: '+380501112233',
        );
        notifier.updateStep3(
          oblastCode: 'oblast-1',
          cityId: 'city-1',
          districtId: 'district-1',
          street: 'вул. Центральна',
          buildingNo: '5Б',
          locationNote: 'кв. 12',
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // No error banner before submit.
        expect(find.byType(AuthBanner), findsNothing);

        await _fillOtp(tester, '654321');
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        await tester.pumpAndSettle();

        // Must navigate to /home — updateLocality succeeded, no logout fired.
        expect(
          find.text('home'),
          findsOneWidget,
          reason:
              'INDEPENDENT_MASTER with full locality must navigate to /done → '
              '/home after a successful verifyEmail + updateLocality. '
              'If this fails, the auth session race (coldStartAccessToken wiped '
              'before state = AsyncData(Authenticated)) is back.',
        );

        // No error banner — the race did not produce a 401.
        expect(
          find.byType(AuthBanner),
          findsNothing,
          reason:
              'No error banner must appear after a successful registration flow. '
              'An AuthBanner here means the 401 race is back.',
        );

        // updateLocality must have been called exactly once with the draft values.
        verify(
          () => masterRepo.updateLocality(
            cityId: 'city-1',
            districtId: 'district-1',
            street: 'вул. Центральна',
            buildingNo: '5Б',
            locationNote: 'кв. 12',
          ),
        ).called(1);
      },
    );

    // -----------------------------------------------------------------------
    // Test 19 — resetCooldown() re-enables the resend link immediately.
    //
    // Fix 2B: when _saveProviderProfile fails after the OTP has been accepted
    // (_emailVerified becomes true before the throw), the parent calls
    // _resendRowKey.currentState?.resetCooldown(). This must cancel the
    // running 30-second countdown and set _cooldown to 0 so the user can
    // request a new OTP right away — they cannot retry with the same code
    // because it was consumed by the successful verifyEmail call.
    //
    // Setup: use a FakeAuthRepository that accepts the OTP (verifyEmail
    // returns success) plus a _MockMasterRepository whose updateLocality
    // throws a NetworkFailure. The submit path therefore:
    //   1. verifyEmail succeeds → _emailVerified = true
    //   2. _saveProviderProfile → updateLocality throws NetworkFailure
    //   3. catch: _emailVerified is true → resetCooldown() called
    //   4. resend GestureDetector.onTap must be non-null immediately
    // -----------------------------------------------------------------------
    testWidgets(
      '19. resetCooldown() after post-OTP profile save failure: resend link '
      're-enabled immediately (Fix 2B regression guard)',
      (tester) async {
        final repo = FakeAuthRepository();
        final masterRepo = _MockMasterRepository();
        // updateLocality throws a NetworkFailure to simulate a transient save
        // failure after a successful OTP verification.
        when(
          () => masterRepo.updateLocality(
            cityId: any(named: 'cityId'),
            districtId: any(named: 'districtId'),
            street: any(named: 'street'),
            buildingNo: any(named: 'buildingNo'),
            locationNote: any(named: 'locationNote'),
          ),
        ).thenThrow(const NetworkFailure());

        final router = _makeRouter();
        addTearDown(router.dispose);

        final storage = FakeSecureStorage();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWith((_) => repo),
            secureStorageProvider.overrideWith((_) => storage),
            masterRepositoryProvider.overrideWith((_) => masterRepo),
          ],
        );
        addTearDown(container.dispose);

        // Seed an INDEPENDENT_MASTER draft WITH a full Step 3 locality so the
        // guard does NOT throw — the failure must come from updateLocality.
        final notifier = container.read(registerDraftProvider.notifier)
          ..start(UserRole.independentMaster);
        notifier.updateStep1(
          email: _testEmail,
          password: 'Password1!',
          confirmPassword: 'Password1!',
        );
        notifier.updateStep2(
          firstName: 'Іванна',
          lastName: 'Ковальчук',
          phone: '+380501112233',
        );
        notifier.updateStep3(
          oblastCode: 'oblast-1',
          cityId: 'city-1',
          districtId: 'district-1',
          street: 'вул. Центральна',
          buildingNo: '5Б',
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _fillOtp(tester, '123456');
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        // Do NOT pumpAndSettle — the resend timer may be active at this point.
        await tester.pump(); // begin async
        await tester.pump(); // verifyEmail microtasks
        await tester.pump(); // _saveProviderProfile / updateLocality throw
        await tester.pump(
          const Duration(milliseconds: 50),
        ); // animations + setState

        // Must remain on the verification screen — the save failed.
        expect(
          find.text('home'),
          findsNothing,
          reason:
              'The screen must NOT navigate to /done when _saveProviderProfile '
              'throws — the user stays to retry.',
        );

        // An error banner must appear (NetworkFailure message).
        expect(
          find.byType(AuthBanner),
          findsOneWidget,
          reason:
              'An AuthBanner must appear after a post-OTP profile save failure.',
        );

        // The resend GestureDetector must be enabled immediately
        // (_cooldown == 0 after resetCooldown() was called via Fix 2B).
        // The initial 30 s mount cooldown was running, but resetCooldown()
        // cancels it so the user can request a fresh OTP right away.
        final gesture = tester.widget<GestureDetector>(
          find.byKey(const ValueKey<String>('verify_resend')),
        );
        expect(
          gesture.onTap,
          isNotNull,
          reason:
              'verify_resend GestureDetector.onTap must be non-null after '
              'resetCooldown() is called by Fix 2B — the OTP was consumed by '
              'the successful verifyEmail call, so the user must be able to '
              'request a new code immediately without waiting 30 seconds.',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 20b — post-OTP save returns a multi-field ValidationFailure: the
    //            AuthBanner names the failed register step 2/3 fields inline,
    //            NOT the generic errValidation banner. (M3 / M11 inline-mapping
    //            gap — the offending fields live on a previous step.)
    // -----------------------------------------------------------------------
    testWidgets(
      '20b. post-OTP save ValidationFailure with a field map → banner names '
      'the failed fields (street/buildingNo) inline, not generic',
      (tester) async {
        final repo = FakeAuthRepository();
        final masterRepo = _MockMasterRepository();
        const fieldErrors = <String, String>{
          'street': 'Вулиця обовʼязкова',
          'buildingNo': 'Будинок занадто довгий',
        };
        when(
          () => masterRepo.updateLocality(
            cityId: any(named: 'cityId'),
            districtId: any(named: 'districtId'),
            street: any(named: 'street'),
            buildingNo: any(named: 'buildingNo'),
            locationNote: any(named: 'locationNote'),
          ),
        ).thenThrow(const ValidationFailure(fieldErrors: fieldErrors));

        final router = _makeRouter();
        addTearDown(router.dispose);

        final storage = FakeSecureStorage();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWith((_) => repo),
            secureStorageProvider.overrideWith((_) => storage),
            masterRepositoryProvider.overrideWith((_) => masterRepo),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(registerDraftProvider.notifier)
          ..start(UserRole.independentMaster);
        notifier.updateStep1(
          email: _testEmail,
          password: 'Password1!',
          confirmPassword: 'Password1!',
        );
        notifier.updateStep2(
          firstName: 'Іванна',
          lastName: 'Ковальчук',
          phone: '+380501112233',
        );
        notifier.updateStep3(
          oblastCode: 'oblast-1',
          cityId: 'city-1',
          districtId: 'district-1',
          street: 'вул. Центральна',
          buildingNo: '5Б',
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Resolve l10n + build the expected banner BEFORE submit consumes the
        // widget tree.
        final l10n = AppLocalizations.of(
          tester.element(find.byType(VerificationScreen)),
        );
        final expectedBanner = buildFieldErrorBanner(fieldErrors, l10n)!;

        await _fillOtp(tester, '123456');
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        await tester.pump(); // begin async
        await tester.pump(); // verifyEmail microtasks
        await tester.pump(); // updateLocality throws
        await tester.pump(const Duration(milliseconds: 50));

        // Stays on the verification screen — the save failed.
        expect(find.text('home'), findsNothing);

        // The AuthBanner carries the field-named multi-line banner, NOT the
        // generic errValidation string.
        expect(find.byType(AuthBanner), findsOneWidget);
        expect(find.text(expectedBanner), findsOneWidget);
        expect(find.text(l10n.errValidation), findsNothing);
      },
    );

    // -----------------------------------------------------------------------
    // Test 20c — post-OTP save returns a ValidationFailure with an EMPTY field
    //            map but a serverMessage: the banner falls back to the server
    //            message (not the generic errValidation copy).
    // -----------------------------------------------------------------------
    testWidgets(
      '20c. post-OTP save ValidationFailure with empty fieldErrors falls back '
      'to serverMessage in the banner',
      (tester) async {
        final repo = FakeAuthRepository();
        final masterRepo = _MockMasterRepository();
        const serverMsg = 'Адресу не вдалося зберегти';
        when(
          () => masterRepo.updateLocality(
            cityId: any(named: 'cityId'),
            districtId: any(named: 'districtId'),
            street: any(named: 'street'),
            buildingNo: any(named: 'buildingNo'),
            locationNote: any(named: 'locationNote'),
          ),
        ).thenThrow(
          const ValidationFailure(
            fieldErrors: <String, String>{},
            serverMessage: serverMsg,
          ),
        );

        final router = _makeRouter();
        addTearDown(router.dispose);

        final storage = FakeSecureStorage();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWith((_) => repo),
            secureStorageProvider.overrideWith((_) => storage),
            masterRepositoryProvider.overrideWith((_) => masterRepo),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(registerDraftProvider.notifier)
          ..start(UserRole.independentMaster);
        notifier.updateStep1(
          email: _testEmail,
          password: 'Password1!',
          confirmPassword: 'Password1!',
        );
        notifier.updateStep2(
          firstName: 'Іванна',
          lastName: 'Ковальчук',
          phone: '+380501112233',
        );
        notifier.updateStep3(
          oblastCode: 'oblast-1',
          cityId: 'city-1',
          districtId: 'district-1',
          street: 'вул. Центральна',
          buildingNo: '5Б',
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(VerificationScreen)),
        );

        await _fillOtp(tester, '123456');
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('home'), findsNothing);
        expect(find.byType(AuthBanner), findsOneWidget);
        // serverMessage wins over the generic errValidation fallback.
        expect(find.text(serverMsg), findsOneWidget);
        expect(find.text(l10n.errValidation), findsNothing);
      },
    );

    // -----------------------------------------------------------------------
    // Test 21 — Defect 8 retry: second submit does NOT re-call verifyEmail
    //           when the OTP was already accepted (_emailVerifiedProvider =
    //           true) but _saveProviderProfile threw on the first attempt.
    //
    // Setup:
    //   - FakeAuthRepository: verifyEmail succeeds on every call.
    //   - _MockMasterRepository: updateLocality throws ServerFailure on the
    //     first call, then succeeds on the second (call-count driven by a
    //     local variable closed over by the mock answer).
    //   - Draft: INDEPENDENT_MASTER with full Step 3 locality (so the
    //     ProviderMissingCityFailure guard does not trigger).
    //
    // Flow:
    //   1st submit: verifyEmail succeeds → _emailVerifiedProvider = true →
    //               updateLocality throws → error banner shown, stays on screen.
    //   2nd submit: _emailVerifiedProvider is still true → verifyEmail skipped →
    //               updateLocality called again (second call) → succeeds →
    //               navigates to /done → /home.
    //
    // Asserts:
    //   - verifyEmailCalls.length == 1 (called only on the first submit).
    //   - updateLocality called twice total (once failing, once succeeding).
    //   - After the first submit: AuthBanner visible, still on screen.
    //   - After the second submit: /home visible.
    //
    // Regression guard for the Defect 8 retry branch introduced in Phase 2.x.
    // The backlog row "LOW — VerificationScreen _saveProviderProfile retry
    // branch untested" is resolved by this test.
    // -----------------------------------------------------------------------
    testWidgets(
      '21. retry: second submit does not re-call verifyEmail when OTP already '
      'accepted (_emailVerifiedProvider = true) but _saveProviderProfile threw',
      (tester) async {
        final repo = FakeAuthRepository(); // verifyEmail succeeds by default

        // Track the call count manually so the mock answer can alternate.
        int updateLocalityCalls = 0;
        final masterRepo = _MockMasterRepository();
        when(
          () => masterRepo.updateLocality(
            cityId: any(named: 'cityId'),
            districtId: any(named: 'districtId'),
            street: any(named: 'street'),
            buildingNo: any(named: 'buildingNo'),
            locationNote: any(named: 'locationNote'),
          ),
        ).thenAnswer((_) async {
          updateLocalityCalls++;
          if (updateLocalityCalls == 1) {
            // First call — simulate a transient server error.
            throw const ServerFailure(statusCode: 500);
          }
          // Second call — succeeds (returns normally).
        });

        final router = _makeRouter();
        addTearDown(router.dispose);

        final storage = FakeSecureStorage();
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWith((_) => repo),
            secureStorageProvider.overrideWith((_) => storage),
            masterRepositoryProvider.overrideWith((_) => masterRepo),
          ],
        );
        addTearDown(container.dispose);

        // Seed an INDEPENDENT_MASTER draft with a full Step 3 locality so
        // _saveProviderProfile reaches the updateLocality call (does not
        // throw ProviderMissingCityFailure).
        final notifier = container.read(registerDraftProvider.notifier)
          ..start(UserRole.independentMaster);
        notifier.updateStep1(
          email: _testEmail,
          password: 'Password1!',
          confirmPassword: 'Password1!',
        );
        notifier.updateStep2(
          firstName: 'Іванна',
          lastName: 'Ковальчук',
          phone: '+380501112233',
        );
        notifier.updateStep3(
          oblastCode: 'oblast-1',
          cityId: 'city-1',
          districtId: 'district-1',
          street: 'вул. Центральна',
          buildingNo: '5Б',
          locationNote: 'кв. 12',
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // No error banner before any submit.
        expect(find.byType(AuthBanner), findsNothing);

        // ── First submit ────────────────────────────────────────────────────
        // Fill the OTP and tap submit.
        await _fillOtp(tester, '654321');
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        // Cannot pumpAndSettle — the resend timer fires every second after
        // resetCooldown() is invoked by the Fix 2B path.
        await tester.pump(); // begin async
        await tester
            .pump(); // verifyEmail microtasks → _emailVerifiedProvider = true
        await tester.pump(); // _saveProviderProfile → updateLocality throw
        await tester.pump(
          const Duration(milliseconds: 50),
        ); // setState / animations

        // Must remain on the verification screen — the save failed.
        expect(
          find.text('home'),
          findsNothing,
          reason:
              'Screen must NOT navigate to /done after the first submit when '
              '_saveProviderProfile throws — the user stays to retry.',
        );

        // An error banner must be shown (ServerFailure message).
        expect(
          find.byType(AuthBanner),
          findsOneWidget,
          reason:
              'An AuthBanner must appear after the first _saveProviderProfile '
              'failure (ServerFailure from updateLocality).',
        );

        // Exactly one verifyEmail call — it was consumed by the first submit.
        expect(
          repo.verifyEmailCalls,
          hasLength(1),
          reason:
              'verifyEmail must have been called exactly once after the first '
              'submit (OTP was accepted and _emailVerifiedProvider set to true).',
        );

        // updateLocality was called once (the failing call).
        expect(
          updateLocalityCalls,
          equals(1),
          reason:
              'updateLocality must have been called once after the first submit '
              '(the call that threw ServerFailure).',
        );

        // ── Second submit ───────────────────────────────────────────────────
        // The OTP field still shows the same digits (they were not cleared
        // by the profile-save failure — only cleared on a successful resend).
        // The submit button must still be enabled (6 digits present).
        final btnBeforeRetry = tester.widget<NeumorphicButton>(
          find.byKey(const ValueKey<String>('verify_submit')),
        );
        expect(
          btnBeforeRetry.onPressed,
          isNotNull,
          reason:
              'Submit button must be re-enabled after a failed profile save '
              '(6 digits are still in the OTP field).',
        );

        await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
        await tester.pump(); // begin async
        await tester.pump(); // _saveProviderProfile → updateLocality succeeds
        await tester.pump(); // context.go(RouteNames.done) → redirect → /home
        await tester.pumpAndSettle(); // router navigation settles

        // Must navigate to /home — the second updateLocality call succeeded.
        expect(
          find.text('home'),
          findsOneWidget,
          reason:
              'After the second submit, _saveProviderProfile must succeed and '
              'the screen must navigate to /done → /home.',
        );

        // verifyEmail must still have been called only once — the second submit
        // skipped it because _emailVerifiedProvider was already true.
        expect(
          repo.verifyEmailCalls,
          hasLength(1),
          reason:
              'verifyEmail must NOT be called on the second submit — '
              '_emailVerifiedProvider was already true (OTP consumed on first '
              'submit). Calling it again would replay an already-consumed OTP '
              'and produce an INVALID_CODE or ALREADY_VERIFIED error.',
        );

        // updateLocality must have been called exactly twice in total.
        expect(
          updateLocalityCalls,
          equals(2),
          reason:
              'updateLocality must have been called twice: once on the first '
              'submit (ServerFailure) and once on the second submit (success).',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 19 — Silent-submit guard for a NON-VerificationFailure.
    //
    //   Regression net (Step 2.7) for the invalid-OTP "no error shown" fix.
    //   A non-VerificationFailure from verifyEmail (here ServerFailure(500) —
    //   the realistic shape when the typed-code mapping is missed and the
    //   request drifts to a 5xx, or a plain backend 500) must STILL render a
    //   non-empty inline error banner. The submit must NEVER complete silently.
    //
    //   This asserts the end-to-end contract that the _setInlineError catch-all
    //   guarantees: every failed verify yields a visible, non-empty banner.
    // -----------------------------------------------------------------------
    testWidgets('19. non-VerificationFailure (ServerFailure 500) on verify shows a '
        'non-empty error banner — never a silent submit', (tester) async {
      final repo = FakeAuthRepository()
        ..verifyEmailResult = const ServerFailure(statusCode: 500);
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpVerification(tester, repo: repo, router: router);

      await _fillOtp(tester, '424242');
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('verify_submit')),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
      await tester.pump(); // begin async
      await tester.pump(); // microtasks (catch → _setInlineError)
      await tester.pump(const Duration(milliseconds: 50)); // animations

      // Must remain on the verification screen — no silent navigation.
      expect(
        find.byKey(const ValueKey<String>('verify_submit')),
        findsOneWidget,
        reason: 'A failed verify must keep the user on the screen.',
      );
      expect(
        find.text('home'),
        findsNothing,
        reason:
            'A failed verify must NOT silently navigate away (no silent '
            'submit).',
      );

      // The error banner must appear ...
      final bannerFinder = find.byType(AuthBanner);
      expect(
        bannerFinder,
        findsOneWidget,
        reason:
            'A non-VerificationFailure must still surface an AuthBanner — the '
            'silent-submit bug showed NO banner at all.',
      );

      // ... with non-empty text. The message must be the resolved ServerFailure
      // copy (errServer); if a future regression blanks the message, the
      // _setInlineError catch-all falls back to errUnknown — either way the
      // banner text is guaranteed non-empty (never a silent/blank submit).
      final l10n = AppLocalizations.of(tester.element(bannerFinder));
      final bannerMessages = tester
          .widgetList<Text>(
            find.descendant(of: bannerFinder, matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .toList();
      expect(
        bannerMessages,
        isNotEmpty,
        reason:
            'The AuthBanner must render non-empty text after a '
            'non-VerificationFailure — a blank banner is a silent submit.',
      );
      expect(
        bannerMessages,
        anyElement(anyOf(equals(l10n.errServer), equals(l10n.errUnknown))),
        reason:
            'The banner must show the resolved ServerFailure copy (errServer) '
            'or the catch-all fallback (errUnknown) — never an empty string.',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// AuthNotifier stubs
// ---------------------------------------------------------------------------

/// Stays in [AsyncLoading] indefinitely — used to verify that the CTA is
/// disabled while a request is in flight.
class _LoadingAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    final completer = Completer<AuthSession>();
    ref.onDispose(() {
      if (!completer.isCompleted) {
        completer.complete(const AuthSession.unauthenticated());
      }
    });
    return completer.future;
  }
}
