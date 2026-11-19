// Phase 2.9 — AuthRefreshNotifier.
//
// Bridges [authProvider] (a Riverpod provider) to [GoRouter.refreshListenable]
// (which requires a Flutter [Listenable]). Whenever a REDIRECT-RELEVANT part
// of [authProvider] changes — loading → authenticated, authenticated →
// unauthenticated, a role / salon / account switch, the add-phone block
// lifting — this notifier calls [notifyListeners] so [GoRouter] re-evaluates
// its redirect callback and routes the user to the correct screen.
//
// M517 (2026-11-18): it no longer fires on EVERY emission. A go_router
// refresh re-parses the last reported route stack through the codec restore
// branch, which (a) nulls a non-JSON `extra`, (b) gives each restored
// imperative match a new Completer so the original `push` future never
// resolves (flutter#128122), and (c) resurrects a popped route that was not
// reported yet. Profile-only emissions (token refresh, `refreshUser`, avatar
// patch) change no redirect input, so they no longer reach the router.
// [authRouterKey] lists exactly the fields the redirects read.
//
// Lifecycle:
//   Created by [appRouterProvider] (keepAlive: true).
//   Disposed via [ref.onDispose] when the router provider is invalidated.
//   The inner [ProviderSubscription] is closed in [dispose] to prevent leaks.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/domain/auth_session.dart';
import '../features/auth/domain/user_role.dart';
import '../features/auth/presentation/auth_notifier.dart';

/// Value-compared snapshot of every [authProvider] field a router redirect
/// reads. Records have structural equality, so two keys built from sessions
/// that differ only in redirect-irrelevant fields (access token, email,
/// phone number, names, avatar, ...) are `==`.
typedef AuthRouterKey = ({
  bool isLoading,
  bool isData,
  bool authenticated,
  String? userId,
  UserRole? role,
  String? salonId,
  bool mustAddPhone,
});

/// Builds the [AuthRouterKey] for [auth].
///
/// Field sources (keep in sync with the redirect readers):
/// - `isLoading` — `auth_redirect.dart` loading hold.
/// - `isData` — `resolvedAuth` / `resolvedSession()` settle checks.
/// - `authenticated` — every signed-in / signed-out branch.
/// - `userId` — an account switch must always re-route.
/// - `role` — every role gate and inline role redirect.
/// - `salonId` — `salonManageGuard` SALON_ADMIN binding.
/// - `mustAddPhone` — the add-phone blocking step and its exit.
///
/// Values are read leniently through `.value`, the same way the guards do.
@visibleForTesting
AuthRouterKey authRouterKey(AsyncValue<AuthSession> auth) {
  final session = auth.value;
  final user = session is Authenticated ? session.user : null;
  return (
    isLoading: auth.isLoading,
    isData: auth is AsyncData<AuthSession>,
    authenticated: session is Authenticated,
    userId: user?.id,
    role: user?.role,
    salonId: user?.salonId,
    mustAddPhone: user?.mustAddPhone ?? false,
  );
}

/// [ChangeNotifier] that re-notifies whenever the [AuthRouterKey] of
/// [authProvider] changes.
///
/// Passed to [GoRouter.refreshListenable] so that auth-state transitions
/// automatically trigger a route re-evaluation without requiring any
/// screen-level code, while profile-only emissions leave the route stack
/// (and its `extra`s and pending `push` futures) untouched.
class AuthRefreshNotifier extends ChangeNotifier {
  /// Creates the notifier and subscribes to the [AuthRouterKey] of
  /// [authProvider].
  ///
  /// [ref] must outlive this notifier; [appRouterProvider] satisfies this
  /// because it is `keepAlive: true`.
  AuthRefreshNotifier(Ref ref) {
    _sub = ref.listen<AuthRouterKey>(
      authProvider.select(authRouterKey),
      (previous, next) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AuthRouterKey> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
