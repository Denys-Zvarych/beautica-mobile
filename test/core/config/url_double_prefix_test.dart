// Regression guard — URL double-prefix invariant (fix: 2026-05-30).
//
// Root cause:
//   AppConfig.baseUrl previously defaulted to `http://localhost:8080/api/v1`.
//   Every repository path and generated API-client path already includes the
//   full `/api/v1/` segment.  Dio assembles the final URL as
//   `baseUrl + path`, so the combination produced paths such as:
//     http://localhost:8080/api/v1/api/v1/users/me
//   Spring Security returned HTTP 401 for unrecognised paths, and
//   RefreshInterceptor found no refresh token in storage (not yet written),
//   causing it to throw UnauthorizedFailure → "Сесія завершилась" banner
//   immediately after the very first successful login.
//
// Fix applied:
//   - `AppConfig.baseUrl` default changed to `http://localhost:8080`.
//   - All raw Dio paths in master/user/salon/location repositories, plus
//     `kAuthPaths`, `kPiiPaths`, `error_mapper_interceptor.dart`, and
//     `refresh_interceptor.dart` were updated to include the full
//     `/api/v1/` prefix explicitly.
//
// This test suite is the regression gate for that fix.  It has two layers:
//
//   Layer A — `AppConfig.baseUrl` invariant:
//     The default value must NOT contain `/api/v1` anywhere in the string.
//     Checked via substring scan and via the explicit absence of the suffix.
//
//   Layer B — Combined-URL double-prefix check:
//     For every known API path string used in the codebase, the result of
//     `baseUrl + path` must not contain the double-prefix fragment
//     `/api/v1/api/v1/`.  This fires immediately when a developer adds
//     `/api/v1` back to baseUrl OR when they accidentally add a second
//     `/api/v1` prefix inside a repository path.
//
// No Dio, no network, no ProviderScope — pure Dart string assertions.
//
// HOW TO MAINTAIN: when you add a new repository path in any feature's
// `*_repository.dart`, add its path string to [_allKnownApiPaths] below.
// The test will then guard it automatically.

import 'package:beautica_mobile/core/config/app_config.dart';
import 'package:beautica_mobile/core/network/auth_paths.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Catalogue of every known raw Dio path used by feature repositories and
// network interceptors.  Update this list whenever a new path is introduced.
// ---------------------------------------------------------------------------

/// All hand-written Dio paths declared in feature repositories.
///
/// These are the strings passed directly to `_dio.get(...)`, `_dio.post(...)`,
/// `_dio.patch(...)`, etc.  Generated API-client paths are not listed here
/// because they are exercised by the generated client's own tests; what matters
/// is that any path we compose manually cannot produce a double-prefix.
const List<String> _repositoryPaths = [
  // master_repository.dart
  '/api/v1/independent-masters/me',
  '/api/v1/independent-masters/me/profile',
  // user_repository.dart
  '/api/v1/users/me',
  // salon_repository.dart
  '/api/v1/salons',
  // location_repository.dart
  '/api/v1/locations/oblasts',
  '/api/v1/locations/oblasts/some-oblast-id/cities',
  '/api/v1/locations/cities/some-city-id/districts',
  // refresh_interceptor.dart
  '/api/v1/auth/refresh',
];

/// All paths in `kAuthPaths` and `kPiiPaths` from `auth_paths.dart`.
///
/// These are matched against `RequestOptions.path` which Dio populates with the
/// raw path string (no base URL prepended at the interceptor level). We still
/// guard against a hypothetical regression where someone re-adds `/api/v1`
/// to the base URL, which would make `baseUrl + interceptorPath` double-prefixed.
final List<String> _interceptorPaths = [
  ...kAuthPaths,
  ...kPiiPaths,
];

// ---------------------------------------------------------------------------
// Combined path set (deduplicated).
// ---------------------------------------------------------------------------

