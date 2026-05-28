// MEDIUM-1 fix (mobile-perf 2026-05-28): shared single-flight guard.
//
// Before this fix two independent Completer-based coalesce guards existed:
//   - HttpAuthRepository._pendingRefresh (Completer<AuthTokens>?)
//   - RefreshInterceptor._refreshing     (Completer<String>?)
//
// Both guards protected against concurrent refresh calls within each code
// path, but did NOT protect against the cross-path race where AuthNotifier
// calls repo.refresh() at cold-start while a 401 from a background request
// simultaneously triggers RefreshInterceptor._runRefresh(). In that window
// two independent refresh calls could both write to flutter_secure_storage,
// orphaning one rotation chain.
//
// Fix: a shared keepAlive provider that holds at most one in-flight
// Completer<AuthTokens>. Both paths consult this lock before starting a
// refresh. Dart's single-threaded event loop guarantees that the
// `pending != null` check and `claim()` are evaluated atomically (no async
// gap between them — both are synchronous statements).

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/domain/auth_tokens.dart';

part 'token_refresh_lock.g.dart';

/// Shared in-flight guard that prevents concurrent token refreshes across
/// both the [HttpAuthRepository.refresh] direct-call path and the
/// [RefreshInterceptor] 401-triggered path.
///
/// At most one refresh runs at a time. A second caller that arrives while a
/// refresh is already in-flight receives the same [Completer.future] and
/// awaits the single network result rather than issuing a duplicate request.
///
/// Thread-safety note: Dart is single-threaded within an isolate. The check
/// `pending != null` and the subsequent [claim] call are both synchronous, so
/// no interleaving can occur between them on the event loop.
class TokenRefreshLock {
  Completer<AuthTokens>? _pending;

  /// The in-flight completer, or `null` if no refresh is currently running.
  Completer<AuthTokens>? get pending => _pending;

  /// Claims the lock and returns a new [Completer<AuthTokens>].
  ///
  /// The caller MUST call either [complete] or [completeError] on the returned
  /// completer exactly once, and MUST call [release] in a `finally` block.
  ///
  /// Asserts that the lock is not already held (programming error if violated).
  Completer<AuthTokens> claim() {
    assert(
      _pending == null,
      'TokenRefreshLock.claim() called while already held',
    );
    _pending = Completer<AuthTokens>();
    return _pending!;
  }

  /// Releases the lock after the refresh completes (success or failure).
  ///
  /// Always call from a `finally` block to guarantee the lock is freed even
  /// when the refresh throws.
  void release() => _pending = null;
}

/// Provides the singleton [TokenRefreshLock] for the app lifetime.
///
/// [keepAlive: true] ensures the same instance is shared by every consumer
/// ([HttpAuthRepository] and [RefreshInterceptor]) without risk of disposal
/// while a refresh is in-flight.
@Riverpod(keepAlive: true)
TokenRefreshLock tokenRefreshLock(Ref ref) => TokenRefreshLock();
