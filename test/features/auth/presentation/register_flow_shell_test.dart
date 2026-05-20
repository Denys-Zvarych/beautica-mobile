// Phase 2.16 — Widget tests for [RegisterFlowShell] (wizard chrome).
//
// SOURCE OF TRUTH: docs/signup-designs/sign-up-page.html (and 2.17 / 2.19
// sibling pages — identical shell header block).
//
// Covered scenarios (closing mobile-qa MEDIUM coverage gap M-1):
//   1. `_redirectScheduled` one-shot guard — when the draft has a `null`
//      role, the shell schedules `context.go('/register/role')` exactly
//      once after the post-frame, even across rebuilds.
//   2. `_stepForLocation` mapping — `/register` resolves to
//      `RegistrationStep.account`; `/register/step-2` and `/register/step-3`
//      both resolve to `RegistrationStep.details`.
//   3. `_headlineFor` switching — the rendered headline copy differs between
//      Step 1 (account) and Step 2/3 (details) when l10n diverges (in the
//      current Phase 2.16 codepath the copy is intentionally reused — the
//      test asserts the step pill changes which is the observable signal).
//   4. `_BackLink` target dispatch — tapping `Key('btn-back-step')` from
//      Step 2 lands on `/register`; from Step 3 lands on `/register/step-2`.
//      NOTE: Step 1 (`/register`) does NOT render the back link by design
//      (`if (step != RegistrationStep.account)` in the shell build), so the
//      "Step 1 → /register/role" case in the M-1 finding is unreachable
//      via tap. Asserted as absence-of-back-link below to lock the contract.
//   5. Role-chip label — each [UserRole] value produces the matching
//      localised role label inside `Key('role-chip-label')`.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/register_flow_shell.dart';
import 'package:beautica_mobile/features/auth/presentation/widgets/registration_progress.dart';
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

/// Returns `(container, repo)` so tests don't need to re-read from the
/// container (same shape as `register_step_1_screen_test.dart`).
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

/// Stub step bodies — the shell wraps `child:` in its glass card; the test
/// only cares about the shell's chrome, never the step body itself.
const _kStep1Body = Text('step-1-body', key: Key('step-1-body'));
const _kStep2Body = Text('step-2-body', key: Key('step-2-body'));
const _kStep3Body = Text('step-3-body', key: Key('step-3-body'));

