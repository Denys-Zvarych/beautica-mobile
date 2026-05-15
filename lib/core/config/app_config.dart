// Phase 2.2 — Static application configuration.
//
// Values are injected at compile-time via `--dart-define` so that release
// builds can target the production endpoint without code changes. The default
// falls back to the Android emulator loopback address for local development
// (10.0.2.2 maps to the host machine from the AVD).
//
// Usage in CI / deploy script:
//   flutter build apk --dart-define=BEAUTICA_BASE_URL=https://api.beautica.com/api/v1

import 'package:flutter/foundation.dart';

/// Compile-time application configuration.
///
/// All constants are resolved at build time via `String.fromEnvironment` /
/// `bool.fromEnvironment`. They can be overridden with:
///   `--dart-define=BEAUTICA_BASE_URL=<value>`
abstract final class AppConfig {
  /// Base URL for the Beautica REST API.
  ///
  /// Default: Android emulator loopback to the local Spring Boot server.
  static const String baseUrl = String.fromEnvironment(
    'BEAUTICA_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080/api/v1',
  );

  /// Throws a [StateError] in release builds when [baseUrl] is not HTTPS.
  ///
  /// Call this once at startup (e.g. inside [dioProvider]) so that a release
  /// APK built without the `--dart-define=BEAUTICA_BASE_URL=https://...` flag
  /// fails loudly at first use rather than silently shipping cleartext traffic.
  ///
  /// Debug and profile builds are exempt — the emulator default (`http://10.0.2.2`)
  /// is intentionally cleartext for local development.
  static void assertSecureUrl() {
    // `assert` is a no-op in release; the if-guard below handles release mode.
    assert(
      true,
      '',
    ); // assertions disabled in release — this line is intentional
    if (!kDebugMode && !kProfileMode && !baseUrl.startsWith('https://')) {
      throw StateError(
        'BEAUTICA_BASE_URL must start with https:// in release builds. '
        'Provide --dart-define=BEAUTICA_BASE_URL=https://... when building for release.',
      );
    }
  }
}
