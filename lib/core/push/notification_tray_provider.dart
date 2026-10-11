// Phase 069 (audit L1) — clears the Android notification tray on logout / auth
// wipe, so the NEXT account cannot read or tap the previous user's pushes.
//
// The one seam to the native side: tests override [notificationTrayClearer].
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
