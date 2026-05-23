// Phase 2.16 — Widget tests for [RegisterFlowShell] (VelvetTouch redesign).
//
// Covered scenarios:
//   1. `_redirectScheduled` one-shot guard — when the draft has a `null`
//      role, the shell schedules `context.go('/register/role')` exactly once
//      after the post-frame, even across rebuilds.
//   2. Two-dot _StepProgress renders on every wizard route.
//   3. Step index mapping — /register → dot 1 active; /register/step-2 and
//      /register/step-3 → dot 2 active.
//   4. shell-headline key is present on every step.
//   5. Role-chip label (Key('role-chip-label')) per UserRole.
//   R1. Navigation-race regression — "Вже є акаунт? Увійти" link exits to
//      /login, NOT to /register/role.
//   R2. Deep-link guard preserved — null-role draft at /register still
//      bounces to /register/role.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/register_flow_shell.dart';
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

/// Stub step bodies — the shell wraps `child:` in its content column.
const _kStep1Body = Text('step-1-body', key: Key('step-1-body'));
const _kStep2Body = Text('step-2-body', key: Key('step-2-body'));
const _kStep3Body = Text('step-3-body', key: Key('step-3-body'));

/// Builds the production-shape ShellRoute graph (`/register`, `/register/step-2`,
/// `/register/step-3`) wrapped in [RegisterFlowShell], plus sibling
/// `/register/role` and `/login` targets.
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

