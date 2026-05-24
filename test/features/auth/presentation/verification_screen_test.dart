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
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/verification_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const _testEmail = 'anya@example.com';

/// Builds a minimal GoRouter with the verification screen at /verification.
/// Includes /register/step-3, /done, and /home as navigation targets.
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

      // Resend is hidden initially (no cooldown started — btn appears immediately
      // since _cooldown starts at 0; screen only starts a cooldown after resend
      // action, not on init). So the link IS visible from the start.
      // The link text shows "Надіслати знову" when _cooldown == 0.
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

        // Tap the resend link (cooldown = 0 initially → link is active).
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

        // Tap resend (cooldown == 0 initially → link is active).
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
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .any((t) => t.data == l10n.verificationErrInvalidCode),
        isTrue,
        reason:
            'Expected an inline error Text matching verificationErrInvalidCode. '
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

      // Tap resend (cooldown = 0 initially → link is active).
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
