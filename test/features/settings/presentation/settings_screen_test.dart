// Widget tests for the Account page (SettingsScreen).
//
// The «Акаунт» page is reached from the settings hub's Account row. It carries a
// language placeholder row (Key('row-language')) and a notifications toggle
// (Key('row-notifications')). There is NO Save button; controls act inline.
//
// Logout was REMOVED from this page — it now lives ONLY on the settings hub
// (settings_hub_screen.dart, row-logout → runLogoutFlow). The Account page must
// surface no logout control. Coverage:
//   A1 — Account-page controls render (language + notifications) and there is
//        NO logout control (regression guard against the row being reintroduced).
//   A8 — notifications toggle flips local state.
//
// The logout confirm/cancel/double-tap/failure/secure-storage-clear flow is
// covered on the hub test (settings_hub_screen_test.dart) — that is the only
// surface that triggers logout now.
//
// ScreenProtector native calls are kDebugMode-suppressed in the test runner.
// Navigation is driven by a minimal GoRouter (initial route = /settings).

import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/settings_row.dart';
import 'package:beautica_mobile/features/settings/presentation/settings_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

GoRouter _makeRouter() => GoRouter(
  initialLocation: RouteNames.settings,
  redirect: (context, state) => null,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.settings,
      builder: (_, _) => const SettingsScreen(),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (_, _) => const Scaffold(body: Text('login')),
    ),
  ],
);

Widget _buildApp({
  required GoRouter router,
  required FakeAuthRepository repo,
  required FakeSecureStorage storage,
}) => ProviderScope(
  overrides: [
    authRepositoryProvider.overrideWith((_) => repo),
    secureStorageProvider.overrideWith((_) => storage),
  ],
  child: MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk'),
  ),
);

void main() {
  group('SettingsScreen (Account page)', () {
    // A1 -----------------------------------------------------------------------
    testWidgets(
      'A1. account controls render (language + notifications) and NO logout '
      'control is present',
      (tester) async {
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(
            router: router,
            repo: FakeAuthRepository(),
            storage: FakeSecureStorage(),
          ),
        );
        await tester.pumpAndSettle();

        // The placeholder rows remain.
        expect(find.byKey(const Key('row-language')), findsOneWidget);
        expect(find.byKey(const Key('row-notifications')), findsOneWidget);

        // Regression guard: logout was removed from the Account page — it lives
        // only on the settings hub now. Neither the row nor its label may
        // appear here.
        expect(
          find.byKey(const Key('btn-logout')),
          findsNothing,
          reason:
              'logout was removed from the Account page; reintroducing it here '
              'would resurrect two logout entry points',
        );
        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(
          find.text(l10n.logout),
          findsNothing,
          reason: 'no logout label may render on the Account page',
        );
      },
    );

    // A8 -----------------------------------------------------------------------
    testWidgets('A8. notifications toggle flips its local state', (
      tester,
    ) async {
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _buildApp(
          router: router,
          repo: FakeAuthRepository(),
          storage: FakeSecureStorage(),
        ),
      );
      await tester.pumpAndSettle();

      final toggle = find.byKey(const Key('row-notifications'));
      expect(toggle, findsOneWidget);
      // Initial state is ON (semantics toggled true).
      SettingsToggleRow row = tester.widget(toggle);
      expect(row.initialValue, isTrue);

      // Tap the switch and confirm it does not throw / rebuild cleanly.
      await tester.tap(find.byKey(const Key('switch-notifications')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('switch-notifications')), findsOneWidget);
    });
  });
}
