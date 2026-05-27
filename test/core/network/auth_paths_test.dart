// Tests for kAuthPaths — the shared set of unauthenticated endpoint paths
// used by AuthInterceptor (token injection guard) and LoggingInterceptor
// (body-redaction guard).
//
// Every path that carries PII or must not receive a Bearer token MUST be
// listed here. When a new auth-related endpoint is added, this test file
// should be updated in the same commit (security HIGH gate).

import 'package:beautica_mobile/core/network/auth_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kAuthPaths', () {
    test('includes original login/register/refresh paths', () {
      expect(kAuthPaths, contains('/auth/login'));
      expect(kAuthPaths, contains('/auth/register'));
      expect(kAuthPaths, contains('/auth/register/independent-master'));
      expect(kAuthPaths, contains('/auth/logout'));
      expect(kAuthPaths, contains('/auth/refresh'));
    });

    test('includes Phase 2.11 OTP verification paths', () {
      expect(kAuthPaths, contains('/auth/verify-email'));
      expect(kAuthPaths, contains('/auth/resend-verification'));
    });

    test('includes Phase 2.13 password-reset paths', () {
      expect(kAuthPaths, contains('/auth/forgot-password'));
      expect(kAuthPaths, contains('/auth/reset-password'));
    });

    test('includes Phase 2.20 invite endpoints', () {
      expect(kAuthPaths, contains('/auth/invite/validate'));
      expect(kAuthPaths, contains('/auth/invite/accept'));
    });

    test('is a Set (no duplicate entries)', () {
      expect(kAuthPaths.length, equals(kAuthPaths.toSet().length));
    });

    test('all entries start with a leading slash', () {
      for (final path in kAuthPaths) {
        expect(
          path,
          startsWith('/'),
          reason: '$path must start with "/" to match RequestOptions.path',
        );
      }
    });
  });
}
