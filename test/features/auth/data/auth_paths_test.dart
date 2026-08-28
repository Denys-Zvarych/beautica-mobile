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
//   9b. kAuthPaths contains /api/v1/auth/verify-password-reset-otp (Beautica
//       OTP task Phase A3/B2 — the new public password-reset OTP-verify step).
//  10.  kAuthPaths contains /api/v1/auth/invite/validate.
//  11.  kAuthPaths contains /api/v1/auth/invite/accept.
//  12.  /api/v1/independent-masters/me is in kPiiPaths but NOT kAuthPaths.
//  13.  /api/v1/masters/me is in kPiiPaths but NOT kAuthPaths.
//  14.  kAuthPaths has exactly 12 entries — no undocumented extras.
//  14b. kPiiPaths is a strict superset of kAuthPaths.
//  15.  kPiiPaths has exactly 22 entries = kAuthPaths (12) + 10 authenticated
//       PII paths: /api/v1/independent-masters/me,
//       /api/v1/independent-masters/me/profile, /api/v1/masters/me, the two
//       auth-gated discovery search paths /api/v1/search/masters +
//       /api/v1/search/salons (added by commit b550428 — auth-gated address
//       redaction), the Phase 14.0 CLIENT booking create endpoint
//       /api/v1/bookings, the MO-1 CLIENT appointment create endpoint
//       /api/v1/appointments, the track 7.x Wave B PROVIDER→CLIENT
//       feedback create endpoint /api/v1/client-reviews, the Phase 13.x
//       CLIENT wish-list toggle endpoint /api/v1/favorites, and the Phase
//       21.1 SALON_OWNER hub endpoint /api/v1/salons/mine (mobile-security
//       MEDIUM follow-up, 2026-08-28 — SalonResponse carries phone + ownerId).
//  16.  kPiiPathPrefixes contains /api/v1/salons/ (Finding 2, mobile-security
//       MEDIUM follow-up, 2026-08-28 — PATCH /salons/{salonId} carries name/
//       description/street/buildingNo/locationNote/phone/instagramUrl). This
//       is a PREFIX entry (dynamic {salonId}), NOT an exact [kPiiPaths]
//       member, so it does NOT change test 15's count of 22 — mirrors the
//       pre-existing /api/v1/bookings (exact, counted) + /api/v1/bookings/
//       (prefix, uncounted) pair, and the identical /api/v1/appointments
//       pair. The exact-match /api/v1/salons/mine entry from test 15 is
//       UNCHANGED — this prefix is additive alongside it, not a replacement.

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

    test('9b. contains /api/v1/auth/verify-password-reset-otp (Beautica OTP '
        'task Phase A3/B2 — email + code must not be logged)', () {
      expect(
        kAuthPaths,
        contains('/api/v1/auth/verify-password-reset-otp'),
        reason:
            'AuthInterceptor must NOT attach a bearer token to this '
            'unauthenticated endpoint (the user has no session yet), and '
            'LoggingInterceptor must redact the request body (the email + '
            'OTP code are sensitive).',
      );
    });

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
    // Tests 13b–13f: membership pins for the authenticated PII-only paths.
    //
    // Without these, the `length == 19` count (test 15) is the ONLY guard on
    // the newer PII entries — a one-for-one path swap (drop one, add another)
    // would keep the count at 19 and pass silently. Pinning each by identity
    // makes the suite fail the moment a specific PII path is removed or renamed.
    // -----------------------------------------------------------------------

    test('13b. /api/v1/independent-masters/me/profile is in kPiiPaths (phone + PII '
        'body redaction) but NOT kAuthPaths', () {
      expect(
        kPiiPaths,
        contains('/api/v1/independent-masters/me/profile'),
        reason:
            'Phase 4.3 profile edit endpoint carries phone number + PII; '
            'LoggingInterceptor must redact its body in debug builds.',
      );
      expect(
        kAuthPaths,
        isNot(contains('/api/v1/independent-masters/me/profile')),
        reason:
            'Authenticated endpoint — must carry a Bearer token; placing it in '
            'kAuthPaths causes AuthInterceptor to skip token injection → 401.',
      );
    });

    test(
      '13c. /api/v1/search/masters is in kPiiPaths (auth-gated address redaction) '
      'but NOT kAuthPaths',
      () {
        expect(
          kPiiPaths,
          contains('/api/v1/search/masters'),
          reason:
              'Security fix 2026-06-25 — discovery search responses carry '
              'auth-gated street/buildingNo for authenticated callers; the '
              'error-path logger would otherwise log err.response?.data.',
        );
        expect(
          kAuthPaths,
          isNot(contains('/api/v1/search/masters')),
          reason:
              'Search is permitAll but the token is attached WHEN PRESENT to '
              'unlock addresses; it must NOT be in kAuthPaths (would strip it).',
        );
      },
    );

    test(
      '13d. /api/v1/search/salons is in kPiiPaths (auth-gated address redaction) '
      'but NOT kAuthPaths',
      () {
        expect(
          kPiiPaths,
          contains('/api/v1/search/salons'),
          reason:
              'Security fix 2026-06-25 — discovery search responses carry '
              'auth-gated street/buildingNo for authenticated callers.',
        );
        expect(
          kAuthPaths,
          isNot(contains('/api/v1/search/salons')),
          reason:
              'Search is permitAll but the token is attached WHEN PRESENT to '
              'unlock addresses; it must NOT be in kAuthPaths (would strip it).',
        );
      },
    );

    test('13e. /api/v1/bookings is in kPiiPaths (free-text clientComment redaction) '
        'but NOT kAuthPaths', () {
      expect(
        kPiiPaths,
        contains('/api/v1/bookings'),
        reason:
            'Phase 14.0 — POST /bookings carries the free-text clientComment '
            'field; its body must be redacted in debug logs.',
      );
      expect(
        kAuthPaths,
        isNot(contains('/api/v1/bookings')),
        reason:
            'Authenticated endpoint — must carry a Bearer token; placing it in '
            'kAuthPaths causes AuthInterceptor to skip token injection → 401.',
      );
    });

    test('13f. /api/v1/appointments is in kPiiPaths (free-text clientComment '
        'redaction) but NOT kAuthPaths', () {
      expect(
        kPiiPaths,
        contains('/api/v1/appointments'),
        reason:
            'MO-1 — POST /appointments carries the free-text clientComment '
            'field; its body must be redacted in debug logs.',
      );
      expect(
        kAuthPaths,
        isNot(contains('/api/v1/appointments')),
        reason:
            'Authenticated endpoint — must carry a Bearer token; placing it in '
            'kAuthPaths causes AuthInterceptor to skip token injection → 401.',
      );
    });

    test('13g. /api/v1/client-reviews is in kPiiPaths (free-text comment '
        'redaction) but NOT kAuthPaths', () {
      expect(
        kPiiPaths,
        contains('/api/v1/client-reviews'),
        reason:
            'Track 7.x Wave B — POST /client-reviews carries the provider\'s '
            'free-text comment about the client; its body must be redacted in '
            'debug logs.',
      );
      expect(
        kAuthPaths,
        isNot(contains('/api/v1/client-reviews')),
        reason:
            'Authenticated endpoint — must carry a Bearer token; placing it in '
            'kAuthPaths causes AuthInterceptor to skip token injection → 401.',
      );
    });

    test('13h. /api/v1/favorites is in kPiiPaths (wish-list redaction) but NOT '
        'kAuthPaths', () {
      expect(
        kPiiPaths,
        contains('/api/v1/favorites'),
        reason:
            'Phase 13.x — POST/DELETE /favorites echoes the saved service / '
            'master identifiers (booking-intent PII); its body must be '
            'redacted in debug logs.',
      );
      expect(
        kAuthPaths,
        isNot(contains('/api/v1/favorites')),
        reason:
            'Authenticated endpoint — must carry a Bearer token; placing it in '
            'kAuthPaths causes AuthInterceptor to skip token injection → 401.',
      );
    });

    test('13i. /api/v1/salons/mine is in kPiiPaths (SalonResponse phone + '
        'ownerId redaction) but NOT kAuthPaths', () {
      expect(
        kPiiPaths,
        contains('/api/v1/salons/mine'),
        reason:
            'mobile-security MEDIUM follow-up (2026-08-28) — Phase 21.1 '
            'GET /salons/mine returns SalonResponse, which carries phone and '
            'ownerId; its body must be redacted in debug logs on any 4xx/5xx.',
      );
      expect(
        kAuthPaths,
        isNot(contains('/api/v1/salons/mine')),
        reason:
            'Authenticated endpoint — must carry a Bearer token; placing it in '
            'kAuthPaths causes AuthInterceptor to skip token injection → 401.',
      );
    });

    // -----------------------------------------------------------------------
    // Test 14: exact cardinality — catches undocumented additions/removals
    // -----------------------------------------------------------------------

    test(
      '14. kAuthPaths has exactly 12 entries (unauthenticated endpoints only)',
      () {
        expect(
          kAuthPaths.length,
          equals(12),
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
      // 2026-06-25 address-redaction fix + Phase 14.0 + the MO-1 appointment
      // create endpoint + the track 7.x Wave B client-review create endpoint +
      // the Phase 13.x wish-list toggle endpoint + the Phase 21.1 salons/mine
      // endpoint added 10 authenticated PII paths that are NOT in kAuthPaths).
      expect(
        kPiiPaths.length,
        greaterThan(kAuthPaths.length),
        reason:
            'kPiiPaths must contain additional entries beyond kAuthPaths '
            '(/api/v1/independent-masters/me, /api/v1/independent-masters/me/profile, '
            '/api/v1/masters/me, /api/v1/search/masters, /api/v1/search/salons, '
            '/api/v1/bookings, /api/v1/appointments, /api/v1/client-reviews, '
            '/api/v1/favorites, and /api/v1/salons/mine).',
      );
    });

    test(
      '15. kPiiPaths has exactly 22 entries (kAuthPaths union + 10 authenticated PII paths)',
      () {
        expect(
          kPiiPaths.length,
          equals(22),
          reason:
              'kPiiPaths must equal kAuthPaths (12) plus '
              '/api/v1/independent-masters/me, /api/v1/independent-masters/me/profile, '
              '/api/v1/masters/me, the two auth-gated discovery search paths '
              '/api/v1/search/masters + /api/v1/search/salons, the '
              'Phase 14.0 CLIENT booking create endpoint /api/v1/bookings, '
              'the MO-1 CLIENT appointment create endpoint /api/v1/appointments, '
              'the track 7.x Wave B PROVIDER→CLIENT feedback create '
              'endpoint /api/v1/client-reviews, the Phase 13.x CLIENT '
              'wish-list toggle endpoint /api/v1/favorites, and the Phase '
              '21.1 SALON_OWNER hub endpoint /api/v1/salons/mine '
              '(10 authenticated PII paths = 22 total). The search paths were '
              'added by commit b550428 (auth-gated address redaction); '
              '/api/v1/bookings was added by the Phase 14.0 security fix '
              '(POST /bookings carries the free-text clientComment field); '
              '/api/v1/appointments was added by the MO-1 fix '
              '(POST /appointments carries the free-text clientComment field); '
              '/api/v1/client-reviews was added by track 7.x Wave B '
              '(POST /client-reviews carries the provider\'s free-text comment); '
              '/api/v1/favorites was added by the Phase 13.x wish-list track '
              '(POST/DELETE /favorites echoes the saved service/master ids); '
              '/api/v1/salons/mine was added by the mobile-security MEDIUM '
              'follow-up 2026-08-28 (GET /salons/mine returns SalonResponse, '
              'which carries phone + ownerId). '
              'Update this count if new PII endpoints are added.',
        );
      },
    );

    test('16. kPiiPathPrefixes contains /api/v1/salons/ (Finding 2, PATCH '
        '/salons/{salonId} redaction) — does NOT change test 15\'s count', () {
      expect(
        kPiiPathPrefixes,
        contains('/api/v1/salons/'),
        reason:
            'PATCH /salons/{salonId} carries name/description/street/'
            'buildingNo/locationNote/phone/instagramUrl — a dynamic '
            '{salonId} path, so it must live in kPiiPathPrefixes (not the '
            'exact-match kPiiPaths test 15 counts), mirroring the '
            '/api/v1/bookings/ and /api/v1/appointments/ prefix pairs.',
      );
      // The exact-match /api/v1/salons/mine entry (counted in test 15's 22)
      // is untouched by this prefix addition.
      expect(kPiiPaths, contains('/api/v1/salons/mine'));
      expect(kPiiPaths.length, equals(22));
    });
  });
}
