// Phase 2.2 — Dio singleton provider.
// Phase 2.7 — RefreshInterceptor added after ErrorMapperInterceptor.
// Phase MEDIUM-3 — iOS cert-pinning (mobile-security 2026-05-27).
//
// This is the single [Dio] instance used for all authenticated API calls.
// Do NOT call `Dio()` anywhere in lib/features/ — always use
// `ref.watch(dioProvider)` or `ref.read(dioProvider)`.
//
// Interceptor order (matters!):
//   1. AuthInterceptor         — attaches Bearer token to outgoing requests.
//   2. LoggingInterceptor      — logs traffic; debug builds only.
//   3. ErrorMapperInterceptor  — converts DioException → typed Failure.
//   4. RefreshInterceptor      — handles 401 retry with silent token refresh.
//
// A separate [refreshDioProvider] with NO interceptors is used by
// [RefreshInterceptor] for POST /auth/refresh to avoid circular requests.
//
// Cert-pinning architecture (MEDIUM-3):
//   [initCertPinning] is called from main() before runApp(). It loads the
//   ISRG Root X1 PEM from the Flutter asset bundle and constructs a
//   [SecurityContext] that trusts ONLY that root. The context is cached in
//   [_cachedSecurityContext]. When [dioProvider] builds the Dio instance it
//   reads the cached context and wires [IOHttpClientAdapter] so every TLS
//   connection is verified against the pinned root.
//
//   This approach keeps [dioProvider] synchronous (no call-site API change)
//   while guaranteeing the pin is in effect before the first network call.
//   On Android this supplements network_security_config.xml (belt-and-suspenders).
//   On iOS this is the only pin (no OS-level equivalent to Android's config).

import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../config/app_config.dart';
import 'auth_interceptor.dart';
import 'error_mapper_interceptor.dart';
import 'logging_interceptor.dart';
import 'refresh_interceptor.dart';

part 'dio_provider.g.dart';

// ---------------------------------------------------------------------------
// Cert-pinning initialisation — called once from main() before runApp().
// ---------------------------------------------------------------------------

/// Cached [SecurityContext] built from the pinned ISRG Root X1 PEM.
///
/// `null` until [initCertPinning] completes. If [initCertPinning] fails in
/// a non-debug build the exception propagates and prevents app startup,
/// ensuring the app never runs without pinning in production.
SecurityContext? _cachedSecurityContext;

/// Loads the ISRG Root X1 PEM from the Flutter asset bundle and caches a
/// [SecurityContext] that trusts only that root.
///
/// MUST be awaited before [runApp]. The cached context is read by
/// [dioProvider] when it constructs the [IOHttpClientAdapter].
///
/// In debug builds a cert-loading failure is logged and the app continues
/// with system-trust fallback (acceptable for local dev against non-pinned
/// backends). In release builds the exception is rethrown — fail-closed is
/// the correct behaviour.
Future<void> initCertPinning() async {
  try {
    final pemBytes = await rootBundle.load('assets/certs/isrg_root_x1.pem');
    _cachedSecurityContext = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(pemBytes.buffer.asUint8List());
    log(
      'Cert-pinning initialised (ISRG Root X1)',
      name: 'network.cert',
      level: 800,
    );
  } catch (e, st) {
    log(
      'Cert-pinning setup failed',
      name: 'network.cert',
      level: 1000,
      error: e,
      stackTrace: st,
    );
    if (!kDebugMode) {
      // Fail closed in release mode — never silently degrade to system trust.
      rethrow;
    }
    // Debug mode: fall back to system trust so local dev against non-pinned
    // backends still works.
  }
}

// ---------------------------------------------------------------------------
// Authenticated Dio provider
// ---------------------------------------------------------------------------

/// Authenticated [Dio] client wired with the full interceptor chain.
///
/// Kept alive for the lifetime of the app — a single instance is reused
/// across all API calls. The interceptors hold a [Ref] reference and read
/// providers lazily, so there is no circular dependency at construction time.
///
/// The [IOHttpClientAdapter] is configured with the [SecurityContext] cached
/// by [initCertPinning] (called from main() before runApp). On platforms where
/// [IOHttpClientAdapter] is not available (web) the adapter is left as-is.
@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  // Throws in release builds if BEAUTICA_BASE_URL is not HTTPS.
  AppConfig.assertSecureUrl();

  final d = Dio(
    BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      // sendTimeout guards the request-write phase (a stalled upload / slow
      // request body). Without it a hung send never fires a DioException and a
      // dependent provider (e.g. serviceTypesProvider) would spin forever — the
      // root cause of the "Тип послуги loads forever" report. A send timeout
      // maps through ServiceRepository._mapDioException → NetworkFailure → the
      // dropdown's retryable error state.
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  d.interceptors.addAll([
    AuthInterceptor(ref),
    if (kDebugMode) LoggingInterceptor(),
    ErrorMapperInterceptor(),
    RefreshInterceptor(ref, d),
  ]);

  // Wire cert-pinning via IOHttpClientAdapter when the cached SecurityContext
  // is available. On web (where dart:io is absent) this is a no-op.
  final sc = _cachedSecurityContext;
  if (sc != null) {
    d.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient(context: sc),
    );
  }

  return d;
}
