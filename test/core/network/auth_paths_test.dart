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
}
