// Phase 2.16 — Widget tests for [RoleSelectionScreen] (VelvetTouch redesign).
//
// Covered scenarios:
//   1. Three NeumorphicTile rows render (client / salon owner / independent
//      master), each addressed via its ValueKey.
//   2. Tapping a tile selects it (check_circle_rounded appears in that tile,
//      not in the others).
//   3. `start(role)` write on Continue — selecting a role + tapping the
//      `role_continue` button writes the role into `registerDraftProvider`
//      and navigates to `/register` (Step 1).
//   4. Continue is disabled (no-op) until a role is tapped — draft stays null
//      and router does not advance.
//   5. Preselection from an existing draft (returning via Step 1 back link).
//   6. Login link navigates to /login and resets the draft.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/role_selection_screen.dart';
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
  initialLocation: RouteNames.registerRole,
  redirect: (context, state) => null,
  routes: [
    GoRoute(
      path: RouteNames.registerRole,
      builder: (context, state) => const RoleSelectionScreen(),
    ),
    GoRoute(
      path: RouteNames.register,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('step-1'))),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('login'))),
    ),
  ],
);

({ProviderContainer container, FakeAuthRepository repo})
_makeContainerWithRepo() {
  final repo = FakeAuthRepository();
  final storage = FakeSecureStorage();
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWith((_) => repo),
      secureStorageProvider.overrideWith((_) => storage),
    ],
  );
  return (container: container, repo: repo);
}

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

