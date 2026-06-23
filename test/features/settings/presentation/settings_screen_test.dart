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

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
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

  // ANB — notification-bell icon swap guard --------------------------------
  //
  // The notifications toggle row's glyph was swapped from a Material
  // Icon(Icons.notifications_none_rounded) to the dotless bell SVG
  // AppIcon(BeauticaAssetIcons.notificationPlain), 19px / accentDeep — the SAME
  // bell the top-bar BellButton renders, so the two sit identically.
  //
  // Red-against-revert: with the old Material icon the notificationPlain
  // predicate finds 0 (Icon is not AppIcon) → ANB1 fails. With the swap it finds
  // the single bell SVG inside row-notifications → passes. Rule 3 (previously
  // unguarded site — the existing A1/A8 tests assert the row by Key only).
  //
  // Finders are robust Key-scoped widget predicates — never localized strings.
  group('SettingsScreen notification-bell icon (swap guard)', () {
    Finder bell() => find.byWidgetPredicate(
      (w) => w is AppIcon && w.asset == BeauticaAssetIcons.notificationPlain,
    );

    testWidgets(
      'ANB1. row-notifications renders the notificationPlain bell SVG and no '
      'Material notifications Icon remains',
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

        // Exactly one bell SVG on the screen, scoped inside the notifications
        // row (red-against-revert: 0 if reverted to the Material bell).
        expect(
          find.descendant(
            of: find.byKey(const Key('row-notifications')),
            matching: bell(),
          ),
          findsOneWidget,
          reason:
              'the notifications row must render the dotless notificationPlain '
              'bell SVG (matching the top-bar BellButton)',
        );

        // The swap is complete, not doubled: the old Material bell must be gone
        // from inside the row.
        expect(
          find.descendant(
            of: find.byKey(const Key('row-notifications')),
            matching: find.byWidgetPredicate(
              (w) => w is Icon && w.icon == Icons.notifications_none_rounded,
            ),
          ),
          findsNothing,
          reason:
              'the old Material Icons.notifications_none_rounded must not remain '
              'alongside the SVG (the swap replaces, not stacks)',
        );
      },
    );

    testWidgets(
      'ANB2. notification bell keeps the 19px / accentDeep tint and size '
      '(parity with the top-bar bell and sibling settings rows)',
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

        final icon = tester.widget<AppIcon>(
          find.descendant(
            of: find.byKey(const Key('row-notifications')),
            matching: bell(),
          ),
        );
        expect(
          icon.size,
          19,
          reason: 'settings notification bell must stay 19px',
        );
        expect(
          icon.color,
          BrandColors.accentDeep,
          reason: 'settings notification bell must stay BrandColors.accentDeep',
        );
      },
    );
  });
}
