// Phase 2.13 — Widget tests for ForgotPasswordRequestScreen.
//
// Harness mirrors login_screen_test.dart: a minimal GoRouter with the screen
// at /forgot-password (+ a /login placeholder) and a FakeAuthRepository wired
// through ProviderScope overrides.
//
// Covered scenarios:
//   1. Invalid email → validator error shown, requestPasswordReset NOT called.
//   2. Valid email + submit → requestPasswordReset(email) called and the
//      generic confirmation state is shown.
//   3. Confirmation state renders the generic anti-enumeration copy + resend.
//   4. Bottom "Повернутись до входу" link navigates to /login.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/presentation/forgot_password_request_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';

GoRouter _makeRouter() => GoRouter(
  initialLocation: RouteNames.forgotPassword,
  redirect: (context, state) => null,
  routes: [
    GoRoute(
      path: RouteNames.forgotPassword,
      builder: (context, state) => const ForgotPasswordRequestScreen(),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('login'))),
    ),
  ],
);

Future<void> _pump(WidgetTester tester, FakeAuthRepository repo) async {
  final router = _makeRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWith((_) => repo)],
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
    testWidgets('1. invalid email → error shown, repo NOT called', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      await _pump(tester, repo);

      await tester.enterText(
        find.byKey(const Key('forgot-email-field')),
        'not-an-email',
      );
      await tester.ensureVisible(find.byKey(const Key('forgot-submit')));
      await tester.tap(find.byKey(const Key('forgot-submit')));
      await tester.pumpAndSettle();

      expect(repo.requestPasswordResetCalls, isEmpty);
      // Still on the request state (email field present).
      expect(find.byKey(const Key('forgot-email-field')), findsOneWidget);
    });

    testWidgets(
      '2. valid email → requestPasswordReset called + confirmation shown',
      (tester) async {
        final repo = FakeAuthRepository(); // default: generic success
        await _pump(tester, repo);

        await tester.enterText(
          find.byKey(const Key('forgot-email-field')),
          'anya@example.com',
        );
        await tester.pump();
        await tester.ensureVisible(find.byKey(const Key('forgot-submit')));
        await tester.tap(find.byKey(const Key('forgot-submit')));
        await tester.pumpAndSettle();

        expect(repo.requestPasswordResetCalls.length, 1);
        expect(repo.requestPasswordResetCalls.first.email, 'anya@example.com');

        // Confirmation state — the email field is gone; the back-to-login CTA
        // and the resend link are present.
        expect(find.byKey(const Key('forgot-email-field')), findsNothing);
        expect(find.byKey(const Key('forgot-confirm-back')), findsOneWidget);
        expect(find.byKey(const Key('forgot-resend')), findsOneWidget);
      },
    );

    testWidgets(
      '3. confirmation renders generic copy + resend returns to form',
      (tester) async {
        final repo = FakeAuthRepository();
        await _pump(tester, repo);
        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const Key('forgot-email-field'))),
        );

        await tester.enterText(
          find.byKey(const Key('forgot-email-field')),
          'anya@example.com',
        );
        // Let the ValueListenableBuilder rebuild the CTA to its enabled state
        // before tapping (it gates on the email controller having text).
        await tester.pump();
        await tester.ensureVisible(find.byKey(const Key('forgot-submit')));
        await tester.tap(find.byKey(const Key('forgot-submit')));
        await tester.pumpAndSettle();

        expect(find.text(l10n.forgotPasswordConfirmTitle), findsOneWidget);
        expect(find.text(l10n.forgotPasswordConfirmDesc), findsOneWidget);

        // Tapping "Надіслати ще раз" returns to the entry state.
        await tester.ensureVisible(find.byKey(const Key('forgot-resend')));
        await tester.tap(find.byKey(const Key('forgot-resend')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('forgot-email-field')), findsOneWidget);
      },
    );

    testWidgets('4. back-to-login link navigates to /login', (tester) async {
      final repo = FakeAuthRepository();
      await _pump(tester, repo);

      await tester.ensureVisible(find.byKey(const Key('forgot-back-to-login')));
      await tester.tap(find.byKey(const Key('forgot-back-to-login')));
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
    });

    // MEDIUM — anti-enumeration negative half. A genuine transport failure must
    // NOT masquerade as the generic confirmation success. The repo throws a
    // NetworkFailure → the screen surfaces the inline error
    // (forgot_password_request_screen.dart:229-240) and STAYS on the entry
    // form (email field still present, confirmation chrome absent).
    testWidgets(
      '5. NetworkFailure → inline error shown, does NOT switch to confirmation',
      (tester) async {
        final repo = FakeAuthRepository()
          ..requestPasswordResetResult = const NetworkFailure();
        await _pump(tester, repo);
        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const Key('forgot-email-field'))),
        );

        await tester.enterText(
          find.byKey(const Key('forgot-email-field')),
          'anya@example.com',
        );
        // Let the ValueListenableBuilder enable the CTA before tapping.
        await tester.pump();
        await tester.ensureVisible(find.byKey(const Key('forgot-submit')));
        await tester.tap(find.byKey(const Key('forgot-submit')));
        await tester.pumpAndSettle();

        // Repo WAS called (the failure happened inside it)…
        expect(repo.requestPasswordResetCalls.length, 1);
        // …but the inline network error renders and the screen stays on State A.
        expect(find.text(l10n.errNetwork), findsOneWidget);
        expect(find.byKey(const Key('forgot-email-field')), findsOneWidget);
        // Confirmation chrome must be absent — a failure is not a success.
        expect(find.byKey(const Key('forgot-confirm-back')), findsNothing);
        expect(find.byKey(const Key('forgot-resend')), findsNothing);
      },
    );

    // LOW — anti-enumeration UI identity. A DISTINCT, almost-certainly-unknown
    // email must render the SAME confirmation widget as a known one. The fake
    // returns generic success regardless of address, so this locks that the
    // screen never branches on the email value (no enumeration side channel).
    testWidgets(
      '6. unknown email renders the SAME generic confirmation widget',
      (tester) async {
        final repo = FakeAuthRepository(); // default: generic success
        await _pump(tester, repo);
        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const Key('forgot-email-field'))),
        );

        await tester.enterText(
          find.byKey(const Key('forgot-email-field')),
          'no-such-user-9f3a@nonexistent.example',
        );
        await tester.pump();
        await tester.ensureVisible(find.byKey(const Key('forgot-submit')));
        await tester.tap(find.byKey(const Key('forgot-submit')));
        await tester.pumpAndSettle();

        expect(
          repo.requestPasswordResetCalls.first.email,
          'no-such-user-9f3a@nonexistent.example',
        );
        // Identical confirmation copy + keys as the known-email path (test 2/3).
        expect(find.text(l10n.forgotPasswordConfirmTitle), findsOneWidget);
        expect(find.text(l10n.forgotPasswordConfirmDesc), findsOneWidget);
        expect(find.byKey(const Key('forgot-confirm-back')), findsOneWidget);
        expect(find.byKey(const Key('forgot-resend')), findsOneWidget);
        expect(find.byKey(const Key('forgot-email-field')), findsNothing);
      },
    );
  });
}
