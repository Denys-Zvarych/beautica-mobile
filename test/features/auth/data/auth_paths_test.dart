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
// Covered scenarios:
//   1. kAuthPaths contains /auth/login.
//   2. kAuthPaths contains /auth/logout.
//   3. kAuthPaths contains /auth/refresh.
//   4. kAuthPaths contains /auth/register (CLIENT + SALON_OWNER unified endpoint).
//   5. kAuthPaths contains /auth/register/independent-master.
//   6. kAuthPaths has exactly 5 entries — no undocumented extras.

import 'package:beautica_mobile/core/network/auth_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kAuthPaths', () {
    // -----------------------------------------------------------------------
    // Tests 1–5: required entries
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

    test('4. contains /auth/register (CLIENT + SALON_OWNER unified endpoint)', () {
      expect(kAuthPaths, contains('/auth/register'));
    });

    test('5. contains /auth/register/independent-master', () {
      expect(kAuthPaths, contains('/auth/register/independent-master'));
    });

    // -----------------------------------------------------------------------
    // Test 6: exact cardinality — catches undocumented additions/removals
    // -----------------------------------------------------------------------

    test('6. has exactly 5 entries — no undocumented paths', () {
      expect(
        kAuthPaths.length,
        equals(5),
        reason:
            'A path was added to or removed from kAuthPaths without a '
            'corresponding test update. Update this test and confirm the '
            'interceptors handle the new path correctly.',
      );
    });
  });
}
