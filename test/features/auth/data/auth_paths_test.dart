// Unit tests for kAuthPaths constant (core/network/auth_paths.dart).
//
// kAuthPaths is consumed by AuthInterceptor and LoggingInterceptor to determine
// which requests should not carry a Bearer token (or should be logged
// differently). A missing entry causes the interceptor to attach an access
// token to registration requests, leaking the token to an unauthenticated
// endpoint. A stale entry causes protected endpoints to lose their token.
//
// These tests lock the exact set of paths so that any addition or removal to
// _registerEndpoint in HttpAuthRepository or to kAuthPaths itself is caught
// immediately.
//
// Covered scenarios:
//   1. kAuthPaths contains /auth/login.
//   2. kAuthPaths contains /auth/logout.
//   3. kAuthPaths contains /auth/refresh.
//   4. kAuthPaths contains /auth/register (legacy base path).
//   5. kAuthPaths contains /auth/register/independent-master.
//   6. kAuthPaths contains /auth/register/salon-owner (added in Phase 2.6).
//   7. kAuthPaths contains /auth/register/client (added in Phase 2.6).
//   8. kAuthPaths has exactly 7 entries — no undocumented extras.

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

    test('4. contains /auth/register (legacy base path)', () {
      expect(kAuthPaths, contains('/auth/register'));
    });

    test('5. contains /auth/register/independent-master', () {
      expect(kAuthPaths, contains('/auth/register/independent-master'));
    });

    test('6. contains /auth/register/salon-owner (Phase 2.6)', () {
      expect(kAuthPaths, contains('/auth/register/salon-owner'));
    });

    test('7. contains /auth/register/client (Phase 2.6)', () {
      expect(kAuthPaths, contains('/auth/register/client'));
    });

    // -----------------------------------------------------------------------
    // Test 8: exact cardinality — catches undocumented additions
    // -----------------------------------------------------------------------

    test('8. has exactly 7 entries — no undocumented paths', () {
      expect(
        kAuthPaths.length,
        equals(7),
        reason:
            'A path was added to or removed from kAuthPaths without a '
            'corresponding test update. Update this test and confirm the '
            'interceptors handle the new path correctly.',
      );
    });
  });
}