final List<String> _allKnownApiPaths = {
  ..._repositoryPaths,
  ..._interceptorPaths,
}.toList();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('URL double-prefix invariant', () {
    // -------------------------------------------------------------------------
    // Layer A — AppConfig.baseUrl must not embed /api/v1
    // -------------------------------------------------------------------------

    test(
      'AppConfig.baseUrl default does not contain /api/v1 (substring check)',
      () {
        expect(
          AppConfig.baseUrl.contains('/api/v1'),
          isFalse,
          reason:
              'AppConfig.baseUrl must NOT include the /api/v1 prefix. '
              'The generated API client and all raw Dio calls already include '
              '/api/v1/ in every path. A baseUrl that embeds /api/v1 causes '
              'double-prefix URLs (e.g. http://host:8080/api/v1/api/v1/users/me) '
              'which Spring Security blocks with HTTP 401. '
              'Current value: "${AppConfig.baseUrl}".',
        );
      },
    );

    test(
      'AppConfig.baseUrl default does not end with /api/v1',
      () {
        expect(
          AppConfig.baseUrl.endsWith('/api/v1'),
          isFalse,
          reason:
              'AppConfig.baseUrl must not end with /api/v1. '
              'Got: "${AppConfig.baseUrl}".',
        );
      },
    );

    test(
      'AppConfig.baseUrl default does not end with /api/v1/ (trailing slash variant)',
      () {
        expect(
          AppConfig.baseUrl.endsWith('/api/v1/'),
          isFalse,
          reason:
              'AppConfig.baseUrl must not end with /api/v1/. '
              'Got: "${AppConfig.baseUrl}".',
        );
      },
    );

    // -------------------------------------------------------------------------
    // Layer B — baseUrl + path must never produce /api/v1/api/v1/
    // -------------------------------------------------------------------------

    test(
      'no known API path produces a double-prefix when appended to AppConfig.baseUrl',
      () {
        const doublePrefix = '/api/v1/api/v1/';
        final base = AppConfig.baseUrl;

        final violations = <String>[];

        for (final path in _allKnownApiPaths) {
          final combined = base + path;
          if (combined.contains(doublePrefix)) {
            violations.add('  "$combined"  (path: "$path")');
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'The following combined URLs contain the double-prefix '
              '"$doublePrefix", which Spring Security rejects with HTTP 401:\n'
              '${violations.join('\n')}\n\n'
              'Fix: ensure AppConfig.baseUrl does not include /api/v1, OR '
              'remove the /api/v1 prefix from the offending path constant.',
        );
      },
    );

    // -------------------------------------------------------------------------
    // Layer C — every known API path starts with /api/v1/ (convention enforcement)
    //
    // Enforces that ALL raw Dio paths are written with the full prefix.  A path
    // that lacks the prefix (e.g. `/auth/login`) silently hits the wrong URL
    // when AppConfig.baseUrl is a plain host — which is exactly the situation
    // that existed before the 2026-05-30 fix.
    // -------------------------------------------------------------------------

    test(
      'every repository path starts with /api/v1/ (full-path convention)',
      () {
        final nonCompliant = _repositoryPaths
            .where((p) => !p.startsWith('/api/v1/'))
            .toList();

        expect(
          nonCompliant,
          isEmpty,
          reason:
              'The following repository paths do not start with "/api/v1/". '
              'All raw Dio paths must include the full API version prefix '
              'because AppConfig.baseUrl no longer carries it:\n'
              '${nonCompliant.map((p) => '  "$p"').join('\n')}',
        );
      },
    );

    test(
      'every kAuthPaths entry starts with /api/v1/ (full-path convention)',
      () {
        final nonCompliant = kAuthPaths
            .where((p) => !p.startsWith('/api/v1/'))
            .toList();

        expect(
          nonCompliant,
          isEmpty,
          reason:
              'The following kAuthPaths entries do not start with "/api/v1/". '
              'AuthInterceptor matches paths against RequestOptions.path which '
              'contains the raw path passed to Dio — missing the prefix means '
              'the interceptor will not skip token injection on these endpoints:\n'
              '${nonCompliant.map((p) => '  "$p"').join('\n')}',
        );
      },
    );

    test(
      'every kPiiPaths entry starts with /api/v1/ (full-path convention)',
      () {
        final nonCompliant = kPiiPaths
            .where((p) => !p.startsWith('/api/v1/'))
            .toList();

        expect(
          nonCompliant,
          isEmpty,
          reason:
              'The following kPiiPaths entries do not start with "/api/v1/". '
              'LoggingInterceptor matches paths against RequestOptions.path — '
              'missing the prefix means bodies for these paths will NOT be '
              'redacted in debug logs, leaking PII:\n'
              '${nonCompliant.map((p) => '  "$p"').join('\n')}',
        );
      },
    );

    // -------------------------------------------------------------------------
    // Layer D — catalogue completeness cross-check
    //
    // The repository-path catalogue above must not contain duplicates (a
    // duplicate would mask a test that should fire twice and draws attention to
    // accidentally-added copy-paste paths).
    // -------------------------------------------------------------------------

    test('_repositoryPaths catalogue contains no duplicate entries', () {
      final seen = <String>{};
      final duplicates = <String>[];
      for (final p in _repositoryPaths) {
        if (!seen.add(p)) duplicates.add(p);
      }
      expect(
        duplicates,
        isEmpty,
        reason:
            'Duplicate entries in _repositoryPaths:\n'
            '${duplicates.map((p) => '  "$p"').join('\n')}\n'
            'Remove duplicates or split into separate named constants.',
      );
    });
  });
}
