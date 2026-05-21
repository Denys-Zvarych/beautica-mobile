// Phase 2.16 — Widget tests for [RegisterStep1Screen] (credentials-only).
//
// SOURCE OF TRUTH: docs/signup-designs/sign-up-page.html (refactored Step 1).
// Step 1 is the credentials form ONLY — email + password + confirm-password.
// Name / surname / phone are tested in Phase 2.17 (Step 2). Salon / address
// fields are tested in Phase 2.19 (Step 3).
//
// Covered scenarios:
//   1. The three inputs (email, password, confirm-password) render.
//   2. Email validator fires on invalid input.
//   3. Password validator fires on empty input.
//   4. Confirm-password validator fires when values do not match.
//   5. Valid submit writes the slice to the draft and navigates to /step-2.
//   6. Draft persists when stepping out and back in (initState pre-fills
//      controllers from the draft).
//   7. Step 1 does NOT call AuthNotifier.register (deferred to Step 3).

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/register_step_1_screen.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

GoRouter _makeRouter() => GoRouter(
  initialLocation: RouteNames.register,
  redirect: (context, state) => null,
  routes: [
    GoRoute(
      path: RouteNames.register,
      // The screen lives inside RegisterFlowShell in production (AuthScaffold
      // wraps it in a Scaffold + Material). The test substitutes a minimal
      // Scaffold so TextFormFields can find a Material ancestor.
      builder: (context, state) => const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: RegisterStep1Screen(),
        ),
      ),
    ),
    GoRoute(
      path: RouteNames.registerStep2,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('step-2'))),
    ),
    GoRoute(
      path: RouteNames.registerRole,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('role-selection'))),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('login'))),
    ),
  ],
);

Widget _buildApp({
  required GoRouter router,
  required ProviderContainer container,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk'),
  ),
);

ProviderContainer _makeContainer({UserRole? role = UserRole.client}) {
  final repo = FakeAuthRepository();
  final storage = FakeSecureStorage();
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWith((_) => repo),
      secureStorageProvider.overrideWith((_) => storage),
    ],
  );
  if (role != null) {
    container.read(registerDraftProvider.notifier).start(role);
  }
  return container;
}

/// Asserts the [FakeAuthRepository.registerCalls] list is empty — i.e. Step 1
/// did NOT fire a registration POST.
///
/// MEDIUM-qa-1: every Step-1 valid-submit test must assert this, not just the
/// dedicated negative test (#7). The real registration POST happens at the
/// end of Step 3 (Phase 2.19).
void _assertNoRegisterPostFired(FakeAuthRepository repo) {
  expect(
    repo.registerCalls,
    isEmpty,
    reason:
        'register_step_1_screen.dart must NOT call AuthNotifier.register — '
        'the real POST happens at the end of Step 3 (Phase 2.19)',
  );
}

