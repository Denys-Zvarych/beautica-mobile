// Phase 2.13 — Widget tests for ResetPasswordScreen.
//
// Covered scenarios:
//   1. Criteria pills + mismatch error → submit blocked, repo NOT called.
//   2. Valid matching password → confirmPasswordReset(token, newPassword)
//      called and the success state is shown.
//   3. Success "Увійти" CTA navigates to /login.
//   4. Generic 400 (ResetTokenInvalidFailure) → invalid-link state shown;
//      its CTA navigates to /forgot-password.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/presentation/reset_password_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';

const _kToken = 'raw-reset-token';

// The length-criterion dot colours from PasswordCriteriaRow (private consts
// mirrored here intentionally — asserting the rendered colour is the
// behavioural signal that the pill flipped unmet→met).
const _kDotOk = Color(0xFF10B981);
const _kDotNo = Color(0x2EFFFFFF);

/// Returns the [Color] of the FIRST 6×6 criterion dot (the "8+ симв." length
/// pill) inside the reset criteria row. The dot is a 6×6 [Container] whose
/// decoration colour is `_kOk` when met and `_kNo` when unmet.
Color _lengthDotColor(WidgetTester tester) {
  final dots = tester
      .widgetList<Container>(
        find.descendant(
          of: find.byKey(const Key('reset-criteria-row')),
          matching: find.byType(Container),
        ),
      )
      .where((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.shape == BoxShape.circle;
      })
      .toList();
  final first = dots.first.decoration! as BoxDecoration;
  return first.color!;
}

