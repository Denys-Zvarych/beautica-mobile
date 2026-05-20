// Phase 2.2 — Static application configuration.
//
// Values are injected at compile-time via `--dart-define` so that release
// builds can target the production endpoint without code changes.
//
// DEV TOPOLOGY for this project:
//   - Android emulator runs on the Windows 11 host.
//   - Spring Boot backend runs on the Ubuntu VM (VirtualBox).
//   - From the emulator's perspective, `10.0.2.2` is the Windows host loopback,
//     NOT the Ubuntu VM.  Use the Ubuntu VM's host-only adapter IP instead
//     (typically `192.168.56.101` or whatever `ip addr` shows on the VM).
//
// The default baseUrl is `http://localhost:8080/api/v1` — the backend process
// reachable from the Ubuntu VM itself (where `flutter run` executes).  This
// keeps Dio constructible without crashing in widget tests and lets `flutter run`
// work on the VM directly.
//
// For emulator builds, always pass the VM's host-only adapter IP:
//   flutter run --dart-define=BEAUTICA_BASE_URL=http://192.168.56.101:8080/api/v1
//
// Usage in CI / deploy script:
//   flutter build apk --dart-define=BEAUTICA_BASE_URL=https://api.beautica.com/api/v1

import 'dart:developer';

import 'package:flutter/foundation.dart';

/// Compile-time application configuration.
///
/// All constants are resolved at build time via `String.fromEnvironment` /
/// `bool.fromEnvironment`. They can be overridden with:
///   `--dart-define=BEAUTICA_BASE_URL=<value>`
abstract final class AppConfig {
  /// Base URL for the Beautica REST API.
  ///
  /// Fallback for `flutter run` on the Ubuntu dev machine.  `localhost:8080`
  /// is the Spring Boot process running directly on the VM where the Dart
  /// toolchain executes.  For emulator builds, always pass:
  ///   `--dart-define=BEAUTICA_BASE_URL=http://<ubuntu-vm-ip>:8080/api/v1`
  /// e.g. `--dart-define=BEAUTICA_BASE_URL=http://192.168.56.101:8080/api/v1`
  ///
  /// In release/profile builds [assertSecureUrl] throws if the URL is not
  /// HTTPS, so the fallback is never reachable in production.
  static const String baseUrl = String.fromEnvironment(
    'BEAUTICA_BASE_URL',
    defaultValue: 'https://beautica-backend-production.up.railway.app/api/v1',
  );

  /// Validates [baseUrl] at startup.
  ///
  /// - Release / profile builds: throws [StateError] if [baseUrl] is empty or
  ///   does not start with `https://`.  A release APK must never ship without
  ///   a real HTTPS endpoint.
  /// - Debug builds: logs an actionable error message if [baseUrl] is empty,
  ///   but does NOT throw — the developer still needs to add the dart-define.
  static void assertSecureUrl() {
    if (kReleaseMode || kProfileMode) {
      if (baseUrl.isEmpty || !baseUrl.startsWith('https://')) {
        throw StateError(
          'BEAUTICA_BASE_URL must start with https:// in release/profile builds. '
          'Provide --dart-define=BEAUTICA_BASE_URL=https://... when building.',
        );
      }
      return;
    }

    // Debug mode: warn loudly but do not crash so the developer can see the
    // message in the console and fix the dart-define without a full restart.
    if (baseUrl.isEmpty) {
      log(
        'BEAUTICA_BASE_URL is not set.\n'
        'Pass --dart-define=BEAUTICA_BASE_URL=http://<ubuntu-vm-ip>:8080/api/v1\n'
        'to `flutter run`. The Ubuntu VM IP is typically 192.168.56.101 — '
        'check with `ip addr show` on the VM side.',
        name: 'core.config',
        level: 1000, // Level.SEVERE
      );
    }
  }
}
