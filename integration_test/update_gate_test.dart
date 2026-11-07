// Phase 438 — E2E: the forced-update gate in the MaterialApp.router builder.
//
// The full app (router, auth redirect, splash → /login) boots with the gate
// mounted exactly as `BeauticaApp` mounts it, over the FakeBackend Dio:
//   1. `minVersionCode = build + 1` → ONLY the gate is on screen (the login
//      screen behind it is absent) and «Оновити» hands `url_launcher` a
//      `market://details?id=<package>` URI, externally.
//   2. `GET /app/config` fails at the transport → the app renders normally.
//   3. `GET /app/config` answers 404 (a backend without 437) → normal app.
//   4. build == min → normal app; the backend then raises min → a resume
//      inside the 1 h throttle does NOT re-check, the next eligible resume
//      does and the gate covers the RUNNING app.
//
// Runs headless: `flutter test integration_test/update_gate_test.dart
// -d flutter-tester`.

import 'package:beautica_mobile/core/app_version/app_version_info.dart';
import 'package:beautica_mobile/core/app_version/update_required_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const ValueKey<String> _loginEmail = ValueKey<String>('login_email');

final PackageInfo _info = PackageInfo(
  appName: 'Beautica',
  packageName: 'com.beautica.app',
  version: '1.5.0',
  buildNumber: '7',
);

/// Records every launch; reports success.
final class _RecordingLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<(String, PreferredLaunchMode)> launched =
      <(String, PreferredLaunchMode)>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add((url, options.mode));
    return true;
  }
}

Future<void> _boot(
  WidgetTester tester,
  FakeBackend fb, {
  DateTime Function()? clock,
}) => AppHarness.boot(
  tester,
  fb,
  clock: clock,
  mountUpdateGate: true,
  extraOverrides: <Object>[
    appPackageInfoProvider.overrideWith((_) async => _info),
  ],
);

/// Background → foreground through the real binding lifecycle dispatch.
Future<void> _backgroundAndResume(WidgetTester tester) async {
  for (final AppLifecycleState s in <AppLifecycleState>[
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late UrlLauncherPlatform original;
  late _RecordingLauncher launcher;

  setUp(() {
    installOverflowGuard();
    original = UrlLauncherPlatform.instance;
    launcher = _RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;
  });
  tearDown(() async {
    UrlLauncherPlatform.instance = original;
    await AppHarness.tearDownHarness();
  });

  testWidgets('build < minVersionCode → only the gate; «Оновити» opens '
      'market:// externally', (tester) async {
    final FakeBackend fb = FakeBackend()..wireAppConfig(minVersionCode: 8);
    await _boot(tester, fb);
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(UpdateRequiredScreen.screenKey),
    );

    expect(fb.appConfigCalls, 1);
    expect(find.byKey(UpdateRequiredScreen.screenKey), findsOneWidget);
    expect(
      find.byKey(_loginEmail),
      findsNothing,
      reason: 'the app shell must not be reachable behind the gate',
    );

    await tester.tap(find.byKey(UpdateRequiredScreen.buttonKey));
    await AppHarness.settle(tester);

    expect(launcher.launched, hasLength(1));
    expect(launcher.launched.single.$1, 'market://details?id=com.beautica.app');
    expect(
      launcher.launched.single.$2,
      PreferredLaunchMode.externalApplication,
    );
    expect(find.byKey(UpdateRequiredScreen.playErrorKey), findsNothing);
  });

  testWidgets('config call fails → fail-open: the normal app renders', (
    tester,
  ) async {
    final FakeBackend fb = FakeBackend()..wireAppConfigFailure();
    await _boot(tester, fb);

    expect(find.byKey(_loginEmail), findsOneWidget);
    expect(find.byKey(UpdateRequiredScreen.screenKey), findsNothing);
    expect(launcher.launched, isEmpty);
  });

  testWidgets('a backend without 437 (404) → fail-open: the normal app '
      'renders', (tester) async {
    final FakeBackend fb = FakeBackend()
      ..wireAppConfig(minVersionCode: 8, statusCode: 404);
    await _boot(tester, fb);

    expect(fb.appConfigCalls, 1);
    expect(find.byKey(_loginEmail), findsOneWidget);
    expect(find.byKey(UpdateRequiredScreen.screenKey), findsNothing);
  });

  testWidgets('build == min renders the app; a raised min blocks the RUNNING '
      'app only on the next eligible resume (1 h throttle)', (tester) async {
    DateTime now = kFixedNow;
    final FakeBackend fb = FakeBackend()..wireAppConfig(minVersionCode: 7);
    await _boot(tester, fb, clock: () => now);

    expect(fb.appConfigCalls, 1);
    expect(find.byKey(_loginEmail), findsOneWidget);
    expect(find.byKey(UpdateRequiredScreen.screenKey), findsNothing);

    fb.wireAppConfig(minVersionCode: 8);
    now = now.add(const Duration(minutes: 30));
    await _backgroundAndResume(tester);
    await AppHarness.settle(tester);
    expect(fb.appConfigCalls, 1, reason: 'inside the throttle: no re-check');
    expect(find.byKey(_loginEmail), findsOneWidget);

    now = now.add(const Duration(minutes: 31));
    await _backgroundAndResume(tester);
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(UpdateRequiredScreen.screenKey),
    );
    expect(fb.appConfigCalls, 2);
    expect(find.byKey(_loginEmail), findsNothing);
  });
}
