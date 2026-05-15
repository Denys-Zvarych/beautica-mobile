// Phase 2.2 — Stub AuthNotifier + AuthState.
//
// This file is a compile-time placeholder so that AuthInterceptor (Phase 2.2)
// can reference `authNotifierProvider` without a forward-reference error.
//
// Phase 2.4 replaces the notifier body with the real implementation:
//   - reads/writes refresh token via SecureStorageProvider
//   - calls the refresh endpoint via a separate refreshDioProvider
//   - drives the router redirect guard via GoRouter.refresh
//
// DO NOT add business logic here — any code added in this stub will be
// overwritten by Phase 2.4. The state hierarchy and class names are final
// (Phase 2.4 will extend, not rename, them).

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_notifier.g.dart';

// ---------------------------------------------------------------------------
// Auth state hierarchy
// ---------------------------------------------------------------------------

/// Top-level sealed state for the authentication lifecycle.
sealed class AuthState {
  const AuthState();
}

/// The user has no valid session (not logged in, or session was cleared).
final class Unauthenticated extends AuthState {
  const Unauthenticated();
}

/// The user is logged in and holds a valid in-memory access token.
///
/// The access token is kept in-memory only — it is NEVER written to
/// `flutter_secure_storage` or `SharedPreferences`. Only the refresh token
/// persists across app restarts (see Phase 2.4).
final class Authenticated extends AuthState {
  const Authenticated({required this.accessToken});

  /// Short-lived JWT access token. In-memory only.
  final String accessToken;
}

/// A session transition is in progress (login, logout, or refresh).
final class AuthLoading extends AuthState {
  const AuthLoading();
}

// ---------------------------------------------------------------------------
// Notifier stub (Phase 2.4 fills in the body)
// ---------------------------------------------------------------------------

/// Manages the user's authentication session.
///
/// Exposes [AsyncValue<AuthState>] so that widgets and interceptors can
/// distinguish between the initial loading phase (app boot, checking stored
/// refresh token) and the settled authenticated / unauthenticated states.
@Riverpod(keepAlive: true)
class AuthNotifier extends _$AuthNotifier {
  @override
  AsyncValue<AuthState> build() {
    // Stub: always starts as unauthenticated.
    // Phase 2.4 replaces this with a startup check of the stored refresh token.
    return const AsyncData(Unauthenticated());
  }
}
