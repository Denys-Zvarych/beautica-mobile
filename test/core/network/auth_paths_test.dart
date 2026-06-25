// Tests for kAuthPaths — the shared set of unauthenticated endpoint paths
// used by AuthInterceptor (token injection guard) and LoggingInterceptor
// (body-redaction guard).
//
// Every path that carries PII or must not receive a Bearer token MUST be
// listed here. When a new auth-related endpoint is added, this test file
// should be updated in the same commit (security HIGH gate).
//
// IMPORTANT (2026-05-30): All paths include the full `/api/v1/` prefix because
// AppConfig.baseUrl no longer carries the `/api/v1` segment. The generated
// API client and all raw Dio calls use `/api/v1/...` paths directly, so
// RequestOptions.path always contains the full prefix when interceptors run.

import 'package:beautica_mobile/core/network/auth_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kAuthPaths', () {
    test(
      'includes original login/register/refresh paths (with /api/v1 prefix)',
      () {
        expect(kAuthPaths, contains('/api/v1/auth/login'));
        expect(kAuthPaths, contains('/api/v1/auth/register'));
        expect(
          kAuthPaths,
          contains('/api/v1/auth/register/independent-master'),
        );
        expect(kAuthPaths, contains('/api/v1/auth/logout'));
        expect(kAuthPaths, contains('/api/v1/auth/refresh'));
      },
    );

    test(
      'includes Phase 2.11 OTP verification paths (with /api/v1 prefix)',
      () {
        expect(kAuthPaths, contains('/api/v1/auth/verify-email'));
        expect(kAuthPaths, contains('/api/v1/auth/resend-verification'));
      },
    );

    test('includes Phase 2.13 password-reset paths (with /api/v1 prefix)', () {
      expect(kAuthPaths, contains('/api/v1/auth/forgot-password'));
      expect(kAuthPaths, contains('/api/v1/auth/reset-password'));
    });

    test('includes Phase 2.20 invite endpoints (with /api/v1 prefix)', () {
      expect(kAuthPaths, contains('/api/v1/auth/invite/validate'));
      expect(kAuthPaths, contains('/api/v1/auth/invite/accept'));
    });

    test(
      'Phase 4.2 master profile endpoints are in kPiiPaths (body redaction), NOT kAuthPaths (token skip)',
      () {
        expect(
          kPiiPaths,
          contains('/api/v1/independent-masters/me'),
          reason:
              'street/buildingNo/locationNote are PII; LoggingInterceptor must '
              'redact the request body when this path is called.',
        );
        expect(
          kPiiPaths,
          contains('/api/v1/masters/me'),
          reason:
              'street/buildingNo/locationNote are PII; LoggingInterceptor must '
              'redact the request body when this path is called.',
        );
        expect(
          kAuthPaths,
          isNot(contains('/api/v1/independent-masters/me')),
          reason:
              'Authenticated endpoints must not be in kAuthPaths — AuthInterceptor '
              'skips Bearer token injection for paths in this set, which would '
              'cause a 401 on PATCH /api/v1/independent-masters/me.',
        );
        expect(
          kAuthPaths,
          isNot(contains('/api/v1/masters/me')),
          reason:
              'Same as above — /api/v1/masters/me is an authenticated endpoint.',
        );
      },
    );

    test('is a Set (no duplicate entries)', () {
      expect(kAuthPaths.length, equals(kAuthPaths.toSet().length));
    });

    test('all entries start with /api/v1/ (enforces full-path convention)', () {
      for (final path in kAuthPaths) {
        expect(
          path,
          startsWith('/api/v1/'),
          reason:
              '$path must start with "/api/v1/" — AppConfig.baseUrl no longer '
              'carries the /api/v1 prefix, so all paths must include it '
              'explicitly to match what the generated API client sends as '
              'RequestOptions.path.',
        );
      }
    });
  });

  group('kPublicPathPrefixes', () {
    test('includes the public location reference-data prefix', () {
      expect(
        kPublicPathPrefixes,
        contains('/api/v1/locations/'),
        reason:
            'Location reference-data reads are public — AuthInterceptor must '
            'skip Bearer token injection on /api/v1/locations/*.',
      );
    });

    test('does NOT include the discovery search prefix (auth-gated address fix, '
        '2026-06-25)', () {
      // REVERSAL of the earlier (2026-06-18) entry. The discovery search
      // endpoints are permitAll, but the backend auth-gates the
      // street/buildingNo address fields on the authenticated principal.
      // Listing '/api/v1/search/' here forced AuthInterceptor to STRIP the
      // Bearer token from every search call → the app was always anonymous →
      // full addresses were permanently null. The prefix is therefore REMOVED
      // so the interceptor attaches the token WHEN present (logged-in →
      // addresses) and sends anonymously when absent (logged-out → still
      // works). See auth_interceptor_test.dart Tests 7 & 8.
      expect(
        kPublicPathPrefixes,
        isNot(contains('/api/v1/search/')),
        reason:
            'The search prefix must NOT be public-listed: doing so strips the '
            'Bearer token and kills the auth-gated address feature. Token '
            'injection on /search/* is conditional on a session (see '
            'auth_interceptor.dart), not suppressed by a public prefix.',
      );
    });

    test(
      'discovery search paths are redacted in logs via kPiiPaths (they carry '
      'auth-gated address PII)',
      () {
        // The search responses carry street/buildingNo for authenticated
        // callers; the error-path logger logs response bodies, so these exact
        // paths must be in kPiiPaths for body redaction.
        expect(kPiiPaths, contains('/api/v1/search/masters'));
        expect(kPiiPaths, contains('/api/v1/search/salons'));
      },
    );

    test('every prefix starts with /api/v1/ and ends with / (prefix-match '
        'convention)', () {
      for (final prefix in kPublicPathPrefixes) {
        expect(
          prefix,
          startsWith('/api/v1/'),
          reason:
              '$prefix must start with "/api/v1/" — RequestOptions.path carries '
              'the full prefix when interceptors run.',
        );
        expect(
          prefix,
          endsWith('/'),
          reason:
              '$prefix should end with "/" so startsWith does not accidentally '
              'match a sibling path (e.g. /api/v1/searchable).',
        );
      }
    });
  });
}
