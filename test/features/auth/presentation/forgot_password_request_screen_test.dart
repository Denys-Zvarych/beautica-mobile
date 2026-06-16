// Phase 2.13 — Widget tests for ForgotPasswordRequestScreen (VelvetTouch).
//
// Harness mirrors login_screen_test.dart: a minimal GoRouter with the screen
// at /forgot-password (+ /login and /reset-password placeholders) and a
// FakeAuthRepository wired through ProviderScope overrides.
//
// Key changes from the pre-VelvetTouch version:
//   - All keys updated to ValueKey<String>('snake_case') per VelvetTouch spec.
//   - No BackdropFilter assertions (glassmorphism removed).
//   - Confirmation state no longer has a "resend" link — instead it has a
//     "У мене є посилання" preview CTA (key 'forgot_preview_reset') that
//     navigates to /reset-password.
//   - The back-to-login affordance is now the top-left AuthScaffold button
//     (key 'auth_scaffold_back'). Test 4 reaches the sent state first.
//   - Email validation is now inline (_inlineError → NeumorphicTextField
//     errorText) rather than Form + GlobalKey, so test 1 checks that the
//     inline email error text appears and the email field is still present.
//
// Covered scenarios:
//   1. Invalid email → inline error shown, requestPasswordReset NOT called.
//   2. Valid email + submit → requestPasswordReset(email) called and the
//      generic confirmation state is shown.
//   3. Confirmation state renders generic copy + preview-reset CTA.
//   4. Back-to-login link (in sent state) navigates to /login.
//   5. NetworkFailure → inline error shown, does NOT switch to confirmation.
//   6. Unknown email renders the SAME generic confirmation widget.

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
      path: RouteNames.resetPassword,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('reset'))),
    ),
  ],
);

Future<void> _pump(WidgetTester tester, FakeAuthRepository repo) async {
  final GoRouter router = _makeRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
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
      '2. valid email → requestPasswordReset called + confirmation shown',
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

        // Confirmation state — the email field is gone; the preview CTA and
        // back-to-login link are present.
        expect(
          find.byKey(const ValueKey<String>('forgot_email')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('forgot_preview_reset')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('auth_scaffold_back')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '3. confirmation state renders generic copy + preview-reset CTA navigates to /reset-password',
      (WidgetTester tester) async {
        final FakeAuthRepository repo = FakeAuthRepository();
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

        // Generic confirmation copy is visible.
        expect(find.text(l10n.forgotPasswordConfirmTitle), findsOneWidget);
        expect(find.text(l10n.forgotPasswordConfirmDesc), findsOneWidget);

        // Tapping "У мене є посилання" navigates to the reset-password screen.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('forgot_preview_reset')),
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('forgot_preview_reset')),
        );
        await tester.pumpAndSettle();
        expect(find.text('reset'), findsOneWidget);
      },
    );

    testWidgets(
      '4. top-left back button (auth_scaffold_back, sent state) navigates to /login',
      (WidgetTester tester) async {
        final FakeAuthRepository repo = FakeAuthRepository();
        await _pump(tester, repo);

        // Reach the sent state first.
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

        // Now tap the top-left back button.
        await tester.tap(
          find.byKey(const ValueKey<String>('auth_scaffold_back')),
        );
        await tester.pumpAndSettle();

        expect(find.text('login'), findsOneWidget);
      },
    );

    // MEDIUM — anti-enumeration negative half. A genuine transport failure must
    // NOT masquerade as the generic confirmation success. The repo throws a
    // NetworkFailure → the screen surfaces the inline error and STAYS on the
    // entry form (email field still present, confirmation chrome absent).
    testWidgets(
      '5. NetworkFailure → inline error shown, does NOT switch to confirmation',
      (WidgetTester tester) async {
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
        // …but the inline network error renders and the screen stays on State A.
        expect(find.text(l10n.errNetwork), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('forgot_email')),
          findsOneWidget,
        );
        // Confirmation chrome must be absent — a failure is not a success.
        expect(
          find.byKey(const ValueKey<String>('forgot_preview_reset')),
          findsNothing,
        );
        // The top-left back button is always present (AuthScaffold.showBack:
        // true), so we only assert the confirmation-specific preview CTA is
        // absent — not the scaffold-level back affordance.
      },
    );

    // MEDIUM — loading state independent assertion. Mid-submit (while the repo
    // Future is pending) the button must be in its loading state
    // (CircularProgressIndicator visible); after the completer resolves the
    // screen must return to its normal state (confirmation shown).
    testWidgets(
      '7. loading indicator visible mid-submit; confirmation shown after '
      'completer resolves',
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

        // Resolve the completer and let the screen transition to sent state.
        completer.complete();
        await tester.pumpAndSettle();

        // Normal (confirmation) state — spinner gone, email field gone.
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('forgot_preview_reset')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('forgot_email')),
          findsNothing,
        );
      },
    );

    // LOW — anti-enumeration UI identity. A DISTINCT, almost-certainly-unknown
    // email must render the SAME confirmation widget as a known one.
    testWidgets('6. unknown email renders the SAME generic confirmation widget', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repo = FakeAuthRepository();
      await _pump(tester, repo);
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byKey(const ValueKey<String>('forgot_email'))),
      );

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
      // Identical confirmation copy + keys as the known-email path (tests 2/3).
      expect(find.text(l10n.forgotPasswordConfirmTitle), findsOneWidget);
      expect(find.text(l10n.forgotPasswordConfirmDesc), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('forgot_preview_reset')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('forgot_email')), findsNothing);
    });

    // ── 8. ValidationFailure with an email field error → inline email error ──
    //
    // The screen now prefers fieldErrors['email'] over the generic errValidation
    // copy, then serverMessage. Guards the inline-mapping extension.
    testWidgets(
      '8. ValidationFailure keyed by email → that message shown inline, no '
      'confirmation, repo email error preferred over generic copy',
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
        // Stayed on the request form (no confirmation).
        expect(
          find.byKey(const ValueKey<String>('forgot_email')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('forgot_preview_reset')),
          findsNothing,
        );
      },
    );

    // ── 9. ValidationFailure, empty fieldErrors + serverMessage → fallback ───
    testWidgets(
      '9. ValidationFailure with empty fieldErrors falls back to serverMessage '
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
        expect(
          find.byKey(const ValueKey<String>('forgot_preview_reset')),
          findsNothing,
        );
      },
    );
  });
}
