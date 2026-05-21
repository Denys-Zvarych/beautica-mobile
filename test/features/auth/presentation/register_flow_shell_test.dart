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
import 'package:beautica_mobile/features/auth/presentation/register_step_1_screen.dart';
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
/// plus sibling `/register/role` and `/login` targets.
///
/// The `/login` route is included so the navigation-race regression tests
/// (tests R1 and R2) can verify that btn-go-to-login truly lands on `/login`
/// and not on `/register/role`.
GoRouter _makeShellRouter({required String initialLocation}) => GoRouter(
  initialLocation: initialLocation,
  redirect: (context, state) => null,
  routes: [
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('login'))),
    ),
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
    // 4d. _BackLink renders Icons.west (not a '← ' Unicode glyph)
    //
    // The Manrope UI font has no glyph for U+2190 (←), so the old
    // Text('← $label') rendered blank. The fix replaces it with an
    // Icon(Icons.west) + Text Row — this test locks that contract.
    // -----------------------------------------------------------------------
    testWidgets(
      '4d. back link at /register/step-2 renders Icon(Icons.west) and NOT '
      'a raw "← " text prefix (fix for blank arrow on Manrope)',
      (tester) async {
        await _pumpShell(tester, initialLocation: RouteNames.registerStep2);

        // The back-link button must exist.
        expect(find.byKey(const Key('btn-back-step')), findsOneWidget);

        // Must contain exactly one Icons.west icon widget.
        expect(
          find.descendant(
            of: find.byKey(const Key('btn-back-step')),
            matching: find.byWidgetPredicate(
              (w) => w is Icon && w.icon == Icons.west,
            ),
          ),
          findsOneWidget,
          reason:
              '_BackLink must use Icon(Icons.west) — not a Unicode "←" glyph',
        );

        // Must NOT contain any Text widget whose content starts with '← '
        // (the broken old pattern).
        final textsInButton = find.descendant(
          of: find.byKey(const Key('btn-back-step')),
          matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data?.startsWith('← ') ?? false),
          ),
        );
        expect(
          textsInButton,
          findsNothing,
          reason:
              '_BackLink must not embed the "← " Unicode prefix in Text — '
              'it rendered blank because Manrope has no U+2190 glyph',
        );
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

    // -----------------------------------------------------------------------
    // R1. Navigation-race regression — "Вже є акаунт? Увійти" link exits to
    //     /login (the bug).
    //
    // Root cause (confirmed by mobile-debugger): the old tap handler called
    // reset() BEFORE context.go('/login'). reset() nulled the draft role;
    // the still-mounted RegisterFlowShell's didChangeDependencies re-fired
    // with role == null and scheduled a post-frame context.go('/register/role')
    // that won the race against the intended '/login' navigation.
    //
    // Both fix parts are exercised here:
    //   Part 1 — tap handler now calls context.go('/login') FIRST, then
    //             reset() (register_step_1_screen.dart).
    //   Part 2 — shell's didChangeDependencies only bounces when
    //             matchedLocation is still a wizard route (register_flow_shell
    //             .dart). After go('/login') the matchedLocation is '/login',
    //             so the bounce is skipped even if reset() fires while the
    //             shell is technically still in the tree for one more frame.
    //
    // This test uses the production router shape — ShellRoute + RegisterFlow
    // Shell wrapping the real RegisterStep1Screen — so both guard layers are
    // exercised, not just the tap-handler reorder.
    // -----------------------------------------------------------------------
    testWidgets(
      'R1. btn-go-to-login inside RegisterFlowShell navigates to /login, '
      'NOT to /register/role (navigation-race regression)',
      (tester) async {
        // Build a router that puts the REAL RegisterStep1Screen inside the
        // REAL RegisterFlowShell shell, plus /login and /register/role
        // siblings so we can assert the final destination.
        final (:container, repo: _) = _makeContainerWithRepo(
          role: UserRole.client,
        );
        addTearDown(container.dispose);

        final router = GoRouter(
          initialLocation: RouteNames.register,
          redirect: (context, state) => null,
          routes: [
            GoRoute(
              path: RouteNames.login,
              builder: (context, state) =>
                  const Scaffold(body: Center(child: Text('login'))),
            ),
            GoRoute(
              path: RouteNames.registerRole,
              builder: (context, state) =>
                  const Scaffold(body: Center(child: Text('role-selection'))),
            ),
            ShellRoute(
              builder: (context, state, child) =>
                  RegisterFlowShell(child: child),
              routes: [
                GoRoute(
                  path: RouteNames.register,
                  // The real screen — passed bare, exactly as in production.
                  // RegisterFlowShell (via AuthScaffold) owns the outer
                  // Scaffold + SingleChildScrollView; the step body is the
                  // bare widget placed inside the glass card. Wrapping with
                  // an extra Scaffold would nest a Scaffold inside a scroll
                  // viewport and trigger unbounded-height layout errors.
                  builder: (context, state) => const RegisterStep1Screen(),
                ),
                GoRoute(
                  path: RouteNames.registerStep2,
                  builder: (context, state) =>
                      const Center(child: Text('step-2')),
                ),
                GoRoute(
                  path: RouteNames.registerStep3,
                  builder: (context, state) =>
                      const Center(child: Text('step-3')),
                ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);

        // Collect every location the router settles on so we can assert the
        // wizard NEVER bounced to /register/role at any point after the tap.
        final visited = <String>[];
        router.routerDelegate.addListener(() {
          visited.add(router.routerDelegate.currentConfiguration.fullPath);
        });

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // Scroll the login link into view (it lives below the form fields
        // and may be below the default 800×600 test viewport fold).
        await tester.ensureVisible(find.byKey(const Key('btn-go-to-login')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn-go-to-login')));
        // pumpAndSettle drains all post-frame callbacks including any that
        // the shell's null-role guard might have (incorrectly) scheduled.
        await tester.pumpAndSettle();

        // (1) Final location is /login.
        expect(
          router.routerDelegate.currentConfiguration.fullPath,
          equals(RouteNames.login),
          reason:
              'btn-go-to-login must navigate to RouteNames.login — '
              'NOT to /register/role (navigation-race bug)',
        );
        expect(find.text('login'), findsOneWidget);

        // (2) The router NEVER settled on /register/role after the tap.
        final roleVisitsAfterTap = visited
            .skipWhile((p) => p != RouteNames.register)
            .where((p) => p == RouteNames.registerRole)
            .length;
        expect(
          roleVisitsAfterTap,
          equals(0),
          reason:
              'The shell null-role guard must NOT bounce to /register/role '
              'when the user intentionally navigated to /login — '
              'visited locations after /register: '
              '${visited.skipWhile((p) => p != RouteNames.register).toList()}',
        );

        // (3) Draft was reset.
        expect(
          container.read(registerDraftProvider),
          isNull,
          reason: 'The draft must be wiped when the user leaves the wizard',
        );
      },
    );

    // -----------------------------------------------------------------------
    // R2. Deep-link guard preserved — null-role draft at /register still
    //     bounces to /register/role.
    //
    // Verifies that the `stillInWizard` guard in didChangeDependencies does
    // NOT break the legitimate deep-link protection: when the draft has no
    // role AND the current location is a wizard route, the shell must still
    // redirect to role-selection.
    //
    // This test uses the STUB body router (not the real screen) because the
    // deep-link bounce fires from the shell's chrome layer, not the step body.
    // -----------------------------------------------------------------------
    testWidgets(
      'R2. null-role draft at /register still bounces to /register/role '
      '(deep-link guard preserved after stillInWizard fix)',
      (tester) async {
        // role: null → no draft role set → shell must redirect.
        final (:container, repo: _) = _makeContainerWithRepo(role: null);
        addTearDown(container.dispose);

        final router = _makeShellRouter(initialLocation: RouteNames.register);
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // The shell must have redirected to /register/role.
        expect(
          router.routerDelegate.currentConfiguration.fullPath,
          equals(RouteNames.registerRole),
          reason:
              'The deep-link guard must still fire when role is null AND '
              'the initial location is /register (a wizard route)',
        );
        expect(find.text('role-selection'), findsOneWidget);
      },
    );
  });
}
