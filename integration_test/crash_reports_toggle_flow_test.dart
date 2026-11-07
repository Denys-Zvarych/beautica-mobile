// Phase 410 (R.3 D8) — E2E: the «Надсилати звіти про збої» opt-out switch on
// the «Акаунт» page (`SettingsScreen`).
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// `settings_screen_test.dart` (A18–A20) pins the row against a bare
// `SettingsScreen` and a stub router. Only this file proves the REAL route
// reaches it (client home → burger → hub → `row-account` → /settings), that the
// real `crashReportingEnabledProvider` drives the row, and that the choice
// survives a relaunch — the provider is rebuilt from the stored flag, not from
// in-memory state.
//
// RELAUNCH MODEL — identical to `owner_relaunch_last_salon_flow_test.dart`:
// `pumpWidget(SizedBox.shrink())` disposes the whole `ProviderScope`, then a
// fresh boot runs over the SAME `FakeSecureStorage` (session) and the SAME
// `FakeDiagnosticsStore` (the diagnostics keys), as on a process kill.
//
// DIAGNOSTICS STORE: the harness defaults `diagnosticsStoreProvider` to a
// fresh in-memory fake per boot; this flow passes ONE shared fake through
// `AppHarness.boot(diagnostics:)` so the opt-out survives the relaunch.
//
// NO PATROL FLOW: no OS dialog, deep link, notification, WebView or biometric.
// The Sentry SDK itself is not initialised in the harness (no DSN), which is
// exactly the debug/local behaviour (A5); `applyOptIn` is then a no-op.

import 'package:beautica_mobile/core/storage/storage_keys.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/settings_row.dart';
import 'package:beautica_mobile/features/settings/presentation/settings_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/fakes/fake_diagnostics_store.dart';
import '../test/helpers/fakes/fake_secure_storage.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const Key _kRow = Key('row-crash-reports');
const Key _kSwitch = Key('switch-crash-reports');

final RegExp _hex128 = RegExp(r'^[0-9a-f]{32}$');

/// Boots the app over [storage] + [diagnostics] (no login).
Future<GoRouter> _boot(
  WidgetTester tester,
  FakeBackend fb,
  FakeSecureStorage storage,
  FakeDiagnosticsStore diagnostics,
) => AppHarness.boot(tester, fb, storage: storage, diagnostics: diagnostics);

/// Client home → burger → hub → `row-account` → «Акаунт» (/settings), then
/// scrolls the crash-reports row into view (800x600 harness viewport).
Future<void> _openAccountPage(WidgetTester tester, GoRouter router) async {
  AppHarness.expectLocation(router, RouteNames.clientHome);
  await AppHarness.tapVisible(tester, find.byKey(const Key('btn-menu-client')));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.clientMenu);

  await AppHarness.tapVisible(tester, find.byKey(const Key('row-account')));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.settings);
  expect(find.byType(SettingsScreen), findsOneWidget);

  expect(find.byKey(_kRow), findsOneWidget);
  await tester.ensureVisible(find.byKey(_kRow));
  await AppHarness.settle(tester);
}

/// Kills the app and cold-starts it over the SAME stores. The stored refresh
/// token restores the session — no login.
Future<GoRouter> _relaunch(
  WidgetTester tester,
  FakeBackend fb,
  FakeSecureStorage storage,
  FakeDiagnosticsStore diagnostics,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await AppHarness.settle(tester);
  final GoRouter router = await _boot(tester, fb, storage, diagnostics);
  await AppHarness.settle(tester);
  return router;
}

bool _rowValue(WidgetTester tester) =>
    tester.widget<SettingsToggleRow>(find.byKey(_kRow)).value!;

Future<void> _tapSwitch(WidgetTester tester) async {
  await AppHarness.tapVisible(tester, find.byKey(_kSwitch));
  await AppHarness.settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  final AppLocalizationsUk l10n = AppLocalizationsUk();

  testWidgets(
    'crash_reports_toggle: ON by default on /settings, OFF persists across a '
    'relaunch, ON again rotates the install ID',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final storage = FakeSecureStorage();
      final diagnostics = FakeDiagnosticsStore();

      // ── Cold start, first launch: nothing stored → ON (decided default).
      GoRouter router = await _boot(tester, fb, storage, diagnostics);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);
      await _openAccountPage(tester, router);

      expect(
        find.descendant(
          of: find.byKey(_kRow),
          matching: find.text(l10n.accountCrashReportsLabel),
        ),
        findsOneWidget,
      );
      expect(_rowValue(tester), isTrue, reason: 'default must be ON');
      expect(diagnostics.values[StorageKeys.diagnosticsEnabled], isNull);

      // ── Toggle OFF → persisted.
      await _tapSwitch(tester);
      expect(_rowValue(tester), isFalse);
      expect(diagnostics.values[StorageKeys.diagnosticsEnabled], 'false');

      // ── Relaunch: the rebuilt provider reads the stored opt-out.
      final int loginsBefore = fb.loginCalls;
      router = await _relaunch(tester, fb, storage, diagnostics);
      expect(fb.loginCalls, loginsBefore, reason: 'relaunch never re-logs in');
      await _openAccountPage(tester, router);
      expect(
        _rowValue(tester),
        isFalse,
        reason: 'the opt-out must survive a relaunch',
      );

      // ── Toggle ON → persisted, and a fresh install ID is minted (D8).
      final int writesBefore = diagnostics.writes;
      await _tapSwitch(tester);
      expect(_rowValue(tester), isTrue);
      expect(diagnostics.values[StorageKeys.diagnosticsEnabled], 'true');
      expect(
        diagnostics.values[StorageKeys.diagnosticsInstallId],
        matches(_hex128),
        reason: 'off→on must regenerate the anonymous install ID',
      );
      expect(diagnostics.writes, writesBefore + 2);

      // ── And ON survives a relaunch too.
      router = await _relaunch(tester, fb, storage, diagnostics);
      await _openAccountPage(tester, router);
      expect(_rowValue(tester), isTrue);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // QA audit 2026-11-05: a non-client (staff-side) role reaches the same row
  // through its own hub and the switch persists there too.
  testWidgets(
    'crash_reports_toggle: INDEPENDENT_MASTER reaches the switch from its menu '
    'and toggling OFF persists',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final storage = FakeSecureStorage();
      final diagnostics = FakeDiagnosticsStore();

      final GoRouter router = await _boot(tester, fb, storage, diagnostics);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await AppHarness.settle(tester);

      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('btn-menu-master')),
      );
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(tester, find.byKey(const Key('row-account')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.settings);

      expect(find.byKey(_kRow), findsOneWidget);
      await tester.ensureVisible(find.byKey(_kRow));
      await AppHarness.settle(tester);
      expect(
        find.descendant(
          of: find.byKey(_kRow),
          matching: find.text(l10n.accountCrashReportsLabel),
        ),
        findsOneWidget,
      );
      expect(_rowValue(tester), isTrue, reason: 'default must be ON');

      await _tapSwitch(tester);
      expect(_rowValue(tester), isFalse);
      expect(diagnostics.values[StorageKeys.diagnosticsEnabled], 'false');
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
