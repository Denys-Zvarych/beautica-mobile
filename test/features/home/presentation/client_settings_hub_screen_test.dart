// Widget tests for the CLIENT settings hub (ClientSettingsHubScreen).
//
// The hub is the screen the home-hub burger icon pushes. It mirrors the master
// settings hub: six rows — five navigational (personal / contacts / location /
// account / help) plus a terminal logout row that raises the confirm dialog.
//
// Coverage:
//   • all six rows render;
//   • each navigational row tap pushes the correct CLIENT route (asserted via a
//     stub destination sentinel keyed per route);
//   • the logout row raises the confirm dialog and confirming calls logout().
//
// Finders use widget Keys (row-personal, …) — never localized strings (M2).
// Layer: Widget.

import 'dart:async';

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/presentation/client_settings_hub_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

/// AuthNotifier whose logout() never resolves — lets a test confirm the dialog
/// without the tree tearing down before assertions run. Tracks invocation.
class _TrackingAuthNotifier extends AuthNotifier {
  int logoutCalls = 0;

  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();

  @override
  Future<void> logout() async {
    logoutCalls++;
    await Completer<void>().future; // block forever
  }
}

/// Builds a router rooted at the CLIENT hub with stub sentinel destinations for
/// every route the hub can push, so navigation can be asserted by Key.
GoRouter _hubRouter() => GoRouter(
  initialLocation: RouteNames.clientMenu,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.clientMenu,
      builder: (_, _) => const ClientSettingsHubScreen(),
    ),
    GoRoute(
      path: RouteNames.clientEditPersonal,
      builder: (_, _) =>
          const Scaffold(body: SizedBox(key: Key('stub-personal'))),
    ),
    GoRoute(
      path: RouteNames.clientEditContacts,
      builder: (_, _) =>
          const Scaffold(body: SizedBox(key: Key('stub-contacts'))),
    ),
    GoRoute(
      path: RouteNames.clientEditLocation,
      builder: (_, _) =>
          const Scaffold(body: SizedBox(key: Key('stub-location'))),
    ),
    GoRoute(
      path: RouteNames.settings,
      builder: (_, _) =>
          const Scaffold(body: SizedBox(key: Key('stub-account'))),
    ),
    GoRoute(
      path: RouteNames.contactSupport,
      builder: (_, _) => const Scaffold(body: SizedBox(key: Key('stub-help'))),
    ),
    GoRoute(
      path: RouteNames.clientHome,
      builder: (_, _) => const Scaffold(body: SizedBox(key: Key('stub-home'))),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (_, _) => const Scaffold(body: SizedBox(key: Key('stub-login'))),
    ),
  ],
);

void main() {
  group('ClientSettingsHubScreen navigation rows', () {
    testWidgets('all six rows render', (tester) async {
      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('row-personal')), findsOneWidget);
      expect(find.byKey(const Key('row-contacts')), findsOneWidget);
      expect(find.byKey(const Key('row-location')), findsOneWidget);
      expect(find.byKey(const Key('row-account')), findsOneWidget);
      expect(find.byKey(const Key('row-help')), findsOneWidget);
      expect(find.byKey(const Key('row-logout')), findsOneWidget);
    });

    // (rowKey, destinationSentinelKey) — the locked CLIENT destinations.
    const cases = <(String, String)>[
      ('row-personal', 'stub-personal'),
      ('row-contacts', 'stub-contacts'),
      ('row-location', 'stub-location'),
      ('row-account', 'stub-account'),
      ('row-help', 'stub-help'),
    ];

    for (final (rowKey, destKey) in cases) {
      testWidgets('tapping $rowKey pushes to $destKey', (tester) async {
        final router = _hubRouter();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(router);
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(Key(rowKey)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(rowKey)));
        await tester.pumpAndSettle();

        expect(
          find.byKey(Key(destKey)),
          findsOneWidget,
          reason: '$rowKey must push the CLIENT route carrying $destKey',
        );
      });
    }

    testWidgets('close button navigates home when canPop false', (
      tester,
    ) async {
      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-close-hub')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stub-home')), findsOneWidget);
    });
  });

  group('ClientSettingsHubScreen location-marker icon (swap guard)', () {
    // The location row's glyph was swapped from a Material
    // Icon(Icons.location_on_outlined) to AppIcon(locationMarker), 19px /
    // accentDeep. Red-against-revert: the predicate finds 0 if reverted to the
    // Material icon (Icon is not AppIcon) → fails; with the swap it finds the
    // single location-marker SVG → passes. Rule 3 (previously unguarded site).
    Finder locationMarker() => find.byWidgetPredicate(
      (w) => w is AppIcon && w.asset == BeauticaAssetIcons.locationMarker,
    );

    testWidgets('row-location renders the locationMarker AppIcon', (
      tester,
    ) async {
      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router);
      await tester.pumpAndSettle();

      // Exactly one location-marker SVG in the hub, inside the location row.
      expect(locationMarker(), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('row-location')),
          matching: locationMarker(),
        ),
        findsOneWidget,
      );
    });

    testWidgets('location marker keeps the 19px / accentDeep tint and size', (
      tester,
    ) async {
      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router);
      await tester.pumpAndSettle();

      final icon = tester.widget<AppIcon>(locationMarker());
      expect(icon.size, 19, reason: 'settings location marker must stay 19px');
      expect(
        icon.color,
        BrandColors.accentDeep,
        reason: 'settings location marker must stay BrandColors.accentDeep',
      );
    });
  });

  group('ClientSettingsHubScreen logout row', () {
    testWidgets('confirming the logout calls logout() exactly once', (
      tester,
    ) async {
      final auth = _TrackingAuthNotifier();
      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[authProvider.overrideWith(() => auth)],
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('row-logout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('row-logout')));
      // mobile-perf MEDIUM fix (2026-09-08) — `_loggingOut` (the re-entrancy
      // guard) flips synchronously on this tap, but it is no longer bound to
      // `SettingsRow(loading:)`; only `_loggingOutLoading` drives the
      // spinner, and it flips true only AFTER confirm, immediately before
      // `logout()`. So nothing is ticking yet here — a real `pumpAndSettle`
      // works again (stronger sync than the bounded pump it replaced).
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(auth.logoutCalls, 0);

      await tester.tap(find.byKey(const Key('btn-logout-confirm')));
      // From here `logout()` blocks forever (`_TrackingAuthNotifier`), which
      // means `_loggingOutLoading` — now true — drives an indeterminate
      // spinner for the rest of this test. `pumpAndSettle` can never settle
      // while that ticks, so bounded pumps stay required past this point.
      await tester.pump(); // apply pop(true) + start logout()
      await tester.pump(const Duration(milliseconds: 300)); // dialog dismiss

      expect(
        auth.logoutCalls,
        1,
        reason: 'confirming must invoke authProvider.logout() exactly once',
      );
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
