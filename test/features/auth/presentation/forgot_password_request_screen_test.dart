// Phase 2.13 — Widget tests for ForgotPasswordRequestScreen (VelvetTouch).
// Beautica OTP task (Phase B3/B6) — rewritten for the email-link → OTP flow.
//
// Harness mirrors login_screen_test.dart: a minimal GoRouter with the screen
// at /forgot-password (+ /login and /reset-password/otp placeholders) and a
// FakeAuthRepository wired through ProviderScope overrides.
//
// Key changes from the pre-OTP version:
//   - The screen is now SINGLE-STATE (form only) — the old "check your email
//     for a link" confirmation state (_linkSent, forgot_preview_reset CTA) is
//     gone. A successful submit navigates to RouteNames.resetOtpVerification
//     carrying the email in `extra` instead of flipping to an in-screen state.
//   - Tests 3 (confirmation copy) and the "reach sent state first" premise of
//     test 4 are retired; test 4 now asserts the back button from the plain
//     form state.
//   - All keys updated to ValueKey<String>('snake_case') per VelvetTouch spec.
//
// Covered scenarios:
//   1. Invalid email → inline error shown, requestPasswordReset NOT called.
//   2. Valid email + submit → requestPasswordReset(email) called and
//      navigation to the OTP screen with the email in `extra`.
//   3. Top-left back button navigates to /login.
//   4. NetworkFailure → inline error shown, does NOT navigate.
//   5. Unknown email navigates the SAME way as a known one (anti-enumeration
//      — the navigation itself must not reveal account existence).
//   6. Loading indicator visible mid-submit; navigates after completer
//      resolves.
//   7. ValidationFailure keyed by email → that message shown inline, no
//      navigation, repo email error preferred over generic copy.
//   8. ValidationFailure with empty fieldErrors falls back to serverMessage.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/presentation/forgot_password_request_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

GoRouter _makeRouter() => GoRouter(
  initialLocation: RouteNames.forgotPassword,
  redirect: (context, state) => null,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.forgotPassword,
      builder: (context, state) => const ForgotPasswordRequestScreen(),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('login'))),
    ),
    GoRoute(
      path: RouteNames.resetOtpVerification,
      builder: (context, state) => Scaffold(
        body: Center(child: Text('otp:${(state.extra as String?) ?? ''}')),
      ),
    ),
  ],
);

