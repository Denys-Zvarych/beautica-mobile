// Phase 2.4 — Real AuthNotifier replacing the Phase 2.2 stub.
//
// Owns the sealed [AuthSession] state for the entire app lifecycle. Kept alive
// because the auth interceptor, router guard, and all feature screens need it.
//
// Cold-start flow (build()):
//   1. Read refresh token from SecureStorage.
//   2. If absent → return Unauthenticated immediately.
//   3. If present → call repo.refresh() to obtain a new token pair, then
//      repo.me() to load the user profile.
//   4. On any Failure (expired/revoked token) → wipe storage, return
//      Unauthenticated. Never bubble the exception to the UI.
//
// Action methods (login, register, logout) follow the AsyncNotifier pattern:
//   - Set state to AsyncLoading before the async work.
//   - Use AsyncValue.guard() so any Failure is captured in AsyncError — the
//     screen's .when(error:) handler surfaces it to the user.
//
// Security invariants (mobile-security MS-1 / MS-2):
//   - Only the refresh token is written to SecureStorage.
//   - The access token lives exclusively in the [Authenticated] state in memory.
//   - Never pass the access token to writeRefreshToken — they are different keys.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../../../core/storage/secure_storage_provider.dart';
import '../data/auth_repository_provider.dart';
import '../domain/auth_session.dart';
import '../domain/user_role.dart';

part 'auth_notifier.g.dart';

/// Manages the user's authentication session for the Beautica app lifetime.
///
/// Exposes [AsyncValue<AuthSession>] so that all consumers — interceptors,
/// router guards, and screens — can distinguish between the initial loading
/// state (cold start) and the settled [Authenticated] / [Unauthenticated]
/// states.
///
/// Generated provider name: `authProvider` (Riverpod 3.x strips "Notifier").
@Riverpod(keepAlive: true)
class AuthNotifier extends _$AuthNotifier {
  @override
  Future<AuthSession> build() async {
    final storage = ref.read(secureStorageProvider);
    final rt = await storage.readRefreshToken();

    if (rt == null) {
      if (kDebugMode) {
        log(
          'Cold start: no refresh token — unauthenticated',
          name: 'auth',
          level: 800,
        );
      }
      return const AuthSession.unauthenticated();
    }

    try {
      final repo = ref.read(authRepositoryProvider);
      final tokens = await repo
          .refresh(rt)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () =>
                throw const NetworkFailure(cause: 'refresh timed out'),
          );
      // Persist the rotated refresh token before loading the profile.
      await storage.writeRefreshToken(tokens.refreshToken);
      final user = await repo.me();
      if (kDebugMode) {
        log(
          'Cold start: session restored for user ${user.id}',
          name: 'auth',
          level: 800,
        );
      }
      return AuthSession.authenticated(
        user: user,
        accessToken: tokens.accessToken,
      );
    } on Failure catch (f) {
      if (kDebugMode) {
        log(
          'Cold start refresh failed — clearing storage and going unauthenticated',
          name: 'auth',
          level: 1000,
          error:
              '${f.runtimeType}${f is ServerFailure ? " (status: ${f.statusCode})" : ""}',
        );
      }
      await storage.deleteAll();
      return const AuthSession.unauthenticated();
    }
  }

  /// Authenticates the user with [email] and [password].
  ///
  /// On success, state becomes [AsyncData<Authenticated>] with the user profile
  /// and a fresh access token. On failure, state becomes [AsyncError] with the
  /// typed [Failure] — the calling screen's `.when(error:)` handler displays it.
  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final (user, tokens) = await ref
          .read(authRepositoryProvider)
          .login(email: email, password: password);
      await ref
          .read(secureStorageProvider)
          .writeRefreshToken(tokens.refreshToken);
      if (kDebugMode) {
        log('Login success: user ${user.id}', name: 'auth', level: 800);
      }
      return AuthSession.authenticated(
        user: user,
        accessToken: tokens.accessToken,
      );
    });
  }

  /// Registers a new account with the given [role] and logs in immediately.
  ///
  /// [role] defaults to [UserRole.independentMaster] for backwards compatibility.
  /// The backend validates eligibility — non-self-registerable roles surface as
  /// a [Failure] that the calling screen displays via snackbar.
  ///
  /// On success, state becomes [AsyncData<Authenticated>]. On failure (e.g.
  /// [ValidationFailure] for duplicate email), state becomes [AsyncError].
  Future<void> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    UserRole role = UserRole.independentMaster,
    String? businessName,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final (user, tokens) = await ref
          .read(authRepositoryProvider)
          .registerIndependentMaster(
            email: email,
            password: password,
            firstName: firstName,
            lastName: lastName,
            role: role,
            businessName: businessName,
          );
      await ref
          .read(secureStorageProvider)
          .writeRefreshToken(tokens.refreshToken);
      if (kDebugMode) {
        log('Registration success: user ${user.id}', name: 'auth', level: 800);
      }
      return AuthSession.authenticated(
        user: user,
        accessToken: tokens.accessToken,
      );
    });
  }

  /// Updates the in-memory access token without re-fetching the user profile.
  ///
  /// Called by [RefreshInterceptor] after a silent token refresh so that
  /// subsequent requests carry the new access token without requiring a full
  /// session reload. Only has effect when the current state is [Authenticated].
  void setAccessToken(String token) {
    final s = state.value;
    if (s is Authenticated) {
      state = AsyncData(
        AuthSession.authenticated(user: s.user, accessToken: token),
      );
    }
  }

  /// Clears the session and wipes all tokens from secure storage.
  ///
  /// Makes a best-effort server-side revocation call via the repository before
  /// wiping local state. Any [Failure] from the server call is tolerated — the
  /// local wipe always proceeds. Sets state to [AsyncData<Unauthenticated>]
  /// so the router guard (Phase 2.9) redirects to the login screen.
  Future<void> logout() async {
    try {
      await ref.read(authRepositoryProvider).logout();
    } on Failure catch (f) {
      if (kDebugMode) {
        log(
          'Logout server call failed (tolerated): ${f.runtimeType}',
          name: 'auth',
          level: 900,
        );
      }
    }
    await ref.read(secureStorageProvider).deleteAll();
    if (kDebugMode) {
      log('Logout: session cleared', name: 'auth', level: 800);
    }
    state = const AsyncData(AuthSession.unauthenticated());
  }
}