GoRouter _makeRouter({String token = _kToken}) => GoRouter(
  initialLocation: RouteNames.resetPassword,
  redirect: (context, state) => null,
  routes: [
    GoRoute(
      path: RouteNames.resetPassword,
      builder: (context, state) => ResetPasswordScreen(token: token),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('login'))),
    ),
    GoRoute(
      path: RouteNames.forgotPassword,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('forgot'))),
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  FakeAuthRepository repo, {
  String token = _kToken,
}) async {
  final router = _makeRouter(token: token);
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
  group('ResetPasswordScreen', () {
    testWidgets('1. criteria pills present + mismatch blocks submit', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      await _pump(tester, repo);
      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('reset-criteria-row'))),
      );

      // Criteria row is present (reused PasswordCriteriaRow).
      expect(find.byKey(const Key('reset-criteria-row')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('reset-new-password-field')),
        'Password1',
      );
      await tester.enterText(
        find.byKey(const Key('reset-confirm-password-field')),
        'Different1',
      );
      await tester.tap(find.byKey(const Key('reset-submit')));
      await tester.pumpAndSettle();

      // Mismatch error shown; repo not called; still on the form.
      expect(find.text(l10n.errPasswordsMismatch), findsOneWidget);
      expect(repo.confirmPasswordResetCalls, isEmpty);
      expect(find.byKey(const Key('reset-new-password-field')), findsOneWidget);
    });

    testWidgets(
      '2. valid matching password → confirmPasswordReset called + success',
      (tester) async {
        final repo = FakeAuthRepository(); // default: success
        await _pump(tester, repo);

        await tester.enterText(
          find.byKey(const Key('reset-new-password-field')),
          'Password1',
        );
        await tester.enterText(
          find.byKey(const Key('reset-confirm-password-field')),
          'Password1',
        );
        await tester.tap(find.byKey(const Key('reset-submit')));
        await tester.pumpAndSettle();

        expect(repo.confirmPasswordResetCalls.length, 1);
        expect(repo.confirmPasswordResetCalls.first.token, _kToken);
        expect(repo.confirmPasswordResetCalls.first.newPassword, 'Password1');

        // Success state — "Увійти" CTA present, form gone.
        expect(find.byKey(const Key('reset-success-cta')), findsOneWidget);
        expect(find.byKey(const Key('reset-new-password-field')), findsNothing);
      },
    );

    testWidgets('3. success CTA navigates to /login', (tester) async {
      final repo = FakeAuthRepository();
      await _pump(tester, repo);

      await tester.enterText(
        find.byKey(const Key('reset-new-password-field')),
        'Password1',
      );
      await tester.enterText(
        find.byKey(const Key('reset-confirm-password-field')),
        'Password1',
      );
      await tester.tap(find.byKey(const Key('reset-submit')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reset-success-cta')));
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
    });

    testWidgets(
      '4. invalid token (generic 400) → invalid state + CTA to /forgot-password',
      (tester) async {
        final repo = FakeAuthRepository()
          ..confirmPasswordResetResult = const ResetTokenInvalidFailure();
        await _pump(tester, repo);

        await tester.enterText(
          find.byKey(const Key('reset-new-password-field')),
          'Password1',
        );
        await tester.enterText(
          find.byKey(const Key('reset-confirm-password-field')),
          'Password1',
        );
        await tester.tap(find.byKey(const Key('reset-submit')));
        await tester.pumpAndSettle();

        // Invalid-link state — recovery CTA present.
        expect(find.byKey(const Key('reset-invalid-cta')), findsOneWidget);

        await tester.tap(find.byKey(const Key('reset-invalid-cta')));
        await tester.pumpAndSettle();
        expect(find.text('forgot'), findsOneWidget);
      },
    );

    // MEDIUM — criteria-pill reactivity. Typing a PARTIAL password ("pass":
    // 4 chars, no digit, no uppercase) leaves the "8+ симв." length pill UNMET;
    // completing it to 8+ chars must flip the dot unmet→met. Exercises the
    // _NewPasswordField controller listener (reset_password_screen.dart:411).
    testWidgets('5. criteria pill flips unmet→met as password is typed', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      await _pump(tester, repo);

      // Empty → length unmet.
      expect(_lengthDotColor(tester), _kDotNo);

      // Partial (4 chars) → still unmet.
      await tester.enterText(
        find.byKey(const Key('reset-new-password-field')),
        'pass',
      );
      await tester.pump();
      expect(_lengthDotColor(tester), _kDotNo);

      // 8+ chars → met (dot turns green).
      await tester.enterText(
        find.byKey(const Key('reset-new-password-field')),
        'password',
      );
      await tester.pump();
      expect(_lengthDotColor(tester), _kDotOk);
    });

    // MEDIUM — empty-token fail-closed. The router parses a missing `?token=`
    // to '' (empty string), and the screen still renders the form. Submitting
    // a valid new password must rely on the backend rejecting the empty token
    // with a generic 400 → ResetTokenInvalidFailure → invalid-link state. This
    // confirms the screen does NOT optimistically show success for a blank
    // token (fail-closed).
    testWidgets('6. empty token → backend 400 drives the invalid-link state', (
      tester,
    ) async {
      final repo = FakeAuthRepository()
        ..confirmPasswordResetResult = const ResetTokenInvalidFailure();
      await _pump(tester, repo, token: '');

      await tester.enterText(
        find.byKey(const Key('reset-new-password-field')),
        'Password1',
      );
      await tester.enterText(
        find.byKey(const Key('reset-confirm-password-field')),
        'Password1',
      );
      await tester.tap(find.byKey(const Key('reset-submit')));
      await tester.pumpAndSettle();

      // The empty token was forwarded verbatim (no client-side guess/skip).
      expect(repo.confirmPasswordResetCalls.length, 1);
      expect(repo.confirmPasswordResetCalls.first.token, '');
      // Fail-closed: invalid-link state, NOT success.
      expect(find.byKey(const Key('reset-invalid-cta')), findsOneWidget);
      expect(find.byKey(const Key('reset-success-cta')), findsNothing);
    });

    // MEDIUM — retryable-error branch (distinct from the invalid-token path).
    // A NetworkFailure (NOT ResetTokenInvalidFailure) must show an inline error
    // and KEEP the user on the form so they can retry, never the invalid-link
    // state (reset_password_screen.dart:231-240).
    testWidgets(
      '7. NetworkFailure → inline error, stays on form (not invalid state)',
      (tester) async {
        final repo = FakeAuthRepository()
          ..confirmPasswordResetResult = const NetworkFailure();
        await _pump(tester, repo);
        final l10n = AppLocalizations.of(
          tester.element(find.byKey(const Key('reset-new-password-field'))),
        );

        await tester.enterText(
          find.byKey(const Key('reset-new-password-field')),
          'Password1',
        );
        await tester.enterText(
          find.byKey(const Key('reset-confirm-password-field')),
          'Password1',
        );
        await tester.tap(find.byKey(const Key('reset-submit')));
        await tester.pumpAndSettle();

        expect(repo.confirmPasswordResetCalls.length, 1);
        // Inline retryable error, form still present, NOT the invalid-link card.
        expect(find.text(l10n.errNetwork), findsOneWidget);
        expect(
          find.byKey(const Key('reset-new-password-field')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('reset-invalid-cta')), findsNothing);
        expect(find.byKey(const Key('reset-success-cta')), findsNothing);
      },
    );

    // MEDIUM — ServerFailure shares the retryable branch with NetworkFailure
    // (anything that is not ResetTokenInvalidFailure). Locks that a 5xx keeps
    // the user on the form rather than mislabelling the link as invalid.
    testWidgets('8. ServerFailure → inline error, stays on form', (
      tester,
    ) async {
      final repo = FakeAuthRepository()
        ..confirmPasswordResetResult = const ServerFailure(statusCode: 503);
      await _pump(tester, repo);
      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('reset-new-password-field'))),
      );

      await tester.enterText(
        find.byKey(const Key('reset-new-password-field')),
        'Password1',
      );
      await tester.enterText(
        find.byKey(const Key('reset-confirm-password-field')),
        'Password1',
      );
      await tester.tap(find.byKey(const Key('reset-submit')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.errServer), findsOneWidget);
      expect(find.byKey(const Key('reset-new-password-field')), findsOneWidget);
      expect(find.byKey(const Key('reset-invalid-cta')), findsNothing);
    });

    // LOW — password-visibility toggles flip obscureText on both fields.
    testWidgets('9. visibility toggles reveal/hide both password fields', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      await _pump(tester, repo);

      EditableText editableUnder(Key fieldKey) => tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(fieldKey),
          matching: find.byType(EditableText),
        ),
      );

      // Both start obscured.
      expect(
        editableUnder(const Key('reset-new-password-field')).obscureText,
        isTrue,
      );
      expect(
        editableUnder(const Key('reset-confirm-password-field')).obscureText,
        isTrue,
      );

      await tester.tap(find.byKey(const Key('reset-toggle-new')));
      await tester.tap(find.byKey(const Key('reset-toggle-confirm')));
      await tester.pump();

      // Both revealed after toggling.
      expect(
        editableUnder(const Key('reset-new-password-field')).obscureText,
        isFalse,
      );
      expect(
        editableUnder(const Key('reset-confirm-password-field')).obscureText,
        isFalse,
      );
    });

    // LOW — bottom back-to-login link navigates to /login (State A).
    testWidgets('10. back-to-login link navigates to /login', (tester) async {
      final repo = FakeAuthRepository();
      await _pump(tester, repo);

      await tester.ensureVisible(find.byKey(const Key('reset-back-to-login')));
      await tester.tap(find.byKey(const Key('reset-back-to-login')));
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
    });
  });
}
