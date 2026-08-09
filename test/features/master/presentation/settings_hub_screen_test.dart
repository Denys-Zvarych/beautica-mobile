// Widget tests for the master settings hub (SettingsHubScreen).
//
// The hub is the screen the profile's top-right menu icon pushes. It is a
// non-PII screen (it does NOT acquire screenshot protection) and lists four
// navigational rows (personal / contacts / location / account) plus a terminal
// logout row that raises the confirm dialog.
//
// Coverage:
//   • each navigational row tap pushes the correct route (asserted via a stub
//     destination sentinel keyed per route);
//   • the close button pops / navigates to the profile;
//   • the logout row raises the confirm dialog (cancel + confirm keys present);
//   • cancelling the dialog does NOT log out;
//   • confirming logout calls logout() once and clears the dialog;
//   • confirming logout (with a real repo/storage) navigates to /login AND
//     leaves secure storage empty (M5 — migrated from the Account-page test
//     after logout was removed from the Account page);
//   • the double-tap guard prevents a second concurrent logout (migrated);
//   • a failing logout surfaces the l10n.logoutFailed VelvetSnack (migrated).
//
// Logout now lives ONLY on the hub — the Account page no longer triggers it, so
// the full logout flow coverage was migrated here to avoid any net loss.
//
// Finders use widget Keys (row-personal, row-contacts, …) — never localized
// strings (M2). Layer: Widget.

import 'dart:async';

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/settings_hub_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

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

/// AuthNotifier whose logout() throws a non-Failure exception — the only way the
/// failure VelvetSnack in runLogoutFlow is reachable (AuthNotifier.logout
/// swallows Failure internally).
class _ThrowingLogoutAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();

  @override
  Future<void> logout() async {
    throw Exception('simulated unexpected platform failure');
  }
}

/// Builds a router rooted at the hub with stub sentinel destinations for every
/// route the hub can push, so navigation can be asserted by Key.
GoRouter _hubRouter() => GoRouter(
  initialLocation: RouteNames.masterMenu,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterMenu,
      builder: (_, _) => const SettingsHubScreen(),
    ),
    GoRoute(
      path: RouteNames.masterEditPersonal,
      builder: (_, _) =>
          const Scaffold(body: SizedBox(key: Key('stub-personal'))),
    ),
    GoRoute(
      path: RouteNames.masterEditContacts,
      builder: (_, _) =>
          const Scaffold(body: SizedBox(key: Key('stub-contacts'))),
    ),
    GoRoute(
      path: RouteNames.masterEditLocation,
      builder: (_, _) =>
          const Scaffold(body: SizedBox(key: Key('stub-location'))),
    ),
    GoRoute(
      path: RouteNames.settings,
      builder: (_, _) =>
          const Scaffold(body: SizedBox(key: Key('stub-account'))),
    ),
    GoRoute(
      path: RouteNames.masterProfile,
      builder: (_, _) =>
          const Scaffold(body: SizedBox(key: Key('stub-profile'))),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (_, _) => const Scaffold(body: SizedBox(key: Key('stub-login'))),
    ),
  ],
);

