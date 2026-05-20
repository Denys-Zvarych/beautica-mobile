// Tests for AppConfig compile-time configuration.
//
// `assertSecureUrl()` checks `!kDebugMode && !baseUrl.startsWith('https://')`.
// In test builds, `kDebugMode` is always `true`, so the release-mode guard
// never fires. Tests validate:
//   1. `assertSecureUrl()` does NOT throw in debug mode (even with HTTP URL).
//   2. A pure URL-check helper (_isSecureUrl) correctly identifies HTTPS vs HTTP.
//   3. `AppConfig.baseUrl` defaults to the localhost fallback when no dart-define
//      is supplied (Ubuntu VM dev machine — not the emulator's 10.0.2.2 address).

import 'package:beautica_mobile/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test-only pure helper that extracts the URL security check from
/// [AppConfig.assertSecureUrl] so it can be exercised without a compile flag.
///
/// This function is defined here in the test file only — it does NOT exist in
/// production code. The production guard uses `kDebugMode` which cannot be
/// overridden at test time.
bool _isSecureUrl(String url) => url.startsWith('https://');

void main() {
  group('AppConfig', () {
    // -----------------------------------------------------------------------
    // Test 1 — assertSecureUrl() does not throw in debug mode
    // -----------------------------------------------------------------------
    test(
      'assertSecureUrl() does not throw in debug mode (kDebugMode == true)',
      () {
        // In test builds, kDebugMode is true → the release guard is skipped.
        // Any base URL (including the HTTP emulator default) is accepted.
        expect(AppConfig.assertSecureUrl, returnsNormally);
      },
    );

    // -----------------------------------------------------------------------
    // Test 2 — _isSecureUrl pure helper
    // -----------------------------------------------------------------------
    group('_isSecureUrl (test-only URL-check helper)', () {
      test('returns true for https:// URLs', () {
        expect(_isSecureUrl('https://api.beautica.com/api/v1'), isTrue);
        expect(
          _isSecureUrl('https://beautica-backend-production.up.railway.app'),
          isTrue,
        );
      });

      test('returns false for http:// URLs', () {
        expect(_isSecureUrl('http://10.0.2.2:8080/api/v1'), isFalse);
        expect(_isSecureUrl('http://localhost:8080/api/v1'), isFalse);
      });

      test('returns false for empty string', () {
        expect(_isSecureUrl(''), isFalse);
      });
    });

    // -----------------------------------------------------------------------
    // Test 3 — AppConfig.baseUrl defaults to the localhost fallback
    //
    // When BEAUTICA_BASE_URL dart-define is absent, falls back to
    // `http://localhost:8080/api/v1` — the backend reachable from the Ubuntu
    // VM where `flutter run` executes. Dev workflows targeting the emulator
    // override via `--dart-define=BEAUTICA_BASE_URL=http://<host-ip>:8080/api/v1`,
    // and CI/release builds bake in the production HTTPS URL via build args.
    // -----------------------------------------------------------------------
    test('baseUrl defaults to the localhost fallback', () {
      expect(AppConfig.baseUrl, equals('http://localhost:8080/api/v1'));
    });

    // -----------------------------------------------------------------------
    // Test 4 — AppConfig.baseUrl is HTTP in the default debug build
    //
    // The compile-time default is `http://localhost:8080/api/v1`, so the
    // test-only `_isSecureUrl` helper returns false. `assertSecureUrl()`
    // tolerates this in debug mode but throws in release/profile builds —
    // CI/deploy pipelines must supply an HTTPS dart-define for release APKs.
    // -----------------------------------------------------------------------
    test('baseUrl is http in the default debug build (localhost fallback)', () {
      expect(
        _isSecureUrl(AppConfig.baseUrl),
        isFalse,
        reason:
            'AppConfig.baseUrl defaults to http://localhost:8080/api/v1 so '
            '`flutter run` on the Ubuntu VM works without a dart-define. '
            'Release/profile builds must override via '
            '--dart-define=BEAUTICA_BASE_URL=https://... to satisfy '
            'assertSecureUrl().',
      );
    });
  });
}