Future<void> _pump(WidgetTester tester, FakeAuthRepository repo) async {
  final GoRouter router = _makeRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: [
        authRepositoryProvider.overrideWith((_) => repo),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ForgotPasswordRequestScreen', () {
    testWidgets('1. invalid email → inline error shown, repo NOT called', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repo = FakeAuthRepository();
      await _pump(tester, repo);

      await tester.enterText(
        find.byKey(const ValueKey<String>('forgot_email')),
        'not-an-email',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('forgot_submit')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('forgot_submit')));
      await tester.pumpAndSettle();

      expect(repo.requestPasswordResetCalls, isEmpty);
      // Still on the request state (email field present).
      expect(
        find.byKey(const ValueKey<String>('forgot_email')),
        findsOneWidget,
      );
    });

    testWidgets(
      '2. valid email → requestPasswordReset called + navigates to the OTP '
      'screen carrying the email in extra',
      (WidgetTester tester) async {
        final FakeAuthRepository repo = FakeAuthRepository();
        await _pump(tester, repo);

        await tester.enterText(
          find.byKey(const ValueKey<String>('forgot_email')),
          'anya@example.com',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('forgot_submit')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('forgot_submit')));
        await tester.pumpAndSettle();

        expect(repo.requestPasswordResetCalls.length, 1);
        expect(repo.requestPasswordResetCalls.first.email, 'anya@example.com');

        // Navigated to the OTP screen with the submitted email.
        expect(find.text('otp:anya@example.com'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('forgot_email')),
          findsNothing,
        );
      },
    );

    testWidgets(
      '3. top-left back button (auth_scaffold_back) navigates to /login',
      (WidgetTester tester) async {
        final FakeAuthRepository repo = FakeAuthRepository();
        await _pump(tester, repo);

        await tester.tap(
          find.byKey(const ValueKey<String>('auth_scaffold_back')),
        );
        await tester.pumpAndSettle();

        expect(find.text('login'), findsOneWidget);
      },
    );

    // MEDIUM — anti-enumeration negative half. A genuine transport failure must
    // NOT masquerade as success. The repo throws a NetworkFailure → the screen
    // surfaces the inline error and STAYS on the form (no navigation).
    testWidgets('4. NetworkFailure → inline error shown, does NOT navigate', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repo = FakeAuthRepository()
        ..requestPasswordResetResult = const NetworkFailure();
      await _pump(tester, repo);
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byKey(const ValueKey<String>('forgot_email'))),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('forgot_email')),
        'anya@example.com',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('forgot_submit')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('forgot_submit')));
      await tester.pumpAndSettle();

      // Repo WAS called (the failure happened inside it)…
      expect(repo.requestPasswordResetCalls.length, 1);
      // …but the inline network error renders and the screen stays on the form.
      expect(find.text(l10n.errNetwork), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('forgot_email')),
        findsOneWidget,
      );
      expect(find.textContaining('otp:'), findsNothing);
    });

    // LOW — anti-enumeration UI identity. A DISTINCT, almost-certainly-unknown
    // email must navigate the SAME way as a known one.
    testWidgets('5. unknown email navigates the SAME way as a known one', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repo = FakeAuthRepository();
      await _pump(tester, repo);

      await tester.enterText(
        find.byKey(const ValueKey<String>('forgot_email')),
        'no-such-user-9f3a@nonexistent.example',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('forgot_submit')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('forgot_submit')));
      await tester.pumpAndSettle();

      expect(
        repo.requestPasswordResetCalls.first.email,
        'no-such-user-9f3a@nonexistent.example',
      );
      // Identical navigation target as the known-email path (test 2).
      expect(
        find.text('otp:no-such-user-9f3a@nonexistent.example'),
        findsOneWidget,
      );
    });

    // MEDIUM — loading state independent assertion. Mid-submit (while the repo
    // Future is pending) the button must be in its loading state
    // (CircularProgressIndicator visible); after the completer resolves the
    // screen must navigate to the OTP screen.
    testWidgets(
      '6. loading indicator visible mid-submit; navigates after completer '
      'resolves',
      (WidgetTester tester) async {
        // A Completer that keeps requestPasswordReset pending so we can
        // assert the intermediate loading state before it resolves.
        final Completer<void> completer = Completer<void>();
        final FakeAuthRepository repo = FakeAuthRepository()
          ..requestPasswordResetDelay = completer.future;

        await _pump(tester, repo);

        await tester.enterText(
          find.byKey(const ValueKey<String>('forgot_email')),
          'anya@example.com',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('forgot_submit')),
        );

        // Tap submit and pump one frame — completer not yet completed, so the
        // screen stays in the loading state.
        await tester.tap(find.byKey(const ValueKey<String>('forgot_submit')));
        await tester.pump();

        // The submit button must be in its loading state
        // (NeumorphicButton with loading:true renders CircularProgressIndicator).
        expect(
          find.byType(CircularProgressIndicator),
          findsOneWidget,
          reason:
              'Mid-submit: NeumorphicButton with loading:true must show a '
              'CircularProgressIndicator',
        );

        // Resolve the completer and let the screen navigate away.
        completer.complete();
        await tester.pumpAndSettle();

        // Normal (navigated) state — spinner gone, on the OTP placeholder.
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('otp:anya@example.com'), findsOneWidget);
      },
    );

    // ── 7. ValidationFailure with an email field error → inline email error ──
    //
    // The screen prefers fieldErrors['email'] over the generic errValidation
    // copy, then serverMessage. Guards the inline-mapping extension.
    testWidgets(
      '7. ValidationFailure keyed by email → that message shown inline, no '
      'navigation, repo email error preferred over generic copy',
      (WidgetTester tester) async {
        const emailMsg = 'Невірна адреса електронної пошти';
        final FakeAuthRepository repo = FakeAuthRepository()
          ..requestPasswordResetResult = const ValidationFailure(
            fieldErrors: <String, String>{'email': emailMsg},
          );
        await _pump(tester, repo);
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byKey(const ValueKey<String>('forgot_email'))),
        );

        await tester.enterText(
          find.byKey(const ValueKey<String>('forgot_email')),
          'anya@example.com',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('forgot_submit')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('forgot_submit')));
        await tester.pumpAndSettle();

        expect(repo.requestPasswordResetCalls.length, 1);
        // The email field error wins over the generic errValidation copy.
        expect(find.text(emailMsg), findsOneWidget);
        expect(find.text(l10n.errValidation), findsNothing);
        // Stayed on the request form (no navigation).
        expect(
          find.byKey(const ValueKey<String>('forgot_email')),
          findsOneWidget,
        );
        expect(find.textContaining('otp:'), findsNothing);
      },
    );

    // ── 8. ValidationFailure, empty fieldErrors + serverMessage → fallback ───
    testWidgets(
      '8. ValidationFailure with empty fieldErrors falls back to serverMessage '
      'inline (not the generic errValidation copy)',
      (WidgetTester tester) async {
        const serverMsg = 'Сервіс тимчасово недоступний';
        final FakeAuthRepository repo = FakeAuthRepository()
          ..requestPasswordResetResult = const ValidationFailure(
            fieldErrors: <String, String>{},
            serverMessage: serverMsg,
          );
        await _pump(tester, repo);
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byKey(const ValueKey<String>('forgot_email'))),
        );

        await tester.enterText(
          find.byKey(const ValueKey<String>('forgot_email')),
          'anya@example.com',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('forgot_submit')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('forgot_submit')));
        await tester.pumpAndSettle();

        expect(find.text(serverMsg), findsOneWidget);
        expect(find.text(l10n.errValidation), findsNothing);
        expect(find.textContaining('otp:'), findsNothing);
      },
    );
  });
}
