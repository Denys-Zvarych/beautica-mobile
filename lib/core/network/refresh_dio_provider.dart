// Phase 2.7 — Clean Dio instance for the token-refresh endpoint.
//
// This provider intentionally has NO interceptors — no AuthInterceptor,
// no LoggingInterceptor, no ErrorMapperInterceptor. A clean Dio is required
// for POST /auth/refresh so that:
//   1. A stale access token is never attached (AuthInterceptor excluded).
//   2. A 401 on the refresh call does NOT trigger another refresh attempt
//      (RefreshInterceptor excluded → prevents infinite loops).
//
// Security invariant (mobile-security MS-CRITICAL):
//   Only [RefreshInterceptor] uses this provider. All other network calls
//   must go through [dioProvider] to get the full interceptor chain.

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../config/app_config.dart';

part 'refresh_dio_provider.g.dart';

/// A clean [Dio] instance used exclusively for `POST /auth/refresh`.
///
/// No auth, logging, or error-mapping interceptors are attached. Kept alive
/// because the [RefreshInterceptor] holds a reference to this instance and
/// is itself kept alive via [dioProvider].
@Riverpod(keepAlive: true)
Dio refreshDio(Ref ref) => Dio(
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