/// Variant of [_makeContainer] that returns the [FakeAuthRepository] handle
/// alongside the container, so the test can call [_assertNoRegisterPostFired]
/// without re-reading from the container.
({ProviderContainer container, FakeAuthRepository repo})
_makeContainerWithRepo({UserRole? role = UserRole.client}) {
  final repo = FakeAuthRepository();
  final storage = FakeSecureStorage();
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWith((_) => repo),
      secureStorageProvider.overrideWith((_) => storage),
    ],
  );
  if (role != null) {
    container.read(registerDraftProvider.notifier).start(role);
  }
  return (container: container, repo: repo);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RegisterStep1Screen (credentials only)', () {
    testWidgets('1. three inputs render: email, password, confirm-password', (
      tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('field-email')), findsOneWidget);
      expect(find.byKey(const Key('field-password')), findsOneWidget);
      expect(find.byKey(const Key('field-confirm-password')), findsOneWidget);
      expect(find.byKey(const Key('btn-submit-step-1')), findsOneWidget);

      // Step 1 must NOT render the Step 2 / Step 3 fields.
      expect(find.byKey(const Key('field-firstName')), findsNothing);
      expect(find.byKey(const Key('field-lastName')), findsNothing);
      expect(find.byKey(const Key('field-phone')), findsNothing);
      expect(find.byKey(const Key('field-businessName')), findsNothing);
    });

    testWidgets(
      '2. invalid email shows errEmailInvalid inline (autovalidateMode)',
      (tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field-email')),
          'not-an-email',
        );
        await tester.pump();

        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(find.text(l10n.errEmailInvalid), findsOneWidget);
      },
    );

    testWidgets('3. empty password on submit shows errPasswordRequired', (
      tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('field-email')), 'a@b.com');
      // Leave password blank.
      await tester.ensureVisible(find.byKey(const Key('btn-submit-step-1')));
      await tester.tap(find.byKey(const Key('btn-submit-step-1')));
      await tester.pump();

      // LOW-qa-4: scope the error finder to the password field so the
      // assertion is independent of the confirm-password field also showing
      // its own (different) error message.
      final l10n = lookupAppLocalizations(const Locale('uk'));
      expect(
        find.descendant(
          of: find.byKey(const Key('field-password')),
          matching: find.text(l10n.errPasswordRequired),
        ),
        findsOneWidget,
      );
    });

    testWidgets('4. mismatched confirm-password shows errPasswordsMismatch', (
      tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('field-email')), 'a@b.com');
      await tester.enterText(
        find.byKey(const Key('field-password')),
        'SecurePass1',
      );
      await tester.enterText(
        find.byKey(const Key('field-confirm-password')),
        'WRONG',
      );

      await tester.ensureVisible(find.byKey(const Key('btn-submit-step-1')));
      await tester.tap(find.byKey(const Key('btn-submit-step-1')));
      await tester.pump();

      final l10n = lookupAppLocalizations(const Locale('uk'));
      expect(find.text(l10n.errPasswordsMismatch), findsOneWidget);
      // Step did NOT advance.
      expect(find.text('step-2'), findsNothing);
    });

    testWidgets(
      '5. valid submit writes the slice to the draft and navigates to /step-2 '
      '(NO register POST fired)',
      (tester) async {
        final (:container, :repo) = _makeContainerWithRepo();
        addTearDown(container.dispose);
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field-email')),
          'anya@example.com',
        );
        await tester.enterText(
          find.byKey(const Key('field-password')),
          'SecurePass1',
        );
        await tester.enterText(
          find.byKey(const Key('field-confirm-password')),
          'SecurePass1',
        );

        await tester.ensureVisible(find.byKey(const Key('btn-submit-step-1')));
        await tester.tap(find.byKey(const Key('btn-submit-step-1')));
        await tester.pumpAndSettle();

        // Navigation occurred.
        expect(find.text('step-2'), findsOneWidget);

        // Draft contains the submitted slice (Step 1 only).
        final draft = container.read(registerDraftProvider);
        expect(draft, isNotNull);
        expect(draft!.email, equals('anya@example.com'));
        expect(draft.password, equals('SecurePass1'));
        expect(draft.confirmPassword, equals('SecurePass1'));
        // Role from the role-selection step is preserved.
        expect(draft.role, equals(UserRole.client));

        // MEDIUM-qa-1 — even the CLIENT-role variant must NOT trigger a
        // registration POST. The real POST is deferred to Phase 2.19.
        _assertNoRegisterPostFired(repo);
      },
    );

    testWidgets('6. controllers re-hydrate from the draft on remount (back-nav '
        'persistence)', (tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final router = _makeRouter();
      addTearDown(router.dispose);

      // Pre-seed the draft as if the user already filled Step 1 once.
      container
          .read(registerDraftProvider.notifier)
          .updateStep1(
            email: 'pre-filled@example.com',
            password: 'PrePass1',
            confirmPassword: 'PrePass1',
          );

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      // LOW-qa-1 — all three controllers must rehydrate, not just email.
      // Email.
      final emailField = tester.widget<TextFormField>(
        find.byKey(const Key('field-email')),
      );
      expect(emailField.controller?.text, equals('pre-filled@example.com'));
      // Password.
      final passwordField = tester.widget<TextFormField>(
        find.byKey(const Key('field-password')),
      );
      expect(passwordField.controller?.text, equals('PrePass1'));
      // Confirm password.
      final confirmField = tester.widget<TextFormField>(
        find.byKey(const Key('field-confirm-password')),
      );
      expect(confirmField.controller?.text, equals('PrePass1'));
    });

    testWidgets(
      '8. tapping btn-back-to-role PRESERVES the draft (role survives) AND '
      'navigates to /register/role — the back link goes one wizard step back, '
      'so the role-selection screen can re-highlight the chosen role',
      (tester) async {
        final (:container, :repo) = _makeContainerWithRepo();
        addTearDown(container.dispose);
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // Pre-seed credentials so we can verify the back link does NOT wipe
        // them on a single-step back. We do this via the notifier rather than
        // via on-screen typing because updateStep1 is the canonical write path
        // and avoids depending on the autovalidate / form-validate timing.
        container
            .read(registerDraftProvider.notifier)
            .updateStep1(
              email: 'pre-fill@example.com',
              password: 'PrePass1',
              confirmPassword: 'PrePass1',
            );
        // Sanity check: the draft is populated (default role = client).
        final beforeTap = container.read(registerDraftProvider)!;
        expect(beforeTap.role, equals(UserRole.client));
        expect(beforeTap.email, equals('pre-fill@example.com'));
        expect(beforeTap.password, equals('PrePass1'));

        // The btn-back-to-role link sits at the bottom of the Step 1 screen
        // and may fall below the default 800x600 test viewport fold; scroll
        // it into view before tapping.
        await tester.ensureVisible(find.byKey(const Key('btn-back-to-role')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-back-to-role')));
        await tester.pumpAndSettle();

        // (1) The draft is PRESERVED — going one wizard step back must keep
        // the chosen role (and the in-progress credentials) so the role-
        // selection screen re-highlights the previously chosen role and keeps
        // Continue enabled. The HIGH-1 reset() only fires on the "log in
        // instead" link, not on a single-step back.
        final afterTap = container.read(registerDraftProvider);
        expect(
          afterTap,
          isNotNull,
          reason:
              'Tapping the bottom back link on Step 1 must NOT reset() the '
              'draft — the role must survive a single-step back so role-'
              'selection can re-highlight it.',
        );
        expect(afterTap!.role, equals(UserRole.client));

        // (2) Navigation landed on /register/role.
        expect(
          router.routerDelegate.currentConfiguration.fullPath,
          equals(RouteNames.registerRole),
        );
        expect(find.text('role-selection'), findsOneWidget);

        // (3) No registration POST was fired.
        _assertNoRegisterPostFired(repo);
      },
    );

    testWidgets(
      '7. Step 1 does NOT call AuthNotifier.register on submit (deferred '
      'to Step 3 / Phase 2.19) — INDEPENDENT_MASTER role variant',
      (tester) async {
        // Use the helper container so we can inspect repo.registerCalls.
        final (:container, :repo) = _makeContainerWithRepo(
          role: UserRole.independentMaster,
        );
        addTearDown(container.dispose);

        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('field-email')), 'a@b.com');
        await tester.enterText(
          find.byKey(const Key('field-password')),
          'SecurePass1',
        );
        await tester.enterText(
          find.byKey(const Key('field-confirm-password')),
          'SecurePass1',
        );
        await tester.ensureVisible(find.byKey(const Key('btn-submit-step-1')));
        await tester.tap(find.byKey(const Key('btn-submit-step-1')));
        await tester.pumpAndSettle();

        // Confirms registration POST is NOT triggered by Step 1 for the
        // independent-master role variant either.
        _assertNoRegisterPostFired(repo);
      },
    );

    // -----------------------------------------------------------------------
    // 9. btn-go-to-login navigates to /login (Issue 2 lock-in)
    //
    // Verifies the destination of the "Вже є акаунт? Увійти" link — it MUST
    // go to RouteNames.login, NOT to RouteNames.registerRole. The adjacent
    // btn-back-to-role link (test 8) goes to registerRole, so mis-wiring
    // would make both links land on the same page.
    // -----------------------------------------------------------------------
    testWidgets('9. btn-go-to-login navigates to /login and resets the draft', (
      tester,
    ) async {
      final (:container, :repo) = _makeContainerWithRepo();
      addTearDown(container.dispose);
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      // Scroll to make the login link visible (it lives below the form).
      await tester.ensureVisible(find.byKey(const Key('btn-go-to-login')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-go-to-login')));
      await tester.pumpAndSettle();

      // (1) Navigated to /login.
      expect(
        router.routerDelegate.currentConfiguration.fullPath,
        equals(RouteNames.login),
        reason:
            'btn-go-to-login must navigate to RouteNames.login, '
            'not to registerRole or any other route',
      );
      expect(find.text('login'), findsOneWidget);

      // (2) Draft was reset — the "log in instead" path is a full wizard
      // exit, unlike the single-step btn-back-to-role.
      expect(
        container.read(registerDraftProvider),
        isNull,
        reason: 'btn-go-to-login must reset() the draft before navigating',
      );

      // (3) No registration POST was fired.
      _assertNoRegisterPostFired(repo);
    });

    // -----------------------------------------------------------------------
    // 10. btn-back-to-role destination is /register/role (not /login)
    //
    // Mirror assertion: the back link must NOT navigate to the login page.
    // This complements test 8 (draft preservation) with an explicit
    // destination check, ensuring the two adjacent links are never swapped.
    // -----------------------------------------------------------------------
    testWidgets(
      '10. btn-back-to-role navigates to /register/role (not /login)',
      (tester) async {
        final (:container, :repo) = _makeContainerWithRepo();
        addTearDown(container.dispose);
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('btn-back-to-role')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-back-to-role')));
        await tester.pumpAndSettle();

        expect(
          router.routerDelegate.currentConfiguration.fullPath,
          equals(RouteNames.registerRole),
          reason:
              'btn-back-to-role must navigate to registerRole, not to /login',
        );
        expect(find.text('role-selection'), findsOneWidget);

        _assertNoRegisterPostFired(repo);
      },
    );

    // -----------------------------------------------------------------------
    // 11. Weak password "asd" is blocked at submit by validateNewPassword.
    //
    // Ensures the registration password field uses the STRICT validator, not
    // the lenient validatePassword used by the login screen. "asd" is 3 chars
    // — it fails the minimum-8 rule and must show errPasswordTooShort.
    // The step must NOT advance to step-2, and no registration POST must fire.
    // -----------------------------------------------------------------------
    testWidgets(
      '11. weak password "asd" shows errPasswordTooShort and does NOT advance '
      'or fire a registration POST',
      (tester) async {
        final (:container, :repo) = _makeContainerWithRepo();
        addTearDown(container.dispose);
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field-email')),
          'anya@example.com',
        );
        await tester.enterText(find.byKey(const Key('field-password')), 'asd');
        await tester.enterText(
          find.byKey(const Key('field-confirm-password')),
          'asd',
        );

        await tester.ensureVisible(find.byKey(const Key('btn-submit-step-1')));
        await tester.tap(find.byKey(const Key('btn-submit-step-1')));
        await tester.pump();

        // The password field must show the too-short error.
        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(
          find.descendant(
            of: find.byKey(const Key('field-password')),
            matching: find.text(l10n.errPasswordTooShort),
          ),
          findsOneWidget,
          reason:
              'field-password must show errPasswordTooShort when "asd" is '
              'submitted — validateNewPassword must be wired, not validatePassword',
        );

        // The step did NOT advance.
        expect(
          find.text('step-2'),
          findsNothing,
          reason: 'A weak password must block navigation to step-2',
        );

        // No registration POST fired.
        _assertNoRegisterPostFired(repo);
      },
    );

    // -----------------------------------------------------------------------
    // 12. Strong password "Abcde123" passes the registration validator.
    //
    // Verifies that a password satisfying all three criteria (8+ chars,
    // ≥1 digit, ≥1 uppercase) is accepted and the step advances normally.
    // This is also a regression guard: if the strict validator is ever
    // accidentally made stricter than the advertised criteria this test fails.
    // -----------------------------------------------------------------------
    testWidgets(
      '12. strong password "Abcde123" passes the registration validator and '
      'advances to step-2 without a registration POST',
      (tester) async {
        final (:container, :repo) = _makeContainerWithRepo();
        addTearDown(container.dispose);
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field-email')),
          'anya@example.com',
        );
        await tester.enterText(
          find.byKey(const Key('field-password')),
          'Abcde123',
        );
        await tester.enterText(
          find.byKey(const Key('field-confirm-password')),
          'Abcde123',
        );

        await tester.ensureVisible(find.byKey(const Key('btn-submit-step-1')));
        await tester.tap(find.byKey(const Key('btn-submit-step-1')));
        await tester.pumpAndSettle();

        // Navigation occurred — the password was accepted.
        expect(
          find.text('step-2'),
          findsOneWidget,
          reason:
              '"Abcde123" meets all registration criteria; the step must advance',
        );

        // Draft holds the correct password value.
        final draft = container.read(registerDraftProvider);
        expect(draft?.password, equals('Abcde123'));

        // No registration POST fired (same as other Step 1 valid-submit tests).
        _assertNoRegisterPostFired(repo);
      },
    );
  });
}
