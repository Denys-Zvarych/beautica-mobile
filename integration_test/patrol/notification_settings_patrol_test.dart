// «Акаунт» → «Сповіщення» — patrol native check of the REAL settings opener:
// the switch tap goes through `notificationSettingsOpenerProvider` → the
// `com.beautica/tray` MethodChannel → `MainActivity.openNotificationSettings`
// → Android's per-app notification settings (an activity of the system
// Settings app). Back returns to the app on the Account page, switch unchanged.
//
// Only the permission READ is faked (denied): CI builds may carry no Firebase
// config, and with push unavailable the switch is inert by design — nothing to
// open. The opener, channel and Kotlin intent are all real.
//
// The fake-backed widget-tier journey (mirror, resume, covered replay,
// revisit) lives in integration_test/settings_change_password_flow_test.dart.
//
// Run: patrol test --target integration_test/patrol/notification_settings_patrol_test.dart

import 'dart:io' show Platform;

import 'package:beautica_mobile/core/push/notification_permission_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:patrol/patrol.dart';

import '../support/app_harness.dart' show AppHarness;
import 'support/patrol_harness.dart';

const Duration _nativeTimeout = Duration(seconds: 30);

/// Any view owned by the system Settings app — both the per-app notification
/// screen and the app-details fallback live there.
const AndroidSelector _systemSettings = AndroidSelector(
  applicationPackage: 'com.android.settings',
);

void main() {
  const PatrolTesterConfig config = PatrolTesterConfig(
    settlePolicy: SettlePolicy.trySettle,
  );

  tearDown(PatrolHarness.tearDownHarness);

  patrolTest(
    'Account notifications switch tap opens the Android app notification '
    'settings; back returns to Account with the switch unchanged',
    skip: !Platform.isAndroid,
    config: config,
    ($) async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.independentMaster;
      final GoRouter router = await PatrolHarness.boot(
        $,
        fb,
        extraOverrides: <Object>[
          notificationPermissionReaderProvider.overrideWithValue(
            () async => NotificationPermissionStatus.denied,
          ),
        ],
      );
      await PatrolHarness.loginAs($, fb, UserRole.independentMaster);

      await $(const Key('btn-menu-master')).tap();
      await $(const Key('row-account')).tap();
      AppHarness.expectLocation(router, RouteNames.settings);

      await $(const Key('switch-notifications')).tap();

      // The real intent fired: the system Settings app is in front.
      await $.platform.android.waitUntilVisible(
        _systemSettings,
        timeout: _nativeTimeout,
      );

      await $.platform.android.pressBack();
      // Poll (bounded) for the app to come back; no Flutter signal for it.
      const Duration step = Duration(milliseconds: 500);
      for (
        var i = 0;
        i < 20 && find.byKey(const Key('row-notifications')).evaluate().isEmpty;
        i++
      ) {
        await $.pump(step);
      }
      await $.pumpAndSettle();

      AppHarness.expectLocation(router, RouteNames.settings);
      final SemanticsHandle handle = $.tester.ensureSemantics();
      expect(
        $.tester.getSemantics(find.byKey(const Key('row-notifications'))),
        isSemantics(isToggled: false),
        reason: 'still denied — the switch never flips on its own',
      );
      handle.dispose();
    },
  );
}
