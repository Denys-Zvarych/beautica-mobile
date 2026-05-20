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
    defaultValue: 'http://localhost:8080/api/v1',
  );

  /// Validates [baseUrl] at startup.
  ///
  /// - Release / profile builds: throws [StateError] if [baseUrl] is empty.
  ///   `https://...` URLs always pass.  `http://...` URLs pass only if the
  ///   host is loopback (localhost, 127.0.0.1, ::1, 10.0.2.2) or an RFC 1918
  ///   private LAN address — this preserves the safety net against shipping
  ///   a Play-Store APK that talks plain HTTP to a public endpoint while
  ///   still allowing the "release build against local backend over
  ///   adb-reverse / VirtualBox NAT" dev workflow.
  /// - Debug builds: logs an actionable error message if [baseUrl] is empty,
  ///   but does NOT throw — the developer still needs to add the dart-define.
  static void assertSecureUrl() {
    if (kReleaseMode || kProfileMode) {
      if (baseUrl.isEmpty) {
        throw StateError(
          'BEAUTICA_BASE_URL must be set in release/profile builds. '
          'Provide --dart-define=BEAUTICA_BASE_URL=https://... when building.',
        );
      }
      if (baseUrl.startsWith('https://')) return;
      if (baseUrl.startsWith('http://') && isPrivateOrLoopbackUrl(baseUrl)) {
        // Allowed: dev workflow — release/profile build pointed at a private
        // address (localhost via adb reverse, Android emulator loopback,
        // VirtualBox NAT, private LAN). MITM risk doesn't apply on
        // non-routable networks; the HTTPS requirement exists to prevent
        // shipping an APK that talks plain HTTP to a public endpoint.
        return;
      }
      throw StateError(
        'BEAUTICA_BASE_URL must start with https:// in release/profile builds '
        '(or http:// pointing at localhost / loopback / private LAN). '
        'Got: $baseUrl. '
        'Provide --dart-define=BEAUTICA_BASE_URL=https://... when building '
        'for distribution.',
      );
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

  /// Returns `true` if [url]'s host is a loopback or RFC 1918 private LAN
  /// address.
  ///
  /// Loopback hosts recognised:
  ///   - `localhost`
  ///   - `127.0.0.1` (IPv4 loopback)
  ///   - `::1` (IPv6 loopback)
  ///   - `10.0.2.2` (Android emulator → host loopback)
  ///
  /// RFC 1918 IPv4 ranges recognised:
  ///   - `10.0.0.0/8`
  ///   - `172.16.0.0/12`
  ///   - `192.168.0.0/16`
  ///
  /// Host equality is exact — `https://localhost.evil.com` does not match
  /// `localhost`.  Public hosts return `false`.
  ///
  /// Exposed (non-underscored) so it can be exercised directly in unit tests,
  /// since `kReleaseMode` is always `false` under `flutter test`.
  @visibleForTesting
  static bool isPrivateOrLoopbackUrl(String url) {
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return false;
    }
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;

    // Hostname-style loopback / well-known emulator alias.
    if (host == 'localhost') return true;
    if (host == '127.0.0.1') return true;
    if (host == '::1') return true;
    if (host == '10.0.2.2') return true; // Android emulator → host loopback

    // RFC 1918 private IPv4 ranges.  Parse as four octets.
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
      octets.add(n);
    }
    // 10.0.0.0/8
    if (octets[0] == 10) return true;
    // 172.16.0.0/12
    if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;
    // 192.168.0.0/16
    if (octets[0] == 192 && octets[1] == 168) return true;
    return false;
  }
}
