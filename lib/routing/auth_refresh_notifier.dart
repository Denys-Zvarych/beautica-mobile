// Phase 2.9 — AuthRefreshNotifier.
//
// Bridges [authProvider] (a Riverpod provider) to [GoRouter.refreshListenable]
// (which requires a Flutter [Listenable]). Whenever [authProvider] emits a
// new value — loading → authenticated, authenticated → unauthenticated, etc. —
// this notifier calls [notifyListeners] so [GoRouter] re-evaluates its
// redirect callback and routes the user to the correct screen.
//
// Lifecycle:
//   Created by [appRouterProvider] (keepAlive: true).
//   Disposed via [ref.onDispose] when the router provider is invalidated.
//   The inner [ProviderSubscription] is closed in [dispose] to prevent leaks.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/domain/auth_session.dart';
import '../features/auth/presentation/auth_notifier.dart';

/// [ChangeNotifier] that re-notifies whenever [authProvider] changes.
///
/// Passed to [GoRouter.refreshListenable] so that auth-state transitions
/// automatically trigger a route re-evaluation without requiring any
/// screen-level code.
class AuthRefreshNotifier extends ChangeNotifier {
  /// Creates the notifier and subscribes to [authProvider].
  ///
  /// [ref] must outlive this notifier; [appRouterProvider] satisfies this
  /// because it is `keepAlive: true`.
  AuthRefreshNotifier(Ref ref) {
    _sub = ref.listen<AsyncValue<AuthSession>>(
      authProvider,
      (previous, next) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AsyncValue<AuthSession>> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
