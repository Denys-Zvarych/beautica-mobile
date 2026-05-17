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
    // Test 3 — AppConfig.baseUrl defaults to localhost fallback
    //
    // When BEAUTICA_BASE_URL dart-define is absent, falls back to localhost
    // (Ubuntu VM dev machine). Emulator builds require an explicit dart-define
    // pointing to the VM's host-only adapter IP (e.g. 192.168.56.101:8080).
    // -----------------------------------------------------------------------
    test('baseUrl defaults to localhost fallback', () {
      // When BEAUTICA_BASE_URL dart-define is absent, falls back to localhost
      // (Ubuntu VM dev). Emulator builds require explicit dart-define.
      expect(AppConfig.baseUrl, equals('http://localhost:8080/api/v1'));
    });

    // -----------------------------------------------------------------------
    // Test 4 — AppConfig.baseUrl is NOT https in the default debug build
    //
    // This test documents the profile-mode guard invariant:
    //   • The compile-time default points to http://localhost:8080/api/v1
    //     (the Ubuntu VM where `flutter run` executes) — HTTP, not HTTPS.
    //   • assertSecureUrl() is guarded by `!kDebugMode`, so it is a no-op in
    //     tests and debug builds.
    //   • In a release build, if someone accidentally leaves the HTTP URL,
    //     assertSecureUrl() would throw at startup — this test documents that
    //     the HTTP default is intentional for the debug/VM target only.
    // -----------------------------------------------------------------------
    test(
      'baseUrl is NOT https in debug/test builds (http localhost default is intentional)',
      () {
        // The test-only _isSecureUrl helper mirrors the production URL check
        // without the kDebugMode gate. We assert the result is false to
        // document that the default URL is HTTP and would trigger the release
        // guard if kDebugMode were false.
        expect(
          _isSecureUrl(AppConfig.baseUrl),
          isFalse,
          reason:
              'AppConfig.baseUrl defaults to http://localhost:8080/api/v1 '
              '(Ubuntu VM dev). assertSecureUrl() is a no-op here '
              '(kDebugMode == true). In a release build, this URL must be '
              'replaced with the HTTPS Railway endpoint or assertSecureUrl() '
              'will throw at startup.',
        );
      },
    );
  });
}
