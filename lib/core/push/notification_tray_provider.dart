// Phase 069 (audit L1) — clears the Android notification tray on logout / auth
// wipe, so the NEXT account cannot read or tap the previous user's pushes.
//
// The one seam to the native side: tests override [notificationTrayClearer]
// (and [notificationSettingsOpener], the «Сповіщення» switch's settings opener).
// Best-effort and never throws; a no-op off Android (and in tests by default).

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'notification_tray_provider.g.dart';

const MethodChannel _kTrayChannel = MethodChannel(
  'com.beautica.beautica_mobile/notification_tray',
);

/// Returns a callable that cancels every notification of this app. Never throws.
@Riverpod(keepAlive: true)
Future<void> Function() notificationTrayClearer(Ref ref) => () async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _kTrayChannel.invokeMethod<void>('cancelAll');
  } on Object catch (e) {
    log(
      'notification tray clear failed: ${e.runtimeType}',
      name: 'feature.notifications.push',
      level: 900,
    );
  }
};

/// Returns a callable that opens Android's per-app notification settings for
/// Beautica (same native channel as the tray clearer). The «Акаунт» →
/// «Сповіщення» switch uses it: an app cannot grant or revoke its own
/// permission. Never throws; a no-op off Android.
@Riverpod(keepAlive: true)
Future<void> Function() notificationSettingsOpener(Ref ref) => () async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _kTrayChannel.invokeMethod<void>('openNotificationSettings');
  } on Object catch (e) {
    log(
      'open notification settings failed: ${e.runtimeType}',
      name: 'feature.notifications.push',
      level: 900,
    );
  }
};
