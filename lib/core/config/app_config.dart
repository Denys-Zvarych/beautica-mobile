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

  /// Phase 408 — which environment this build was baked for
  /// (`staging` | `prod`), from `config/env/<env>.json` via
  /// `--dart-define-from-file`. Defaults to `staging` so a plain `flutter run`
  /// with no flavor still works; `env_guard.dart` tolerates that only in debug.
  static const String env = String.fromEnvironment(
    'BEAUTICA_ENV',
    defaultValue: 'staging',
  );

  /// Public website origin (`https://beautica.app`) — the ONLY origin a
  /// server-built public link (booking links, phase 413) may point at.
  ///
  /// Mirrors the backend's `app.booking-links.web-base-url` (default
  /// `https://beautica.app`, not overridden by any backend profile — local and
  /// staging build their links on the prod website too). Deliberately NOT a
  /// `--dart-define`: an allow-list anchor that a build flag can widen is not
  /// an anchor. Bare https origin: no userinfo, no port, no path, no trailing
  /// slash.
  static const String publicWebOrigin = 'https://beautica.app';

  /// Host part of [publicWebOrigin].
  static const String publicWebHost = 'beautica.app';

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

  /// Test seam, invoked (assert-only) at the top of [assertSecureUrl].
  /// Assigned only from tests; guarded by forbid_debug_hook_assignment_in_lib.sh.
  @visibleForTesting
  static void Function()? debugOnAssertSecureUrl;

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
    // Phase 075 test seam (assert-only, compiled out of release): lets
    // boot_order_test pin that this guard runs before the first boot slice.
    assert(() {
      debugOnAssertSecureUrl?.call();
      return true;
    }());
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
  ///   - `localhost` (a trailing dot is stripped)
  ///   - `127.0.0.0/8` (IPv4 loopback), `0.0.0.0`, `169.254.0.0/16` (link-local)
  ///   - `::1` (IPv6 loopback) and IPv4-mapped `::ffff:a.b.c.d` (v4 classified)
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
  /// since `kReleaseMode` is always `false` under `flutter test`; also reused by
  /// `env_guard.dart` (phase 408) rather than a parallel host classifier.
  // (phase 408: no longer @visibleForTesting — env_guard.dart calls it.)
  static bool isPrivateOrLoopbackUrl(String url) {
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return false;
    }
    var host = uri.host.toLowerCase();
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    if (host.isEmpty) return false;

    // Hostname-style loopback / well-known emulator alias.
    if (host == 'localhost') return true;
    if (host == '::1' || host == '::') return true;

    // IPv4-mapped IPv6 (`::ffff:a.b.c.d` or `::ffff:xxxx:xxxx`): classify the v4.
    if (host.startsWith('::ffff:')) {
      final mapped = host.substring('::ffff:'.length);
      if (mapped.contains('.')) return _isPrivateOrLoopbackIpv4(mapped);
      final groups = mapped.split(':');
      if (groups.length == 2) {
        final hi = int.tryParse(groups[0], radix: 16);
        final lo = int.tryParse(groups[1], radix: 16);
        if (hi == null || lo == null) return false;
        return _isPrivateOrLoopbackIpv4(
          '${hi >> 8}.${hi & 0xff}.${lo >> 8}.${lo & 0xff}',
        );
      }
      return false;
    }
    return _isPrivateOrLoopbackIpv4(host);
  }

  static bool _isPrivateOrLoopbackIpv4(String host) {
    if (host == '10.0.2.2') return true; // Android emulator → host loopback
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
      octets.add(n);
    }
    // 127.0.0.0/8 loopback
    if (octets[0] == 127) return true;
    // 0.0.0.0 unspecified
    if (octets.every((o) => o == 0)) return true;
    // 169.254.0.0/16 link-local
    if (octets[0] == 169 && octets[1] == 254) return true;
    // 10.0.0.0/8
    if (octets[0] == 10) return true;
    // 172.16.0.0/12
    if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;
    // 192.168.0.0/16
    if (octets[0] == 192 && octets[1] == 168) return true;
    return false;
  }
}
