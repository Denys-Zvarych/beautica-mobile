// TODO(phase-3.2): replace hand-written DTOs with imports from lib/api/ (generated AuthApi).
//
// Phase 2.3 — HttpAuthRepository.
// Phase 2.8 — Added SecureStorage injection + logout() implementation.
//
// Concrete implementation of [AuthRepository] backed by the Beautica backend
// REST API. Uses the singleton [dioProvider] Dio instance which carries the
// full interceptor chain (Auth → Log → ErrorMapper → Refresh).
//
// Backend response envelope for all endpoints:
//   { "success": bool, "data": T, "message": String }
//
// This class extracts `data` from `response.data['data']`. Field-level
// naming follows the backend DTOs as of Phase 2.x; Phase 3.2 will replace
// these raw Map accesses with generated type-safe API classes.

import 'dart:async';
import 'dart:developer';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../domain/auth_tokens.dart';
import '../domain/user.dart';
import 'auth_repository.dart';

/// HTTP implementation of [AuthRepository].
///
/// Inject via [authRepositoryProvider] — never construct directly.
final class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._dio, this._storage);

  final Dio _dio;

  /// Used exclusively by [logout] to read the current refresh token so it can
  /// be revoked on the backend. Never used for access tokens.
  final SecureStorage _storage;

  /// Guards against concurrent refresh races: if a refresh call is already
  /// in-flight, subsequent callers await the same [Completer] instead of
  /// issuing duplicate network requests.
  Completer<AuthTokens>? _pendingRefresh;

  // ---------------------------------------------------------------------------
  // AuthRepository
  // ---------------------------------------------------------------------------

  @override
  Future<(User, AuthTokens)> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      return _parseUserAndTokens(response.data!);
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'login failed: ${e.type} ${e.response?.statusCode}',
          name: 'auth.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<(User, AuthTokens)> registerIndependentMaster({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/register/independent-master',
        data: {
          'email': email,
          'password': password,
          'firstName': firstName,
          'lastName': lastName,
        },
      );
      return _parseUserAndTokens(response.data!);
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'registerIndependentMaster failed: ${e.type} ${e.response?.statusCode}',
          name: 'auth.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    // If a refresh is already in-flight, reuse its result rather than
    // issuing a duplicate request (e.g. two expired requests racing).
    if (_pendingRefresh != null) return _pendingRefresh!.future;

    _pendingRefresh = Completer<AuthTokens>();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = response.data!['data'] as Map<String, dynamic>;
      final result = AuthTokens(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      _pendingRefresh!.complete(result);
      return result;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'refresh failed',
          name: 'auth.repository',
          level: 1000,
          error: '${e.type} ${e.response?.statusCode}',
          stackTrace: st,
        );
      }
      final failure = _mapDioException(e);
      _pendingRefresh!.completeError(failure, st);
      throw failure;
    } finally {
      _pendingRefresh = null;
    }
  }

  @override
  Future<User> me() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/user/me');
      final data = response.data!['data'] as Map<String, dynamic>;
      return User.fromJson(data);
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'me failed',
          name: 'auth.repository',
          level: 1000,
          error: '${e.type} ${e.response?.statusCode}',
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> logout() async {
    final rt = await _storage.readRefreshToken();
    if (rt == null) return; // nothing to revoke

    try {
      await _dio.post<void>('/auth/logout', data: {'refreshToken': rt});
    } on DioException catch (e) {
      // Best-effort: 4xx / network errors are intentionally swallowed.
      // The caller wipes local storage unconditionally after this returns.
      if (kDebugMode) {
        log(
          'logout server call failed (tolerated): ${e.type} ${e.response?.statusCode}',
          name: 'auth.repository',
          level: 900,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Extracts the `{ user, accessToken, refreshToken }` shape from the backend
  /// envelope and returns the domain tuple.
  (User, AuthTokens) _parseUserAndTokens(Map<String, dynamic> envelope) {
    final data = envelope['data'] as Map<String, dynamic>;
    final user = User.fromJson(data['user'] as Map<String, dynamic>);
    final tokens = AuthTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
    );
    return (user, tokens);
  }

  /// Maps a [DioException] to a typed [Failure].
  ///
  /// If [ErrorMapperInterceptor] has already attached a [Failure] as
  /// `e.error`, that value is re-thrown directly. Otherwise a catch-all
  /// [UnknownFailure] is returned. Raw [DioException] must never escape this
  /// class.
  Failure _mapDioException(DioException e) {
    if (e.error is Failure) return e.error as Failure;
    return UnknownFailure(cause: e);
  }
}
