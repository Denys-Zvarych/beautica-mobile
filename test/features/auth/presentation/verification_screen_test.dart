// Phase 2.11 — Widget tests for VerificationScreen.
//
// Tests use a minimal GoRouter (initial route = /verification → VerificationScreen)
// so that context.go works inside the widget under test. Auth state is
// controlled via ProviderScope overrides.
//
// Covered scenarios:
//   1.   All 6 OTP boxes filled → verify button enables.
//   2.   Fewer than 6 boxes filled → verify button is opacity-disabled.
//   3.   Resend timer counts down and re-enables the resend link at 0.
//   3b.  Tapping btn-resend clears OTP boxes and hides the resend button.
//   4.   Verify success navigates to /done (→ / via redirect).
//   5.   Verify failure → inline error text uses l10n key (not raw string).
//   6.   Back link taps → navigates to /register.
//   7.   BackdropFilter render-budget: at most 2 BackdropFilter nodes on screen
//        (ceiling — strict target is 1).
//   8.   CTA is opacity-disabled when authProvider is AsyncLoading.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/verification_screen.dart';
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
/// Includes /register and /done (→ home) as navigation targets.
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
    // Phase 2.16 — the back link on verification now returns to Step 3
    // of the wizard (the natural previous step), not /register.
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

/// Types one digit into each of the 6 OTP boxes.
Future<void> _fillOtp(WidgetTester tester, String digits) async {
  assert(digits.length == 6, 'OTP must be exactly 6 digits');
  for (var i = 0; i < 6; i++) {
    await tester.tap(find.byKey(Key('otp-box-$i')));
    await tester.pump();
    await tester.enterText(find.byKey(Key('otp-box-$i')), digits[i]);
    await tester.pump();
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('VerificationScreen', () {
    // -----------------------------------------------------------------------
    // Test 1 — All 6 boxes filled → verify button becomes enabled
    // -----------------------------------------------------------------------
    testWidgets('1. filling all 6 OTP boxes enables the verify button', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpVerification(tester, repo: repo, router: router);

      // Fill all 6 boxes — this enables the button.
      await _fillOtp(tester, '123456');
      await tester.pumpAndSettle();

      // Scroll to btn-verify (may be below the 800×600 test viewport).
      await tester.ensureVisible(find.byKey(const Key('btn-verify')));
      await tester.pumpAndSettle();

      // The key is present and the AnimatedOpacity is 1.0.
      final opacityWidget = tester.widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.byKey(const Key('btn-verify')),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      );
      expect(opacityWidget.opacity, equals(1.0));
    });

    // -----------------------------------------------------------------------
    // Test 2 — Fewer than 6 boxes → button opacity-disabled
    // -----------------------------------------------------------------------
    testWidgets(
      '2. fewer than 6 OTP digits keeps verify button opacity-disabled',
      (tester) async {
        final repo = FakeAuthRepository();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        // Fill only 5 boxes.
        for (var i = 0; i < 5; i++) {
          await tester.tap(find.byKey(Key('otp-box-$i')));
          await tester.pump();
          await tester.enterText(find.byKey(Key('otp-box-$i')), '$i');
          await tester.pump();
        }
        await tester.pumpAndSettle();

        // The AnimatedOpacity wraps the button — find it and check opacity.
        final opacityWidget = tester.widget<AnimatedOpacity>(
          find
              .ancestor(
                of: find.byKey(const Key('btn-verify')),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        );
        expect(opacityWidget.opacity, lessThan(1.0));
      },
    );

    // -----------------------------------------------------------------------
    // Test 3 — Resend timer: btn-resend not visible while counting down;
    //           appears when fake timer reaches 0.
    // -----------------------------------------------------------------------
    testWidgets(
      '3. resend link hidden while countdown is active, visible when timer = 0',
      (tester) async {
        final repo = FakeAuthRepository();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        // Resend button should be absent immediately (timer just started).
        expect(find.byKey(const Key('btn-resend')), findsNothing);

        // Advance fake time by 91 seconds to exhaust the 90-second countdown.
        await tester.pump(const Duration(seconds: 91));
        await tester.pump(); // allow setState to propagate

        // Resend button should now be visible.
        expect(find.byKey(const Key('btn-resend')), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // Test 3b — Tapping btn-resend clears OTP boxes and restarts the timer
    //           (QA MEDIUM-2 fix — Test 3 verified the timer countdown but
    //           never tapped the resend button to verify its action).
    // -----------------------------------------------------------------------
    testWidgets(
      '3b. tapping btn-resend clears OTP boxes and hides the resend button '
      '(timer restarts)',
      (tester) async {
        final repo = FakeAuthRepository();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        // Fill all 6 OTP boxes so there is visible data to clear.
        await _fillOtp(tester, '654321');
        await tester.pump();

        // Advance fake time past the 90-second countdown so btn-resend appears.
        await tester.pump(const Duration(seconds: 91));
        await tester.pump();
        expect(find.byKey(const Key('btn-resend')), findsOneWidget);

        // Tap the resend button.
        await tester.tap(find.byKey(const Key('btn-resend')));
        await tester.pump();

        // After tapping resend the timer restarts → btn-resend disappears
        // (the countdown is active again, _canResend == false).
        expect(
          find.byKey(const Key('btn-resend')),
          findsNothing,
          reason:
              'Tapping btn-resend must restart the countdown; '
              'btn-resend must not be visible while the timer is running',
        );

        // All 6 OTP controllers must be cleared.
        for (var i = 0; i < 6; i++) {
          final box = tester.widget<TextField>(
            find.descendant(
              of: find.byKey(Key('otp-box-$i')),
              matching: find.byType(TextField),
            ),
          );
          expect(
            box.controller?.text,
            isEmpty,
            reason: 'OTP box $i must be cleared after tapping btn-resend',
          );
        }
      },
    );

    // -----------------------------------------------------------------------
    // Test 3c — Resend 429 ResendThrottledFailure adopts server retryAfterSeconds
    //           (M-Sec-1 fix, 2026-05-20)
    //
    // Before the fix `_resend()` cleared the OTP boxes and called
    // `_startCountdown()` BEFORE the await — so a 429 with
    // `retryAfterSeconds > 90` would silently shorten the lockout and wipe
    // the user's typed digits even though the request never consumed a slot.
    //
    // This test asserts the post-fix contract:
    //   - OTP boxes retain whatever was typed (NOT cleared).
    //   - The inline error renders the throttled message (l10n key
    //     `verificationErrResendThrottled`, parameter = retryAfterSeconds).
    //   - The local timer adopts the server value (42 s here) and drains
    //     organically — btn-resend stays hidden for 41 more seconds and
    //     reappears on the 42nd.
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

        // Drain the initial 90 s countdown so btn-resend is tappable.
        await tester.pump(const Duration(seconds: 91));
        await tester.pump();
        expect(find.byKey(const Key('btn-resend')), findsOneWidget);

        // Tap btn-resend — fake throws ResendThrottledFailure(42).
        await tester.tap(find.byKey(const Key('btn-resend')));
        // Cannot pumpAndSettle: the throttle catch restarts the periodic
        // timer, which fires setState every second.
        await tester.pump(); // begin async
        await tester.pump(); // microtasks (await + catch)
        await tester.pump(const Duration(milliseconds: 50));

        // OTP digits must be preserved — the request never consumed a slot.
        for (var i = 0; i < 6; i++) {
          final box = tester.widget<TextField>(
            find.descendant(
              of: find.byKey(Key('otp-box-$i')),
              matching: find.byType(TextField),
            ),
          );
          expect(
            box.controller?.text,
            equals('654321'[i]),
            reason:
                'OTP box $i must retain its digit after a throttled resend; '
                'optimistic clear was the M-Sec-1 bug',
          );
        }

        // Inline error must use the localized throttled message.
        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const Key('otp-box-0'))),
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

        // Btn-resend must be hidden — the timer adopted 42 s.
        expect(find.byKey(const Key('btn-resend')), findsNothing);

        // After 41 seconds the timer is still running; btn-resend remains
        // hidden because _secondsLeft > 0.
        await tester.pump(const Duration(seconds: 41));
        expect(
          find.byKey(const Key('btn-resend')),
          findsNothing,
          reason:
              'btn-resend must stay hidden while the server throttle has not '
              'fully elapsed',
        );

        // The 42nd second drains _secondsLeft to 0 → btn-resend reappears.
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.byKey(const Key('btn-resend')),
          findsOneWidget,
          reason:
              'btn-resend must reappear once the server-mandated cooldown '
              'has fully elapsed',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 4 — Verify success navigates to /done (→ / redirect)
    // -----------------------------------------------------------------------
    testWidgets('4. verify success navigates away from verification screen', (
      tester,
    ) async {
      final repo = FakeAuthRepository()
        ..verifyEmailResult = null; // null = success
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpVerification(tester, repo: repo, router: router);

      // Fill OTP.
      await _fillOtp(tester, '654321');
      await tester.pumpAndSettle();

      // Scroll to btn-verify (may be below the 800×600 test viewport).
      await tester.ensureVisible(find.byKey(const Key('btn-verify')));
      await tester.pumpAndSettle();

      // Tap verify.
      await tester.tap(find.byKey(const Key('btn-verify')));
      await tester.pumpAndSettle();

      // /done redirects to home — expect the placeholder home screen.
      expect(find.text('home'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 5 — Verify failure (typed VerificationFailure) shows inline copy
    //
    // Backend Phase 1.5 contract: a 400 with `data.code: "INVALID_CODE"` is
    // mapped to VerificationFailure(invalidCode) by the interceptor. The
    // screen renders [Failure.userMessage(context)] which resolves to the
    // verificationErrInvalidCode l10n key.
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
      // Use pump (not pumpAndSettle) because the countdown timer fires
      // setState every second, which prevents pumpAndSettle from settling.
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('btn-verify')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-verify')));
      // Drive microtasks and animation frames.
      // Cannot use pumpAndSettle because the countdown timer fires setState
      // every second, preventing the framework from settling.
      await tester.pump(); // begin async
      await tester.pump(); // complete microtasks
      await tester.pump(const Duration(milliseconds: 50)); // animations

      // Should still be on verification screen with an error message visible.
      expect(find.byKey(const Key('btn-verify')), findsOneWidget);
      // Use l10n key lookup instead of a raw string so the test survives
      // copy changes and locale updates (QA MEDIUM-1 fix).
      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('btn-verify'))),
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
    // Test 6 — Back link navigates to /register/step-3 (Phase 2.16)
    // -----------------------------------------------------------------------
    testWidgets('6. back link navigates to /register/step-3', (tester) async {
      final repo = FakeAuthRepository();
      final router = _makeRouter();
      addTearDown(router.dispose);

      await _pumpVerification(tester, repo: repo, router: router);

      // The back link may be below the 800×600 test viewport — scroll to it.
      await tester.ensureVisible(find.byKey(const Key('btn-back')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-back')));
      await tester.pumpAndSettle();

      // Phase 2.16 — should be on the Step 3 placeholder route (the natural
      // previous step in the wizard).
      expect(find.text('register-step-3'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Test 7 — BackdropFilter render-budget: ≤ 2 on screen
    //           (strict target: exactly 1 — the glass card)
    // -----------------------------------------------------------------------
    testWidgets(
      '7. BackdropFilter count is within render-budget ceiling (≤ 2)',
      (tester) async {
        final repo = FakeAuthRepository();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        final bdfCount = tester.widgetList(find.byType(BackdropFilter)).length;

        // Ceiling is 2 to allow for OS-injected layers. Strict target is 1.
        expect(
          bdfCount,
          lessThanOrEqualTo(2),
          reason:
              'Expected ≤2 BackdropFilter nodes (render-budget ceiling). '
              'Found $bdfCount — check for extra blur layers.',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 7b — OTP TextField hardening (backlog row 161, gate crossed)
    //
    // Each _OtpBox TextField must:
    //   - disable autocorrect       (no learned suggestions for OTP digits)
    //   - disable text suggestions  (same as above on Android)
    //   - disable IME personalised learning (no on-device retention)
    //   - declare autofillHints: [AutofillHints.oneTimeCode] so Android /
    //     iOS can offer the SMS OTP autofill prompt.
    // -----------------------------------------------------------------------
    testWidgets(
      '7b. _OtpBox TextField has security hardening + AutofillHints.oneTimeCode',
      (tester) async {
        final repo = FakeAuthRepository();
        final router = _makeRouter();
        addTearDown(router.dispose);

        await _pumpVerification(tester, repo: repo, router: router);

        for (var i = 0; i < 6; i++) {
          final field = tester.widget<TextField>(
            find.descendant(
              of: find.byKey(Key('otp-box-$i')),
              matching: find.byType(TextField),
            ),
          );
          expect(
            field.autocorrect,
            isFalse,
            reason: 'OTP box $i must disable autocorrect',
          );
          expect(
            field.enableSuggestions,
            isFalse,
            reason: 'OTP box $i must disable text suggestions',
          );
          expect(
            field.enableIMEPersonalizedLearning,
            isFalse,
            reason: 'OTP box $i must disable IME personalised learning',
          );
          expect(
            field.autofillHints,
            contains(AutofillHints.oneTimeCode),
            reason:
                'OTP box $i must declare AutofillHints.oneTimeCode so SMS '
                'autofill can prompt with the received code',
          );
        }
      },
    );

    // -----------------------------------------------------------------------
    // Test 4b — Verify success flips auth state to Authenticated
    //
    // Backend Phase 1.5 contract: verify-email returns a full session, so
    // the notifier writes the refresh token + transitions state. We assert
    // both side-effects via the captured FakeSecureStorage.
    // -----------------------------------------------------------------------
    testWidgets(
      '4b. verify success persists refresh token and arrives at home',
      (tester) async {
        final repo =
            FakeAuthRepository(); // default = success with default user
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

        await tester.ensureVisible(find.byKey(const Key('btn-verify')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn-verify')));
        await tester.pumpAndSettle();

        // /done forwards to home — the placeholder is now visible.
        expect(find.text('home'), findsOneWidget);

        // The captured args carry both email and otp (backlog row 164).
        expect(repo.verifyEmailCalls, hasLength(1));
        expect(repo.verifyEmailCalls.single.email, equals(_testEmail));
        expect(repo.verifyEmailCalls.single.otp, equals('654321'));

        // Refresh token was persisted (security invariant MS-1) — the
        // FakeAuthRepository default tokens have refreshToken = 'refresh-token'.
        expect(await storage.readRefreshToken(), equals('refresh-token'));
      },
    );

    // -----------------------------------------------------------------------
    // Test 8 — CTA disabled while authProvider is in AsyncLoading state
    //           (QA MEDIUM-3 fix)
    // -----------------------------------------------------------------------
    testWidgets(
      '8. CTA verify button is opacity-disabled when authProvider is AsyncLoading',
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

        // Fill all 6 OTP boxes — the button would be enabled if not loading.
        for (var i = 0; i < 6; i++) {
          await tester.tap(find.byKey(Key('otp-box-$i')));
          await tester.pump();
          await tester.enterText(find.byKey(Key('otp-box-$i')), '$i');
          await tester.pump();
        }

        await tester.ensureVisible(find.byKey(const Key('btn-verify')));
        await tester.pump();

        // The CTA is wrapped in AnimatedOpacity — when isLoading is true the
        // opacity is 0.4 (disabled) regardless of OTP completeness.
        final opacityWidget = tester.widget<AnimatedOpacity>(
          find
              .ancestor(
                of: find.byKey(const Key('btn-verify')),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        );
        expect(
          opacityWidget.opacity,
          lessThan(1.0),
          reason:
              'CTA must remain opacity-disabled while authProvider is loading, '
              'even when all 6 OTP boxes are filled',
        );

        // The Key('btn-verify') is placed directly on the InkWell widget.
        // When enabled is false, InkWell.onTap is null (CTA is not tappable).
        final inkWell = tester.widget<InkWell>(
          find.byKey(const Key('btn-verify')),
        );
        expect(
          inkWell.onTap,
          isNull,
          reason: 'btn-verify InkWell.onTap must be null while loading',
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
