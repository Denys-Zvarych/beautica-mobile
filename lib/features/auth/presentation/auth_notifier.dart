// Phase 2.4 — Real AuthNotifier replacing the Phase 2.2 stub.
//
// Owns the sealed [AuthSession] state for the entire app lifecycle. Kept alive
// because the auth interceptor, router guard, and all feature screens need it.
//
// Cold-start flow (build()) — F4 perf fix:
//   build() returns SYNCHRONOUSLY with Unauthenticated so the router can
//   immediately redirect to /login (splash no longer blocks for ~1.5 s on the
//   KeyStore-backed flutter_secure_storage read). The storage read + refresh
//   call run as a fire-and-forget background task that mutates [state] when
//   it completes:
//     1. Read refresh token from SecureStorage.
//     2. If absent → state stays Unauthenticated (no-op, build() already set it).
//     3. If present → call repo.refresh() then repo.me().
//        - Success → state = AsyncData(Authenticated(...)).
//        - Failure → wipe storage, state = AsyncData(Unauthenticated).
//   The background task never throws to the caller — every failure path
//   resolves to Unauthenticated, so the router guard sees a settled state.
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

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../../../core/storage/secure_storage_provider.dart';
import '../../../shared/util/mask_email.dart';
import '../data/auth_repository_provider.dart';
import '../domain/auth_session.dart';
import '../domain/register_result.dart';
import '../domain/user_role.dart';
import '../state/register_draft_notifier.dart';

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
  Future<AuthSession> build() {
    // F4 (corrected) — never block the splash on the KeyStore-backed storage
    // read. Schedule the storage read + refresh as a microtask so the Future
    // returned here resolves IMMEDIATELY (synchronously-completed) — by the
    // time the router observes [authProvider], the AsyncNotifier has settled
    // to AsyncData(Unauthenticated()). The background task then mutates
    // [state] to AsyncData(Authenticated(...)) if a valid session is restored.
    //
    // NOTE: build() is intentionally NOT marked `async`. Using `async` would
    // force a microtask boundary before the value is observable; returning
    // `Future.value(...)` is observably synchronous when awaited but cleanly
    // typed as Future<AuthSession>. This preserves the public AsyncValue
    // surface that every consumer (router, interceptor, selectors, screens)
    // depends on.
    unawaited(Future.microtask(_restoreSessionInBackground));
    return Future.value(const AuthSession.unauthenticated());
  }

  /// Background restoration task — never throws. Runs after [build] returns.
  ///
  /// Reads the stored refresh token; if present, exchanges it for a new token
  /// pair and loads the user profile. On any failure, wipes storage and leaves
  /// the state as Unauthenticated.
  ///
  /// Mutates [state] directly — does not return anything.
  Future<void> _restoreSessionInBackground() async {
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
      // Already AsyncData(Unauthenticated) from build(); nothing to update.
      return;
    }

    try {
      final repo = ref.read(authRepositoryProvider);
      // F3 piggy-back — timeout lowered from 20 s to 6 s. Splash is no longer
      // blocked on this call (F4) so a snappier "you're logged out" UX is the
      // goal; 6 s comfortably covers a slow mobile network round-trip while
      // still surfacing dead-server scenarios quickly.
      final tokens = await repo
          .refresh(rt)
          .timeout(
            const Duration(seconds: 6),
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
      state = AsyncData(
        AuthSession.authenticated(user: user, accessToken: tokens.accessToken),
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
      // Re-assert Unauthenticated in case any caller mutated state in between
      // (defensive — the more common path is that state is already this value).
      state = const AsyncData(AuthSession.unauthenticated());
    } catch (e, st) {
      // Catch-all — must not bubble up since this is a fire-and-forget Future.
      if (kDebugMode) {
        log(
          'Cold start refresh failed with non-Failure exception — '
          'clearing storage and going unauthenticated',
          name: 'auth',
          level: 1000,
          error: e,
          stackTrace: st,
        );
      }
      await storage.deleteAll();
      state = const AsyncData(AuthSession.unauthenticated());
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

  /// Registers a new account with the given [role].
  ///
  /// [role] defaults to [UserRole.independentMaster] for backwards compatibility.
  /// The backend validates eligibility — non-self-registerable roles surface as
  /// a [Failure] that the calling screen displays via snackbar.
  ///
  /// Returns a [RegisterResult] so the caller can branch on whether email
  /// verification is required:
  /// - [VerificationRequired]    — state stays [Unauthenticated]; caller
  ///                                navigates to the OTP screen.
  /// - [AuthenticatedRegisterResult] — refresh token is persisted and state
  ///                                becomes [AsyncData<Authenticated>]; caller
  ///                                may transition straight to the home shell.
  /// - `null` (only when an error occurred) — state becomes [AsyncError] with
  ///   the typed [Failure]; the calling screen's `.when(error:)` handler
  ///   surfaces it via inline field errors / snackbar.
  Future<RegisterResult?> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    UserRole role = UserRole.independentMaster,
    String? businessName,
    String? address,
    String? phone,
  }) async {
    state = const AsyncLoading();
    // AsyncValue.guard fixes the [state] for screens that pattern-match on
    // [AsyncValue]; we keep a local handle on the [RegisterResult] so we can
    // return it to the caller (which AsyncValue.guard cannot do).
    RegisterResult? result;
    state = await AsyncValue.guard(() async {
      final outcome = await ref
          .read(authRepositoryProvider)
          .registerIndependentMaster(
            email: email,
            password: password,
            firstName: firstName,
            lastName: lastName,
            role: role,
            businessName: businessName,
            address: address,
            phone: phone,
          );
      result = outcome;
      switch (outcome) {
        case AuthenticatedRegisterResult(:final user, :final tokens):
          await ref
              .read(secureStorageProvider)
              .writeRefreshToken(tokens.refreshToken);
          if (kDebugMode) {
            log(
              'Registration success (auto-login): user ${user.id}',
              name: 'auth',
              level: 800,
            );
          }
          return AuthSession.authenticated(
            user: user,
            accessToken: tokens.accessToken,
          );
        case VerificationRequired(:final email):
          if (kDebugMode) {
            log(
              'Registration success (verification-required) for $email',
              name: 'auth',
              level: 800,
            );
          }
          // No session yet — user must verify their email next.
          return const AuthSession.unauthenticated();
      }
    });
    return result;
  }

  /// Verifies the user's email address by submitting the 6-digit [otp] code.
  ///
  /// Backend Phase 1.5 contract: a successful verify-email call returns a full
  /// `AuthResponse` (user + accessToken + refreshToken) — the account is
  /// authenticated as a side-effect of verification.
  ///
  /// On success this method mirrors the [login] / [register] success path:
  ///   - persists the rotated refresh token to [SecureStorage];
  ///   - flips [state] to `AsyncData(Authenticated(user, accessToken))`.
  /// The router redirect (Phase 2.9) detects the Authenticated state and
  /// forwards the user away from `/verification`.
  ///
  /// Throws whatever the underlying [AuthRepository.verifyEmail] throws —
  /// the calling screen wraps the call in `try/catch` to render the inline
  /// error message via [VerificationFailure.userMessage].
  Future<void> verifyEmail({required String email, required String otp}) async {
    try {
      final (user, tokens) = await ref
          .read(authRepositoryProvider)
          .verifyEmail(email: email, otp: otp);
      await ref
          .read(secureStorageProvider)
          .writeRefreshToken(tokens.refreshToken);
      state = AsyncData(
        AuthSession.authenticated(user: user, accessToken: tokens.accessToken),
      );
      if (kDebugMode) {
        log(
          'verifyEmail success for ${maskEmail(email)}',
          name: 'auth.verification',
          level: 800,
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'verifyEmail failed for ${maskEmail(email)}',
          name: 'auth.verification',
          level: 900,
          error: e,
          stackTrace: st,
        );
      }
      rethrow;
    }
  }

  /// Re-sends the verification code to [email].
  ///
  /// Does NOT mutate [state] — the resend call only triggers a side-effect
  /// on the backend. Callers wrap the call in `try/catch` so they can render
  /// [ResendThrottledFailure] (429) inline.
  ///
  /// Throws whatever [AuthRepository.resendVerificationCode] throws.
  Future<void> resendCode({required String email}) async {
    try {
      await ref
          .read(authRepositoryProvider)
          .resendVerificationCode(email: email);
      if (kDebugMode) {
        log(
          'resendCode dispatched for ${maskEmail(email)}',
          name: 'auth.verification',
          level: 800,
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'resendCode failed for ${maskEmail(email)}',
          name: 'auth.verification',
          level: 900,
          error: e,
          stackTrace: st,
        );
      }
      rethrow;
    }
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
    // Security (Phase 2.16 HIGH-1) — clear any in-flight registration draft
    // so the password fields it holds in memory do not linger past the user's
    // explicit logout. The draft survives across nav (keepAlive) so without
    // this it would persist until the process is killed.
    ref.read(registerDraftProvider.notifier).reset();
    if (kDebugMode) {
      log('Logout: session cleared', name: 'auth', level: 800);
    }
    state = const AsyncData(AuthSession.unauthenticated());
  }
}