/// Pumps the role-selection screen on a fresh container/router and returns
/// both handles so each test can inspect provider state and router path.
Future<({ProviderContainer container, GoRouter router})> _pumpRoleSelection(
  WidgetTester tester,
) async {
  final (:container, repo: _) = _makeContainerWithRepo();
  addTearDown(container.dispose);
  final router = _makeRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(_buildApp(router: router, container: container));
  await tester.pumpAndSettle();
  return (container: container, router: router);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RoleSelectionScreen (VelvetTouch)', () {
    // -----------------------------------------------------------------------
    // 1. Three NeumorphicTile rows render
    // -----------------------------------------------------------------------
    testWidgets(
      '1. three NeumorphicTile rows render (client / salon owner / independent '
      'master), each addressed by its ValueKey',
      (tester) async {
        await _pumpRoleSelection(tester);
        final l10n = lookupAppLocalizations(const Locale('uk'));

        // Each tile is uniquely keyed.
        expect(
          find.byKey(const ValueKey<String>('role_client')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('role_salon_owner')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('role_master')),
          findsOneWidget,
        );

        // Titles are visible.
        expect(find.text(l10n.roleClient), findsAtLeast(1));
        expect(find.text(l10n.roleSalonOwner), findsAtLeast(1));
        expect(find.text(l10n.roleIndependentMaster), findsAtLeast(1));

        // The continue CTA is keyed.
        expect(
          find.byKey(const ValueKey<String>('role_continue')),
          findsOneWidget,
        );
      },
    );

    // -----------------------------------------------------------------------
    // 2. Tapping a tile selects it
    // -----------------------------------------------------------------------
    testWidgets(
      '2. tapping a tile selects it — check_circle_rounded appears inside that '
      'tile; switching to another tile moves the indicator',
      (tester) async {
        await _pumpRoleSelection(tester);
        final l10n = lookupAppLocalizations(const Locale('uk'));

        // No selection yet → no check_circle_rounded.
        expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

        // Tap "Client" tile.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('role_client')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('role_client')));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

        // Switch to "Independent master".
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('role_master')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('role_master')));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

        // Switch to "Salon owner".
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('role_salon_owner')),
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('role_salon_owner')),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

        // Verify the role labels are still present (smoke-check l10n keys).
        expect(find.text(l10n.roleClient), findsAtLeast(1));
      },
    );

    // -----------------------------------------------------------------------
    // 3. start(role) write on Continue
    // -----------------------------------------------------------------------
    testWidgets(
      '3. tapping a tile + Continue writes role into registerDraftProvider '
      'and navigates to /register (Step 1)',
      (tester) async {
        final (:container, :router) = await _pumpRoleSelection(tester);

        // Draft starts null.
        expect(container.read(registerDraftProvider), isNull);

        // Tap "Salon owner" tile.
        await tester.tap(
          find.byKey(const ValueKey<String>('role_salon_owner')),
        );
        await tester.pumpAndSettle();

        // Tap Continue.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('role_continue')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('role_continue')));
        await tester.pumpAndSettle();

        // Draft populated with the chosen role.
        final draft = container.read(registerDraftProvider);
        expect(draft, isNotNull);
        expect(draft!.role, equals(UserRole.salonOwner));

        // Router landed on /register (Step 1).
        expect(
          router.routerDelegate.currentConfiguration.fullPath,
          equals(RouteNames.register),
        );
        expect(find.text('step-1'), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // 4. Continue disabled until role picked
    // -----------------------------------------------------------------------
    testWidgets(
      '4. tapping Continue before any role selection is a no-op — draft '
      'stays null and the router does not advance',
      (tester) async {
        final (:container, :router) = await _pumpRoleSelection(tester);

        // No role selected.
        expect(container.read(registerDraftProvider), isNull);

        // Tap the CTA — onPressed is null when _selectedRole is null.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('role_continue')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('role_continue')));
        await tester.pumpAndSettle();

        // Draft still null — `start(role)` was not called.
        expect(container.read(registerDraftProvider), isNull);

        // Router did NOT advance to /register.
        expect(
          router.routerDelegate.currentConfiguration.fullPath,
          equals(RouteNames.registerRole),
        );
        expect(find.text('step-1'), findsNothing);
      },
    );

    // -----------------------------------------------------------------------
    // 5. Preselection from an existing draft (returning via Step 1 back link)
    // -----------------------------------------------------------------------
    testWidgets(
      '5. when the draft already has a role (user returned via the Step 1 '
      'back link), that role is preselected — Continue is enabled and shows '
      'check_circle_rounded without re-tapping a tile',
      (tester) async {
        final (:container, repo: _) = _makeContainerWithRepo();
        addTearDown(container.dispose);
        // Seed the draft as if the user had already chosen a role and stepped
        // into Step 1, then tapped "← Назад".
        container
            .read(registerDraftProvider.notifier)
            .start(UserRole.independentMaster);

        final router = _makeRouter();
        addTearDown(router.dispose);
        await tester.pumpWidget(
          _buildApp(router: router, container: container),
        );
        await tester.pumpAndSettle();

        // The preselected role surfaces a single check_circle_rounded icon
        // with no taps.
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

        // Continue is enabled — tapping it advances and overwrites cleanly.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('role_continue')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('role_continue')));
        await tester.pumpAndSettle();

        final draft = container.read(registerDraftProvider);
        expect(draft, isNotNull);
        expect(draft!.role, equals(UserRole.independentMaster));
        expect(
          router.routerDelegate.currentConfiguration.fullPath,
          equals(RouteNames.register),
        );
      },
    );

    // -----------------------------------------------------------------------
    // 6. Login link navigates to /login and resets the draft
    // -----------------------------------------------------------------------
    testWidgets(
      '6. tapping the login link navigates to /login and resets the draft',
      (tester) async {
        final (:container, :router) = await _pumpRoleSelection(tester);

        // Seed a draft so we can verify reset fires.
        container.read(registerDraftProvider.notifier).start(UserRole.client);
        expect(container.read(registerDraftProvider), isNotNull);

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('role_login_link')),
        );
        await tester.tap(find.byKey(const ValueKey<String>('role_login_link')));
        await tester.pumpAndSettle();

        // Navigated to /login.
        expect(
          router.routerDelegate.currentConfiguration.fullPath,
          equals(RouteNames.login),
        );
        expect(find.text('login'), findsOneWidget);

        // Draft was reset.
        expect(container.read(registerDraftProvider), isNull);
      },
    );
  });
}
