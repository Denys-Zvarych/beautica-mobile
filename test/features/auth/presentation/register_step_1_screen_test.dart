// Phase 2.16 — Widget tests for [RegisterStep1Screen] (VelvetTouch redesign).
//
// Step 1 is the credentials form ONLY — email + password + confirm-password.
// Fields are `NeumorphicTextField` instances (not TextFormField) keyed by
// ValueKey<String>.
//
// Covered scenarios:
//   1. The three inputs (email, password, confirm-password) render.
//   2. Invalid email shows errEmailInvalid after submit.
//   3. Empty password on submit shows errPasswordRequired.
//   4. Confirm-password mismatch shows errPasswordsMismatch after submit.
//   5. Valid submit writes the slice to the draft and navigates to /step-2.
//   6. Draft persists when stepping out and back in (initState pre-fills
//      controllers from the draft).
//   7. Step 1 does NOT call AuthNotifier.register (deferred to Step 3).
//   8. btn back (step1_back) PRESERVES the draft and navigates to /register/role.
//   9. Login link (step1_login_link) navigates to /login and resets draft.
//  10. step1_back navigates to /register/role (not /login).
//  11. Weak password "asd" shows errPasswordTooShort and does NOT advance.
//  12. Strong password "Abcde123" passes the validator and advances to step-2.

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
      // RegisterStep1Screen returns a Column (not a Scaffold) — it lives
      // inside RegisterFlowShell in production. The test substitutes a minimal
      // Scaffold with a scroll view so NeumorphicTextField can lay out.
      builder: (context, state) => const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(children: <Widget>[RegisterStep1Screen()]),
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
void _assertNoRegisterPostFired(FakeAuthRepository repo) {
  expect(
    repo.registerCalls,
    isEmpty,
    reason:
        'register_step_1_screen.dart must NOT call AuthNotifier.register — '
        'the real POST happens at the end of Step 3 (Phase 2.19)',
  );
}

