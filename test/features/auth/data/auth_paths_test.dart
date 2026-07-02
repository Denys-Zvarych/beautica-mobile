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
// IMPORTANT (2026-05-30 fix): All paths include the full `/api/v1/` prefix
// because AppConfig.baseUrl no longer carries the `/api/v1` segment. The
// generated API client and all raw Dio calls use `/api/v1/...` paths directly,
// so RequestOptions.path always contains the full prefix when interceptors run.
//
// Backend registration contract (Phase 2.x):
//   INDEPENDENT_MASTER → POST /api/v1/auth/register/independent-master
//   CLIENT + SALON_OWNER → POST /api/v1/auth/register  (unified, role discriminator in body)
//
// Phase 2.11 — OTP paths added to prevent plaintext OTP body logging (SECURITY HIGH):
//   /api/v1/auth/verify-email      — submit OTP code
//   /api/v1/auth/resend-verification — re-send verification email
//
// Covered scenarios:
//   1.  kAuthPaths contains /api/v1/auth/login.
//   2.  kAuthPaths contains /api/v1/auth/logout.
//   3.  kAuthPaths contains /api/v1/auth/refresh.
//   4.  kAuthPaths contains /api/v1/auth/register.
//   5.  kAuthPaths contains /api/v1/auth/register/independent-master.
//   6.  kAuthPaths contains /api/v1/auth/verify-email.
//   7.  kAuthPaths contains /api/v1/auth/resend-verification.
//   8.  kAuthPaths contains /api/v1/auth/forgot-password.
//   9.  kAuthPaths contains /api/v1/auth/reset-password.
//  10.  kAuthPaths contains /api/v1/auth/invite/validate.
//  11.  kAuthPaths contains /api/v1/auth/invite/accept.
//  12.  /api/v1/independent-masters/me is in kPiiPaths but NOT kAuthPaths.
//  13.  /api/v1/masters/me is in kPiiPaths but NOT kAuthPaths.
//  14.  kAuthPaths has exactly 11 entries — no undocumented extras.
//  14b. kPiiPaths is a strict superset of kAuthPaths.
//  15.  kPiiPaths has exactly 16 entries = kAuthPaths (11) + 5 authenticated
//       PII paths: /api/v1/independent-masters/me,
//       /api/v1/independent-masters/me/profile, /api/v1/masters/me,
//       /api/v1/search/masters, /api/v1/search/salons (the last two added by
//       commit b550428 — auth-gated address redaction).

