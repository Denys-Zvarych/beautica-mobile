// Phase 2.16 — Widget tests for [RoleSelectionScreen] (wizard entry gate).
//
// SOURCE OF TRUTH: docs/signup-designs/role-selection-page.html.
//
// Covered scenarios (closing mobile-qa MEDIUM coverage gap M-2 — behavior
// previously lived in the now-deleted `register_screen_test.dart` monolith):
//   1. Three role cards render — Client / Salon owner / Independent master.
//      The cards are addressed via their localised title text (the cards
//      themselves carry no per-card Key in source; the keyed wrapper is
//      `Key('field-role')`).
//   2. Single-check invariant — picking one role shows exactly one
//      `Icons.check` glyph in the picker (no leakage from a prior tap).
//   3. `start(role)` write on Continue — selecting a role + tapping
//      `Key('btn-continue-role')` writes the role into
//      `registerDraftProvider` and navigates to `/register` (Step 1).
//   4. Continue disabled until a role is picked — tapping the CTA before
//      any selection must not call `start` and must not navigate away.
//
// (5) Login-link-clears-draft is intentionally NOT duplicated here — it's
// already covered in `logout_flow_test.dart` test "login-link-from-role-
// selection-clears-draft".

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
  group('RoleSelectionScreen', () {
    // -----------------------------------------------------------------------
    // 1. Three role cards render
    // -----------------------------------------------------------------------
    testWidgets(
      '1. three role cards render (client / salon owner / independent master) '
      'inside the keyed field-role wrapper',
      (tester) async {
        await _pumpRoleSelection(tester);
        final l10n = lookupAppLocalizations(const Locale('uk'));

        // The keyed wrapper hosts all three cards.
        expect(find.byKey(const Key('field-role')), findsOneWidget);

        // Each card is uniquely addressable via its localised title.
        expect(find.text(l10n.intentClientTitle), findsOneWidget);
        expect(find.text(l10n.intentSalonTitle), findsOneWidget);
        expect(find.text(l10n.intentIndependentTitle), findsOneWidget);

        // The continue CTA is keyed.
        expect(find.byKey(const Key('btn-continue-role')), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // 2. Single-check invariant
    // -----------------------------------------------------------------------
    testWidgets(
      '2. tapping one role card shows exactly one Icons.check (no leakage '
      'from a prior selection)',
      (tester) async {
        await _pumpRoleSelection(tester);
        final l10n = lookupAppLocalizations(const Locale('uk'));

        // No selection yet → no check icon.
        expect(find.byIcon(Icons.check), findsNothing);

        // Pick "Client".
        await tester.tap(find.text(l10n.intentClientTitle));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.check), findsOneWidget);

        // Switch to "Independent master" — must still be exactly one check.
        await tester.tap(find.text(l10n.intentIndependentTitle));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.check), findsOneWidget);

        // And a third switch — still exactly one.
        await tester.tap(find.text(l10n.intentSalonTitle));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.check), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // 3. start(role) write on Continue
    // -----------------------------------------------------------------------
    testWidgets(
      '3. tapping a role + Continue writes role into registerDraftProvider '
      'and navigates to /register (Step 1)',
      (tester) async {
        final (:container, :router) = await _pumpRoleSelection(tester);
        final l10n = lookupAppLocalizations(const Locale('uk'));

        // Draft starts null.
        expect(container.read(registerDraftProvider), isNull);

        // Pick "Salon owner".
        await tester.tap(find.text(l10n.intentSalonTitle));
        await tester.pumpAndSettle();

        // Tap Continue.
        await tester.ensureVisible(find.byKey(const Key('btn-continue-role')));
        await tester.tap(find.byKey(const Key('btn-continue-role')));
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

        // Tap the CTA — should be a no-op (InkWell.onTap is null when
        // _selectedRole is null per role_selection_screen.dart:202).
        await tester.ensureVisible(find.byKey(const Key('btn-continue-role')));
        await tester.tap(find.byKey(const Key('btn-continue-role')));
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
      'exactly one check icon without re-tapping a card',
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

        // The preselected role surfaces a single check icon with no taps.
        expect(find.byIcon(Icons.check), findsOneWidget);

        // Continue is enabled — tapping it advances and overwrites cleanly.
        await tester.ensureVisible(find.byKey(const Key('btn-continue-role')));
        await tester.tap(find.byKey(const Key('btn-continue-role')));
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
  });
}
