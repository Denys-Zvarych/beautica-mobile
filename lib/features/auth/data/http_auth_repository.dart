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
import '../domain/user_role.dart';
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
    UserRole role = UserRole.independentMaster,
    String? businessName,
    String? address,
    String? phone,
  }) async {
    // Backend contract:
    //   INDEPENDENT_MASTER → POST /auth/register/independent-master
    //     Body: { email, password, firstName, lastName, phoneNumber? }
    //     Note: no `role` field; backend derives it from the path.
    //
    //   CLIENT → POST /auth/register
    //     Body: { email, password, role, firstName, lastName }
    //
    //   SALON_OWNER → POST /auth/register
    //     Body: { email, password, role, firstName, lastName, businessName?,
    //             address?, phoneNumber? }
    //     Note: `businessName` is REQUIRED when role == SALON_OWNER.
    //     Note: firstName/lastName are sent as empty strings for salon owners
    //           because the backend schema still requires the fields; the
    //           meaningful identity for a salon owner is businessName + address.
    try {
      final Response<Map<String, dynamic>> response;

      if (role == UserRole.independentMaster) {
        // Phone is now required for all roles (Change 7).
        // Use a local trimmed variable to avoid calling .trim() twice
        // (backlog pattern 5).
        final trimmedPhone = phone?.trim();
        final imBody = <String, dynamic>{
          'email': email,
          'password': password,
          'firstName': firstName,
          'lastName': lastName,
        };
        if (trimmedPhone != null && trimmedPhone.isNotEmpty) {
          imBody['phoneNumber'] = trimmedPhone;
        }
        response = await _dio.post<Map<String, dynamic>>(
          '/auth/register/independent-master',
          data: imBody,
        );
      } else {
        final body = <String, dynamic>{
          'email': email,
          'password': password,
          'role': role.toWire,
          // For salon owners firstName/lastName come from the notifier as empty
          // strings (the UI no longer collects them); include them so the
          // backend schema remains satisfied.
          'firstName': firstName,
          'lastName': lastName,
        };
        // Include businessName only when it is non-null and non-blank.
        // Backend enforces its presence for SALON_OWNER with a 400.
        // Use a local trimmed variable to avoid calling .trim() twice
        // (backlog pattern 5).
        final trimmedBusiness = businessName?.trim();
        if (trimmedBusiness != null && trimmedBusiness.isNotEmpty) {
          body['businessName'] = trimmedBusiness;
        }
        // Optional salon details — included only when provided.
        final trimmedAddress = address?.trim();
        if (trimmedAddress != null && trimmedAddress.isNotEmpty) {
          body['address'] = trimmedAddress;
        }
        // Phone is now included for all roles (Change 7), including CLIENT.
        final trimmedPhone = phone?.trim();
        if (trimmedPhone != null && trimmedPhone.isNotEmpty) {
          body['phoneNumber'] = trimmedPhone;
        }
        response = await _dio.post<Map<String, dynamic>>(
          '/auth/register',
          data: body,
        );
      }

      return _parseUserAndTokens(response.data!);
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'register failed (role=${role.toWire}): ${e.type} ${e.response?.statusCode}',
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
