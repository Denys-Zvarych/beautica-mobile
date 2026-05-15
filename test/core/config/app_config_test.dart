// Tests for AppConfig compile-time configuration.
//
// `assertSecureUrl()` checks `!kDebugMode && !baseUrl.startsWith('https://')`.
// In test builds, `kDebugMode` is always `true`, so the release-mode guard
// never fires. Tests validate:
//   1. `assertSecureUrl()` does NOT throw in debug mode (even with HTTP URL).
//   2. A pure URL-check helper (_isSecureUrl) correctly identifies HTTPS vs HTTP.
//   3. `AppConfig.baseUrl` is not null or empty.

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
    // Test 3 — AppConfig.baseUrl is not empty
    // -----------------------------------------------------------------------
    test('baseUrl is not null or empty', () {
      expect(AppConfig.baseUrl, isNotEmpty);
    });
  });
}
