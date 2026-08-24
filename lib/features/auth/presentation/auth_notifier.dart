// Phase 2.4 — Real AuthNotifier replacing the Phase 2.2 stub.
//
// Owns the sealed [AuthSession] state for the entire app lifecycle. Kept alive
// because the auth interceptor, router guard, and all feature screens need it.
//
// Cold-start flow (build()):
//   build() is async and stays in AsyncLoading until the session is known:
//   1. Read refresh token from SecureStorage (~1–5 ms).
//      If absent → return Unauthenticated immediately (no network call).
//   2. If present → call repo.refresh() then repo.me() (~200–2000 ms).
//      - Success → state briefly set to Authenticated(sentinel) so AuthInterceptor
//        can inject the Bearer header on /users/me, then return Authenticated(user).
//      - Failure → wipe storage, return Unauthenticated.
//   While build() is in-flight, Riverpod emits AsyncLoading — the go_router
//   auth guard parks the user on /splash until the session resolves (no /login flash).
//
// Action methods (login, register, logout) follow the AsyncNotifier pattern:
//   - Set state to AsyncLoading before the async work.
//   - Use AsyncValue.guard() so any Failure is captured in AsyncError — the
//     screen's .when(error:) handler surfaces it to the user.
//
// Security invariants (mobile-security MS-1 / MS-2 / HIGH-1):
//   - Only the refresh token is written to SecureStorage.
//   - The access token lives exclusively in the [Authenticated] state in memory.
//   - Never pass the access token to writeRefreshToken — they are different keys.
//   - HttpAuthRepository.refresh() sends X-No-Retry: true so RefreshInterceptor
//     cannot intercept a failed cold-start refresh and loop (HIGH-1 fix).
//   - After repo.refresh() succeeds, state is immediately set to Authenticated
//     (sentinel user) so AuthInterceptor injects the Bearer token into the
//     subsequent repo.me() call — preventing a RefreshInterceptor loop on me().

