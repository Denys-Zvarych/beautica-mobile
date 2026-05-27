// Unit tests for kAuthPaths constant (core/network/auth_paths.dart).
//
// kAuthPaths is consumed by AuthInterceptor and LoggingInterceptor to determine
// which requests should not carry a Bearer token (or should be logged
// differently). A missing entry causes the interceptor to attach an access
// token to registration requests, leaking the token to an unauthenticated
// endpoint. A stale entry causes protected endpoints to lose their token.
//
// These tests lock the exact set of paths so that any addition or removal to
// kAuthPaths itself is caught immediately.
//
// Backend registration contract (Phase 2.x):
//   INDEPENDENT_MASTER → POST /auth/register/independent-master  (path-specific)
//   CLIENT + SALON_OWNER → POST /auth/register  (unified, role discriminator in body)
//
// Phase 2.11 — OTP paths added to prevent plaintext OTP body logging (SECURITY HIGH):
//   /auth/verify-email      — submit OTP code
//   /auth/resend-verification — re-send verification email
//
// Covered scenarios:
//   1. kAuthPaths contains /auth/login.
//   2. kAuthPaths contains /auth/logout.
//   3. kAuthPaths contains /auth/refresh.
//   4. kAuthPaths contains /auth/register (CLIENT + SALON_OWNER unified endpoint).
//   5. kAuthPaths contains /auth/register/independent-master.
//   6. kAuthPaths contains /auth/verify-email (OTP redaction — Phase 2.11).
//   7. kAuthPaths contains /auth/resend-verification (OTP redaction — Phase 2.11).
//   8. kAuthPaths contains /auth/forgot-password (email PII redaction — Phase 2.13).
//   9. kAuthPaths contains /auth/reset-password (token + password redaction — Phase 2.13).
//  10. kAuthPaths has exactly 11 entries — no undocumented extras.

import 'package:beautica_mobile/core/network/auth_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kAuthPaths', () {
    // -----------------------------------------------------------------------
    // Tests 1–7: required entries
    // -----------------------------------------------------------------------

    test('1. contains /auth/login', () {
      expect(kAuthPaths, contains('/auth/login'));
    });

    test('2. contains /auth/logout', () {
      expect(kAuthPaths, contains('/auth/logout'));
    });

    test('3. contains /auth/refresh', () {
      expect(kAuthPaths, contains('/auth/refresh'));
    });

    test(
      '4. contains /auth/register (CLIENT + SALON_OWNER unified endpoint)',
      () {
        expect(kAuthPaths, contains('/auth/register'));
      },
    );

    test('5. contains /auth/register/independent-master', () {
      expect(kAuthPaths, contains('/auth/register/independent-master'));
    });

    test(
      '6. contains /auth/verify-email (OTP body must not be logged in plaintext)',
      () {
        expect(
          kAuthPaths,
          contains('/auth/verify-email'),
          reason:
              'LoggingInterceptor must redact OTP payloads on this path. '
              'Missing entry would cause the OTP to appear in plaintext logs.',
        );
      },
    );

    test(
      '7. contains /auth/resend-verification (re-send OTP path must be redacted)',
      () {
        expect(
          kAuthPaths,
          contains('/auth/resend-verification'),
          reason:
              'LoggingInterceptor must redact OTP payloads on this path. '
              'Missing entry would log resend request bodies in plaintext.',
        );
      },
    );

    test(
      '8. contains /auth/forgot-password (email PII must not be logged)',
      () {
        expect(
          kAuthPaths,
          contains('/auth/forgot-password'),
          reason:
              'AuthInterceptor must NOT attach a bearer token to this '
              'unauthenticated endpoint, and LoggingInterceptor must redact '
              'the request body (the email is PII).',
        );
      },
    );

    test(
      '9. contains /auth/reset-password (token + new password must not be logged)',
      () {
        expect(
          kAuthPaths,
          contains('/auth/reset-password'),
          reason:
              'AuthInterceptor must NOT attach a bearer token to this '
              'unauthenticated endpoint, and LoggingInterceptor must redact '
              'the request body (the single-use reset token + new password '
              'are sensitive).',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 10: exact cardinality — catches undocumented additions/removals
    // -----------------------------------------------------------------------

    test('10. has exactly 11 entries — no undocumented paths', () {
      expect(
        kAuthPaths.length,
        equals(11),
        reason:
            'A path was added to or removed from kAuthPaths without a '
            'corresponding test update. Update this test and confirm the '
            'interceptors handle the new path correctly.',
      );
    });
  });
}
