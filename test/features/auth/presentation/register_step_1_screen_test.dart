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
  });
}
