// Phase 2.2 — Dio singleton provider.
//
// This is the single [Dio] instance used for all authenticated API calls.
// Do NOT call `Dio()` anywhere in lib/features/ — always use
// `ref.watch(dioProvider)` or `ref.read(dioProvider)`.
//
// Interceptor order (matters!):
//   1. AuthInterceptor   — attaches Bearer token to outgoing requests.
//   2. LoggingInterceptor — logs traffic; debug builds only.
//   3. ErrorMapperInterceptor — converts DioException → typed Failure.
//   4. RefreshInterceptor — handles 401 retry (Phase 2.7, placeholder comment).
//
// A separate `refreshDioProvider` with NO auth interceptor will be added in
// Phase 2.7 for the token-refresh flow, to avoid circular requests.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../config/app_config.dart';
import 'auth_interceptor.dart';
import 'error_mapper_interceptor.dart';
import 'logging_interceptor.dart';

part 'dio_provider.g.dart';

/// Authenticated [Dio] client wired with the full interceptor chain.
///
/// Kept alive for the lifetime of the app — a single instance is reused
/// across all API calls. The interceptors hold a [Ref] reference and read
/// providers lazily, so there is no circular dependency at construction time.
@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  // Throws in release builds if BEAUTICA_BASE_URL is not HTTPS.
  AppConfig.assertSecureUrl();

  final d = Dio(
    BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
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
    // RefreshInterceptor — Phase 2.7
  ]);

  return d;
}
