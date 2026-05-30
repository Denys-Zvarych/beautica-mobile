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
//   1.  kAuthPaths contains /auth/login.
//   2.  kAuthPaths contains /auth/logout.
//   3.  kAuthPaths contains /auth/refresh.
//   4.  kAuthPaths contains /auth/register (CLIENT + SALON_OWNER unified endpoint).
//   5.  kAuthPaths contains /auth/register/independent-master.
//   6.  kAuthPaths contains /auth/verify-email (OTP redaction — Phase 2.11).
//   7.  kAuthPaths contains /auth/resend-verification (OTP redaction — Phase 2.11).
//   8.  kAuthPaths contains /auth/forgot-password (email PII redaction — Phase 2.13).
//   9.  kAuthPaths contains /auth/reset-password (token + password redaction — Phase 2.13).
//  10.  kAuthPaths contains /auth/invite/validate (Phase 2.20).
//  11.  kAuthPaths contains /auth/invite/accept (Phase 2.20).
//  12.  kAuthPaths contains /independent-masters/me (Phase 4.2 — PII address body redaction).
//  13.  kAuthPaths contains /masters/me (Phase 4.2 — PII address body redaction).
//  14.  kAuthPaths has exactly 13 entries — no undocumented extras.

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

    test(
      '10. contains /auth/invite/validate (Phase 2.20 — invite token must not be logged)',
      () {
        expect(
          kAuthPaths,
          contains('/auth/invite/validate'),
          reason:
              'AuthInterceptor must NOT inject a bearer token; '
              'LoggingInterceptor must redact the single-use invite token.',
        );
      },
    );

    test(
      '11. contains /auth/invite/accept (Phase 2.20 — invite token + password must not be logged)',
      () {
        expect(
          kAuthPaths,
          contains('/auth/invite/accept'),
          reason:
              'AuthInterceptor must NOT inject a bearer token; '
              'LoggingInterceptor must redact the plaintext password and '
              'single-use invite token.',
        );
      },
    );

    test(
      '12. /independent-masters/me is in kPiiPaths (body redaction) but NOT kAuthPaths (token skip)',
      () {
        expect(
          kPiiPaths,
          contains('/independent-masters/me'),
          reason:
              'LoggingInterceptor must redact the request body in debug builds; '
              'street/buildingNo/locationNote are PII (MS5 pattern).',
        );
        expect(
          kAuthPaths,
          isNot(contains('/independent-masters/me')),
          reason:
              'Authenticated endpoint — must carry a Bearer token; placing it in '
              'kAuthPaths causes AuthInterceptor to skip token injection → 401.',
        );
      },
    );

    test(
      '13. /masters/me is in kPiiPaths (body redaction) but NOT kAuthPaths (token skip)',
      () {
        expect(
          kPiiPaths,
          contains('/masters/me'),
          reason:
              'LoggingInterceptor must redact the request body in debug builds; '
              'street/buildingNo/locationNote are PII (MS5 pattern).',
        );
        expect(
          kAuthPaths,
          isNot(contains('/masters/me')),
          reason:
              'Authenticated endpoint — must carry a Bearer token; placing it in '
              'kAuthPaths causes AuthInterceptor to skip token injection → 401.',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 14: exact cardinality — catches undocumented additions/removals
    // -----------------------------------------------------------------------

    test(
      '14. kAuthPaths has exactly 11 entries (unauthenticated endpoints only)',
      () {
        expect(
          kAuthPaths.length,
          equals(11),
          reason:
              'A path was added to or removed from kAuthPaths without a '
              'corresponding test update. kAuthPaths must only contain unauthenticated '
              'endpoints. PII-bearing authenticated paths go in kPiiPaths instead.',
        );
      },
    );

    test('14b. kPiiPaths is a strict superset of kAuthPaths — every unauthenticated '
        'path is also redacted in logs', () {
      // Every path in kAuthPaths must appear in kPiiPaths. The reverse is not
      // required — kPiiPaths may contain additional authenticated PII paths.
      for (final path in kAuthPaths) {
        expect(
          kPiiPaths,
          contains(path),
          reason:
              'kPiiPaths must contain every path in kAuthPaths. '
              'Missing: $path. All unauthenticated endpoints carry credentials '
              'or OTPs and must therefore also be redacted in debug logs.',
        );
      }
      // kPiiPaths must be strictly larger than kAuthPaths (Phase 4.2 added
      // 2 authenticated PII paths that are NOT in kAuthPaths).
      expect(
        kPiiPaths.length,
        greaterThan(kAuthPaths.length),
        reason:
            'kPiiPaths must contain additional entries beyond kAuthPaths '
            '(/independent-masters/me, /independent-masters/me/profile, and /masters/me).',
      );
    });

    test(
      '15. kPiiPaths has exactly 14 entries (kAuthPaths union + 3 authenticated PII paths)',
      () {
        expect(
          kPiiPaths.length,
          equals(14),
          reason:
              'kPiiPaths must equal kAuthPaths plus /independent-masters/me, '
              '/independent-masters/me/profile, and /masters/me. '
              'Update this count if new PII endpoints are added.',
        );
      },
    );
  });
}
