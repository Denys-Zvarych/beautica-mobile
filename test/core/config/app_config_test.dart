// Tests for AppConfig compile-time configuration.
//
// `assertSecureUrl()` gates on `kReleaseMode || kProfileMode`.  In test builds
// `kDebugMode` is always `true`, so the release/profile branch can never be
// triggered from a unit test — we test it indirectly by exercising the
// `@visibleForTesting` helper [AppConfig.isPrivateOrLoopbackUrl], which
// encapsulates the only non-trivial decision the release branch makes.
//
// Coverage:
//   1. `assertSecureUrl()` does NOT throw in debug mode (even with HTTP URL).
//   2. `AppConfig.baseUrl` defaults to the localhost fallback when no
//      dart-define is supplied.
//   3. `isPrivateOrLoopbackUrl(...)` correctly classifies hosts:
//        - allows loopback and RFC 1918 private LAN
//        - rejects public hosts and homograph attacks like
//          `localhost.evil.com`

import 'package:beautica_mobile/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig', () {
    // -----------------------------------------------------------------------
    // Test 1 — assertSecureUrl() does not throw in debug mode
    // -----------------------------------------------------------------------
    test(
      'assertSecureUrl() does not throw in debug mode (kDebugMode == true)',
      () {
        // In test builds, kDebugMode is true → the release guard is skipped.
        // Any base URL (including the HTTP localhost default) is accepted.
        expect(AppConfig.assertSecureUrl, returnsNormally);
      },
    );

    // -----------------------------------------------------------------------
    // Test 2 — AppConfig.baseUrl defaults to the localhost fallback
    //
    // When BEAUTICA_BASE_URL dart-define is absent, falls back to
    // `http://localhost:8080` — the backend reachable from the Ubuntu
    // VM where `flutter run` executes. The URL must NOT include an `/api/v1`
    // suffix because the generated API client and all raw Dio calls already
    // include the `/api/v1/` prefix in their paths. A double-prefix like
    // `http://localhost:8080/api/v1/api/v1/users/me` causes Spring Security
    // to return 401 for unrecognised paths.
    //
    // Dev workflows targeting the emulator override via:
    //   `--dart-define=BEAUTICA_BASE_URL=http://<host-ip>:8080`
    // CI/release builds bake in the production HTTPS URL via build args.
    // -----------------------------------------------------------------------
    test(
      'baseUrl defaults to the localhost fallback (without /api/v1 suffix)',
      () {
        expect(AppConfig.baseUrl, equals('http://localhost:8080'));
      },
    );

    // -----------------------------------------------------------------------
    // Test 3 — isPrivateOrLoopbackUrl whitelist
    //
    // The release/profile branch of assertSecureUrl() consults this helper to
    // decide whether to allow an `http://` URL through.  We cannot drive
    // release mode in a unit test, so we validate the gatekeeper directly.
    // -----------------------------------------------------------------------
    group('isPrivateOrLoopbackUrl', () {
      test('allows hostname-style loopback (localhost)', () {
        expect(
          AppConfig.isPrivateOrLoopbackUrl('http://localhost:8080/api/v1'),
          isTrue,
        );
        expect(AppConfig.isPrivateOrLoopbackUrl('https://localhost/'), isTrue);
      });

      test('allows IPv4 loopback (127.0.0.1)', () {
        expect(
          AppConfig.isPrivateOrLoopbackUrl('http://127.0.0.1:8080'),
          isTrue,
        );
      });

      test('allows IPv6 loopback (::1)', () {
        // Uri.parse strips the surrounding [] from the IPv6 literal.
        expect(AppConfig.isPrivateOrLoopbackUrl('http://[::1]:8080'), isTrue);
      });

      test('allows Android emulator loopback alias (10.0.2.2)', () {
        expect(
          AppConfig.isPrivateOrLoopbackUrl('http://10.0.2.2:8080'),
          isTrue,
        );
      });

      test('allows RFC 1918 10.0.0.0/8 addresses', () {
        expect(
          AppConfig.isPrivateOrLoopbackUrl('http://10.1.2.3:8080'),
          isTrue,
        );
        expect(
          AppConfig.isPrivateOrLoopbackUrl('http://10.255.255.255'),
          isTrue,
        );
      });

      test('allows RFC 1918 172.16.0.0/12 addresses', () {
        expect(
          AppConfig.isPrivateOrLoopbackUrl('http://172.16.0.1:8080'),
          isTrue,
        );
        expect(AppConfig.isPrivateOrLoopbackUrl('http://172.20.10.5'), isTrue);
        expect(
          AppConfig.isPrivateOrLoopbackUrl('http://172.31.255.254'),
          isTrue,
        );
      });

      test('rejects 172.x outside 16-31 range', () {
        expect(AppConfig.isPrivateOrLoopbackUrl('http://172.15.0.1'), isFalse);
        expect(AppConfig.isPrivateOrLoopbackUrl('http://172.32.0.1'), isFalse);
      });

      test('allows RFC 1918 192.168.0.0/16 addresses', () {
        expect(
          AppConfig.isPrivateOrLoopbackUrl('http://192.168.1.42:8080'),
          isTrue,
        );
        expect(AppConfig.isPrivateOrLoopbackUrl('http://192.168.0.1'), isTrue);
        expect(
          AppConfig.isPrivateOrLoopbackUrl('http://192.168.255.254'),
          isTrue,
        );
      });

      test('rejects 192.x outside 168 range', () {
        expect(AppConfig.isPrivateOrLoopbackUrl('http://192.167.1.1'), isFalse);
        expect(AppConfig.isPrivateOrLoopbackUrl('http://192.169.1.1'), isFalse);
      });

      test('rejects public hosts', () {
        expect(AppConfig.isPrivateOrLoopbackUrl('http://example.com'), isFalse);
        expect(
          AppConfig.isPrivateOrLoopbackUrl('http://api.beautica.com/api/v1'),
          isFalse,
        );
        expect(AppConfig.isPrivateOrLoopbackUrl('http://8.8.8.8'), isFalse);
      });

      test('rejects homograph-style attacks on loopback labels', () {
        // Exact-host matching prevents `localhost.evil.com` from passing.
        expect(
          AppConfig.isPrivateOrLoopbackUrl('http://localhost.evil.com'),
          isFalse,
        );
        expect(
          AppConfig.isPrivateOrLoopbackUrl('http://127.0.0.1.evil.com'),
          isFalse,
        );
      });

      test('rejects empty / hostless URLs', () {
        expect(AppConfig.isPrivateOrLoopbackUrl(''), isFalse);
        expect(AppConfig.isPrivateOrLoopbackUrl('not-a-url'), isFalse);
      });
    });
  });
}