import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../../../core/media/beautica_image.dart';
import '../../../core/security/screen_protection.dart';
import '../../../core/time/clock_provider.dart';
import '../../../core/storage/secure_storage_provider.dart';
import '../../../shared/util/mask_email.dart';
// Deliberate, narrow exception to "auth never imports another feature"
// (mobile-security HIGH, 2026-07-19): the day-timeline cache's bounded
// `keepAlive()` pool cannot be reached by the ordinary `ref.watch(authProvider)`
// cascade every OTHER per-user cache uses to self-clear — see
// `bookings_day_notifier.dart`'s file header ("Session-boundary PII") for the
// full defence-in-depth reasoning. This is a plain method call, not
// `ref.invalidate(...)`, and `dayKeepAliveLruProvider` does not watch
// `authProvider` back, so it cannot reopen the CircularDependencyError the
// NOTE further down in [logout] warns about.
import '../../booking/application/bookings_day_notifier.dart';
import '../data/auth_repository_provider.dart';
import '../domain/auth_session.dart';
import '../domain/register_result.dart';
import '../domain/user.dart';
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
  // HIGH-1 sentinel token (mobile-security 2026-05-24):
  //
  // Riverpod 3's AsyncNotifier completes `provider.future` on the FIRST
  // `state = AsyncData(...)` assignment (or the `build()` return value,
  // whichever comes first). A mid-build `state =` assignment therefore
  // hijacks `provider.future` and causes it to resolve with the sentinel
  // user rather than the real user — breaking `await authProvider.future`
  // in tests and router guards.
  //
  // To preserve the HIGH-1 invariant (Bearer token present on /users/me so
  // RefreshInterceptor cannot issue a second refresh) WITHOUT a mid-build
  // state mutation, we use this plain Dart field. [AuthInterceptor] checks
  // [coldStartAccessToken] when [authProvider.value] is still loading. The
  // field is cleared to null once [build()] returns (either success or
  // failure), at which point the settled state carries the real access token.
  //
  // This field is intentionally NOT part of the Riverpod state graph — it is
  // a lightweight synchronisation primitive purely for the interceptor.
  String? coldStartAccessToken;

  // Last-known access token for the *settled* authenticated session.
  //
  // Unlike [coldStartAccessToken] (a transient sentinel cleared the moment the
  // Authenticated state settles), this field persists for the whole lifetime of
  // the authenticated session and is only cleared on logout / when the session
  // goes Unauthenticated. It exists to harden token resolution in
  // [AuthInterceptor] against the brief window where a watcher of [authProvider]
  // is mid-rebuild (e.g. the delete flow invalidates [masterProfileProvider],
  // which [serviceRepositoryProvider] watches) and `_ref.read(authProvider)` is
  // momentarily not in the `AsyncData(Authenticated)` state. In that window an
  // in-flight request must still carry the last good Bearer token rather than
  // be sent tokenless (which the backend correctly answers with a false 401).
  String? _lastKnownAccessToken;

  /// The best-available access token for an authenticated user, used by
  /// [AuthInterceptor] as a fallback when [authProvider] is not currently
  /// resolvable to an [Authenticated] [AsyncData] state.
  ///
  /// Resolution order:
  ///   1. the token on the settled [Authenticated] session ([state.value]);
  ///   2. the cold-start sentinel ([coldStartAccessToken]);
  ///   3. the last-known token from the current authenticated session
  ///      ([_lastKnownAccessToken]).
  ///
  /// Returns `null` only when there is genuinely no authenticated session
  /// (cold start with no stored token, or after logout).
  String? get lastKnownAccessToken {
    // `state.value` returns the data when in AsyncData, null while loading /
    // errored — exactly the "momentarily unresolved" window we fall back for.
    final settled = state.value;
    if (settled is Authenticated) return settled.accessToken;
    return coldStartAccessToken ?? _lastKnownAccessToken;
  }

  // ---------------------------------------------------------------------------
  // JWT exp pre-check (MEDIUM-4, mobile-security 2026-05-27)
  // ---------------------------------------------------------------------------

  /// Returns `true` when [jwt]'s `exp` claim is in the past (or within a
  /// 30-second grace window). Used to short-circuit the cold-start network
  /// refresh when the stored refresh token is already known to be expired.
  ///
  /// Signature is NOT verified — this is a UX optimisation only. The server
  /// remains the authoritative arbiter; if clock-skew is extreme or the token
  /// was revoked server-side, the server 401 still handles it correctly.
  ///
  /// Returns `false` (fail-open) on any decode error so the server can decide.
  bool _isTokenExpired(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return false;
      // Normalise the URL-safe base64 segment (no padding) before decoding.
      final normalised = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalised));
      final payload = jsonDecode(decoded) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! int) return false;
      // Apply a 30-second grace window to account for minor clock skew.
      const kGraceSeconds = 30;
      final nowSeconds =
          ref.read(clockProvider)().millisecondsSinceEpoch ~/ 1000;
      return exp < nowSeconds + kGraceSeconds;
    } catch (_) {
      // Fail-open — let the server decide if we cannot decode the token.
      return false;
    }
  }

  @override
  Future<AuthSession> build() async {
    // Cold-start session restore — Riverpod emits AsyncLoading while this
    // Future is in-flight, parking the router on /splash (auth_redirect.dart
    // isLoading guard) until we know definitively whether the user is
    // authenticated or not.
    //
    // The restore has two phases:
    //   Phase 1 (fast, ~1–5 ms): read the refresh token from SecureStorage.
    //     If absent → return Unauthenticated immediately (no network call).
    //   Phase 2 (network, ~200–2000 ms): exchange the stored token for a new
    //     token pair (repo.refresh) and load the user profile (repo.me).
    //     On success → return Authenticated.
    //     On any failure → wipe storage, return Unauthenticated.
    //
    // HIGH-1: before calling repo.me(), write the fresh access token to
    // [coldStartAccessToken] so AuthInterceptor injects it as the Bearer
    // header. This prevents a 401 on /users/me that would trigger a redundant
    // second refresh via RefreshInterceptor. The field is cleared on return
    // because the settled Authenticated state carries the real access token.
    //
    // Why the old "F4 synchronous return" was wrong: Future.value() completes
    // in the same microtask as the observer's first subscription, giving Riverpod
    // zero time to emit AsyncLoading. The auth_redirect isLoading guard was
    // architecturally correct but unreachable. This async build() restores it.
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

    // MEDIUM-4 (mobile-security 2026-05-27): exp pre-check.
    // Skip the refresh network call when the stored refresh token is already
    // known to be expired — saves a full DNS + TLS + server round-trip.
    // The server remains the authoritative arbiter; this is a UX optimisation.
    if (_isTokenExpired(rt)) {
      if (kDebugMode) {
        log(
          'Cold start: refresh token expired — skip network call',
          name: 'auth',
          level: 800,
        );
      }
      await storage.deleteAll(); // clean up stale token
      return const AuthSession.unauthenticated();
    }

    try {
      final repo = ref.read(authRepositoryProvider);

      // HIGH-1 (mobile-security 2026-05-24): repo.refresh() sends
      // X-No-Retry: true so RefreshInterceptor cannot re-intercept a 401
      // from /auth/refresh and loop with the already-expired token.
      final tokens = await repo.refresh(rt);
      await storage.writeRefreshToken(tokens.refreshToken);

      // HIGH-1: write the fresh access token to the sentinel field so
      // AuthInterceptor can inject the Bearer header on the subsequent
      // repo.me() call while authProvider is still in AsyncLoading.
      coldStartAccessToken = tokens.accessToken;
      // Persist the token for the whole session so the interceptor can fall
      // back to it during any later mid-rebuild window (see [lastKnownAccessToken]).
      _lastKnownAccessToken = tokens.accessToken;

      final user = await repo.me();

      if (kDebugMode) {
        log(
          'Cold start: session restored for ${user.id}',
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
      _lastKnownAccessToken = null;
      return const AuthSession.unauthenticated();
    } catch (e, st) {
      // Catch-all — must not surface as AsyncError; the router handles
      // Unauthenticated states but has no handler for AsyncError on startup.
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
      _lastKnownAccessToken = null;
      return const AuthSession.unauthenticated();
    } finally {
      // Clear the sentinel regardless of outcome — the settled state (or the
      // Unauthenticated return) no longer needs it.
      coldStartAccessToken = null;
    }
  }

  /// Authenticates the user with [email] and [password].
  ///
  /// On success, state becomes [AsyncData<Authenticated>] with the user profile
  /// and a fresh access token. On failure, state becomes [AsyncError] with the
  /// typed [Failure] — the calling screen's `.when(error:)` handler displays it.
  ///
  /// HIGH-1 pattern: while [AsyncValue.guard] holds state in [AsyncLoading],
  /// the access token is written to [coldStartAccessToken] so [AuthInterceptor]
  /// can inject the Bearer header on the [repo.me] call that follows. The
  /// sentinel is cleared unconditionally via try/finally so a failed [repo.me]
  /// does not leave a stale token in memory. This guarantees [firstName] and
  /// [lastName] are populated in the settled [Authenticated] session — callers
  /// such as the home screen and master-profile header see the real name.
  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      final storage = ref.read(secureStorageProvider);
      final (_, tokens) = await repo.login(email: email, password: password);
      await storage.writeRefreshToken(tokens.refreshToken);
      // HIGH-1 pattern: state is AsyncLoading while this guard runs; write the
      // access token to the sentinel so AuthInterceptor injects the Bearer
      // header on repo.me() without triggering RefreshInterceptor.
      coldStartAccessToken = tokens.accessToken;
      _lastKnownAccessToken = tokens.accessToken;
      final User fullUser;
      try {
        fullUser = await repo.me();
      } catch (_) {
        coldStartAccessToken = null;
        rethrow;
      }
      if (kDebugMode) {
        log(
          'Login success: user ${fullUser.id} (firstName: ${fullUser.firstName})',
          name: 'auth',
          level: 800,
        );
      }
      // Clear the sentinel AFTER returning the Authenticated value so that
      // AsyncValue.guard sets state = AsyncData(Authenticated) before the next
      // microtask observes coldStartAccessToken == null. Mirrors the fix applied
      // to verifyEmail() (same race window).
      final session = AuthSession.authenticated(
        user: fullUser,
        accessToken: tokens.accessToken,
      );
      coldStartAccessToken = null;
      return session;
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
          _lastKnownAccessToken = tokens.accessToken;
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
  ///   - calls [repo.me] to load the full user profile (firstName/lastName are
  ///     absent from [AuthResponse] — only [/users/me] returns them);
  ///   - flips [state] to `AsyncData(Authenticated(fullUser, accessToken))`.
  /// The router redirect (Phase 2.9) detects the Authenticated state and
  /// forwards the user away from `/verification` to the done screen, where
  /// [_resolveDisplayName] surfaces the real first name in the greeting.
  ///
  /// HIGH-1 pattern: before calling [repo.me], the access token is written to
  /// [coldStartAccessToken] so [AuthInterceptor] injects the Bearer header
  /// while the provider state is still [AsyncData(Unauthenticated)] from the
  /// registration phase. Without this, [/users/me] returns 401 and [firstName]
  /// remains null, causing the done screen to fall back to "друже".
  /// The sentinel is cleared unconditionally via try/finally.
  ///
  /// Throws whatever the underlying [AuthRepository.verifyEmail] throws —
  /// the calling screen wraps the call in `try/catch` to render the inline
  /// error message via [VerificationFailure.userMessage].
  Future<void> verifyEmail({required String email, required String otp}) async {
    // LOW fix: set AsyncLoading immediately so the UI disables the submit
    // button for the full POST /verify-email + GET /users/me window, preventing
    // double-submit on slow networks (~400–1200 ms). Mirrors the pattern used
    // by login() and build().
    state = const AsyncLoading();
    try {
      final repo = ref.read(authRepositoryProvider);
      final storage = ref.read(secureStorageProvider);
      final (_, tokens) = await repo.verifyEmail(email: email, otp: otp);
      await storage.writeRefreshToken(tokens.refreshToken);
      // HIGH-1 pattern (same as build()): write the access token to the
      // sentinel field so AuthInterceptor can inject the Bearer header on
      // repo.me() while the provider state is still AsyncData(Unauthenticated)
      // from registration. Without this, /users/me returns 401 and firstName
      // stays null — the done screen greeting falls back to "друже".
      coldStartAccessToken = tokens.accessToken;
      _lastKnownAccessToken = tokens.accessToken;
      final User fullUser;
      try {
        fullUser = await repo.me();
      } catch (_) {
        // Failure-path hygiene: the verify succeeded but the profile load
        // failed, so this session never settles to Authenticated. Clear BOTH
        // in-memory token caches so a half-built session leaves no token for
        // the interceptor to replay, then let the outer catch surface the
        // failure as AsyncError (mirrors build()'s failure path). Without this,
        // a real repo.me() failure would leave the UI in a stale state.
        coldStartAccessToken = null;
        _lastKnownAccessToken = null;
        rethrow;
      }
      // CRITICAL: set the Authenticated state BEFORE clearing coldStartAccessToken.
      //
      // The old finally-block order was:
      //   1. coldStartAccessToken = null   ← sentinel wiped
      //   2. state = AsyncData(Authenticated)  ← state settled
      //
      // Between steps 1 and 2 there is a Dart microtask gap. Any Dio request
      // that fires during that gap (e.g. _saveProviderProfile() → PATCH
      // /independent-masters/me) hits AuthInterceptor while authProvider is
      // still AsyncLoading AND coldStartAccessToken is null → no Bearer token
      // injected → backend returns 401 → RefreshInterceptor triggers logout →
      // "Сесія завершилась" shown.
      //
      // Fix: settle the state first, then clear the sentinel. Once state is
      // AsyncData(Authenticated) the interceptor reads the token from the
      // settled Authenticated session; the sentinel is no longer needed.
      state = AsyncData(
        AuthSession.authenticated(
          user: fullUser,
          accessToken: tokens.accessToken,
        ),
      );
      coldStartAccessToken = null;
      if (kDebugMode) {
        log(
          'verifyEmail success for ${maskEmail(email)} — profile loaded '
          '(firstName: ${fullUser.firstName})',
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
      state = AsyncError(e, st);
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

  /// Requests a password-reset link for [email] (backend Phase 11.2).
  ///
  /// Does NOT mutate [state] — the request only triggers a backend side-effect
  /// and always resolves generically (anti-enumeration). The calling screen
  /// wraps this in `try/catch` so it can surface a real transport error inline
  /// while still showing the generic confirmation on success.
  ///
  /// Throws whatever [AuthRepository.requestPasswordReset] throws.
  Future<void> requestPasswordReset(String email) async {
    try {
      await ref.read(authRepositoryProvider).requestPasswordReset(email);
      if (kDebugMode) {
        log(
          'requestPasswordReset dispatched for ${maskEmail(email)}',
          name: 'auth.reset',
          level: 800,
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'requestPasswordReset failed for ${maskEmail(email)}',
          name: 'auth.reset',
          level: 900,
          error: e,
          stackTrace: st,
        );
      }
      rethrow;
    }
  }

  /// Requests a password-reset OTP for the AUTHENTICATED caller (backend
  /// Phase A3 — the "change password from settings" entry point).
  ///
  /// Does NOT mutate [state] — the request only triggers a backend
  /// side-effect (emailing an OTP). The calling screen wraps this in
  /// `try/catch` so it can render [ResendThrottledFailure] (429) inline —
  /// unlike [requestPasswordReset], this authenticated entry point DOES
  /// surface the per-account resend cooldown as a 429.
  ///
  /// Throws whatever [AuthRepository.requestChangePasswordOtp] throws.
  Future<void> requestChangePasswordOtp() async {
    try {
      await ref.read(authRepositoryProvider).requestChangePasswordOtp();
      if (kDebugMode) {
        log(
          'requestChangePasswordOtp dispatched',
          name: 'auth.reset',
          level: 800,
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'requestChangePasswordOtp failed',
          name: 'auth.reset',
          level: 900,
          error: e,
          stackTrace: st,
        );
      }
      rethrow;
    }
  }

  /// Verifies the 6-digit [code] emailed to [email] and returns the
  /// single-use reset ticket to submit to [confirmPasswordReset] (backend
  /// Phase A3). Used by BOTH the forgot-password flow (unauthenticated) and
  /// the authenticated settings change-password flow.
  ///
  /// Does NOT mutate [state] — this is a pure request/response call with no
  /// session side-effect (unlike [verifyEmail], which authenticates the
  /// caller as a side-effect). The calling screen wraps this in `try/catch`
  /// so it can render [PasswordResetOtpFailure] (wrong/expired code) inline.
  ///
  /// Throws whatever [AuthRepository.verifyPasswordResetOtp] throws.
  Future<String> verifyPasswordResetOtp({
    required String email,
    required String code,
  }) async {
    try {
      final ticket = await ref
          .read(authRepositoryProvider)
          .verifyPasswordResetOtp(email: email, code: code);
      if (kDebugMode) {
        log(
          'verifyPasswordResetOtp success for ${maskEmail(email)}',
          name: 'auth.reset',
          level: 800,
        );
      }
      return ticket;
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'verifyPasswordResetOtp failed for ${maskEmail(email)}',
          name: 'auth.reset',
          level: 900,
          error: e is Failure ? e.runtimeType.toString() : 'non-Failure error',
          stackTrace: st,
        );
      }
      rethrow;
    }
  }

  /// Confirms a password reset with the single-use [resetTicket] (minted by
  /// [verifyPasswordResetOtp]) and [newPassword] (backend Phase 11.3 / A3).
  ///
  /// Does NOT mutate [state] and does NOT auto-login — by design the backend
  /// issues no session on reset and the caller routes the user to the login
  /// screen. The calling screen wraps this in `try/catch` so it can branch on
  /// [ResetTokenInvalidFailure] (render the invalid-link state) vs. a generic
  /// retryable error.
  ///
  /// Throws whatever [AuthRepository.confirmPasswordReset] throws.
  Future<void> confirmPasswordReset({
    required String resetTicket,
    required String newPassword,
  }) async {
    try {
      await ref
          .read(authRepositoryProvider)
          .confirmPasswordReset(
            resetTicket: resetTicket,
            newPassword: newPassword,
          );
      if (kDebugMode) {
        log('confirmPasswordReset success', name: 'auth.reset', level: 800);
      }
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'confirmPasswordReset failed',
          name: 'auth.reset',
          level: 900,
          // Sanitised — never pass the raw exception (its toString may carry
          // the reset ticket / new password from the request body).
          error: e is Failure ? e.runtimeType.toString() : 'non-Failure error',
          stackTrace: st,
        );
      }
      rethrow;
    }
  }

  /// Accepts an invite by completing profile setup. On success, persists the
  /// refresh token and transitions to [Authenticated] — the router redirect picks
  /// up the state change and routes to home.
  ///
  /// On failure, state becomes [AsyncError] with the typed [Failure] — the
  /// calling screen's `.when(error:)` handler (or try/catch) displays it.
  Future<void> acceptInvite({
    required String token,
    required String password,
    required String firstName,
    required String lastName,
    String? phoneNumber,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final (user, tokens) = await ref
          .read(authRepositoryProvider)
          .acceptInvite(
            token: token,
            password: password,
            firstName: firstName,
            lastName: lastName,
            phoneNumber: phoneNumber,
          );
      await ref
          .read(secureStorageProvider)
          .writeRefreshToken(tokens.refreshToken);
      if (kDebugMode) {
        log('Invite accepted: user ${user.id}', name: 'auth', level: 800);
      }
      _lastKnownAccessToken = tokens.accessToken;
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
  /// session reload.
  ///
  /// The write is DURABLE ACROSS THE COLD-START WINDOW (mobile-qa MEDIUM,
  /// 2026-08-07). This used to no-op unless the settled state was already
  /// [Authenticated], which silently DISCARDED the freshly-refreshed token
  /// whenever the refresh completed while [build] / [login] / [verifyEmail]
  /// still held the provider in [AsyncLoading]. [RefreshInterceptor] then
  /// replayed the failed request through `_dio.fetch`, which re-enters
  /// [AuthInterceptor] — and that re-derives the Bearer header from
  /// [lastKnownAccessToken], i.e. from the STALE cold-start sentinel. So the
  /// replay re-sent the exact token that had just 401'd, `X-No-Retry` stopped
  /// the second round, cold-start [build] read that as a dead session and wiped
  /// storage: a false "session expired" bounce to /login for a user holding
  /// valid credentials. Measured before the fix (throwaway probe):
  ///   `state.value=null lastKnown=stale-access`
  ///   `authHeaders=[Bearer stale-access, Bearer stale-access]`
  /// and after: `authHeaders=[Bearer stale-access, Bearer new-access]`.
  ///
  /// The path was dormant until 2026-08-07: `ErrorMapperInterceptor` ran ahead
  /// of [RefreshInterceptor] and ended the error flow with `handler.reject`, so
  /// no silent refresh ever reached this method. Reordering the chain (see
  /// `dio_provider.dart`'s ORDER IS LOAD-BEARING block) armed it.
  ///
  /// The fix is at the token WRITE, not at the replay: the replay is only one
  /// of the requests that re-derive their Bearer from [lastKnownAccessToken]
  /// during that window, so making `_dio.fetch` carry the token out-of-band
  /// would leave every other in-flight cold-start request on the stale one.
  /// Both slots [lastKnownAccessToken] resolves through are therefore updated,
  /// so the fresh token cannot be shadowed by the stale sentinel:
  ///   - [_lastKnownAccessToken] always;
  ///   - [coldStartAccessToken] only when it is currently non-null. It is a
  ///     transient sentinel owned by whichever flow set it (each clears it in a
  ///     `finally`); planting one here when none is live would leave a token
  ///     nobody is responsible for clearing.
  /// The Riverpod state itself is still rewritten ONLY when settled
  /// [Authenticated] — a mid-[build] `state =` assignment would hijack
  /// `provider.future` (see the [coldStartAccessToken] header).
  ///
  /// No-ops entirely when the settled state is [Unauthenticated]: [logout]
  /// wipes both slots and flips the state, so a refresh landing after that must
  /// not resurrect a Bearer token for a signed-out session.
  void setAccessToken(String token) {
    final s = state.value;
    if (s is Unauthenticated) return;
    // Keep the interceptor's session-lifetime fallback in lock-step with the
    // freshly-refreshed token so a mid-rebuild window never replays a stale one.
    _lastKnownAccessToken = token;
    if (coldStartAccessToken != null) {
      // A cold-start/login flow is mid-flight and its sentinel takes precedence
      // in [lastKnownAccessToken]; refresh it in place rather than let it
      // shadow the token that just replaced it server-side.
      coldStartAccessToken = token;
    }
    if (s is Authenticated) {
      state = AsyncData(
        AuthSession.authenticated(user: s.user, accessToken: token),
      );
    }
  }

  /// Re-fetches the user profile from `GET /users/me` and re-settles the
  /// [Authenticated] session with the fresh [User], preserving the current
  /// access token.
  ///
  /// Called by the client profile-edit save flows after a successful
  /// `PATCH /users/me` so that every consumer deriving from [authProvider]
  /// (e.g. the home-hub profile card via `clientProfile`, and the edit-seed
  /// providers) re-derives from the updated session User instead of the stale
  /// snapshot captured at the last [repo.me] call. Without this, the saved
  /// name / city / phone would only appear after an app restart (cold start).
  ///
  /// Only acts when the settled state is [Authenticated] — there is nothing to
  /// refresh while loading / unauthenticated.
  ///
  /// The access token is taken from the settled session and re-applied to the
  /// new [Authenticated] state, with [_lastKnownAccessToken] kept in lock-step
  /// exactly as [setAccessToken] does, so the interceptor's session-lifetime
  /// fallback never replays a stale token.
  ///
  /// A transient [repo.me] failure is tolerated: it is logged (kDebugMode) and
  /// the prior [Authenticated] session is left intact — a refresh hiccup must
  /// never tear down a valid session.
  Future<void> refreshUser() async {
    final s = state.value;
    if (s is! Authenticated) return;
    // Preserve the current settled session's access token across the refresh.
    final accessToken = s.accessToken;
    try {
      final freshUser = await ref.read(authRepositoryProvider).me();
      // Keep the interceptor's session-lifetime fallback in lock-step with the
      // preserved token (mirrors setAccessToken) so a mid-rebuild window never
      // replays a stale one.
      _lastKnownAccessToken = accessToken;
      state = AsyncData(
        AuthSession.authenticated(user: freshUser, accessToken: accessToken),
      );
      if (kDebugMode) {
        log(
          'refreshUser: session user refreshed for ${freshUser.id}',
          name: 'auth',
          level: 800,
        );
      }
    } catch (e) {
      // Tolerated — leave the prior Authenticated session in place so a
      // transient /users/me failure does not blow away a valid session.
      if (kDebugMode) {
        log(
          'refreshUser failed (tolerated, session preserved): '
          '${e is Failure ? e.runtimeType.toString() : 'non-Failure error'}',
          name: 'auth',
          level: 900,
        );
      }
    }
  }

  /// Clears the session and wipes all tokens from secure storage.
  ///
  /// Makes a best-effort server-side revocation call via the repository before
  /// wiping local state. ANY error from the server call (a [Failure] or an
  /// unmapped error such as a platform exception or [StateError]) is tolerated —
  /// the local wipe always proceeds so a logout never leaves tokens on device
  /// (M5 hardening). Sets state to [AsyncData<Unauthenticated>] so the router
  /// guard (Phase 2.9) redirects to the login screen.
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
    } catch (e) {
      // M5 hardening: a NON-Failure error (unmapped platform exception, raw
      // StateError, …) must NOT propagate past the wipe — otherwise the user's
      // refresh token would survive an explicit logout. Logout stays best-effort
      // for every error type; the unconditional wipe below always runs.
      if (kDebugMode) {
        log(
          'Logout server call threw non-Failure (tolerated): ${e.runtimeType}',
          name: 'auth',
          level: 900,
        );
      }
    }
    await ref.read(secureStorageProvider).deleteAll();
    // Security (mobile-security MEDIUM-1, 2026-07-24) — purge the shared media
    // disk cache. The loader (core/media/beautica_image.dart) disk-caches
    // remote avatars/photos for 7 days; the client faces this account viewed
    // are PII and must not survive an explicit or forced sign-out onto a
    // shared/reassigned device. Best-effort like the rest of the wipe: any
    // error (e.g. a wedged sqflite store) is tolerated so it can never abort
    // the unconditional local wipe below. Routed through the top-level
    // `purgeBeauticaMediaCache()` so it hits the override-aware ACTIVE cache
    // manager (never the raw handle) and stays testable.
    try {
      await purgeBeauticaMediaCache();
    } catch (e) {
      if (kDebugMode) {
        log(
          'Media cache purge on logout failed (tolerated): ${e.runtimeType}',
          name: 'auth',
          level: 900,
        );
      }
    }
    // Security (mobile-security MEDIUM) — force-clear the screen-protection
    // reference count and tear down the iOS app-switcher blur. (No FLAG_SECURE
    // is involved: screenshots are allowed by product decision 2026-08-20 —
    // see the header of `lib/core/security/screen_protection.dart`.)
    // Without this, a logout triggered while a PII screen's dialog is still
    // showing above a live `screenProtectionProvider` acquirer (e.g.
    // `RefreshInterceptor` force-logs-out on a failed token refresh while
    // `ClientBookingConflictDialog` is open over `BookingConfirmScreen`)
    // would leave protection latched on past the auth boundary — see
    // `ScreenProtectionManager.reset()`'s doc comment.
    ref.read(screenProtectionProvider).reset();
    // Security (Phase 2.16 HIGH-1) — clear any in-flight registration draft
    // so the password fields it holds in memory do not linger past the user's
    // explicit logout. The draft survives across nav (keepAlive) so without
    // this it would persist until the process is killed.
    ref.read(registerDraftProvider.notifier).reset();
    // Security (mobile-security HIGH, 2026-07-19) — sweep the day-timeline's
    // bounded keepAlive cache's OWN bookkeeping. `BookingsDayNotifier.build`'s
    // `authProvider`-id watch (triggered by the state assignment below)
    // already reclaims every member's PII on its own the instant the
    // identity changes — actively watched or not: Riverpod's
    // `invalidateSelf()` unconditionally severs every `KeepAliveLink` an
    // element holds and queues either its disposal (no active listener) or a
    // rebuild (an active one) for the very next event-loop turn — never left
    // lazily pending on some future read. This call exists because that
    // severing does NOT touch [DayKeepAliveLru]'s own `_links` map: without
    // it, a logged-out query's slot keeps pointing at an already-severed
    // link — a "zombie" entry silently wasting the LRU's bounded budget —
    // until a future cache touch happens to overwrite it. See
    // `bookings_day_notifier.dart`'s file header ("Session-boundary PII") for
    // the full reasoning, including the Riverpod internals this depends on.
    ref.read(dayKeepAliveLruProvider).clear();
    // NOTE — this belt-and-braces list is NOT the app's full inventory of
    // keepAlive, user-scoped state, and must not be read as one (mobile-security
    // INFO, 2026-08-17). `clientReviewSignalProvider` (a `keepAlive` set of
    // BOOKING IDS this provider has left client feedback about) is deliberately
    // ABSENT: like `BookingsDayNotifier`, its `build()` watches the
    // authenticated identity itself (`authProvider.select(… user.id …)`), so
    // the state assignment below already rebuilds it to a fresh empty set
    // through the ordinary cascade. Unlike the day cache it holds no external
    // bookkeeping (no LRU, no links map) for that rebuild to miss, so there is
    // nothing left for an explicit sweep to do — adding one would be redundant
    // work on every logout. Pinned by `client_review_signal_provider_test.dart`
    // and by `master_archive_review_flow_test.dart`'s session-boundary scenario,
    // which drives a real logout → login round trip.
    // Wipe the interceptor's session-lifetime token fallback so no request can
    // carry a stale Bearer token after an explicit logout.
    _lastKnownAccessToken = null;
    coldStartAccessToken = null;
    // NOTE — do NOT `ref.invalidate(...)` the master profile / service repository
    // / services list here. Each of those providers transitively
    // `ref.watch(authProvider)` (masterProfileProvider directly; serviceRepository
    // and servicesList through it), so invalidating them from INSIDE this notifier
    // records a back-edge that closes a dependency cycle — Riverpod's
    // CircularDependencyError assert (debug/test only) then throws and escapes the
    // state transition below, surfacing a false "logout failed". The cascade
    // already handles teardown: when state flips to Unauthenticated below, those
    // watchers rebuild and clear their stale PII automatically. The manual
    // invalidation was both redundant and the cause of the cycle.
    if (kDebugMode) {
      log('Logout: session cleared', name: 'auth', level: 800);
    }
    state = const AsyncData(AuthSession.unauthenticated());
  }
}