import 'package:beautica_mobile/core/network/auth_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kAuthPaths', () {
    // -----------------------------------------------------------------------
    // Tests 1–11: required entries (all with /api/v1/ prefix)
    // -----------------------------------------------------------------------

    test('1. contains /api/v1/auth/login', () {
      expect(kAuthPaths, contains('/api/v1/auth/login'));
    });

    test('2. contains /api/v1/auth/logout', () {
      expect(kAuthPaths, contains('/api/v1/auth/logout'));
    });

    test('3. contains /api/v1/auth/refresh', () {
      expect(kAuthPaths, contains('/api/v1/auth/refresh'));
    });

    test(
      '4. contains /api/v1/auth/register (CLIENT + SALON_OWNER unified endpoint)',
      () {
        expect(kAuthPaths, contains('/api/v1/auth/register'));
      },
    );

    test('5. contains /api/v1/auth/register/independent-master', () {
      expect(kAuthPaths, contains('/api/v1/auth/register/independent-master'));
    });

    test(
      '6. contains /api/v1/auth/verify-email (OTP body must not be logged in plaintext)',
      () {
        expect(
          kAuthPaths,
          contains('/api/v1/auth/verify-email'),
          reason:
              'LoggingInterceptor must redact OTP payloads on this path. '
              'Missing entry would cause the OTP to appear in plaintext logs.',
        );
      },
    );

    test(
      '7. contains /api/v1/auth/resend-verification (re-send OTP path must be redacted)',
      () {
        expect(
          kAuthPaths,
          contains('/api/v1/auth/resend-verification'),
          reason:
              'LoggingInterceptor must redact OTP payloads on this path. '
              'Missing entry would log resend request bodies in plaintext.',
        );
      },
    );

    test(
      '8. contains /api/v1/auth/forgot-password (email PII must not be logged)',
      () {
        expect(
          kAuthPaths,
          contains('/api/v1/auth/forgot-password'),
          reason:
              'AuthInterceptor must NOT attach a bearer token to this '
              'unauthenticated endpoint, and LoggingInterceptor must redact '
              'the request body (the email is PII).',
        );
      },
    );

    test(
      '9. contains /api/v1/auth/reset-password (token + new password must not be logged)',
      () {
        expect(
          kAuthPaths,
          contains('/api/v1/auth/reset-password'),
          reason:
              'AuthInterceptor must NOT attach a bearer token to this '
              'unauthenticated endpoint, and LoggingInterceptor must redact '
              'the request body (the single-use reset token + new password '
              'are sensitive).',
        );
      },
    );

    test(
      '10. contains /api/v1/auth/invite/validate (Phase 2.20 — invite token must not be logged)',
      () {
        expect(
          kAuthPaths,
          contains('/api/v1/auth/invite/validate'),
          reason:
              'AuthInterceptor must NOT inject a bearer token; '
              'LoggingInterceptor must redact the single-use invite token.',
        );
      },
    );

    test(
      '11. contains /api/v1/auth/invite/accept (Phase 2.20 — invite token + password must not be logged)',
      () {
        expect(
          kAuthPaths,
          contains('/api/v1/auth/invite/accept'),
          reason:
              'AuthInterceptor must NOT inject a bearer token; '
              'LoggingInterceptor must redact the plaintext password and '
              'single-use invite token.',
        );
      },
    );

    test(
      '12. /api/v1/independent-masters/me is in kPiiPaths (body redaction) but NOT kAuthPaths (token skip)',
      () {
        expect(
          kPiiPaths,
          contains('/api/v1/independent-masters/me'),
          reason:
              'LoggingInterceptor must redact the request body in debug builds; '
              'street/buildingNo/locationNote are PII (MS5 pattern).',
        );
        expect(
          kAuthPaths,
          isNot(contains('/api/v1/independent-masters/me')),
          reason:
              'Authenticated endpoint — must carry a Bearer token; placing it in '
              'kAuthPaths causes AuthInterceptor to skip token injection → 401.',
        );
      },
    );

    test(
      '13. /api/v1/masters/me is in kPiiPaths (body redaction) but NOT kAuthPaths (token skip)',
      () {
        expect(
          kPiiPaths,
          contains('/api/v1/masters/me'),
          reason:
              'LoggingInterceptor must redact the request body in debug builds; '
              'street/buildingNo/locationNote are PII (MS5 pattern).',
        );
        expect(
          kAuthPaths,
          isNot(contains('/api/v1/masters/me')),
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
      // kPiiPaths must be strictly larger than kAuthPaths (Phase 4.2 + the
      // 2026-06-25 address-redaction fix added 5 authenticated PII paths that
      // are NOT in kAuthPaths).
      expect(
        kPiiPaths.length,
        greaterThan(kAuthPaths.length),
        reason:
            'kPiiPaths must contain additional entries beyond kAuthPaths '
            '(/api/v1/independent-masters/me, /api/v1/independent-masters/me/profile, '
            '/api/v1/masters/me, /api/v1/search/masters, and /api/v1/search/salons).',
      );
    });

    test(
      '15. kPiiPaths has exactly 17 entries (kAuthPaths union + 6 authenticated PII paths)',
      () {
        expect(
          kPiiPaths.length,
          equals(17),
          reason:
              'kPiiPaths must equal kAuthPaths (11) plus '
              '/api/v1/independent-masters/me, /api/v1/independent-masters/me/profile, '
              '/api/v1/masters/me, the two auth-gated discovery search paths '
              '/api/v1/search/masters + /api/v1/search/salons, and the '
              'Phase 14.0 CLIENT booking create endpoint /api/v1/bookings '
              '(6 authenticated PII paths = 17 total). The search paths were '
              'added by commit b550428 (auth-gated address redaction); '
              '/api/v1/bookings was added by the Phase 14.0 security fix '
              '(POST /bookings carries the free-text clientComment field). '
              'Update this count if new PII endpoints are added.',
        );
      },
    );
  });
}