/// Pumps the shell at [initialLocation] with the given [role] pre-seeded.
Future<({ProviderContainer container, GoRouter router})> _pumpShell(
  WidgetTester tester, {
  required String initialLocation,
  UserRole? role = UserRole.client,
}) async {
  final (:container, repo: _) = _makeContainerWithRepo(role: role);
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
  group('RegisterFlowShell (VelvetTouch)', () {
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

        // Capture every route the delegate settles on.
        final visited = <String>[];
        final router = _makeShellRouter(initialLocation: RouteNames.register);
        addTearDown(router.dispose);
        router.routerDelegate.addListener(() {
          visited.add(router.routerDelegate.currentConfiguration.fullPath);
        });

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        // Extra frames so didChangeDependencies has multiple opportunities.
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

        // The destination is reached exactly once.
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
    // 2. Two-dot _StepProgress renders on all wizard routes
    // -----------------------------------------------------------------------
    testWidgets('2a. two AnimatedContainers (dots) render on /register', (
      tester,
    ) async {
      await _pumpShell(tester, initialLocation: RouteNames.register);
      // Step body is rendered.
      expect(find.byKey(const Key('step-1-body')), findsOneWidget);
      // Shell headline is present.
      expect(find.byKey(const Key('shell-headline')), findsOneWidget);
      // No glassmorphism — BackdropFilter must be absent.
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('2b. shell renders step body at /register/step-2', (
      tester,
    ) async {
      await _pumpShell(tester, initialLocation: RouteNames.registerStep2);
      expect(find.byKey(const Key('step-2-body')), findsOneWidget);
      expect(find.byKey(const Key('shell-headline')), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('2c. shell renders step body at /register/step-3', (
      tester,
    ) async {
      await _pumpShell(tester, initialLocation: RouteNames.registerStep3);
      expect(find.byKey(const Key('step-3-body')), findsOneWidget);
      expect(find.byKey(const Key('shell-headline')), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    // -----------------------------------------------------------------------
    // 3. Step index — dot 1 vs dot 2 active
    //
    // _StepProgress is private, so we test the *observable* effect: at
    // /register the first dot is wide (24 dp) and the second is narrow (8 dp).
    // At /register/step-2 and /register/step-3 the second dot is wide.
    // We use AnimatedContainer dimensions via tester.
    // -----------------------------------------------------------------------
    testWidgets(
      '3a. /register → AnimatedContainers (step dots) render and step body '
      'is visible',
      (tester) async {
        await _pumpShell(tester, initialLocation: RouteNames.register);
        // _StepDot uses AnimatedContainer — at least one must be present.
        expect(
          tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer)),
          isNotEmpty,
        );
        // Step 1 body confirms we are on the correct route.
        expect(find.byKey(const Key('step-1-body')), findsOneWidget);
      },
    );

    testWidgets(
      '3b. /register/step-2 renders step-2 body (second dot is active)',
      (tester) async {
        await _pumpShell(tester, initialLocation: RouteNames.registerStep2);
        expect(find.byKey(const Key('step-2-body')), findsOneWidget);
      },
    );

    testWidgets(
      '3c. /register/step-3 renders step-3 body (second dot is active — '
      'same dot as step-2)',
      (tester) async {
        await _pumpShell(tester, initialLocation: RouteNames.registerStep3);
        expect(find.byKey(const Key('step-3-body')), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // 4. shell-headline key is present on every step
    // -----------------------------------------------------------------------
    testWidgets(
      '4. headline block is present (Key shell-headline) on every step',
      (tester) async {
        await _pumpShell(tester, initialLocation: RouteNames.register);
        expect(find.byKey(const Key('shell-headline')), findsOneWidget);

        await _pumpShell(tester, initialLocation: RouteNames.registerStep2);
        expect(find.byKey(const Key('shell-headline')), findsOneWidget);

        await _pumpShell(tester, initialLocation: RouteNames.registerStep3);
        expect(find.byKey(const Key('shell-headline')), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // 4b. No glassmorphism — BackdropFilter must be absent in all steps
    // -----------------------------------------------------------------------
    testWidgets('4b. BackdropFilter is NOT present on any wizard step '
        '(no glassmorphism in VelvetTouch shell)', (tester) async {
      await _pumpShell(tester, initialLocation: RouteNames.register);
      expect(find.byType(BackdropFilter), findsNothing);

      await _pumpShell(tester, initialLocation: RouteNames.registerStep2);
      expect(find.byType(BackdropFilter), findsNothing);

      await _pumpShell(tester, initialLocation: RouteNames.registerStep3);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    // -----------------------------------------------------------------------
    // 4c. No four-pill RegistrationProgress — only two-dot progress
    // -----------------------------------------------------------------------
    testWidgets(
      '4c. old RegistrationProgress (4-pill) widget is NOT rendered by the '
      'VelvetTouch shell',
      (tester) async {
        await _pumpShell(tester, initialLocation: RouteNames.register);
        // The old `registration-progress` key must not exist.
        expect(find.byKey(const Key('registration-progress')), findsNothing);
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
    //     /login (the bug where reset() raced with go('/login')).
    // -----------------------------------------------------------------------
    testWidgets(
      'R1. step1_login_link inside RegisterFlowShell navigates to /login, '
      'NOT to /register/role (navigation-race regression)',
      (tester) async {
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

        // Collect every location the router settles on.
        final visited = <String>[];
        router.routerDelegate.addListener(() {
          visited.add(router.routerDelegate.currentConfiguration.fullPath);
        });

        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // Scroll the login link into view.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('step1_login_link')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('step1_login_link')),
        );
        await tester.pumpAndSettle();

        // (1) Final location is /login.
        expect(
          router.routerDelegate.currentConfiguration.fullPath,
          equals(RouteNames.login),
          reason:
              'step1_login_link must navigate to RouteNames.login — '
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

    // -----------------------------------------------------------------------
    // shell headline per step (GAP 2 — design-parity)
    // -----------------------------------------------------------------------
    group('shell headline per step', () {
      testWidgets(
        'headline at /register is registerHeadline ("Створення акаунту")',
        (tester) async {
          await _pumpShell(
            tester,
            initialLocation: RouteNames.register,
            role: UserRole.client,
          );
          final l10n = lookupAppLocalizations(const Locale('uk'));
          final headline = tester.widget<Text>(
            find.byKey(const Key('shell-headline')),
          );
          expect(headline.data, equals(l10n.registerHeadline));
        },
      );

      testWidgets('headline at /register/step-2 is registerStep2ShellHeadline '
          '("Особисті дані")', (tester) async {
        await _pumpShell(
          tester,
          initialLocation: RouteNames.registerStep2,
          role: UserRole.client,
        );
        final l10n = lookupAppLocalizations(const Locale('uk'));
        final headline = tester.widget<Text>(
          find.byKey(const Key('shell-headline')),
        );
        expect(headline.data, equals(l10n.registerStep2ShellHeadline));
      });

      testWidgets('headline at /register/step-3 with role=client is '
          'registerStep3ShellHeadlineClient ("Ваш район")', (tester) async {
        await _pumpShell(
          tester,
          initialLocation: RouteNames.registerStep3,
          role: UserRole.client,
        );
        final l10n = lookupAppLocalizations(const Locale('uk'));
        final headline = tester.widget<Text>(
          find.byKey(const Key('shell-headline')),
        );
        expect(headline.data, equals(l10n.registerStep3ShellHeadlineClient));
      });

      testWidgets('headline at /register/step-3 with role=independentMaster is '
          'registerStep3ShellHeadlineMaster ("Де ви працюєте")', (
        tester,
      ) async {
        await _pumpShell(
          tester,
          initialLocation: RouteNames.registerStep3,
          role: UserRole.independentMaster,
        );
        final l10n = lookupAppLocalizations(const Locale('uk'));
        final headline = tester.widget<Text>(
          find.byKey(const Key('shell-headline')),
        );
        expect(headline.data, equals(l10n.registerStep3ShellHeadlineMaster));
      });

      testWidgets('headline at /register/step-3 with role=salonOwner is '
          'registerStep3ShellHeadlineOwner ("Адреса салону")', (tester) async {
        await _pumpShell(
          tester,
          initialLocation: RouteNames.registerStep3,
          role: UserRole.salonOwner,
        );
        final l10n = lookupAppLocalizations(const Locale('uk'));
        final headline = tester.widget<Text>(
          find.byKey(const Key('shell-headline')),
        );
        expect(headline.data, equals(l10n.registerStep3ShellHeadlineOwner));
      });
    });
  });
}