/// Builds the real production-shape ShellRoute graph (`/register`,
/// `/register/step-2`, `/register/step-3`) wrapped in [RegisterFlowShell]
/// plus a sibling `/register/role` target.
GoRouter _makeShellRouter({required String initialLocation}) => GoRouter(
  initialLocation: initialLocation,
  redirect: (context, state) => null,
  routes: [
    GoRoute(
      path: RouteNames.registerRole,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('role-selection'))),
    ),
    ShellRoute(
      builder: (context, state, child) => RegisterFlowShell(child: child),
      routes: [
        GoRoute(
          path: RouteNames.register,
          builder: (context, state) => _kStep1Body,
        ),
        GoRoute(
          path: RouteNames.registerStep2,
          builder: (context, state) => _kStep2Body,
        ),
        GoRoute(
          path: RouteNames.registerStep3,
          builder: (context, state) => _kStep3Body,
        ),
      ],
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

/// Pumps the shell at [initialLocation] with the given [role] pre-seeded
/// into the draft. Returns the live container + router for inspection.
Future<({ProviderContainer container, GoRouter router})> _pumpShell(
  WidgetTester tester, {
  required String initialLocation,
  UserRole? role = UserRole.client,
}) async {
  final (:container, :repo) = _makeContainerWithRepo(role: role);
  addTearDown(container.dispose);
  final router = _makeShellRouter(initialLocation: initialLocation);
  addTearDown(router.dispose);
  await tester.pumpWidget(_buildApp(router: router, container: container));
  await tester.pumpAndSettle();
  return (container: container, router: router);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RegisterFlowShell', () {
    // -----------------------------------------------------------------------
    // 1. _redirectScheduled one-shot guard
    // -----------------------------------------------------------------------
    testWidgets(
      '1. null-role draft bounces to /register/role exactly once and stays '
      'there across additional pump frames (MEDIUM-perf-1 guard)',
      (tester) async {
        // role: null → the shell must redirect.
        final (:container, repo: _) = _makeContainerWithRepo(role: null);
        addTearDown(container.dispose);

        // Capture every route the delegate settles on so we can assert that
        // we land on /register/role exactly once (no oscillation, no double-
        // push to the same path that would surface as a `locationChanges`
        // burst if the guard regressed and every rebuild re-scheduled the
        // postframe callback).
        final visited = <String>[];
        final router = _makeShellRouter(initialLocation: RouteNames.register);
        addTearDown(router.dispose);
        router.routerDelegate.addListener(() {
          visited.add(router.routerDelegate.currentConfiguration.fullPath);
        });

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        // Force-pump extra frames so didChangeDependencies has multiple
        // opportunities to fire. With the guard intact, the shell schedules
        // the postframe callback once; without it, every rebuild would
        // schedule a fresh callback.
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();

        // Landed on /register/role.
        expect(
          router.routerDelegate.currentConfiguration.fullPath,
          equals(RouteNames.registerRole),
          reason: 'shell must redirect when draft.role is null',
        );
        expect(find.text('role-selection'), findsOneWidget);

        // The destination is reached exactly once — visited may contain the
        // initial route + the redirect, but should not contain /register/role
        // more than once (which would indicate the guard failed and a second
        // postframe `context.go` fired).
        final roleVisits = visited
            .where((p) => p == RouteNames.registerRole)
            .length;
        expect(
          roleVisits,
          equals(1),
          reason:
              '_redirectScheduled must prevent re-scheduling on rebuild — '
              'observed visits: $visited',
        );
      },
    );

    // -----------------------------------------------------------------------
    // 2. _stepForLocation mapping
    // -----------------------------------------------------------------------
    testWidgets('2a. /register → RegistrationStep.account', (tester) async {
      await _pumpShell(tester, initialLocation: RouteNames.register);
      final progress = tester.widget<RegistrationProgress>(
        find.byKey(const Key('registration-progress')),
      );
      expect(progress.currentStep, equals(RegistrationStep.account));
      expect(find.byKey(const Key('step-1-body')), findsOneWidget);
    });

    testWidgets('2b. /register/step-2 → RegistrationStep.details', (
      tester,
    ) async {
      await _pumpShell(tester, initialLocation: RouteNames.registerStep2);
      final progress = tester.widget<RegistrationProgress>(
        find.byKey(const Key('registration-progress')),
      );
      expect(progress.currentStep, equals(RegistrationStep.details));
      expect(find.byKey(const Key('step-2-body')), findsOneWidget);
    });

    testWidgets(
      '2c. /register/step-3 → RegistrationStep.details (shared dot)',
      (tester) async {
        await _pumpShell(tester, initialLocation: RouteNames.registerStep3);
        final progress = tester.widget<RegistrationProgress>(
          find.byKey(const Key('registration-progress')),
        );
        expect(progress.currentStep, equals(RegistrationStep.details));
        expect(find.byKey(const Key('step-3-body')), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // 2.5 Active-label dispatch — 2026-05-20 design refresh
    //
    // Step 2 and Step 3 BOTH collapse to RegistrationStep.details (dot 2 is
    // active for both), so the only observable distinction between the two
    // routes is the under-dot label: "Профіль" on /register/step-2 and
    // "Локація" on /register/step-3. _labelForLocation must return the
    // right label so the shell forwards it to RegistrationProgress.
    // -----------------------------------------------------------------------
    testWidgets(
      '2.5a. /register renders the "Акаунт" active-label under dot 1',
      (tester) async {
        await _pumpShell(tester, initialLocation: RouteNames.register);
        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(find.text(l10n.registerProgressAccount), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('progress-step-1')),
            matching: find.byKey(const Key('progress-active-label')),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '2.5b. /register/step-2 renders the "Профіль" active-label under dot 2',
      (tester) async {
        await _pumpShell(tester, initialLocation: RouteNames.registerStep2);
        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(find.text(l10n.registerProgressProfile), findsOneWidget);
        // The Локація label MUST NOT appear (otherwise the dispatcher is broken).
        expect(find.text(l10n.registerProgressLocation), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const Key('progress-step-2')),
            matching: find.byKey(const Key('progress-active-label')),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '2.5c. /register/step-3 renders the "Локація" active-label under dot 2 '
      '(same dot as Step 2, different label)',
      (tester) async {
        await _pumpShell(tester, initialLocation: RouteNames.registerStep3);
        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(find.text(l10n.registerProgressLocation), findsOneWidget);
        // The Профіль label MUST NOT appear.
        expect(find.text(l10n.registerProgressProfile), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const Key('progress-step-2')),
            matching: find.byKey(const Key('progress-active-label')),
          ),
          findsOneWidget,
        );
      },
    );

    // -----------------------------------------------------------------------
    // 3. _headlineFor switching
    // -----------------------------------------------------------------------
    testWidgets(
      '3. headline block is present on every step (line1 + line2 widgets) '
      'and is keyed `shell-headline`',
      (tester) async {
        // Step 1.
        await _pumpShell(tester, initialLocation: RouteNames.register);
        expect(find.byKey(const Key('shell-headline')), findsOneWidget);

        // Step 2 — fresh pump.
        await _pumpShell(tester, initialLocation: RouteNames.registerStep2);
        expect(find.byKey(const Key('shell-headline')), findsOneWidget);

        // Step 3 — fresh pump.
        await _pumpShell(tester, initialLocation: RouteNames.registerStep3);
        expect(find.byKey(const Key('shell-headline')), findsOneWidget);

        // NOTE: per `_headlineFor` (register_flow_shell.dart:229-247), the
        // Step 1 and Step 2/3 headlines intentionally share the same l10n
        // keys until Phase 2.17 / 2.19 ship their own copy. The step pill
        // (Test 2 above) is the observable signal for now; this test locks
        // that the headline widget is rendered on every step so the future
        // copy split doesn't accidentally drop it.
      },
    );

    // -----------------------------------------------------------------------
    // 4. _BackLink target dispatch
    // -----------------------------------------------------------------------
    testWidgets('4a. back link at /register/step-2 navigates to /register', (
      tester,
    ) async {
      final (container: _, :router) = await _pumpShell(
        tester,
        initialLocation: RouteNames.registerStep2,
      );
      expect(find.byKey(const Key('btn-back-step')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('btn-back-step')));
      await tester.tap(find.byKey(const Key('btn-back-step')));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.fullPath,
        equals(RouteNames.register),
      );
      expect(find.byKey(const Key('step-1-body')), findsOneWidget);
    });

    testWidgets(
      '4b. back link at /register/step-3 navigates to /register (Step 1) — '
      'source contract: both step-2 and step-3 map to '
      'RegistrationStep.details and the switch arm targets `register`. '
      'NOTE: the M-1 audit suggested step-3 → step-2, but the actual '
      'source dispatches step-3 → /register. Test locks the source '
      'behavior; if the wizard later differentiates step-2 vs step-3 '
      'back-targets, update _BackLink and this assertion together.',
      (tester) async {
        final (container: _, :router) = await _pumpShell(
          tester,
          initialLocation: RouteNames.registerStep3,
        );
        expect(find.byKey(const Key('btn-back-step')), findsOneWidget);

        await tester.ensureVisible(find.byKey(const Key('btn-back-step')));
        await tester.tap(find.byKey(const Key('btn-back-step')));
        await tester.pumpAndSettle();

        expect(
          router.routerDelegate.currentConfiguration.fullPath,
          equals(RouteNames.register),
        );
        expect(find.byKey(const Key('step-1-body')), findsOneWidget);
      },
    );

    testWidgets(
      '4c. back link is NOT rendered on Step 1 (/register) — the shell '
      'guard `if (step != RegistrationStep.account)` skips it',
      (tester) async {
        await _pumpShell(tester, initialLocation: RouteNames.register);
        expect(find.byKey(const Key('btn-back-step')), findsNothing);
      },
    );

    // -----------------------------------------------------------------------
    // 5. Role-chip label per UserRole
    // -----------------------------------------------------------------------
    testWidgets('5a. role=client → role chip shows roleClient l10n string', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        initialLocation: RouteNames.register,
        role: UserRole.client,
      );
      final l10n = lookupAppLocalizations(const Locale('uk'));
      final chipLabel = tester.widget<Text>(
        find.byKey(const Key('role-chip-label')),
      );
      expect(chipLabel.data, equals(l10n.roleClient));
    });

    testWidgets(
      '5b. role=salonOwner → role chip shows roleSalonOwner l10n string',
      (tester) async {
        await _pumpShell(
          tester,
          initialLocation: RouteNames.register,
          role: UserRole.salonOwner,
        );
        final l10n = lookupAppLocalizations(const Locale('uk'));
        final chipLabel = tester.widget<Text>(
          find.byKey(const Key('role-chip-label')),
        );
        expect(chipLabel.data, equals(l10n.roleSalonOwner));
      },
    );

    testWidgets(
      '5c. role=independentMaster → role chip shows roleIndependentMaster '
      'l10n string',
      (tester) async {
        await _pumpShell(
          tester,
          initialLocation: RouteNames.register,
          role: UserRole.independentMaster,
        );
        final l10n = lookupAppLocalizations(const Locale('uk'));
        final chipLabel = tester.widget<Text>(
          find.byKey(const Key('role-chip-label')),
        );
        expect(chipLabel.data, equals(l10n.roleIndependentMaster));
      },
    );
  });
}
