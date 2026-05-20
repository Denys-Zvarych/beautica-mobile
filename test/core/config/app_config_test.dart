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
    // Test 3 — AppConfig.baseUrl defaults to the Railway production URL
    //
    // When BEAUTICA_BASE_URL dart-define is absent, falls back to the Railway
    // production endpoint so installed release APKs reach a real backend
    // instead of timing out against an unreachable localhost. Dev workflows
    // override via `--dart-define=BEAUTICA_BASE_URL=http://<host-ip>:8080/api/v1`.
    // -----------------------------------------------------------------------
    test('baseUrl defaults to the Railway production URL', () {
      expect(
        AppConfig.baseUrl,
        equals('https://beautica-backend-production.up.railway.app/api/v1'),
      );
    });

    // -----------------------------------------------------------------------
    // Test 4 — AppConfig.baseUrl is HTTPS in the default build
    //
    // This test documents that the compile-time default is the Railway
    // production endpoint (HTTPS), so:
    //   • Release/profile builds without a dart-define still satisfy
    //     `assertSecureUrl()`.
    //   • The test-only `_isSecureUrl` helper mirrors that check and returns
    //     true for the default URL.
    // Dev builds that want to hit a local backend must opt in explicitly via
    //   `--dart-define=BEAUTICA_BASE_URL=http://<host-ip>:8080/api/v1`.
    // -----------------------------------------------------------------------
    test('baseUrl is https in the default build (Railway production URL)', () {
      expect(
        _isSecureUrl(AppConfig.baseUrl),
        isTrue,
        reason:
            'AppConfig.baseUrl defaults to the Railway production HTTPS URL '
            'so release APKs do not stall on localhost timeouts. '
            'assertSecureUrl() therefore passes in release/profile builds '
            'when no dart-define is supplied.',
      );
    });
  });
}
