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

  // ── Query-string redaction (security fix 2026-06-28) ─────────────────────
  //
  // redactLogPath() now has TWO layers:
  //   • PII routes (isPiiPath) → the ENTIRE query string is masked
  //     as `?[REDACTED]` (even the param names can be revealing there).
  //   • every other route → the VALUE of any kSensitiveQueryKeys param is
  //     masked as `key=***`, while harmless params (page / size / sort) stay
  //     visible for debugging.
  //
  // These tests assert no sensitive value can survive into the log line, that
  // debug-useful params are preserved, that key matching is case-insensitive,
  // and that malformed query strings degrade safely (no throw).
  group('kSensitiveQueryKeys', () {
    test('covers the free-text + credential param names (lower-case)', () {
      for (final String key in <String>[
        'q',
        'query',
        'search',
        'token',
        'access_token',
        'refresh_token',
        'code',
        'otp',
        'password',
        'secret',
        'email',
        'phone',
      ]) {
        expect(
          kSensitiveQueryKeys,
          contains(key),
          reason: '"$key" carries PII / credentials and must be value-masked',
        );
      }
    });

    test('does NOT list the harmless pagination/sort keys', () {
      expect(kSensitiveQueryKeys, isNot(contains('page')));
      expect(kSensitiveQueryKeys, isNot(contains('size')));
      expect(kSensitiveQueryKeys, isNot(contains('sort')));
    });
  });

  group('redactLogPath', () {
    test('PII route: search q free-text is fully redacted (value absent)', () {
      // /api/v1/search/* is a PII prefix → the WHOLE query is masked, so the
      // typed person/business name can never reach the log.
      const String path = '/api/v1/search/masters?q=Олена%20Тест&page=2';
      final String out = redactLogPath(path);

      expect(out, equals('/api/v1/search/masters?[REDACTED]'));
      expect(
        out,
        isNot(contains('Олена')),
        reason: 'the free-text search term must never appear in the log line',
      );
      expect(out, isNot(contains('q=')));
    });

    test('non-PII route: token value masked; page & sort stay visible', () {
      // /api/v1/service-categories/approved is NOT a PII route (public
      // reference-data list, no free-text/PII body), so the per-key value
      // mask applies: the credential value disappears while debug-useful
      // params survive.
      const String path =
          '/api/v1/service-categories/approved?token=abc123&page=2&sort=name';
      final String out = redactLogPath(path);

      expect(out, contains('token=***'));
      expect(
        out,
        isNot(contains('abc123')),
        reason: 'the token VALUE must be masked even on a non-PII route',
      );
      expect(out, contains('page=2'), reason: 'pagination stays visible');
      expect(out, contains('sort=name'), reason: 'sort stays visible');
    });

    test('key matching is case-insensitive (TOKEN masked like token)', () {
      const String path = '/api/v1/service-categories/approved?TOKEN=abc123';
      final String out = redactLogPath(path);

      expect(out, contains('TOKEN=***'));
      expect(
        out,
        isNot(contains('abc123')),
        reason: 'kSensitiveQueryKeys is matched case-insensitively',
      );
    });

    test('repeated sensitive params: every occurrence is masked', () {
      const String path =
          '/api/v1/service-categories/approved?token=aaa&token=bbb&page=1';
      final String out = redactLogPath(path);

      expect(out, isNot(contains('aaa')));
      expect(out, isNot(contains('bbb')));
      expect(out, contains('page=1'));
      // Both token pairs present, both masked.
      expect('token=***'.allMatches(out).length, equals(2));
    });

    test('malformed query strings degrade safely (no throw, sane output)', () {
      const String base = '/api/v1/service-categories/approved';

      // Trailing '?' with empty query → original path returned unchanged.
      expect(() => redactLogPath('$base?'), returnsNormally);
      expect(redactLogPath('$base?'), equals('$base?'));

      // Empty pairs from a doubled '&' must not crash.
      expect(() => redactLogPath('$base?a&&b'), returnsNormally);
      expect(redactLogPath('$base?a&&b'), equals('$base?a&&b'));

      // Key without '=' (no value to leak) is left as-is, no crash.
      expect(() => redactLogPath('$base?token'), returnsNormally);
      expect(redactLogPath('$base?token'), equals('$base?token'));
    });

    test('path without a query string is returned unchanged', () {
      expect(redactLogPath('/api/v1/bookings'), equals('/api/v1/bookings'));
    });

    // ── MO-1 — appointment (multi-service visit) PII paths ──────────────────
    //
    // The visit endpoints carry the SAME PII the single-service booking
    // endpoints do (enriched master name/address/price + free-text
    // clientComment / providerComment / clientCancellationNote):
    //   POST  /api/v1/appointments                 (create — clientComment)
    //   GET   /api/v1/appointments/{id}            (detail — full enrichment)
    //   PATCH /api/v1/appointments/{id}/cancel     (clientCancellationNote)
    //   POST  /api/v1/appointments/{id}/review     (free-text comment)
    // They MUST be classified PII so LoggingInterceptor redacts request AND
    // response bodies (the error-path logger logs response bodies otherwise).
    // Mirrors the `/api/v1/bookings` (exact) + `/api/v1/bookings/` (prefix)
    // pair. This is the tripwire guarding the mobile-security allowlist fix —
    // if the exact-`/appointments` entry or the `/appointments/` prefix is ever
    // removed, these fail loudly.
    test('bare POST /appointments is a PII route (redacted)', () {
      expect(
        isPiiPath('/api/v1/appointments'),
        isTrue,
        reason:
            'POST /appointments carries free-text clientComment — its body '
            'must be redacted in debug logs, exactly like POST /bookings.',
      );
    });

    test('appointment sub-routes ({id}/cancel/review) are PII routes', () {
      expect(
        isPiiPath('/api/v1/appointments/appt-123'),
        isTrue,
        reason:
            'GET /appointments/{id} returns enriched master address + notes — '
            'PII that must be redacted, like GET /bookings/{id}.',
      );
      expect(
        isPiiPath('/api/v1/appointments/appt-123/cancel'),
        isTrue,
        reason:
            'PATCH .../cancel carries the free-text clientCancellationNote.',
      );
      expect(
        isPiiPath('/api/v1/appointments/appt-123/review'),
        isTrue,
        reason: 'POST .../review carries the free-text review comment.',
      );
    });

    test('a PII appointment path has its whole query string redacted', () {
      expect(
        redactLogPath('/api/v1/appointments/appt-123?token=secret'),
        equals('/api/v1/appointments/appt-123?[REDACTED]'),
      );
    });

    test('auth/PII token route: whole query redacted (token value absent)', () {
      // /api/v1/auth/verify-email is an exact kPiiPaths member → full mask,
      // including the param NAME, not just its value.
      const String path = '/api/v1/auth/verify-email?token=secretLinkToken123';
      final String out = redactLogPath(path);

      expect(out, equals('/api/v1/auth/verify-email?[REDACTED]'));
      expect(
        out,
        isNot(contains('secretLinkToken123')),
        reason: 'the verify-email link token must never reach the log',
      );
    });
  });
}
