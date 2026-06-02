// Regression safety net (2026-06-02) — Fix 3 (static contract-drift guard).
//
// The "double /api/v1 prefix" bug class:
//   AppConfig.baseUrl is documented to NOT carry the /api/v1 prefix, because
//   BOTH the generated client paths (e.g. '/api/v1/masters/me') AND the raw Dio
//   calls in HttpMasterRepository (e.g. '/api/v1/independent-masters/me/profile')
//   already include the full /api/v1/ segment. If baseUrl ends with /api/v1 the
//   assembled URL becomes '.../api/v1/api/v1/...' which Spring Security rejects
//   with 401/404 — every authenticated call silently fails ("save → nothing
//   persists" from the user's point of view).
//
// This static suite pins both halves of the invariant so a future change to
// either side (baseUrl default, or a generated/raw path) trips the build:
//   1. AppConfig.baseUrl must NOT end with '/api/v1' (any trailing slash).
//   2. The generated client paths DO begin with '/api/v1/' (single prefix).
//   3. Composing baseUrl + a generated path never yields a double prefix.
//
// Runs with no live backend. See also master_repository_transport_test.dart
// (Fix 1) for the real-Dio wire assertions, and scripts/regenerate_api.sh
// --check (Fix 3 CI job) for spec-vs-client drift.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/config/app_config.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig.baseUrl / generated-path consistency', () {
    test('baseUrl does NOT end with /api/v1 (no double-prefix source)', () {
      final normalized = AppConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
      expect(
        normalized.endsWith('/api/v1'),
        isFalse,
        reason:
            'AppConfig.baseUrl must NOT include the /api/v1 prefix — the '
            'generated client and the raw Dio repository calls already prepend '
            'it. A baseUrl ending in /api/v1 produces .../api/v1/api/v1/... '
            'which Spring rejects with 401/404.',
      );
    });

    test('baseUrl does not contain an /api/v1 segment at all', () {
      expect(
        AppConfig.baseUrl.contains('/api/v1'),
        isFalse,
        reason:
            'No /api/v1 segment belongs in baseUrl; it lives only in the '
            'per-endpoint paths.',
      );
    });

    test('generated MasterControllerApi resolves a single /api/v1/ prefix '
        'against a clean baseUrl (no double prefix)', () async {
      // Build a real Dio with the production-shaped baseUrl, hand it to the
      // generated API, and capture the path that Dio would actually request.
      // We do NOT need a server — we abort the request inside an interceptor
      // and read the resolved RequestOptions.uri.
      final dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));

      String? resolvedPath;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            resolvedPath = options.uri.path;
            // Reject so no socket is opened; we only care about the path.
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
              ),
              true,
            );
          },
        ),
      );

      final api = MasterControllerApi(dio, standardSerializers);
      try {
        await api.getMyProfile();
      } on DioException {
        // expected — request was rejected after path capture
      }

      expect(resolvedPath, isNotNull);
      expect(
        resolvedPath,
        '/api/v1/masters/me',
        reason:
            'GET /masters/me must resolve to exactly /api/v1/masters/me — '
            'a double prefix would read /api/v1/api/v1/masters/me.',
      );
      expect(
        resolvedPath!.contains('/api/v1/api/v1'),
        isFalse,
        reason: 'double /api/v1 prefix detected — baseUrl is mis-configured.',
      );
    });
  });
}
