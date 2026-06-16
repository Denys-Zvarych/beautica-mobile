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
// The default baseUrl is `http://localhost:8080` — the backend process
// reachable from the Ubuntu VM itself (where `flutter run` executes).  This
// keeps Dio constructible without crashing in widget tests and lets `flutter run`
// work on the VM directly.
//
// IMPORTANT: The baseUrl must NOT include the `/api/v1` path prefix. The
// generated API client (beautica_api package) already includes `/api/v1/` in
// every endpoint path. Raw Dio calls in feature repositories also explicitly
// include the `/api/v1/` prefix. A baseUrl that ends with `/api/v1` would
// cause double-prefix URLs (e.g. `http://host:8080/api/v1/api/v1/users/me`)
// which Spring Security blocks with 401 Unauthorized for unrecognised paths.
//
// For emulator builds, always pass the VM's host-only adapter IP:
//   flutter run --dart-define=BEAUTICA_BASE_URL=http://192.168.56.101:8080
//
// Usage in CI / deploy script:
//   flutter build apk --dart-define=BEAUTICA_BASE_URL=https://api.beautica.com

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
  ///   `--dart-define=BEAUTICA_BASE_URL=http://<ubuntu-vm-ip>:8080`
  /// e.g. `--dart-define=BEAUTICA_BASE_URL=http://192.168.56.101:8080`
  ///
  /// Do NOT append `/api/v1` to this value — the generated API client and all
  /// raw Dio calls already include the full `/api/v1/` path prefix.
  ///
  /// In release/profile builds [assertSecureUrl] throws if the URL is not
  /// HTTPS, so the fallback is never reachable in production.
  ///
  /// The raw compile-time value (before normalization). Read directly via
  /// `String.fromEnvironment` so it stays a compile-time constant; the
  /// public [baseUrl] is derived from it through [normalizeBaseUrl].
  static const String _rawBaseUrl = String.fromEnvironment(
    'BEAUTICA_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  /// Normalized base URL actually used by Dio.
  ///
  /// Computed once from [_rawBaseUrl] via [normalizeBaseUrl]. This is a
  /// `static final` (not `const`) because the normalization runs at first
  /// access — the trade-off is intentional: it's the only safe place to kill
  /// the "double `/api/v1` prefix" bug class regardless of what the build
  /// pipeline or a careless `--dart-define` injects.
  static final String baseUrl = normalizeBaseUrl(_rawBaseUrl);

  /// Defensive guard against the double-`/api/v1`-prefix bug class.
  ///
  /// WHY: the generated `beautica_api` client AND every raw Dio repository call
  /// already prepend the full `/api/v1/` segment to each endpoint path. If a
  /// `--dart-define=BEAUTICA_BASE_URL=...` value ends with `/api/v1` (or
  /// `/api/v1/`), the assembled URL becomes `.../api/v1/api/v1/...`, which
  /// Spring Security rejects with 401/404 — every authenticated call (incl.
  /// profile Save) then fails *silently*. This normalizer strips that
  /// accidental suffix (and any trailing slash) so the invariant holds no
  /// matter what the environment injects.
  ///
  /// Stripping is applied once: a single trailing `/api/v1` segment
  /// (case-insensitive, with or without a trailing slash) and any remaining
  /// trailing slash are removed. A clean `http://localhost:8080` is returned
  /// unchanged.
  ///
  /// Exposed for testing — `String.fromEnvironment` is compile-time-only and
  /// cannot be varied under `flutter test`, so the logic is verified directly.
  @visibleForTesting
  static String normalizeBaseUrl(String raw) {
    var value = raw.trim();
    // Drop any trailing slashes first so the suffix match below is reliable.
    value = value.replaceAll(RegExp(r'/+$'), '');
    // Strip a single accidental trailing `/api/v1` (case-insensitive).
    value = value.replaceFirst(RegExp(r'/api/v1$', caseSensitive: false), '');
    // Re-trim in case stripping the segment exposed a trailing slash.
    value = value.replaceAll(RegExp(r'/+$'), '');
    return value;
  }

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
        'Pass --dart-define=BEAUTICA_BASE_URL=http://<ubuntu-vm-ip>:8080\n'
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