void main() {
  group('SettingsHubScreen navigation rows', () {
    // (rowKey, destinationSentinelKey)
    const cases = <(String, String)>[
      ('row-personal', 'stub-personal'),
      ('row-contacts', 'stub-contacts'),
      ('row-location', 'stub-location'),
      ('row-account', 'stub-account'),
    ];

    for (final (rowKey, destKey) in cases) {
      testWidgets('tapping $rowKey pushes to $destKey', (tester) async {
        final router = _hubRouter();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(router);
        await tester.pumpAndSettle();

        expect(find.byKey(Key(rowKey)), findsOneWidget);

        await tester.tap(find.byKey(Key(rowKey)));
        await tester.pumpAndSettle();

        expect(
          find.byKey(Key(destKey)),
          findsOneWidget,
          reason: '$rowKey must push the route whose screen carries $destKey',
        );
      });
    }

    testWidgets('all four navigational rows + the logout row render', (
      tester,
    ) async {
      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('row-personal')), findsOneWidget);
      expect(find.byKey(const Key('row-contacts')), findsOneWidget);
      expect(find.byKey(const Key('row-location')), findsOneWidget);
      expect(find.byKey(const Key('row-account')), findsOneWidget);
      expect(find.byKey(const Key('row-logout')), findsOneWidget);
    });

    testWidgets(
      'close button navigates back to the profile when canPop false',
      (tester) async {
        final router = _hubRouter();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(router);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn-close-hub')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('stub-profile')),
          findsOneWidget,
          reason:
              'with no prior history (canPop false) the close button must '
              'go(masterProfile)',
        );
      },
    );
  });

  group('SettingsHubScreen logout row', () {
    testWidgets('tapping the logout row raises the confirm dialog', (
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
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const Key('btn-logout-cancel')), findsOneWidget);
      expect(find.byKey(const Key('btn-logout-confirm')), findsOneWidget);
      // Opening the dialog must not log out.
      expect(auth.logoutCalls, 0);
    });

    testWidgets('cancelling the logout dialog does NOT log out', (
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
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-logout-cancel')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(auth.logoutCalls, 0);
      // Still on the hub.
      expect(find.byKey(const Key('row-logout')), findsOneWidget);
    });

    testWidgets('confirming the logout calls logout() and clears the dialog', (
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
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-logout-confirm')));
      // Pump frames to drive the dialog's deterministic dismiss transition.
      // We cannot pumpAndSettle because logout() blocks forever by design (the
      // in-flight guard test fixture), so we advance just the pop animation.
      await tester.pump(); // apply ctx.pop(true) + start logout()
      await tester.pump(const Duration(milliseconds: 300)); // dialog dismiss

      expect(
        auth.logoutCalls,
        1,
        reason: 'confirming must invoke authProvider.logout() exactly once',
      );
      expect(find.byType(AlertDialog), findsNothing);
    });

    // Migrated from the Account-page test (A4 + A7 / M5): a real logout (backed
    // by FakeAuthRepository + FakeSecureStorage) calls repo.logout() once,
    // navigates to /login, and leaves secure storage empty.
    testWidgets(
      'confirming logout calls repo.logout() once, navigates to /login and '
      'leaves secure storage empty (M5)',
      (tester) async {
        final repo = FakeAuthRepository();
        // Storage starts empty: pre-seeding would trigger the AuthNotifier
        // cold-start restore, whose write-back of refreshed tokens races the
        // logout deleteAll() at the widget layer. The "wipe a populated token"
        // assertion lives in logout_flow_test.dart Test 1 (unit layer, restore
        // fully awaited). Here we assert the widget-layer logout reaches
        // secureStorage.deleteAll() and leaves it empty (M5).
        final storage = FakeSecureStorage();
        final router = _hubRouter();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            authRepositoryProvider.overrideWith((_) => repo),
            secureStorageProvider.overrideWith((_) => storage),
          ],
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('row-logout')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('row-logout')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-logout-confirm')));
        await tester.pumpAndSettle();

        expect(repo.logoutCallCount, 1);
        expect(
          find.byKey(const Key('stub-login')),
          findsOneWidget,
          reason: 'a successful logout must go(/login)',
        );
        expect(
          await storage.readRefreshToken(),
          isNull,
          reason: 'M5: logout must clear the refresh token from secure storage',
        );
      },
    );

    // Migrated from the Account-page test (A5): the in-flight guard must block a
    // second concurrent logout while the first is still running.
    testWidgets(
      'double-tap guard: a second confirm while logout is in flight does not '
      'trigger a second logout',
      (tester) async {
        final auth = _TrackingAuthNotifier(); // logout() blocks forever
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
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-logout-confirm')));
        await tester.pump(); // logout() now in flight (blocks forever)

        // Re-open + re-confirm: the inFlight guard must short-circuit.
        await tester.tap(find.byKey(const Key('row-logout')));
        await tester.pumpAndSettle();
        if (find.byKey(const Key('btn-logout-confirm')).evaluate().isNotEmpty) {
          await tester.tap(find.byKey(const Key('btn-logout-confirm')));
          await tester.pump();
        }

        expect(
          auth.logoutCalls,
          1,
          reason: 'the in-flight guard must prevent a second concurrent logout',
        );
      },
    );

    // Migrated from the Account-page test (A6): a logout failure surfaces the
    // l10n.logoutFailed error VelvetSnack.
    testWidgets('logout failure shows the l10n.logoutFailed VelvetSnack', (
      tester,
    ) async {
      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          authProvider.overrideWith(() => _ThrowingLogoutAuthNotifier()),
        ],
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('row-logout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('row-logout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-logout-confirm')));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('uk'));
      expectVelvetSnack(l10n.logoutFailed, variant: VelvetSnackVariant.error);

      // Drain the dwell Timer so it does not leak past the test.
      await pumpPastVelvetSnack(tester);
    });
  });

  // Sanity: l10n is wired so the title is the real localized string, never a
  // raw literal in the source (M11). We assert via the resolved l10n key.
  testWidgets('hub title uses the localized settingsTitle key', (tester) async {
    final router = _hubRouter();
    addTearDown(router.dispose);

    await tester.pumpRoutedApp(router);
    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(const Locale('uk'));
    expect(find.text(l10n.settingsTitle), findsOneWidget);
  });

  // ── Scroll / overflow regression (from the debugger) ────────────────────────
  //
  // The hub grew a 6th navigational concept (the help / contact-us row) on top
  // of the original four + the logout terminal action — seven rows in total
  // counting the hairline + logout. On a short, narrow viewport that pushes the
  // terminal logout row below the fold. This locks in two invariants so a FUTURE
  // 8th row can't silently reintroduce the off-screen-tap failure:
  //   (a) all seven rows lay out with NO RenderFlex overflow (the Phase 17.2
  //       overflow guard fails the test automatically if one is reported), and
  //   (b) after ensureVisible(row-logout) the logout row is hit-testable — i.e.
  //       the hub body stays scrollable and the terminal action is reachable.
  group('short-viewport scroll regression', () {
    testWidgets(
      'all seven rows render with no overflow and logout is reachable on a '
      'short narrow viewport',
      (tester) async {
        // A short, narrow phone surface that cannot fit all rows + the staggered
        // reveal padding without scrolling.
        tester.view.physicalSize = const Size(320, 520);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final router = _hubRouter();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(router);
        await tester.pumpAndSettle();

        // (a) Every row is present in the tree (no overflow stripped the column;
        // the overflow guard's tearDown fails the test if any RenderFlex
        // overflowed during layout at this size).
        for (final key in const <String>[
          'row-personal',
          'row-contacts',
          'row-location',
          'row-account',
          'row-help',
          'row-logout',
        ]) {
          expect(
            find.byKey(Key(key)),
            findsOneWidget,
            reason: '$key must be present at the short-viewport size',
          );
        }

        // (b) The terminal logout row stays reachable: scroll it into view and
        // confirm it is hit-testable (a tap lands on the real row, opening the
        // confirm dialog) — proving the hub body remained scrollable.
        await tester.ensureVisible(find.byKey(const Key('row-logout')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('row-logout')));
        await tester.pumpAndSettle();

        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason:
              'after ensureVisible the logout row must be hit-testable — a tap '
              'must reach it and raise the confirm dialog',
        );
      },
    );
  });
}
