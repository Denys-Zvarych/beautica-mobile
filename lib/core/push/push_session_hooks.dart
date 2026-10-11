// Phase 067 — auth <-> push decoupling.
//
// `PushRegistration` watches `authProvider`, so `AuthNotifier` must NEVER
// `ref.read(pushRegistrationProvider...)`: in debug builds Riverpod's
// `_debugAssertCanDependOn` throws `CircularDependencyError` (release skips the
// assert, which is how the bug hid). This coordinator inverts the edge: it has
// NO dependencies, `PushRegistration` registers its handlers here when built,
// and `AuthNotifier` only reads this provider and invokes whatever is present.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'push_session_hooks.g.dart';

/// Mutable holder of the push handlers. Handlers are bound to the (single,
/// keepAlive) `PushRegistration` notifier instance, which survives auth-driven
/// rebuilds, so they are registered idempotently and never cleared on rebuild.
final class PushSessionHooks {
  /// Logout cleanup (DELETE + deleteToken, bounded, never throws).
  Future<void> Function({required bool forced})? onLogout;

  /// Local-only revoke for non-logout auth wipes.
  Future<void> Function()? onLocalRevoke;
}

@Riverpod(keepAlive: true)
PushSessionHooks pushSessionHooks(Ref ref) => PushSessionHooks();