/// Variant that returns the [FakeAuthRepository] handle alongside the container.
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
  group('RegisterStep1Screen (VelvetTouch credentials)', () {
    testWidgets('1. three inputs render: email, password, confirm-password', (
      tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('step1_email')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('step1_password')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('step1_confirm')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('step1_submit')),
        findsOneWidget,
      );

      // Step 1 must NOT render Step 2 / Step 3 fields.
      expect(find.byKey(const Key('field-firstName')), findsNothing);
      expect(find.byKey(const Key('field-lastName')), findsNothing);
      expect(find.byKey(const Key('field-phone')), findsNothing);
      expect(find.byKey(const Key('field-businessName')), findsNothing);
    });

    testWidgets('2. invalid email shows errEmailInvalid after submit', (
      tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      // Enter invalid email, leave password empty, tap submit.
      await tester.enterText(
        find.byKey(const ValueKey<String>('step1_email')),
        'not-an-email',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('step1_submit')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('step1_submit')));
      await tester.pump();

      final l10n = lookupAppLocalizations(const Locale('uk'));
      expect(find.text(l10n.errEmailInvalid), findsOneWidget);
    });

    testWidgets('3. empty password on submit shows errPasswordRequired', (
      tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('step1_email')),
        'a@b.com',
      );
      // Leave password blank.
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('step1_submit')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('step1_submit')));
      await tester.pump();

      final l10n = lookupAppLocalizations(const Locale('uk'));
      // The error is shown inline next to the password NeumorphicTextField.
      expect(find.text(l10n.errPasswordRequired), findsAtLeast(1));
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

      await tester.enterText(
        find.byKey(const ValueKey<String>('step1_email')),
        'a@b.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('step1_password')),
        'SecurePass1',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('step1_confirm')),
        'WRONG',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('step1_submit')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('step1_submit')));
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
          find.byKey(const ValueKey<String>('step1_email')),
          'anya@example.com',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step1_password')),
          'SecurePass1',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step1_confirm')),
          'SecurePass1',
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('step1_submit')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('step1_submit')));
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

      // All three TextField controllers must re-hydrate. We inspect the
      // TextField descendants of each NeumorphicTextField key.
      final emailField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('step1_email')),
          matching: find.byType(TextField),
        ),
      );
      expect(emailField.controller?.text, equals('pre-filled@example.com'));

      final passwordField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('step1_password')),
          matching: find.byType(TextField),
        ),
      );
      expect(passwordField.controller?.text, equals('PrePass1'));

      final confirmField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('step1_confirm')),
          matching: find.byType(TextField),
        ),
      );
      expect(confirmField.controller?.text, equals('PrePass1'));
    });

    testWidgets(
      '7. Step 1 does NOT call AuthNotifier.register on submit (deferred '
      'to Step 3 / Phase 2.19) — INDEPENDENT_MASTER role variant',
      (tester) async {
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

        await tester.enterText(
          find.byKey(const ValueKey<String>('step1_email')),
          'a@b.com',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step1_password')),
          'SecurePass1',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step1_confirm')),
          'SecurePass1',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('step1_submit')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('step1_submit')));
        await tester.pumpAndSettle();

        _assertNoRegisterPostFired(repo);
      },
    );

    testWidgets('8. tapping step1_back PRESERVES the draft (role survives) AND '
        'navigates to /register/role — the back link goes one wizard step back, '
        'so the role-selection screen can re-highlight the chosen role', (
      tester,
    ) async {
      final (:container, :repo) = _makeContainerWithRepo();
      addTearDown(container.dispose);
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      // Pre-seed credentials so we can verify the back link does NOT wipe them.
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

      // Scroll the back link into view and tap it.
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('step1_back')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('step1_back')));
      await tester.pumpAndSettle();

      // (1) Draft is PRESERVED — going one wizard step back must keep the
      // chosen role (and in-progress credentials).
      final afterTap = container.read(registerDraftProvider);
      expect(
        afterTap,
        isNotNull,
        reason:
            'Tapping the back link on Step 1 must NOT reset() the draft — '
            'the role must survive a single-step back.',
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
    });

    testWidgets(
      '9. step1_login_link navigates to /login and resets the draft',
      (tester) async {
        final (:container, :repo) = _makeContainerWithRepo();
        addTearDown(container.dispose);
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // Scroll to make the login link visible (it lives below the form).
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('step1_login_link')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('step1_login_link')),
        );
        await tester.pumpAndSettle();

        // (1) Navigated to /login.
        expect(
          router.routerDelegate.currentConfiguration.fullPath,
          equals(RouteNames.login),
          reason:
              'step1_login_link must navigate to RouteNames.login, '
              'not to registerRole or any other route',
        );
        expect(find.text('login'), findsOneWidget);

        // (2) Draft was reset.
        expect(
          container.read(registerDraftProvider),
          isNull,
          reason: 'step1_login_link must reset() the draft before navigating',
        );

        // (3) No registration POST was fired.
        _assertNoRegisterPostFired(repo);
      },
    );

    testWidgets('10. step1_back navigates to /register/role (not /login)', (
      tester,
    ) async {
      final (:container, :repo) = _makeContainerWithRepo();
      addTearDown(container.dispose);
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('step1_back')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('step1_back')));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.fullPath,
        equals(RouteNames.registerRole),
        reason: 'step1_back must navigate to registerRole, not to /login',
      );
      expect(find.text('role-selection'), findsOneWidget);

      _assertNoRegisterPostFired(repo);
    });

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
          find.byKey(const ValueKey<String>('step1_email')),
          'anya@example.com',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step1_password')),
          'asd',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step1_confirm')),
          'asd',
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('step1_submit')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('step1_submit')));
        await tester.pump();

        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(
          find.text(l10n.errPasswordTooShort),
          findsOneWidget,
          reason:
              'step1_password must show errPasswordTooShort when "asd" is '
              'submitted — password < 8 chars must be blocked',
        );

        // The step did NOT advance.
        expect(
          find.text('step-2'),
          findsNothing,
          reason: 'A weak password must block navigation to step-2',
        );

        _assertNoRegisterPostFired(repo);
      },
    );

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
          find.byKey(const ValueKey<String>('step1_email')),
          'anya@example.com',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step1_password')),
          'Abcde123',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('step1_confirm')),
          'Abcde123',
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('step1_submit')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('step1_submit')));
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

        _assertNoRegisterPostFired(repo);
      },
    );
  });
}
