// The REAL OS notification-permission state for this app, read through the
// same Firebase seam push registration uses. Read-only: it never prompts —
// the ask-once decision stays in `push_registration_notifier.dart`.
//
// Tests override [notificationPermissionReader] with a fake.

import 'dart:developer';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'firebase_messaging_provider.dart';
import 'push_available_provider.dart';

part 'notification_permission_provider.g.dart';

/// What the OS currently allows for this app's notifications.
enum NotificationPermissionStatus {
  /// Authorized (or provisional) — notifications are shown.
  granted,

  /// The user turned notifications off for Beautica.
  denied,

  /// Never decided (Android 13+ before / without the runtime prompt) — the OS
  /// shows nothing, so this reads as OFF.
  notDetermined,

  /// Push is not available in this build (no Firebase) — nothing to mirror.
  unavailable,
}

/// Returns a callable that reads the current permission. Never throws, never
/// prompts: `getNotificationSettings()` only, never `requestPermission()`.
@Riverpod(keepAlive: true)
Future<NotificationPermissionStatus> Function() notificationPermissionReader(
  Ref ref,
) => () async {
  final bool available = await ref.read(pushAvailableProvider.future);
  if (!available) return NotificationPermissionStatus.unavailable;
  try {
    final NotificationSettings settings = await ref
        .read(firebaseMessagingProvider)
        .getNotificationSettings();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional => NotificationPermissionStatus.granted,
      AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently =>
        NotificationPermissionStatus.denied,
      AuthorizationStatus.notDetermined =>
        NotificationPermissionStatus.notDetermined,
    };
  } on Object catch (e) {
    log(
      'notification permission read failed: ${e.runtimeType}',
      name: 'feature.notifications.push',
      level: 900,
    );
    return NotificationPermissionStatus.notDetermined;
  }
};
